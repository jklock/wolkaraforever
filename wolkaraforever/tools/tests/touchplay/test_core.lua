-- Task 1: the core's guard, pause and restore, combat queue and /touch.
dofile("tests/stub.lua")

T("guard_error_pauses_and_restores", function()
    Stub.reset(); Stub.load("Core.lua")
    local restored = 0
    ns.Register("Bad", { Layout = function() error("boom") end, Restore = function() restored = restored + 1 end })
    Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.fire("PLAYER_LOGIN")
    assert(ns.paused == true and restored == 1, "paused and restored once")
    assert(Stub.printed("Touch screen paused, tap to report") == 1, "notice printed once")
    assert(ns.lastError and ns.lastError:find("boom"), "error kept")
    -- a second error in the same session shows no second notice
    ns.Pause("again")
    assert(Stub.printed("Touch screen paused, tap to report") == 1)
end)

T("pause_stops_other_modules", function()
    Stub.reset(); Stub.load("Core.lua")
    local laterLaid = 0
    ns.Register("Bad", { Layout = function() error("boom") end })
    ns.Register("Later", { Layout = function() laterLaid = laterLaid + 1 end })
    Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.fire("PLAYER_LOGIN")
    assert(laterLaid == 0, "a module after the broken one must not lay out over the restore")
end)

T("pause_in_combat_waits", function()
    Stub.reset(); Stub.load("Core.lua"); local restored = 0
    ns.Register("Bad", { Refresh = function() error("x") end, Restore = function() restored = restored + 1 end })
    Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.combat(true); ns.Each("Refresh")
    assert(ns.paused and restored == 0)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); assert(restored == 1)
end)

T("login_in_combat_defers_layout", function()
    Stub.reset(); Stub.load("Core.lua"); local laid = 0
    ns.Register("M", { Layout = function() laid = laid + 1 end })
    Stub.combat(true); Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.fire("PLAYER_LOGIN"); assert(laid == 0)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); assert(laid == 1)
end)

T("queue_same_key_replaces", function()
    Stub.reset(); Stub.load("Core.lua"); local log = {}
    Stub.combat(true)
    ns.Queue("k", function() log[#log + 1] = "first" end)
    ns.Queue("k", function() log[#log + 1] = "second" end)
    ns.Queue("other", function() log[#log + 1] = "other" end)
    assert(#log == 0)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(#log == 2 and log[1] == "second" and log[2] == "other")
    ns.Queue("k", function() log[#log + 1] = "now" end)
    assert(log[3] == "now", "out of combat it runs at once")
end)

T("slash_touch_toggles", function()
    Stub.reset(); Stub.load("Core.lua"); local restored, laid = 0, 0
    ns.Register("M", { Layout = function() laid = laid + 1 end, Restore = function() restored = restored + 1 end })
    Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.fire("PLAYER_LOGIN")
    assert(TouchPlayDB.enabled == true and laid == 1)
    SlashCmdList.TOUCHPLAY(""); assert(TouchPlayDB.enabled == false and restored >= 1)
    SlashCmdList.TOUCHPLAY(""); assert(TouchPlayDB.enabled == true and laid == 2)
end)

T("disabled_stays_off_after_reload", function()
    Stub.reset(); Stub.load("Core.lua"); local laid = 0
    Stub.fire("ADDON_LOADED", "TouchPlay"); Stub.fire("PLAYER_LOGIN")
    SlashCmdList.TOUCHPLAY("")
    Stub.reload(); ns.Register("M", { Layout = function() laid = laid + 1 end })
    Stub.fire("PLAYER_LOGIN")
    assert(TouchPlayDB.enabled == false and laid == 0)
end)

T("events_ignored_while_paused", function()
    Stub.reset(); Stub.load("Core.lua"); local seen = 0
    ns.On("BAG_UPDATE_DELAYED", function() seen = seen + 1 end)
    Stub.fire("ADDON_LOADED", "TouchPlay")
    Stub.fire("BAG_UPDATE_DELAYED"); assert(seen == 1)
    ns.Pause("test"); Stub.fire("BAG_UPDATE_DELAYED"); assert(seen == 1)
end)

Stub.done("core")
