-- Interface mobile : les barres de vie. Ton personnage en haut à gauche (vie, ressource,
-- expérience), ta cible tout en haut juste à sa droite (vie, ressource, effets, points de
-- combo), comme dans un jeu mobile. Toucher ta barre te cible toi-même (pour un soin), toucher celle de la
-- cible la garde ciblée. La barre de la cible n'apparaît qu'avec une cible, et c'est le jeu
-- qui la montre ou la cache, combat compris.

local _, ns = ...

local Hud = ns.Register("Barres de vie", {})
local player, target
local MAX_AURAS = 10
local AURA_SIZE = 30
local PLAYER_WIDTH, TARGET_WIDTH, BESIDE = 280, 240, 8

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

-- Sur ce client, la vie, la ressource et les effets peuvent être des valeurs « secrètes », en
-- combat surtout : l'addon ne peut ni les comparer ni calculer avec, seulement les passer aux
-- barres et aux textes du jeu, qui les dessinent. Sur l'iPhone (sauvegarde du 2026-11-09), la vie
-- secrète arrêtait la mise à jour en route, 38 fois en deux minutes (Hud.lua:254) : la ressource
-- et les effets de la cible ne bougeaient plus. Chaque calcul se tente donc à part, et un texte
-- qui ne peut se calculer passe par les formats du jeu (méthode de scarrdi94, #26).
local function Fill(bar, value, most)
    if not pcall(bar.SetMinMaxValues, bar, 0, most) then bar:SetMinMaxValues(0, 1) end
    if not pcall(bar.SetValue, bar, value) then bar:SetValue(0) end
end

-- « 1234 / 2000 », ou, d'un secret, ce que le jeu en écrit.
local function Amounts(label, value, most)
    local ok, text = pcall(function() return Short(value) .. " / " .. Short(most) end)
    if ok then label:SetText(text); return end
    if pcall(label.SetFormattedText, label, "%s / %s", value, most) then return end
    label:SetText("")
end

-- « 62 % » de la vie d'une cible, ou, d'un secret, le pour-cent que le jeu calcule lui-même.
local function Percent(label, unit, value, most)
    local ok, text = pcall(function() return (most > 0 and math.floor(value * 100 / most + 0.5) or 0) .. " %" end)
    if ok then label:SetText(text); return end
    if UnitHealthPercent and pcall(function()
        label:SetFormattedText("%d %%", UnitHealthPercent(unit, true, CurveConstants and CurveConstants.ScaleTo100))
    end) then return end
    label:SetText("")
end

-- Vrai ou faux si l'on peut lire que `value` dépasse zéro ; nil si c'est un secret.
local function Positive(value)
    local ok, positive = pcall(function() return value > 0 end)
    if ok then return positive end
    return nil
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
    frame:SetSize(width, unit == "player" and 72 or 58)
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
        -- Ton niveau dans un badge doré sur le portrait (idée de scarrdi94, #26) : le nom reste
        -- seul sur sa ligne.
        local badge = CreateFrame("Frame", nil, portrait)
        badge:SetSize(26, 26)
        badge:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 6, -4)
        badge:SetFrameLevel(portrait:GetFrameLevel() + 5)
        ns.Disc(badge, "ARTWORK", 0.85, 0.65, 0.15, 1, 0)
        badge.text = ns.Label(badge, "GameFontHighlightSmall")
        badge.text:SetPoint("CENTER")
        badge.text:SetTextColor(0.1, 0.07, 0.02)
        frame.badge = badge
        frame.portrait = portrait
        left = 66
    else
        -- Le portrait de ta cible, à gauche de ses barres : on voit qui est sélectionné
        -- (demandé sur l'iPhone, 2026-11-09). Le toucher la garde ciblée, comme le reste.
        local portrait = CreateFrame("Frame", nil, frame)
        portrait:SetSize(52, 52)
        portrait:SetPoint("LEFT", frame, "LEFT", 3, 0)
        ns.Disc(portrait, "BACKGROUND", 0.05, 0.05, 0.08, 0.9, 2)
        portrait.texture = portrait:CreateTexture(nil, "ARTWORK")
        portrait.texture:SetAllPoints()
        ns.Circle(portrait, portrait.texture)
        frame.portrait = portrait
        left = 58
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
        -- L'expérience lisible (idée de scarrdi94, #26) : une vraie barre, son pourcentage et
        -- « reposé » écrits dessus, au lieu d'un filet de 6 points sans texte.
        frame.xp = Bar(frame, 11, 0.6, 0.3, 0.85)
        frame.xp:SetPoint("TOPLEFT", frame.power, "BOTTOMLEFT", 0, -2)
        frame.xp:SetPoint("TOPRIGHT", frame.power, "BOTTOMRIGHT", 0, -2)
        frame.xp.text:SetFontObject("NumberFontNormalSmall")
        frame.xp.text:SetText("")
    else
        -- Points de combo, à droite du nom.
        frame.combo = ns.Label(frame, "GameFontNormalLarge")
        frame.combo:SetPoint("TOPRIGHT", -8, -1)
        frame.combo:SetTextColor(1, 0.85, 0.2)
        -- Effets sous la barre : ceux qui gênent d'abord, puis les autres, sur autant de rangs
        -- que la largeur de la barre en demande.
        frame.auras = {}
        local perRow = math.max(1, math.floor((width + 3) / (AURA_SIZE + 3)))
        for i = 1, MAX_AURAS do
            local aura = CreateFrame("Frame", nil, frame)
            aura:SetSize(AURA_SIZE, AURA_SIZE)
            local row, column = math.floor((i - 1) / perRow), (i - 1) % perRow
            aura:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", column * (AURA_SIZE + 3), -3 - row * (AURA_SIZE + 3))
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
            if not pcall(aura.icon.SetTexture, aura.icon, icon) then aura.icon:SetTexture(ns.QUESTION) end
            -- Une pile ou une durée secrète ne s'écrit pas : l'effet reste, sans chiffre ni balayage.
            local counted, stacks = pcall(function() return (count and count > 1) and count or "" end)
            aura.count:SetText(counted and stacks or "")
            local timed = pcall(function()
                if duration and duration > 0 and expiration then
                    aura.cooldown:SetCooldown(expiration - duration, duration)
                    aura.cooldown:Show()
                else
                    aura.cooldown:Hide()
                end
            end)
            if not timed then aura.cooldown:Hide() end
            aura:Show()
            index = index + 1
        end
    end
    for i = shown + 1, MAX_AURAS do frame.auras[i]:Hide() end
end

-- « 42 %  reposé » : le texte de la barre d'expérience.
function ns.XPText(xp, most, rested)
    if not most or most <= 0 then return "" end
    local text = math.floor((xp or 0) * 100 / most) .. " %"
    if rested and rested > 0 then text = text .. "  reposé" end
    return text
end

-- La barre d'expérience, à part du reste : elle « ne s'affichait pas toujours » (iPhone,
-- 2026-11-09). Mise à jour au milieu de la barre du joueur, elle ne l'était plus dès qu'une
-- ligne avant elle (vie, ressource) échouait ; et un instant où le jeu ne connaît pas encore
-- l'expérience (juste après un chargement) la cachait jusqu'au prochain changement de vie ou de
-- ressource, qui peut ne jamais venir, vie et mana pleines. Maintenant elle a sa propre mise à
-- jour, garde ses dernières valeurs pendant un tel instant, ne se cache que si l'expérience est
-- bloquée, et une vérification par seconde la rattrape si un événement manque. Chaque fois
-- qu'elle change d'état, ns.db.xpSeen le note (écrit à l'enregistrement) : de quoi mesurer.
local applied  -- ce que la barre montre : "off", "unknown" ou "xp/max/reposé"
local function NoteXP(state)
    local db = ns.db
    if type(db) ~= "table" then return end
    if type(db.xpSeen) ~= "table" then db.xpSeen = {} end
    local seen = db.xpSeen
    seen[state] = (tonumber(seen[state]) or 0) + 1
    seen.last, seen.at = state, time and time() or nil
end

function Hud.UpdateXP()
    local bar = player and player.xp
    if not bar then return end
    local xp, most = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    local rested = GetXPExhaustion and GetXPExhaustion() or nil
    local state
    if IsXPUserDisabled and IsXPUserDisabled() then
        state = "off"
    elseif most > 0 then
        state = xp .. "/" .. most .. "/" .. tostring(rested ~= nil and rested > 0)
    else
        state = "unknown"
    end
    if state == applied then return end
    if state == "off" then
        bar:Hide()
        NoteXP("hidden")
    elseif state == "unknown" then
        -- Rien de connu encore : rien à montrer. Déjà montrée : elle garde ses valeurs.
        if applied == nil or applied == "off" then
            bar:Hide()
            NoteXP("waiting")
            applied = "unknown"
        elseif applied ~= "kept" then
            NoteXP("kept")
            applied = "kept"
        end
        return
    else
        bar:SetMinMaxValues(0, most)
        bar:SetValue(xp)
        bar.text:SetText(ns.XPText(xp, most, rested))
        bar:Show()
        if applied == nil or applied == "off" or applied == "unknown" then NoteXP("shown") end
    end
    applied = state
end

local function Update(frame)
    local unit = frame.unit
    if not UnitExists(unit) then return end
    local level = UnitLevel(unit)
    local known, levelText = pcall(function() return (level and level > 0) and tostring(level) or "??" end)
    if not known then levelText = "??" end
    if frame.badge then
        frame.name:SetText(UnitName(unit) or "")
        frame.badge.text:SetText(levelText)
    else
        frame.name:SetText((UnitName(unit) or "") .. "  |cffbbbbbb" .. levelText .. "|r")
    end

    local health, maxHealth = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    Fill(frame.health, health, Positive(maxHealth) == false and 1 or maxHealth)
    if unit == "player" then
        Amounts(frame.health.text, health, maxHealth)
    else
        Percent(frame.health.text, unit, health, maxHealth)
        if UnitIsDead(unit) then
            frame.health:SetStatusBarColor(0.4, 0.4, 0.4)
        elseif UnitIsFriend("player", unit) then
            frame.health:SetStatusBarColor(0.15, 0.75, 0.2)
        elseif UnitCanAttack("player", unit) then
            frame.health:SetStatusBarColor(0.85, 0.15, 0.1)
        else
            frame.health:SetStatusBarColor(0.9, 0.8, 0.2)
        end
        local combos, combo = pcall(function()
            local points = GetComboPoints and GetComboPoints("player", "target") or 0
            return points > 0 and ("Combo " .. points) or ""
        end)
        frame.combo:SetText(combos and combo or "")
    end

    -- Une ressource dont on ne peut lire le maximum (secret) reste affichée : le jeu la dessine.
    local power, maxPower = UnitPower(unit) or 0, UnitPowerMax(unit) or 0
    if Positive(maxPower) ~= false then
        local color = PowerBarColor and PowerBarColor[UnitPowerType(unit)]
        if color then frame.power:SetStatusBarColor(color.r, color.g, color.b) end
        Fill(frame.power, power, maxPower)
        Amounts(frame.power.text, power, maxPower)
        frame.power:Show()
    else
        frame.power:Hide()
    end
    UpdateAuras(frame)
end

function Hud:Init()
    -- Ta barre en haut à gauche, plus étroite qu'avant (366), tes effets dessous (Buffs.lua) ;
    -- ta cible tout en haut aussi, juste à sa droite et plus étroite (demandé sur l'iPhone,
    -- 2026-11-09 : au centre, un cran plus bas, elle était plus large que nécessaire).
    player = Unit("WolkaraMobilePlayer", "player", PLAYER_WIDTH, { "TOPLEFT", "TOPLEFT", 12, -10 })
    ns.HudPlayer = player  -- les effets du joueur (Buffs.lua) se rangent dessous
    target = Unit("WolkaraMobileTarget", "target", TARGET_WIDTH,
        { "TOPLEFT", "TOPLEFT", 12 + PLAYER_WIDTH + BESIDE, -10 })
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
    Hud.Deselect()
    self:Refresh()
end

local function Portrait(unit)
    if not SetPortraitTexture then return end
    if (unit == nil or unit == "player") and player and player.portrait then
        SetPortraitTexture(player.portrait.texture, "player")
    end
    if (unit == nil or unit == "target") and target and target.portrait and UnitExists("target") then
        SetPortraitTexture(target.portrait.texture, "target")
    end
end

-- Toucher le vide (le sol, le ciel) retire la cible : c'est le réglage du jeu « deselectOnClick »
-- (l'inverse de son « ciblage persistant »). Sur l'iPhone, rien ne la retirait (2026-11-09).
-- On l'allume tant que le réglage Cible de l'interface mobile le demande, et on rend au jeu sa
-- valeur d'avant quand on l'éteint. Hors combat, une fois la disposition faite.
local DESELECT = "deselectOnClick"
function Hud.Deselect()
    local settings = ns.db and ns.db.hud
    if not settings or InCombatLockdown() or not GetCVar or not SetCVar then return end
    local ok, current = pcall(GetCVar, DESELECT)
    if not ok or current == nil then return end  -- réglage inconnu de ce client
    if settings.deselect then
        if settings.deselectWas == nil then settings.deselectWas = tostring(current) end
        if tostring(current) ~= "1" then pcall(SetCVar, DESELECT, "1") end
    elseif settings.deselectWas ~= nil then
        pcall(SetCVar, DESELECT, settings.deselectWas)
        settings.deselectWas = nil
    end
end

local function XP() ns.Guard("expérience", Hud.UpdateXP) end

function Hud:Refresh()
    if not player then return end
    XP()
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
    if unit == nil or unit == "player" then XP(); Update(player) end
    if unit == nil or unit == "target" then Update(target) end
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
        "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_AURA" }) do
    ns.On(event, Changed)
end
ns.On("PLAYER_TARGET_CHANGED", function() Portrait("target"); Changed("target") end)
ns.On("PLAYER_XP_UPDATE", function() if player then XP() end end)
ns.On("UPDATE_EXHAUSTION", function() if player then XP() end end)
ns.On("PLAYER_LEVEL_UP", function() Changed("player") end)
-- Une fois par seconde : trois questions au jeu, et la barre ne change que si l'expérience a
-- changé.
local clock = CreateFrame("Frame")
local since = 0
clock:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since < 1 then return end
    since = 0
    if player and ns.db and ns.db.hud.enabled then XP() end
end)
Hud.clock = clock
ns.On("UNIT_COMBO_POINTS", function() Changed("target") end)
ns.On("PLAYER_ENTERING_WORLD", function() Portrait(); Changed(nil) end)
ns.On("UNIT_PORTRAIT_UPDATE", function(unit) if unit == "player" or unit == "target" then Portrait(unit) end end)
