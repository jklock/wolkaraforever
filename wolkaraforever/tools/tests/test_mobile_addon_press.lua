-- The Interface mobile add-on's touch on a spell (addons/WolkaraRoue/Actions.lua), run outside
-- the game: the clicks the app gives the game reach a spell button's PreClick and PostClick,
-- which decide - before the game's secure click acts - whether the touch casts.
--   - A touch casts. This interface's Customise is a mode of its own (the Customize button, the
--     Duo Edit button and EditMode.lua), so a press on a spell never turns it on: a right click
--     casts like a touch, out of combat and in it.
--   - While a slot is being edited, a touch casts nothing and opens the picker for that slot.
--   - Something held on the cursor (an object taken from a bag) and a touch on a spell to cast
--     it: the spell is cast and stays. The held thing goes only into an empty slot, or into any
--     slot while customising, or when dragged there on purpose.
--
-- usage: luajit test_mobile_addon_press.lua <path to Actions.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_press.lua <Actions.lua>")

local combat, cursor = false, nil
InCombatLockdown = function() return combat end
GetCursorInfo = function() return cursor end
ClearCursor = function() cursor = nil end
GetTime = function() return 0 end

-- A frame: its attributes and scripts kept; any other method answers nothing, as a stand-in.
local function Frame(kind)
    local frame = { kind = kind, attributes = {}, scripts = {} }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:CreateTexture() return Frame("Texture") end
    function frame:CreateFontString() return Frame("FontString") end
    function frame:GetFrameLevel() return 1 end
    function frame:GetName() return "WolkaraMobileFree1" end
    setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
    return frame
end
CreateFrame = function(kind) return Frame(kind) end

local ns = { editing = false, CIRCLE = "circle", QUESTION = "?" }
local assigned, picked, opened, changed = {}, {}, 0, 0
function ns.Disc() return Frame("Texture") end
function ns.Circle() return true end
function ns.Label() return Frame("FontString") end
function ns.SpellName(id) return "Sort " .. id end
function ns.SpellIcon(id) return "icon" .. id end
function ns.SpellCooldown() return 0, 0, true end
function ns.SpellUsable() return true, false end
function ns.SpellInRange() return nil end
function ns.ItemName(id) return "Objet " .. id end
function ns.ItemIcon(id) return "item" .. id end
function ns.ItemCount() return 1 end
function ns.ItemCooldown() return 0, 0, true end
function ns.ItemSpell() return nil end
function ns.CursorEntry() return cursor and { kind = "item", id = 6948 } end
function ns.PickupEntry(entry) picked[#picked + 1] = entry end
function ns.MarkChanged() changed = changed + 1 end
function ns.Print() end
ns.Picker = { Open = function() opened = opened + 1; return true end, Close = function() end }
C_XMLUtil = { GetTemplateInfo = function() return {} end }
assert(loadfile(path))("WolkaraRoue", ns)

local entry = { kind = "spell", id = 75 }
local button = ns.CreateActionButton("WolkaraMobileFree1", nil, 64,
    function() return entry end, function(value) entry = value; assigned[#assigned + 1] = value end)
ns.ApplyButton(button)
assert(button.attributes.type == "spell" and button.attributes.spell == "Sort 75")

-- How the game clicks it: PreClick, the secure click (which casts if a type is set), PostClick,
-- for the press and for the release.
local cast = 0
local function Click(mouse)
    for _, down in ipairs({ true, false }) do
        button.scripts.PreClick(button, mouse, down)
        if not down and button.attributes.type == "spell" then cast = cast + 1 end
        button.scripts.PostClick(button, mouse, down)
    end
end

-- A touch casts.
Click("LeftButton")
assert(cast == 1 and opened == 0)
-- A right click casts like a touch: Customise is its own mode here, never a press on a spell.
Click("RightButton")
assert(cast == 2 and not ns.editing)
-- In combat the same.
combat = true
Click("RightButton")
assert(cast == 3 and not ns.editing)
combat = false

-- While a slot is being edited, a touch never casts; it opens the picker for that slot.
ns.slotEditing = true
ns.ApplyButton(button)
Click("LeftButton")
assert(cast == 3 and opened == 1, "a touch while editing a slot cast the spell")
ns.slotEditing = false
ns.ApplyButton(button)

-- An object held on the cursor, and a touch on the spell to cast it: cast, the spell stays.
cursor = "item"
Click("LeftButton")
assert(cast == 4 and #assigned == 0 and entry.id == 75, "the held object replaced the spell")
-- Dragged onto it on purpose, it takes the slot, and the spell goes to the cursor.
button.scripts.OnReceiveDrag(button)
assert(entry.kind == "item" and entry.id == 6948 and picked[1].id == 75 and changed == 1)
-- Into an empty slot, a touch puts it.
entry = nil
cursor = "item"
ns.ApplyButton(button)
Click("LeftButton")
assert(entry and entry.id == 6948 and changed == 2, "a touch did not fill the empty slot")
-- While customising, any slot takes it.
entry = { kind = "spell", id = 75 }
cursor = "item"
ns.editing = true
ns.ApplyButton(button)
Click("LeftButton")
assert(entry.kind == "item" and changed == 3)
-- And a touch with nothing held opens the picker there.
cursor = nil
Click("LeftButton")
assert(opened == 2)
ns.editing = false

print("mobile add-on touch: a touch casts, a right click casts like it (Customise is its own mode), a slot being edited never casts and opens the picker, an object on the cursor never replaces a spell touched to cast, fills an empty slot, any slot while customising or when dragged there: PASS")
