-- The Interface mobile add-on's game windows (addons/WolkaraRoue/Windows.lua), run outside the
-- game. A window that overflows the enlarged interface is made smaller, never larger. A quest
-- window keeps its size and is kept between the sticks, clear of the left stick that used to take
-- the "Complete quest" touch; a window too wide for that goes above the sticks; the world map
-- takes the whole screen with its top-right corner (the close button) on it. Protected windows
-- wait for the end of a fight; windows the game creates later are caught when it shows them.
--
-- usage: luajit test_mobile_addon_windows.lua <path to Windows.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_windows.lua <Windows.lua>")

local W, H, UI = 1000, 703, 1.7
local combat = false
InCombatLockdown = function() return combat end
UIParent = { GetWidth = function() return W end, GetHeight = function() return H end,
    GetEffectiveScale = function() return UI end }

local function Window(name, width, height, protected, parent)
    local frame = { name = name, width = width, height = height, scale = 1, shown = false,
        protected = protected, parent = parent or UIParent, points = 1, hooks = {}, scaled = 0 }
    function frame:GetName() return self.name end
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return self.protected end
    function frame:GetNumPoints() return self.points end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:SetScale(scale) self.scale = scale; self.scaled = self.scaled + 1 end
    function frame:GetParent() return self.parent end
    function frame:GetEffectiveScale() return self.scale * self.parent:GetEffectiveScale() end
    function frame:SetClampedToScreen(on) self.clamped = on end
    function frame:SetClampRectInsets(l, r, t, b) self.insets = { l, r, t, b } end
    function frame:HookScript(script, fn) self.hooks[script] = fn end
    function frame:Show() self.shown = true; if self.hooks.OnShow then self.hooks.OnShow(self) end end
    function frame:GetRight() return self.right end
    function frame:GetTop() return self.top end
    return frame
end

WorldMapFrame = Window("WorldMapFrame", 1100, 760)
-- Its close button sits astride the top-right corner: 6 units out to the right, 12 above.
WorldMapFrame.right, WorldMapFrame.top = 1100, 760
WorldMapFrame.BorderFrame = { CloseButton = { IsShown = function() return true end,
    GetRight = function() return 1106 end, GetTop = function() return 772 end,
    GetEffectiveScale = function() return WorldMapFrame:GetEffectiveScale() end } }
QuestFrame = Window("QuestFrame", 384, 512)
SpellBookFrame = Window("SpellBookFrame", 384, 512, true)
local panelHook
ShowUIPanel = function(frame) frame.shown = true end
hooksecurefunc = function(name, fn) assert(name == "ShowUIPanel"); panelHook = fn end
C_Timer = { After = function(_, fn) fn() end }
-- The game shows a panel: its own code, then the add-on's hook.
local function Open(frame) ShowUIPanel(frame); panelHook(frame) end

local handlers, module = {}, nil
local ns = { STICK_X = 0.12, STICK_Y = 0.222 }
function ns.Register(_, m) module = m; return m end
function ns.On(event, fn) handlers[event] = fn end
assert(loadfile(path))("WolkaraRoue", ns)
module:Init()
assert(panelHook, "the game's panels are not followed")

-- The window's scale against the interface, and the room it must leave, in interface units.
local function Rel(frame) return frame:GetEffectiveScale() / UI end
local function Room(frame)
    local s = Rel(frame)
    return { left = -frame.insets[1] * s, right = frame.insets[2] * s, top = frame.insets[3] * s, bottom = -frame.insets[4] * s }
end
local function Near(a, b) return math.abs(a - b) < 1e-6 end
local ring = 0.077 * H  -- the stick ring the app draws, measured on the Duo

-- A quest window: as big as before, kept between the sticks, the whole height of the screen.
Open(QuestFrame)
local room = Room(QuestFrame)
assert(Near(Rel(QuestFrame), 1) and QuestFrame.clamped, "the quest window changed size")
assert(room.left > W * ns.STICK_X + ring and Near(room.left, room.right), "the quest window may go under the left stick")
assert(room.bottom <= 12 and room.top > 0, "the quest window lost the bottom of the screen")
assert(QuestFrame.width + room.left + room.right <= W and QuestFrame.height + room.top + room.bottom <= H)

-- Too wide to fit between the sticks: smaller, above them, the whole width.
local auction = Window(nil, 1200, 600)
Open(auction)
room = Room(auction)
assert(Rel(auction) < 1 and room.bottom > H * ns.STICK_Y + ring and room.left <= 12, "a wide window is not above the sticks")
assert(auction.width * Rel(auction) + room.left + room.right <= W + 1e-6)
assert(auction.height * Rel(auction) + room.top + room.bottom <= H + 1e-6)

-- The world map: the whole screen, its close button (astride the top-right corner) on it.
WorldMapFrame:Show()
room = Room(WorldMapFrame)
local s = Rel(WorldMapFrame)
assert(s < 1 and WorldMapFrame.width * s + room.left + room.right <= W + 1e-6, "the map does not fit the screen")
assert(WorldMapFrame.height * s + room.top + room.bottom <= H + 1e-6)
assert(room.right >= 6 * s + 9 and room.top >= 12 * s + 9, "the map's close button can still leave the screen")
assert(s > 0.85, "the map was made smaller than the screen needs")

-- Never larger than the game made it, its own scale included.
local small = Window(nil, 300, 200)
small.scale = 0.8
Open(small)
assert(Near(small.scale, 0.8), "a window was enlarged")

-- A window inside a scaled parent gets the same size on screen.
local parent = { GetEffectiveScale = function() return UI * 1.25 end }
local inner = Window(nil, 384, 900, false, parent)
Open(inner)
assert(Near(Rel(inner) * inner.height + Room(inner).top + Room(inner).bottom, H), "the parent's scale was ignored")

-- A window sized by its anchors would follow its own scale: left alone.
local anchored = Window(nil, 2000, 2000)
anchored.points = 2
Open(anchored)
assert(anchored.scaled == 0 and anchored.insets == nil)

-- In combat a protected window waits for the end of the fight; the others fit at once.
combat = true
QuestFrame.shown, SpellBookFrame.shown = false, false
QuestFrame.scale, SpellBookFrame.scale = 1, 1
SpellBookFrame.height = 900
Open(SpellBookFrame)
assert(SpellBookFrame.scaled == 0 and SpellBookFrame.insets == nil, "a protected window was touched in combat")
QuestFrame.height = 900
Open(QuestFrame)
assert(Rel(QuestFrame) < 1, "an unprotected window waited for the end of the fight")
combat = false
handlers.PLAYER_REGEN_ENABLED()
assert(Rel(SpellBookFrame) < 1 and SpellBookFrame.clamped, "the protected window was not fitted after the fight")

-- A window made by a module loaded later is watched once it exists.
TalentFrame = Window("TalentFrame", 384, 900)
ns.db = {}
handlers.ADDON_LOADED("Blizzard_TalentUI")
TalentFrame:Show()
assert(Rel(TalentFrame) < 1)

-- The interface size changes (Mobile panel): open windows fit again.
local before = Rel(QuestFrame)
H = 560
module:Layout()
assert(Rel(QuestFrame) < before, "an open window kept its old size")

print("mobile add-on game windows: never enlarged, quests between the sticks, wide ones above, map on the whole screen, protected after the fight, late windows caught: PASS")
