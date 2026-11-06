-- The Interface mobile add-on's minimap (addons/WolkaraRoue/Minimap.lua), run outside the game:
-- the minimap and everything round it take the size chosen in the Mobile panel (60 % by
-- default), are put away into an invisible frame when it is switched off and come back to their
-- own parent when it is switched on again; the game's Edit Mode setting its own size is undone.
--
-- usage: luajit test_mobile_addon_minimap.lua <path to Minimap.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_minimap.lua <Minimap.lua>")

local combat = false
InCombatLockdown = function() return combat end
UIParent = { name = "UIParent" }
local created = {}
CreateFrame = function()
    local frame = { shown = true }
    function frame:Hide() self.shown = false end
    created[#created + 1] = frame
    return frame
end
MinimapCluster = { parent = UIParent, scale = 1 }
function MinimapCluster:GetParent() return self.parent end
function MinimapCluster:SetParent(parent) self.parent = parent end
function MinimapCluster:SetScale(scale) self.scale = scale end
C_Timer = { After = function(_, fn) fn() end }

local handlers, module = {}, nil
local ns = {}
function ns.Register(_, m) module = m; return m end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end
assert(loadfile(path))("WolkaraRoue", ns)
local hider = created[1]
assert(hider and hider.shown == false, "no invisible frame to put the minimap away in")

ns.db = { minimap = { shown = true, scale = 60 } }
module:Layout()
assert(MinimapCluster.scale == 0.6 and MinimapCluster.parent == UIParent, "the minimap kept the interface's size")

-- Switched off: away in the invisible frame; on again: back where it was, at its size.
ns.db.minimap.shown = false
module:Layout()
assert(MinimapCluster.parent == hider)
module:Layout()
assert(MinimapCluster.parent == hider, "put away twice")
ns.db.minimap.shown, ns.db.minimap.scale = true, 90
module:Layout()
assert(MinimapCluster.parent == UIParent and MinimapCluster.scale == 0.9, "the minimap did not come back")

-- The game's Edit Mode sets its own size: ours again, but not in combat.
MinimapCluster.scale = 1.2
handlers.EDIT_MODE_LAYOUTS_UPDATED()
assert(MinimapCluster.scale == 0.9)
MinimapCluster.scale = 1.2
combat = true
handlers.PLAYER_ENTERING_WORLD()
assert(MinimapCluster.scale == 1.2, "the minimap was changed in combat")
combat = false
handlers.PLAYER_ENTERING_WORLD()
assert(MinimapCluster.scale == 0.9)

print("mobile add-on minimap: chosen size, put away and back to its parent, Edit Mode undone out of combat: PASS")
