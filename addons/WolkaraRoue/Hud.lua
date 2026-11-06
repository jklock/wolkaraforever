-- Interface mobile : les barres de vie. Ton personnage en haut à gauche (vie, ressource,
-- expérience), ta cible en haut au centre (vie, ressource, effets, points de combo), comme
-- dans un jeu mobile. Toucher ta barre te cible toi-même (pour un soin), toucher celle de la
-- cible la garde ciblée. La barre de la cible n'apparaît qu'avec une cible, et c'est le jeu
-- qui la montre ou la cache, combat compris.

local _, ns = ...

local Hud = ns.Register("Barres de vie", {})
local player, target
local MAX_AURAS = 10
local AURA_SIZE = 30

local function Bar(parent, height, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    ns.Box(bar, "BACKGROUND", 0, 0, 0, 0.55)
    bar.text = ns.Label(bar, "GameFontHighlight")
    bar.text:SetPoint("CENTER")
    return bar
end

local function Short(value)
    if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
    if value >= 10000 then return string.format("%.0fk", value / 1000) end
    return tostring(value)
end

local function Aura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if aura then return aura.icon, aura.applications, aura.duration, aura.expirationTime end
        return nil
    end
    if UnitAura then
        local name, icon, count, _, duration, expiration = UnitAura(unit, index, filter)
        if name then return icon, count, duration, expiration end
    end
end

local function Unit(name, unit, width, default)
    local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(width, unit == "player" and 66 or 58)
    -- Sous les fenêtres du jeu (fiche, sacs, sorts), qui s'ouvrent par-dessus.
    frame:SetFrameStrata("LOW")
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("type1", "target")
    frame.unit = unit
    ns.Box(frame, "BACKGROUND", 0, 0, 0, 0.4)
    -- Ton portrait, à gauche de tes barres : le toucher ouvre la fiche du personnage sans passer
    -- par le menu, par un clic sur le bouton Personnage du jeu (le combat le permet).
    local left = 0
    if unit == "player" then
        local portrait = CreateFrame("Button", "WolkaraMobilePortrait", frame, "SecureActionButtonTemplate")
        portrait:SetSize(60, 60)
        portrait:SetPoint("LEFT", frame, "LEFT", 3, 0)
        portrait:RegisterForClicks("AnyUp", "AnyDown")
        if _G.CharacterMicroButton then
            portrait:SetAttribute("type", "click")
            portrait:SetAttribute("clickbutton", _G.CharacterMicroButton)
        else
            portrait:SetScript("PostClick", function(_, _, down)
                if not down and ToggleCharacter then ToggleCharacter("PaperDollFrame") end
            end)
        end
        ns.Disc(portrait, "BACKGROUND", 0.05, 0.05, 0.08, 0.9, 2)
        portrait.texture = portrait:CreateTexture(nil, "ARTWORK")
        portrait.texture:SetAllPoints()
        ns.Circle(portrait, portrait.texture)
        local highlight = ns.Disc(portrait, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
        highlight:SetBlendMode("ADD")
        frame.portrait = portrait
        left = 66
    end
    frame.name = ns.Label(frame, "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", 6 + left, -3)
    frame.name:SetPoint("TOPRIGHT", -6, -3)
    frame.name:SetJustifyH("LEFT")
    frame.health = Bar(frame, 24, 0.15, 0.75, 0.2)
    frame.health:SetPoint("TOPLEFT", 4 + left, -20)
    frame.health:SetPoint("TOPRIGHT", -4, -20)
    frame.power = Bar(frame, 12, 0.2, 0.4, 1)
    frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -2)
    frame.power:SetPoint("TOPRIGHT", frame.health, "BOTTOMRIGHT", 0, -2)
    frame.power.text:SetFontObject("GameFontHighlightSmall")
    if unit == "player" then
        frame.xp = Bar(frame, 6, 0.6, 0.3, 0.85)
        frame.xp:SetPoint("TOPLEFT", frame.power, "BOTTOMLEFT", 0, -2)
        frame.xp:SetPoint("TOPRIGHT", frame.power, "BOTTOMRIGHT", 0, -2)
        frame.xp.text:SetText("")
    else
        -- Points de combo, à droite du nom.
        frame.combo = ns.Label(frame, "GameFontNormalLarge")
        frame.combo:SetPoint("TOPRIGHT", -8, -1)
        frame.combo:SetTextColor(1, 0.85, 0.2)
        -- Effets sous la barre : ceux qui gênent d'abord, puis les autres.
        frame.auras = {}
        for i = 1, MAX_AURAS do
            local aura = CreateFrame("Frame", nil, frame)
            aura:SetSize(AURA_SIZE, AURA_SIZE)
            aura:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", (i - 1) * (AURA_SIZE + 3), -3)
            aura.icon = aura:CreateTexture(nil, "ARTWORK")
            aura.icon:SetAllPoints()
            aura.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            aura.count = ns.Label(aura, "NumberFontNormalSmall")
            aura.count:SetPoint("BOTTOMRIGHT", 0, 0)
            aura.cooldown = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
            aura.cooldown:SetAllPoints()
            if aura.cooldown.SetReverse then aura.cooldown:SetReverse(true) end
            aura:Hide()
            frame.auras[i] = aura
        end
    end
    frame.glow = ns.EditFrame(frame)
    ns.Movable(frame, function() return ns.db.hud end, unit, default)
    return frame
end

local function UpdateAuras(frame)
    if frame.unit == "player" then return end
    local shown = 0
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        local index = 1
        while shown < MAX_AURAS do
            local icon, count, duration, expiration = Aura(frame.unit, index, filter)
            if not icon then break end
            shown = shown + 1
            local aura = frame.auras[shown]
            aura.icon:SetTexture(icon)
            aura.count:SetText((count and count > 1) and count or "")
            if duration and duration > 0 and expiration then
                aura.cooldown:SetCooldown(expiration - duration, duration)
                aura.cooldown:Show()
            else
                aura.cooldown:Hide()
            end
            aura:Show()
            index = index + 1
        end
    end
    for i = shown + 1, MAX_AURAS do frame.auras[i]:Hide() end
end

local function Update(frame)
    local unit = frame.unit
    if not UnitExists(unit) then return end
    local level = UnitLevel(unit)
    local levelText = (level and level > 0) and tostring(level) or "??"
    frame.name:SetText((UnitName(unit) or "") .. "  |cffbbbbbb" .. levelText .. "|r")

    local health, maxHealth = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    frame.health:SetMinMaxValues(0, math.max(1, maxHealth))
    frame.health:SetValue(health)
    local percent = maxHealth > 0 and math.floor(health * 100 / maxHealth + 0.5) or 0
    if unit == "player" then
        frame.health.text:SetText(Short(health) .. " / " .. Short(maxHealth))
    else
        frame.health.text:SetText(percent .. " %")
        if UnitIsDead(unit) then
            frame.health:SetStatusBarColor(0.4, 0.4, 0.4)
        elseif UnitIsFriend("player", unit) then
            frame.health:SetStatusBarColor(0.15, 0.75, 0.2)
        elseif UnitCanAttack("player", unit) then
            frame.health:SetStatusBarColor(0.85, 0.15, 0.1)
        else
            frame.health:SetStatusBarColor(0.9, 0.8, 0.2)
        end
        local combo = GetComboPoints and GetComboPoints("player", "target") or 0
        frame.combo:SetText(combo > 0 and ("Combo " .. combo) or "")
    end

    if frame.unit == "player" then
        local xp, maxXp = UnitXP and UnitXP(unit) or 0, UnitXPMax and UnitXPMax(unit) or 0
        if maxXp > 0 and not (IsXPUserDisabled and IsXPUserDisabled()) then
            frame.xp:SetMinMaxValues(0, maxXp)
            frame.xp:SetValue(xp)
            frame.xp:Show()
        else
            frame.xp:Hide()
        end
    end

    local power, maxPower = UnitPower(unit) or 0, UnitPowerMax(unit) or 0
    if maxPower > 0 then
        local color = PowerBarColor and PowerBarColor[UnitPowerType(unit)]
        if color then frame.power:SetStatusBarColor(color.r, color.g, color.b) end
        frame.power:SetMinMaxValues(0, maxPower)
        frame.power:SetValue(power)
        frame.power.text:SetText(Short(power) .. " / " .. Short(maxPower))
        frame.power:Show()
    else
        frame.power:Hide()
    end
    UpdateAuras(frame)
end

function Hud:Init()
    player = Unit("WolkaraMobilePlayer", "player", 366, { "TOPLEFT", "TOPLEFT", 12, -10 })
    target = Unit("WolkaraMobileTarget", "target", 330, { "TOP", "TOP", 0, -96 })
    target:Hide()
end

function Hud:Layout()
    local on = ns.db.hud.enabled
    local scale = ns.db.hud.scale / 100
    for _, frame in ipairs({ player, target }) do
        frame:SetScale(scale)
        frame:PlaceSaved()
    end
    if on then player:Show() else player:Hide() end
    -- La cible : le jeu la montre quand il y en a une. En mode Personnaliser, elle reste
    -- visible pour pouvoir la déplacer.
    if UnregisterUnitWatch then UnregisterUnitWatch(target) end
    if on and ns.editing then
        target:Show()
    elseif on and RegisterUnitWatch then
        RegisterUnitWatch(target)
    else
        target:Hide()
    end
    self:Refresh()
end

local function Portrait()
    if player and player.portrait and SetPortraitTexture then SetPortraitTexture(player.portrait.texture, "player") end
end

function Hud:Refresh()
    if not player then return end
    Portrait()
    Update(player)
    Update(target)
end

function Hud:SetEditing(on)
    player.glow:SetShown(on)
    target.glow:SetShown(on)
    if on and not UnitExists("target") then target.name:SetText("Cible") end
end

local function Changed(unit)
    if not player then return end
    if unit == nil or unit == "player" then Update(player) end
    if unit == nil or unit == "target" then Update(target) end
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
        "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_AURA" }) do
    ns.On(event, Changed)
end
ns.On("PLAYER_TARGET_CHANGED", function() Changed("target") end)
ns.On("PLAYER_XP_UPDATE", function() Changed("player") end)
ns.On("UNIT_COMBO_POINTS", function() Changed("target") end)
ns.On("PLAYER_ENTERING_WORLD", function() Portrait(); Changed(nil) end)
ns.On("UNIT_PORTRAIT_UPDATE", function(unit) if unit == "player" then Portrait() end end)
