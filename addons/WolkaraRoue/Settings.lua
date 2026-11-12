-- Interface mobile : le panneau de réglages, tout au toucher (l'engrenage « Mobile » des
-- raccourcis, ou /mobile). Les roues de sorts se règlent côté par côté, à droite et à gauche :
-- combien de roues, combien de sorts sur chacune, leur taille et l'écart entre deux sorts ; les
-- raccourcis, les barres de vie, la cible, le chat, les quêtes et la mini-carte ont leurs
-- réglages. « Personnaliser » passe en mode déplacement : on fait glisser chaque élément là où
-- le pouce l'attend, et on touche une case pour choisir son sort.
--
-- Les roues dorées (un bouton qui ouvre un cercle de sorts) et le mode « Arc » des sorts sont
-- partis en 0.8. Le nombre de roues de chaque côté se choisit ici depuis la 0.9, quatre par
-- défaut (demandé sur l'iPhone, 2026-11-09).

local _, ns = ...

local Settings = ns.Register("Réglages", {})
ns.Settings = Settings

local panel, doneButton
local updaters = {}
local ROW_H = 40
local LEFT = 20

local function Apply()
    if InCombatLockdown() then ns.Print("on règle l'interface hors combat."); return false end
    ns.Layout()
    ns.Refresh()
    for _, update in ipairs(updaters) do update() end
    return true
end

local function Text(parent, text, x, y, width)
    local label = ns.Label(parent, "GameFontHighlight", text)
    label:SetPoint("TOPLEFT", x, y)
    if width then label:SetWidth(width); label:SetJustifyH("LEFT") end
    return label
end

-- [ - ] valeur [ + ] ; `reason` dit ce qui a changé dans le journal de la sauvegarde, quand la
-- légende seule (« Droite ») ne le dit pas.
local function Stepper(parent, x, y, caption, get, set, step, low, high, suffix, reason)
    local name = Text(parent, caption, x, y - 10)
    local minus = ns.UIButton(parent, "-", 36, 34, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() - step, low, high)); ns.MarkChanged("réglage : " .. (reason or caption)); Apply()
    end)
    minus:SetPoint("TOPLEFT", x + 62, y)
    local value = ns.Label(parent, "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(50)
    local plus = ns.UIButton(parent, "+", 36, 34, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() + step, low, high)); ns.MarkChanged("réglage : " .. (reason or caption)); Apply()
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    updaters[#updaters + 1] = function() value:SetText(get() .. (suffix or "")) end
    return name
end

-- Un bouton qui bascule entre deux états et affiche celui en cours.
local function Switch(parent, x, y, width, get, set, onText, offText, caption)
    local button
    button = ns.UIButton(parent, "", width, 34, function()
        if InCombatLockdown() then return Apply() end
        set(not get()); ns.MarkChanged("réglage : " .. (caption or onText)); Apply()
    end)
    button:SetPoint("TOPLEFT", x, y)
    updaters[#updaters + 1] = function()
        local on = get()
        button.text:SetText(on and onText or offText)
        button.back:SetVertexColor(on and 0.2 or 0.18, on and 0.45 or 0.18, on and 0.25 or 0.22, 0.95)
    end
    return button
end

local function Build()
    panel = CreateFrame("Frame", "WolkaraMobileSettings", UIParent)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetWidth(700)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.04, 0.05, 0.08, 0.96)
    if ns.Surface then ns.Surface(panel, "panel", 2) end
    local title = ns.Label(panel, "GameFontNormalLarge", "Interface mobile")
    title:SetPoint("TOPLEFT", LEFT, -22)
    Stepper(panel, LEFT + 375, -14, "Interface", function() return ns.db.ui.scale end,
        function(v) ns.db.ui.scale = v end, 10, 100, 220, " %")

    -- Les roues de sorts, une ligne par réglage, la droite puis la gauche : combien de roues,
    -- combien de sorts sur chacune, leur taille, l'écart entre deux sorts qui se suivent.
    local y = -64
    local WHEEL_ROWS = {
        { label = "Roues", field = "wheels", step = 1, low = 1, high = ns.PAGES },
        { label = "Sorts par roue", field = "count", step = 1, low = 0, high = ns.MAX_FREE },
        { label = "Taille des sorts", field = "scale", step = 10, low = 50, high = 200, suffix = " %" },
        { label = "Écart des sorts", field = "spread", step = 10, low = 60, high = 180, suffix = " %" },
    }
    for _, row in ipairs(WHEEL_ROWS) do
        Text(panel, row.label, LEFT, y - 10, 150)
        for column, side in ipairs({ { key = "free", caption = "Droite" }, { key = "freeLeft", caption = "Gauche" } }) do
            Stepper(panel, LEFT + 175 + (column - 1) * 200, y, side.caption,
                function() return ns.db[side.key][row.field] end,
                function(v) ns.db[side.key][row.field] = v end,
                row.step, row.low, row.high, row.suffix, row.label:lower() .. " " .. side.caption:lower())
        end
        y = y - ROW_H
    end
    -- Comment passer d'une roue à l'autre, dit là où l'on choisit leur nombre.
    local hint = ns.Label(panel, "GameFontHighlightSmall",
        "Changer de roue : touche ses onglets numérotés, au-dessus d'elle, ou glisse en diagonale depuis la roue (vers le centre : la suivante ; vers le coin : la précédente).")
    hint:SetPoint("TOPLEFT", LEFT, y + 2)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.75, 0.75, 0.75)
    panel.wheelHint = hint
    y = y - 34

    Text(panel, "Raccourcis", LEFT, y - 10, 90)
    Switch(panel, LEFT + 90, y, 70, function() return ns.db.shortcuts.enabled end,
        function(v) ns.db.shortcuts.enabled = v end, "Oui", "Non")
    Text(panel, "Vie", LEFT + 175, y - 10, 50)
    Switch(panel, LEFT + 237, y, 70, function() return ns.db.hud.enabled end,
        function(v) ns.db.hud.enabled = v end, "Oui", "Non")
    Stepper(panel, LEFT + 375, y, "Taille", function() return ns.db.hud.scale end,
        function(v) ns.db.hud.scale = v end, 10, 50, 200, " %")
    y = y - ROW_H

    Text(panel, "Cible", LEFT, y - 10, 90)
    Text(panel, "Toucher le vide la retire", LEFT + 90, y - 10, 230)
    Switch(panel, LEFT + 330, y, 70, function() return ns.db.hud.deselect end,
        function(v) ns.db.hud.deselect = v end, "Oui", "Non", "toucher le vide retire la cible")
    y = y - ROW_H

    Text(panel, "Chat", LEFT, y - 10, 90)
    Switch(panel, LEFT + 90, y, 70, function() return ns.db.chat.custom end,
        function(v) ns.db.chat.custom = v end, "Mobile", "Jeu")
    Stepper(panel, LEFT + 175, y, "Texte", function() return ns.db.chat.fontSize end,
        function(v) ns.db.chat.fontSize = v end, 1, 10, 26)
    y = y - ROW_H

    Text(panel, "Quêtes", LEFT, y - 10, 90)
    Switch(panel, LEFT + 90, y, 70, function() return ns.db.quests.enabled end,
        function(v) ns.db.quests.enabled = v end, "Carte", "Jeu")
    Stepper(panel, LEFT + 175, y, "Affichées", function() return ns.db.quests.shown end,
        function(v) ns.db.quests.shown = v end, 1, 1, 5)
    y = y - ROW_H

    Text(panel, "Mini-carte", LEFT, y - 10, 90)
    Switch(panel, LEFT + 90, y, 70, function() return ns.db.minimap.shown end,
        function(v) ns.db.minimap.shown = v end, "Oui", "Non")
    Stepper(panel, LEFT + 175, y, "Taille", function() return ns.db.minimap.scale end,
        function(v) ns.db.minimap.scale = v end, 10, 30, 150, " %")
    y = y - ROW_H

    Text(panel, "D'origine", LEFT, y - 10, 90)
    Text(panel, "Barres de sorts", LEFT + 90, y - 10, 130)
    Switch(panel, LEFT + 220, y, 110, function() return not ns.db.blizzard.hideBars end,
        function(v) ns.db.blizzard.hideBars = not v end, "Affichées", "Masquées")
    Text(panel, "Cadres joueur et cible", LEFT + 345, y - 10, 190)
    Switch(panel, LEFT + 545, y, 110, function() return not ns.db.blizzard.hideUnitFrames end,
        function(v) ns.db.blizzard.hideUnitFrames = not v end, "Affichés", "Masqués")
    y = y - ROW_H

    panel:SetHeight(-y + 70)

    local customize = ns.UIButton(panel, "Personnaliser", 200, 44, function()
        panel:Hide()
        ns.SetEditing(true)
    end)
    customize:SetPoint("BOTTOMLEFT", LEFT, 16)
    local defaults = ns.UIButton(panel, "Positions par défaut", 230, 44, function()
        if InCombatLockdown() then return Apply() end
        ns.ClearPositions(ns.db)
        ns.db.quests.pos = nil
        ns.MarkChanged("positions par défaut")
        Apply()
    end)
    defaults:SetPoint("LEFT", customize, "RIGHT", 10, 0)
    -- Fermer et Terminé enregistrent ce qui a changé (Save.lua) : le jeu n'écrit la sauvegarde
    -- qu'en rechargeant l'interface sur un vrai toucher.
    local close = ns.UIButton(panel, "Fermer", 130, 44, function() panel:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -LEFT, 16)
    if ns.SaveOver then ns.SaveOver(close, function() panel:Hide() end) end

    -- En mode Personnaliser : un seul bouton à l'écran pour en sortir.
    doneButton = ns.UIButton(UIParent, "Terminé", 180, 44, function() ns.SetEditing(false) end)
    doneButton:SetFrameStrata("FULLSCREEN_DIALOG")
    doneButton:SetPoint("TOP", UIParent, "TOP", 0, -60)
    doneButton.back:SetVertexColor(0.85, 0.68, 0.3, 0.95)
    if ns.SaveOver then ns.SaveOver(doneButton, function() ns.SetEditing(false) end) end
    doneButton:Hide()
end

function Settings:Init() Build() end

function Settings:IsOpen() return panel ~= nil and panel:IsShown() end

function Settings:Toggle()
    if not panel then return end
    if panel:IsShown() then panel:Hide(); return end
    if InCombatLockdown() then ns.Print("on règle l'interface hors combat."); return end
    for _, update in ipairs(updaters) do update() end
    -- Toujours entier à l'écran, quelle que soit la taille de l'interface.
    panel:SetScale(1)
    panel:SetScale(math.min(1, (UIParent:GetWidth() - 16) / panel:GetWidth(), (UIParent:GetHeight() - 16) / panel:GetHeight()))
    panel:Show()
end

function Settings:SetEditing(on)
    doneButton:SetShown(on)
    if on and panel then panel:Hide() end
end

function Settings:CombatStarts()
    if panel then panel:Hide() end
end
