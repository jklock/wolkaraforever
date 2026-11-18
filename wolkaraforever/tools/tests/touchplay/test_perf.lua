-- Task 15: the animation clock, /touch perf, the pause card (mockup 91), a login in a fight, a login that is already Off.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, tostring(ns.lastError))
    return ns.Perf
end

local function plain()
    local f = CreateFrame("Frame", nil, UIParent)
    return f
end

local function near(a, b) return math.abs(a - b) < 0.011 end

local function printedMatching(pattern)
    for _, line in ipairs(Stub.chat) do
        if type(line) == "string" and line:find(pattern) then return line end
    end
end

local function boundKeys()
    local list = {}
    for key in pairs(Stub.bindings) do list[#list + 1] = key end
    table.sort(list)
    return table.concat(list, ",")
end

-- ---------------------------------------------------------------------------------------
-- The animation clock

T("animate_fades_in_and_removes_its_onupdate", function()
    setup()
    local f = plain(); f:SetAlpha(0)
    assert(#Stub.onUpdateFrames() == 0, "nothing runs before an animation")
    ns.Animate(f, "fadein", 0.2)
    assert(ns.Animating() == 1 and #Stub.onUpdateFrames() == 1, "one clock for it")
    Stub.advance(0.1); assert(near(f:GetAlpha(), 0.5), f:GetAlpha())
    Stub.advance(0.2); assert(f:GetAlpha() == 1, f:GetAlpha())
    assert(ns.Animating() == 0 and #Stub.onUpdateFrames() == 0, "the clock removed itself")
end)

T("animate_fadeout_hides_and_resets_alpha", function()
    setup()
    local f = plain(); f:Show()
    ns.Animate(f, "fadeout", 0.2)
    Stub.advance(0.1); assert(near(f:GetAlpha(), 0.5) and f:IsShown())
    Stub.advance(0.2)
    assert(not f:IsShown() and f:GetAlpha() == 1, "hidden, and shown again later at full strength")
    assert(#Stub.onUpdateFrames() == 0)
end)

T("animate_fadeto_goes_to_the_given_alpha", function()
    setup()
    local f = plain()
    ns.Animate(f, "fadeto", 0.4, 0.25)
    Stub.advance(0.5); assert(f:GetAlpha() == 0.25 and f:IsShown(), f:GetAlpha())
    assert(#Stub.onUpdateFrames() == 0)
end)

T("animate_many_frames_one_clock", function()
    setup()
    local a, b = plain(), plain(); a:SetAlpha(0); b:SetAlpha(0)
    ns.Animate(a, "fadein", 0.2); ns.Animate(b, "fadein", 0.4)
    assert(ns.Animating() == 2 and #Stub.onUpdateFrames() == 1, "one OnUpdate however many animate")
    Stub.advance(0.25); assert(a:GetAlpha() == 1 and near(b:GetAlpha(), 0.625) and #Stub.onUpdateFrames() == 1)
    Stub.advance(0.25); assert(b:GetAlpha() == 1 and #Stub.onUpdateFrames() == 0)
end)

T("animate_same_frame_replaces_and_cancel_stops", function()
    setup()
    local f = plain(); f:SetAlpha(0)
    ns.Animate(f, "fadein", 0.2); ns.Animate(f, "fadein", 0.2)
    assert(ns.Animating() == 1, "the second call replaces the first")
    Stub.advance(0.1)
    local half = f:GetAlpha()
    ns.Animate.Cancel(f)
    assert(ns.Animating() == 0 and #Stub.onUpdateFrames() == 0)
    Stub.advance(1); assert(f:GetAlpha() == half, "cancelled where it was")
    ns.Animate.Cancel(f)           -- nothing to cancel: no error
end)

T("animate_reduce_motion_is_instant", function()
    setup()
    TouchPlayDB.feel = { reduceMotion = true }
    local f = plain(); f:SetAlpha(0)
    ns.Animate(f, "fadein", 0.2)
    assert(f:GetAlpha() == 1 and ns.Animating() == 0 and #Stub.onUpdateFrames() == 0, "no clock at all")
    ns.Animate(f, "fadeout", 0.2); assert(not f:IsShown() and f:GetAlpha() == 1)
    local g = plain(); ns.Animate(g, "fadeto", 0.4, 0.25); assert(g:GetAlpha() == 0.25)
    assert(#Stub.onUpdateFrames() == 0)
end)

T("animate_a_secure_frame_in_a_fight_does_not_raise", function()
    setup()
    local secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    Stub.combat(true)
    ns.Animate(secure, "fadeout", 0.2)
    Stub.advance(0.5)
    assert(not ns.paused, tostring(ns.lastError))
    assert(#Stub.onUpdateFrames() == 0)
end)

T("animate_an_onhide_that_animates_again_does_not_share_a_record", function()
    setup()
    local f = plain(); f:SetAlpha(1)
    f:SetScript("OnHide", function() ns.Animate(f, "fadein", 0.4) end)
    ns.Animate(f, "fadeout", 0.1)
    Stub.advance(0.15)            -- the fade-out ends, Hide runs, OnHide starts a fade-in on the same frame
    assert(ns.Animating() == 1 and f:IsShown(), "one animation: the new fade-in")
    local g = plain(); g:SetAlpha(0)
    ns.Animate(g, "fadein", 0.4)
    assert(ns.Animating() == 2, "a second record of its own")
    local before = f:GetAlpha()
    Stub.advance(0.1)
    assert(near(f:GetAlpha(), before + 0.25) and near(g:GetAlpha(), 0.25),
        ("independent progress: f %.2f (was %.2f), g %.2f"):format(f:GetAlpha(), before, g:GetAlpha()))
    Stub.advance(1); assert(f:GetAlpha() == 1 and g:GetAlpha() == 1 and ns.Animating() == 0)
    assert(#Stub.onUpdateFrames() == 0)
end)

T("animate_unknown_kind_is_an_error", function()
    setup()
    assert(not pcall(ns.Animate, plain(), "spin", 1))
end)

T("chat_fade_uses_the_clock_and_ends_idle", function()
    setup()
    local Chat = ns.Chat
    Chat.Clear()
    DEFAULT_CHAT_FRAME:AddMessage("hello", 1, 1, 0)
    assert(#Stub.onUpdateFrames() == 0, "waiting for the 20 s is a timer, not an OnUpdate")
    Stub.advance(19.9); Stub.advance(0.2)
    local mid = Chat.lines:GetAlpha()
    assert(mid < 1 and mid > 0.25 and ns.Animating() == 1, "fading, not jumping: " .. mid)
    DEFAULT_CHAT_FRAME:AddMessage("again", 1, 1, 0)
    assert(Chat.lines:GetAlpha() == 1 and ns.Animating() == 0, "a new line stops the fade and brings the lines back")
    Stub.advance(21); Stub.advance(1)
    assert(Chat.lines:GetAlpha() == 0.25 and #Stub.onUpdateFrames() == 0, "faded, and idle again")
end)

-- ---------------------------------------------------------------------------------------
-- The idle rules

T("no_onupdate_when_idle", function()
    setup()
    local function define()
        StaticPopupDialogs.TIMED = { text = "%s wants to resurrect you.", button1 = "Accept", button2 = "Decline",
            timeout = 60, OnAccept = function() end }
    end
    define()
    assert(#Stub.onUpdateFrames() == 0, "a quiet screen has no OnUpdate")
    local d = StaticPopup_Show("TIMED", "Tarek")
    d.timeleft = 50
    Stub.advance(0.5)
    local running = Stub.onUpdateFrames()
    assert(#running <= 1, "only the popup's time bar may run: " .. #running)
    StaticPopup_Hide("TIMED")
    Stub.advance(1)
    local f = plain(); f:SetAlpha(0); ns.Animate(f, "fadein", 0.3); Stub.advance(1)
    Stub.advance(30)
    local left = Stub.onUpdateFrames()
    local names = {}
    for i, frame in ipairs(left) do names[i] = tostring(frame.name) end
    assert(#left == 0, "after every popup closes and every animation ends nothing has an OnUpdate: " .. table.concat(names, ","))
end)

-- Allocation per event: the frames' own OnEvent scripts are called straight (so what is measured is the add-on, not
-- the stub's copy of the listener list). The least growth of three rounds after a warm-up: a real allocation in a
-- handler shows in every round; LuaJIT's own noise does not. Health and power change between fires, for the player and
-- the target, so a handler that only allocates when a value really changed is caught too.
local function growthOf(event, units)
    local frames, scripts = Stub.eventFrames(event), {}
    for i, f in ipairs(frames) do scripts[i] = f.scripts.OnEvent end
    local tick = 0
    local function fire()
        tick = tick + 1
        local player, target = Stub.units.player, Stub.units.target
        player.health, player.power = 1000 + tick % 400, 10 + tick % 80
        if target then target.health, target.power = 500 + tick % 300, 5 + tick % 50 end
        for u = 1, #units do
            for i = 1, #frames do scripts[i](frames[i], event, units[u]) end
        end
    end
    for _ = 1, 300 do fire() end
    local least
    for _ = 1, 3 do
        collectgarbage("collect"); collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do fire() end
        local grew = collectgarbage("count") - before
        collectgarbage("restart")
        if not least or grew < least then least = grew end
    end
    return least, #frames
end

T("no_tables_per_event", function()
    setup(); Stub.setTarget("enemy")
    local _, listeners = growthOf("UNIT_HEALTH", { "player" })
    assert(listeners >= 3, "the unit cards, the item glow and the screen edge listen: " .. listeners)
    local both = { "player", "target" }
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_START", "UNIT_AURA" }) do
        local grew = growthOf(event, both)
        assert(grew < 4, ("1000 %s events grew memory by %.1f KB"):format(event, grew))
    end
end)

-- ---------------------------------------------------------------------------------------
-- /touch perf

T("perf_within_budget", function()
    setup()
    Stub.profiler = { recent = 0.12, peak = 0.8 }
    SlashCmdList.TOUCHPLAY("perf")
    local line = printedMatching("0%.12")
    assert(line, "the recent average is printed")
    assert(line:find("0%.80"), "and the peak: " .. line)
    assert(line:find("within budget"), line)
    assert(TouchPlayDB.enabled == true, "perf does not switch Touch off")
end)

T("perf_over_budget", function()
    setup()
    Stub.profiler = { recent = 0.7, peak = 3.2 }
    SlashCmdList.TOUCHPLAY("perf")
    local line = printedMatching("0%.70")
    assert(line and line:find("over budget") and not line:find("within budget"), tostring(line))
    Stub.chat = {}
    Stub.profiler = { recent = 0.5, peak = 0.5 }
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("over budget"), "exactly 0.5 ms is not under budget")
    Stub.chat = {}
    Stub.profiler = { recent = 0.499, peak = 0.6 }
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("within budget"))
end)

T("perf_not_available", function()
    setup()
    Stub.profiler = nil
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("not available in this client"), "profiler off")
    Stub.chat = {}
    C_AddOnProfiler = nil
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("not available in this client"), "no profiler API")
    Stub.chat = {}
    C_AddOnProfiler = {}; Enum.AddOnProfilerMetric = nil
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("not available in this client"), "no metric enum")
    assert(not ns.paused)
end)

T("perf_hidden_numbers_are_not_available_not_an_error", function()
    setup()
    Stub.profiler = { recent = Stub.secret(), peak = 1 }
    SlashCmdList.TOUCHPLAY("perf")
    assert(printedMatching("not available in this client") and not ns.paused)
end)

-- ---------------------------------------------------------------------------------------
-- The pause card (mockup 91)

local TITLE = "Touch buttons are paused"
local SLOW = "The game switched off the touch add-on because it was running slowly. "
    .. "Your normal bars are back, so you can still play with the walk stick, Jump and Interact."

local function card() return ns.Perf.card end

T("pause_card_shows_once_and_restores_bars", function()
    Stub.reset(); Stub.loadAll()
    _G.ChatFrame1:SetAlpha(0.6)
    Stub.login()
    assert(not card():IsShown(), "no card while Touch runs")
    assert(_G.ChatFrame1:GetAlpha() == 0)
    ns.Pause("test")
    assert(card():IsShown() and ns.Perf.CardTitle() == TITLE, tostring(ns.Perf.CardTitle()))
    assert(_G.ChatFrame1:GetAlpha() == 0.6, "the game's own bars are back")
    assert(Stub.printed("Touch screen paused, tap to report") == 1)
    ns.Pause("again"); ns.Pause("and again")
    assert(Stub.printed("Touch screen paused, tap to report") == 1, "the chat line once")
    ns.Perf.notNow:_Fire("OnClick", "LeftButton")
    assert(not card():IsShown(), "Not now closes it")
    ns.Pause("a third time")
    assert(not card():IsShown(), "shown once per pause")
end)

T("pause_card_comes_again_for_a_new_pause", function()
    setup()
    ns.Pause("first"); ns.Perf.notNow:_Fire("OnClick", "LeftButton")
    ns.SetEnabled(true)
    assert(not ns.paused and not card():IsShown())
    ns.Pause("second")
    assert(card():IsShown(), "a pause after turning it back on shows the card again")
end)

T("pause_keeps_interact_and_jump_faces", function()
    setup()
    assert(ns.root:IsShown())
    ns.Pause("test")
    assert(not ns.root:IsShown(), "the touch screen is hidden")
    assert(ns.moveRoot:IsShown(), "the move root stays")
    assert(ns.Interact.interact:IsVisible() and ns.Interact.jump:IsVisible(), "Interact and Jump faces stay")
    assert(card():GetParent() == ns.moveRoot and card():IsVisible(), "the card lives on the root a pause never hides")
    local keys = boundKeys()
    for _, name in ipairs({ "interact", "jump" }) do
        local tap, _, press = ns.Contract.KeysFor(name)
        assert(Stub.bindings[tap or press], name .. " still bound")
    end
    assert(Stub.bindings["F12"], "bare F12 stays for the chat key")
end)

T("pause_card_text_for_each_reason", function()
    setup()
    ns.Pause("x", "game")
    assert(ns.Perf.CardText() == SLOW, tostring(ns.Perf.CardText()))
    ns.SetEnabled(true); ns.Perf.Hide()
    ns.Pause("InfoCard.Init")
    local text = ns.Perf.CardText()
    assert(text:find("Touch buttons hit a problem and stopped", 1, true), text)
    assert(text:find("Your normal bars are back, so you can still play with the walk stick, Jump and Interact.", 1, true), text)
    assert(not text:find("\226\128\148"), "no em dash")
end)

T("pause_card_turn_back_on_enables_and_reloads_by_secure_macro", function()
    setup()
    SlashCmdList.TOUCHPLAY("")                          -- switched off
    ns.Pause("x", "game")
    local b = ns.Perf.reloadButton
    assert(Stub.inherits(b, "SecureActionButtonTemplate"))
    assert(b:GetAttribute("type") == "macro" and b:GetAttribute("macrotext") == "/reload")
    assert(ns.Perf.turnOn.label:GetText() == "Turn touch back on" and ns.Perf.notNow.label:GetText() == "Not now")
    assert(Stub.calls.ReloadUI == 0)
    Stub.combat(true)                                   -- also works in a fight: the reload is secure
    Stub.click(b)
    assert(Stub.calls.ReloadUI == 1 and Stub.lastMacro == "/reload")
    assert(TouchPlayDB.enabled == true, "switched on again for the next load")
    assert(Stub.enabledAddOns[1] == "TouchPlay", "the game's list says enabled")
end)

-- The buttons hold the secure /reload, so the game protects them: a pause in a fight shows the words at once and
-- the buttons when the fight ends.
T("pause_in_a_fight_shows_the_words_now_and_the_buttons_after_it", function()
    Stub.reset(); Stub.loadAll(); _G.ChatFrame1:SetAlpha(0.6); Stub.login()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    assert(card():IsProtected(), "the buttons frame holds the secure reload")
    ns.Pause("fight")
    assert(not ns.lastError or not ns.lastError:find("BLOCKED"), tostring(ns.lastError))
    assert(ns.Perf.panel:IsShown() and ns.Perf.CardText():find("hit a problem", 1, true), "the words show in the fight")
    assert(not card():IsShown(), "the protected buttons wait")
    assert(_G.ChatFrame1:GetAlpha() == 0, "the bars wait for the end of the fight (a game rule)")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(_G.ChatFrame1:GetAlpha() == 0.6 and not ns.root:IsShown())
    assert(ns.Perf.panel:IsShown() and card():IsShown(), "the buttons come when the fight ends")
    -- Not now in a fight: the words go at once, the buttons when it ends
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    Stub.click(ns.Perf.notNow)
    assert(not ns.Perf.panel:IsShown() and not (ns.lastError or ""):find("BLOCKED"), tostring(ns.lastError))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not card():IsShown())
end)

T("forbidden_action_for_us_pauses_with_the_plain_wording", function()
    setup()
    Stub.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddOn", "CastSpell()")
    assert(not ns.paused and not card():IsShown(), "another add-on's trouble is not ours")
    Stub.fire("ADDON_ACTION_FORBIDDEN", "TouchPlay", "CastSpell()")
    assert(ns.paused and card():IsShown())
    assert(ns.Perf.CardText():find("Touch buttons hit a problem and stopped.", 1, true), "an honest wording, not 'running slowly'")
    assert(not ns.Perf.CardText():find("slowly", 1, true))
    assert(ns.lastError and ns.lastError:find("CastSpell"), tostring(ns.lastError))
end)

-- The game's performance check is a static popup (Blizzard_AddOnPerformance): "Disable" / "Ignore" for the add-on it names
local function definePerformancePopup()
    StaticPopupDialogs.ADDON_PERFORMANCE_SPECIFIC_ERROR = { text = "%s is using a lot of memory or time.",
        button1 = "Disable", button2 = "Ignore", timeout = 0,
        OnAccept = function(_, data) C_AddOns.DisableAddOn(data); ReloadUI() end }
end

-- R39: the popup does not pause us. Only our words show beside it (no buttons); the player decides there.
T("the_games_performance_popup_for_us_shows_only_our_words_and_never_pauses", function()
    setup(); definePerformancePopup()
    local d = StaticPopup_Show("ADDON_PERFORMANCE_SPECIFIC_ERROR", "TouchPlay", nil, "TouchPlay")
    assert(d and d:IsShown(), "the game's popup is up")
    assert(not ns.paused and ns.IsActive() and ns.root:IsShown(), "Touch keeps running")
    assert(ns.Perf.panel:IsShown() and ns.Perf.CardText() == ns.L["perf.popup.text"], tostring(ns.Perf.CardText()))
    assert(ns.Perf.CardTitle() == "Touch is running slowly")
    assert(not card():IsShown(), "no Turn touch back on / Not now: nothing is paused")
    assert(d:IsShown() and d.which == "ADDON_PERFORMANCE_SPECIFIC_ERROR", "never hidden by us")
    assert(d:GetButton(1):IsEnabled() and d:GetButton(2):IsEnabled(), "its buttons are as the game left them")
    assert(Stub.calls.ReloadUI == 0 and #Stub.enabledAddOns == 0, "nothing pressed for the player")
    -- Ignore: the popup hides, our words go, Touch is still on
    Stub.click(d:GetButton(2))
    assert(not d:IsShown() and not ns.Perf.panel:IsShown() and not ns.Perf.IsExplaining())
    assert(not ns.paused and ns.IsActive() and Stub.bindings[ns.Contract.WORLD_KEY], "still active, keys still bound")
end)

T("the_games_performance_popup_in_a_fight_shows_the_words_too", function()
    setup(); definePerformancePopup()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    local d = StaticPopup_Show("ADDON_PERFORMANCE_SPECIFIC_ERROR", "TouchPlay", nil, "TouchPlay")
    assert(ns.Perf.panel:IsShown() and not ns.paused, tostring(ns.lastError))
    StaticPopup_Hide("ADDON_PERFORMANCE_SPECIFIC_ERROR")
    assert(not ns.Perf.panel:IsShown() and not ns.paused, tostring(ns.lastError))
end)

T("the_games_performance_popup_for_another_addon_is_not_ours", function()
    setup(); definePerformancePopup()
    StaticPopup_Show("ADDON_PERFORMANCE_SPECIFIC_ERROR", "Bartender4", nil, "Bartender4")
    assert(not ns.paused and not card():IsShown())
    StaticPopup_Hide("ADDON_PERFORMANCE_SPECIFIC_ERROR")
    StaticPopupDialogs.OTHER = { text = "%s", button1 = "Okay" }
    StaticPopup_Show("OTHER", "TouchPlay", nil, "TouchPlay")
    assert(not ns.paused, "only the performance popup counts")
end)

T("the_games_performance_popup_while_off_or_paused_changes_nothing", function()
    setup(); definePerformancePopup()
    SlashCmdList.TOUCHPLAY("")
    StaticPopup_Show("ADDON_PERFORMANCE_SPECIFIC_ERROR", "TouchPlay", nil, "TouchPlay")
    assert(not card():IsShown(), "Touch is off: there is nothing to pause")
end)

T("blocked_action_is_remembered_not_paused", function()
    setup()
    Stub.fire("ADDON_ACTION_BLOCKED", "TouchPlay", "Frame:SetPoint()")
    assert(not ns.paused, "blocked in a fight is the add-on's own queue to fix, not a reason to stop")
    assert(TouchPlayDB.errors and TouchPlayDB.errors[1].text:find("SetPoint"), "kept for the Mac to read")
end)

T("login_off_shows_no_card", function()
    Stub.reset(); TouchPlayDB = { enabled = false }
    Stub.loadAll(); Stub.login()
    assert(not card():IsShown() and not ns.paused)
    assert(not ns.root:IsShown() and ns.moveRoot:IsShown())
end)

T("no_was_running_or_login_disabled_state_is_kept", function()
    setup()
    assert(TouchPlayDB.wasRunning == nil, "dropped by ruling R36: a disabled add-on cannot run to show a card")
    assert(ns.Perf.GameDisabled == nil)
end)

-- ---------------------------------------------------------------------------------------
-- R11: already Off at login keeps the movement keys and bare F12, exactly as switching Off in a session

T("off_at_login_binds_the_same_keys_as_off_in_a_session", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    SlashCmdList.TOUCHPLAY("")
    local inSession = boundKeys()
    assert(inSession ~= "" and Stub.bindings["F12"], "something stays bound")

    Stub.reset(); TouchPlayDB = { enabled = false }
    Stub.loadAll(); Stub.login()
    assert(boundKeys() == inSession, "at login:\n" .. boundKeys() .. "\nin a session:\n" .. inSession)
    local _, _, jump = ns.Contract.KeysFor("jump")
    local interact = ns.Contract.KeysFor("interact")
    local _, _, dive = ns.Contract.KeysFor("dive")
    assert(Stub.bindings[jump] and Stub.bindings[interact] and Stub.bindings[dive], "jump, interact and dive")
    assert(Stub.bindings["F12"] and Stub.bindings["F12"].command == "OPENCHAT", "bare F12")
    assert(not Stub.bindings[ns.Contract.WORLD_KEY] and not Stub.bindings[ns.Contract.KeysFor("spell1")], "nothing else")
end)

T("off_at_login_in_a_fight_binds_after_it", function()
    Stub.reset(); TouchPlayDB = { enabled = false }
    Stub.loadAll(); Stub.combat(true); Stub.login()
    assert(next(Stub.bindings) == nil, "the game refuses binding changes in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.bindings["F12"] and not ns.paused)
end)

T("switching_off_survives_a_failing_contract_pause", function()
    setup()
    ns.Contract.OnPause = function() error("boom") end
    SlashCmdList.TOUCHPLAY("")
    assert(TouchPlayDB.enabled == false and not ns.root:IsShown(), "off all the same")
    assert(ns.lastError and ns.lastError:find("Contract.OnPause"), tostring(ns.lastError))
end)

-- ---------------------------------------------------------------------------------------
-- A login in a fight

T("login_in_a_fight_waits_and_then_works", function()
    Stub.reset(); Stub.loadAll(); Stub.combat(true); Stub.login()
    assert(not ns.paused, "no block, no pause: " .. tostring(ns.lastError))
    assert(not card():IsShown())
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused and ns.IsActive(), tostring(ns.lastError))
    assert(ns.root:IsShown())
    local secure = ns.InfoCard.secureButton
    for _, key in ipairs({ "type", "unit", "macrotext", "item", "clickbutton" }) do
        assert(secure:GetAttribute(key) == nil, "the card's secure button got no action while loading: " .. key)
    end
    assert(Stub.bindings[ns.Contract.WORLD_KEY], "the keys are bound after the fight")
    assert(TouchPlayDB.errors == nil or #TouchPlayDB.errors == 0, "nothing was blocked")
end)

-- The words beside the game's performance popup must never cover its Disable and Ignore: they hang under the popup,
-- take no touch, and sit no higher than its strata (the popup is DIALOG, at the top of the screen).
T("the_words_beside_the_performance_popup_leave_its_buttons_free", function()
    setup(); definePerformancePopup()
    local d = StaticPopup_Show("ADDON_PERFORMANCE_SPECIFIC_ERROR", "TouchPlay", nil, "TouchPlay")
    local words = ns.Perf.panel
    assert(words:IsShown() and not words:IsMouseEnabled(), "no touch on the words")
    local order = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    assert(order[words:GetFrameStrata()] <= order[d:GetFrameStrata()], words:GetFrameStrata())
    local point, rel, relPoint, _, y = words:GetPoint(1)
    assert(point == "TOP" and rel == d and relPoint == "BOTTOM" and y < 0, "under the popup's bottom edge")
    -- the pause card itself is back in its own place when a real pause comes
    Stub.click(d:GetButton(2))
    ns.Pause("x")
    assert(words:IsMouseEnabled() and words:GetFrameStrata() == "FULLSCREEN_DIALOG" and words.touchAnchor.y == 147)
    point, rel = words:GetPoint(1)
    assert(rel == ns.moveRoot, "anchored in the layout again")
end)

Stub.done("perf")
