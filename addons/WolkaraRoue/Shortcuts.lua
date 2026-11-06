-- Interface mobile : les raccourcis du haut. Quatre gros boutons seulement, pour ce qu'on
-- ouvre tout le temps (sacs, grimoire, carte) et le Menu en tuiles pour tout le reste. Quand
-- le bouton de l'interface du jeu existe, on le « clique » de façon sécurisée, ce qui marche
-- aussi en combat ; sinon on appelle la fonction du jeu qui ouvre la même fenêtre.

local _, ns = ...

local SIZE = 58
local GAP = 12

local Shortcuts = ns.Register("Raccourcis", {})
local bar

local LIST = {
    { label = "Sacs", icon = "Interface\\Icons\\INV_Misc_Bag_08", run = function()
        if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end
    end },
    { label = "Sorts", icon = "Interface\\Icons\\INV_Misc_Book_09", click = "SpellbookMicroButton", run = function()
        if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end
    end },
    { label = "Carte", icon = "Interface\\Icons\\INV_Misc_Map_01", run = function()
        if ToggleWorldMap then ToggleWorldMap() end
    end },
    { label = "Menu", icon = "Interface\\Icons\\INV_Misc_Gear_01", menu = true },
}

local function Decorate(button, info)
    button:SetSize(SIZE, SIZE)
    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 3)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(info.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(button, icon)
    local label = ns.Label(button, "GameFontNormal", info.label)
    label:SetPoint("TOP", button, "BOTTOM", 0, -2)
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.2, 0)
    highlight:SetBlendMode("ADD")
end

local function MakeButton(info, index)
    local name = "WolkaraMobileShortcut" .. index
    local target = info.click and _G[info.click]
    local button
    if info.menu and ns.Menu and ns.Menu.frame then
        -- Le Menu s'ouvre et se ferme comme une roue : en combat aussi.
        button = CreateFrame("Button", name, bar, "SecureHandlerClickTemplate")
        button:RegisterForClicks("AnyUp")
        button:SetFrameRef("menu", ns.Menu.frame)
        button:SetAttribute("_onclick", [=[
            local menu = self:GetFrameRef("menu")
            if menu:IsShown() then menu:Hide() else menu:Show() end
        ]=])
    elseif target then
        button = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", target)
    else
        button = CreateFrame("Button", name, bar)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function() ns.Guard(info.label, info.run) end)
    end
    Decorate(button, info)
    button:SetPoint("LEFT", bar, "LEFT", 8 + (index - 1) * (SIZE + GAP), 8)
    ns.DragHandle(button, bar)
    return button
end

function Shortcuts:Init()
    bar = CreateFrame("Frame", "WolkaraMobileShortcuts", UIParent)
    bar:SetFrameStrata("LOW")  -- sous les fenêtres du jeu
    bar:SetSize(16 + #LIST * (SIZE + GAP) - GAP, SIZE + 30)
    -- La barre ne prend les touchers qu'en mode Personnaliser : entre deux boutons, le
    -- toucher va au jeu.
    bar:EnableMouse(false)
    bar.back = ns.Box(bar, "BACKGROUND", 0, 0, 0, 0)
    bar.glow = ns.EditFrame(bar)
    -- En haut, à droite du centre : le centre est la poignée de la barre de l'app.
    ns.Movable(bar, function() return ns.db.shortcuts end, "pos", { "TOP", "TOP", 190, -4 })
    for index, info in ipairs(LIST) do MakeButton(info, index) end
end

function Shortcuts:Layout()
    if ns.db.shortcuts.enabled then
        bar:SetScale(ns.db.shortcuts.scale / 100)
        bar:PlaceSaved()
        bar:Show()
    else
        bar:Hide()
    end
end

function Shortcuts:SetEditing(on)
    bar.glow:SetShown(on)
    bar:EnableMouse(on)
    bar.back:SetVertexColor(0, 0, 0, on and 0.35 or 0)
end
