-- The Interface mobile add-on's turning wheels (addons/WolkaraRoue/Turn.lua), run outside the
-- game. The secure snippets - the only code that moves the spells in combat - are executed
-- against stand-ins for their frames: the finger's angle they compute without a maths library
-- is compared with the real one; a swipe that starts on a spell turns the wheel by the right
-- number of notches and does not cast that spell; a touch casts it; nothing else is caught, so
-- a drag beside the spells stays the camera's. The left wheel is the right one in a mirror.
-- Turning one wheel never moves the other (reported on the iPhone, 2026-11-07), even when the
-- game never tells a spell its swipe ended, and a swipe still does not cast when the game
-- passes the click before the release. The game refuses to wrap OnMouseDown and OnMouseUp
-- ("Unsupported script type", General.log 2026-11-09): this stand-in refuses them too, and the
-- press and release snippets run the way the game runs a SecureHandlerMouseUpDownTemplate's.
-- Out of combat the release settles on the nearest notch without waiting for the secure code.
--
-- Asked for on the iPhone (2026-11-09): each side has its wheels, four by default and one to
-- six by the setting, one shown at a time, empty or not. A diagonal swipe from the wheel goes
-- to the next one (toward the screen's centre) or the previous one (toward the corner), round
-- in a loop, in combat by the secure code and out of combat by the add-on; a swipe along the
-- wheel, which turns it, is never taken for one anywhere on the visible quarter. Numbered tabs
-- in an arc just above the wheel show which one is up and switch straight to theirs, in combat
-- too; the wheel that comes lights up spell after spell, in the swipe's direction, through
-- frames of the add-on's own laid over the spells (the game's protected buttons are not
-- animated). Only the left button turns or changes wheels: the long press, which the app gives
-- as a right click, and the right-button drag after it belong to moving a spell (Free.lua).
--
-- usage: luajit test_mobile_addon_turn.lua <path to Turn.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_turn.lua <Turn.lua>")

local function Frame(name)
    local frame = { name = name, attributes = {}, scripts = {}, hooks = {}, points = {}, refs = {},
        wraps = {}, shown = true, alpha = 1, level = 1 }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetFrameRef(key, other) self.refs[key] = other end
    function frame:GetFrameRef(key) return self.refs[key] end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:HookScript(script, fn) self.hooks[script] = fn end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points = { ... } end
    function frame:EnableMouse(on) self.mouse = on end
    function frame:CreateTexture() local t = Frame(); t.shown = true; return t end
    function frame:CreateFontString() return Frame() end
    function frame:CreateMaskTexture() return Frame() end
    for _, method in ipairs({ "SetFrameStrata", "SetTexture", "SetSize", "SetAllPoints", "AddMaskTexture",
        "SetBlendMode", "SetHitRectInsets" }) do
        frame[method] = function() end
    end
    function frame:SetVertexColor(...) self.color = { ... } end
    function frame:SetTextColor(...) self.textColor = { ... } end
    function frame:SetText(text) self.text = text end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetFrameLevel() return self.level end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:RegisterForClicks(...) self.clicks = { ... } end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:SetShown(on) self.shown = on and true or false end
    function frame:IsShown() return self.shown end
    function frame:SetParent(parent) self.parent = parent end
    function frame:RegisterForDrag(...) self.drag = { ... } end
    return frame
end

local combat = false
local W, H = 797, 548
local frames, wrapCalls = {}, 0
InCombatLockdown = function() return combat end
CreateFrame = function(kind, name, parent, template)
    local f = Frame(name)
    f.kind, f.template, f.createdIn = kind, template, parent
    frames[#frames + 1] = f
    return f
end
local function Named(name) for _, frame in ipairs(frames) do if frame.name == name then return frame end end end
SecureHandlerWrapScript = function(frame, script, header, pre)
    -- The game's list of scripts it wraps has neither of these.
    if script == "OnMouseDown" or script == "OnMouseUp" then
        error("Unsupported script type '" .. script .. "'")
    end
    wrapCalls = wrapCalls + 1
    frame.wraps[script] = { header = header, run = assert(loadstring("local self, owner = ...\n" .. pre)) }
end
UIParent = { GetWidth = function() return W end, GetHeight = function() return H end,
    GetEffectiveScale = function() return 1 end }
local cursor = { 0, 0 }
GetCursorPosition = function() return cursor[1], cursor[2] end
local clock = 100
GetTime = function() return clock end
-- The left button as the game reports it. Down only where a test says so: by default the
-- game is taken to say nothing useful, as an untranslated query would.
local mouseDown = false
IsMouseButtonDown = function(button) return button == "LeftButton" and mouseDown end

local handlers = {}
local ns = { STICK_X = 0.12, STICK_Y = 0.222, WHITE = "white", PAGES = 6, WHEELS = 4, MAX_FREE = 12, editing = false }
function ns.Register(_, module) return module end
function ns.On(event, fn) handlers[event] = fn end
function ns.Circle() return true end
function ns.Disc(frame) return frame:CreateTexture() end
function ns.Label(frame, _, text) local label = frame:CreateFontString(); label.text = text; return label end
-- As Core.lua has them.
function ns.PageData(side, page)
    if type(side.pages) ~= "table" then side.pages = {} end
    if type(side.pages[page]) ~= "table" then side.pages[page] = {} end
    if type(side.pages[page].buttons) ~= "table" then side.pages[page].buttons = {} end
    return side.pages[page]
end
local function Side(filled)
    local side = { count = 12, wheels = 4, scale = 100, spread = 100, page = 1, pages = {} }
    for _, page in ipairs(filled) do ns.PageData(side, page).buttons[1] = { entry = { kind = "spell", id = page } } end
    return side
end
-- The right side has spells on its wheels 1 and 3, none on 2 and 4.
ns.db = { free = Side({ 1, 3 }), freeLeft = Side({ 1 }) }

assert(loadfile(path))("WolkaraRoue", ns)
local Turn = ns.Turn
Turn:Init()
local band, pager = Named("WolkaraMobileTurn"), Named("WolkaraMobileTurnPages")
assert(band and pager, "the right wheel's band or pager was not created")
local bands = { band }
for page = 2, 6 do bands[page] = Named("WolkaraMobileTurn" .. page) end
for page = 1, 6 do
    assert(bands[page], "no band for wheel " .. page)
    assert(pager:GetFrameRef("band" .. page) == bands[page] and bands[page]:GetFrameRef("pager") == pager)
end
local pages, buttons = {}, nil
for page = 1, 6 do
    pages[page] = {}
    for i = 1, 12 do pages[page][i] = Frame(page == 1 and ("WolkaraMobileFree" .. i) or ("WolkaraMobileFree" .. page .. "_" .. i)) end
end
buttons = pages[1]
Turn:Attach(pages, "right")
Turn:Layout()

-- Nothing beside the spells is caught: the bands take no touch, each spell carries the code:
-- its click wrapped by its own wheel's band, its press and release in its own template's
-- attributes; it lives in its band, which shows and hides it with its wheel.
for page = 1, 6 do assert(bands[page].mouse == false) end
assert(wrapCalls == 72)
for page = 1, 6 do
    for i = 1, 12 do
        local b = pages[page][i]
        assert(b.wraps.OnClick and b.wraps.OnClick.header == bands[page])
        assert(not b.wraps.OnMouseDown and not b.wraps.OnMouseUp)
        assert(b:GetAttribute("_onmousedown") and b:GetAttribute("_onmouseup"), "no press/release code")
        assert(b:GetFrameRef("wheel") == bands[page] and b.parent == bands[page])
        assert(b:GetAttribute("useOnKeyDown") == false) -- a spell casts on release
        -- Only the right button drags (moving a spell after a long press): a left drag would keep
        -- the finger's release from the spell.
        assert(b.drag and #b.drag == 1 and b.drag[1] == "RightButton", "a spell is draggable by the left button")
        -- Over it, the add-on's own frame for the wheel's arrival: no touch, no secure code.
        local fx = b.wmArrive
        assert(fx and fx.createdIn == b and fx.template == nil and fx.mouse == false and not fx.shown, "no arrival effect over a spell")
        assert(fx.level > b.level and fx.veil and fx.flash)
    end
end
Turn:Layout()
assert(wrapCalls == 72) -- wrapped once
-- Four wheels a side by default: the first is shown, the others wait, empty or not; the bands
-- past the fourth are there for a player who asks for six.
assert(pager:GetAttribute("pages") == 4 and pager:GetAttribute("page") == 1)
assert(bands[1].shown and not bands[2].shown and not bands[3].shown and not bands[4].shown and not bands[5].shown and not bands[6].shown)

-- Its tabs: one per wheel, numbered, secure (they switch in combat), in an arc just above the
-- wheel - the lowest on its diagonal, the others going up toward the screen's edge - from 1 on
-- the left to 4 on the right; the first gold. Clear of the chat strip: on the Duo's screen
-- (951 x 669 points, about this test's proportions) an arc centred on the diagonal touched the
-- strip's corner. The strip, as Chat.lua lays it: 36 % of the width, centred, from 12 % of the
-- height, three lines of 16 and its row of tabs above.
local radius, step = Turn.Geometry(W, H, 12, 100)
local tabs = {}
for i = 1, 6 do tabs[i] = assert(Named("WolkaraMobileTurnTab" .. i), "no tab " .. i) end
local function TabAt(tab) return tab.points[4], tab.points[5] end
local CHAT = { left = W * 0.32, right = W * 0.68, bottom = H * 0.12, top = H * 0.12 + 16 * 3 + 14 + 28 + 4 }
local function ClearOfChat(tab, mirror)
    local x, y = TabAt(tab)
    x = mirror and x or W + x
    return x + 17 < CHAT.left or x - 17 > CHAT.right or y - 17 > CHAT.top or y + 17 < CHAT.bottom
end
local function Degrees(tab) local x, y = TabAt(tab); return math.deg(math.atan2(y, x)) end
assert(math.abs(Degrees(tabs[1]) - 135) < 1e-6, "the lowest tab is not on the diagonal")
for i = 1, 4 do
    local tab = tabs[i]
    assert(tab.shown and tab.template == "SecureHandlerClickTemplate" and tab:GetAttribute("page") == i)
    assert(tab:GetFrameRef("pager") == pager and tab:GetAttribute("_onclick") and tab.clicks[1] == "AnyUp")
    assert(tab.points[1] == "CENTER" and tab.points[2] == UIParent and tab.points[3] == "BOTTOMRIGHT")
    local x, y = TabAt(tab)
    local distance = math.sqrt(x * x + y * y)
    assert(distance >= radius + 32 + 17 + 10, "a tab sits on the wheel's spells")
    assert(x < -17 and x > -W + 17 and y > 17 and y < H - 17, "a tab is off the screen")
    assert(ClearOfChat(tab), "tab " .. i .. " sits on the chat strip")
    assert(tab.label.text == tostring(i))
    if i > 1 then
        local px, py = TabAt(tabs[i - 1])
        assert(px < x and py < y and Degrees(tab) < Degrees(tabs[i - 1]), "the tabs do not go up from left to right")
        assert(math.sqrt((x - px) ^ 2 + (y - py) ^ 2) >= 34, "two tabs overlap")
    end
end
assert(not tabs[5].shown and not tabs[6].shown, "tabs for wheels the side does not have")
local function Gold(tab) return tab.face.color[1] == 1 end
assert(Gold(tabs[1]) and not Gold(tabs[2]) and not Gold(tabs[3]) and not Gold(tabs[4]), "the tab of the wheel shown is not gold")

-- How the game runs the code: the click through the band's wrap, the press and release as the
-- button's own template does (self is the button; the band only by its frame reference); a
-- tab's click by its own template (self is the tab).
local function Snippet(b, script, mouse)
    if script == "OnClick" then return b.wraps.OnClick.run(b, b.wraps.OnClick.header) end
    local body = b:GetAttribute(script == "OnMouseDown" and "_onmousedown" or "_onmouseup")
    return assert(loadstring("local self, button = ...\n" .. body))(b, mouse or "LeftButton")
end
local function Run(b, script, mouse) return Snippet(b, script, mouse) end
local function Touch(tab) return assert(loadstring("local self, button, down = ...\n" .. tab:GetAttribute("_onclick")))(tab, "LeftButton", false) end

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
assert(band:GetAttribute("count") == 12 and math.abs(band:GetAttribute("step") - step) < 1e-9)
assert(math.abs(2 * radius * math.sin(math.rad(step) / 2) - 64 * 1.25) < 1e-6)
local r60, s60 = Turn.Geometry(W, H, 12, 60)
local r180, s180 = Turn.Geometry(W, H, 12, 180)
assert(r60 == radius and r180 == radius and s60 < step and step < s180)
local function Where(b) return b.points[4], b.points[5] end
local function Expected(index, offset)
    local a = math.rad(Turn.Angle(index, offset, 12, step))
    return radius * math.cos(a), radius * math.sin(a)
end
local function AtOn(list, offset)
    for i = 1, 12 do
        local x, y = Where(list[i]); local ex, ey = Expected(i, offset)
        if math.abs(x - ex) > 1e-6 or math.abs(y - ey) > 1e-6 then return false end
    end
    return true
end
local function At(offset) return AtOn(buttons, offset) end
assert(At(0) and buttons[1].points[3] == "BOTTOMRIGHT" and buttons[1].points[2] == band)
assert(AtOn(pages[3], 0) and pages[3][1].points[2] == bands[3], "the third wheel is not laid out")
assert(AtOn(pages[2], 0), "the empty second wheel is not laid out")
-- The band reaches past the wheel, so a swipe that ends beyond the spells still reads.
assert(size >= radius + 64 * 2.5)
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

-- Where the finger is on a band, as GetMousePosition says it (0 to 1 from its bottom left),
-- for a point at `angle` and `distance` from the wheel's corner.
local function OnBand(b, angle, distance, mirror)
    local a, s = math.rad(angle), b:GetAttribute("size")
    local px, py = -math.cos(a) * distance, math.sin(a) * distance
    if mirror then return px / s, py / s end
    return 1 - px / s, py / s
end
-- A finger on a spell, moved along the wheel by the given number of steps, then lifted.
local function Swipe(spell, from, steps)
    band.GetMousePosition = function() return OnBand(band, from, radius) end; Run(buttons[spell], "OnMouseDown")
    band.GetMousePosition = function() return OnBand(band, from + steps * step, radius) end; Run(buttons[spell], "OnMouseUp")
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
-- The right button turns nothing: its press and release are the long press's (Free.lua).
band.GetMousePosition = function() return OnBand(band, 120, radius) end; Run(buttons[3], "OnMouseDown", "RightButton")
band.GetMousePosition = function() return OnBand(band, 120 + 2 * step, radius) end; Run(buttons[3], "OnMouseUp", "RightButton")
assert(band:GetAttribute("offset") == 11 and band:GetAttribute("swiped") == nil, "a right-button drag turned the wheel")

-- A diagonal swipe, from the wheel toward the centre of the screen: the next wheel, empty or
-- not (2 has no spell), shown by the secure code, and the spell under the finger is not cast.
local function Diagonal(b, list, spell, angle, dx, dy)
    b.GetMousePosition = function() return OnBand(b, angle, radius) end; Run(list[spell], "OnMouseDown")
    local fx, fy = OnBand(b, angle, radius)
    local s = b:GetAttribute("size")
    b.GetMousePosition = function() return fx - dx / s, fy + dy / s end; Run(list[spell], "OnMouseUp")
    return Run(list[spell], "OnClick")
end
local function Showing(page)
    if pager:GetAttribute("page") ~= page then return false end
    for i = 1, 6 do if bands[i].shown ~= (i == page) then return false end end
    return true
end
assert(Diagonal(band, buttons, 4, 135, 60, 60) == false, "a diagonal swipe cast its spell")
assert(Showing(2), "the diagonal did not show the empty wheel 2")
assert(band:GetAttribute("offset") == 11, "the diagonal turned the wheel it left")
-- From an empty slot of that wheel, back toward the corner: the previous one.
assert(Diagonal(bands[2], pages[2], 2, 135, -60, -60) == false and Showing(1))
-- Toward the corner from the first wheel: round to the last one; toward the centre from the
-- last: round to the first.
assert(Diagonal(band, buttons, 4, 135, -60, -60) == false and Showing(4), "no loop back to the last wheel")
assert(Diagonal(bands[4], pages[4], 3, 135, 60, 60) == false and Showing(1), "no loop on to the first wheel")
-- From the top of the visible quarter and from its bottom, up and in.
assert(Diagonal(band, buttons, 1, 97, 55, 55) == false and Showing(2))
assert(Diagonal(bands[2], pages[2], 1, 170, 55, 55) == false and Showing(3), "the bottom slot's diagonal")
assert(Diagonal(bands[3], pages[3], 2, 135, -60, -60) == false and Showing(2))
assert(Diagonal(bands[2], pages[2], 2, 135, -60, -60) == false and Showing(1))
-- A short diagonal is a touch: it casts, nothing changes.
assert(Diagonal(band, buttons, 4, 135, 20, 20) == nil and Showing(1))

-- A tab, in combat: straight to its wheel, through the secure code.
Touch(tabs[3])
assert(Showing(3), "the tab did not show its wheel")
-- Its wheel's band, now shown, says so on the tabs and lights its spells up one after the
-- other from the top of the wheel, through the add-on's frames over them.
local animator
for _, frame in ipairs(frames) do if frame.name == nil and frame.scripts.OnUpdate then animator = frame end end
assert(animator, "no animator")
bands[3].scripts.OnUpdate()
assert(Gold(tabs[3]) and not Gold(tabs[1]), "the tabs did not follow the wheel shown")
local lit = {}
for i = 1, 12 do if pages[3][i].wmArrive.shown then lit[#lit + 1] = i end end
-- The spells on the screen's quarter: slots 0 to 4 at this spacing, nothing off the screen.
assert(#lit == 5 and lit[1] == 1 and lit[5] == 5, #lit .. " spells lit")
assert(animator.shown and pages[3][1].wmArrive.veil.alpha == 1)
clock = clock + Turn.STAGGER * 1.5; animator.scripts.OnUpdate()
local first, second, last = pages[3][1].wmArrive, pages[3][2].wmArrive, pages[3][5].wmArrive
assert(first.veil.alpha < 1 and second.veil.alpha < 1 and second.veil.alpha > first.veil.alpha, "the spells do not light up in turn")
assert(last.veil.alpha == 1, "the last spell lit up with the first")
assert(first.flash.alpha > 0, "no flash")
clock = clock + 2; animator.scripts.OnUpdate()
for i = 1, 5 do assert(not pages[3][i].wmArrive.shown) end
assert(not animator.shown, "the animation does not end")
-- Counted in the save, to be read from the Mac: one wheel arrived, in combat.
assert(ns.db.wheelSeen and ns.db.wheelSeen.arrived == 1 and ns.db.wheelSeen.combat == 1, "the arrival is not counted")
assert(ns.db.screenSeen and ns.db.screenSeen.width == W and ns.db.screenSeen.height == H, "the screen size is not kept")
-- The tab of the wheel shown, and a tab past the side's wheels, change nothing.
Touch(tabs[3]); assert(Showing(3))
Touch(tabs[5]); assert(Showing(3), "a tab past the side's wheels switched")
-- Toward the corner, the previous wheel lights up from the bottom of the wheel.
assert(Diagonal(bands[3], pages[3], 2, 135, -60, -60) == false and Showing(2))
bands[2].scripts.OnUpdate()
clock = clock + Turn.STAGGER * 1.5; animator.scripts.OnUpdate()
assert(pages[2][5].wmArrive.veil.alpha < 1 and pages[2][1].wmArrive.veil.alpha == 1, "the previous wheel did not light up from the bottom")
clock = clock + 2; animator.scripts.OnUpdate()
Touch(tabs[1]); bands[1].scripts.OnUpdate(); clock = clock + 2; animator.scripts.OnUpdate()
assert(Showing(1) and Gold(tabs[1]))

-- One wheel only (the setting): no tab, and a diagonal changes nothing; the spell is still not
-- cast.
ns.db.free.wheels = 1
combat = false; Turn:Layout(); combat = true
assert(pager:GetAttribute("pages") == 1)
for i = 1, 6 do assert(not tabs[i].shown, "a tab for a single wheel") end
assert(Diagonal(band, buttons, 4, 135, 60, 60) == false and Showing(1))
ns.db.free.wheels = 4
combat = false; Turn:Layout(); combat = true
-- When the fight ends the wheel shown and the notch are kept for the next launch.
handlers.PLAYER_REGEN_ENABLED()
assert(ns.db.free.pages[1].turnOffset == 11 and ns.db.free.page == 1)
combat = false

-- A swipe along the wheel, which turns it, is never a diagonal: from any spell on the visible
-- quarter, by up to two notches either way as far as the screen goes, even cutting straight
-- across.
local checked = 0
for from = 95, 175, 2.5 do
    for steps = -2, 2, 0.25 do
        local to = from + steps * step
        if to >= 90 and to <= 180 then
            checked = checked + 1
            local a, b = math.rad(from), math.rad(to)
            local dx = (-math.cos(b) * radius) - (-math.cos(a) * radius)
            local dy = math.sin(b) * radius - math.sin(a) * radius
            assert(Turn.Diagonal(dx, dy) == 0, string.format("a turn from %.1f by %.2f notches reads as a diagonal", from, steps))
        end
    end
end
assert(checked > 400, checked .. " turns checked")
assert(Turn.Diagonal(50, 50) == 1 and Turn.Diagonal(-50, -50) == -1 and Turn.Diagonal(25, 25) == 0)

-- Out of combat the spells follow the finger once it has really moved, then settle on the
-- secure code's notch.
local function Cursor(angle, distance) local a = math.rad(angle); local d = distance or radius
    cursor = { W + math.cos(a) * d, math.sin(a) * d } end
Cursor(110); buttons[4].hooks.OnMouseDown(buttons[4], "LeftButton")
Cursor(110 + step * 0.2); band.scripts.OnUpdate()
assert(At(11), "the spells moved for a touch")
Cursor(110 + step * 0.6); band.scripts.OnUpdate()
assert(At(11.6), "the spells did not follow the finger")
-- Lifted: the nearest notch, worked out here (no secure code runs in this stand-in for the
-- hooks), kept for the secure code and for the next launch.
buttons[4].hooks.OnMouseUp(buttons[4], "LeftButton")
assert(At(0) and band:GetAttribute("offset") == 0 and ns.db.free.pages[1].turnOffset == 0, "the wheel sprang back")
-- And it stays there: the next layout puts it back on the same notch.
Turn:Layout()
assert(At(0), "the next layout forgot the notch")
-- That swipe is marked on the spell, so the add-on's own click handlers ignore it (no picker);
-- a touch is not marked.
assert(buttons[4].swiped == true)
buttons[4].swiped = nil
Cursor(120); buttons[6].hooks.OnMouseDown(buttons[6], "LeftButton"); Cursor(120 + step * 0.2); buttons[6].hooks.OnMouseUp(buttons[6], "LeftButton")
assert(buttons[6].swiped == nil)
-- The right button is not followed.
Cursor(120); buttons[6].hooks.OnMouseDown(buttons[6], "RightButton")
Cursor(120 + step * 1.6); band.scripts.OnUpdate()
assert(At(0), "a right-button drag turned the wheel")
-- Out of combat a diagonal does not turn on its way, and changes the wheel when lifted: to the
-- next one, empty or not.
local function CursorAt(x, y) cursor = { W - x, y } end
local a = math.rad(135)
local px, py = -math.cos(a) * radius, math.sin(a) * radius
CursorAt(px, py); buttons[4].hooks.OnMouseDown(buttons[4], "LeftButton")
CursorAt(px + 50, py + 50); band.scripts.OnUpdate()
assert(At(0), "the wheel turned under a diagonal")
buttons[4].hooks.OnMouseUp(buttons[4], "LeftButton")
assert(Showing(2) and ns.db.free.page == 2, "no wheel change out of combat")
assert(buttons[4].swiped == true and At(0))
-- It lights up, and the tabs say so, out of combat as in combat.
bands[2].scripts.OnUpdate()
assert(Gold(tabs[2]) and animator.shown)
clock = clock + 2; animator.scripts.OnUpdate()
-- The next layout keeps the wheel shown, empty as it is.
Turn:Layout()
assert(Showing(2))
-- Fewer wheels than the one shown: the layout keeps the wheel shown within them.
ns.db.free.wheels = 1
Turn:Layout()
assert(Showing(1) and ns.db.free.page == 1)
ns.db.free.wheels = 4
Turn:Layout()
-- Out of combat, the add-on steps through the same loop.
assert(Turn.Step("right", 1) == 2 and Showing(2))
assert(Turn.Step("right", -1) == 1 and Showing(1))
assert(Turn.Step("right", -1) == 4 and Showing(4))
assert(Turn.Step("right", 1) == 1 and Showing(1))
-- Six wheels, asked for: six tabs, still clear of the chat and on the screen, and the loop
-- goes through them all.
ns.db.free.wheels = 6
Turn:Layout()
for i = 1, 6 do
    assert(tabs[i].shown, "no tab for wheel " .. i)
    local x, y = TabAt(tabs[i])
    assert(ClearOfChat(tabs[i]) and x < -17 and y < H - 17, "tab " .. i .. " of six is on the chat or off the screen")
    assert(math.sqrt(x * x + y * y) >= radius + 32 + 17, "tab " .. i .. " of six sits on the spells")
end
assert(Turn.Step("right", -1) == 6 and Showing(6))
assert(Turn.Step("right", 1) == 1 and Showing(1))
ns.db.free.wheels = 4
Turn:Layout()

-- The left wheel: the right one in a mirror, in the bottom-left corner. Nothing is drawn for
-- either wheel but its tabs.
local left = Named("WolkaraMobileTurnLeft")
assert(left and left.points[1] == "BOTTOMLEFT" and left.mouse == false, "the left wheel's band")
assert(band.disc == nil and left.disc == nil, "a wheel still draws its shadow")
local leftBands = { left }
for page = 2, 6 do leftBands[page] = Named("WolkaraMobileTurnLeft" .. page) end
local leftPages = {}
for page = 1, 6 do
    leftPages[page] = {}
    for i = 1, 12 do leftPages[page][i] = Frame("WolkaraMobileFreeLeft" .. page .. "_" .. i) end
end
local lefts = leftPages[1]
Turn:Attach(leftPages, "left")
local wrappedBefore = wrapCalls
Turn:Layout()
assert(wrapCalls == wrappedBefore + 72 and left.shown)
assert(lefts[1]:GetFrameRef("wheel") == left, "a left spell's code reaches the right wheel")
assert(left:GetAttribute("mirror") == true and left:GetAttribute("corner") == "BOTTOMLEFT")
local function AtLeft(offset)
    for i = 1, 12 do
        local x, y = Where(lefts[i]); local ex, ey = Expected(i, offset)
        if lefts[i].points[3] ~= "BOTTOMLEFT" or math.abs(x + ex) > 1e-6 or math.abs(y - ey) > 1e-6 then return false end
    end
    return true
end
assert(AtLeft(0), "the left spells are not the mirror of the right ones")
-- Its tabs: the right ones in the mirror, still from 1 on the left to 4 on the right.
local leftTabs = {}
for i = 1, 4 do
    leftTabs[i] = assert(Named("WolkaraMobileTurnLeftTab" .. i))
    local tab = leftTabs[i]
    assert(tab.shown and tab.points[3] == "BOTTOMLEFT" and tab:GetFrameRef("pager") == Named("WolkaraMobileTurnLeftPages"))
    local x, y = TabAt(tab)
    local rx, ry = TabAt(tabs[5 - i])
    assert(math.abs(x + rx) < 1e-6 and math.abs(y - ry) < 1e-6, "the left tabs are not the mirror of the right ones")
    if i > 1 then assert(TabAt(leftTabs[i - 1]) < x, "the left tabs do not read from left to right") end
    assert(ClearOfChat(tab, true), "left tab " .. i .. " sits on the chat strip")
end

-- Its secure angle, seen from its own corner and turned in the mirror.
local worstLeft, leftSize = 0, left:GetAttribute("size")
for fx = 0.02, 0.98, 0.04 do
    for fy = 0.02, 0.98, 0.04 do
        left.GetMousePosition = function() return fx, fy end
        Run(lefts[1], "OnMouseDown")
        local exact = math.deg(math.atan2(fy * leftSize, -fx * leftSize))
        worstLeft = math.max(worstLeft, math.abs(left:GetAttribute("downangle") - exact))
    end
end
assert(worstLeft < 0.4, "the left secure angle is off by " .. worstLeft .. " degrees")

-- In combat: a swipe along the left wheel turns it by the rounded notches and does not cast; a
-- touch casts; the right wheel stays as it is.
local function SwipeLeft(spell, from, steps)
    left.GetMousePosition = function() return OnBand(left, from, radius, true) end; Run(lefts[spell], "OnMouseDown")
    left.GetMousePosition = function() return OnBand(left, from + steps * step, radius, true) end; Run(lefts[spell], "OnMouseUp")
    return Run(lefts[spell], "OnClick")
end
combat = true
assert(SwipeLeft(3, 120, 1.6) == false and left:GetAttribute("offset") == 2 and AtLeft(2), "the left wheel did not turn")
assert(SwipeLeft(3, 130, 0.2) == nil and left:GetAttribute("offset") == 2 and AtLeft(2))
-- Its diagonal goes up and to the right, in the mirror, to its next wheel (empty), then back.
local leftPager = Named("WolkaraMobileTurnLeftPages")
local function DiagonalLeft(b, list, spell, dx, dy)
    local s = b:GetAttribute("size")
    b.GetMousePosition = function() return OnBand(b, 135, radius, true) end; Run(list[spell], "OnMouseDown")
    local lx, ly = OnBand(b, 135, radius, true)
    b.GetMousePosition = function() return lx + dx / s, ly + dy / s end; Run(list[spell], "OnMouseUp")
    return Run(list[spell], "OnClick")
end
assert(DiagonalLeft(left, lefts, 4, 60, 60) == false and leftPager:GetAttribute("page") == 2 and not left.shown and leftBands[2].shown)
assert(DiagonalLeft(leftBands[2], leftPages[2], 4, -60, -60) == false and leftPager:GetAttribute("page") == 1 and left.shown)
assert(pager:GetAttribute("page") == 1, "the left diagonal changed the right wheel")
handlers.PLAYER_REGEN_ENABLED()
assert(ns.db.freeLeft.pages[1].turnOffset == 2 and ns.db.free.pages[1].turnOffset == 0)
combat = false

-- Out of combat its spells follow the finger in the mirror, then settle on the notch.
local function CursorLeft(angle) local a = math.rad(angle); cursor = { -math.cos(a) * radius, math.sin(a) * radius } end
CursorLeft(110); lefts[4].hooks.OnMouseDown(lefts[4], "LeftButton")
CursorLeft(110 + step * 0.6); left.scripts.OnUpdate()
assert(AtLeft(2.6), "the left spells did not follow the finger")
lefts[4].hooks.OnMouseUp(lefts[4], "LeftButton")
assert(AtLeft(3) and ns.db.freeLeft.pages[1].turnOffset == 3 and lefts[4].swiped == true, "the left wheel sprang back")
-- A new touch forgets the last swipe, so an empty slot's next touch still opens the picker.
lefts[4].hooks.OnMouseDown(lefts[4], "LeftButton"); lefts[4].hooks.OnMouseUp(lefts[4], "LeftButton")
assert(lefts[4].swiped == nil)

-- Both wheels turning. Reported on the iPhone (2026-11-07): turning one wheel moved the other.
-- A swipe whose release never reached its spell left that wheel following the cursor, so the
-- next swipe, on the other wheel, turned both.
assert(band.shown and At(0) and AtLeft(3))
-- The release that never comes: the left wheel's finger lifts and nothing tells its spell.
CursorLeft(120); lefts[2].hooks.OnMouseDown(lefts[2], "LeftButton")
-- Then a swipe on the right wheel: the left one stops where it was, the right one alone follows.
Cursor(120); buttons[3].hooks.OnMouseDown(buttons[3], "LeftButton")
Cursor(120 + step * 1.6)
band.scripts.OnUpdate(); left.scripts.OnUpdate()
assert(AtLeft(3), "turning the right wheel moved the left one")
assert(At(1.6), "the right wheel did not follow the finger")
-- Its release does not reach the spell either, but the game has seen the finger down and now
-- up: the swipe ends on the nearest notch, kept, and the wheel no longer follows the cursor.
mouseDown = true; band.scripts.OnUpdate()
mouseDown = false; band.scripts.OnUpdate()
assert(At(2) and band:GetAttribute("offset") == 2 and ns.db.free.pages[1].turnOffset == 2, "the unreleased swipe did not settle")
Cursor(170); band.scripts.OnUpdate(); left.scripts.OnUpdate()
assert(At(2) and AtLeft(3), "a wheel still follows the cursor after the finger lifted")
-- The other way round: a swipe on the left wheel leaves the right one alone.
CursorLeft(120); lefts[3].hooks.OnMouseDown(lefts[3], "LeftButton")
CursorLeft(120 + step * 0.6); left.scripts.OnUpdate(); band.scripts.OnUpdate()
assert(AtLeft(3.6) and At(2), "turning the left wheel moved the right one")
lefts[3].hooks.OnMouseUp(lefts[3], "LeftButton")
assert(AtLeft(4) and At(2))

-- In combat, should the game pass the click before the release, a swipe still does not cast,
-- and the release still turns the wheel; a diagonal does not cast either; a touch still casts.
combat = true
band.GetMousePosition = function() return OnBand(band, 120, radius) end; Run(buttons[3], "OnMouseDown")
band.GetMousePosition = function() return OnBand(band, 120 + step * 1.6, radius) end
assert(Run(buttons[3], "OnClick") == false, "a swipe cast its spell when the click came first")
Run(buttons[3], "OnMouseUp")
assert(band:GetAttribute("offset") == 4 and At(4))
band.GetMousePosition = function() return OnBand(band, 135, radius) end; Run(buttons[3], "OnMouseDown")
local fx, fy = OnBand(band, 135, radius)
band.GetMousePosition = function() return fx - 60 / size, fy + 60 / size end
assert(Run(buttons[3], "OnClick") == false, "a diagonal cast its spell when the click came first")
Run(buttons[3], "OnMouseUp")
assert(Showing(2))
band.GetMousePosition = function() return OnBand(band, 130, radius) end; Run(buttons[3], "OnMouseDown")
assert(Run(buttons[3], "OnClick") == nil, "a touch no longer casts")
combat = false

print(string.format("mobile add-on turning wheels: secure angle within %.2f deg (left %.2f); swipe on a spell turns without casting, touch casts, nothing else caught, left is the mirror, one wheel turns at a time even when a release goes unreported, press/release on the template the game accepts, a released wheel keeps its notch; four wheels a side by default (one to six), a diagonal goes to the next or previous one, empty or not, in a loop, in and out of combat without casting, never mistaken for a turn; numbered secure tabs above the wheel switch straight to theirs and show the one up; the wheel that comes lights up spell after spell in the swipe's direction; right button left to moving: PASS", worst, worstLeft))
