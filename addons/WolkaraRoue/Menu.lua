-- Interface mobile : le menu en grandes tuiles, façon tablette. Tout ce qu'on ouvre moins
-- souvent que les sacs ou la carte : personnage, talents, quêtes, social, guilde, macros,
-- options du jeu, réglages de l'interface mobile, recharger, déconnexion, quitter.
-- Il s'ouvre et se ferme en combat aussi (cadre sécurisé) ; toucher à côté le referme.

local _, ns = ...

local COLUMNS = 5
local TILE_W, TILE_H = 132, 118

local Menu = ns.Register("Menu", {})
ns.Menu = Menu

local tiles = {}

local TILES = {
    { label = "Character", icon = "Interface\\Icons\\INV_Shirt_White_01", click = "CharacterMicroButton",
      run = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
    { label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08",
      run = function() if ToggleAllBags then ToggleAllBags() end end },
    { label = "Spells", icon = "Interface\\Icons\\INV_Misc_Book_09", click = "SpellbookMicroButton",
      run = function() if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end end },
    { label = "Talents", icon = "Interface\\Icons\\Ability_Marksmanship", run = function()
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame()
        elseif ToggleTalentFrame then ToggleTalentFrame()
        elseif _G.TalentMicroButton then _G.TalentMicroButton:Click()
        elseif _G.PlayerSpellsMicroButton then _G.PlayerSpellsMicroButton:Click()
        else ns.Print(ns.T("talents are not available in this version of the game.")) end
    end },
    { label = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing", run = function()
        if ToggleProfessionsBook then ToggleProfessionsBook()
        elseif _G.ProfessionMicroButton then _G.ProfessionMicroButton:Click()
        elseif _G.ProfessionsBookFrame then
            if ProfessionsBookFrame:IsShown() then HideUIPanel(ProfessionsBookFrame) else ShowUIPanel(ProfessionsBookFrame) end
        elseif ToggleSpellBook then ToggleSpellBook(BOOKTYPE_PROFESSION or "professions")
        else ns.Print(ns.T("professions are in the spellbook in this version of the game.")) end
    end },
    { label = "Quests", icon = "Interface\\Icons\\INV_Misc_Note_01", click = "QuestLogMicroButton",
      run = function() if ToggleQuestLog then ToggleQuestLog() end end },
    { label = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01",
      run = function() if ToggleWorldMap then ToggleWorldMap() end end },
    { label = "Social", icon = "Interface\\Icons\\INV_Letter_02", click = "SocialsMicroButton",
      run = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { label = "Guild", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", click = "GuildMicroButton",
      run = function() if ToggleGuildFrame then ToggleGuildFrame() end end },
    { label = "Group Finder", icon = "Interface\\Icons\\INV_Misc_GroupLooking", click = "LFDMicroButton", run = function()
        if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame()
        elseif ToggleLFDParentFrame then ToggleLFDParentFrame()
        else ns.Print(ns.T("the group finder is not available in this version of the game.")) end
    end },
    { label = "Legacy", icon = "Interface\\Icons\\INV_Misc_Book_07", click = "LegacyMicroButton", run = function()
        ns.Print(ns.T("the Legacy page is not available in this version of the game."))
    end },
    { label = "Collections", icon = "Interface\\Icons\\Ability_Mount_RidingHorse", click = "CollectionsMicroButton", run = function()
        if ToggleCollectionsJournal then ToggleCollectionsJournal() end
    end },
    { label = "Macros", icon = "Interface\\Icons\\INV_Scroll_03", macro = "/macro" },
    { label = "Game Menu", icon = "Interface\\Icons\\INV_Misc_Gear_01", run = function()
        if GameMenuFrame then
            if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
        elseif ToggleGameMenu then
            ToggleGameMenu()
        end
    end },
    { label = "Game Settings", icon = "Interface\\Icons\\INV_Misc_Wrench_01", run = function()
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
    { label = "Mobile UI", icon = "Interface\\Icons\\Trade_Engineering",
      run = function() if ns.Settings then ns.Settings:Toggle() end end },
    { label = "Reload", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", macro = "/reload" },
    { label = "Log Out", icon = "Interface\\Icons\\INV_Misc_Rune_01", macro = "/logout" },
    { label = "Quit", icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", macro = "/quit" },
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
            if down then return end
            if ns.menuChoosing then ns.ToggleQuickTile(info.label); return end
            if not InCombatLockdown() then frame:Hide() end
        end)
    else
        tile = CreateFrame("Button", nil, frame)
        tile:RegisterForClicks("AnyUp")
        tile:SetScript("OnClick", function()
            if ns.menuChoosing then ns.ToggleQuickTile(info.label); return end
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
    local label = ns.Label(tile, "GameFontHighlight", ns.T(info.label))
    label:SetPoint("TOP", icon, "BOTTOM", 0, -6)
    label:SetWidth(TILE_W - 14)
    local highlight = ns.Box(tile, "HIGHLIGHT", 1, 1, 1, 0.12)
    highlight:SetBlendMode("ADD")
    tile.check = tile:CreateTexture(nil, "OVERLAY")
    tile.check:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    tile.check:SetSize(30, 30)
    tile.check:SetPoint("TOPRIGHT", -6, -6)
    tile.check:Hide()
    tile.info, tile.secure = info, (target or info.macro) and true or false
    tiles[#tiles + 1] = tile
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
    close:SetPoint("BOTTOMRIGHT", -24, 14)
    close:RegisterForClicks("AnyUp")
    close:SetFrameRef("menu", frame)
    close:SetAttribute("_onclick", [=[ self:GetFrameRef("menu"):Hide() ]=])
    ns.Box(close, "BACKGROUND", 0.18, 0.18, 0.22, 0.95)
    local closeText = ns.Label(close, "GameFontHighlightLarge", ns.T("Close"))
    closeText:SetPoint("CENTER")

    local choose = ns.UIButton(card, ns.T("Choose for quick menu"), 260, 42, function() ns.ChooseQuickMenu(not ns.menuChoosing) end)
    choose:SetPoint("BOTTOMLEFT", 24, 14)
    card.choose = choose
    card.hint = ns.Label(card, "GameFontHighlightSmall", ns.T("Tap tiles to add them to the quick menu or take them out. Menu always comes last."))
    card.hint:SetPoint("TOP", 0, -42)
    card.hint:Hide()
    frame:HookScript("OnHide", function() if ns.menuChoosing then ns.ChooseQuickMenu(false) end end)
end

ns.MenuTiles = TILES

local QUICK_DEFAULT = { "Character", "Professions", "Spells", "Talents", "Social", "Quests", "Guild" }
local QUICK_MAX = 15
function ns.QuickMenuList()
    if not ns.db then return QUICK_DEFAULT end
    if type(ns.db.quickMenu) ~= "table" then
        ns.db.quickMenu = {}
        for i, label in ipairs(QUICK_DEFAULT) do ns.db.quickMenu[i] = label end
    end
    if not ns.db.quickMenuFinderUndone then
        ns.db.quickMenuFinderUndone = true
        for i = #ns.db.quickMenu, 1, -1 do
            if ns.db.quickMenu[i] == "Group Finder" then table.remove(ns.db.quickMenu, i) end
        end
    end
    return ns.db.quickMenu
end

local function ShowChoices()
    local list = ns.QuickMenuList()
    local chosen = {}
    for _, label in ipairs(list) do chosen[label] = true end
    for _, tile in ipairs(tiles) do
        tile.check:SetShown(ns.menuChoosing and chosen[tile.info.label] or false)
        tile:SetAlpha((not ns.menuChoosing or chosen[tile.info.label]) and 1 or 0.45)
    end
end

function ns.ChooseQuickMenu(on)
    if InCombatLockdown() then ns.Print(ns.T("customize out of combat.")); return end
    ns.menuChoosing = on and true or false
    for _, tile in ipairs(tiles) do
        if tile.secure then
            if ns.menuChoosing then
                tile.savedType = tile.savedType or tile:GetAttribute("type")
                tile:SetAttribute("type", nil)
            elseif tile.savedType then
                tile:SetAttribute("type", tile.savedType); tile.savedType = nil
            end
        end
    end
    if frame and frame.card then
        frame.card.choose.text:SetText(ns.menuChoosing and ns.T("Done") or ns.T("Choose for quick menu"))
        frame.card.hint:SetShown(ns.menuChoosing)
    end
    ShowChoices()
    if not ns.menuChoosing then
        if ns.DuoMenuLayout then ns.DuoMenuLayout() end
        if ns.quickMenuChanged then ns.quickMenuChanged = nil; ns.MarkChanged() end
    end
end

function ns.ToggleQuickTile(label)
    if InCombatLockdown() then return end
    local list = ns.QuickMenuList()
    for i, name in ipairs(list) do
        if name == label then table.remove(list, i); ns.quickMenuChanged = true; ShowChoices(); return end
    end
    if #list >= QUICK_MAX then ns.Print(ns.T("the quick menu holds 15 entries, plus Menu.")); return end
    list[#list + 1] = label
    ns.quickMenuChanged = true
    ShowChoices()
end
