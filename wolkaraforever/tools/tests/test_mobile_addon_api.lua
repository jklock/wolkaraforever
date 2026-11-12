-- The Interface mobile add-on's game-API wrappers (addons/WolkaraRoue/Core.lua), run outside
-- the game. Every value these read can be absent on a client that does not have the call, or
-- secret: a spell that does not exist, a cooldown the game will not give, an item the client
-- has never seen. What is asserted: each wrapper answers "I do not know" the way the interface
-- needs - nil, an empty count, "usable" with no reason - and never raises, so one unavailable
-- value cannot take the whole interface down with it.
--
-- usage: luajit test_mobile_addon_api.lua <path to Core.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_api.lua <Core.lua>")

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

-- 1. Nothing at all: no C_* namespace and no older global. Every read is guarded.
local target = false
UnitExists = function() return target end
assert(ns.SpellName(1) == nil and ns.SpellIcon(1) == nil and ns.SpellCooldown(1) == nil)
assert(ns.ItemIcon(1) == nil and ns.ItemName(1) == nil and ns.ItemSpell(1) == nil)
assert(ns.ItemCooldown(1) == nil and ns.ItemCount(1) == 0)
-- An unknown usability never stops a cast: the click still goes to the game.
local usable, noMana = ns.SpellUsable(1)
assert(usable == true and noMana == false)
assert(ns.SpellInRange(1) == nil)

-- 2. The older globals, which answer with more than one value.
GetSpellInfo = function() return "Sort", nil, "icon", 0, 0, 0, 1 end
GetSpellTexture = function() return "tex" end
GetSpellCooldown = function() return 5, 10, 1 end
GetItemIcon = function() return "itemTex" end
GetItemInfo = function() return "Objet", "lien", 1, 1, 1 end
GetItemSpell = function() return "Sort d'objet" end
GetItemCooldown = function() return 1, 2, 1 end
GetItemCount = function() return 7 end
assert(ns.SpellName(1) == "Sort" and ns.SpellIcon(1) == "tex")
assert(select(1, ns.SpellCooldown(1)) == 5 and select(2, ns.SpellCooldown(1)) == 10)
assert(ns.ItemName(1) == "Objet" and ns.ItemIcon(1) == "itemTex")
assert(ns.ItemSpell(1) == "Sort d'objet" and ns.ItemCount(1) == 7)
IsUsableSpell = function(name) return name == "Sort", false end
assert(select(1, ns.SpellUsable(1)) == true)
-- In range is only asked with a target, and its 1/0/nil become true/false/nil.
target = true
IsSpellInRange = function() return 1 end
assert(ns.SpellInRange(1) == true)
IsSpellInRange = function() return 0 end
assert(ns.SpellInRange(1) == false)
IsSpellInRange = function() return nil end
assert(ns.SpellInRange(1) == nil)

-- 3. The modern namespace, which can answer nil, an empty table or a secret value.
C_Spell = {
    GetSpellName = function() return nil end,
    GetSpellTexture = function() return nil end,
    GetSpellCooldown = function() return { startTime = nil, duration = nil } end,
    IsSpellUsable = function() return nil, nil end,
    IsSpellInRange = function() return nil end,
}
local startTime, duration = ns.SpellCooldown(1)
assert(startTime == nil and duration == nil, "a secret cooldown became a number")
assert(select(1, ns.SpellUsable(1)) == nil, "a secret usability became a boolean")
assert(ns.SpellInRange(1) == nil)
assert(ns.SpellName(1) == nil and ns.SpellIcon(1) == nil)
-- A cooldown that answers with no table at all is passed through, not indexed.
C_Spell.GetSpellCooldown = function() return nil end
assert(ns.SpellCooldown(1) == nil)

-- 4. Nothing on the cursor is no entry, and a pet ability is refused with a word rather than
-- an entry the slot could not cast.
C_Item = nil
GetCursorInfo = function() return nil end
assert(ns.CursorEntry() == nil)
GetCursorInfo = function() return "spell", nil, "pet", 1 end
assert(ns.CursorEntry() == nil)
GetCursorInfo = function() return "spell", nil, "book", 75 end
local entry = ns.CursorEntry()
assert(entry and entry.kind == "spell" and entry.id == 75)
GetCursorInfo = function() return "item", 6948 end
entry = ns.CursorEntry()
assert(entry and entry.kind == "item" and entry.id == 6948)
GetCursorInfo = function() return "totem", 1 end
assert(ns.CursorEntry() == nil, "an unknown cursor kind became an entry")

print("mobile add-on game API: absent calls, an unknown spell, a secret cooldown, a secret usability, an unknown range, a pet ability on the cursor and an unknown cursor kind all answer 'I do not know' without raising: PASS")
