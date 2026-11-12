-- The Interface mobile add-on's bags (addons/WolkaraRoue/Bags.lua), run outside the game. The
-- game opens its bags in the bottom-right corner, where the app keeps the camera stick and the
-- jump, and the jump caught touches meant for the bags ("quand j'ouvre les sacs le bouton de saut
-- fout la merde", iPhone, 2026-11-09). Until 0.7 only bags anchored to the screen's right edge
-- through UpdateContainerFrameAnchors moved. What is asserted now: whatever a stack of bags is
-- anchored to, once the game has placed it, a stack reaching into the right 36 % of the screen
-- slides left just out of it (never past the left edge), stacked bags following their first one;
-- a stack elsewhere does not move; nothing moves in combat, and it is placed when the fight ends;
-- it works with or without the game's UpdateContainerFrameAnchors, and the placement is noted.
--
-- usage: luajit test_mobile_addon_bags.lua <path to Bags.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_bags.lua <Bags.lua>")

local W, H, combat = 1000, 460, false
local SCALE = 1.25 -- the bags' own scale against UIParent's
UIParent = { GetWidth = function() return W end, GetHeight = function() return H end,
    GetEffectiveScale = function() return 1 end }
InCombatLockdown = function() return combat end
time = function() return 7 end
local later = {}
C_Timer = { After = function(_, fn) later[#later + 1] = fn end }
local function RunLater() local list = later; later = {}; for _, fn in ipairs(list) do fn() end end

-- A bag: its size in its own units, and its rectangle from its first anchor, which may be the
-- screen, another bag, or a frame of the game's own.
local Rect
local function Bag(name, shown, width, height)
    local bag = { name = name, shown = shown, w = width, h = height, hooks = {} }
    function bag:IsShown() return self.shown end
    function bag:GetNumPoints() return self.anchor and 1 or 0 end
    function bag:GetPoint() return unpack(self.anchor) end
    function bag:ClearAllPoints() self.anchor = nil end
    function bag:SetPoint(...) self.anchor = { ... } end
    function bag:GetEffectiveScale() return SCALE end
    function bag:GetRect() return Rect(self) end
    function bag:HookScript(script, fn) self.hooks[script] = fn end
    _G[name] = bag
    return bag
end
-- Where a bag is, in its own units, from its anchor (BOTTOMRIGHT/TOPRIGHT/BOTTOMLEFT only).
function Rect(bag)
    if not bag.anchor then return nil end
    local point, relative, relativePoint, x, y = unpack(bag.anchor)
    local rl, rb, rw, rh
    if relative == UIParent then
        rl, rb, rw, rh = 0, 0, W / SCALE, H / SCALE
    else
        rl, rb, rw, rh = relative:GetRect()
        if not rl then return nil end
    end
    local ax = relativePoint:find("RIGHT") and rl + rw or rl
    local ay = relativePoint:find("TOP") and rb + rh or rb
    ax, ay = ax + (x or 0), ay + (y or 0)
    local left = point:find("RIGHT") and ax - bag.w or ax
    local bottom = point:find("TOP") and ay - bag.h or ay
    return left, bottom, bag.w, bag.h
end
local function Right(bag) local l, _, w = Rect(bag); return (l + w) * SCALE end
local function Left(bag) return (Rect(bag)) * SCALE end

NUM_CONTAINER_FRAMES = 4
local game = { name = "the game's own frame", GetEffectiveScale = function() return SCALE end }
function game.GetRect() return W / SCALE - 160, 10, 150, 40 end
-- The backpack on a frame of the game's (not the screen's edge), a bag stacked above it, a
-- closed bag, and one the player keeps at the top left.
local backpack = Bag("ContainerFrame1", true, 180, 200)
local stacked = Bag("ContainerFrame2", true, 180, 150)
local closed = Bag("ContainerFrame3", false, 180, 150)
local apart = Bag("ContainerFrame4", true, 180, 150)
local function GamePlaces()
    backpack:SetPoint("BOTTOMRIGHT", game, "TOPRIGHT", 0, 6)
    stacked:SetPoint("BOTTOMRIGHT", backpack, "TOPRIGHT", 0, 4)
    closed:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 90)
    apart:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
end
GamePlaces()

local handlers, registered = {}, nil
local ns = { db = {} }
function ns.Register(_, module) registered = module; return module end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end
hooksecurefunc = nil   -- this client may not have UpdateContainerFrameAnchors either
assert(loadfile(path))("WolkaraRoue", ns)
registered:Init()
local limit = W * (1 - (registered.CLEAR or 0.36))

-- The game shows the backpack: once it has placed it, the stack slides out of the controls'
-- corner, just enough; the stacked bag follows it; the others stay.
assert(Right(backpack) > limit, "the test's backpack starts outside the corner")
local apartLeft = Left(apart)
backpack.hooks.OnShow()
assert(Right(backpack) > limit, "moved before the game had placed it")
RunLater()
assert(math.abs(Right(backpack) - limit) < 1e-6, "the backpack is still in the controls' corner")
assert(math.abs(Right(stacked) - limit) < 1e-6 and stacked.anchor[2] == backpack, "the stacked bag did not follow")
assert(Left(apart) == apartLeft, "a bag placed elsewhere moved")
assert(closed.anchor[2] == UIParent and closed.anchor[4] == -10, "a closed bag moved")
assert(ns.db.bagsSeen.moved == 1 and ns.db.bagsSeen.stacks == 2 and ns.db.bagsSeen.hook == false and ns.db.bagsSeen.after == 0.64)
-- Placed again by the game, again just out of the corner: nothing piles up.
GamePlaces()
backpack.hooks.OnShow(); RunLater()
assert(math.abs(Right(backpack) - limit) < 1e-6, "the move accumulated")

-- In combat nothing moves; when the fight ends it does.
GamePlaces()
combat = true
backpack.hooks.OnShow(); RunLater()
assert(Right(backpack) > limit, "a bag moved in combat")
combat = false
handlers.PLAYER_REGEN_ENABLED(); RunLater()
assert(math.abs(Right(backpack) - limit) < 1e-6, "the bag was not placed after the fight")

-- A stack too wide for the space left stops at the left edge.
backpack.w = 0.8 * W / SCALE
GamePlaces()
backpack.hooks.OnShow(); RunLater()
assert(math.abs(Left(backpack) - 8) < 1e-6, "a wide stack went past the left edge")
backpack.w = 180

-- With the game's UpdateContainerFrameAnchors, its every placement is followed too.
local hooked
UpdateContainerFrameAnchors = function() GamePlaces(); if hooked then hooked() end end
hooksecurefunc = function(name, fn) assert(name == "UpdateContainerFrameAnchors"); hooked = fn end
assert(loadfile(path))("WolkaraRoue", ns)
registered:Init()
UpdateContainerFrameAnchors(); RunLater()
assert(math.abs(Right(backpack) - limit) < 1e-6 and ns.db.bagsSeen.hook == true)

print("mobile add-on bags: a stack in the controls' corner slides just out of it whatever it hangs on, stacked bags follow, others stay, never past the left edge, never in combat, placed after the fight, with or without the game's anchoring function, noted: PASS")
