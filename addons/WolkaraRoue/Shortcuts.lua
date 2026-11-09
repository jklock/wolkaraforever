-- Interface mobile : les raccourcis. Un seul petit bouton « ☰ » sous la mini-carte ; le
-- toucher ouvre un menu rapide compact (sacs, grimoire, personnage, quêtes, carte, et le Menu en
-- tuiles pour tout le reste), le retoucher le referme. Avant, quatre gros boutons légendés
-- restaient toujours à l'écran ; le menu rapide vient de l'interface Duo de scarrdi94
-- (jklock/wolkaraforever#26), qui laisse le jeu plus dégagé.
--
-- Le bouton et le menu s'ouvrent et se ferment par du code sécurisé : en combat aussi. Quand le
-- bouton de l'interface du jeu existe, une entrée le « clique » de façon sécurisée, ce qui marche
-- aussi en combat ; sinon elle appelle la fonction du jeu qui ouvre la même fenêtre.
--
-- « Enregistrer » recharge l'interface, ce qui écrit la sauvegarde (Save.lua) ; un point doré
-- sur le bouton « ☰ » dit qu'il y a quelque chose à enregistrer. Le bouton qui surgissait au
-- milieu de l'écran pendant le jeu n'existe plus.

local _, ns = ...

local TAB = 38
local ICON, COLUMN_W, ROW_H, COLUMNS = 42, 80, 66, 4

local Shortcuts = ns.Register("Raccourcis", {})
ns.Shortcuts = Shortcuts
local tab, panel

local LIST = {
    { label = "Sacs", icon = "Interface\\Icons\\INV_Misc_Bag_08", run = function()
        if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end
    end },
    { label = "Sorts", icon = "Interface\\Icons\\INV_Misc_Book_09", click = "SpellbookMicroButton", run = function()
        if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end
    end },
    { label = "Personnage", icon = "Interface\\Icons\\INV_Shirt_White_01", click = "CharacterMicroButton", run = function()
        if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
    end },
    { label = "Quêtes", icon = "Interface\\Icons\\INV_Misc_Note_01", click = "QuestLogMicroButton", run = function()
        if ToggleQuestLog then ToggleQuestLog() end
    end },
    { label = "Carte", icon = "Interface\\Icons\\INV_Misc_Map_01", run = function()
        if ToggleWorldMap then ToggleWorldMap() end
    end },
    { label = "Menu", icon = "Interface\\Icons\\INV_Misc_Gear_01", menu = true },
    { label = "Enregistrer", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", save = true },
}
Shortcuts.LIST = LIST

local function Decorate(button, info)
    button:SetSize(ICON, ICON)
    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.9, 2)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(info.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(button, icon)
    local label = ns.Label(button, "GameFontHighlightSmall", info.label)
    label:SetPoint("TOP", button, "BOTTOM", 0, -2)
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.2, 0)
    highlight:SetBlendMode("ADD")
end

-- Une entrée touchée referme le menu rapide, par du code sécurisé (le combat le permet).
local CLOSE_AFTER = [=[ return nil, "close" ]=]
local CLOSE = [=[ owner:Hide() ]=]

local function MakeEntry(info, index)
    local name = "WolkaraMobileShortcut" .. index
    local target = info.click and _G[info.click]
    local button
    if info.menu and ns.Menu and ns.Menu.frame then
        button = CreateFrame("Button", name, panel, "SecureHandlerClickTemplate")
        button:RegisterForClicks("AnyUp")
        button:SetFrameRef("menu", ns.Menu.frame)
        button:SetFrameRef("panel", panel)
        button:SetAttribute("_onclick", [=[
            local menu = self:GetFrameRef("menu")
            if menu:IsShown() then menu:Hide() else menu:Show() end
            self:GetFrameRef("panel"):Hide()
        ]=])
    elseif info.save then
        -- Le /reload du jeu, toujours (même sans changement en attente) ; arrêté en combat.
        button = CreateFrame("Button", name, panel, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", ns.RELOAD or "/reload")
        button:SetScript("PreClick", function(self) if ns.SavePreClick then ns.SavePreClick(self, true) end end)
    elseif target then
        button = CreateFrame("Button", name, panel, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", target)
        if SecureHandlerWrapScript then SecureHandlerWrapScript(button, "OnClick", panel, CLOSE_AFTER, CLOSE) end
    else
        button = CreateFrame("Button", name, panel)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function()
            if not InCombatLockdown() then panel:Hide() end
            ns.Guard(info.label, info.run)
        end)
    end
    Decorate(button, info)
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + column * COLUMN_W + (COLUMN_W - ICON) / 2, -12 - row * ROW_H)
    return button
end

function Shortcuts:Init()
    -- Le bouton « ☰ » : trois traits dorés.
    tab = CreateFrame("Button", "WolkaraMobileShortcuts", UIParent, "SecureHandlerClickTemplate")
    tab:SetFrameStrata("LOW")  -- sous les fenêtres du jeu
    tab:SetSize(TAB, TAB)
    tab:RegisterForClicks("AnyUp")
    tab:SetHitRectInsets(-8, -8, -8, -8)
    ns.Disc(tab, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 2)
    for i = 1, 3 do
        local line = ns.Box(tab, "ARTWORK", 1, 0.82, 0.3, 0.95)
        line:ClearAllPoints()
        line:SetSize(20, 3)
        line:SetPoint("CENTER", 0, (2 - i) * 7)
    end
    local glow = ns.Disc(tab, "HIGHLIGHT", 1, 1, 1, 0.15, 0)
    glow:SetBlendMode("ADD")
    tab.glow = ns.EditFrame(tab)
    -- Le point doré : quelque chose attend d'être enregistré.
    local dot = tab:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(ns.WHITE)
    dot:SetVertexColor(1, 0.78, 0.2, 1)
    dot:SetSize(12, 12)
    dot:SetPoint("TOPRIGHT", 3, 3)
    ns.Circle(tab, dot)
    dot:SetShown(ns.SavePending ~= nil and ns.SavePending())
    tab.dot = dot
    if ns.OnSavePending then ns.OnSavePending(function(on) dot:SetShown(on) end) end
    -- En haut, à gauche de la mini-carte (voir Layout) ; ceci ne sert que sans mini-carte.
    ns.Movable(tab, function() return ns.db.shortcuts end, "pos", { "TOPRIGHT", "TOPRIGHT", -20, -14 })

    panel = CreateFrame("Frame", "WolkaraMobileQuickMenu", UIParent, "SecureHandlerBaseTemplate")
    panel:SetFrameStrata("MEDIUM")
    local rows = math.ceil(#LIST / COLUMNS)
    panel:SetSize(24 + COLUMNS * COLUMN_W, 20 + rows * ROW_H)
    panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", -8, 0)
    panel:EnableMouse(true)
    ns.Box(panel, "BACKGROUND", 0.04, 0.05, 0.08, 0.9)
    if ns.Surface then ns.Surface(panel, "panel", 0) end
    panel:Hide()
    for index, info in ipairs(LIST) do MakeEntry(info, index) end

    tab:SetFrameRef("panel", panel)
    tab:SetAttribute("_onclick", [=[
        local panel = self:GetFrameRef("panel")
        if panel:IsShown() then panel:Hide() else panel:Show() end
    ]=])
end

function Shortcuts:IsOpen() return panel ~= nil and panel:IsShown() end

function Shortcuts:Layout()
    if ns.db.shortcuts.enabled then
        tab:SetScale(ns.db.shortcuts.scale / 100)
        panel:SetScale(ns.db.shortcuts.scale / 100)
        -- Tant qu'on ne l'a pas déplacé : en haut de l'écran, à gauche de la mini-carte et de ses
        -- boutons + et -, au niveau de son bord haut ; il la suit quand elle change de taille.
        -- Plus sous elle depuis la 0.9 : il y était trop bas (demandé sur l'iPhone, 2026-11-09).
        local map = _G.Minimap
        if ns.db.shortcuts.pos == nil and map then
            -- Les boutons + et - (Minimap.lua, disposé après nous) sont là quand la mini-carte l'est.
            local scale = ns.db.shortcuts.scale / 100
            local beside = (ns.db.minimap and ns.db.minimap.shown) and (6 + 34 + 10) or 10
            tab:ClearAllPoints()
            tab:SetPoint("TOPRIGHT", map, "TOPLEFT", -beside / scale, 0)
        else
            tab:PlaceSaved()
        end
        tab:Show()
    else
        tab:Hide()
        panel:Hide()
    end
end

function Shortcuts:SetEditing(on)
    tab.glow:SetShown(on)
    if on then panel:Hide() end
end

function Shortcuts:CombatStarts() end
