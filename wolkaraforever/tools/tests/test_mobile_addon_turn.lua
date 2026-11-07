-- The Interface mobile add-on's turning wheel (addons/WolkaraRoue/Turn.lua), run outside the
-- game. The secure snippets - the only code that moves the spells in combat - are executed
-- against stand-ins for their frames: the finger's angle they compute without a maths library
-- is compared with the real one; a swipe that starts on a spell turns the wheel by the right
-- number of notches and does not cast that spell; a touch casts it; nothing else is caught, so
-- a drag beside the spells stays the camera's; and in arc mode the snippets do nothing. The left
-- wheel is the right one in a mirror: positions turned left for right, the same secure angle
-- seen from its own corner, the same turning; and neither wheel draws a disc or a shadow.
-- Turning one wheel never moves the other (reported on the iPhone, 2026-11-07), even when the
-- game never tells a spell its swipe ended, and a swipe still does not cast when the game
-- passes the click before the release.
--
-- usage: luajit test_mobile_addon_turn.lua <path to Turn.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_turn.lua <Turn.lua>")

local function Frame(name)
    local frame = { name = name, attributes = {}, scripts = {}, hooks = {}, points = {}, refs = {},
        wraps = {}, shown = true }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetFrameRef(key, other) self.refs[key] = other end
    function frame:GetFrameRef(key) return self.refs[key] end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:HookScript(script, fn) self.hooks[script] = fn end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points = { ... } end
    function frame:EnableMouse(on) self.mouse = on end
    function frame:CreateTexture() return Frame() end
    function frame:CreateMaskTexture() return Frame() end
    for _, method in ipairs({ "SetFrameStrata", "SetTexture", "SetVertexColor", "SetSize",
        "SetAllPoints", "AddMaskTexture" }) do frame[method] = function() end end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:RegisterForDrag(...) self.drag = { ... } end
    return frame
end

local combat = false
local W, H = 797, 548
local frames, wrapCalls = {}, 0
InCombatLockdown = function() return combat end
CreateFrame = function(_, name) local f = Frame(name); frames[#frames + 1] = f; return f end
SecureHandlerWrapScript = function(frame, script, header, pre)
    wrapCalls = wrapCalls + 1
    frame.wraps[script] = { header = header, run = assert(loadstring("local self, owner = ...\n" .. pre)) }
end
UIParent = { GetWidth = function() return W end, GetHeight = function() return H end,
    GetEffectiveScale = function() return 1 end }
local cursor = { 0, 0 }
GetCursorPosition = function() return cursor[1], cursor[2] end
-- The left button as the game reports it. Down only where a test says so: by default the
-- game is taken to say nothing useful, as an untranslated query would.
local mouseDown = false
IsMouseButtonDown = function(button) return button == "LeftButton" and mouseDown end

local handlers = {}
local ns = { STICK_X = 0.12, STICK_Y = 0.222, WHITE = "white" }
function ns.Register(_, module) return module end
function ns.On(event, fn) handlers[event] = fn end
function ns.Circle() return true end
ns.db = { free = { count = 12, scale = 100, spread = 100, turn = true, turnOffset = 0 } }

assert(loadfile(path))("WolkaraRoue", ns)
local Turn = ns.Turn
Turn:Init()
local band
for _, frame in ipairs(frames) do if frame.name == "WolkaraMobileTurn" then band = frame end end
assert(band, "the wheel's band was not created")
local buttons = {}
for i = 1, 12 do buttons[i] = Frame("WolkaraMobileFree" .. i) end
Turn:Attach(buttons)
Turn:Layout()

-- Nothing beside the spells is caught: the band takes no touch, each spell carries the code.
assert(band.mouse == false and band.shown and band:GetAttribute("turning") == true)
assert(wrapCalls == 36)
for i = 1, 12 do
    for _, script in ipairs({ "OnMouseDown", "OnMouseUp", "OnClick" }) do
        assert(buttons[i].wraps[script] and buttons[i].wraps[script].header == band, script)
    end
    assert(buttons[i]:GetAttribute("useOnKeyDown") == false) -- a spell casts on release
    -- and is not the game's to drag: a drag would keep the finger's release from the spell.
    assert(buttons[i].drag and #buttons[i].drag == 0, "a turning spell is still registered for drag")
end
Turn:Layout()
assert(wrapCalls == 36) -- wrapped once
local function Run(button, script) return button.wraps[script].run(button, band) end

-- The finger's angle in the secure code, against the real arc tangent, all over the band.
local worst, size = 0, band:GetAttribute("size")
for fx = 0.02, 0.98, 0.04 do
    for fy = 0.02, 0.98, 0.04 do
        band.GetMousePosition = function() return fx, fy end
        Run(buttons[1], "OnMouseDown")
        local exact = math.deg(math.atan2(fy * size, (fx - 1) * size))
        worst = math.max(worst, math.abs(band:GetAttribute("downangle") - exact))
    end
end
assert(worst < 0.4, "the secure angle is off by " .. worst .. " degrees")

-- The layout: 12 spells round the corner, a quarter of a spell apart at "Écart" 100 %.
local radius, step = Turn.Geometry(W, H, 12, 100)
assert(band:GetAttribute("count") == 12 and math.abs(band:GetAttribute("step") - step) < 1e-9)
assert(math.abs(2 * radius * math.sin(math.rad(step) / 2) - 64 * 1.25) < 1e-6)
local r60, s60 = Turn.Geometry(W, H, 12, 60)
local r180, s180 = Turn.Geometry(W, H, 12, 180)
assert(r60 == radius and r180 == radius and s60 < step and step < s180)
local function Where(button) return button.points[4], button.points[5] end
local function Expected(index, offset)
    local a = math.rad(Turn.Angle(index, offset, 12, step))
    return radius * math.cos(a), radius * math.sin(a)
end
local function At(offset)
    for i = 1, 12 do
        local x, y = Where(buttons[i]); local ex, ey = Expected(i, offset)
        if math.abs(x - ex) > 1e-6 or math.abs(y - ey) > 1e-6 then return false end
    end
    return true
end
assert(At(0) and buttons[1].points[3] == "BOTTOMRIGHT")
-- No spell on the screen sits under the stick, where the jump is.
local sx, sy = W * (1 - ns.STICK_X) - W, H * ns.STICK_Y
local onScreen = 0
for i = 1, 12 do
    local x, y = Where(buttons[i])
    if x < 0 and y > 0 then
        onScreen = onScreen + 1
        assert(not (math.abs(x - sx) < 40 and y < sy), "a spell on the screen under the stick")
    end
end
assert(onScreen >= 4 and onScreen <= 7, onScreen .. " spells on the screen")

-- A finger on spell 3, moved along the wheel by the given number of steps, then lifted.
local function Swipe(spell, from, steps)
    local function at(angle) local a = math.rad(angle); return 1 + math.cos(a) * 0.6, math.sin(a) * 0.6 end
    band.GetMousePosition = function() return at(from) end; Run(buttons[spell], "OnMouseDown")
    band.GetMousePosition = function() return at(from + steps * step) end; Run(buttons[spell], "OnMouseUp")
    return Run(buttons[spell], "OnClick")
end

-- In combat: a swipe turns by the rounded number of notches and does not cast.
combat = true
assert(Swipe(3, 120, 1.6) == false, "the swiped spell was cast")
assert(band:GetAttribute("offset") == 2 and band:GetAttribute("swiped") == nil and At(2))
-- A touch, even a slightly moving one, casts and does not turn.
assert(Swipe(3, 130, 0.2) == nil and band:GetAttribute("offset") == 2 and At(2))
-- Back the other way, wrapping round (one drag spans at most the visible quarter).
assert(Swipe(5, 170, -2.6) == false and band:GetAttribute("offset") == 11 and At(11))
-- Lifted off the wheel: no turn, and the next touch still casts.
band.GetMousePosition = function() return 0.5, 0.5 end; Run(buttons[2], "OnMouseDown")
band.GetMousePosition = function() return nil end; Run(buttons[2], "OnMouseUp")
assert(band:GetAttribute("offset") == 11 and Run(buttons[2], "OnClick") == nil)
-- When the fight ends the notch is kept for the next launch.
handlers.PLAYER_REGEN_ENABLED()
assert(ns.db.free.turnOffset == 11)
combat = false

-- Out of combat the spells follow the finger once it has really moved, then settle on the
-- secure code's notch.
local function Cursor(angle) local a = math.rad(angle); cursor = { W + math.cos(a) * 200, math.sin(a) * 200 } end
Cursor(110); buttons[4].hooks.OnMouseDown()
Cursor(110 + step * 0.2); band.scripts.OnUpdate()
assert(At(11), "the spells moved for a touch")
Cursor(110 + step * 0.5); band.scripts.OnUpdate()
assert(At(11.5), "the spells did not follow the finger")
band:SetAttribute("offset", 0)
buttons[4].hooks.OnMouseUp()
assert(At(0) and ns.db.free.turnOffset == 0)
-- That swipe is marked on the spell, so the add-on's own click handlers ignore it (no picker);
-- a touch is not marked.
assert(buttons[4].swiped == true)
buttons[4].swiped = nil
Cursor(120); buttons[6].hooks.OnMouseDown(); Cursor(120 + step * 0.2); buttons[6].hooks.OnMouseUp()
assert(buttons[6].swiped == nil)

-- Arc mode: the band hides, spells cast on the game's own setting, and the snippets do nothing.
ns.db.free.turn = false
Turn:Layout()
assert(not band.shown and band:GetAttribute("turning") == false and buttons[1]:GetAttribute("useOnKeyDown") == nil)
assert(buttons[1].drag[1] == "LeftButton", "an arc spell can no longer be moved in Customise mode")
assert(Swipe(3, 120, 1.6) == nil and band:GetAttribute("offset") == 0)
buttons[4].hooks.OnMouseDown()
assert(band.scripts.OnUpdate() == nil and At(0))

-- The left wheel: the right one in a mirror, in the bottom-left corner. Nothing is drawn for
-- either wheel (the right one used to lay a dark disc over the corner).
local left
for _, frame in ipairs(frames) do if frame.name == "WolkaraMobileTurnLeft" then left = frame end end
assert(left and left.points[1] == "BOTTOMLEFT" and left.mouse == false, "the left wheel's band")
assert(band.disc == nil and left.disc == nil, "a wheel still draws its shadow")
ns.db.freeLeft = { count = 12, scale = 100, spread = 100, turn = true, turnOffset = 0 }
local lefts = {}
for i = 1, 12 do lefts[i] = Frame("WolkaraMobileFreeLeft" .. i) end
Turn:Attach(lefts, "left")
local wrappedBefore = wrapCalls
Turn:Layout()
assert(wrapCalls == wrappedBefore + 36 and left.shown and left:GetAttribute("turning") == true)
assert(left:GetAttribute("mirror") == true and left:GetAttribute("corner") == "BOTTOMLEFT")
local function AtLeft(offset)
    for i = 1, 12 do
        local x, y = Where(lefts[i]); local ex, ey = Expected(i, offset)
        if lefts[i].points[3] ~= "BOTTOMLEFT" or math.abs(x + ex) > 1e-6 or math.abs(y - ey) > 1e-6 then return false end
    end
    return true
end
assert(AtLeft(0), "the left spells are not the mirror of the right ones")
local function RunLeft(button, script) return button.wraps[script].run(button, left) end

-- Its secure angle, seen from its own corner and turned in the mirror.
local worstLeft, leftSize = 0, left:GetAttribute("size")
for fx = 0.02, 0.98, 0.04 do
    for fy = 0.02, 0.98, 0.04 do
        left.GetMousePosition = function() return fx, fy end
        RunLeft(lefts[1], "OnMouseDown")
        local exact = math.deg(math.atan2(fy * leftSize, -fx * leftSize))
        worstLeft = math.max(worstLeft, math.abs(left:GetAttribute("downangle") - exact))
    end
end
assert(worstLeft < 0.4, "the left secure angle is off by " .. worstLeft .. " degrees")

-- In combat: a swipe along the left wheel turns it by the rounded notches and does not cast; a
-- touch casts. The right wheel, in arc mode, stays as it is.
local function SwipeLeft(spell, from, steps)
    local function at(angle) local a = math.rad(angle); return -math.cos(a) * 0.6, math.sin(a) * 0.6 end
    left.GetMousePosition = function() return at(from) end; RunLeft(lefts[spell], "OnMouseDown")
    left.GetMousePosition = function() return at(from + steps * step) end; RunLeft(lefts[spell], "OnMouseUp")
    return RunLeft(lefts[spell], "OnClick")
end
combat = true
assert(SwipeLeft(3, 120, 1.6) == false and left:GetAttribute("offset") == 2 and AtLeft(2), "the left wheel did not turn")
assert(SwipeLeft(3, 130, 0.2) == nil and left:GetAttribute("offset") == 2 and AtLeft(2))
handlers.PLAYER_REGEN_ENABLED()
assert(ns.db.freeLeft.turnOffset == 2 and ns.db.free.turnOffset == 0)
combat = false

-- Out of combat its spells follow the finger in the mirror, then settle on the notch.
local function CursorLeft(angle) local a = math.rad(angle); cursor = { -math.cos(a) * 200, math.sin(a) * 200 } end
CursorLeft(110); lefts[4].hooks.OnMouseDown()
CursorLeft(110 + step * 0.5); left.scripts.OnUpdate()
assert(AtLeft(2.5), "the left spells did not follow the finger")
lefts[4].hooks.OnMouseUp()
assert(AtLeft(2) and ns.db.freeLeft.turnOffset == 2 and lefts[4].swiped == true)
-- A new touch forgets the last swipe, so an empty slot's next touch still opens the picker.
lefts[4].hooks.OnMouseDown(); lefts[4].hooks.OnMouseUp()
assert(lefts[4].swiped == nil)

-- Both wheels turning. Reported on the iPhone (2026-11-07): turning one wheel moved the other.
-- A swipe whose release never reached its spell left that wheel following the cursor, so the
-- next swipe, on the other wheel, turned both.
ns.db.free.turn = true
Turn:Layout()
assert(band.shown and At(0) and AtLeft(2))
-- The release that never comes: the left wheel's finger lifts and nothing tells its spell.
CursorLeft(120); lefts[2].hooks.OnMouseDown()
-- Then a swipe on the right wheel: the left one stops where it was, the right one alone follows.
Cursor(120); buttons[3].hooks.OnMouseDown()
Cursor(120 + step * 1.6)
band.scripts.OnUpdate(); left.scripts.OnUpdate()
assert(AtLeft(2), "turning the right wheel moved the left one")
assert(At(1.6), "the right wheel did not follow the finger")
-- Its release does not reach the spell either, but the game has seen the finger down and now
-- up: the swipe ends on the nearest notch, kept, and the wheel no longer follows the cursor.
mouseDown = true; band.scripts.OnUpdate()
mouseDown = false; band.scripts.OnUpdate()
assert(At(2) and band:GetAttribute("offset") == 2 and ns.db.free.turnOffset == 2, "the unreleased swipe did not settle")
Cursor(170); band.scripts.OnUpdate(); left.scripts.OnUpdate()
assert(At(2) and AtLeft(2), "a wheel still follows the cursor after the finger lifted")
-- The other way round: a swipe on the left wheel leaves the right one alone.
CursorLeft(120); lefts[3].hooks.OnMouseDown()
CursorLeft(120 + step * 0.5); left.scripts.OnUpdate(); band.scripts.OnUpdate()
assert(AtLeft(2.5) and At(2), "turning the left wheel moved the right one")
lefts[3].hooks.OnMouseUp()
assert(AtLeft(2))

-- In combat, should the game pass the click before the release, a swipe still does not cast,
-- and the release still turns the wheel; a touch still casts.
combat = true
local function at(angle) local a = math.rad(angle); return 1 + math.cos(a) * 0.6, math.sin(a) * 0.6 end
band.GetMousePosition = function() return at(120) end; Run(buttons[3], "OnMouseDown")
band.GetMousePosition = function() return at(120 + step * 1.6) end
assert(Run(buttons[3], "OnClick") == false, "a swipe cast its spell when the click came first")
Run(buttons[3], "OnMouseUp")
assert(band:GetAttribute("offset") == 4 and At(4))
band.GetMousePosition = function() return at(130) end; Run(buttons[3], "OnMouseDown")
assert(Run(buttons[3], "OnClick") == nil, "a touch no longer casts")
combat = false

print(string.format("mobile add-on turning wheels: secure angle within %.2f deg (left %.2f); swipe on a spell turns without casting, touch casts, nothing else caught, arc mode inert, left is the mirror, no shadow, one wheel turns at a time even when a release goes unreported: PASS", worst, worstLeft))
