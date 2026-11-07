-- Interface mobile : le menu en grandes tuiles, façon tablette. Tout ce qu'on ouvre moins
-- souvent que les sacs ou la carte : personnage, talents, quêtes, social, guilde, macros,
-- options du jeu, réglages de l'interface mobile, recharger, déconnexion, quitter.
-- Il s'ouvre et se ferme en combat aussi (cadre sécurisé) ; toucher à côté le referme.

local _, ns = ...

local COLUMNS = 5
local TILE_W, TILE_H = 132, 118

local Menu = ns.Register("Menu", {})
ns.Menu = Menu

local TILES = {
    { label = "Personnage", icon = "Interface\\Icons\\INV_Shirt_White_01", click = "CharacterMicroButton",
      run = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
    { label = "Sacs", icon = "Interface\\Icons\\INV_Misc_Bag_08",
      run = function() if ToggleAllBags then ToggleAllBags() end end },
    { label = "Sorts", icon = "Interface\\Icons\\INV_Misc_Book_09", click = "SpellbookMicroButton",
      run = function() if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end end },
    { label = "Talents", icon = "Interface\\Icons\\Ability_Marksmanship", click = "TalentMicroButton",
      run = function() if ToggleTalentFrame then ToggleTalentFrame() end end },
    { label = "Quêtes", icon = "Interface\\Icons\\INV_Misc_Note_01", click = "QuestLogMicroButton",
      run = function() if ToggleQuestLog then ToggleQuestLog() end end },
    { label = "Carte", icon = "Interface\\Icons\\INV_Misc_Map_01",
      run = function() if ToggleWorldMap then ToggleWorldMap() end end },
    { label = "Social", icon = "Interface\\Icons\\INV_Letter_02", click = "SocialsMicroButton",
      run = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { label = "Guilde", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", click = "GuildMicroButton",
      run = function() if ToggleGuildFrame then ToggleGuildFrame() end end },
    { label = "Macros", icon = "Interface\\Icons\\INV_Scroll_03", macro = "/macro" },
    { label = "Menu du jeu", icon = "Interface\\Icons\\INV_Misc_Gear_01", run = function()
        if GameMenuFrame then
            if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
        elseif ToggleGameMenu then
            ToggleGameMenu()
        end
    end },
    { label = "Réglages du jeu", icon = "Interface\\Icons\\INV_Misc_Wrench_01", run = function()
        if SettingsPanel and SettingsPanel.Open then
            SettingsPanel:Open()
        elseif SettingsPanel then
            ShowUIPanel(SettingsPanel)
        elseif VideoOptionsFrame then
            ShowUIPanel(VideoOptionsFrame)
        elseif InterfaceOptionsFrame then
            ShowUIPanel(InterfaceOptionsFrame)
        end
    end },
    { label = "Interface mobile", icon = "Interface\\Icons\\Trade_Engineering",
      run = function() if ns.Settings then ns.Settings:Toggle() end end },
    { label = "Recharger", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", macro = "/reload" },
    { label = "Déconnexion", icon = "Interface\\Icons\\INV_Misc_Rune_01", macro = "/logout" },
    { label = "Quitter", icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", macro = "/quit" },
}

local frame

local function Tile(info, index)
    local target = info.click and _G[info.click]
    local tile
    if target or info.macro then
        tile = CreateFrame("Button", "WolkaraMobileMenuTile" .. index, frame, "SecureActionButtonTemplate")
        tile:RegisterForClicks("AnyUp", "AnyDown")
        if target then
            tile:SetAttribute("type", "click")
            tile:SetAttribute("clickbutton", target)
        else
            tile:SetAttribute("type", "macro")
            tile:SetAttribute("macrotext", info.macro)
        end
        tile:SetScript("PostClick", function(_, _, down)
            if not down and not InCombatLockdown() then frame:Hide() end
        end)
    else
        tile = CreateFrame("Button", nil, frame)
        tile:RegisterForClicks("AnyUp")
        tile:SetScript("OnClick", function()
            if not InCombatLockdown() then frame:Hide() end
            ns.Guard(info.label, info.run)
        end)
    end
    tile:SetSize(TILE_W - 8, TILE_H - 8)
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    tile:SetPoint("TOPLEFT", 24 + column * TILE_W, -60 - row * TILE_H)
    ns.Box(tile, "BACKGROUND", 0.1, 0.1, 0.14, 0.95)
    local icon = tile:CreateTexture(nil, "ARTWORK")
    icon:SetSize(60, 60)
    icon:SetPoint("TOP", 0, -10)
    icon:SetTexture(info.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(tile, icon)
    local label = ns.Label(tile, "GameFontHighlight", info.label)
    label:SetPoint("TOP", icon, "BOTTOM", 0, -6)
    label:SetWidth(TILE_W - 14)
    local highlight = ns.Box(tile, "HIGHLIGHT", 1, 1, 1, 0.12)
    highlight:SetBlendMode("ADD")
end

function Menu:IsOpen() return frame ~= nil and frame:IsShown() end

function Menu:Init()
    frame = CreateFrame("Frame", "WolkaraMobileMenu", UIParent, "SecureHandlerBaseTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetAllPoints(UIParent)
    frame:Hide()
    self.frame = frame

    -- Le fond : assombrit le jeu, et un toucher dessus referme le menu.
    local dim = CreateFrame("Button", "WolkaraMobileMenuBackdrop", frame, "SecureHandlerClickTemplate")
    dim:SetAllPoints(frame)
    dim:RegisterForClicks("AnyUp")
    dim:SetFrameRef("menu", frame)
    dim:SetAttribute("_onclick", [=[ self:GetFrameRef("menu"):Hide() ]=])
    ns.Box(dim, "BACKGROUND", 0, 0, 0, 0.55)

    local rows = math.ceil(#TILES / COLUMNS)
    local card = CreateFrame("Frame", nil, frame)
    card:SetSize(COLUMNS * TILE_W + 40, rows * TILE_H + 120)
    card:SetPoint("CENTER")
    card:SetFrameLevel((dim:GetFrameLevel() or 1) + 2)
    card:EnableMouse(true)
    ns.Box(card, "BACKGROUND", 0.04, 0.05, 0.08, 0.97)
    local title = ns.Label(card, "GameFontNormalLarge", "Menu")
    title:SetPoint("TOP", 0, -18)
    frame.card = card

    -- Les tuiles sont sur la carte, au-dessus du fond.
    local parent = frame
    frame = card
    for index, info in ipairs(TILES) do Tile(info, index) end
    frame = parent

    local close = CreateFrame("Button", "WolkaraMobileMenuClose", card, "SecureHandlerClickTemplate")
    close:SetSize(160, 42)
    close:SetPoint("BOTTOM", 0, 14)
    close:RegisterForClicks("AnyUp")
    close:SetFrameRef("menu", frame)
    close:SetAttribute("_onclick", [=[ self:GetFrameRef("menu"):Hide() ]=])
    ns.Box(close, "BACKGROUND", 0.18, 0.18, 0.22, 0.95)
    local closeText = ns.Label(close, "GameFontHighlightLarge", "Fermer")
    closeText:SetPoint("CENTER")
end
