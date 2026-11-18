-- TouchPlay: the way back to your corpse (rule 11, Task 13; mockups 14, 15, 80).
--
-- As a ghost an arrow at (683, 175) points to the corpse, with "Your corpse" and the distance in yards
-- and a compass word under it. A second, small arrow sits on the edge of the minimap ring (Hud's disc:
-- its centre and size are read from the frame, nothing is repeated here). Both hide when the corpse is
-- on no map we can read (inside an instance), when it is in range (the game's own "Resurrect now?"
-- takes over, mockup 15) and when you are alive.
--
-- The distance is plain arithmetic on two map positions and the map's size in yards
-- (C_Map.GetMapWorldSize), so there are no world coordinates and no axis to get wrong. The arrow turns
-- with the compass bearing and the way you face (GetPlayerFacing, counter-clockwise from north).
--
-- Updates come from events (death, release, zone changes, corpse in or out of range, the first and last
-- step, the first and last turn). While a ghost is moving or turning, and the arrow is shown, one 0.25 s
-- ticker keeps it pointing; it is cancelled the moment the ghost stops or the arrow hides. Nothing here
-- acts for the player.

local ADDON_NAME, ns = ...

local Corpse = ns.Register("Corpse", {})
local Kit = ns.Kit

ns.L["corpse.title"] = "Your corpse"
ns.L["corpse.distance"] = "%d yards, %s"
ns.L["corpse.n"] = "north"
ns.L["corpse.ne"] = "north-east"
ns.L["corpse.e"] = "east"
ns.L["corpse.se"] = "south-east"
ns.L["corpse.s"] = "south"
ns.L["corpse.sw"] = "south-west"
ns.L["corpse.w"] = "west"
ns.L["corpse.nw"] = "north-west"

-- Mockup 14: the arrow's centre, in layout units.
local ARROW_X, ARROW_Y, ARROW_D = 683, 175, 64
local EDGE_D, EDGE_INSET = 24, 8
local TICK_SECONDS = 0.25
local ARROW_ART = "Interface\\Minimap\\MinimapArrow"
local GOLD = { 1, 0.82, 0 }
local TWO_PI = 2 * math.pi
local WORDS = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

-- ---------------------------------------------------------------------------------------
-- Pure parts. Map positions are 0..1 (x east, y south); width and height are the map's size in yards.

function Corpse.Yards(px, py, cx, cy, width, height)
    local dx, dy = (cx - px) * width, (cy - py) * height
    return math.sqrt(dx * dx + dy * dy)
end

-- Compass bearing to the corpse in radians, clockwise from north (0 .. 2 pi).
function Corpse.Bearing(px, py, cx, cy, width, height)
    local east, north = (cx - px) * width, (py - cy) * height
    local angle = math.atan2(east, north)
    if angle < 0 then angle = angle + TWO_PI end
    return angle
end

-- The word for a bearing: one of eight, each 45 degrees wide.
function Corpse.Compass(bearing)
    local index = math.floor(bearing / (math.pi / 4) + 0.5) % 8 + 1
    return WORDS[index]
end

-- How far to turn a texture that points up so it points at the corpse: counter-clockwise radians, in
-- (-pi, pi]. `facing` is GetPlayerFacing (counter-clockwise from north), so the corpse lies
-- bearing + facing clockwise from where you look.
function Corpse.Rotation(bearing, facing)
    local turn = -(bearing + (facing or 0))
    turn = turn % TWO_PI
    if turn > math.pi then turn = turn - TWO_PI end
    return turn
end

-- Where a minimap-edge marker sits at `angle` (clockwise from up) on a ring: offsets from the centre.
function Corpse.EdgePoint(angle, radius)
    return math.sin(angle) * radius, math.cos(angle) * radius
end

-- ---------------------------------------------------------------------------------------
-- The arrow

local arrow = CreateFrame("Frame", nil, ns.root)
arrow:SetSize(ARROW_D, ARROW_D)
arrow:EnableMouse(false)
arrow:SetFrameLevel(12)
local arrowTexture = arrow:CreateTexture(nil, "ARTWORK")
arrowTexture:SetTexture(ARROW_ART)
arrowTexture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
arrowTexture:SetAllPoints(arrow)
local title = arrow:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(title, Kit.FONT_TITLE, 28, "")
title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
title:SetPoint("TOP", arrow, "BOTTOM", 0, -8)
local distance = arrow:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(distance, Kit.FONT_TITLE, 22, "")
distance:SetTextColor(1, 1, 1)
distance:SetPoint("TOP", title, "BOTTOM", 0, -4)
arrow:Hide()
Corpse.arrow, Corpse.arrowTexture, Corpse.title, Corpse.distance = arrow, arrowTexture, title, distance

-- The small one on the minimap ring.
local edge = CreateFrame("Frame", nil, ns.root)
edge:SetSize(EDGE_D, EDGE_D)
edge:EnableMouse(false)
edge:SetFrameLevel(14)
local edgeTexture = edge:CreateTexture(nil, "ARTWORK")
edgeTexture:SetTexture(ARROW_ART)
edgeTexture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
edgeTexture:SetAllPoints(edge)
edge:Hide()
Corpse.edge, Corpse.edgeTexture = edge, edgeTexture

local inRange, walking, turning, moving = false, false, false, false
local ticker

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function Hide()
    if arrow:IsShown() then arrow:Hide() end
    if edge:IsShown() then edge:Hide() end
    StopTicker()
end

local function Place()
    ns.Anchor(arrow, "TL", ARROW_X - ARROW_D / 2, ARROW_Y - ARROW_D / 2)
end

-- The corpse's place and your own on the current map: yards, bearing; nil when either is unknown.
local function Read()
    if not C_Map or not C_DeathInfo then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map or not Plain(map) then return nil end
    local me = C_Map.GetPlayerMapPosition(map, "player")
    local body = C_DeathInfo.GetCorpseMapPosition(map)
    if not me or not body then return nil end
    local width, height = C_Map.GetMapWorldSize(map)
    local px, py = me:GetXY()
    local cx, cy = body:GetXY()
    if not (Plain(px) and Plain(py) and Plain(cx) and Plain(cy) and Plain(width) and Plain(height)) then return nil end
    if type(px) ~= "number" or type(cx) ~= "number" or not width or width <= 0 then return nil end
    return Corpse.Yards(px, py, cx, cy, width, height), Corpse.Bearing(px, py, cx, cy, width, height)
end

-- How many yards to the corpse, or nil (alive, no map, instance). Rounded.
function Corpse.CurrentYards()
    local yards = Read()
    return yards and math.floor(yards + 0.5) or nil
end

local function IsGhost()
    local ghost = UnitIsGhost and UnitIsGhost("player")
    return Plain(ghost) and ghost and true or false
end

local function Rotates()
    return GetCVar and GetCVar("rotateMinimap") == "1"
end

local function Tick()
    if not ns.IsActive() then StopTicker(); return end
    ns.Guard("corpse tick", Corpse.Update)
end

function Corpse.Update()
    if not ns.IsActive() or inRange or not IsGhost() then Hide(); return end
    local yards, bearing = Read()
    if not yards then Hide(); return end
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    if not Plain(facing) or type(facing) ~= "number" then facing = 0 end
    local turn = Corpse.Rotation(bearing, facing)
    arrowTexture:SetRotation(turn)
    title:SetText(ns.T("corpse.title"))
    distance:SetText(ns.T("corpse.distance", math.floor(yards + 0.5), ns.T("corpse." .. Corpse.Compass(bearing))))
    if not arrow:IsShown() then arrow:Show() end
    -- the minimap's edge: pointing north up, or the way you look when the map turns with you
    local disc = ns.Hud and ns.Hud.disc
    if disc then
        local angle = Rotates() and -turn or bearing
        local radius = disc:GetWidth() / 2 - EDGE_INSET
        local x, y = Corpse.EdgePoint(angle, radius)
        edge:ClearAllPoints()
        edge:SetPoint("CENTER", disc, "CENTER", x, y)
        edgeTexture:SetRotation(-angle)
        if not edge:IsShown() then edge:Show() end
    end
    -- one ticker while the ghost moves or turns, so the arrow follows
    if moving and not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
    elseif not moving then
        StopTicker()
    end
end

local function Moved(which, on)
    if which == "walking" then walking = on else turning = on end
    moving = walking or turning
    Corpse.Update()
end

-- ---------------------------------------------------------------------------------------
-- Events

for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "CORPSE_IN_INSTANCE" }) do
    ns.On(event, Corpse.Update)
end
ns.On("CORPSE_IN_RANGE", function() inRange = true; Corpse.Update() end)
ns.On("CORPSE_OUT_OF_RANGE", function() inRange = false; Corpse.Update() end)
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_UNGHOST" }) do
    ns.On(event, function() inRange = false; Corpse.Update() end)       -- a new death starts out of range
end
ns.On("PLAYER_STARTED_MOVING", function() Moved("walking", true) end)
ns.On("PLAYER_STOPPED_MOVING", function() Moved("walking", false) end)
ns.On("PLAYER_STARTED_TURNING", function() Moved("turning", true) end)
ns.On("PLAYER_STOPPED_TURNING", function() Moved("turning", false) end)

function Corpse:Layout()
    ns.Queue("corpse layout", Place)
end

function Corpse:Refresh()
    Corpse.Update()
end

function Corpse:Restore()
    inRange, walking, turning, moving = false, false, false, false
    Hide()
end
