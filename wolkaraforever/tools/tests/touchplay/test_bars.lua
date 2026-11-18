-- Task 2: the game's bars are hidden by reparenting and come back unchanged (rule 2).
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.load("Core.lua", "Bars.lua")
    Stub.login()
    return ns.Bars
end

T("rule2_hide_then_restore_same_parents", function()
    Stub.reset(); Stub.load("Core.lua", "Bars.lua")
    local Bars = ns.Bars
    local before = Stub.frames.MainActionBar:GetParent()
    Bars:Layout(); assert(Bars.IsHidden("MainActionBar"))
    assert(not Stub.frames.MainActionBar:IsVisible())
    Bars:Restore(); assert(Stub.frames.MainActionBar:GetParent() == before)
    assert(not Bars.IsHidden("MainActionBar"))
end)

T("rule2_every_listed_frame_hidden_at_login", function()
    local Bars = setup()
    for _, name in ipairs(Bars.HIDDEN) do
        if Stub.frames[name] then assert(Bars.IsHidden(name), name) end
    end
    assert(Bars.IsHidden("PlayerFrame") and Bars.IsHidden("ObjectiveTrackerFrame"))
end)

-- iPad run 1: the controller's bottom-centre bar and the minimap's own cluster (zone bar, coordinates, clock)
-- stayed on screen next to ours.
T("gamepad_bar_and_minimap_cluster_hidden_and_given_back", function()
    Stub.reset(); Stub.load("Core.lua", "Bars.lua")
    local Bars = ns.Bars
    assert(Stub.frames.GamepadMainActionBarFrame and Stub.frames.MinimapCluster, "the stub has both")
    local gamepadParent, clusterParent = Stub.frames.GamepadMainActionBarFrame:GetParent(), Stub.frames.MinimapCluster:GetParent()
    Stub.login()
    assert(Bars.IsHidden("GamepadMainActionBarFrame") and Bars.IsHidden("MinimapCluster"))
    assert(not Stub.frames.GamepadMainActionBarFrame:IsVisible() and not Stub.frames.MinimapCluster:IsVisible())
    assert(Stub.frames.GamepadMainActionBarFrame.isShownExternal == nil, "Edit Mode's flag purged, as the other bars")
    -- never through Edit Mode's own methods
    for _, name in ipairs({ "GamepadMainActionBarFrame", "MinimapCluster" }) do
        local f = Stub.frames[name]
        assert(f.calls.Hide == 0 and f.calls.SetPoint == 0 and f.calls.ClearAllPoints == 0, name)
    end
    -- the game puts them back (a layout change): they are hidden again; Edit Mode and Off give them back
    Stub.frames.GamepadMainActionBarFrame:SetParent(UIParent); Stub.fire("EDIT_MODE_LAYOUTS_UPDATED")
    assert(Bars.IsHidden("GamepadMainActionBarFrame"))
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(Stub.frames.GamepadMainActionBarFrame:GetParent() == gamepadParent and Stub.frames.MinimapCluster:GetParent() == clusterParent)
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(Bars.IsHidden("GamepadMainActionBarFrame") and Bars.IsHidden("MinimapCluster"))
    Bars:Restore()
    assert(Stub.frames.GamepadMainActionBarFrame:GetParent() == gamepadParent and Stub.frames.MinimapCluster:GetParent() == clusterParent)
    assert(not ns.paused, tostring(ns.lastError))
end)

T("rule2_slots_untouched", function()
    local Bars = setup()
    Bars:Restore(); Bars:Layout(); Bars:Restore()
    assert(Stub.calls.PlaceAction == 0 and Stub.calls.PickupAction == 0 and Stub.calls.ClearCursor == 0)
end)

T("rule2_in_combat_waits", function()
    local Bars = setup()
    Stub.combat(true); Bars:Restore(); assert(Bars.IsHidden("MainActionBar"))
    assert(not ns.paused, "no blocked action in combat")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); assert(not Bars.IsHidden("MainActionBar"))
end)

T("touch_off_restores_bars", function()
    local Bars = setup()
    SlashCmdList.TOUCHPLAY("")
    assert(not Bars.IsHidden("MainActionBar") and Stub.frames.MainActionBar:GetParent() == Stub.frames.UIParent)
    SlashCmdList.TOUCHPLAY("")
    assert(Bars.IsHidden("MainActionBar"))
end)

T("missing_frames_skipped", function()
    Stub.reset(); Stub.load("Core.lua", "Bars.lua")
    Stub.frames.MultiBar7 = nil
    ns.Bars:Layout() -- no error
    ns.Bars:Restore()
end)

T("late_frames_hidden", function()
    local Bars = setup()
    Stub.frames.Questie_BaseFrame = CreateFrame("Frame", "Questie_BaseFrame", UIParent)
    Stub.fire("ADDON_LOADED", "Questie")
    assert(Bars.IsHidden("Questie_BaseFrame"))
    Bars:Restore(); assert(Stub.frames.Questie_BaseFrame:GetParent() == Stub.frames.UIParent)
end)

-- iPad run 8 (17 Nov): Questie's tracker ("Questie Tracker: 1/40") was drawn at the right edge over the page boxes
-- and the item column. Questie makes Questie_BaseFrame in its start-up thread (QuestieInit Stage 3 ->
-- QuestieTracker.Initialize -> TrackerBaseFrame.Initialize), seconds after PLAYER_LOGIN and after the last
-- ADDON_LOADED, so the name was never there when Bars looked. While the touch screen is active it is moved into the
-- hidden frame as soon as it appears; Off, a pause and Edit Mode give it back. Questie's settings are not touched.
T("questie_tracker_made_after_login_is_hidden_and_given_back", function()
    Questie_BaseFrame = nil                           -- an earlier test made one
    local Bars = setup()
    C_AddOns.IsAddOnLoaded = function(name) return name == "Questie" end
    Stub.fire("PLAYER_ENTERING_WORLD", true, false)
    Stub.advance(5)                                   -- Questie still starting
    local base = CreateFrame("Frame", "Questie_BaseFrame", UIParent)
    Stub.frames.Questie_BaseFrame = base
    base:Show()
    Stub.advance(2)
    assert(Bars.IsHidden("Questie_BaseFrame"), "hidden once it appears, with no ADDON_LOADED")
    assert(not base:IsVisible())
    -- Off gives it back, On hides it again
    ns.SetEnabled(false); Stub.advance(1)
    assert(base:GetParent() == UIParent and base:IsVisible(), "Off: Questie's tracker is back")
    ns.SetEnabled(true); Stub.advance(1)
    assert(Bars.IsHidden("Questie_BaseFrame"))
    -- Edit Mode gives it back, closing it hides it again
    EventRegistry:TriggerEvent("EditMode.Enter"); Stub.advance(1)
    assert(base:GetParent() == UIParent)
    EventRegistry:TriggerEvent("EditMode.Exit"); Stub.advance(1)
    assert(Bars.IsHidden("Questie_BaseFrame"))
    -- a pause gives it back
    ns.Pause("test"); Stub.advance(1)
    assert(base:GetParent() == UIParent)
    C_AddOns.IsAddOnLoaded = nil
end)

T("questie_tracker_made_in_a_fight_waits_for_the_end", function()
    Questie_BaseFrame = nil                           -- an earlier test made one
    local Bars = setup()
    C_AddOns.IsAddOnLoaded = function(name) return name == "Questie" end
    Stub.fire("PLAYER_ENTERING_WORLD", true, false)
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    local base = CreateFrame("Frame", "Questie_BaseFrame", UIParent)
    Stub.frames.Questie_BaseFrame = base
    Stub.advance(2)
    assert(not ns.paused, tostring(ns.lastError))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); Stub.advance(2)
    assert(Bars.IsHidden("Questie_BaseFrame"))
    C_AddOns.IsAddOnLoaded = nil
end)

T("no_watch_for_questie_when_it_is_not_loaded", function()
    Questie_BaseFrame = nil
    local Bars = setup()
    C_AddOns.IsAddOnLoaded = function() return false end
    local before = #Stub.timers
    Stub.fire("PLAYER_ENTERING_WORLD", true, false)
    assert(#Stub.timers == before, "nothing to wait for")
    -- Questie loaded but its tracker never made (tracker off in Questie's settings): the watch ends
    C_AddOns.IsAddOnLoaded = function(name) return name == "Questie" end
    Stub.fire("PLAYER_ENTERING_WORLD", false, true)
    Stub.advance(Bars.LATE_WATCH_SECONDS + 5)
    local pending = 0
    for _, t in ipairs(Stub.timers) do if not t.done and t.at > Stub.now then pending = pending + 1 end end
    assert(pending == 0, "the watch stopped: " .. pending)
    assert(not ns.paused, tostring(ns.lastError))
    C_AddOns.IsAddOnLoaded = nil
end)

T("error_restores_bars", function()
    local Bars = setup()
    ns.Register("Bad", { Refresh = function() error("boom") end })
    ns.Each("Refresh")
    assert(ns.paused and not Bars.IsHidden("MainActionBar"))
end)

-- Task 1: Edit Mode safe (rule 2).
T("rule2_never_calls_editmode_methods", function()
    local Bars = setup()
    for _, name in ipairs(Bars.HIDDEN) do
        local f = Stub.frames[name]
        if f then assert(f.calls.Hide == 0 and f.calls.SetPoint == 0 and f.calls.ClearAllPoints == 0, name) end
    end
end)
T("isshownexternal_purged", function()
    local Bars = setup()
    assert(Stub.frames.MultiBarBottomLeft.isShownExternal == nil)
end)
T("regen_events_unregistered_and_restored", function()
    local Bars = setup()
    assert(not Stub.frames.MainActionBar:IsEventRegistered("ACTIONBAR_SHOWGRID"))
    Bars:Restore()
    assert(Stub.frames.MainActionBar:IsEventRegistered("ACTIONBAR_SHOWGRID"))
end)
T("show_hook_rehides_out_of_combat", function()
    local Bars = setup()
    Stub.frames.MultiBarRight:SetParent(UIParent); Stub.frames.MultiBarRight:Show()
    assert(Bars.IsHidden("MultiBarRight"))
end)
T("editmode_enter_restores_exit_rehides", function()
    local Bars = setup()
    EventRegistry:TriggerEvent("EditMode.Enter"); assert(not Bars.IsHidden("MainActionBar"))
    EventRegistry:TriggerEvent("EditMode.Exit"); assert(Bars.IsHidden("MainActionBar"))
end)
T("layouts_updated_rehides", function()
    local Bars = setup()
    Stub.frames.PlayerFrame:SetParent(UIParent); Stub.fire("EDIT_MODE_LAYOUTS_UPDATED")
    assert(Bars.IsHidden("PlayerFrame"))
end)

T("show_in_combat_does_not_cancel_a_pending_restore", function()
    local Bars = setup()
    Stub.combat(true)
    Bars:Restore()
    Stub.runSnippet(Stub.frames.MultiBarRight, "self:Show()") -- the game itself shows a bar in the fight
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not Bars.IsHidden("MultiBarRight") and not Bars.IsHidden("MainActionBar"))
end)

-- I8 (R44): one Edit Mode flag in Core. Entering gives back the bars, the minimap and the mirror timers and hides
-- our screen (the move root stays); a rebuild while it is open leaves the game's frames alone; leaving lays out again.
T("edit_mode_gives_the_game_its_frames_and_hides_our_screen", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local Hud, Bars = ns.Hud, ns.Bars
    local box = Stub.frames.MirrorTimerContainer
    assert(Hud.IsMinimapInRing() and Bars.IsHidden("MainActionBar") and box.mirrorTimers[1]:GetWidth() ~= 206)
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(ns.inEditMode == true)
    assert(not Bars.IsHidden("MainActionBar"), "the bars are back")
    assert(not Hud.IsMinimapInRing() and Stub.frames.Minimap:GetParent() ~= Hud.disc, "the minimap is back")
    assert(box.mirrorTimers[1]:GetWidth() == 206, "the mirror timers are back")
    assert(not ns.root:IsShown() and ns.moveRoot:IsShown(), "our screen hides, the move root stays")
    -- a Touch settings rebuild while Edit Mode is open
    ns.Feel.Set("buttonSize", 1.2); Stub.advance(1)
    assert(not Bars.IsHidden("MainActionBar") and not Hud.IsMinimapInRing(), "a rebuild leaves the game's frames alone")
    assert(box.mirrorTimers[1]:GetWidth() == 206 and not ns.root:IsShown())
    assert(_G.ChatFrame1:GetAlpha() == 1, "the game's chat stays the game's")
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(ns.inEditMode == false)
    assert(ns.root:IsShown() and Bars.IsHidden("MainActionBar") and Hud.IsMinimapInRing(), "our screen is back")
    assert(box.mirrorTimers[1]:GetWidth() ~= 206 and _G.ChatFrame1:GetAlpha() == 0)
    assert(not ns.paused, tostring(ns.lastError))
end)

-- iPad run 5: the game's own cast bar drew under ours.
T("game_cast_bar_hidden_and_given_back", function()
    Stub.reset()
    local castBar = CreateFrame("StatusBar", "PlayerCastingBarFrame", UIParent)
    castBar.system, castBar.isShownExternal = true, true
    Stub.load("Core.lua", "Bars.lua"); Stub.login()
    local Bars = ns.Bars
    assert(Bars.IsHidden("PlayerCastingBarFrame") and not castBar:IsVisible())
    assert(castBar.calls.Hide == 0 and castBar.calls.SetPoint == 0, "never through Edit Mode's own methods")
    castBar:Show()                                  -- a cast: still hidden (its parent is)
    assert(not castBar:IsVisible())
    castBar:SetParent(UIParent); castBar:Show()     -- attached / detached by the game: hidden again
    assert(Bars.IsHidden("PlayerCastingBarFrame"))
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(castBar:GetParent() == UIParent, "Edit Mode gives it back")
    EventRegistry:TriggerEvent("EditMode.Exit")
    Bars:Restore()
    assert(castBar:GetParent() == UIParent and castBar:IsVisible(), "Off gives it back")
end)

-- iPad run 5: the gamepad UI's own bars (Blizzard_GamepadActionBars, no source in this client's UI) drew two large
-- spell buttons and a row of small ones under the chat strip. Every frame under UIParent holding an action button
-- is hidden, whatever its name, except TouchPlay's own and the ones the touch screen does not replace.
local function actionButton(parent, slot, name)
    local b = CreateFrame("CheckButton", name, parent)
    b:SetAttribute("action", slot)
    return b
end

T("stray_action_bars_found_by_their_buttons_and_given_back", function()
    Stub.reset()
    local hostile = CreateFrame("Frame", "SomeGamepadTargetingBar", UIParent)
    local inner = CreateFrame("Frame", nil, hostile)
    actionButton(inner, 61)
    local unnamed = CreateFrame("Frame", nil, UIParent)       -- a bar with no name, buttons by type only
    local typed = CreateFrame("Button", nil, unnamed); typed:SetAttribute("type", "action")
    local shortcuts = CreateFrame("Frame", "SomeShortcutsBar", UIParent)
    local field = CreateFrame("Button", nil, shortcuts); field.action = 7
    shortcuts.shown = false                                   -- shown later (a target): hidden already
    local extra = CreateFrame("Frame", "ExtraActionBarFrame", UIParent)
    actionButton(extra, 169)
    local plain = CreateFrame("Frame", "SomeAddonWindow", UIParent)
    CreateFrame("Button", nil, plain)                         -- a button with no action: not a bar
    Stub.loadAll(); Stub.login()
    local Bars = ns.Bars
    assert(Bars.IsHidden(hostile) and Bars.IsHidden(unnamed) and Bars.IsHidden(shortcuts), "the stray bars")
    shortcuts:Show(); assert(not shortcuts:IsVisible(), "shown by the game: still not drawn")
    assert(not Bars.IsHidden(extra), "the extra action button stays (the touch screen does not replace it)")
    assert(not Bars.IsHidden(plain), "a window with plain buttons stays")
    for _, f in ipairs(Stub.allFrames()) do
        local name = f.GetName and f:GetName()
        if type(name) == "string" and name:find("^TouchPlay") then assert(not Bars.IsHidden(f), name .. " is ours") end
    end
    assert(ns.root:GetParent() == UIParent and ns.root:IsShown())
    local names = table.concat(Bars.Strays(), ",")
    assert(names:find("SomeGamepadTargetingBar", 1, true) and names:find("<unnamed>", 1, true), names)
    -- a bar made later (its add-on loads): found at ADDON_LOADED
    local late = CreateFrame("Frame", "LateBar", UIParent); actionButton(late, 3)
    Stub.fire("ADDON_LOADED", "Blizzard_Something"); Stub.advance(0.3)
    assert(Bars.IsHidden(late))
    -- in a fight the move waits
    local fightBar = CreateFrame("Frame", "FightBar", UIParent); actionButton(fightBar, 4)
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.fire("ADDON_LOADED", "X"); Stub.advance(0.3)
    assert(not Bars.IsHidden(fightBar), "nothing moves in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Bars.IsHidden(fightBar), "after the fight")
    -- Edit Mode and Off give them back
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(hostile:GetParent() == UIParent and unnamed:GetParent() == UIParent)
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(Bars.IsHidden(hostile))
    Bars:Restore()
    assert(hostile:GetParent() == UIParent and late:GetParent() == UIParent and shortcuts:GetParent() == UIParent)
    assert(not ns.paused, ns.lastError)
end)

T("touch_frames_lists_what_is_drawn_at_a_point", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local probe = CreateFrame("Frame", "ProbeWindow", UIParent)
    ns.Anchor(probe, "TL", 600, 800, nil)
    probe.touchAnchor = { x = 600, y = 800, w = 200, h = 50 }
    SlashCmdList.TOUCHPLAY("frames 650 820")
    local log = TouchPlayDB.framelog
    assert(log and log[1]:find("frames at 650, 820", 1, true), log and log[1])
    local text = table.concat(log, "\n")
    assert(text:find("ProbeWindow", 1, true), text)
    assert(text:find("hidden as stray action bars:", 1, true))
    SlashCmdList.TOUCHPLAY("frames 10 10")
    assert(not table.concat(TouchPlayDB.framelog, "\n"):find("ProbeWindow", 1, true), "not at another point")
    Stub.pointer(650, 1024 - 820)                   -- the pointer (a tap moved it there): screen units
    SlashCmdList.TOUCHPLAY("frames")
    assert(table.concat(TouchPlayDB.framelog, "\n"):find("ProbeWindow", 1, true))
    assert(TouchPlayDB.framelog[1]:find("the pointer", 1, true))
    assert(not ns.paused, ns.lastError)
end)

-- iPad run 7: "/touch frames causes some sort of bug" (BugSack's alert as it was typed). A frame whose rect is hidden
-- from add-ons, whose getter throws, or that is forbidden must not raise an error, and the walk calls nothing on other
-- frames but read-only getters (never a protected function); one line in chat, the full list saved; refused in a fight.
local GETTERS = { GetName = true, GetObjectType = true, GetParent = true, IsShown = true, IsVisible = true,
    IsForbidden = true, GetRect = true, GetEffectiveScale = true, GetFrameStrata = true, GetFrameLevel = true }

-- The stub's shared widget method table (the FrameMeta __index closure's upvalue `Frame`).
local function widgetMethods()
    local probe = CreateFrame("Frame")
    local index = getmetatable(probe).__index
    for i = 1, 20 do
        local name, value = debug.getupvalue(index, i)
        if not name then break end
        if name == "Frame" then return value end
    end
    error("no Frame table")
end

T("touch_frames_is_safe_and_quiet", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local probe = CreateFrame("Frame", "ProbeWindow", UIParent)
    ns.Anchor(probe, "TL", 600, 800, nil)
    probe.touchAnchor = { x = 600, y = 800, w = 200, h = 50 }
    -- a frame whose rect is a secret value, one whose GetRect throws, one forbidden whose getters throw
    local secret = CreateFrame("Frame", "SecretRect", UIParent)
    secret.GetRect = function() return Stub.secret(), Stub.secret(), Stub.secret(), Stub.secret() end
    local throws = CreateFrame("Frame", "ThrowingRect", UIParent)
    throws.GetRect = function() error("no rect for you") end
    local forbidden = CreateFrame("Frame", "ForbiddenOne", UIParent)
    forbidden.IsForbidden = function() return true end
    forbidden.GetName = function() error("forbidden") end
    forbidden.IsVisible = function() error("forbidden") end
    local secretName = CreateFrame("Frame", nil, probe)
    secretName.GetName = function() return Stub.secret() end
    secretName.GetFrameLevel = function() return Stub.secret() end
    -- record every call on a frame that is not a read-only getter, and every protected global
    local Frame, calls, saved = widgetMethods(), {}, {}
    local mine = {}
    for name, fn in pairs(Frame) do
        if type(fn) == "function" and not GETTERS[name] then
            saved[name] = fn
            Frame[name] = function(self, ...)
                if not mine[self] then calls[#calls + 1] = name .. " on " .. tostring(rawget(self, "name")) end
                return fn(self, ...)
            end
        end
    end
    local protectedCalls = 0
    _G.SetPreferredGamepadInteractTarget = function() protectedCalls = protectedCalls + 1 end
    local printed, realPrint = {}, ns.Print       -- our own chat lines are not the walk's
    ns.Print = function(text) printed[#printed + 1] = text end
    local ok, err = pcall(SlashCmdList.TOUCHPLAY, "frames 650 820")
    local ok2, err2 = pcall(SlashCmdList.TOUCHPLAY, "frames")
    for name, fn in pairs(saved) do Frame[name] = fn end
    ns.Print = realPrint
    assert(ok and ok2, tostring(err or err2))
    assert(#calls == 0, "only getters on the game's frames: " .. table.concat(calls, ", "))
    assert(protectedCalls == 0)
    assert(#printed == 2, "one line a command: " .. #printed)
    assert(printed[1]:find("frames at 650, 820", 1, true) and printed[1]:find("ProbeWindow", 1, true), printed[1])
    local text = table.concat(TouchPlayDB.framelog, "\n")
    assert(not text:find("SecretRect", 1, true) and not text:find("ThrowingRect", 1, true)
        and not text:find("ForbiddenOne", 1, true), text)
    assert(TouchPlayDB.framelog[1]:find("the pointer", 1, true))
    -- in a fight: refused, nothing walked
    SlashCmdList.TOUCHPLAY("frames 650 820")
    local before = TouchPlayDB.framelog
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    SlashCmdList.TOUCHPLAY("frames 10 10")
    assert(TouchPlayDB.framelog == before and Stub.chat[#Stub.chat]:find("out of a fight", 1, true))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused, ns.lastError)
end)

Stub.done("bars")
