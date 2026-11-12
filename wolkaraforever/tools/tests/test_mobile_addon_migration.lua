-- A save written before release 1.0.4 (the interface that kept each side's spells in
-- `pages[1..6]`), loaded by 1.0.4 (one list per side, plus four gold-button wheels).
-- What is asserted: page 1 becomes that side's list, pages 2 and up go into the gold wheels
-- with their spells, nothing is invented or dropped, the old table is kept untouched so a
-- return to 0.9.1 still finds every spell, and loading the same save twice does not duplicate
-- anything.
--
-- usage: luajit test_mobile_addon_migration.lua <path to Core.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_migration.lua <Core.lua>")

local onEvent
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript(_, fn) onEvent = fn end
    return frame
end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
InCombatLockdown = function() return false end

local ns = {}
ns.T = ns.T or function(text) return text end
assert(loadfile(path))("WolkaraRoue", ns)

local function Load(saved)
    WolkaraRoueDB = saved
    ns.db = nil
    onEvent(nil, "ADDON_LOADED", "WolkaraRoue")
    return ns.db
end
local function Entry(list, index)
    local button = type(list) == "table" and list[index] or nil
    return type(button) == "table" and button.entry or nil
end
local function Wheel(db, index) return db.wheels[index] end
local function WheelIds(wheel)
    local ids = {}
    for _, entry in pairs(wheel.entries or {}) do ids[#ids + 1] = entry.id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- A 0.9.1 save: two pages on the right, two on the left, and the four gold wheels off.
local saved = {
    version = 2, layoutVersion = 8,
    wheels = {
        { enabled = false, slots = 8, entries = {} },
        { enabled = false, slots = 8, entries = {} },
        { enabled = false, slots = 8, entries = {} },
        { enabled = false, slots = 8, entries = {} },
    },
    free = { count = 4, wheels = 4, scale = 100, spread = 100, page = 1, pages = {
        [1] = { buttons = { [1] = { entry = { kind = "spell", id = 9 } } } },
        [2] = { buttons = { [1] = { entry = { kind = "spell", id = 300 } },
                            [3] = { entry = { kind = "spell", id = 500 } } } },
        [3] = { buttons = { [2] = { entry = { kind = "item", id = 77 } } } },
    } },
    freeLeft = { count = 4, wheels = 4, scale = 100, spread = 100, page = 2, pages = {
        [1] = { buttons = { [2] = { entry = { kind = "spell", id = 11 } },
                            [4] = { entry = { kind = "spell", id = 22 } } } },
        [2] = { buttons = { [1] = { entry = { kind = "spell", id = 33 } } } },
    } },
}
local originalRightPage2 = saved.free.pages[2].buttons[1].entry
local originalLeftPage2 = saved.freeLeft.pages[2].buttons[1].entry

local db = Load(saved)
-- Page 1 of each side is that side's list, in the slots it was in.
assert(Entry(db.free.buttons, 1).id == 9, "the right side's first page did not become its list")
assert(Entry(db.freeLeft.buttons, 2).id == 11 and Entry(db.freeLeft.buttons, 4).id == 22,
       "the left side's first page did not become its list, or lost its slots")
-- Pages 2 and 3 went into the gold wheels, which are now reachable.
assert(Wheel(db, 1).enabled == true and WheelIds(Wheel(db, 1)) == "33,300,500",
       "the second pages did not reach the first gold wheel")
assert(Wheel(db, 2).enabled == true and WheelIds(Wheel(db, 2)) == "77",
       "the third page did not reach the second gold wheel")
assert(Wheel(db, 3).enabled == false and Wheel(db, 4).enabled == false,
       "a wheel that held nothing was switched on")
-- The old table is still there, untouched, so going back to 0.9.1 finds everything.
assert(db.legacyPages and db.legacyPages.free.pages[2].buttons[1].entry == originalRightPage2,
       "the old right-hand pages were not kept")
assert(db.legacyPages.freeLeft.pages[2].buttons[1].entry == originalLeftPage2,
       "the old left-hand pages were not kept")
-- The same spells are still there, once each.
local seen, total = {}, 0
for _, wheel in ipairs(db.wheels) do
    for _, entry in pairs(wheel.entries) do
        seen[entry.id] = (seen[entry.id] or 0) + 1; total = total + 1
    end
end
assert(total == 4 and seen[300] == 1 and seen[500] == 1 and seen[77] == 1 and seen[33] == 1,
       "a gold wheel holds a spell twice, or lost one")
-- Loading the same save again changes nothing.
local again = Load(db)
assert(WheelIds(Wheel(again, 1)) == "33,300,500" and WheelIds(Wheel(again, 2)) == "77",
       "loading the merged save again duplicated its spells")
assert(Entry(again.free.buttons, 1).id == 9)

print("mobile add-on migration: a 0.9.1 save keeps every spell - page 1 becomes each side's list, later pages go into the gold wheels once, and the old table is kept for a rollback: PASS")
