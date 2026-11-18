-- TouchPlay: the layout root and the shared parts every screen is built from.
--
-- Layout space: ns.root is 1024 units tall at any screen size, so one unit is screen height
-- / 1024 and the mockups (1366 x 1024) carry over. ns.Anchor places a frame by its mockup
-- top-left, measured from the nearest screen corner. ns.moveRoot is the same space for the
-- Interact, Jump and Dive faces, which stay when ns.root is hidden by a pause.
--
-- ns.Kit holds the pieces in the game's own art, drawn to the proportions of the mockups
-- (mockups/forever-style/source/index.html: backdrop, goldHeader, redButton, ringButton), except the ring
-- buttons, glyphs, page box and minimap ring, which use the add-on's own sharp art in Art/ (R48).
-- Every touch area is at least 44 x 44 units; art may be smaller than its area.

local ADDON_NAME, ns = ...

local REF_W, REF_H = 1366, 1024      -- the mockups' size in layout units
local MIN_TAP = 44

local FONT_TITLE = "Fonts\\FRIZQT__.TTF"
local FONT_NUMBER = "Fonts\\ARIALN.TTF"

local Kit = {}
ns.Kit = Kit
Kit.FONT_TITLE, Kit.FONT_NUMBER = FONT_TITLE, FONT_NUMBER

-- Other alphabets (iPad run 5: other players' Cyrillic chat came out as boxes). A font file set with SetFont draws
-- only its own letters; the game's font objects are font families that switch file per alphabet. So every TouchPlay
-- text gets a family made with CreateFontFamily: our file for Latin, the game's own files for the others, as its
-- families have them (Blizzard_Fonts_Shared/Shared/Fonts.xml:275 SystemFont_Shadow_Med1 for the title face,
-- Blizzard_Fonts_Shared/Mainline/Fonts.xml:775 NumberFont_Shadow_Med, which ChatFontNormal inherits, for numbers).
Kit.ALPHABETS = {
    [FONT_TITLE] = {
        russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF",
        simplifiedchinese = "Fonts\\ARKai_T.ttf", traditionalchinese = "Fonts\\blei00d.TTF",
    },
    [FONT_NUMBER] = {
        russian = "Fonts\\ARIALN.TTF", korean = "Fonts\\2002.TTF",
        simplifiedchinese = "Fonts\\ARHei.ttf", traditionalchinese = "Fonts\\arheiuhk_bd.TTF",
    },
}
local ALPHABET_ORDER = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
local families = {}         -- "file|size|flags" -> font family
local familyCount = 0

-- The font family for `file` at `size` with `flags` (made once; nil when this client has no CreateFontFamily).
function Kit.FontFamily(file, size, flags)
    if type(CreateFontFamily) ~= "function" then return nil end
    flags = flags or ""
    size = math.floor((size or 12) + 0.5)
    local key = file .. "|" .. size .. "|" .. flags
    local family = families[key]
    if family then return family end
    local others = Kit.ALPHABETS[file] or Kit.ALPHABETS[FONT_TITLE]
    local members = {}
    for _, alphabet in ipairs(ALPHABET_ORDER) do
        members[#members + 1] = { alphabet = alphabet, file = alphabet == "roman" and file or others[alphabet],
            height = size, flags = flags }
    end
    familyCount = familyCount + 1
    local ok, made = pcall(CreateFontFamily, "TouchPlayFont" .. familyCount, members)
    if not ok or not made then return nil end
    families[key] = made
    return made
end

-- Sets `fs`'s font: the family (every alphabet) when the client can make one, else the plain file. The colour,
-- justification and shadow set on the string before stay (a font object brings its own).
function Kit.SetFont(fs, file, size, flags)
    local family = Kit.FontFamily(file, size, flags)
    if not family or not fs.SetFontObject then return fs:SetFont(file, size, flags or "") end
    local r, g, b, a
    if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end
    local justifyH = fs.GetJustifyH and fs:GetJustifyH()
    local justifyV = fs.GetJustifyV and fs:GetJustifyV()
    local sx, sy
    if fs.GetShadowOffset then sx, sy = fs:GetShadowOffset() end
    local sr, sg, sb, sa
    if fs.GetShadowColor then sr, sg, sb, sa = fs:GetShadowColor() end
    fs:SetFontObject(family)
    if r and fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
    if justifyH and fs.SetJustifyH then fs:SetJustifyH(justifyH) end
    if justifyV and fs.SetJustifyV then fs:SetJustifyV(justifyV) end
    if sx and fs.SetShadowOffset then fs:SetShadowOffset(sx, sy) end
    if sr and fs.SetShadowColor then fs:SetShadowColor(sr, sg, sb, sa) end
    return true
end
Kit.MIN_TAP = MIN_TAP

-- ---------------------------------------------------------------------------------------
-- Layout roots

ns.root = CreateFrame("Frame", "TouchPlayRoot", UIParent)
ns.moveRoot = CreateFrame("Frame", "TouchPlayMoveRoot", UIParent)
-- The play screen is LOW, as the game's own unit frames are (iPad run 6): under every game window (bags, map,
-- character, vendor ... are MEDIUM or HIGH; Bagnon is HIGH by default), over the world's BACKGROUND layers. Set here,
-- before any frame is made under the roots, so every frame takes it when made and none changes later (a secure
-- frame's strata cannot change in a fight). TouchPlay's sheets and cards set DIALOG or higher on themselves
-- (Kit.SHEET_STRATA): they stay above every window.
Kit.PLAY_STRATA, Kit.SHEET_STRATA = "LOW", "DIALOG"
for _, root in ipairs({ ns.root, ns.moveRoot }) do
    root:SetFrameStrata(Kit.PLAY_STRATA)
    root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    root:EnableMouse(false)
end

local function ApplyScale()
    local height, width = UIParent:GetHeight(), UIParent:GetWidth()
    if not height or height <= 0 then return end
    local scale = height / REF_H
    for _, root in ipairs({ ns.root, ns.moveRoot }) do
        root:SetScale(scale)
        root:SetSize(width / scale, REF_H)
    end
end
ApplyScale()

local function ApplyScaleOutOfCombat() ns.Queue("style scale", ApplyScale) end
ns.On("UI_SCALE_CHANGED", ApplyScaleOutOfCombat)
ns.On("DISPLAY_SIZE_CHANGED", ApplyScaleOutOfCombat)
ns.Register("Style", { Layout = ApplyScale })

local function RootOf(frame)
    local f = frame
    while f do
        if f == ns.moveRoot then return ns.moveRoot end
        f = f:GetParent()
    end
    return ns.root
end

-- ---------------------------------------------------------------------------------------
-- The player's Touch settings that change where things go (Feel.lua edits them; the values and
-- their defaults live in Contract.lua). Before the Contract has loaded nothing is changed.

local function FeelValue(key)
    local contract = ns.Contract
    if contract and contract.GetFeel then return contract.GetFeel(key) end
    return nil
end
ns.FeelValue = FeelValue

function ns.LeftHanded() return FeelValue("leftHanded") == true end

-- Reduce motion: the player's choice, else the game's own "reduce unexpected movement" setting (the
-- game sets it from the iPad's Reduce Motion). Every pulse and flight asks here (Units, Picker, Loot,
-- Guide) and stops or fades in place when it is true.
function ns.ReduceMotion()
    local saved = ns.db and ns.db.feel
    local mine
    if type(saved) == "table" then mine = saved.reduceMotion end
    if type(mine) == "boolean" then return mine end
    local read = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    if read then
        local ok, on = pcall(read, "CameraReduceUnexpectedMovement")
        if ok and on then return true end
    end
    return false
end

local FLIP = { TL = "TR", TR = "TL", BL = "BR", BR = "BL" }
function ns.MirrorCorner(corner) return FLIP[corner] or corner end

local STAND_DROP = 40        -- "iPad on a stand": the thumb side sits this much nearer the bottom edge

-- What each kind of placed thing follows. thumb: the spells, items, Interact, Jump (mirrored, lowered
-- on a stand, scaled by Button size); side: mirrored only (the chat strip); text: scaled by Text size
-- (the quest list); sidetext: both (the chat lines).
local KINDS = {
    thumb = { mirror = true, stand = true, scale = "buttonSize" },
    side = { mirror = true },
    text = { scale = "textSize" },
    sidetext = { mirror = true, scale = "textSize" },
}

-- Places `frame` (its size already set) so its top-left sits at mockup (x, y), as offsets from
-- `corner`: "TL", "TR", "BL" or "BR". The mockup position and size are kept in
-- frame.touchAnchor for the layout contract (Task 3).
--
-- `kind` (true means "thumb") says which Touch settings move this frame: left-handed mirrors it
-- (x becomes 1366 - x - w, the corner flips), "iPad on a stand" lowers it, and Button size or Text
-- size scales its distances and its size around the corner it counts from. A frame with no kind
-- stays where the mockup has it.
-- Where a frame of size (w, h) placed at mockup (x, y) from `corner` with `kind` ends up under the current Touch
-- settings: the corner it counts from, its top-left (x, y) and size (w, h) in layout units, whether it is mirrored,
-- and its scale. Pure: ns.Anchor uses it, and a module that must keep clear of another's frames can ask it (through
-- ns.Final) whatever order the modules lay out in.
function ns.Placed(corner, x, y, w, h, kind)
    local mirrored, scale = false, 1
    local follows = kind and KINDS[kind == true and "thumb" or kind]
    if kind and not follows then error("TouchPlay: unknown placement kind " .. tostring(kind), 2) end
    if follows then
        if follows.mirror and ns.LeftHanded() then
            x, corner, mirrored = REF_W - x - w, FLIP[corner], true
        end
        if follows.stand and FeelValue("stand") then y = math.min(y + STAND_DROP, REF_H - h) end
        scale = follows.scale and FeelValue(follows.scale) or 1
        if scale ~= 1 then
            local right, bottom = REF_W - (x + w), REF_H - (y + h)
            local dx = (corner == "TL" or corner == "BL") and x or right
            local dy = (corner == "TL" or corner == "TR") and y or bottom
            dx, dy, w, h = dx * scale, dy * scale, w * scale, h * scale
            x = (corner == "TL" or corner == "BL") and dx or REF_W - dx - w
            y = (corner == "TL" or corner == "TR") and dy or REF_H - dy - h
        end
    end
    return corner, x, y, w, h, mirrored, scale, follows
end

-- Where a frame placed with ns.Anchor is under the current Touch settings (x, y, w, h in layout units), worked out
-- from what it was placed with, so it is right even before its own module has laid out again. Nil if never placed.
function ns.Final(frame)
    local a = frame and frame.touchAnchor
    if not a or not a.inCorner then return nil end
    local w, h = frame:GetSize()
    local _, x, y, fw, fh = ns.Placed(a.inCorner, a.inX, a.inY, w, h, a.kind)
    return x, y, fw, fh
end

-- A rectangle grown to the smallest touch area (44 units) around its centre, as the contract grows it.
function ns.TapRect(x, y, w, h)
    if w < MIN_TAP then x = x - (MIN_TAP - w) / 2; w = MIN_TAP end
    if h < MIN_TAP then y = y - (MIN_TAP - h) / 2; h = MIN_TAP end
    return x, y, w, h
end

-- The thumb side's touch areas (the spell buttons, page boxes, Next target, Interact, Jump and Dive), grown to 44
-- and where they are under the current Touch settings, into `list` as { x, y, w, h }. Something laid out beside
-- them (the pet row, the chat strip) keeps clear of these. Dive counts even while hidden: it appears in water or on a
-- mount, in a fight too, when nothing may move.
function ns.ThumbAreas(list)
    local n = 0
    local function add(frame)
        local x, y, w, h = ns.Final(frame)
        if not x then return end
        x, y, w, h = ns.TapRect(x, y, w, h)
        n = n + 1
        local o = list[n] or {}
        list[n] = o
        o.x, o.y, o.w, o.h = x, y, w, h
    end
    local cluster, interact = ns.Cluster, ns.Interact
    if cluster then
        for _, b in ipairs(cluster.buttons) do add(b) end
        for _, b in ipairs(cluster.pageBoxes) do add(b) end
        add(cluster.nextTarget)
    end
    if interact then add(interact.interact); add(interact.jump); add(interact.dive) end
    for i = n + 1, #list do list[i] = nil end
    return list
end

-- The app's own buttons over the game (iPad run 5): its toolbar sits in the top-centre band, folded (96 x 34 points) or
-- open (208 x 44 points: 255 x 54 layout units on the 834-point-tall iPad), and was seen at the bottom centre too
-- (x 614..860, y 939..982 on the 1486-wide iPad; the app keeps it at the top from 546e31e on). No TouchPlay card or the
-- game's buffs may sit there. As { x, y, w, h } in layout units, centred on the root's real width (the screen's), into
-- `list`.
ns.APP_TOP_W, ns.APP_TOP_H = 270, 60            -- top centre: the open toolbar with a margin
ns.APP_BOTTOM_W, ns.APP_BOTTOM_H = 260, 100     -- bottom centre: the band the card keeps off
function ns.AppBands(list)
    list = list or {}
    local width = (ns.root and ns.root:GetWidth()) or REF_W
    if not width or width <= 0 then width = REF_W end
    local top = list[1] or {}
    top.name, top.x, top.y, top.w, top.h = "app toolbar (top)", width / 2 - ns.APP_TOP_W / 2, 0, ns.APP_TOP_W, ns.APP_TOP_H
    local bottom = list[2] or {}
    bottom.name, bottom.x, bottom.y, bottom.w, bottom.h = "app toolbar (bottom)", width / 2 - ns.APP_BOTTOM_W / 2,
        REF_H - ns.APP_BOTTOM_H, ns.APP_BOTTOM_W, ns.APP_BOTTOM_H
    list[1], list[2] = top, bottom
    for i = 3, #list do list[i] = nil end
    return list
end

function ns.Anchor(frame, corner, x, y, kind)
    if not FLIP[corner] then error("TouchPlay: unknown corner " .. tostring(corner), 2) end
    local inCorner, inX, inY = corner, x, y
    local w, h = frame:GetSize()
    local mirrored, scale, follows
    corner, x, y, w, h, mirrored, scale, follows = ns.Placed(corner, x, y, w, h, kind)
    -- only a frame that follows a setting has its scale managed here (the cards keep their own 1.5)
    if follows and frame:GetScale() ~= scale then frame:SetScale(scale) end
    local root = RootOf(frame)
    -- the offsets are in the frame's own units: a frame scaled here counts them in its own scale
    local own = follows and scale or 1
    local right, bottom = (REF_W - (x + w)) / own, (REF_H - (y + h)) / own
    local px, py = x / own, y / own
    frame:ClearAllPoints()
    if corner == "TL" then
        frame:SetPoint("TOPLEFT", root, "TOPLEFT", px, -py)
    elseif corner == "TR" then
        frame:SetPoint("TOPRIGHT", root, "TOPRIGHT", -right, -py)
    elseif corner == "BL" then
        frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", px, bottom)
    else
        frame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -right, bottom)
    end
    local a = frame.touchAnchor
    if not a then a = {}; frame.touchAnchor = a end
    a.corner, a.x, a.y, a.w, a.h, a.mirrored = corner, x, y, w, h, mirrored
    a.inCorner, a.inX, a.inY, a.kind = inCorner, inX, inY, kind
end

-- ---------------------------------------------------------------------------------------
-- Small helpers

-- Grows a touch area under 44 units with negative hit-rect insets. Call again after a resize.
function Kit.FitHit(frame)
    local w, h = frame:GetSize()
    local dx = w < MIN_TAP and (MIN_TAP - w) / 2 or 0
    local dy = h < MIN_TAP and (MIN_TAP - h) / 2 or 0
    frame:SetHitRectInsets(-dx, -dx, -dy, -dy)
end

-- The game's own action button (ActionBarButtonTemplate, PetActionButtonTemplate) is made for a 45 unit button:
-- its icon texture has no anchors of its own, its round mask and its frame, push, glow and flash art are sized
-- 31 to 51 units at the top-left. On a button of ours (64, 88, 52) the icon came out about half the box with the
-- frame far outside it (iPad run 1). This makes the icon fill the box with the game's Quickslot frame round it
-- (as the item column), and the glows follow the box. Textures only: safe in a fight, nothing protected changes.
local QUICKSLOT = "Interface\\Buttons\\UI-Quickslot2"
local QUICKSLOT_RATIO = 1.68              -- the Quickslot frame is 1.68 x the icon
Kit.QUICKSLOT, Kit.QUICKSLOT_RATIO = QUICKSLOT, QUICKSLOT_RATIO

Kit.TEMPLATE_BUTTON = 45                  -- ActionButtonTemplate's own size

function Kit.FitActionButton(b, d)
    local icon = b.icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(b)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        -- the round mask cuts the corners the carved frame shows
        if b.IconMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(b.IconMask) end
    end
    b:SetNormalTexture(QUICKSLOT)
    local frame = b:GetNormalTexture()
    if frame then
        local off = (math.floor(d * QUICKSLOT_RATIO + 0.5) - d) / 2
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", b, "TOPLEFT", -off, off)
        frame:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", off, -off)
    end
    local parts = { b.GetPushedTexture and b:GetPushedTexture(), b.GetHighlightTexture and b:GetHighlightTexture(),
        b.GetCheckedTexture and b:GetCheckedTexture(), b.Border, b.Flash, b.NewActionTexture, b.SpellHighlightTexture }
    for _, part in pairs(parts) do
        if part ~= frame then
            part:ClearAllPoints()
            part:SetAllPoints(b)
        end
    end
    -- no hover look (polish pass): the pointer stays where the last plain tap left it, and the template's hover
    -- highlight stayed lit on the button under it. The press look (Kit.AddPress) is the feedback.
    local hover = b.GetHighlightTexture and b:GetHighlightTexture()
    if hover then hover:SetAlpha(0) end
    -- the template's "casting this" and aiming animations (ActionButtonSpellFXTemplate) are 128 units for a 45-unit
    -- button, centred: they grow with ours so the cast ring sits on the frame, not inside the icon
    local fxScale = d / Kit.TEMPLATE_BUTTON
    for _, key in ipairs({ "SpellCastAnimFrame", "TargetReticleAnimFrame" }) do
        local fx = rawget(b, key)
        if type(fx) == "table" and fx.SetScale then fx:SetScale(fxScale) end
    end
end

-- Out of range (mockup 10: the whole icon goes red). The game's template shows range only on the key label
-- (ActionButton_UpdateRangeIndicator colours HotKey), which TouchPlay hides, so out of range showed nothing. A red
-- veil over the icon follows the same call instead. Its two answers may be hidden values in a fight: they go
-- straight to SetAlphaFromBoolean, one per layer (the frame: the slot checks range; the veil: not in range), so
-- nothing compares them.
local RANGE_RED = { 0.95, 0.12, 0.08, 0.5 }

local function AlphaFrom(region, flag, yes, no)
    if type(flag) == "nil" then flag = false end
    if region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(flag, yes, no)
    elseif ns.Plain(flag) then
        region:SetAlpha(flag and yes or no)
    end
end

local function ShowRange(button, checksRange, inRange)
    local r = button and button.touchRange
    if not r then return end
    AlphaFrom(r.frame, checksRange, 1, 0)
    AlphaFrom(r.veil, inRange, 0, 1)
end
Kit.ShowRange = ShowRange

local rangeHooked = false
function Kit.AddRange(b)
    local frame = CreateFrame("Frame", nil, b)
    frame:SetAllPoints(b)
    frame:SetFrameLevel(b:GetFrameLevel() + 2)
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    local veil = frame:CreateTexture(nil, "OVERLAY")
    veil:SetAllPoints(b)
    veil:SetColorTexture(RANGE_RED[1], RANGE_RED[2], RANGE_RED[3], RANGE_RED[4])
    veil:SetBlendMode("BLEND")
    veil:SetAlpha(0)
    b.touchRange = { frame = frame, veil = veil }
    if not rangeHooked and type(ActionButton_UpdateRangeIndicator) == "function" then
        rangeHooked = true
        hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
            if type(self) == "table" and self.touchRange then
                local ok, problem = pcall(ShowRange, self, checksRange, inRange)
                if not ok and ns.RememberError then ns.RememberError("range: " .. tostring(problem)) end
            end
        end)
    end
end

local SOUND_KEYS = {
    tap = "IG_MAINMENU_OPTION_CHECKBOX_ON", open = "IG_MAINMENU_OPEN",
    close = "IG_MAINMENU_CLOSE", error = "IG_QUEST_FAILED",
}
function Kit.Sound(name)
    -- Touch settings > Tap sounds: off silences the tap sound (opening and closing keep theirs)
    if name == "tap" and FeelValue("tapSounds") == false then return end
    local key = SOUND_KEYS[name]
    local id = key and SOUNDKIT and SOUNDKIT[key]
    if id and PlaySound then PlaySound(id) end
end

local function PlayTap() Kit.Sound("tap") end

local function NewText(parent, size, layer, font)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Kit.SetFont(fs, font or FONT_TITLE, size, "")
    return fs
end

-- ---------------------------------------------------------------------------------------
-- Press feedback (polish pass, 18 Nov; after iPad run 8: "highlights when clicking buttons")
--
-- Every control TouchPlay draws lights pale gold while it is pressed (mockup 10: "Pressed" is a pale-gold edge round
-- a square button, a red button or a card; a glow on a round one) and lets go with a short fade. A press reaches
-- the add-on two ways:
--   * a key from the app (the play screen in the world): the app sends a tap's key down and up together when the
--     finger lifts, and a press key (Jump, Dive) down when it lands and up when it lifts. The contract's key watcher
--     (Contract.lua) calls Kit.PressDown on the area's frame at the key's down and Kit.PressUp at its up. The app's
--     own gold outline is what shows the instant the finger lands on a tap area (TouchAreas.m AKTouchPressView);
--   * a plain tap (a window, sheet or card open): the app sends the left button down and up, so OnMouseDown and
--     OnMouseUp, hooked here on the button.
-- A press of a key or tap that arrives with no down before it (down and up in one frame) still flashes: the look
-- holds PRESS_HOLD seconds, then fades in PRESS_FADE. Reduce motion: the look holds for the same time and goes at
-- once, no fade. One animation group per control, nothing runs per frame, and nothing here touches a protected
-- frame: the look is a child frame of plain textures, safe in a fight.
-- A control that refuses the press now (greyed: disabled, or a refused() answer) shows the press in grey, and the
-- reason (refused's answer) next to it (Kit.ShowReason).

Kit.PRESS_COLOR = { 1, 0.9, 0.55 }       -- the mockups' pale gold
Kit.PRESS_GREY = { 0.62, 0.62, 0.62 }
Kit.PRESS_ERROR = { 1, 0.18, 0.12 }
Kit.PRESS_HOLD, Kit.PRESS_FADE = 0.06, 0.12
local PRESS_EDGE, PRESS_WASH = 3, 0.16
local PRESS_SHAPES = { square = true, rect = true, round = true }
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function PressTint(layer, color)
    if layer.tint == color then return end
    layer.tint = color
    for _, part in ipairs(layer.parts) do part:SetVertexColor(color[1], color[2], color[3]) end
end

-- The look: a frame over `on` (pad units outside it), alpha 0 until pressed.
local function NewPressLayer(on, shape, pad)
    local layer = CreateFrame("Frame", nil, on)
    layer:SetPoint("TOPLEFT", on, "TOPLEFT", -pad, pad)
    layer:SetPoint("BOTTOMRIGHT", on, "BOTTOMRIGHT", pad, -pad)
    layer:SetFrameLevel(on:GetFrameLevel() + 8)      -- over the cooldown sweep and the template's glows
    layer:EnableMouse(false)
    layer:SetAlpha(0)
    layer.shape, layer.parts = shape, {}
    if shape == "round" then
        -- the glow of the ring buttons (our own art), over the whole ring
        local glow = layer:CreateTexture(nil, "OVERLAY")
        Kit.SetGlyph(glow, "glow")
        glow:SetBlendMode("ADD")
        glow:SetPoint("TOPLEFT", on, "TOPLEFT", -pad, pad)
        glow:SetPoint("BOTTOMRIGHT", on, "BOTTOMRIGHT", pad, -pad)
        layer.glow = glow
        layer.parts[1] = glow
    else
        -- a pale-gold edge PRESS_EDGE thick, and a faint wash inside it
        local function Edge(p1, p2, w, h)
            local t = layer:CreateTexture(nil, "OVERLAY")
            t:SetTexture(WHITE)
            t:SetPoint(p1, layer, p1, 0, 0)
            t:SetPoint(p2, layer, p2, 0, 0)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            layer.parts[#layer.parts + 1] = t
            return t
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, PRESS_EDGE)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, PRESS_EDGE)
        Edge("TOPLEFT", "BOTTOMLEFT", PRESS_EDGE, nil)
        Edge("TOPRIGHT", "BOTTOMRIGHT", PRESS_EDGE, nil)
        local wash = layer:CreateTexture(nil, "ARTWORK")
        wash:SetTexture(WHITE)
        wash:SetBlendMode("ADD")
        wash:SetAllPoints(on)
        wash:SetAlpha(shape == "rect" and PRESS_WASH * 0.6 or PRESS_WASH)
        layer.wash = wash
        layer.parts[#layer.parts + 1] = wash
    end
    PressTint(layer, Kit.PRESS_COLOR)
    -- let go: hold, then fade (or, with Reduce motion, hold a little longer and go at once)
    local group = layer:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local hold = group:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetOrder(1)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetOrder(2)
    if fade.SetSmoothing then fade:SetSmoothing("OUT") end
    group:SetScript("OnFinished", function() layer:SetAlpha(0) end)
    group:SetScript("OnStop", function() layer:SetAlpha(layer.down and 1 or 0) end)
    layer.group, layer.hold, layer.fade = group, hold, fade
    on.touchPressLayer = layer
    return layer
end

-- Whether the control refuses a press now, and why (nil reason: greyed with no words).
local function Refused(button)
    if button.touchRefused then
        local ok, reason = pcall(button.touchRefused, button)
        if ok and reason then return true, reason ~= true and reason or nil end
    end
    if button.IsEnabled and not button:IsEnabled() then return true, button.reason end
    return false
end

local pressed = setmetatable({}, { __mode = "k" })     -- every control pressed so far (Kit.PressReleaseAll)

local function LetGo(layer, color)
    layer.limitToken = (layer.limitToken or 0) + 1       -- a limit timer still waiting does nothing now
    if color then PressTint(layer, color) end
    layer.down = false
    if layer.shape == "round" and layer.icon then layer.icon:SetPoint("CENTER", layer.iconOn, "CENTER", 0, 0) end
    local still = ns.ReduceMotion()
    layer.hold:SetDuration(still and Kit.PRESS_HOLD + Kit.PRESS_FADE or Kit.PRESS_HOLD)
    layer.fade:SetToAlpha(still and 1 or 0)
    layer.fade:SetDuration(still and 0.001 or Kit.PRESS_FADE)
    if layer.group:IsPlaying() then layer.group:Stop() end
    layer:SetAlpha(0)              -- the group holds it lit, and leaves it at 0
    layer.group:Play()
end

-- Let go at once, no fade (a frame that hid, a pause, a loading screen).
local function Drop(layer)
    layer.limitToken = (layer.limitToken or 0) + 1
    layer.down = false
    if layer.shape == "round" and layer.icon then layer.icon:SetPoint("CENTER", layer.iconOn, "CENTER", 0, 0) end
    if layer.group:IsPlaying() then layer.group:Stop() end
    layer:SetAlpha(0)
end

-- The finger (or the key) went down on `button`: the look lights at once and stays lit until it lets go.
-- `limit` (seconds, optional): a safety net for a key up that never comes (iPad, 18 Nov: a window opened between the
-- down and the up and the bags button stayed lit); the look lets go by itself after that long. A tap area uses
-- Kit.PRESS_TAP_MAX; a held press (Jump, Dive, Mount) and a plain finger on a button have no limit.
Kit.PRESS_TAP_MAX = 1.5
function Kit.PressDown(button, limit)
    local layer = button and button.touchPress
    if not layer then return end
    pressed[button] = true
    if layer.group:IsPlaying() then layer.group:Stop() end
    local refused, reason = Refused(button)
    PressTint(layer, refused and Kit.PRESS_GREY or Kit.PRESS_COLOR)
    layer.down = true
    layer.limitToken = (layer.limitToken or 0) + 1
    layer:SetAlpha(1)
    if layer.shape == "round" and layer.icon then layer.icon:SetPoint("CENTER", layer.iconOn, "CENTER", 1, -1) end
    if refused and reason then Kit.ShowReason(button, reason) end
    if limit then
        local mine = layer.limitToken
        C_Timer.After(limit, function()
            if layer.limitToken == mine and layer.down then LetGo(layer) end
        end)
    end
end

-- The finger lifted (or the key came up): the look lets go. With no press before it, it still flashes once.
function Kit.PressUp(button)
    local layer = button and button.touchPress
    if not layer then return end
    if not layer.down then
        local refused = Refused(button)
        PressTint(layer, refused and Kit.PRESS_GREY or Kit.PRESS_COLOR)
    end
    LetGo(layer)
end

-- The game refused what the press asked for (an error message right after a spell button): a red flash.
function Kit.PressError(button)
    local layer = button and button.touchPress
    if not layer then return end
    LetGo(layer, Kit.PRESS_ERROR)
end

-- Gives `button` the press look, drawn on `on` (the picture under a secure button; `button` itself by default).
-- shape: "square" (a spell, item or page box), "rect" (a red button, card, row, tile) or "round" (a ring button).
-- pad: units the look reaches outside `on` (default 2 square, 0 rect, 0 round). A picture that already has a look
-- (a ring or red button made by the kit) shares it. Hooks OnMouseDown/OnMouseUp on `button`: call it after any
-- SetScript of those two (SetScript drops the hooks).
function Kit.AddPress(button, shape, on, pad)
    if not PRESS_SHAPES[shape] then error("TouchPlay: unknown press shape " .. tostring(shape), 2) end
    on = on or button
    local layer = on.touchPressLayer
    if not layer then
        layer = NewPressLayer(on, shape, pad or (shape == "square" and 2 or 0))
        -- a ring's picture sinks a little while pressed
        if shape == "round" and on.icon then layer.icon, layer.iconOn = on.icon, on end
    end
    button.touchPress = layer
    -- a frame that hides (its window closed, its area left) takes a press with it: dark when it comes back
    for _, frame in ipairs({ button, on }) do
        if frame.HookScript and not frame.touchPressHideHooked then
            frame.touchPressHideHooked = true
            frame:HookScript("OnHide", function(self)
                for _, l in ipairs({ self.touchPress or false, self.touchPressLayer or false }) do
                    if l and l.down then Drop(l) end
                end
            end)
        end
    end
    if not button.touchPressHooked then
        button.touchPressHooked = true
        button:HookScript("OnMouseDown", function(self, mouse)
            if mouse == nil or mouse == "LeftButton" then Kit.PressDown(self) end
        end)
        button:HookScript("OnMouseUp", function(self, mouse)
            if mouse == nil or mouse == "LeftButton" then Kit.PressUp(self) end
        end)
    end
    return layer
end

-- Every look let go at once, no fade (a pause, Off, a loading screen: a key up that never comes).
function Kit.PressReleaseAll()
    for button in pairs(pressed) do
        local layer = button.touchPress
        if layer then Drop(layer) end
    end
end

-- Every look that is lit lets go the usual way (a short fade): a window opened or closed, a fight began or ended, the
-- keyboard went to another box. Whatever key up was due is not waited for.
function Kit.PressLetGoAll()
    for button in pairs(pressed) do
        local layer = button.touchPress
        if layer and layer.down then LetGo(layer) end
    end
end
-- A short line next to `frame` saying why it did nothing (a greyed control pressed). One line at a time.
local reasonFrame, reasonToken = nil, 0
Kit.REASON_SECONDS = 2
function Kit.ShowReason(frame, text)
    if type(text) ~= "string" or text == "" then return end
    if not reasonFrame then
        reasonFrame = CreateFrame("Frame", nil, ns.root)
        reasonFrame:SetFrameStrata(Kit.SHEET_STRATA)
        reasonFrame:SetFrameLevel(200)
        reasonFrame:EnableMouse(false)
        reasonFrame:SetSize(360, 26)
        reasonFrame.text = NewText(reasonFrame, 17)
        reasonFrame.text:SetTextColor(0.92, 0.92, 0.92)
        reasonFrame.text:SetShadowOffset(1, -1)
        reasonFrame.text:SetShadowColor(0, 0, 0, 1)
        reasonFrame.text:SetAllPoints(reasonFrame)
        Kit.reasonFrame = reasonFrame
    end
    reasonFrame:ClearAllPoints()
    reasonFrame:SetPoint("BOTTOM", frame, "TOP", 0, 8)
    reasonFrame.text:SetText(text)
    reasonFrame:Show()
    reasonToken = reasonToken + 1
    local mine = reasonToken
    C_Timer.After(Kit.REASON_SECONDS, function() if mine == reasonToken then reasonFrame:Hide() end end)
end

-- ---------------------------------------------------------------------------------------
-- Backdrop: the game's dialog and tooltip frames

local EDGES = {
    gold = { "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", 32, 11 },
    silver = { "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 11 },
    tooltip = { "Interface\\Tooltips\\UI-Tooltip-Border", 16, 4 },
}
local BACKGROUNDS = {
    dark = { "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", true, 1, 1, 1, 1 },
    tooltip = { "Interface\\Tooltips\\UI-Tooltip-Background", true, 9 / 255, 9 / 255, 19 / 255, 0.92 },
    parchment = { "Interface\\FontStyles\\FontStyleParchment", false, 1, 0.96, 0.84, 1 },
}

-- `frameType` is optional ("Frame" by default; the chip and tabs ask for "Button").
function Kit.Backdrop(parent, edge, bg, frameType)
    local e, b = EDGES[edge], BACKGROUNDS[bg]
    if not e or not b then error("TouchPlay: unknown backdrop " .. tostring(edge) .. "/" .. tostring(bg), 2) end
    local f = CreateFrame(frameType or "Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = b[1], edgeFile = e[1], tile = b[2], tileSize = 64, edgeSize = e[2],
        insets = { left = e[3], right = e[3], top = e[3], bottom = e[3] },
    })
    f:SetBackdropColor(b[3], b[4], b[5], b[6])
    return f
end

-- ---------------------------------------------------------------------------------------
-- Gold header: a plate in three parts (two ornament ends, a stretched middle) sized to its text

local HEADER_ART = "Interface\\DialogFrame\\UI-DialogBox-Gold-Header"
local HEADER_SCALE = 1.25
local HEADER_CAP = 16 * HEADER_SCALE          -- 20 units: 16 art pixels
local HEADER_HEIGHT = 38 * HEADER_SCALE       -- 47.5 units: 38 art pixels
local HEADER_MIN_WIDTH = 200

local function HeaderSetLabel(self, text)
    self.label:SetText(text)
    local width = math.max(HEADER_MIN_WIDTH, math.ceil(self.label:GetStringWidth() + 64))
    self:SetSize(width, HEADER_HEIGHT)
    self.parts.middle:SetWidth(width - 2 * HEADER_CAP)
end

-- A part shows art pixels x0 to x1 (of 256) and rows 2 to 40 (of 64).
local function HeaderPart(frame, point, x0, x1)
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(HEADER_ART)
    t:SetTexCoord(x0 / 256, x1 / 256, 2 / 64, 40 / 64)
    t:SetPoint(point, frame, point, 0, 0)
    t:SetHeight(HEADER_HEIGHT)
    return t
end

function Kit.GoldHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    local left = HeaderPart(f, "TOPLEFT", 60, 76)
    local right = HeaderPart(f, "TOPRIGHT", 180, 196)
    local middle = HeaderPart(f, "TOP", 76, 180)
    left:SetWidth(HEADER_CAP); right:SetWidth(HEADER_CAP)
    f.parts = { left = left, middle = middle, right = right }
    f.label = NewText(f, 18)
    f.label:SetTextColor(1, 0.82, 0)
    f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.SetLabel = HeaderSetLabel
    f:SetLabel(text)
    return f
end

-- ---------------------------------------------------------------------------------------
-- Red button: the game's panel button, art stretched to size

local RED_UP = "Interface\\Buttons\\UI-Panel-Button-Up"
local RED_DOWN = "Interface\\Buttons\\UI-Panel-Button-Down"
-- the art is the top-left 80 x 22 of a 128 x 32 texture
local RED_U, RED_V = 80 / 128, 22 / 32

local function RefreshRed(b)
    local off = b.busy or b.userEnabled == false
    if off then b:Disable() else b:Enable() end
    if off then b.label:SetTextColor(0.85, 0.85, 0.85) else b.label:SetTextColor(1, 0.82, 0) end
    local showReason = off and not b.busy and b.reason ~= nil
    if showReason then b.reasonText:SetText(b.reason) end
    b.reasonText:SetShown(showReason)
end

-- Busy: waiting for the game. The button ignores taps and shows its label greyed.
local function RedSetBusy(self, on)
    self.busy = on and true or false
    RefreshRed(self)
end

-- Off: greyed, and reasonText (when given) is written under the button so the player knows why.
local function RedSetEnabledWithReason(self, on, reasonText)
    self.userEnabled = on and true or false
    self.reason = (not on) and reasonText or nil
    RefreshRed(self)
end

function Kit.RedButton(parent, w, h, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetNormalTexture(RED_UP)
    b:SetPushedTexture(RED_DOWN)
    b:SetDisabledTexture(RED_UP)
    -- no hover highlight: a touch screen has no hover, and the pointer stays where the last plain tap left it, so a
    -- hover look stuck on whatever button sat there (polish pass). The press look below is the feedback.
    for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetDisabledTexture() }) do
        tex:SetTexCoord(0, RED_U, 0, RED_V)
    end
    b:GetDisabledTexture():SetDesaturated(true)
    b.label = NewText(b, math.max(12, math.floor(h * 0.4 + 0.5)))
    b.label:SetAllPoints(b)
    b.label:SetText(label)
    b.reasonText = NewText(b, 13)
    b.reasonText:SetTextColor(0.85, 0.85, 0.85)
    b.reasonText:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.reasonText:Hide()
    b.SetBusy, b.SetEnabledWithReason = RedSetBusy, RedSetEnabledWithReason
    b:RegisterForClicks("LeftButtonUp")
    b:HookScript("PostClick", PlayTap)
    RefreshRed(b)
    Kit.FitHit(b)
    Kit.AddPress(b, "rect", b, 3)        -- mockup 10: pressed = a pale-gold edge round the red button
    return b
end

-- ---------------------------------------------------------------------------------------
-- Our own art (R48, R49). The game's small icons and frames (64 px icons, the 64 px tracking ring, the 16 px
-- gossip bubble) came out soft at touch size on the iPad's 2x screen, so the non-spell buttons draw art the
-- add-on ships in Art/, made by tools/make-art.py at twice the drawn size or more: the ring, the icons
-- (game-icons.net, CC BY 3.0, shaded as gold metal; credits in Art/CREDITS.txt and NOTICE.md), the press glow,
-- the page box and the minimap ring. Spell, item and tracking icons stay the game's own.

local ART = "Interface\\AddOns\\TouchPlay\\Art\\"
Kit.ART_RING = ART .. "Ring.tga"          -- 256 x 256: the round button, spanning 1.25 x the button
Kit.ART_GLYPHS = ART .. "Glyphs.tga"      -- 2048 x 1024: 8 x 4 cells of 256
Kit.ART_MINIMAP = ART .. "Minimap.tga"    -- 512 x 512: 256 x 256 units round the minimap disc
Kit.RING_SPAN = 1.25
Kit.RING_ICON = 0.62                      -- the icon cell's share of the ring button

-- Each glyph's cell (column, row), as tools/make-art.py lays them out.
local GLYPH_COLS, GLYPH_ROWS, GLYPH_CELL = 8, 4, 256
local GLYPHS = {
    bag = { 0, 0 }, menu = { 1, 0 }, talk = { 2, 0 }, jump = { 3, 0 },
    dive = { 4, 0 }, cross = { 5, 0 }, cancel = { 6, 0 }, mail = { 7, 0 },
    loot = { 0, 1 }, open = { 1, 1 }, hook = { 2, 1 }, skin = { 3, 1 },
    sword = { 4, 1 }, person = { 5, 1 }, book = { 6, 1 }, star = { 7, 1 },
    scroll = { 0, 2 }, map = { 1, 2 }, hammer = { 2, 2 }, people = { 3, 2 },
    chat = { 4, 2 }, gear = { 5, 2 }, layout = { 6, 2 }, exit = { 7, 2 },
    glow = { 0, 3 }, box = { 1, 3 }, mount = { 2, 3 },
}
Kit.GLYPHS = GLYPHS

-- Puts a glyph on a texture: the sheet, cut to the glyph's cell (half a texel in, so no neighbour bleeds in).
-- texture.touchGlyph names the glyph shown.
function Kit.SetGlyph(texture, name)
    local cell = GLYPHS[name]
    if not cell then error("TouchPlay: unknown glyph " .. tostring(name), 2) end
    local du, dv = 0.5 / (GLYPH_CELL * GLYPH_COLS), 0.5 / (GLYPH_CELL * GLYPH_ROWS)
    texture:SetTexture(Kit.ART_GLYPHS)
    texture:SetTexCoord(cell[1] / GLYPH_COLS + du, (cell[1] + 1) / GLYPH_COLS - du,
        cell[2] / GLYPH_ROWS + dv, (cell[2] + 1) / GLYPH_ROWS - dv)
    texture.touchGlyph = name
end

-- ---------------------------------------------------------------------------------------
-- Ring button: a dark disc in a gold ring, as the mockups' ringButton

-- The ring's picture: a glyph name (Kit.GLYPHS) or a game texture (the tracked ability's icon), or nil for none.
function Kit.SetRingIcon(b, icon)
    if type(icon) == "string" and GLYPHS[icon] then
        Kit.SetGlyph(b.icon, icon)
    else
        b.icon:SetTexture(icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon.touchGlyph = nil
    end
end

function Kit.RingButton(parent, d, icon, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(d, d)
    -- disc, ring, edge and shadow in one picture, 1.25 x the button, centred on it; greyed with SetVertexColor
    local ring = b:CreateTexture(nil, "BACKGROUND")
    ring:SetTexture(Kit.ART_RING)
    ring:SetSize(d * Kit.RING_SPAN, d * Kit.RING_SPAN)
    ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.ring = ring
    -- the icon's cell fills the middle 62 % (the icon itself about 53 %, as the mockup's inset of 24 %)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(d * Kit.RING_ICON, d * Kit.RING_ICON)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    Kit.SetRingIcon(b, icon)
    if label then
        b.label = NewText(b, 12)
        b.label:SetTextColor(1, 0.82, 0)
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -(d * 0.32 - 12))
        b.label:SetText(label)
    end
    b:RegisterForClicks("LeftButtonUp")
    b:HookScript("PostClick", PlayTap)
    Kit.FitHit(b)
    -- the press glow (our own art) over the ring, only while pressed: no hover look (a touch screen has no hover;
    -- the pointer left by the last plain tap kept a hover glow lit). The icon sinks a little while pressed.
    Kit.AddPress(b, "round", b, d * (Kit.RING_SPAN - 1) / 2)
    return b
end

-- ---------------------------------------------------------------------------------------
-- Status bars

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local BAR_COLORS = {
    health = { 0, 0.88, 0 }, power = { 0, 0, 1 }, cast = { 1, 0.76, 0.1 },
    xp = { 0.58, 0.1, 0.78 }, timer = { 1, 0.76, 0.1 },
}

-- Values go straight to the bar: no comparing, no maths (they are hidden in a fight).
local function BarSet(self, min, max, value)
    self:SetMinMaxValues(min, max)
    self:SetValue(value)
end

function Kit.Bar(parent, kind)
    local color = BAR_COLORS[kind]
    if not color then error("TouchPlay: unknown bar kind " .. tostring(kind), 2) end
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 1)
    bg:SetAllPoints(bar)
    bar.bg = bg
    local big = kind == "cast" or kind == "timer"
    if big then
        -- the cast and timer bars sit in the tooltip frame, with their text inside the bar
        local frame = Kit.Backdrop(bar, "tooltip", "tooltip")
        frame:SetPoint("TOPLEFT", bar, "TOPLEFT", -7, 7)
        frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 7, -7)
        frame:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        bar.frame = frame
    end
    bar.text = NewText(bar, big and 18 or 12, "OVERLAY", FONT_NUMBER)
    bar.text:SetTextColor(1, 1, 1)
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.Set = BarSet
    return bar
end

-- ---------------------------------------------------------------------------------------
-- Chip: a pill that is lit with a tick when on

local CHIP_CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local CHIP_HEIGHT = 44

local function ChipSetOn(self, on)
    on = on and true or false
    self.on = on
    if on then
        self:SetBackdropColor(90 / 255, 70 / 255, 16 / 255, 0.92)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        self.label:SetTextColor(1, 0.82, 0)
    else
        self:SetBackdropColor(10 / 255, 10 / 255, 14 / 255, 0.8)
        self:SetBackdropBorderColor(1, 1, 1, 0.25)
        self.label:SetTextColor(0.62, 0.62, 0.62)
    end
    self.check:SetShown(on)
end

-- Tapping a chip only plays the tap sound; what it switches is the caller's (OnClick).
function Kit.Chip(parent, label)
    local b = Kit.Backdrop(parent, "tooltip", "tooltip", "Button")
    b.label = NewText(b, 16)
    b.label:SetText(label)
    b.label:SetPoint("LEFT", b, "LEFT", 38, 0)
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetTexture(CHIP_CHECK)
    b.check:SetSize(24, 24)
    b.check:SetPoint("LEFT", b, "LEFT", 10, 0)
    b:SetSize(math.ceil(b.label:GetStringWidth()) + 54, CHIP_HEIGHT)
    b.SetOn = ChipSetOn
    b:SetOn(false)
    b:RegisterForClicks("LeftButtonUp")
    b:HookScript("PostClick", PlayTap)
    Kit.FitHit(b)
    Kit.AddPress(b, "rect", b, 2)
    return b
end

-- ---------------------------------------------------------------------------------------
-- Tabs: a row of buttons, one selected at a time

local TAB_HEIGHT, TAB_MIN_WIDTH, TAB_GAP = 46, 112, 6

local function TabPaint(tab)
    if tab.selected then
        tab:SetBackdropColor(0.35, 0.27, 0.08, 0.95)
        tab:SetBackdropBorderColor(1, 0.82, 0, 1)
        tab.label:SetTextColor(1, 0.82, 0)
    else
        tab:SetBackdropColor(20 / 255, 16 / 255, 8 / 255, 0.85)
        tab:SetBackdropBorderColor(1, 0.82, 0, 0.3)
        tab.label:SetTextColor(0.73, 0.73, 0.73)
    end
end

local function TabsSetSelected(self, index)
    self.selected = index
    for i, tab in ipairs(self.buttons) do
        tab.selected = i == index
        TabPaint(tab)
    end
end

local function TabClick(tab)
    local tabs = tab.tabs
    Kit.Sound("tap")
    if tabs.selected == tab.index then return end
    tabs:SetSelected(tab.index)
    if tabs.onSelect then tabs.onSelect(tab.index) end
end

function Kit.Tabs(parent, labels)
    local tabs = CreateFrame("Frame", nil, parent)
    tabs.buttons = {}
    local width = TAB_MIN_WIDTH
    local measure = NewText(tabs, 17)
    for _, label in ipairs(labels) do
        measure:SetText(label)
        width = math.max(width, math.ceil(measure:GetStringWidth()) + 24)
    end
    measure:Hide()
    for i, label in ipairs(labels) do
        local tab = Kit.Backdrop(tabs, "tooltip", "tooltip", "Button")
        tab:SetSize(width, TAB_HEIGHT)
        tab:SetPoint("TOPLEFT", tabs, "TOPLEFT", (i - 1) * (width + TAB_GAP), 0)
        tab.label = NewText(tab, 17)
        tab.label:SetText(label)
        tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.tabs, tab.index = tabs, i
        tab:RegisterForClicks("LeftButtonUp")
        tab:SetScript("OnClick", TabClick)
        Kit.FitHit(tab)
        Kit.AddPress(tab, "rect", tab, 2)
        tabs.buttons[i] = tab
    end
    tabs:SetSize(#labels * width + math.max(0, #labels - 1) * TAB_GAP, TAB_HEIGHT)
    tabs.SetSelected = TabsSetSelected
    tabs.GetSelected = function(self) return self.selected end
    tabs.SetOnSelect = function(self, fn) self.onSelect = fn end
    tabs:SetSelected(1)
    return tabs
end

-- ---------------------------------------------------------------------------------------
-- Card: the tooltip frame with a title, body lines and up to four red buttons in a row

local CARD_WIDTH, CARD_PAD, CARD_GAP = 420, 20, 10
local CARD_BUTTON_HEIGHT, CARD_BUTTON_MAX = 44, 4

-- Stacks the title, lines and buttons for the card's current width and content.
local function CardFit(self)
    local inner = self:GetWidth() - 2 * CARD_PAD
    local y = 14
    local titleText = self.title:GetText()
    -- a hidden title (the game's tooltip text in a fight) is never compared: it counts as a title
    if titleText and (not ns.Plain(titleText) or titleText ~= "") then
        self.title:SetWidth(inner)
        y = y + self.title:GetStringHeight() + 6
    end
    for i = 1, self.lineCount do
        local line = self.lines[i]
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD, -y)
        line:SetWidth(inner)
        y = y + line:GetStringHeight() + 4
    end
    local count = self.buttonCount
    if count > 0 then
        local bw = (self:GetWidth() - 2 * CARD_PAD - (count - 1) * CARD_GAP) / count
        for i = 1, count do
            local b = self.buttons[i]
            b:SetSize(bw, CARD_BUTTON_HEIGHT)
            Kit.FitHit(b)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", CARD_PAD + (i - 1) * (bw + CARD_GAP), 14)
        end
        y = y + 10 + CARD_BUTTON_HEIGHT
    end
    self:SetHeight(math.max(60, y + 14))
end

local function CardSetTitle(self, text, r, g, b)
    self.title:SetText(text)
    self.title:SetTextColor(r or 1, g or 1, b or 1)
    self:Fit()
end

-- lines: a list of strings (colour codes allowed). The font strings are reused.
local function CardSetLines(self, lines)
    for i = 1, #lines do
        local line = self.lines[i]
        if not line then
            line = NewText(self, 16)
            line:SetJustifyH("LEFT")
            line:SetJustifyV("TOP")
            line:SetTextColor(1, 1, 1)
            self.lines[i] = line
        end
        line:SetText(lines[i])
        line:Show()
    end
    for i = #lines + 1, self.lineCount do self.lines[i]:Hide() end
    self.lineCount = #lines
    self:Fit()
end

-- buttons: a list of { label =, onClick =, enabled =, reason = }; at most four.
local function CardSetButtons(self, buttons)
    if #buttons > CARD_BUTTON_MAX then
        error("TouchPlay: a card holds at most " .. CARD_BUTTON_MAX .. " buttons", 2)
    end
    for i = 1, #buttons do
        local entry = buttons[i]
        local b = self.buttons[i]
        if not b then
            b = Kit.RedButton(self, 100, CARD_BUTTON_HEIGHT, entry.label)
            self.buttons[i] = b
        end
        b.label:SetText(entry.label)
        b:SetScript("OnClick", entry.onClick)
        b:SetEnabledWithReason(entry.enabled ~= false, entry.reason)
        b:SetBusy(false)
        b:Show()
    end
    for i = #buttons + 1, self.buttonCount do self.buttons[i]:Hide() end
    self.buttonCount = #buttons
    self:Fit()
end

function Kit.Card(parent)
    local card = Kit.Backdrop(parent, "tooltip", "tooltip")
    card:SetSize(CARD_WIDTH, 60)
    card.title = NewText(card, 23)
    card.title:SetJustifyH("LEFT")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -14)
    card.lines, card.lineCount = {}, 0
    card.buttons, card.buttonCount = {}, 0
    card.Fit = CardFit
    card.SetTitle, card.SetLines, card.SetButtons = CardSetTitle, CardSetLines, CardSetButtons
    return card
end
