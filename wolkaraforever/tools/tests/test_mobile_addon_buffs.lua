-- The Interface mobile add-on's player auras (addons/WolkaraRoue/Buffs.lua), run outside the game:
-- the game's own buff and debuff frames go small (65 %) just under the player bar at the top
-- left, debuffs under buffs - right of the bar is the target's place since 0.9.1 (asked on the
-- iPhone, 2026-11-09); the game moving them back (Edit Mode) is undone, never in combat but
-- right after it; with the health bars off they get the game's own place and size back.
--
-- usage: luajit test_mobile_addon_buffs.lua <path to Buffs.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_buffs.lua <Buffs.lua>")

local combat = false
InCombatLockdown = function() return combat end
C_Timer = { After = function(_, fn) fn() end }
hooksecurefunc = function(object, method, hook)
    local original = object[method]
    object[method] = function(...) local result = original(...); hook(...); return result end
end

local function AuraFrame(name)
    local frame = { name = name, scale = 1, systemAnchored = 0 }
    function frame:SetScale(scale) self.scale = scale end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ApplySystemAnchor()
        self.systemAnchored = self.systemAnchored + 1
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", "MinimapCluster", "TOPLEFT", -10, 0)
    end
    return frame
end
BuffFrame, DebuffFrame = AuraFrame("BuffFrame"), AuraFrame("DebuffFrame")

local handlers, module = {}, nil
local ns = { HudPlayer = { name = "WolkaraMobilePlayer" } }
function ns.Register(_, m) module = m; return m end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end
assert(loadfile(path))("WolkaraRoue", ns)

ns.db = { hud = { enabled = true } }
module:Init()
module:Layout()
-- Under the bar: its left edge, a few units below it (4 at the screen's scale).
local function Beside()
    return BuffFrame.scale == 0.65 and BuffFrame.point[1] == "TOPLEFT" and BuffFrame.point[2] == ns.HudPlayer
        and BuffFrame.point[3] == "BOTTOMLEFT" and BuffFrame.point[4] == 0 and math.abs(BuffFrame.point[5] * 0.65 + 4) < 1e-9
        and DebuffFrame.scale == 0.65 and DebuffFrame.point[2] == BuffFrame and DebuffFrame.point[3] == "BOTTOMLEFT"
end
assert(Beside(), "the auras did not move under the player bar")

-- The game puts them back by itself: ours again at once.
BuffFrame:ApplySystemAnchor()
assert(Beside(), "the game's own anchor stayed")
handlers.EDIT_MODE_LAYOUTS_UPDATED()
assert(Beside())

-- In combat nothing moves; the fight over, they are put back.
combat = true
BuffFrame:ApplySystemAnchor()
assert(BuffFrame.point[2] == "MinimapCluster", "moved in combat")
combat = false
handlers.PLAYER_REGEN_ENABLED()
assert(Beside(), "not put back after the fight")

-- Health bars off: the game's place and size come back, and stay.
ns.db.hud.enabled = false
local before = BuffFrame.systemAnchored
module:Layout()
assert(BuffFrame.scale == 1 and DebuffFrame.scale == 1 and BuffFrame.systemAnchored == before + 1)
assert(BuffFrame.point[2] == "MinimapCluster")
BuffFrame:ApplySystemAnchor()
assert(BuffFrame.point[2] == "MinimapCluster" and BuffFrame.scale == 1)

print("mobile add-on player auras: small under the player bar, debuffs under them, game re-anchoring undone out of combat, given back with the bars off: PASS")
