-- The Interface mobile add-on's save (addons/WolkaraRoue/Save.lua), run outside the game with
-- the few WoW functions it calls stubbed. What is asserted is when it reloads the interface -
-- the reload is what makes the game write WolkaraRoueDB - and that it never does so while the
-- player is fighting, choosing, setting up or still changing things.
--
-- usage: luajit test_mobile_addon_save.lua <path to Save.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_save.lua <Save.lua>")

local now, combat, reloads = 100, false, 0
local frames, printed, handlers = {}, {}, {}
local open = { picker = false, settings = false, menu = false }

GetTime = function() return now end
InCombatLockdown = function() return combat end
ReloadUI = function() reloads = reloads + 1 end
CreateFrame = function()
    local frame = {}
    function frame:SetScript(name, fn) self[name] = fn end
    frames[#frames + 1] = frame
    return frame
end

local ns = { db = {}, editing = false }
function ns.Print(message) printed[#printed + 1] = message end
function ns.On(event, fn) handlers[event] = fn end
ns.Picker = { IsOpen = function() return open.picker end }
ns.Settings = { IsOpen = function() return open.settings end }
ns.Menu = { IsOpen = function() return open.menu end }

assert(loadfile(path))("WolkaraRoue", ns)
local tick = ns.SaveTick

-- Nothing changed: nothing reloads, however long it waits.
assert(not tick(100) and not tick(1000) and reloads == 0)

-- A change saves once the player has left it alone for 4 s and nothing was open for 1.5 s.
now = 1000; ns.MarkChanged()
assert(ns.SavePending())
assert(not tick(1001) and not tick(1003.9) and reloads == 0)
assert(tick(1004) and reloads == 1 and ns.db.justSaved == true and not ns.SavePending())
assert(printed[#printed]:find("recharge"))
assert(not tick(1100) and reloads == 1)  -- once per change

-- Every new change starts the wait again.
now = 2000; ns.MarkChanged()
assert(not tick(2003))
now = 2003; ns.MarkChanged()
assert(not tick(2006.9) and tick(2007) and reloads == 2)

-- Never in combat, in the picker, the settings, the menu or Customize; then 1.5 s after the
-- last of them closes.
for _, busy in ipairs({ "combat", "picker", "settings", "menu", "editing" }) do
    local function set(on)
        if busy == "combat" then combat = on elseif busy == "editing" then ns.editing = on else open[busy] = on end
    end
    local before = reloads
    now = 3000; ns.MarkChanged(); set(true)
    assert(not tick(3010) and not tick(3100), busy)
    set(false)
    assert(not tick(3100.5) and not tick(3101.9), busy)
    assert(tick(3102) and reloads == before + 1, busy)
end

-- The frame checks twice a second, through the same decision.
local before = reloads
now = 4000; ns.MarkChanged()
now = 4010
frames[1].OnUpdate(frames[1], 0.3)
assert(reloads == before)
frames[1].OnUpdate(frames[1], 0.3)
now = 4011.6
frames[1].OnUpdate(frames[1], 0.6)
assert(reloads == before + 1)

-- After the reload the add-on says it saved, once, and does not save again for that.
handlers.PLAYER_LOGIN()
assert(ns.db.justSaved == nil and printed[#printed] == "réglages enregistrés.")
assert(not ns.SavePending() and not tick(5000))

-- Before the settings are loaded a change is not recorded.
local db = ns.db; ns.db = nil
ns.MarkChanged()
assert(not ns.SavePending())
ns.db = db

print("mobile add-on save: waits for quiet, never in combat or open panels, one reload per change, said after: PASS")
