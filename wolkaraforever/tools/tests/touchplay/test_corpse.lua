-- Task 13: the arrow to your corpse and the distance (mockups 14, 15). The maths is pure; the arrow
-- follows the ghost on events, with one ticker only while it moves.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return ns.Corpse
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- the ghost of mockup 14: 240 yards east of where you stand
local function ghost()
    Stub.mapPos = { 0.4, 0.5 }
    Stub.corpse = { 0.64, 0.5 }
    Stub.mapSize = { 1000, 700 }
    Stub.setDead("player", "ghost")
    Stub.fire("PLAYER_ALIVE")
end

T("corpse_arrow_distance", function()
    local C = setup()
    assert(near(C.Yards(0.4, 0.5, 0.64, 0.5, 1000, 700), 240))
    assert(near(C.Yards(0.4, 0.5, 0.4, 0.6, 1000, 700), 70), "the map is not square: y counts for 700 yards")
    assert(near(C.Yards(0.40, 0.50, 0.44, 0.47, 1000, 500), math.sqrt(40 * 40 + 15 * 15)))
    assert(C.Yards(0.3, 0.3, 0.3, 0.3, 1000, 700) == 0)
end)

T("corpse_bearing_and_words", function()
    local C = setup()
    local function b(cx, cy) return C.Bearing(0.5, 0.5, cx, cy, 1000, 1000) end
    assert(near(b(0.5, 0.4), 0) and C.Compass(b(0.5, 0.4)) == "n")
    assert(near(b(0.6, 0.5), math.pi / 2) and C.Compass(b(0.6, 0.5)) == "e")
    assert(near(b(0.5, 0.6), math.pi) and C.Compass(b(0.5, 0.6)) == "s")
    assert(near(b(0.4, 0.5), 3 * math.pi / 2) and C.Compass(b(0.4, 0.5)) == "w")
    assert(C.Compass(b(0.6, 0.4)) == "ne" and C.Compass(b(0.6, 0.6)) == "se")
    assert(C.Compass(b(0.4, 0.6)) == "sw" and C.Compass(b(0.4, 0.4)) == "nw")
    assert(C.Compass(2 * math.pi - 0.1) == "n", "just short of a full turn is still north")
end)

T("corpse_arrow_turns_with_the_way_you_look", function()
    local C = setup()
    -- where an arrow that points up points after a counter-clockwise turn of `rotation`
    local function points(rotation) return -math.sin(rotation), math.cos(rotation) end
    -- corpse east, looking north: right
    local x, y = points(C.Rotation(math.pi / 2, 0)); assert(near(x, 1) and near(y, 0))
    -- corpse east, looking east (facing, counter-clockwise from north, is 3 pi / 2): straight ahead
    x, y = points(C.Rotation(math.pi / 2, 3 * math.pi / 2)); assert(near(x, 0) and near(y, 1))
    -- corpse east, looking west (facing pi / 2): behind
    x, y = points(C.Rotation(math.pi / 2, math.pi / 2)); assert(near(x, 0) and near(y, -1))
    local r = C.Rotation(1, 2); assert(r > -math.pi and r <= math.pi)
end)

T("corpse_edge_point_sits_on_the_ring", function()
    local C = setup()
    local x, y = C.EdgePoint(0, 78); assert(near(x, 0) and near(y, 78))
    x, y = C.EdgePoint(math.pi / 2, 78); assert(near(x, 78) and near(y, 0))
end)

T("ghost_gets_the_arrow_at_the_mockup_place", function()
    local C = setup()
    assert(not C.arrow:IsShown(), "alive: nothing")
    ghost()
    assert(C.arrow:IsShown())
    local cx, cy = Stub.centre(C.arrow)
    assert(cx == 683 and cy == 175, cx .. "," .. cy)
    assert(C.title:GetText() == "Your corpse")
    assert(C.distance:GetText() == "240 yards, east", C.distance:GetText())
    assert(near(C.arrowTexture.rotation, -math.pi / 2), "points right: the corpse is east and you look north")
end)

T("minimap_edge_arrow_uses_the_hud_ring", function()
    local C = setup()
    ghost()
    assert(C.edge:IsShown())
    local p = C.edge.points[1]
    assert(p[1] == "CENTER" and p[2] == ns.Hud.disc, "anchored to the minimap disc's centre")
    local radius = math.sqrt(p[4] ^ 2 + p[5] ^ 2)
    assert(near(radius, ns.Hud.disc:GetWidth() / 2 - 8), radius)
    assert(p[4] > 0 and near(p[5], 0, 1e-6), "east of the centre")
    -- the ring is read, not remembered
    ns.Hud.disc:SetSize(200, 200); Stub.fire("ZONE_CHANGED")
    p = C.edge.points[1]
    assert(near(math.sqrt(p[4] ^ 2 + p[5] ^ 2), 92))
end)

T("minimap_that_turns_points_the_way_you_look", function()
    local C = setup()
    GetCVar = function(name) return name == "rotateMinimap" and "1" or "0" end
    Stub.facing = math.pi / 2           -- looking west: the corpse (east) is behind
    ghost()
    local p = C.edge.points[1]
    assert(near(p[4], 0, 1e-6) and p[5] < 0, "behind you is down on a turning map")
    GetCVar = nil
end)

T("arrow_hides_when_it_should", function()
    local C = setup()
    ghost(); assert(C.arrow:IsShown())
    Stub.fire("CORPSE_IN_RANGE"); assert(not C.arrow:IsShown() and not C.edge:IsShown(), "in range: the game's own question takes over")
    Stub.fire("CORPSE_OUT_OF_RANGE"); assert(C.arrow:IsShown())
    Stub.corpse = nil; Stub.fire("ZONE_CHANGED"); assert(not C.arrow:IsShown(), "no corpse on this map (an instance)")
    Stub.corpse = { 0.64, 0.5 }; Stub.fire("ZONE_CHANGED"); assert(C.arrow:IsShown())
    Stub.setDead("player", nil); Stub.fire("PLAYER_UNGHOST"); assert(not C.arrow:IsShown(), "alive again")
    Stub.setDead("player", "dead"); Stub.fire("PLAYER_DEAD"); assert(not C.arrow:IsShown(), "dead, not yet released: no arrow (mockup 13)")
end)

T("a_new_death_starts_out_of_range", function()
    local C = setup()
    ghost(); Stub.fire("CORPSE_IN_RANGE")
    Stub.setDead("player", nil); Stub.fire("PLAYER_UNGHOST")
    ghost()
    assert(C.arrow:IsShown(), "the range of the last corpse is forgotten")
end)

T("the_arrow_follows_a_moving_ghost_with_one_ticker", function()
    local C = setup()
    ghost()
    local base = #Stub.timers           -- the Hud's own one-second ticker is already there
    Stub.fire("PLAYER_STARTED_MOVING")
    assert(#Stub.timers == base + 1)
    Stub.fire("PLAYER_STARTED_TURNING"); assert(#Stub.timers == base + 1, "still one")
    Stub.mapPos = { 0.64, 0.6 }          -- walked to the corpse's x, 70 yards south of it
    Stub.advance(0.3)
    assert(C.distance:GetText() == "70 yards, north", C.distance:GetText())
    Stub.fire("PLAYER_STOPPED_MOVING"); Stub.advance(0.3)
    Stub.mapPos = { 0.64, 0.7 }
    Stub.advance(0.3)
    assert(C.distance:GetText() == "140 yards, north", "still turning: still following")
    Stub.fire("PLAYER_STOPPED_TURNING"); Stub.advance(0.3); Stub.advance(0.3)
    assert(#Stub.timers == base, "the ticker is gone once nothing moves: " .. #Stub.timers - base)
end)

T("no_ticker_for_the_living", function()
    local C = setup()
    local base = #Stub.timers
    Stub.fire("PLAYER_STARTED_MOVING"); Stub.advance(1)
    assert(#Stub.timers == base and not C.arrow:IsShown())
end)

T("hidden_positions_are_never_computed", function()
    local C = setup()
    ghost()
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return Stub.secret(), Stub.secret() end } end
    Stub.fire("ZONE_CHANGED")
    assert(not ns.paused, ns.lastError)
    assert(not C.arrow:IsShown())
end)

T("off_takes_the_arrow_away", function()
    local C = setup()
    ghost()
    local base = #Stub.timers
    Stub.fire("PLAYER_STARTED_MOVING")
    ns.SetEnabled(false)
    assert(not C.arrow:IsShown() and not C.edge:IsShown())
    Stub.advance(1); assert(#Stub.timers <= base, "our ticker is gone")
end)

T("current_yards_for_the_spirit_healer_line", function()
    local C = setup()
    assert(C.CurrentYards() == nil)
    ghost(); assert(C.CurrentYards() == 240)
end)

Stub.done("corpse")
