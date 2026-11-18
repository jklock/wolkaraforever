-- Ruling A24: the in-world signal. A hidden password edit box takes focus briefly so the host sees secure
-- event input switch on and off: one pulse entering the world (1 s after PLAYER_ENTERING_WORLD, ruling A27),
-- two leaving it (at once), three while a window is open in the world (ruling A32).
dofile("tests/stub.lua")

-- Game windows a test made (by name): the stub keeps globals across sessions, so each session starts without them.
local madeWindows = {}

local function setup()
    for name in pairs(madeWindows) do _G[name] = nil end
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    local box = TouchPlayWorldSignal
    assert(box, "the signal box exists once loaded")
    -- a log of the focus edges: { "on"|"off", seconds since t0 }
    local log, t0 = {}, Stub.now
    box.scripts.OnEditFocusGained = function() log[#log + 1] = { "on", Stub.now - t0 } end
    box.scripts.OnEditFocusLost = function() log[#log + 1] = { "off", Stub.now - t0 } end
    return box, log, t0
end

local function near(a, b) return math.abs(a - b) < 1e-6 end
local W3 = "on,off,on,off,on,off"           -- three pulses: a window is open (ruling A32)
local L4 = "on,off,on,off,on,off,on,off"    -- four pulses: "left" whatever group they join
local function pulses(log)
    local n = 0
    for _, e in ipairs(log) do if e[1] == "on" then n = n + 1 end end
    return n
end
local function edges(log)
    local t = {}
    for _, e in ipairs(log) do t[#t + 1] = e[1] end
    return table.concat(t, ",")
end
-- Moves the clock `seconds` forward timer by timer, so timers that start timers run in order (Stub.advance runs
-- only what is due at the end of one jump).
local function step(seconds)
    local stop = Stub.now + seconds
    while true do
        local nextAt
        for _, t in ipairs(Stub.timers) do
            if not t.cancelled and t.at <= stop + 1e-9 and (not nextAt or t.at < nextAt) then nextAt = t.at end
        end
        if not nextAt then break end
        Stub.advance(math.max(nextAt - Stub.now, 0) + 1e-9)
    end
    if stop > Stub.now then Stub.advance(stop - Stub.now) end
end

-- ---------------------------------------------------------------------------------------

T("signal_box_is_hidden_password_2x2", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local box = TouchPlayWorldSignal
    assert(box:GetObjectType() == "EditBox" and box:GetParent() == UIParent)
    assert(box:IsPassword() and not box:HasAutoFocus())
    assert(box:GetWidth() == 2 and box:GetHeight() == 2 and box:GetAlpha() == 0 and not box:IsMouseEnabled())
    assert(not box:HasFocus(), "no pulse until the world is entered")
    -- nothing types, sends or reacts
    for _, script in ipairs({ "OnChar", "OnKeyDown", "OnKeyUp", "OnTextChanged", "OnEnterPressed", "OnEscapePressed",
        "OnTabPressed", "OnEvent", "OnUpdate" }) do
        assert(box.scripts[script] == nil, "the box has no " .. script)
    end
    assert((box:GetText() or "") == "")
end)

T("signal_toc_before_contract", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then order[#order + 1] = line end
    end
    assert(order[#order] == "Contract.lua" and order[#order - 1] == "Signal.lua")
end)

T("signal_entering_one_pulse", function()
    local box, log = setup()
    Stub.fire("PLAYER_ENTERING_WORLD")
    assert(not box:HasFocus() and #log == 0, "no pulse at once (ruling A27)")
    step(0.99); assert(not box:HasFocus() and #log == 0, "nothing before 1 s")
    step(0.01)
    assert(box:HasFocus() and edges(log) == "on", "focus 1 s after entering")
    step(0.14); assert(box:HasFocus(), "still on before 0.15 s")
    step(0.01)
    assert(not box:HasFocus() and edges(log) == "on,off", edges(log))
    assert(near(log[1][2], 1.0) and near(log[2][2] - log[1][2], 0.15))
    step(5); assert(edges(log) == "on,off", "one pulse only")
    assert(not ns.paused, ns.lastError)
end)

T("signal_leaving_double_pulse", function()
    local box, log = setup()
    Stub.fire("PLAYER_LEAVING_WORLD")
    assert(box:HasFocus())
    step(0.15); assert(not box:HasFocus())
    step(0.14); assert(not box:HasFocus(), "still in the gap")
    step(0.01); assert(box:HasFocus(), "second pulse")
    step(0.15); assert(not box:HasFocus())
    assert(edges(log) == "on,off,on,off", edges(log))
    assert(near(log[1][2], 0) and near(log[2][2], 0.15) and near(log[3][2], 0.30) and near(log[4][2], 0.45))
    step(5); assert(#log == 4)
end)

T("signal_logout_after_leaving_adds_an_immediate_pair", function()
    local box, log = setup()
    Stub.fire("PLAYER_LEAVING_WORLD")
    assert(edges(log) == "on")
    Stub.fire("PLAYER_LOGOUT")      -- timers will not run any more
    assert(not box:HasFocus())
    assert(edges(log) == "on,off," .. L4, "the cut pulse closes, then four immediate pairs (4 or more reads left "
        .. "whatever they join): " .. edges(log))
    local n = #log
    step(5); assert(#log == n, "the cancelled timed pulses do nothing")
end)

T("signal_logout_alone_is_a_double_pulse", function()
    local box, log = setup()
    Stub.fire("PLAYER_LOGOUT")
    step(1)
    assert(edges(log) == "on,off,on,off", edges(log))
end)

T("signal_entering_waits_while_another_box_has_focus", function()
    local box, log = setup()
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    Stub.fire("PLAYER_ENTERING_WORLD")
    assert(not box:HasFocus() and #log == 0, "does not steal focus")
    step(3); assert(not box:HasFocus() and chat:HasFocus() and #log == 0)
    chat:ClearFocus()
    step(0.5)
    assert(edges(log) == "on,off", "pulses at the next poll: " .. edges(log))
    assert(log[1][2] >= 3 - 1e-6 and log[1][2] <= 3.5 + 1e-6, "not before the player left the typing box")
end)

T("signal_polls_at_most_every_half_second_and_gives_up_after_ten", function()
    local box, log = setup()
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    local calls = 0
    local original = GetCurrentKeyBoardFocus
    GetCurrentKeyBoardFocus = function() calls = calls + 1; return original() end
    Stub.fire("PLAYER_ENTERING_WORLD")
    assert(calls == 0, "not asked before the 1 s delay is over")
    step(0.99); assert(calls == 0)
    step(0.01); assert(calls == 1, "first check 1 s after entering")
    step(0.4); assert(calls == 1, "not asked again inside 0.5 s")
    step(0.1); assert(calls == 2)
    step(30)
    assert(calls == 21, "one check after the delay and twenty polls up to 10 s, then it stops: " .. calls)
    chat:ClearFocus()
    step(5); assert(#log == 0 and not box:HasFocus(), "gave up: no pulse afterwards")
end)

T("signal_leaving_goes_at_once_even_while_typing", function()
    local box, log = setup()
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    Stub.fire("PLAYER_LEAVING_WORLD")
    assert(box:HasFocus() and edges(log) == "on")
end)

T("signal_leaving_cancels_a_waiting_entering_pulse", function()
    local box, log = setup()
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    Stub.fire("PLAYER_ENTERING_WORLD")
    Stub.fire("PLAYER_LEAVING_WORLD")
    chat:ClearFocus()
    step(1)
    assert(edges(log) == "on,off,on,off", "only the leaving pulses: " .. edges(log))
end)

T("signal_leaving_within_the_delay_cancels_the_pending_entering_pulse", function()
    local box, log = setup()
    Stub.fire("PLAYER_ENTERING_WORLD")
    step(0.5)
    assert(#log == 0, "still waiting out the 1 s")
    Stub.fire("PLAYER_LEAVING_WORLD")
    assert(box:HasFocus() and edges(log) == "on", "the leaving pulse goes at once")
    step(0.15); step(0.15); step(0.15)
    assert(edges(log) == "on,off,on,off", "only the leaving pulses: " .. edges(log))
    step(5)
    assert(edges(log) == "on,off,on,off", "the entering pulse never fires: " .. edges(log))
    assert(not box:HasFocus())
end)

T("signal_off_sends_leaving_on_sends_entering", function()
    local box, log = setup()
    ns.SetEnabled(false)
    assert(box:HasFocus(), "Off pulses at once")
    step(1); assert(edges(log) == "on,off,on,off", edges(log))
    local n = #log
    ns.SetEnabled(true)
    -- the leaving pulses ended at 0.45 s: an entering pulse before 1.25 s would join their group (the app closes a
    -- group 0.6 s after its last pulse) and read as three pulses, "left"
    assert(#log == n and not box:HasFocus(), "On waits until the app has closed the leaving group")
    step(0.24); assert(#log == n, "not before 1.25 s")
    step(0.02)
    assert(#log == n + 1 and box:HasFocus(), "On pulses once")
    assert(log[n + 1][2] - log[n][2] >= 0.8 - 1e-6, "0.8 s after the last pulse ended")
    step(1); assert(edges(log) == "on,off,on,off,on,off", edges(log))
    assert(not ns.paused, ns.lastError)
end)

T("signal_on_long_after_off_pulses_at_once", function()
    local box, log = setup()
    ns.SetEnabled(false); step(2)
    local n = #log
    ns.SetEnabled(true)
    assert(#log == n + 1 and box:HasFocus(), "nothing to wait for")
end)

T("signal_no_pulses_while_off", function()
    local box, log = setup()
    ns.SetEnabled(false); step(1)
    local n = #log
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1)
    Stub.fire("PLAYER_LEAVING_WORLD"); step(1)
    Stub.fire("PLAYER_LOGOUT"); step(1)
    assert(#log == n and not box:HasFocus(), "an Off add-on stays silent")
end)

T("signal_on_out_of_the_world_waits_for_entering", function()
    local box, log = setup()
    ns.SetEnabled(false); step(1)
    Stub.fire("PLAYER_LEAVING_WORLD"); step(1)
    local n = #log
    ns.SetEnabled(true)
    assert(#log == n, "not in the world: no entering pulse yet")
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1.2)
    assert(#log == n + 2)
end)

T("signal_off_while_entering_is_superseded", function()
    local box, log = setup()
    Stub.fire("PLAYER_ENTERING_WORLD")
    step(1.05)
    ns.SetEnabled(false)
    step(2)
    -- the entering pulse was cut short (on, off), then four leaving pulses ran in full after a gap: 1 + 2 would read
    -- as 3, "a window" (ruling A32), so a leave into an open group is four
    assert(edges(log) == "on,off," .. L4, edges(log))
    assert(near(log[3][2] - log[2][2], 0.15) and near(log[4][2] - log[3][2], 0.15) and near(log[5][2] - log[4][2], 0.15))
    assert(not box:HasFocus())
end)

T("signal_reload_enters_again_and_login_off_is_silent", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1)
    TouchPlayDB.enabled = false
    Stub.reload()
    Stub.fire("PLAYER_LOGIN")
    local box = TouchPlayWorldSignal
    local n = 0
    box.scripts.OnEditFocusGained = function() n = n + 1 end
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1)
    assert(n == 0, "an add-on saved Off pulses nothing at login")
end)

T("signal_nothing_typed_and_no_action", function()
    local box, log = setup()
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1)
    assert(box:HasFocus())
    box:SetText("x")              -- something typed while the box held focus
    step(0.15)
    assert((box:GetText() or "") == "", "emptied with the focus")
    for _, script in ipairs({ "OnChar", "OnKeyDown", "OnTextChanged", "OnEnterPressed" }) do
        assert(box.scripts[script] == nil)
    end
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Ruling A26: an error pause tells the app too

T("signal_pause_sends_the_leaving_double_pulse", function()
    local box, log = setup()
    ns.Pause("test")
    assert(box:HasFocus() and edges(log) == "on")
    step(1)
    assert(edges(log) == "on,off,on,off", edges(log))
    assert(near(log[3][2] - log[1][2], 0.30))
    ns.Pause("again"); step(1)
    assert(#log == 4, "a second pause call does nothing")
end)

T("signal_resume_sends_one_entering_pulse", function()
    local box, log = setup()
    ns.Pause("test"); step(1)
    local n = #log
    ns.SetEnabled(false); step(1)
    assert(#log == n, "Off from a pause adds nothing: the pause already told the app")
    ns.SetEnabled(true)
    assert(not ns.paused and box:HasFocus() and #log == n + 1)
    step(1); assert(edges(log) == "on,off,on,off,on,off", edges(log))
end)

T("signal_pause_while_off_sends_nothing", function()
    local box, log = setup()
    ns.SetEnabled(false); step(1)
    local n = #log
    ns.Pause("test"); step(1)
    assert(#log == n and not box:HasFocus())
end)

T("signal_world_events_are_silent_while_paused", function()
    local box, log = setup()
    ns.Pause("test"); step(1)
    local n = #log
    Stub.fire("PLAYER_LEAVING_WORLD"); step(1)
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1)
    assert(#log == n, "a paused add-on stays silent")
end)

T("signal_pause_from_the_add_ons_own_error", function()
    local box, log = setup()
    ns.Guard("test", function() error("boom") end)
    assert(ns.paused); step(1)
    assert(edges(log) == "on,off,on,off", edges(log))
end)

-- ---------------------------------------------------------------------------------------
-- Ruling A30: an open sheet, card or game window hands the app's taps back to the game

-- In the world with the entering pulse already sent; the log starts empty.
local function inWorld()
    local box, log, t0 = setup()
    Stub.fire("PLAYER_ENTERING_WORLD"); step(2)
    assert(edges(log) == "on,off", edges(log))
    for i = #log, 1, -1 do log[i] = nil end
    return box, log, t0
end

-- A game window made the way a load-on-demand add-on makes it (shown or not): the frame and its UIPanelWindows entry
-- (as Blizzard_UIPanels_Game/Shared/TaxiFrame.lua:2 writes one), then ADDON_LOADED. No name list is involved.
local function gameWindow(name, shown)
    madeWindows[name] = true
    local f = CreateFrame("Frame", name, UIParent)
    f.shown = shown and true or false
    UIPanelWindows[name] = { area = "left", pushable = 0 }
    Stub.fire("ADDON_LOADED", "Blizzard_Something")
    return f
end

-- A hidden frame the test makes (its global is forgotten at the next setup).
local function hiddenFrame(name, parent)
    if name then madeWindows[name] = true end
    local f = CreateFrame("Frame", name, parent or UIParent)
    f.shown = false
    return f
end

T("overlay_open_sends_three_pulses_after_it_settles", function()
    local box, log = inWorld()
    ns.Loot.card:Show()             -- a card (A37: TouchPlay's full-screen sheets send 2)
    step(0.24); assert(#log == 0, "nothing before 0.25 s")
    step(0.02); assert(box:HasFocus() and edges(log) == "on", "the window pulses start")
    step(1.5); assert(edges(log) == W3, "three pulses: a window is open, still in the world (A32): " .. edges(log))
    assert(ns.Signal.Covered() and ns.Signal.Told() == ns.Signal.WINDOW)
    step(5); assert(#log == 6, "once")
end)

T("overlay_closed_sends_the_entering_pulse_at_once", function()
    local box, log = inWorld()
    ns.Loot.card:Show(); step(2)
    local n = #log
    ns.Loot.card:Hide()
    step(0.24); assert(#log == n)
    step(0.02)
    assert(#log == n + 1 and box:HasFocus(), "one pulse 0.25 s after the close: no 1 s wait")
    step(1); assert(edges(log) == W3 .. ",on,off", edges(log))
    assert(not ns.Signal.Covered() and ns.Signal.Told() == ns.Signal.ENTERED)
end)

-- The sequence that stopped auto-run on the iPad (run 5): map open, map closed. Never a "left" (2) on the way.
T("overlay_map_open_then_closed_never_says_left", function()
    local box, log = inWorld()
    local map = gameWindow("WorldMapFrame", false)
    ShowUIPanel(map); step(2)
    assert(edges(log) == W3, edges(log))
    HideUIPanel(map); step(2)
    assert(edges(log) == W3 .. ",on,off", "3 then 1: " .. edges(log))
end)

T("overlay_loading_screen_while_a_window_is_open_says_left", function()
    local box, log = inWorld()
    local map = gameWindow("WorldMapFrame", false)
    ShowUIPanel(map); step(2)
    local n = #log
    Stub.fire("PLAYER_LEAVING_WORLD")
    assert(box:HasFocus(), "at once")
    step(2)
    assert(pulses(log) - n / 2 == 2 and ns.Signal.Told() == ns.Signal.LEFT, "3 then 2: " .. edges(log))
    -- a loading screen just after the window pulses (their group may still be open): four, never "3 + 2"
    local box2, log2 = inWorld()
    local map2 = gameWindow("WorldMapFrame", false)
    ShowUIPanel(map2); step(0.26 + 0.6)               -- the third window pulse is on
    Stub.fire("PLAYER_LEAVING_WORLD"); step(3)
    assert(pulses(log2) == 3 + 4, "the cut third pulse, then four: " .. edges(log2))
end)

T("overlay_window_waits_for_a_closed_group_after_the_entering_pulse", function()
    local box, log, t0 = setup()
    Stub.fire("PLAYER_ENTERING_WORLD"); step(1.1)     -- the entering pulse is on (1.0 .. 1.15)
    ns.Loot.card:Show(); step(3)
    assert(edges(log) == "on,off," .. W3, edges(log))
    assert(log[3][2] - log[2][2] >= 0.8 - 1e-6, "3 never joins the 1 (that would read 4, left): "
        .. (log[3][2] - log[2][2]))
end)

T("overlay_switching_window_to_window_sends_nothing", function()
    local box, log = inWorld()
    local bags = ContainerFrame1             -- the game's own bag and character window (stub.lua)
    local character = CharacterFrame
    bags:Show(); step(2)
    local n = #log
    assert(n == 6)
    bags:Hide(); step(0.1); character:Show()
    step(3)
    assert(#log == n, "still covered: no pulse " .. edges(log))
    character:Hide(); step(1)
    assert(#log == n + 2, "closed: one entering pulse")
end)

T("overlay_open_and_closed_quickly_sends_nothing", function()
    local box, log = inWorld()
    ns.Menu.panel:Show(); step(0.1); ns.Menu.panel:Hide()
    step(3)
    assert(#log == 0, edges(log))
end)

T("overlay_entering_waits_for_the_app_to_close_the_window_group", function()
    local box, log = inWorld()
    ns.Loot.card:Show()
    step(0.26)                            -- the window pulses start (they end 0.75 s later)
    ns.Loot.card:Hide()                  -- counted again 0.25 s later, while the pulses still run
    step(0.3)
    assert(edges(log) == "on,off,on", edges(log))
    step(5)
    assert(edges(log) == W3 .. ",on,off", edges(log))
    assert(log[7][2] - log[6][2] >= 0.8 - 1e-6, "the entering pulse waits 0.8 s after the window ones ended: "
        .. (log[7][2] - log[6][2]))
end)

T("overlay_already_open_when_hooked_counts", function()
    local box, log = inWorld()
    gameWindow("PlayerSpellsFrame", true)  -- a load-on-demand window, shown as its add-on loaded
    step(1.5)
    assert(edges(log) == W3, edges(log))
end)

T("overlay_entering_world_with_a_window_open_says_window", function()
    local box, log = setup()
    local map = gameWindow("WorldMapFrame", true)
    step(1)
    Stub.fire("PLAYER_ENTERING_WORLD")
    step(0.99); assert(#log == 0, "not before the 1 s entering delay")
    step(3)
    assert(edges(log) == W3, "in the world with the map open: 3, " .. edges(log))
    map:Hide(); step(1.5)
    assert(edges(log) == W3 .. ",on,off", "the map closed: the entering pulse " .. edges(log))
end)

T("overlay_window_pulses_wait_while_the_player_types", function()
    local box, log, t0 = inWorld()
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    ns.Loot.card:Show()
    step(15)
    assert(#log == 0 and chat:HasFocus(), "the keyboard is never taken (and 3 does not give up)")
    local cleared = Stub.now
    chat:ClearFocus()
    step(1.5)
    assert(edges(log) == W3, edges(log))
    assert(log[1][2] >= cleared - t0 - 1e-6, "not before the player left the typing box")
end)

T("overlay_entering_waits_while_the_player_types", function()
    local box, log = inWorld()
    ns.Loot.card:Show(); step(2)
    local chat = CreateFrame("EditBox", "TypingBox", UIParent)
    chat:SetFocus()
    ns.Loot.card:Hide(); step(3)
    assert(#log == 6 and chat:HasFocus())
    chat:ClearFocus(); step(0.6)
    assert(edges(log) == W3 .. ",on,off", "the entering pulse at the next poll: " .. edges(log))
end)

T("overlay_silent_while_off_and_on_with_it_open_says_window", function()
    local box, log = inWorld()
    ns.SetEnabled(false); step(2)
    local n = #log
    ns.Loot.card:Show(); step(2)
    assert(#log == n, "Off: silent")
    ns.SetEnabled(true); step(2)
    assert(#log == n + 6, "On with the loot card open: 3 " .. edges(log))
    ns.Loot.card:Hide(); step(1.5)
    assert(#log == n + 8, "the card closed: the entering pulse")
end)

T("overlay_every_touchplay_panel_counts", function()
    -- ruling A37: the full-screen sheets say "left" (2) while open
    for _, path in ipairs({ { "Picker", "sheet" }, { "Menu", "panel" }, { "Feel", "panel" }, { "Guide", "dim" } }) do
        local box, log = inWorld()
        local frame = ns[path[1]][path[2]]
        frame:Show(); step(1.5)
        assert(ns.Signal.Covered() and ns.Signal.SheetOpen() and ns.Signal.Told() == ns.Signal.LEFT and #log == 4,
            path[1] .. "." .. path[2] .. " is a sheet: 2, " .. edges(log))
        frame:Hide(); step(1.5)
        assert(not ns.Signal.SheetOpen() and ns.Signal.Told() == ns.Signal.ENTERED and #log == 6, "closed: 1")
    end
    for _, path in ipairs({ { "Loot", "card" }, { "Perf", "panel" }, { "Perf", "card" }, { "Hud", "afk" },
        { "Interact", "card" } }) do
        local box, log = inWorld()
        local frame = ns[path[1]][path[2]]
        frame:Show(); step(1.5)
        assert(ns.Signal.Covered() and #log == 6, path[1] .. "." .. path[2] .. " is an overlay")
    end
    -- the info card is made on first use
    local box, log = inWorld()
    Stub.actions[3] = 116
    ns.InfoCard.Show({ kind = "action", slot = 3 }); step(1.5)
    assert(ns.InfoCard.IsShown() and ns.Signal.Covered() and #log == 6, "the info card is an overlay")
    ns.InfoCard.Hide(); step(1.5)
    assert(not ns.Signal.Covered() and #log == 8, "closed: the entering pulse")
    -- the reload notice is not: it sits clear of every touch area
    inWorld()
    ns.Contract.notice:Show(); step(1)
    assert(not ns.Signal.Covered())
end)

-- Ruling A37 (iPad run 7): a sheet over a game window says 2; closing the sheet with the window still open says 3 again;
-- closing the window then says 1. Going from one sheet to another (Menu, then Touch settings) sends nothing.
T("sheet_over_a_window_left_then_window_then_entered", function()
    local box, log = inWorld()
    local map = gameWindow("WorldMapFrame", false)
    ShowUIPanel(map); step(2)
    assert(edges(log) == W3, edges(log))
    ns.Picker.sheet:Show(); step(2)
    assert(ns.Signal.Told() == ns.Signal.LEFT and pulses(log) == 3 + 2, "3 then 2: " .. edges(log))
    ns.Picker.sheet:Hide(); step(2)
    assert(ns.Signal.Told() == ns.Signal.WINDOW and pulses(log) == 3 + 2 + 3, "the map still open: 3 " .. edges(log))
    HideUIPanel(map); step(2)
    assert(ns.Signal.Told() == ns.Signal.ENTERED and pulses(log) == 3 + 2 + 3 + 1, "then 1: " .. edges(log))
    -- sheet to sheet
    local n = pulses(log)
    ns.Menu.panel:Show(); step(2)
    assert(pulses(log) == n + 2)
    ns.Menu.panel:Hide(); step(0.1); ns.Feel.panel:Show(); step(3)
    assert(pulses(log) == n + 2, "Menu to Touch settings: still 2, nothing sent")
    ns.Feel.panel:Hide(); step(2)
    assert(pulses(log) == n + 3 and ns.Signal.Told() == ns.Signal.ENTERED, "Done: 1")
end)

-- No name list: the windows come from the game's own registries. Only frames that neither registry covers are named,
-- each with its file and line in /tmp/wowui.
T("overlay_no_guessed_window_names", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(ns.Signal.WINDOWS == nil, "the hand-written list is gone")
    local extra = {}
    for _, n in ipairs(ns.Signal.EXTRA) do extra[n] = true end
    assert(#ns.Signal.EXTRA == 2 and extra.ModelPreviewFrame and extra.GroupLootHistoryFrame,
        "only the windows no registry covers")
    local f = assert(io.open("addon/TouchPlay/Signal.lua")); local text = f:read("*a"); f:close()
    for _, n in ipairs(ns.Signal.EXTRA) do
        local evidence = text:match("%-%- " .. n .. ": (.-)\n%s*\"" .. n .. "\"")
        assert(evidence and evidence:find("[%w_/]+%.xml:%d+") and evidence:find("[%w_]+%.lua:%d+"),
            n .. " carries its evidence (file:line)")
    end
end)

T("overlay_a_named_window_counts", function()
    local box, log = inWorld()
    local preview = hiddenFrame("ModelPreviewFrame")   -- Blizzard_SharedXML: made before any add-on loads
    Stub.fire("ADDON_LOADED", "SomeAddon")
    SlashCmdList.TOUCHPLAY("windows on")
    preview:Show(); step(1.5)
    assert(edges(log) == W3 and ns.Signal.Covered(), edges(log))
    local l = TouchPlayDB.windowlog
    assert(l[#l]:find("| OPEN | ModelPreviewFrame | named", 1, true), l[#l])
    SlashCmdList.TOUCHPLAY("windows off")
end)

-- ---------------------------------------------------------------------------------------
-- The panel manager: UIPanelWindows, RegisterUIPanel, ShowUIPanel / HideUIPanel, CloseAllWindows

T("panel_registered_after_load_and_shown_with_ShowUIPanel_says_window_HideUIPanel_enters", function()
    local box, log = inWorld()
    local late = hiddenFrame("LateLoadedWindow")
    UIPanelWindows.LateLoadedWindow = { area = "left", pushable = 0 }    -- no ADDON_LOADED: ShowUIPanel finds it
    ShowUIPanel(late)
    step(0.24); assert(#log == 0, "settles first")
    step(0.02); assert(box:HasFocus() and edges(log) == "on", "the window pulses")
    step(1.5); assert(edges(log) == W3 and ns.Signal.Covered(), edges(log))
    HideUIPanel(late)
    step(0.26); assert(#log == 7 and box:HasFocus(), "the entering pulse at once: " .. edges(log))
    step(1); assert(edges(log) == W3 .. ",on,off" and not ns.Signal.Covered(), edges(log))
end)

T("panel_registered_with_RegisterUIPanel_counts_when_shown_directly", function()
    local box, log = inWorld()
    local map = hiddenFrame("LateMapFrame")
    RegisterUIPanel(map, { area = "left", pushable = 0, allowOtherPanels = 1 })   -- as Blizzard_WorldMap.lua:135
    map:Show()                                                                     -- not through ShowUIPanel
    step(1.5)
    assert(edges(log) == W3 and ns.Signal.Covered(), edges(log))
    map:Hide(); step(1.5)
    assert(#log == 8 and not ns.Signal.Covered())
end)

T("panel_found_in_UIPanelWindows_when_its_addon_loads", function()
    local box, log = inWorld()
    -- UIPanelWindows names the frame before its load-on-demand add-on made it (Mainline/UIPanelWindows.lua:9)
    local book = hiddenFrame("ProfessionsBookFrame")
    Stub.fire("ADDON_LOADED", "Blizzard_ProfessionsBook")
    book:Show(); step(1.5)
    assert(edges(log) == W3, edges(log))
end)

T("panel_any_frame_ShowUIPanel_shows_counts_even_unnamed", function()
    local box, log = inWorld()
    -- ShowUIPanel shows a frame that has no UIPanelWindows entry too (UIParentPanelManager.lua:891)
    local holder = hiddenFrame("SomeHolder"); holder.shown = true
    local unnamed = hiddenFrame(nil, holder)
    ShowUIPanel(unnamed); step(1.5)
    assert(edges(log) == W3, edges(log))
    unnamed:Hide(); step(1.5)
    assert(#log == 8)
end)

T("panel_close_all_windows_sends_the_entering_pulse", function()
    local box, log = inWorld()
    ShowUIPanel(CharacterFrame)
    ContainerFrame1:Show()
    step(2); assert(#log == 6 and ns.Signal.Covered())
    CloseAllWindows()                 -- Escape (UIParentPanelManager.lua:1175): the bags, then the panels
    step(1.5)
    assert(edges(log) == W3 .. ",on,off" and not ns.Signal.Covered(), edges(log))
end)

T("panel_in_a_fight_ShowUIPanel_that_did_nothing_counts_nothing", function()
    local box, log = inWorld()
    Stub.combat(true)
    ShowUIPanel(CharacterFrame)       -- add-on code in a fight: the game shows nothing
    step(2)
    Stub.combat(false)
    assert(#log == 0 and not ns.Signal.Covered(), edges(log))
end)

-- ---------------------------------------------------------------------------------------
-- UISpecialFrames: the Escape list other add-ons put their windows in

T("special_frame_added_by_a_later_ADDON_LOADED_is_caught", function()
    local box, log = inWorld()
    local window = hiddenFrame("SomeAddonMainWindow")
    table.insert(UISpecialFrames, "SomeAddonMainWindow")
    Stub.fire("ADDON_LOADED", "SomeAddon")
    window:Show(); step(1.5)
    assert(edges(log) == W3 and ns.Signal.Covered(), edges(log))
    CloseSpecialWindows()             -- Escape closes it (UIParentPanelManager.lua:1106)
    step(1.5)
    assert(#log == 8 and not ns.Signal.Covered(), edges(log))
end)

T("special_the_games_own_entries_count", function()
    local box, log = inWorld()
    ItemRefTooltip:Show(); step(1.5)
    assert(edges(log) == W3, "a clicked link's tooltip: " .. edges(log))
end)

T("special_bag_addon_window_made_on_first_toggle_is_found", function()
    for name in pairs(madeWindows) do _G[name] = nil end
    madeWindows.SomeBagAddonInventory = true
    Stub.reset()
    local made
    -- a bag add-on such as Bagnon: its window is made on first use and put in UISpecialFrames
    ToggleAllBags = function()
        if not made then
            made = CreateFrame("Frame", "SomeBagAddonInventory", UIParent)
            made.shown = false
            table.insert(UISpecialFrames, "SomeBagAddonInventory")
        end
        made:Show()
    end
    Stub.loadAll(); Stub.login()
    local box = TouchPlayWorldSignal
    local log = {}
    box.scripts.OnEditFocusGained = function() log[#log + 1] = "on" end
    Stub.fire("PLAYER_ENTERING_WORLD"); step(2)
    assert(#log == 1)
    ToggleAllBags()
    step(1.5)
    assert(#log == 4 and ns.Signal.Covered(), "the bag add-on's window counts: " .. #log)
    made:Hide(); step(1.5)
    assert(#log == 5)
    ToggleAllBags = nil
end)

-- ---------------------------------------------------------------------------------------
-- The game's bags (ContainerFrame.xml: ContainerFrameContainer.ContainerFrames and ContainerFrameCombinedBags)

T("bag_opening_is_caught_and_closing_enters", function()
    local box, log = inWorld()
    ContainerFrame1:Show()             -- ContainerFrame_GenerateFrame shows the frame (ContainerFrame.lua:1304)
    step(1.5)
    assert(edges(log) == W3 and ns.Signal.Covered(), edges(log))
    ContainerFrame1:Hide(); step(1.5)
    assert(#log == 8 and not ns.Signal.Covered())
    ContainerFrameCombinedBags:Show(); step(1.5)
    assert(#log == 14, "the combined bag counts too: " .. #log)
    ContainerFrameCombinedBags:Hide(); step(1.5)
    for i = 2, 7 do
        local n = #log
        ContainerFrameContainer.ContainerFrames[i]:Show(); step(1.5)
        assert(#log == n + 6, "bag frame " .. i)
        ContainerFrameContainer.ContainerFrames[i]:Hide(); step(1.5)
    end
end)

-- ---------------------------------------------------------------------------------------
-- What stays out

T("excluded_frames_are_not_windows", function()
    local box, log = inWorld()
    LootFrame:Show(); step(2)          -- in UIPanelWindows, but TouchPlay's loot card stands in for it
    assert(#log == 0 and not ns.Signal.Covered(), "the game's loot window: " .. edges(log))
    LootFrame:Hide(); step(1)
    table.insert(UISpecialFrames, "StaticPopup1")    -- a popup is not a window, whoever lists it
    Stub.fire("ADDON_LOADED", "SomeAddon")
    StaticPopup1:Show(); step(2)
    assert(#log == 0 and not ns.Signal.Covered(), "a popup: " .. edges(log))
    StaticPopup1:Hide()
    local quiet = hiddenFrame("QuietWindow")   -- a registered window kept at alpha 0 counts as closed
    quiet:SetAlpha(0)
    UIPanelWindows.QuietWindow = { area = "left" }
    ShowUIPanel(quiet); step(2)
    assert(#log == 0 and not ns.Signal.Covered(), "alpha 0: " .. edges(log))
    ns.Contract.notice:Show(); step(1)
    assert(#log == 0 and not ns.Signal.Covered(), "the reload notice")
end)

T("excluded_a_bag_kept_shown_at_a_tiny_scale_by_a_bag_addon", function()
    local box, log = inWorld()
    -- Bagnon keeps the game's combined bag open inside a parent at scale 0.001 while its own window stands in
    -- (BagBrother/core/features/uiOverrides.lua:25, :56)
    local tiny = hiddenFrame(nil, ContainerFrameContainer); tiny.shown = true; tiny:SetScale(0.001)
    local own = hiddenFrame("SomeBagAddonInventory")
    table.insert(UISpecialFrames, "SomeBagAddonInventory")
    Stub.fire("ADDON_LOADED", "SomeBagAddon")
    ContainerFrameCombinedBags:Show(); ContainerFrameCombinedBags:SetParent(tiny); own:Show()
    step(1.5)
    assert(edges(log) == W3, edges(log))
    own:Hide()                        -- closed with its own button: the game's bag stays shown, tiny
    step(1.5)
    assert(edges(log) == W3 .. ",on,off" and not ns.Signal.Covered(), "the tiny bag is not a window: "
        .. edges(log))
    ContainerFrameCombinedBags:SetParent(UIParent); ContainerFrameCombinedBags:Hide()
end)

-- ---------------------------------------------------------------------------------------
-- /touch windows: the detector's own log, for checking on the iPad

local function windowLog() return TouchPlayDB.windowlog or {} end
local function lastWindowLine() local l = windowLog(); return l[#l] or "" end
local function lineHas(line, ...)
    for _, part in ipairs({ ... }) do
        if not line:find(part, 1, true) then return false end
    end
    return true
end

T("windows_log_lines_name_source_open_and_close", function()
    inWorld()
    assert(TouchPlayDB.windowlog == nil, "nothing saved before it is asked for")
    ShowUIPanel(CharacterFrame)        -- already open when the log starts: listed at the start
    SlashCmdList.TOUCHPLAY("windows")
    local l = windowLog()
    assert(lineHas(l[1], "| START") and lineHas(l[2], "| OPEN | CharacterFrame | panel"), table.concat(l, "\n"))
    assert(lineHas(Stub.chat[#Stub.chat] or "", "CharacterFrame"), "printed too")
    HideUIPanel(CharacterFrame)
    assert(lineHas(lastWindowLine(), "| CLOSE | CharacterFrame | panel"), lastWindowLine())
    ContainerFrame2:Show()
    assert(lineHas(lastWindowLine(), "| OPEN | ContainerFrame2 | bag"), lastWindowLine())
    ContainerFrame2:Hide()
    ItemRefTooltip:Show()
    assert(lineHas(lastWindowLine(), "| OPEN | ItemRefTooltip | special"), lastWindowLine())
    ItemRefTooltip:Hide()
    ns.Picker.sheet:Show()
    assert(lineHas(lastWindowLine(), "| OPEN |", "| own"), lastWindowLine())
    ns.Picker.sheet:Hide()
    local holder = hiddenFrame("SomeHolder"); holder.shown = true
    local unnamed = hiddenFrame(nil, holder)
    ShowUIPanel(unnamed)
    assert(lineHas(lastWindowLine(), "| OPEN | <unnamed> in SomeHolder > UIParent | panel"), lastWindowLine())
    unnamed:Hide()
    assert(lineHas(lastWindowLine(), "| CLOSE | <unnamed> in SomeHolder > UIParent | panel"), lastWindowLine())
    local quiet = hiddenFrame("QuietWindow"); quiet:SetAlpha(0)
    UIPanelWindows.QuietWindow = { area = "left" }
    ShowUIPanel(quiet)
    assert(lineHas(lastWindowLine(), "| OPEN | QuietWindow | panel", "alpha 0"), "seen, marked not counted: "
        .. lastWindowLine())
    SlashCmdList.TOUCHPLAY("windows")
    assert(lineHas(lastWindowLine(), "| STOP"))
    local n = #windowLog()
    ShowUIPanel(CharacterFrame); HideUIPanel(CharacterFrame)
    assert(#windowLog() == n, "off: nothing more is logged")
    assert(not ns.paused, ns.lastError)
end)

T("windows_log_keeps_the_last_200_lines", function()
    inWorld()
    SlashCmdList.TOUCHPLAY("windows on")
    for _ = 1, 150 do ShowUIPanel(CharacterFrame); HideUIPanel(CharacterFrame) end
    assert(#windowLog() == 200, #windowLog())
    assert(lineHas(lastWindowLine(), "| CLOSE | CharacterFrame"))
    assert(not lineHas(windowLog()[1], "| START"), "the oldest went first")
    SlashCmdList.TOUCHPLAY("windows clear")
    assert(TouchPlayDB.windowlog == nil)
    SlashCmdList.TOUCHPLAY("windows off")
    assert(not ns.paused, ns.lastError)
end)

T("overlay_hooks_create_no_timer_while_nothing_changes", function()
    local box, log = inWorld()
    local base = #Stub.timers
    ns.Picker.sheet:Hide(); ns.Menu.panel:Hide()     -- already hidden
    assert(#Stub.timers == base, "nothing waits")
end)

Stub.done("signal")
