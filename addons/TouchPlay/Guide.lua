-- TouchPlay: the touch guide (rule 8, Task 14; mockups 101, 102, 103).
--
-- The first time touch mode starts (TouchPlayDB.guideDone is not set) four short steps run, each dimming
-- everything but the part it is about (a spotlight), drawing a finger doing the gesture, and saying it in
-- plain words (ns.L["guide.1"] to ["guide.4"]); Next and Skip are big red buttons in the same place every
-- time. Skip, or the end, ends on one closing card ("You're ready", Play), and Menu glows once so the player
-- knows where the guide lives: Menu > Touch guide shows it again. It never starts by itself a second time
-- (guideDone is written the moment it starts), waits for the end of a fight, and does nothing while touch
-- mode is off or paused. It also waits while the reload notice is up (Contract starts it once there is
-- nothing to reload): on the very first run the player reloads first, and the guide opens after that.
--
--   1 Walk              the walk side: the left (the right when left-handed)
--   2 Look and target   the middle of the screen
--   3 Cast, and hold    the spell cluster as it sits now (read from the cluster's own placement)
--   4 Interact and Jump the Interact and Jump rings as they sit now
-- The finger is an animation group (no OnUpdate); with Reduce motion on it stays where it is.

local ADDON_NAME, ns = ...

local Guide = ns.Register("Guide", {})
local Kit = ns.Kit

ns.L["guide.counter"] = "%d of 4"
ns.L["guide.title.1"] = "Walk"
ns.L["guide.title.2"] = "Look and target"
ns.L["guide.title.3"] = "Cast, and hold to read"
ns.L["guide.title.4"] = "Interact and Jump"
ns.L["guide.1"] = "Put your thumb anywhere on the left and slide. The stick appears under it. Push to the edge and let go to keep running."
ns.L["guide.1.right"] = "Put your thumb anywhere on the right and slide. The stick appears under it. Push to the edge and let go to keep running."
ns.L["guide.2"] = "Drag the world with one finger to look around; your character turns with you. Tap an enemy to target it. Pinch to zoom."
ns.L["guide.3"] = "Tap a spell to cast it. Hold any button or person for its card: what it does, and what you can do with it."
ns.L["guide.4"] = "Interact does whatever is nearest: Talk, Loot, Open, Reel in. Jump is beside it."
ns.L["guide.skip"] = "Skip"
ns.L["guide.next"] = "Next"
ns.L["guide.done"] = "Done"
ns.L["guide.ready"] = "You're ready"
ns.L["guide.ready.body"] = "You can open this guide again from Menu › Touch guide."
ns.L["guide.play"] = "Play"

local REF_W, REF_H = 1366, 1024
local STEPS = 4
local CARD_W, CARD_H = 487, 235
local CARD_AT = { { 646, 307 }, { 52, 650 }, { 443, 309 }, { 445, 309 } }       -- mockups 101, 102
local WALK_HOLE = { 19, 477, 563, 523 }
local LOOK_HOLE = { 563, 99, 502, 606 }
local PAD, GLOW_SECONDS = 16, 8
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }
local DOT = "Interface\\Common\\Indicator-Yellow"
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local GLOW_ART = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local WHITE_ART = "Interface\\Buttons\\WHITE8x8"

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, Kit.FONT_TITLE, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- ---------------------------------------------------------------------------------------
-- The dim with a hole, the gold outline of the hole

local dim = CreateFrame("Button", nil, ns.root)
dim:SetAllPoints(ns.root)
dim:SetFrameStrata("DIALOG")
dim:SetFrameLevel(200)
dim:Hide()
Guide.dim = dim
dim.sides = {}
for i = 1, 4 do
    local t = dim:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE_ART)
    t:SetVertexColor(0, 0, 0, 0.74)
    dim.sides[i] = t
end

local outline = Kit.Backdrop(dim, "tooltip", "tooltip")
outline:SetBackdropColor(0, 0, 0, 0)
outline:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
outline:EnableMouse(false)
Guide.outline = outline

-- Lays the four dark pieces around the hole (layout units from the top-left of the screen).
local function SetHole(x, y, w, h)
    Guide.hole = { x = x, y = y, w = w, h = h }
    local top, bottom, left, right = unpack(dim.sides)
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", dim, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", dim, "TOPRIGHT", 0, 0)
    top:SetHeight(math.max(0, y))
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", dim, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", dim, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(math.max(0, REF_H - (y + h)))
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", dim, "TOPLEFT", 0, -y)
    left:SetSize(math.max(0, x), h)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", dim, "TOPLEFT", x + w, -y)
    right:SetPoint("TOPRIGHT", dim, "TOPRIGHT", 0, -y)
    right:SetHeight(h)
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", dim, "TOPLEFT", x, -y)
    outline:SetSize(w, h)
end

-- The box round some placed frames, with a margin, kept on the screen.
local function Around(frames, fallback)
    local x1, y1, x2, y2
    for _, f in ipairs(frames) do
        local a = f and f.touchAnchor
        if a and a.x then
            x1 = math.min(x1 or a.x, a.x); y1 = math.min(y1 or a.y, a.y)
            x2 = math.max(x2 or a.x + a.w, a.x + a.w); y2 = math.max(y2 or a.y + a.h, a.y + a.h)
        end
    end
    if not x1 then return unpack(fallback) end
    x1, y1, x2, y2 = math.max(0, x1 - PAD), math.max(0, y1 - PAD), math.min(REF_W, x2 + PAD), math.min(REF_H, y2 + PAD)
    return x1, y1, x2 - x1, y2 - y1
end

-- The part each step is about, and the middle of the finger's gesture.
local function Spotlight(step)
    local left = ns.LeftHanded()
    if step == 1 then
        local x, y, w, h = unpack(WALK_HOLE)
        if left then x = REF_W - x - w end
        return x, y, w, h
    elseif step == 2 then
        return unpack(LOOK_HOLE)
    elseif step == 3 then
        local list = {}
        local c = ns.Cluster
        if c then
            for _, b in ipairs(c.buttons) do list[#list + 1] = b end
            for _, b in ipairs(c.pageBoxes) do list[#list + 1] = b end
            list[#list + 1] = c.nextTarget
        end
        return Around(list, { 1013, 541, 353, 480 })
    end
    local i = ns.Interact
    return Around({ i and i.interact, i and i.jump }, { 883, 772, 322, 252 })
end

-- ---------------------------------------------------------------------------------------
-- The finger: a disc, a glow and an arrow

local finger = CreateFrame("Frame", nil, dim)
finger:SetSize(80, 80)
finger:EnableMouse(false)
finger:SetFrameLevel(215)
finger:Hide()
Guide.finger = finger
finger.disc = finger:CreateTexture(nil, "ARTWORK")
finger.disc:SetTexture(DISC)
finger.disc:SetVertexColor(1, 1, 1, 0.55)
finger.disc:SetSize(76, 76)
finger.disc:SetPoint("CENTER", finger, "CENTER", 0, 0)
finger.glow = finger:CreateTexture(nil, "OVERLAY")
finger.glow:SetTexture(GLOW_ART)
finger.glow:SetBlendMode("ADD")
finger.glow:SetSize(100, 100)
finger.glow:SetPoint("CENTER", finger, "CENTER", 0, 0)
finger.arrow = finger:CreateTexture(nil, "OVERLAY")
finger.arrow:SetTexture(ARROW)
finger.arrow:SetSize(56, 56)
finger.slide = finger:CreateAnimationGroup()
finger.slide:SetLooping("REPEAT")
finger.slideMove = finger.slide:CreateAnimation("Translation")
finger.slideMove:SetDuration(1.1)
finger.tap = finger:CreateAnimationGroup()
finger.tap:SetLooping("BOUNCE")
do
    local a = finger.tap:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.4)
    a:SetDuration(0.6)
end

-- Per step: where the finger rests and which way the stroke goes (dx, dy in layout units, y up).
local function PlaceFinger(step)
    local x, y, w, h = Guide.hole.x, Guide.hole.y, Guide.hole.w, Guide.hole.h
    local cx, cy, dx, dy
    if step == 1 then
        cx, cy, dx, dy = x + w * 0.44, y + h * 0.84, 60, 60
        local sign = ns.LeftHanded() and -1 or 1
        dx = dx * sign
    elseif step == 2 then
        cx, cy, dx, dy = x + w * 0.34, y + h * 0.5, 90, 0
    else
        local a = (step == 3 and ns.Cluster and ns.Cluster.buttons[1] or ns.Interact and ns.Interact.interact)
        local at = a and a.touchAnchor
        cx, cy = at and (at.x + at.w / 2) or (x + w / 2), at and (at.y + at.h / 2) or (y + h / 2)
        dx, dy = 0, 0
    end
    finger:ClearAllPoints()
    finger:SetPoint("CENTER", dim, "TOPLEFT", cx, -cy)
    finger.arrow:ClearAllPoints()
    if dx ~= 0 or dy ~= 0 then
        finger.arrow:SetPoint("CENTER", finger, "CENTER", dx * 0.9, dy * 0.9 + (dy == 0 and 0 or 20))
        finger.arrow:SetRotation(-math.atan2(dx, dy))
        finger.arrow:Show()
    else
        finger.arrow:Hide()
    end
    finger.slide:Stop(); finger.tap:Stop()
    finger.slideMove:SetOffset(dx, dy)
    finger.group = (dx ~= 0 or dy ~= 0) and finger.slide or finger.tap
    finger:Show()
    -- Reduce motion: the finger stays where it rests
    if not ns.ReduceMotion() then finger.group:Play() end
end

-- ---------------------------------------------------------------------------------------
-- The step card

local card = Kit.Backdrop(dim, "gold", "dark")
card:SetSize(CARD_W, CARD_H)
card:SetFrameLevel(220)
card:EnableMouse(true)
Guide.card = card
Guide.counter = Text(card, 14, { 0.85, 0.85, 0.85 })
Guide.counter:SetPoint("TOPLEFT", card, "TOPLEFT", 22, -20)
Guide.title = Text(card, 28, GOLD)
Guide.title:SetPoint("TOPLEFT", card, "TOPLEFT", 22, -38)
Guide.body = Text(card, 19, WHITE)
Guide.body:SetJustifyV("TOP")
Guide.body:SetWidth(CARD_W - 44)
Guide.body:SetPoint("TOPLEFT", card, "TOPLEFT", 22, -84)
card.dots = {}
for i = 1, STEPS do
    local d = card:CreateTexture(nil, "OVERLAY")
    d:SetTexture(DOT)
    d:SetSize(16, 16)
    d:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 24 + (i - 1) * 26, 36)
    card.dots[i] = d
end
Guide.skipButton = Kit.RedButton(card, 102, 44, ns.T("guide.skip"))
Guide.nextButton = Kit.RedButton(card, 102, 44, ns.T("guide.next"))
Guide.nextButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -22, 22)
Guide.skipButton:SetPoint("BOTTOMRIGHT", Guide.nextButton, "BOTTOMLEFT", -16, 0)

-- The closing card
local final = Kit.Backdrop(dim, "gold", "dark")
final:SetSize(488, 207)
final:SetFrameLevel(220)
final:EnableMouse(true)
final:Hide()
Guide.final = final
Guide.finalTitle = Text(final, 34, GOLD, "CENTER")
Guide.finalTitle:SetPoint("TOP", final, "TOP", 0, -28)
Guide.finalTitle:SetWidth(440)
Guide.finalTitle:SetText(ns.T("guide.ready"))
Guide.finalBody = Text(final, 22, WHITE, "CENTER")
Guide.finalBody:SetPoint("TOP", final, "TOP", 0, -80)
Guide.finalBody:SetWidth(420)
Guide.finalBody:SetText(ns.T("guide.ready.body"))
Guide.playButton = Kit.RedButton(final, 187, 44, ns.T("guide.play"))
Guide.playButton:SetPoint("BOTTOM", final, "BOTTOM", 0, 22)

-- ---------------------------------------------------------------------------------------
-- Menu glows once

local glow = CreateFrame("Frame", nil, ns.root)
glow:SetSize(96, 96)
glow:EnableMouse(false)
glow:SetFrameStrata("DIALOG")
glow:SetFrameLevel(150)
glow:Hide()
glow.art = glow:CreateTexture(nil, "OVERLAY")
glow.art:SetTexture(GLOW_ART)
glow.art:SetBlendMode("ADD")
glow.art:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
glow.art:SetAllPoints(glow)
glow.pulse = glow:CreateAnimationGroup()
glow.pulse:SetLooping("BOUNCE")
do
    local a = glow.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)
end
Guide.glow = glow

local glowTimer
local function StopGlow()
    if glowTimer then glowTimer:Cancel(); glowTimer = nil end
    glow.pulse:Stop()
    glow:Hide()
end

-- Only the first time the guide ends: the Menu ring glows so the player knows where the guide lives.
local function GlowOnce()
    if ns.db.guideGlowed then return end
    local menu = ns.Hud and ns.Hud.menu
    if not menu then return end
    ns.db.guideGlowed = true
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", menu, "CENTER", 0, 0)
    glow:Show()
    if not ns.ReduceMotion() then glow.pulse:Play() end
    glowTimer = C_Timer.NewTimer(GLOW_SECONDS, StopGlow)
end

-- ---------------------------------------------------------------------------------------
-- Steps, show and hide

function Guide.IsShown() return dim:IsShown() end

local function ShowStep(step)
    Guide.step = step
    final:Hide()
    card:Show()
    local x, y, w, h = Spotlight(step)
    SetHole(x, y, w, h)
    Guide.counter:SetText(ns.T("guide.counter", step))
    Guide.title:SetText(ns.T("guide.title." .. step))
    local key = "guide." .. step
    if step == 1 and ns.LeftHanded() then key = "guide.1.right" end
    Guide.body:SetText(ns.T(key))
    for i, d in ipairs(card.dots) do
        if i == step then d:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]) else d:SetVertexColor(0.4, 0.4, 0.4) end
    end
    Guide.nextButton.label:SetText(ns.T(step == STEPS and "guide.done" or "guide.next"))
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", dim, "TOPLEFT", CARD_AT[step][1], -CARD_AT[step][2])
    PlaceFinger(step)
end

local function ShowFinal()
    card:Hide()
    finger.slide:Stop(); finger.tap:Stop()
    finger:Hide()
    for _, side in ipairs(dim.sides) do side:Show() end
    SetHole(REF_W / 2, REF_H / 2, 0, 0)
    outline:Hide()
    final:ClearAllPoints()
    final:SetPoint("TOPLEFT", dim, "TOPLEFT", (REF_W - 488) / 2, -336)
    final:Show()
end

function Guide.Hide()
    finger.slide:Stop(); finger.tap:Stop()
    final:Hide(); card:Hide(); finger:Hide()
    dim:Hide()
end

-- Shows the guide from step 1. The Menu's Touch guide button asks for it again.
function Guide.Show()
    outline:Show()
    dim:Show()
    StopGlow()
    ShowStep(1)
    Kit.Sound("open")
end

local function Next()
    if Guide.step < STEPS then ShowStep(Guide.step + 1) else ShowFinal() end
end

-- A swipe (Swipe.lua): the next step (as Next) or the one before. Answers whether it turned.
function Guide.Turn(dir)
    if not dim:IsShown() or not card:IsShown() then return false end
    if dir > 0 then Next(); return true end
    if (Guide.step or 1) > 1 then ShowStep(Guide.step - 1); return true end
    return false
end

Guide.nextButton:SetScript("OnClick", function() ns.Guard("guide next", Next) end)
Guide.skipButton:SetScript("OnClick", function() ns.Guard("guide skip", ShowFinal) end)
Guide.playButton:SetScript("OnClick", function()
    Guide.Hide()
    ns.Guard("guide glow", GlowOnce)
end)

-- ---------------------------------------------------------------------------------------
-- The first time

local function MaybeStart()
    if not ns.db or ns.db.guideDone or not ns.IsActive() or InCombatLockdown() then return end
    local contract = ns.Contract
    if contract and contract.notice and (contract.notice:IsShown() or contract.loadedAtLogin ~= ns.db.contract) then return end
    ns.db.guideDone = true
    Guide.Show()
end
Guide.MaybeStart = MaybeStart

ns.On("PLAYER_REGEN_ENABLED", MaybeStart)

-- (No start from Layout: Contract lays out last and starts the guide itself, once it knows whether the
-- reload notice is up.)

function Guide:Restore()
    StopGlow()
    Guide.Hide()
end
