-- Quick menu, Edit and Bags buttons (iPhone Duo layout).
local _, ns = ...

local DuoMenu = ns.Register("Duo menu", {})

local ICON, COLUMN_W, ROW_H, COLUMNS = 40, 84, 64, 4
local panel, tab, bags, menuButton, edit
local buttons = {}
local mapClick

local function Decorate(button, icon, size)
    button:SetSize(size, size)
    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.9, 2)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(icon)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(button, texture)
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.2, 0)
    highlight:SetBlendMode("ADD")
end

local function Make(info, index)
    local target = info.click and _G[info.click]
    local button
    if target or info.macro then
        button = CreateFrame("Button", "WolkaraMobileQuickMenu" .. index, panel, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        if target then
            button:SetAttribute("type", "click")
            button:SetAttribute("clickbutton", target)
        else
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext", info.macro)
        end
        button:SetScript("PostClick", function(_, _, down)
            if not down and not InCombatLockdown() then panel:Hide() end
        end)
    else
        button = CreateFrame("Button", "WolkaraMobileQuickMenu" .. index, panel)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function()
            if not InCombatLockdown() then panel:Hide() end
            ns.Guard(info.label, info.run)
        end)
    end
    Decorate(button, info.icon, ICON)
    button.label = ns.Label(button, "GameFontHighlightSmall", ns.T(info.label))
    button.label:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button:Hide()
    return button
end

function DuoMenu:Init()
    panel = CreateFrame("Frame", "WolkaraMobileQuickMenu", UIParent, BackdropTemplateMixin and "SecureHandlerBaseTemplate,BackdropTemplate" or "SecureHandlerBaseTemplate")
    panel:SetFrameStrata("MEDIUM")
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        panel:SetBackdropColor(0.04, 0.05, 0.08, 0.9)
        panel:SetBackdropBorderColor(0.55, 0.5, 0.4, 0.9)
    else
        ns.Box(panel, "BACKGROUND", 0.04, 0.05, 0.08, 0.9)
    end
    for index, info in ipairs(ns.MenuTiles or {}) do buttons[info.label] = Make(info, index) end

    menuButton = CreateFrame("Button", "WolkaraMobileQuickMenuMain", panel, "SecureHandlerClickTemplate")
    menuButton:RegisterForClicks("AnyUp")
    if ns.Menu and ns.Menu.frame then menuButton:SetFrameRef("menu", ns.Menu.frame) end
    menuButton:SetFrameRef("panel", panel)
    menuButton:SetAttribute("_onclick", [=[
        local menu = self:GetFrameRef("menu")
        if menu then if menu:IsShown() then menu:Hide() else menu:Show() end end
        self:GetFrameRef("panel"):Hide()
    ]=])
    Decorate(menuButton, "Interface\\Icons\\INV_Misc_Gear_01", ICON)
    menuButton.label = ns.Label(menuButton, "GameFontHighlightSmall", ns.T("Menu"))
    menuButton.label:SetPoint("TOP", menuButton, "BOTTOM", 0, -1)
    panel:Hide()

    tab = CreateFrame("Button", "WolkaraMobileQuickMenuTab", UIParent, "SecureHandlerClickTemplate")
    tab:SetFrameStrata("MEDIUM")
    tab:SetSize(34, 34)
    tab:RegisterForClicks("AnyUp")
    tab:SetFrameRef("panel", panel)
    tab:SetAttribute("_onclick", [=[
        local panel = self:GetFrameRef("panel")
        if panel:IsShown() then panel:Hide() else panel:Show() end
    ]=])
    ns.Box(tab, "BACKGROUND", 0.05, 0.05, 0.08, 0.85)
    for i = 1, 3 do
        local bar = ns.Box(tab, "ARTWORK", 1, 0.82, 0.3, 0.95)
        bar:ClearAllPoints()
        bar:SetSize(20, 3)
        bar:SetPoint("CENTER", 0, (2 - i) * 7)
    end
    local tabGlow = ns.Box(tab, "HIGHLIGHT", 1, 1, 1, 0.15)
    tabGlow:SetBlendMode("ADD")
    tab:Hide()

    edit = CreateFrame("Button", "WolkaraMobileDuoEdit", UIParent)
    edit:SetFrameStrata("MEDIUM")
    edit:RegisterForClicks("AnyUp")
    edit:SetScript("OnClick", function()
        if InCombatLockdown() then ns.Print(ns.T("customize out of combat.")); return end
        if ns.editMode then ns.ExitEditMode() elseif ns.EnterEditMode then ns.EnterEditMode(nil) end
    end)
    Decorate(edit, "Interface\\Icons\\INV_Misc_Book_09", 34)
    edit.label = ns.Label(edit, "GameFontHighlightSmall", ns.T("Edit"))
    edit.label:SetPoint("TOP", edit, "BOTTOM", 0, -1)
    edit:Hide()

    bags = CreateFrame("Button", "WolkaraMobileDuoBags", UIParent)
    bags:SetFrameStrata("LOW")
    bags:RegisterForClicks("AnyUp")
    bags:SetScript("OnClick", function()
        if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end
    end)
    Decorate(bags, "Interface\\Icons\\INV_Misc_Bag_08", 50)
    bags:Hide()
end

local function MinimapOpensMap(on)
    local minimap = _G.Minimap
    if not minimap then return end
    if on and mapClick == nil then
        mapClick = minimap:GetScript("OnMouseUp") or false
        minimap:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and mapClick then return mapClick(self, button) end
            if ToggleWorldMap then ToggleWorldMap() end
        end)
    elseif not on and mapClick ~= nil then
        minimap:SetScript("OnMouseUp", mapClick or nil)
        mapClick = nil
    end
end

local function Arrange()
    for _, button in pairs(buttons) do button:Hide() end
    local shown = {}
    for _, label in ipairs(ns.QuickMenuList and ns.QuickMenuList() or {}) do
        if buttons[label] then shown[#shown + 1] = buttons[label] end
    end
    shown[#shown + 1] = menuButton
    local columns = math.max(COLUMNS, math.ceil(#shown / 2))
    for index, button in ipairs(shown) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + column * COLUMN_W + (COLUMN_W - ICON) / 2, -10 - row * ROW_H)
        button:Show()
    end
    local rows = math.ceil(#shown / columns)
    panel:SetSize(20 + columns * COLUMN_W, 16 + rows * ROW_H)
end

local minimapHome
local function PlaceMinimap(duo)
    local cluster = _G.MinimapCluster
    if not cluster or InCombatLockdown() then return end
    if not minimapHome then minimapHome = { cluster:GetPoint(1) } end
    local point, relative, relativePoint, x, y = unpack(minimapHome)
    if not point then return end
    cluster:ClearAllPoints()
    cluster:SetPoint(point, relative, relativePoint, (x or 0) + (duo and -22 or 0), (y or 0) + (duo and -8 or 0))
end

function ns.DuoMenuLayout()
    if not panel or InCombatLockdown() then return end
    local duo = ns.DuoLayout() and not (ns.Fan and not ns.Fan:Enabled())
    local shortcuts = _G.WolkaraMobileShortcuts
    MinimapOpensMap(duo)
    PlaceMinimap(duo)
    if not duo then
        tab:Hide(); panel:Hide(); bags:Hide(); edit:Hide()
        return
    end
    if shortcuts then shortcuts:Hide() end
    Arrange()
    local H = UIParent:GetHeight()
    tab:ClearAllPoints()
    tab:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -H * 0.245)
    tab:SetHitRectInsets(-6, -6, -6, -6)
    tab:Show()
    edit:ClearAllPoints()
    edit:SetPoint("TOP", tab, "BOTTOM", 0, -10)
    edit:SetHitRectInsets(-6, -6, -6, -6)
    edit:Show()
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", tab, "TOPLEFT", -6, 0)
    bags:ClearAllPoints()
    bags:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", -H * 0.229, H * 0.476)
    bags:SetHitRectInsets(-6, -6, -6, -6)
    bags:Show()
end

function DuoMenu:Layout() ns.DuoMenuLayout() end
function DuoMenu:SetEditing() end
