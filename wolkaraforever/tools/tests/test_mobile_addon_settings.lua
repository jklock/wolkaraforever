-- The Interface mobile add-on's settings (addons/WolkaraRoue/Core.lua), run outside the game: a
-- 0.5 save moves to 0.6 once. The golden wheel's spells go into the left turning wheel, in its
-- free places and without duplicates, and the golden wheel is switched off but keeps them; the
-- left wheel turns and shows at least four spells; the chat goes back to its new place at the
-- bottom; the minimap gets its default size. A fresh install starts the same way, and a save
-- that has already moved is left as the player set it.
--
-- usage: luajit test_mobile_addon_settings.lua <path to Core.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_settings.lua <Core.lua>")

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
assert(loadfile(path))("WolkaraRoue", ns)
local function Load(saved)
    WolkaraRoueDB = saved
    ns.db = nil
    onEvent(nil, "ADDON_LOADED", "WolkaraRoue")
    return ns.db
end
local function Entry(db, index)
    local button = db.freeLeft.buttons[index]
    return type(button) == "table" and button.entry or nil
end

-- A 0.5 save: the golden wheel on, with spells; the left side had one spell and one moved slot.
local db = Load({
    version = 2, layoutVersion = 3,
    wheels = { { enabled = true, slots = 8, scale = 100, radius = 110, open = "bouton", entries = {
        [1] = { kind = "spell", id = 100 }, [2] = { kind = "spell", id = 200 },
        [4] = { kind = "item", id = 300 }, [5] = { kind = "spell", id = 500 } } } },
    free = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 2, buttons = { [1] = { entry = { kind = "spell", id = 9 } } } },
    freeLeft = { count = 0, scale = 100, spread = 100, buttons = {
        [1] = { entry = { kind = "spell", id = 500 } }, [2] = { pos = { point = "CENTER", x = 1, y = 2 } } } },
    chat = { custom = true, fontSize = 18, pos = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40 } },
})
assert(db.layoutVersion == 4)
assert(db.wheels[1].enabled == false and db.wheels[1].entries[4].id == 300, "the golden wheel lost its spells or stayed on")
assert(db.freeLeft.turn == true and db.freeLeft.count == 4, "the left wheel does not turn with four spells")
assert(Entry(db, 1).id == 500, "the left wheel's own spell was replaced")
assert(Entry(db, 2).id == 100 and db.freeLeft.buttons[2].pos.x == 1, "a free place was not filled, or lost its position")
assert(Entry(db, 3).id == 200 and Entry(db, 4).kind == "item" and Entry(db, 4).id == 300)
assert(Entry(db, 5) == nil, "a spell already in the left wheel was added twice")
assert(db.chat.pos == nil and db.chat.fontSize == 18 and db.chat.tab == "talk", "the chat kept its old place")
assert(db.minimap.shown == true and db.minimap.scale == 60)
assert(db.free.turnOffset == 2 and db.free.buttons[1].entry.id == 9, "the right wheel changed")

-- More spells than four: the left wheel shows them all.
db = Load({ version = 2, layoutVersion = 3, wheels = { { enabled = true, slots = 8, entries = {
    { kind = "spell", id = 1 }, { kind = "spell", id = 2 }, { kind = "spell", id = 3 },
    { kind = "spell", id = 4 }, { kind = "spell", id = 5 }, { kind = "spell", id = 6 } } } } })
assert(db.freeLeft.count == 6 and Entry(db, 6).id == 6)

-- A fresh install: the same start, nothing to move.
db = Load(nil)
assert(db.layoutVersion == 4 and db.freeLeft.count == 4 and db.freeLeft.turn == true and Entry(db, 1) == nil)
for i = 1, ns.MAX_WHEELS do assert(db.wheels[i].enabled == false, "a golden wheel is on by default") end

-- Already moved: the player's own choices stay.
db.wheels[1].enabled = true
db.freeLeft.count = 2
db.chat.pos = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 90 }
db = Load(db)
assert(db.wheels[1].enabled == true and db.freeLeft.count == 2 and db.chat.pos.y == 90, "the move ran twice")

print("mobile add-on settings: 0.5 golden wheel moved into the left wheel once, no duplicate or overwrite, chat and minimap defaults: PASS")
