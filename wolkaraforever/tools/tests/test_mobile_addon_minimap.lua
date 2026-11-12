-- The Interface mobile add-on's minimap (addons/WolkaraRoue/Minimap.lua), run outside the game:
-- the minimap and everything round it take the size chosen in the Mobile panel (60 % by
-- default), are put away into an invisible frame when it is switched off and come back to their
-- own parent when it is switched on again; the game's Edit Mode setting its own size is undone.
-- By finger: "+" and "-" beside it change its size in steps of 10 % (30 to 150 %, never in
-- combat), and the wheel the app sends for a pinch over it zooms it within the game's levels.
-- A touch on it opens the world map (the right button keeps the game's own use).
--
-- usage: luajit test_mobile_addon_minimap.lua <path to Minimap.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_minimap.lua <Minimap.lua>")

local combat = false
InCombatLockdown = function() return combat end
UIParent = { name = "UIParent" }
local created = {}
local function Frame()
    local frame = { shown = true, scripts = {} }
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:SetSize() end
    function frame:SetFrameStrata() end
    function frame:SetPoint(...) self.point = { ... } end
    return frame
end
CreateFrame = function()
    local frame = Frame()
    created[#created + 1] = frame
    return frame
end
local gameUp, mapOpened = 0, 0
ToggleWorldMap = function() mapOpened = mapOpened + 1 end
Minimap = { zoom = 2, levels = 6, wheel = false, scripts = { OnMouseUp = function() gameUp = gameUp + 1 end } }
function Minimap:GetZoom() return self.zoom end
function Minimap:SetZoom(zoom) self.zoom = zoom end
function Minimap:GetZoomLevels() return self.levels end
function Minimap:EnableMouseWheel(on) self.wheel = on end
function Minimap:GetScript(name) return self.scripts[name] end
function Minimap:SetScript(name, fn) self.scripts[name] = fn end
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
local changes, buttons = 0, {}
function ns.MarkChanged() changes = changes + 1 end
function ns.UIButton(_, text, _, _, onClick)
    local button = Frame()
    button.click = onClick
    buttons[text] = button
    return button
end
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

-- The size buttons, beside the minimap, shown with it.
local sizer = created[2]
assert(sizer and buttons["+"] and buttons["-"], "no size buttons")
assert(sizer.point[1] == "TOPRIGHT" and sizer.point[2] == Minimap and sizer.point[3] == "TOPLEFT")
assert(sizer.shown)
buttons["+"].click()
assert(ns.db.minimap.scale == 100 and MinimapCluster.scale == 1 and changes == 1)
for _ = 1, 10 do buttons["+"].click() end
assert(ns.db.minimap.scale == 150 and changes == 6, "grew past 150 %")
for _ = 1, 20 do buttons["-"].click() end
assert(ns.db.minimap.scale == 30 and MinimapCluster.scale == 0.3, "shrank past 30 %")
combat = true
buttons["+"].click()
assert(ns.db.minimap.scale == 30, "resized in combat")
combat = false
ns.db.minimap.shown = false
module:Layout()
assert(not sizer.shown, "the size buttons stayed without the minimap")
ns.db.minimap.shown = true
module:Layout()
assert(sizer.shown)

-- A pinch over the minimap arrives as the wheel: one zoom level a notch, within the game's levels.
assert(Minimap.wheel == true and Minimap.scripts.OnMouseWheel, "the minimap does not take the wheel")
local zoom = Minimap.scripts.OnMouseWheel
zoom(Minimap, 1)
assert(Minimap.zoom == 3)
for _ = 1, 5 do zoom(Minimap, 1) end
assert(Minimap.zoom == 5, "zoomed past the last level")
for _ = 1, 9 do zoom(Minimap, -1) end
assert(Minimap.zoom == 0, "zoomed out past the first level")

-- A touch on the minimap opens the world map; its right button keeps the game's own use.
local up = Minimap.scripts.OnMouseUp
up(Minimap, "LeftButton")
assert(mapOpened == 1 and gameUp == 0, "a touch on the minimap did not open the map")
up(Minimap, "RightButton")
assert(mapOpened == 1 and gameUp == 1, "the right button lost the game's own use")

print("mobile add-on minimap: chosen size, put away and back to its parent, Edit Mode undone out of combat, +/- size by finger, pinch zooms it, a touch opens the map: PASS")
