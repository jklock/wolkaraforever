-- Interface mobile : le panneau de réglages, tout au toucher (l'engrenage « Mobile » des
-- raccourcis, ou /mobile). Chaque roue a son interrupteur, son nombre de cases, sa taille
-- et son ouverture ; les boutons libres, les raccourcis, les barres de vie et le chat ont
-- les leurs. « Personnaliser » passe en mode déplacement : on fait glisser chaque élément
-- là où le pouce l'attend, et on touche une case pour choisir son sort.

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

-- [ - ] valeur [ + ]
local function Stepper(parent, x, y, caption, get, set, step, low, high, suffix)
    local name = Text(parent, caption, x, y - 10)
    local minus = ns.UIButton(parent, "-", 36, 34, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() - step, low, high)); ns.MarkChanged(); Apply()
    end)
    minus:SetPoint("TOPLEFT", x + 62, y)
    local value = ns.Label(parent, "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(50)
    local plus = ns.UIButton(parent, "+", 36, 34, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() + step, low, high)); ns.MarkChanged(); Apply()
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    updaters[#updaters + 1] = function() value:SetText(get() .. (suffix or "")) end
    return name
end

-- Un bouton qui bascule entre deux états et affiche celui en cours.
local function Switch(parent, x, y, width, get, set, onText, offText)
    local button
    button = ns.UIButton(parent, "", width, 34, function()
        if InCombatLockdown() then return Apply() end
        set(not get()); ns.MarkChanged(); Apply()
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
    panel:SetSize(700, 70 + ROW_H * 12 + 70)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.04, 0.05, 0.08, 0.96)
    local title = ns.Label(panel, "GameFontNormalLarge", "Interface mobile")
    title:SetPoint("TOPLEFT", LEFT, -22)
    Stepper(panel, LEFT + 375, -14, "Interface", function() return ns.db.ui.scale end,
        function(v) ns.db.ui.scale = v end, 10, 100, 220, " %")

    local y = -64
    for index = 1, ns.MAX_WHEELS do
        local function wheel() return ns.db.wheels[index] end
        Text(panel, index == 1 and "Roue" or ("Roue " .. index), LEFT, y - 10, 90)
        Switch(panel, LEFT + 90, y, 70, function() return wheel().enabled end,
            function(v) wheel().enabled = v end, "Oui", "Non")
        Stepper(panel, LEFT + 175, y, "Cases", function() return wheel().slots end,
            function(v) wheel().slots = v end, 1, 4, ns.MAX_SLOTS)
        Stepper(panel, LEFT + 375, y, "Taille", function() return wheel().scale end,
            function(v) wheel().scale = v end, 10, 50, 200, " %")
        Switch(panel, LEFT + 575, y, 90, function() return wheel().open ~= "centre" end,
            function(v) wheel().open = v and "bouton" or "centre" end, "Au bouton", "Au centre")
        y = y - ROW_H
    end

    for _, side in ipairs({ { key = "free", label = "Sorts à droite" }, { key = "freeLeft", label = "Sorts à gauche" } }) do
        Text(panel, side.label, LEFT, y - 10, 150)
        Stepper(panel, LEFT + 175, y, "Nombre", function() return ns.db[side.key].count end,
            function(v) ns.db[side.key].count = v end, 1, 0, ns.MAX_FREE)
        Stepper(panel, LEFT + 375, y, "Taille", function() return ns.db[side.key].scale end,
            function(v) ns.db[side.key].scale = v end, 10, 50, 200, " %")
        Switch(panel, LEFT + 575, y, 90, function() return ns.db[side.key].turn end,
            function(v) ns.db[side.key].turn = v end, "Roue", "Arc")
        y = y - ROW_H
    end

    -- En arc, l'écart entre le stick et ses sorts, donc entre les sorts. En roue, l'écart entre
    -- deux sorts qui se suivent. Un sort déplacé à la main en mode Personnaliser garde sa place ;
    -- Positions par défaut le rend à l'arc.
    Text(panel, "Écart des sorts", LEFT, y - 10, 150)
    Stepper(panel, LEFT + 175, y, "Droite", function() return ns.db.free.spread end,
        function(v) ns.db.free.spread = v end, 10, 60, 180, " %")
    Stepper(panel, LEFT + 375, y, "Gauche", function() return ns.db.freeLeft.spread end,
        function(v) ns.db.freeLeft.spread = v end, 10, 60, 180, " %")
    y = y - ROW_H

    Text(panel, "Raccourcis", LEFT, y - 10, 90)
    Switch(panel, LEFT + 90, y, 70, function() return ns.db.shortcuts.enabled end,
        function(v) ns.db.shortcuts.enabled = v end, "Oui", "Non")
    Text(panel, "Vie", LEFT + 175, y - 10, 50)
    Switch(panel, LEFT + 237, y, 70, function() return ns.db.hud.enabled end,
        function(v) ns.db.hud.enabled = v end, "Oui", "Non")
    Stepper(panel, LEFT + 375, y, "Taille", function() return ns.db.hud.scale end,
        function(v) ns.db.hud.scale = v end, 10, 50, 200, " %")
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

    local customize = ns.UIButton(panel, "Personnaliser", 200, 44, function()
        panel:Hide()
        ns.SetEditing(true)
    end)
    customize:SetPoint("BOTTOMLEFT", LEFT, 16)
    local defaults = ns.UIButton(panel, "Positions par défaut", 230, 44, function()
        if InCombatLockdown() then return Apply() end
        ns.ClearPositions(ns.db)
        ns.db.quests.pos = nil
        ns.MarkChanged()
        Apply()
    end)
    defaults:SetPoint("LEFT", customize, "RIGHT", 10, 0)
    local close = ns.UIButton(panel, "Fermer", 130, 44, function() panel:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -LEFT, 16)

    -- En mode Personnaliser : un seul bouton à l'écran pour en sortir.
    doneButton = ns.UIButton(UIParent, "Terminé", 180, 44, function() ns.SetEditing(false) end)
    doneButton:SetFrameStrata("FULLSCREEN_DIALOG")
    doneButton:SetPoint("TOP", UIParent, "TOP", 0, -60)
    doneButton.back:SetVertexColor(0.85, 0.68, 0.3, 0.95)
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
