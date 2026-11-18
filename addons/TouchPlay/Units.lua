-- TouchPlay: the player card, the target card and the cast bars (mockups 01, 02, 19, 20, 70, 74, 77).
--
-- The cards use the game's own TargetingFrame art at scale 1.5 (232 x 100 art units, so 348 x 150
-- layout units); the player card is the same art mirrored. Each card is a secure action button
-- (`unit` attribute, `*type1 = "target"`): a tap targets that unit, a hold (the right click the
-- hold key sends) asks the info card and never opens the game's unit menu.
--
-- The target card shows and hides itself in secure code (RegisterUnitWatch), so it follows the
-- target in a fight. Everything else is plain widgets updated from events:
--   * numbers that are hidden in a fight (health, power, cast times, whether a cast can be
--     interrupted) go straight to StatusBar:SetMinMaxValues/SetValue/SetTimerDuration,
--     FontString:SetFormattedText, SetAlphaFromBoolean and C_CurveUtil: nothing here compares or
--     does maths on them;
--   * "health under 25%" is a step curve handed to UnitHealthPercent itself (the game evaluates it:
--     a curve's Evaluate refuses a hidden number from add-on code, R43); the screen's red edge (Hud.lua)
--     uses its answer (1 or 0) as an alpha. The card itself draws no glow (iPad run 7).
-- Events come through one frame with RegisterUnitEvent for "player" and "target" only.

local ADDON_NAME, ns = ...

local Units = ns.Register("Units", {})
local Kit = ns.Kit

ns.L["unit.dead"] = "Dead"
ns.L["unit.ghost"] = "Ghost"
ns.L["unit.resting"] = "zzz"

-- ---------------------------------------------------------------------------------------
-- Numbers from the mockups (layout units, 1366 x 1024). One art unit = S layout units.

local S = 1.5
local CARD_W, CARD_H = 232 * S, 100 * S
local PLAYER_X, PLAYER_Y = 10, 8
local TARGET_X, TARGET_Y = 360, 8
local PLAYER_CAST_X, PLAYER_CAST_Y, PLAYER_CAST_W = 483, 700, 400
local TARGET_CAST_X, TARGET_CAST_W = 372, 264
local CAST_H = 34
local TARGET_CAST_Y = TARGET_Y + CARD_H + 6
local OUT_OF_RANGE_ALPHA = 0.55
local LOW_PERCENT = 25

local ART = {
    normal = "Interface\\TargetingFrame\\UI-TargetingFrame",
    elite = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    rare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
    rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
}
-- The art is 256 x 128; the card shows its columns 24 to 256 and rows 0 to 100.
local ART_LEFT, ART_RIGHT, ART_BOTTOM = 24 / 256, 1, 100 / 128

-- The pet's card (mockup 22): the player's card at scale 1 under it, its portrait centred at (143, 158). Its touch area is
-- the drawn part (art x 30..226, y 20..90), and the player's card takes taps on its top 120 units only (art rows 0..80,
-- the portrait, the bars and the level) when there is a pet card, so the two touch areas meet at y 128 and never overlap.
local PET_S = 1
local PET_X, PET_Y = 73, 108
local PET_HIT_X, PET_HIT_Y, PET_HIT_W, PET_HIT_H = 30, 20, 196, 70
local PLAYER_TAP_H = 120
-- The classes whose pet has a card (and the pet row its areas, ClassBars): a borrowed pet (a priest's mind control) has
-- neither.
Units.PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- Whether this character's pet has a card (a hunter or a warlock).
function Units.HasPetCard()
    local class = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
    return Units.PET_CLASSES[class] == true
end

local NAME_BACKGROUND = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local SHIELD = "Interface\\CastingBar\\UI-CastingBar-Arena-Shield"

-- ---------------------------------------------------------------------------------------
-- Pure helpers

function Units.FrameArt(kind) return ART[kind] or ART.normal end

-- UnitClassification answers "worldboss", "elite", "rare", "rareelite", "normal", "trivial", "minus".
function Units.KindOf(classification)
    if classification == "worldboss" then return "elite" end
    if ART[classification] then return classification end
    return "normal"
end

local LEVEL_RED, LEVEL_ORANGE = { 1, 0.125, 0.125 }, { 1, 0.5, 0.25 }
local LEVEL_YELLOW, LEVEL_GREEN, LEVEL_GREY = { 1, 0.82, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }

-- The text of a level and its colour as the game's quest difficulty reads it. A skull ("skull")
-- stands for level -1 and for 10 or more levels above the player.
function Units.LevelText(level, playerLevel)
    playerLevel = playerLevel or 1
    if type(level) ~= "number" or level == 0 then return "", LEVEL_GREY[1], LEVEL_GREY[2], LEVEL_GREY[3] end
    if level < 0 or level >= playerLevel + 10 then return "skull", LEVEL_RED[1], LEVEL_RED[2], LEVEL_RED[3] end
    local diff = level - playerLevel
    local c
    if diff >= 5 then c = LEVEL_RED
    elseif diff >= 3 then c = LEVEL_ORANGE
    elseif diff >= -2 then c = LEVEL_YELLOW
    elseif -diff <= (GetQuestGreenRange and GetQuestGreenRange() or 8) then c = LEVEL_GREEN
    else c = LEVEL_GREY end
    return tostring(level), c[1], c[2], c[3]
end

local NAME_RED, NAME_YELLOW = { 0.78, 0, 0 }, { 0.75, 0.67, 0 }
local NAME_GREEN, NAME_BLUE, NAME_GREY = { 0, 0.59, 0 }, { 0, 0.24, 0.78 }, { 0.43, 0.43, 0.43 }

-- A yes/no answer the game may hide: true only for a plain true-ish one; a hidden one counts as "no" (it is never
-- tested). Not ns.Plain, which answers whether a value is plain at all.
local function PlainTrue(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value and true or false
end

local function Tapped(unit) return UnitIsTapDenied and UnitIsTapDenied(unit) and true or false end

-- The colour of the name bar, as the game's target frame picks it: grey when the unit is dead
-- or someone else tagged it, red hostile, yellow neutral, green friendly, blue another player.
function Units.NameBarColour(unit)
    local c
    if UnitIsDead(unit) or Tapped(unit) then
        c = NAME_GREY
    elseif UnitPlayerControlled(unit) then
        if UnitCanAttack(unit, "player") then
            c = UnitCanAttack("player", unit) and NAME_RED or NAME_BLUE
        elseif UnitCanAttack("player", unit) then
            c = NAME_YELLOW
        elseif PlainTrue(UnitIsPVP(unit)) then
            c = NAME_GREEN
        else
            c = NAME_BLUE
        end
    else
        local reaction = UnitReaction(unit, "player") or 2
        if reaction <= 3 then c = NAME_RED elseif reaction == 4 then c = NAME_YELLOW else c = NAME_GREEN end
    end
    return c[1], c[2], c[3]
end


-- ---------------------------------------------------------------------------------------
-- The step curve for "health under 25%": 1 below LOW_PERCENT, 0 from there up. The game's percentages
-- run 0 to 1 (CurveConstants.lua), so the step is at 0.25. It is built once and handed to UnitHealthPercent,
-- which evaluates it; the (possibly hidden) answer is only ever used as an alpha.

local lowCurve
local function LowCurve()
    if lowCurve == nil then
        lowCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            local curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            curve:AddPoint(0, 1)
            curve:AddPoint(LOW_PERCENT / 100, 0)
            lowCurve = curve
        end
    end
    return lowCurve
end
Units.LowCurve = LowCurve       -- the screen edge (Hud.lua) uses the same step curve

-- ---------------------------------------------------------------------------------------
-- A card

local function Region(parent, layer, texture)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(texture)
    return t
end

local function Text(parent, font, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, font, size, "")
    return fs
end

-- A hold asks the info card (R4); a right click never does anything else.
local function OnCardPostClick(self, button)
    if button ~= "RightButton" then return end
    if ns.InfoCard then
        ns.Guard("units hold", function()
            ns.InfoCard.Show({ kind = "unit", unit = self:GetAttribute("unit") }, self)
        end)
    end
end

-- `scale`: layout units per art unit (1.5 for the player and the target, 1 for the pet).
local function NewCard(unit, frameName, mirror, scale)
    local S = scale or S
    -- a secure action button, not the unit button template: a unit button's click asks the game's click bindings,
    -- which bind no Ctrl+Option+Shift click, so the app's keys would do nothing (R47)
    local card = CreateFrame("Button", frameName, ns.root, "SecureActionButtonTemplate")
    card:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    card:SetSize(232 * S, 100 * S)
    card:RegisterForClicks("AnyUp")
    card:SetAttribute("unit", unit)
    card:SetAttribute("*type1", "target")   -- a left click with any keys held (the app holds three)
    card:SetAttribute("type2", nil)       -- the game's unit menu is never opened from here
    card:SetAttribute("*type2", nil)
    card.unit, card.mirror, card.artScale = unit, mirror, S
    local level = card:GetFrameLevel()

    local barX = (mirror and 105 or 8) * S                 -- left edge of the bars and the name
    local portraitX = (mirror and 38 or 130) * S
    local levelX = (mirror and 40 or 166) * S

    -- portrait: a round picture under the art
    card.portrait = card:CreateTexture(nil, "BACKGROUND")
    card.portrait:SetSize(64 * S, 64 * S)
    card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", portraitX, -18 * S)
    local mask = card:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(card.portrait)
    card.portrait:AddMaskTexture(mask)

    -- health and power bars, under the art
    local function NewBar(kind, top)
        local bar = Kit.Bar(card, kind)
        bar:SetSize(119 * S, 12 * S)
        bar:SetPoint("TOPLEFT", card, "TOPLEFT", barX, -top * S)
        bar:SetFrameLevel(level + 1)
        bar:EnableMouse(false)
        bar.text:Hide()
        return bar
    end
    card.healthBar = NewBar("health", 41)
    card.powerBar = NewBar("power", 53)

    -- the art frame: name bar, the game's frame art, then the words
    local art = CreateFrame("Frame", nil, card)
    art:SetAllPoints(card)
    art:SetFrameLevel(level + 3)
    art:EnableMouse(false)
    card.art = art
    if unit == "target" then
        card.nameBg = Region(art, "BACKGROUND", NAME_BACKGROUND)
        card.nameBg:SetSize(119 * S, 19 * S)
        card.nameBg:SetPoint("TOPLEFT", art, "TOPLEFT", barX, -22 * S)
    end
    card.frameArt = art:CreateTexture(nil, "ARTWORK")
    card.frameArt:SetAllPoints(art)
    card.frameArt:SetTexture(ART.normal)
    if mirror then card.frameArt:SetTexCoord(1, ART_LEFT, 0, ART_BOTTOM)
    else card.frameArt:SetTexCoord(ART_LEFT, 1, 0, ART_BOTTOM) end
    card.artKind = "normal"

    card.nameText = Text(art, Kit.FONT_TITLE, 11 * S)
    card.nameText:SetTextColor(1, 0.82, 0)
    card.nameText:SetJustifyH("CENTER")
    card.nameText:SetWordWrap(false)
    card.nameText:SetWidth(119 * S)
    card.nameText:SetPoint("TOPLEFT", art, "TOPLEFT", barX, -23 * S)

    card.healthText = Text(art, Kit.FONT_NUMBER, 8.5 * S)
    card.healthText:SetTextColor(1, 1, 1)
    card.healthText:SetPoint("CENTER", card.healthBar, "CENTER", 0, 0)

    card.levelText = Text(art, Kit.FONT_NUMBER, 10 * S)
    card.levelText:SetJustifyH("CENTER")
    card.levelText:SetWidth(26 * S)
    card.levelText:SetPoint("TOPLEFT", art, "TOPLEFT", levelX, -58 * S)
    card.skull = Region(art, "OVERLAY", SKULL)
    card.skull:SetSize(24, 24)
    card.skull:SetPoint("CENTER", card.levelText, "CENTER", 0, 0)
    card.skull:Hide()

    card:HookScript("PostClick", OnCardPostClick)
    return card
end

-- ---------------------------------------------------------------------------------------
-- The player card's states (mockup 70)

local function AddPlayerStates(card)
    local art = card.art

    -- in a fight: crossed swords where the level was. No glow box round the card (iPad run 7: "just a red box
    -- around the frame - remove it altogether"); low health shows on the screen's red edge (Hud.lua).
    card.swords = Region(art, "OVERLAY", STATE_ICON)
    card.swords:SetTexCoord(0.5, 1, 0, 0.484375)
    card.swords:SetSize(40, 40)
    card.swords:SetPoint("CENTER", card.levelText, "CENTER", 0, 0)
    card.swords:Hide()

    -- resting: "zzz" by the portrait
    card.rest = Text(art, Kit.FONT_NUMBER, 18)
    card.rest:SetTextColor(1, 0.82, 0)
    card.rest:SetText(ns.T("unit.resting"))
    card.rest:SetPoint("TOPLEFT", art, "TOPLEFT", 105, -5)
    card.rest:Hide()

    -- party leader: the game's crown on the portrait
    card.crown = Region(art, "OVERLAY", LEADER_ICON)
    card.crown:SetSize(28, 28)
    card.crown:SetPoint("TOPLEFT", art, "TOPLEFT", 70, -4)
    card.crown:Hide()

    -- PvP: the faction badge beside the portrait
    card.pvp = Region(art, "OVERLAY", ART.normal)
    card.pvp:SetSize(52, 55)
    card.pvp:SetPoint("TOPLEFT", art, "TOPLEFT", -6, -29)
    card.pvp:Hide()
end

-- ---------------------------------------------------------------------------------------
-- Cast bars

local COLOR_GOLD = CreateColor and CreateColor(1, 0.76, 0.1, 1)
local COLOR_GREEN = CreateColor and CreateColor(0.1, 0.9, 0.1, 1)
local COLOR_GREY = CreateColor and CreateColor(0.65, 0.65, 0.65, 1)

local function NewCastBar(width)
    local holder = CreateFrame("Frame", nil, ns.root)
    holder:SetSize(width, CAST_H)
    holder:EnableMouse(false)
    holder:SetFrameLevel(20)
    local bar = Kit.Bar(holder, "cast")
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 7, -7)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7, 7)
    bar:EnableMouse(false)
    bar.shield = bar:CreateTexture(nil, "OVERLAY")
    bar.shield:SetTexture(SHIELD)
    bar.shield:SetSize(18, 22)
    bar.shield:SetPoint("LEFT", bar, "LEFT", 8, 0)
    bar.shield:SetAlpha(0)
    bar.timeText = bar:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(bar.timeText, Kit.FONT_NUMBER, 18, "")
    bar.timeText:SetTextColor(1, 1, 1)
    bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    holder.bar = bar
    holder:Hide()
    return holder
end

-- Colours the bar and shows the shield from "can it not be interrupted": the answer is hidden in
-- a fight, so it only goes into the game's own boolean helpers, never into an `if`.
local function PaintCast(bar, notInterruptible, base)
    local evaluate = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
    local colour = base
    if evaluate and COLOR_GREY then colour = evaluate(notInterruptible, COLOR_GREY, base) end
    bar:SetStatusBarColor(colour:GetRGBA())
    if bar.shield.SetAlphaFromBoolean then bar.shield:SetAlphaFromBoolean(notInterruptible, 1, 0) end
end

-- UnitCastingDuration / UnitChannelDuration return nothing when there is no such cast, and a
-- duration object that may be hidden when there is. A hidden one is never tested: it is a cast.
local function Present(duration)
    if issecretvalue and issecretvalue(duration) then return true end
    return duration ~= nil
end

-- The time left is written by a duration text binding: the game updates the font string from the
-- duration object itself, so there is no OnUpdate and no arithmetic here.
local function NewTimeBinding(bar)
    if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then return nil end
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(bar.timeText)
    local formatter = C_StringUtil and C_StringUtil.CreateSecondsFormatter and C_StringUtil.CreateSecondsFormatter()
    if formatter then
        local property = Enum and Enum.DurationTextBindingProperty
        if property and binding.SetTextFormat then
            binding:SetTextFormat("{}", { { property = property.RemainingDuration, formatter = formatter } })
        else
            binding:SetFormatter(formatter)
        end
    end
    binding:SetUpdateInterval(0.1)
    return binding
end

local function ShowCast(card, name, notInterruptible, duration, channel)
    local bar = card.castHolder.bar
    bar.text:SetText(name)
    if bar.SetTimerDuration then
        local direction = Enum and Enum.StatusBarTimerDirection
        direction = direction and (channel and direction.RemainingTime or direction.ElapsedTime)
        local interpolation = Enum and Enum.StatusBarInterpolation
        -- the game may refuse a hidden duration from add-on code: the bar then just does not run
        pcall(bar.SetTimerDuration, bar, duration, interpolation and interpolation.Immediate or 0, direction)
    end
    if bar.timeBinding then
        bar.timeBinding:SetDuration(duration)
        bar.timeBinding:Enable()
    end
    PaintCast(bar, notInterruptible, channel and COLOR_GREEN or COLOR_GOLD)
    if not card.castHolder:IsShown() then card.castHolder:Show() end
end

local function HideCast(card)
    local holder = card.castHolder
    if holder:IsShown() then
        holder:Hide()
        if holder.bar.timeBinding then holder.bar.timeBinding:Disable() end
    end
end

local function UpdateCast(card)
    local unit = card.unit
    if UnitExists(unit) then
        local duration = UnitCastingDuration and UnitCastingDuration(unit)
        if Present(duration) then
            local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
            ShowCast(card, name, notInterruptible, duration, false)
            return
        end
        duration = UnitChannelDuration and UnitChannelDuration(unit)
        if Present(duration) then
            local name, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
            ShowCast(card, name, notInterruptible, duration, true)
            return
        end
    end
    HideCast(card)
end

-- ---------------------------------------------------------------------------------------
-- Updating a card from the game

local function UpdateName(card)
    local unit = card.unit
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    card.nameText:SetText(name)
    if card.nameBg then
        local r, g, b = Units.NameBarColour(unit)
        card.nameBg:SetVertexColor(r, g, b, 0.75)
    end
    local tapped = Tapped(unit)
    if tapped ~= card.tapped then
        card.tapped = tapped
        if tapped then card.healthBar:SetStatusBarColor(0.54, 0.54, 0.54)
        else card.healthBar:SetStatusBarColor(0, 0.88, 0) end
        if tapped then card.nameText:SetTextColor(0.8, 0.8, 0.8) else card.nameText:SetTextColor(1, 0.82, 0) end
    end
end

local function UpdateLevel(card)
    local unit = card.unit
    if unit == "player" or unit == "pet" then
        card.levelText:SetText(tostring(UnitLevel(unit)))
        card.levelText:SetTextColor(1, 0.82, 0)
        return
    end
    local text, r, g, b = Units.LevelText(UnitLevel(unit), UnitLevel("player"))
    local skull = text == "skull"
    card.levelText:SetText(skull and "" or text)
    card.levelText:SetTextColor(r, g, b)
    card.skull:SetShown(skull)
end

local function UpdateArt(card)
    if card.unit ~= "target" then return end
    local kind = Units.KindOf(UnitClassification(card.unit))
    if kind ~= card.artKind then
        card.artKind = kind
        card.frameArt:SetTexture(Units.FrameArt(kind))
    end
end

local function UpdatePortrait(card)
    if not UnitExists(card.unit) then return end
    SetPortraitTexture(card.portrait, card.unit)
end

-- Grey for the dead, pale blue for a ghost.
local function ApplyLook(card, state)
    if state == card.look then return end
    card.look = state
    local p = card.portrait
    if state == "dead" then
        p:SetDesaturated(true); p:SetVertexColor(0.5, 0.5, 0.5)
    elseif state == "ghost" then
        p:SetDesaturated(true); p:SetVertexColor(0.6, 0.85, 1)
    else
        p:SetDesaturated(false); p:SetVertexColor(1, 1, 1)
    end
end

local function UpdateHealth(card)
    local unit = card.unit
    if not UnitExists(unit) then return end
    local ghost, dead = UnitIsGhost(unit), UnitIsDead(unit)
    local state = ghost and "ghost" or (dead and "dead" or nil)
    if state then
        card.healthBar:Set(0, 1, 0)
        card.healthText:SetText(ns.T(ghost and "unit.ghost" or "unit.dead"))
    else
        card.healthBar:Set(0, UnitHealthMax(unit), UnitHealth(unit))
        if unit == "pet" then
            card.healthText:SetText("")              -- the small card's bars carry no numbers (mockup 22)
        elseif unit == "player" then
            card.healthText:SetFormattedText("%d / %d", UnitHealth(unit), UnitHealthMax(unit))
        else
            card.healthText:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
        end
    end
    local changed = state ~= card.look
    ApplyLook(card, state)
    if changed and card.nameBg then UpdateName(card) end     -- the name bar goes grey
end

local function UpdatePower(card)
    local unit = card.unit
    if not UnitExists(unit) then return end
    card.powerBar:Set(0, UnitPowerMax(unit), UnitPower(unit))
end

local function UpdatePowerType(card)
    local unit = card.unit
    if not UnitExists(unit) then return end
    local powerType, token = UnitPowerType(unit)
    if powerType ~= card.powerType then
        card.powerType = powerType
        local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
        if c then card.powerBar:SetStatusBarColor(c.r, c.g, c.b) else card.powerBar:SetStatusBarColor(0, 0, 1) end
    end
end

local function UpdatePowerAll(card)
    UpdatePowerType(card)
    UpdatePower(card)
end

local function ShowIf(region, on)
    if region:IsShown() ~= on then region:SetShown(on) end
end

-- Player only: fight, resting, leader, PvP.
local function UpdateStates(card)
    if card.unit ~= "player" then return end
    local combat = UnitAffectingCombat("player") and true or false
    ShowIf(card.swords, combat)
    ShowIf(card.levelText, not combat)
    ShowIf(card.rest, IsResting() and true or false)
    ShowIf(card.crown, PlainTrue(UnitIsGroupLeader("player")))
    local pvp = PlainTrue(UnitIsPVP("player"))
    if pvp then
        local texture = "Interface\\TargetingFrame\\UI-PVP-"
            .. (UnitIsPVPFreeForAll("player") and "FFA" or (UnitFactionGroup("player") or "FFA"))
        if texture ~= card.pvpTexture then
            card.pvpTexture = texture
            card.pvp:SetTexture(texture)
            card.pvp:SetTexCoord(0, 0.609375, 0, 0.640625)
        end
    end
    ShowIf(card.pvp, pvp)
end

-- The target fades when it is out of reach: a party member by UnitInRange, an enemy by whether
-- the first spell button can reach it. Answers that are hidden count as "in range".
local function InRange(unit)
    if not UnitExists(unit) then return true end
    local inRange, checked = UnitInRange(unit)
    local hidden = issecretvalue and (issecretvalue(inRange) or issecretvalue(checked))
    if not hidden and checked then return inRange and true or false end
    if UnitCanAttack("player", unit) then
        local slot = ns.Cluster and ns.Cluster.buttons[1] and ns.Cluster.buttons[1]:GetAttribute("action") or 1
        local reach = IsActionInRange(slot)
        if not (issecretvalue and issecretvalue(reach)) and reach == false then return false end
    end
    return true
end

local function UpdateRange(card)
    if card.unit ~= "target" then return end
    local alpha = InRange(card.unit) and 1 or OUT_OF_RANGE_ALPHA
    if card:GetAlpha() ~= alpha then card:SetAlpha(alpha) end
end

local function UpdateAll(card)
    if not UnitExists(card.unit) then
        HideCast(card)
        return
    end
    UpdateName(card)
    UpdateLevel(card)
    UpdateArt(card)
    UpdatePowerAll(card)
    UpdateHealth(card)
    UpdatePortrait(card)
    UpdateStates(card)
    UpdateRange(card)
    UpdateCast(card)
end

-- ---------------------------------------------------------------------------------------
-- The frames

Units.player = NewCard("player", "TouchPlayPlayer", true)
Units.target = NewCard("target", "TouchPlayTarget", false)
Units.pet = NewCard("pet", "TouchPlayPetCard", true, PET_S)
Units.pet:Hide()                 -- a state driver shows it, for a pet class (Units:Layout)
AddPlayerStates(Units.player)

-- The touch areas the contract carries: the drawn part of each small-art card (plain frames, never shown on their
-- own: each is a child of its card, so it is visible exactly when the card is). A plain click keeps to the same part.
local function TapRect(card, w, h)
    local tap = CreateFrame("Frame", nil, card)
    tap:SetSize(w, h)
    tap:EnableMouse(false)
    return tap
end
Units.playerTap = TapRect(Units.player, CARD_W, CARD_H)
Units.petTap = TapRect(Units.pet, PET_HIT_W * PET_S, PET_HIT_H * PET_S)
Units.pet:SetHitRectInsets(PET_HIT_X * PET_S, (232 - PET_HIT_X - PET_HIT_W) * PET_S, PET_HIT_Y * PET_S,
    (100 - PET_HIT_Y - PET_HIT_H) * PET_S)

-- Pressed (polish pass): the portrait glows, as the ring buttons do. Never a box round the card (iPad run 7:
-- the red box round the frame went for good). The card's key lights it through its touch area (Contract's key
-- watcher), a plain tap through the card itself.
for _, pair in ipairs({ { Units.player, Units.playerTap }, { Units.target }, { Units.pet, Units.petTap } }) do
    local card, area = pair[1], pair[2]
    local spot = CreateFrame("Frame", nil, card)
    spot:SetAllPoints(card.portrait)
    spot:EnableMouse(false)
    card.pressSpot = spot
    ns.Kit.AddPress(card, "round", spot, 8 * (card.artScale or 1))
    if area then ns.Kit.AddPress(area, "round", spot) end
end
Units.playerCast = NewCastBar(PLAYER_CAST_W)
Units.targetCast = NewCastBar(TARGET_CAST_W)
Units.player.castHolder, Units.target.castHolder = Units.playerCast, Units.targetCast
Units.playerCast.bar.timeBinding = NewTimeBinding(Units.playerCast.bar)
Units.targetCast.bar.timeBinding = NewTimeBinding(Units.targetCast.bar)

-- With no target the card is hidden and the quest list takes its place: the game hides and
-- shows it from secure code, so it follows the target in a fight too.
RegisterUnitWatch(Units.target)

local cards = { player = Units.player, target = Units.target, pet = Units.pet }

local function Place()
    ns.Anchor(Units.player, "TL", PLAYER_X, PLAYER_Y)
    -- with a pet card under it, the player's card takes taps on its top 120 units only (out of combat: a secure button)
    local tapH = Units.HasPetCard() and PLAYER_TAP_H or CARD_H
    Units.playerTap:SetSize(CARD_W, tapH)
    Units.player:SetHitRectInsets(0, 0, 0, CARD_H - tapH)
    ns.Anchor(Units.playerTap, "TL", PLAYER_X, PLAYER_Y)
    ns.Anchor(Units.target, "TL", TARGET_X, TARGET_Y)
    ns.Anchor(Units.pet, "TL", PET_X, PET_Y)
    ns.Anchor(Units.petTap, "TL", PET_X + PET_HIT_X * PET_S, PET_Y + PET_HIT_Y * PET_S)
    ns.Anchor(Units.playerCast, "TL", PLAYER_CAST_X, PLAYER_CAST_Y)
    ns.Anchor(Units.targetCast, "TL", TARGET_CAST_X, TARGET_CAST_Y)
end
Place()

-- ---------------------------------------------------------------------------------------
-- Events: one frame, unit events for "player" and "target" only

local UNIT_HANDLERS = {
    UNIT_HEALTH = UpdateHealth, UNIT_MAXHEALTH = UpdateHealth,
    UNIT_POWER_UPDATE = UpdatePower, UNIT_MAXPOWER = UpdatePower,
    UNIT_DISPLAYPOWER = UpdatePowerAll,
    UNIT_LEVEL = UpdateLevel,
    UNIT_NAME_UPDATE = UpdateName,
    UNIT_PORTRAIT_UPDATE = UpdatePortrait, UNIT_MODEL_CHANGED = UpdatePortrait,
    UNIT_CLASSIFICATION_CHANGED = UpdateArt,
    UNIT_IN_RANGE_UPDATE = UpdateRange,
    UNIT_SPELLCAST_START = UpdateCast, UNIT_SPELLCAST_STOP = UpdateCast,
    UNIT_SPELLCAST_FAILED = UpdateCast, UNIT_SPELLCAST_INTERRUPTED = UpdateCast,
    UNIT_SPELLCAST_DELAYED = UpdateCast, UNIT_SPELLCAST_CHANNEL_START = UpdateCast,
    UNIT_SPELLCAST_CHANNEL_STOP = UpdateCast, UNIT_SPELLCAST_CHANNEL_UPDATE = UpdateCast,
    UNIT_SPELLCAST_INTERRUPTIBLE = UpdateCast, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = UpdateCast,
}
-- Flags and faction change the name bar, the tapped grey, the PvP badge.
local function UpdateFlags(card)
    UpdateName(card)
    UpdateStates(card)
end
UNIT_HANDLERS.UNIT_FLAGS, UNIT_HANDLERS.UNIT_FACTION = UpdateFlags, UpdateFlags

local unitEvents = CreateFrame("Frame")
for event in pairs(UNIT_HANDLERS) do
    pcall(unitEvents.RegisterUnitEvent, unitEvents, event, "player", "target")
end
local function OnUnitEvent(_, event, unit)
    if not ns.IsActive() then return end
    local card, fn = cards[unit], UNIT_HANDLERS[event]
    if card and fn then ns.Guard(event, fn, card) end
end
unitEvents:SetScript("OnEvent", OnUnitEvent)

-- The pet's card: the same handlers through its own frame (a unit event takes two units at most). No cast bar.
local PET_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }
local petEvents = CreateFrame("Frame")
for _, event in ipairs(PET_EVENTS) do pcall(petEvents.RegisterUnitEvent, petEvents, event, "pet") end
petEvents:SetScript("OnEvent", OnUnitEvent)


-- The bottom of the pet card's touch area (layout units) when this character has one, else nil: the quest list starts
-- below it (Hud.PlaceQuest).
function Units.PetCardBottom()
    if not Units.HasPetCard() then return nil end
    local a = Units.petTap.touchAnchor
    return a and a.y + a.h or nil
end

local function UpdatePetCard()
    if not UnitExists("pet") then return end
    UpdateName(Units.pet); UpdateLevel(Units.pet); UpdatePowerAll(Units.pet); UpdateHealth(Units.pet)
    UpdatePortrait(Units.pet)
end
Units.UpdatePetCard = UpdatePetCard
ns.On("UNIT_PET", function(unit) if unit == nil or unit == "player" then UpdatePetCard() end end)

-- Shown by the game while a pet exists (alive or dead: the dead pet keeps its card, mockup 21), in a fight too; not in a
-- vehicle (the game swaps the pet token for you there). Out of combat only, as it registers a secure driver.
local petCardDriven = false
local function DrivePetCard()
    local want = Units.HasPetCard()
    if want == petCardDriven then return end
    petCardDriven = want
    if want then
        RegisterStateDriver(Units.pet, "visibility", "[vehicleui] hide; [@pet,exists] show; hide")
    else
        UnregisterStateDriver(Units.pet, "visibility")
        Units.pet:Hide()
    end
end

ns.On("PLAYER_ENTERING_WORLD", function() UpdateAll(Units.player); UpdateAll(Units.target); UpdatePetCard() end)
ns.On("PLAYER_TARGET_CHANGED", function() UpdateAll(Units.target) end)
ns.On("PLAYER_REGEN_DISABLED", function() UpdateStates(Units.player) end)
ns.On("PLAYER_REGEN_ENABLED", function() UpdateStates(Units.player) end)
ns.On("PLAYER_UPDATE_RESTING", function() UpdateStates(Units.player) end)
ns.On("PARTY_LEADER_CHANGED", function() UpdateStates(Units.player) end)
ns.On("GROUP_ROSTER_UPDATE", function() UpdateStates(Units.player) end)
ns.On("PLAYER_DEAD", function() UpdateHealth(Units.player); UpdatePortrait(Units.player) end)
ns.On("PLAYER_ALIVE", function() UpdateHealth(Units.player); UpdatePortrait(Units.player) end)
ns.On("PLAYER_UNGHOST", function() UpdateHealth(Units.player); UpdatePortrait(Units.player) end)
ns.On("ACTION_RANGE_CHECK_UPDATE", function() UpdateRange(Units.target) end)

-- ---------------------------------------------------------------------------------------
-- Module steps

-- The pet card's area: a hunter's or a warlock's, whether or not the pet is out now (the app reads the list only at a
-- reload, so it follows what the character can have, not what is on screen).
local function RegisterPetArea()
    local Contract = ns.Contract
    if not Contract then return end
    if Units.HasPetCard() then
        Contract.Area("petcard", Units.petTap, { anchor = "TL",
            tap = { click = "TouchPlayPetCard", button = "LeftButton" },
            hold = { click = "TouchPlayPetCard", button = "RightButton" } })
    elseif Contract.Has("petcard") then
        Contract.Drop("petcard")
    end
end

function Units:Init()
    local Contract = ns.Contract
    if not Contract then return end
    Contract.Area("player", Units.playerTap, { anchor = "TL",
        tap = { click = "TouchPlayPlayer", button = "LeftButton" },
        hold = { click = "TouchPlayPlayer", button = "RightButton" } })
    Contract.Area("target", Units.target, { anchor = "TL",
        tap = { click = "TouchPlayTarget", button = "LeftButton" },
        hold = { click = "TouchPlayTarget", button = "RightButton" } })
end

function Units:Layout()
    ns.Queue("units layout", function()
        Place()
        DrivePetCard()
        RegisterPetArea()
    end)
end

function Units:Refresh()
    UpdateAll(Units.player)
    UpdateAll(Units.target)
    UpdatePetCard()
end
