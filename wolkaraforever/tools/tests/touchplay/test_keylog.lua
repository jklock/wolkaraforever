-- /touch keys: the key diagnostic (Keylog.lua). What the game receives for the app's Ctrl-Alt-Shift chords, kept in
-- TouchPlayDB.keylog (the last 400 lines) and printed to the chat. Off changes nothing.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, tostring(ns.lastError))
    return ns.Keylog
end

local function lastLine() local log = TouchPlayDB.keylog; return log and log[#log] end
local function hookCount(frame) return #(frame.hooks.PreClick or {}) end

local function pressKey(frame, key)
    frame:_Fire("OnKeyDown", key)
    frame:_Fire("OnKeyUp", key)
end

T("keylog_is_off_and_leaves_no_trace_until_asked", function()
    local Keylog = setup()
    assert(Keylog and not Keylog.IsOn() and Keylog.Frame() == nil)
    assert(TouchPlayKeylog == nil, "no frame is made before the first switch on")
    assert(TouchPlayDB.keylog == nil, "nothing is saved for a log never used")
    local hooks = hookCount(TouchPlaySpell1)
    SlashCmdList.TOUCHPLAY("keys help")             -- an unknown word changes nothing
    assert(hookCount(TouchPlaySpell1) == hooks and Keylog.Frame() == nil)
    assert(not Stub.allEvents.MODIFIER_STATE_CHANGED, "no modifier event is asked for")
end)

T("keylog_on_makes_a_keyboard_frame_that_passes_keys_on_and_off_takes_it_away", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    assert(Keylog.IsOn())
    local frame = Keylog.Frame()
    assert(frame and frame == TouchPlayKeylog and frame:IsShown())
    assert(frame:IsKeyboardEnabled(), "it takes keys")
    assert(frame:GetPropagateKeyboardInput(), "and passes them on to the bindings and the game")
    assert(frame.scripts.OnKeyDown and frame.scripts.OnKeyUp and frame:IsEventRegistered("MODIFIER_STATE_CHANGED"))
    assert(Stub.printed("Key log on") == 1)
    assert(TouchPlayDB.keylog[1]:find("| START", 1, true))

    SlashCmdList.TOUCHPLAY("keys")
    assert(not Keylog.IsOn() and Keylog.Frame() == nil, "off: no logger")
    assert(not frame:IsKeyboardEnabled() and not frame:IsShown(), "the frame takes no keys")
    assert(not frame.scripts.OnKeyDown and not frame.scripts.OnKeyUp and not frame.scripts.OnEvent)
    assert(not frame:IsEventRegistered("MODIFIER_STATE_CHANGED"))
    assert(Stub.printed("Key log off") == 1)
    assert(TouchPlayDB.keylog[#TouchPlayDB.keylog]:find("| STOP", 1, true), "the log keeps its lines")

    SlashCmdList.TOUCHPLAY("keys on")
    assert(Keylog.IsOn() and Keylog.Frame() == frame, "on again reuses the one frame")
    SlashCmdList.TOUCHPLAY("keys off")
    assert(not Keylog.IsOn() and Keylog.Frame() == nil)
    SlashCmdList.TOUCHPLAY("keys off")
    assert(Stub.printed("Key log off") == 2, "off when already off says nothing more")
end)

T("keylog_a_key_with_modifiers_logs_each_flag_and_the_binding", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    local frame = Keylog.Frame()
    -- the app's chord: Ctrl, Alt and Shift held (left ones), F2 bound as an override to the first spell button
    SetOverrideBindingClick(frame, false, "ALT-CTRL-SHIFT-F2", "TouchPlaySpell1", "LeftButton")
    Stub.gameBindings.F2 = "TOGGLECHARACTER0"
    Stub.hold(true, true, true)
    local before = #TouchPlayDB.keylog
    frame:_Fire("OnKeyDown", "F2")
    assert(#TouchPlayDB.keylog == before + 1)
    local line = lastLine()
    assert(line:match("^%d+%.%d%d%d | KD | F2 | mod=CAS | L=CAS | R=%-%-%- | bind=TOGGLECHARACTER0 | ovr=CLICK"), line)
    assert(line:find("| ovr=CLICK TouchPlaySpell1:LeftButton", 1, true), "the game's ALT-CTRL-SHIFT- order finds the override: " .. line)
    assert(line:find("| ovr2=-", 1, true), "the old CTRL-ALT-SHIFT- order finds nothing: " .. line)
    assert(Stub.printed("KD F2 mod=CAS bind=TOGGLECHARACTER0") == 1, "the chat gets the short form")
    assert(not Stub.chat[#Stub.chat]:find(" | ", 1, true) and not Stub.chat[#Stub.chat]:find("L=", 1, true))

    -- the bare key with nothing held
    Stub.hold(false, false, false)
    frame:_Fire("OnKeyUp", "F2")
    line = lastLine()
    assert(line:find("| KU | F2 | mod=--- | L=--- | R=--- | bind=TOGGLECHARACTER0 | ovr=TOGGLECHARACTER0 | ovr2=TOGGLECHARACTER0 ", 1, true)
        or line:find("| KU | F2 | mod=--- | L=--- | R=--- | bind=TOGGLECHARACTER0 | ovr=TOGGLECHARACTER0 | ovr2=TOGGLECHARACTER0", 1, true), line)

    -- Control alone, and the right-hand Shift
    Stub.hold(false, true, false)
    frame:_Fire("OnKeyDown", "F5")
    assert(lastLine():find("| KD | F5 | mod=C-- | L=C-- | R=--- | bind=- | ovr=- | ovr2=-", 1, true), lastLine())
    Stub.hold(false, false, true); Stub.rightHeld.shift = true
    frame:_Fire("OnKeyDown", "F5")
    assert(lastLine():find("| mod=--S | L=--- | R=--S |", 1, true), lastLine())
end)

T("keylog_a_game_that_lacks_a_function_shows_a_question_mark", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    IsLeftControlKeyDown, GetBindingAction = nil, nil
    Stub.hold(false, true, false)
    Keylog.Frame():_Fire("OnKeyDown", "F3")
    assert(lastLine():find("| mod=C-- | L=?-- | R=--- | bind=? | ovr=? | ovr2=?", 1, true), lastLine())
end)

T("keylog_modifier_keys_and_the_modifier_event", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    local frame = Keylog.Frame()
    Stub.hold(false, true, false)
    frame:_Fire("OnKeyDown", "LCTRL")
    assert(lastLine():find("| KD | LCTRL | mod=C-- | L=C-- | R=--- | bind=- | ovr=- | ovr2=-", 1, true), lastLine())
    Stub.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    assert(lastLine():find("| MODSTATE | LCTRL | down=1 | mod=C-- | L=C-- | R=--- ", 1, true)
        or lastLine():find("| MODSTATE | LCTRL | down=1 | mod=C-- | L=C-- | R=---", 1, true), lastLine())
    assert(Stub.printed("MODSTATE LCTRL down=1 mod=C--") == 1)
    Stub.hold(false, false, false)
    Stub.fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
    assert(lastLine():find("| MODSTATE | LCTRL | down=0 | mod=---", 1, true), lastLine())
end)

T("keylog_button_clicks_are_logged_through_a_hook_that_stops_when_off", function()
    local Keylog = setup()
    local baseline = hookCount(TouchPlaySpell1)
    SlashCmdList.TOUCHPLAY("keys")
    Stub.hold(true, true, true)
    local names = { "TouchPlaySpell1", "TouchPlaySpell7", "TouchPlayItem1", "TouchPlayBags", "TouchPlayMenu",
        "TouchPlayNextTarget", "TouchPlayPage1" }
    for _, name in ipairs(names) do
        assert(_G[name], name .. " exists")
        Stub.click(_G[name], "LeftButton", true)
        assert(lastLine():find("| CLICK | " .. name .. " | LeftButton | down=1 | mod=CAS", 1, true), name .. ": " .. tostring(lastLine()))
    end
    Stub.hold(false, false, false)
    Stub.click(TouchPlayBags, "RightButton", false)
    assert(lastLine():find("| CLICK | TouchPlayBags | RightButton | down=0 | mod=---", 1, true), lastLine())
    assert(Stub.printed("CLICK TouchPlayBags RightButton down=0 mod=---") == 1)

    -- on, off, on again: one hook per button, and it does nothing while off
    assert(hookCount(TouchPlaySpell1) == baseline + 1)
    SlashCmdList.TOUCHPLAY("keys off")
    local n = #TouchPlayDB.keylog
    Stub.click(TouchPlayBags, "LeftButton", true)
    Stub.click(TouchPlaySpell1, "LeftButton", false)
    assert(#TouchPlayDB.keylog == n, "off: a click adds no line")
    SlashCmdList.TOUCHPLAY("keys")
    assert(hookCount(TouchPlaySpell1) == baseline + 1, "no second hook")
end)

T("keylog_keeps_the_last_400_lines", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    local frame = Keylog.Frame()
    for i = 1, 450 do frame:_Fire("OnKeyDown", "K" .. i) end
    local log = TouchPlayDB.keylog
    assert(#log == 400, #log)
    assert(log[#log]:find("| KD | K450 |", 1, true))
    assert(log[1]:find("| KD | K51 |", 1, true), "the oldest 51 lines (the START and K1 to K50) went: " .. log[1])
    -- a saved log longer than the cap shrinks at the next line
    for i = 1, 30 do log[#log + 1] = "extra " .. i end
    frame:_Fire("OnKeyDown", "LAST")
    assert(#TouchPlayDB.keylog == 400 and lastLine():find("| LAST |", 1, true))
end)

T("keylog_clear_empties_the_log", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    Keylog.Frame():_Fire("OnKeyDown", "F2")
    assert(#TouchPlayDB.keylog == 2)
    SlashCmdList.TOUCHPLAY("keys clear")
    assert(TouchPlayDB.keylog == nil and Keylog.IsOn(), "cleared, and still logging")
    assert(Stub.printed("Key log cleared") == 1)
    Keylog.Frame():_Fire("OnKeyDown", "F3")
    assert(#TouchPlayDB.keylog == 1)
end)

T("keylog_the_log_survives_a_reload_and_logging_does_not", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    Keylog.Frame():_Fire("OnKeyDown", "F2")
    Stub.reload()
    assert(#TouchPlayDB.keylog == 2, "the lines are read from the saved variables after a /reload")
    assert(not ns.Keylog.IsOn() and ns.Keylog.Frame() == nil)
end)

-- iPad run 6: "Touch: MODSTATE ..." lines in the chat came from the logger switched on by hand. It must never come back
-- by itself: after a /reload, or a logout and a new login, it is off and prints nothing, and no saved switch exists.
T("keylog_is_off_after_a_reload_or_a_relog_and_saves_no_switch", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    assert(Keylog.IsOn())
    Stub.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    assert(Stub.printed("MODSTATE LSHIFT down=1") == 1, "on: the modifier lines print")
    -- nothing in the saved variables remembers the switch (only the lines are kept)
    for _, db in ipairs({ TouchPlayDB or {}, TouchPlayCharDB or {} }) do
        for key, value in pairs(db) do
            local name = tostring(key):lower()
            if name:find("keylog") or name:find("keys") then
                assert(key == "keylog" and type(value) == "table", "only the log lines are saved, not " .. tostring(key))
            end
        end
    end
    for _, how in ipairs({ "reload", "relog" }) do
        if how == "relog" then
            SlashCmdList.TOUCHPLAY("keys")                       -- on again, then log out and back in
            if not ns.Keylog.IsOn() then SlashCmdList.TOUCHPLAY("keys") end
            assert(ns.Keylog.IsOn())
            Stub.fire("PLAYER_LOGOUT")
        end
        Stub.reload()
        assert(not ns.Keylog.IsOn() and ns.Keylog.Frame() == nil, how .. ": the logger is off")
        local before = Stub.printed("MODSTATE")
        Stub.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
        assert(Stub.printed("MODSTATE") == before, how .. ": nothing prints for a modifier")
        assert(not Stub.allEvents.MODIFIER_STATE_CHANGED, how .. ": the modifier event is not asked for")
    end
end)

T("keylog_switching_on_waits_for_the_end_of_a_fight_and_off_stops_at_once", function()
    local Keylog = setup()
    Stub.combat(true)
    SlashCmdList.TOUCHPLAY("keys")
    assert(not Keylog.IsOn() and Keylog.Frame() == nil)
    assert(Stub.printed("out of a fight") == 1)
    Stub.combat(false)
    SlashCmdList.TOUCHPLAY("keys")
    local frame = Keylog.Frame()
    assert(Keylog.IsOn() and frame)

    Stub.combat(true)
    SlashCmdList.TOUCHPLAY("keys off")
    assert(not Keylog.IsOn(), "off at once")
    local n = #TouchPlayDB.keylog
    frame:_Fire("OnKeyDown", "F2"); Stub.click(TouchPlayBags, "LeftButton", true)
    assert(#TouchPlayDB.keylog == n, "nothing is logged any more")
    assert(Keylog.Frame() == frame and frame:IsKeyboardEnabled(), "the frame itself is given up after the fight")
    Stub.combat(false)
    Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Keylog.Frame() == nil and not frame:IsKeyboardEnabled() and not frame.scripts.OnKeyDown)
end)

T("keylog_on_again_before_a_fights_end_keeps_the_logger", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    local frame = Keylog.Frame()
    Stub.combat(true)
    SlashCmdList.TOUCHPLAY("keys off")            -- the teardown waits
    Stub.combat(false)
    SlashCmdList.TOUCHPLAY("keys on")             -- on before the end-of-fight event reaches the queue
    assert(Keylog.IsOn() and Keylog.Frame() == frame)
    Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Keylog.IsOn() and Keylog.Frame() == frame and frame:IsKeyboardEnabled() and frame.scripts.OnKeyDown,
        "the queued teardown leaves a logger that is on")
end)

T("keylog_a_failing_function_is_remembered_and_does_not_stop_the_key", function()
    local Keylog = setup()
    SlashCmdList.TOUCHPLAY("keys")
    GetTime = function() error("boom") end
    Keylog.Frame():_Fire("OnKeyDown", "F2")
    GetTime = function() return Stub.now end
    assert(not ns.paused, "a diagnostic never pauses the add-on")
    assert(TouchPlayDB.errors and TouchPlayDB.errors[1].text:find("Keylog: ", 1, true) and TouchPlayDB.errors[1].text:find("boom"))
end)

T("keylog_slash_words", function()
    setup()
    SlashCmdList.TOUCHPLAY("keys bogus")
    assert(Stub.printed("Use /touch keys") == 1 and not ns.Keylog.IsOn())
    SlashCmdList.TOUCHPLAY("KEYS ON")
    assert(ns.Keylog.IsOn())
    SlashCmdList.TOUCHPLAY("keys list")
    assert(Stub.printed("Touch areas and their keys") == 1, "the area list moved to /touch keys list")
    assert(ns.Keylog.IsOn(), "list leaves the log as it is")
end)

T("keylog_toc_order_and_no_onupdate", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then order[#order + 1] = line end
    end
    local keylog
    for i, name in ipairs(order) do if name == "Keylog.lua" then keylog = i end end
    assert(keylog and keylog < #order and order[#order] == "Contract.lua", "Keylog.lua is listed, before Contract.lua")
end)

Stub.done("keylog")
