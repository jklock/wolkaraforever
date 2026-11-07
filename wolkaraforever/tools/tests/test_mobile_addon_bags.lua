-- The Interface mobile add-on's bags (addons/WolkaraRoue/Bags.lua), run outside the game: after
-- the game places its bags in the bottom-right corner, those anchored to the right edge move left
-- past the wheel; bags stacked on another bag, closed bags and bags placed elsewhere are left
-- alone; nothing moves in combat, and the move happens when the fight ends.
--
-- usage: luajit test_mobile_addon_bags.lua <path to Bags.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_bags.lua <Bags.lua>")

local W, combat, hooked = 800, false, nil
UIParent = { GetWidth = function() return W end }
InCombatLockdown = function() return combat end
local function Bag(shown, point, relative, relativePoint, x, y)
    local bag = { shown = shown, anchor = { point, relative, relativePoint, x, y } }
    function bag:IsShown() return self.shown end
    function bag:GetNumPoints() return self.anchor[1] and 1 or 0 end
    function bag:GetPoint() return unpack(self.anchor) end
    function bag:ClearAllPoints() self.anchor = {} end
    function bag:SetPoint(...) self.anchor = { ... } end
    return bag
end
NUM_CONTAINER_FRAMES = 4
ContainerFrame1 = Bag(true, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 90)
ContainerFrame2 = Bag(true, "BOTTOMRIGHT", ContainerFrame1, "TOPRIGHT", 0, 4)
ContainerFrame3 = Bag(false, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 90)
ContainerFrame4 = Bag(true, "TOPLEFT", UIParent, "TOPLEFT", 20, -20)
local placed = 0
UpdateContainerFrameAnchors = function()
    placed = placed + 1
    ContainerFrame1:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 90)
    if hooked then hooked() end
end
hooksecurefunc = function(name, fn) assert(name == "UpdateContainerFrameAnchors"); hooked = fn end
-- The module registers its table through ns.Register; keep it to call Init as the add-on does.
local handlers, registered = {}, nil
local ns = {}
function ns.Register(_, module) registered = module; return module end
function ns.On(event, fn) handlers[event] = fn end
assert(loadfile(path))("WolkaraRoue", ns)
registered:Init()
assert(hooked, "the bags are not followed")
local function X(bag) return bag.anchor[4] end

UpdateContainerFrameAnchors()
assert(X(ContainerFrame1) == -10 - W * 0.36, "the bottom-right bag did not move left")
assert(X(ContainerFrame2) == 0 and ContainerFrame2.anchor[2] == ContainerFrame1, "a stacked bag moved")
assert(X(ContainerFrame3) == -10, "a closed bag moved")
assert(X(ContainerFrame4) == 20, "a bag placed elsewhere moved")
UpdateContainerFrameAnchors()
assert(X(ContainerFrame1) == -10 - W * 0.36, "the move accumulated")

-- In combat nothing moves; when the fight ends the game places them again and they move.
combat = true
ContainerFrame1:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 90)
hooked()
assert(X(ContainerFrame1) == -10)
combat = false
local before = placed
handlers.PLAYER_REGEN_ENABLED()
assert(placed == before + 1 and X(ContainerFrame1) == -10 - W * 0.36)
handlers.PLAYER_REGEN_ENABLED()
assert(placed == before + 1, "placed again with nothing pending")

print("mobile add-on bags: moved left of the wheel, stacked/closed/elsewhere untouched, never in combat, caught up after: PASS")
