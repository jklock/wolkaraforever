-- TouchPlay: the Menu (rule 8, Task 14; mockup 30). The Hud's Menu ring opens it.
--
-- A gold panel, 900 x 640 at (233, 130), with 12 tiles: each shows what is waiting there in a live line
-- (green) and a gold dot. The game's windows open through secure buttons, so a tap works in a fight and
-- nothing here taints the game's windows. This client's own buttons (ActionButtonUtilOverrides.lua):
--   Character   /click CharacterMicroButton      Spellbook  /click PlayerSpellsMicroButton
--   Talents     /click PlayerSpellsMicroButton   (the same window; Spellbook and Talents are its tabs)
--   Quests      /click QuestLogMicroButton       Bags       /click MainMenuBarBackpackButton
--   Professions /click ProfessionMicroButton     Social     /click GuildMicroButton (QuickJoinToastButton is
--               in the same list, but nothing in the game source shows it opens Friends)
--   Map         type "click" on MinimapCluster.ZoneTextButton, the secure path the Hud's minimap uses
-- Every secure button is made while the add-on loads and its attributes are set once; nothing protected
-- changes in a fight.
--
-- Should the game lack the named button, the tile falls back on the game's own Toggle function. That is only
-- allowed out of a fight: the game refuses add-on code to show or hide a UI panel in combat (R32,
-- UIParentPanelManager.lua CheckProtectedFunctionsAllowed). So such a tile is greyed in a fight with "After
-- the fight", does nothing then, and out of a fight the call runs inside pcall: a Blizzard function that is
-- missing or changed never pauses TouchPlay.
--
-- Log out is protected, so our code never calls it. The tile is a secure button with the macro /logout, and
-- Hold.lua puts a hold over it: the hold completes on release after 0.8 s and only unlocks the tile ("Tap to
-- confirm" for 3 s); the player's next real tap runs the secure button (R28, R29). With "Risky actions need a
-- hold" off there is no hold and one tap does it.
--
-- Edit layout says "Coming in a later version". Settings opens Touch settings (Feel.lua); Touch guide shows
-- the guide again (Guide.lua); Save settings is a secure /reload so the game writes the saved variables.
--
-- The panel holds secure tiles, so the game protects it: add-on code cannot show or hide it in a fight. It opens
-- and closes through the secure environment instead (R42): the Hud's Menu ring is wrapped by a secure header that
-- shows the panel and the dim, and the dim, Close, Touch guide and the tiles that open a window hide them from
-- secure snippets. What is drawn on the panel (sub-lines, dots, the Log out hold) follows from ordinary code in
-- the panel's OnShow and OnHide.

local ADDON_NAME, ns = ...

local Menu = ns.Register("Menu", {})
local Kit = ns.Kit

ns.L["menu.title"] = "%s · Level %d %s"
ns.L["menu.character"] = "Character"
ns.L["menu.character.sub"] = "Gear and stats"
ns.L["menu.spellbook"] = "Spellbook"
ns.L["menu.spellbook.sub"] = "All your spells"
ns.L["menu.talents"] = "Talents"
ns.L["menu.talents.none"] = "No points to spend"
ns.L["menu.talents.some"] = "Points to spend"
ns.L["menu.talents.one"] = "1 point to spend"
ns.L["menu.talents.many"] = "%d points to spend"
ns.L["menu.quests"] = "Quests"
ns.L["menu.quests.none"] = "No active quests"
ns.L["menu.quests.active"] = "%d active"
ns.L["menu.quests.ready"] = "%d active · %d ready"
ns.L["menu.map"] = "Map"
ns.L["menu.bags"] = "Bags"
ns.L["menu.bags.sub"] = "%d slots free"
ns.L["menu.professions"] = "Professions"
ns.L["menu.professions.sub"] = "%s %d"
ns.L["menu.professions.none"] = "None learned yet"
ns.L["menu.social"] = "Social"
ns.L["menu.social.sub"] = "Friends, guild, who"
ns.L["menu.chat"] = "Chat"
ns.L["menu.chat.none"] = "Tap to talk"
ns.L["menu.chat.one"] = "1 unread whisper"
ns.L["menu.chat.many"] = "%d unread whispers"
ns.L["menu.editLayout"] = "Edit layout"
ns.L["menu.editLayout.sub"] = "Move and resize"
ns.L["menu.editLayout.later"] = "Coming in a later version"
ns.L["menu.settings"] = "Settings"
ns.L["menu.settings.sub"] = "Game and touch"
ns.L["menu.logout"] = "Log out"
ns.L["menu.logout.sub"] = "Hold to confirm"
ns.L["menu.guide"] = "Touch guide"
ns.L["menu.save"] = "Save settings"

local PANEL_W, PANEL_H, PANEL_X, PANEL_Y = 900, 640, 233, 130
local TILE_W, TILE_H, TILE_GAP_X, TILE_GAP_Y, TILE_X, TILE_Y = 193, 149, 19, 23, 33, 49
local FOOTER_Y, FOOTER_H, FOOTER_W = 580, 44, 189
local LATER_SECONDS = 3
local GOLD, WHITE, GREEN, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 30 / 255, 1, 0 }, { 0.62, 0.62, 0.62 }
local DOT = "Interface\\Common\\Indicator-Yellow"

local Plain = ns.Plain

-- ---------------------------------------------------------------------------------------
-- What each tile does and shows. click: the game's micro button the secure macro clicks; fallback: the game's
-- own Toggle, called from the click when that button is missing.

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local GREYED_ALPHA = 0.45

-- icon: the tile's glyph (our own art, R48; Style.lua Kit.GLYPHS), as the mockup's Menu.
-- click: the game's micro button the secure macro clicks; zone: the Hud's secure click on the zone text
-- button; fallback: the game's own Toggle, used (out of a fight only) when that button is missing.
local TILES = {
    { key = "character", icon = "person", click = "CharacterMicroButton",
      fallback = function() Call("ToggleCharacter", "PaperDollFrame") end },
    { key = "spellbook", icon = "book", click = "PlayerSpellsMicroButton",
      fallback = function() if PlayerSpellsUtil then PlayerSpellsUtil.ToggleSpellBookFrame() end end },
    { key = "talents", icon = "star", click = "PlayerSpellsMicroButton",
      fallback = function() if PlayerSpellsUtil then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() end end },
    { key = "quests", icon = "scroll", click = "QuestLogMicroButton",
      fallback = function() Call("ToggleQuestLog") end },
    { key = "map", icon = "map", zone = true,
      fallback = function() Call("ToggleWorldMap") end },
    { key = "bags", icon = "bag", click = "MainMenuBarBackpackButton",
      fallback = function() Call("ToggleAllBags") end },
    { key = "professions", icon = "hammer", click = "ProfessionMicroButton",
      fallback = function() Call("ToggleProfessionsBook") end },
    { key = "social", icon = "people", click = "GuildMicroButton",
      fallback = function() Call("ToggleFriendsFrame") end },
    { key = "chat", icon = "chat" },
    { key = "editLayout", icon = "layout" },
    { key = "settings", icon = "gear" },
    { key = "logout", icon = "exit", macro = "/logout" },
}
Menu.KEYS = {}
for i, tile in ipairs(TILES) do Menu.KEYS[i] = tile.key end

-- ---------------------------------------------------------------------------------------
-- The panel, the dim behind it, the title

-- The dim behind the panel: a tap on it closes the Menu, from a secure snippet so it works in a fight.
local dim = CreateFrame("Button", "TouchPlayMenuDim", ns.root, "SecureHandlerClickTemplate")
dim:SetAllPoints(ns.root)
dim:SetFrameStrata("DIALOG")
dim:SetFrameLevel(90)
dim:RegisterForClicks("LeftButtonUp")
dim.shade = dim:CreateTexture(nil, "BACKGROUND")
dim.shade:SetAllPoints(dim)
dim.shade:SetColorTexture(0, 0, 0, 0.6)
dim:Hide()
Menu.dim = dim

local panel = Kit.Backdrop(ns.root, "gold", "dark")
panel:SetSize(PANEL_W, PANEL_H)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(100)
panel:EnableMouse(true)
panel:Hide()
ns.Anchor(panel, "TL", PANEL_X, PANEL_Y)
Menu.panel = panel

-- The secure header: it holds the panel and the dim, and its snippets show and hide them (R42).
local CLOSE_BODY = [[ self:GetFrameRef("panel"):Hide(); self:GetFrameRef("dim"):Hide() ]]
dim:SetFrameRef("panel", panel)
dim:SetFrameRef("dim", dim)
dim:SetAttribute("_onclick", CLOSE_BODY)

local header = CreateFrame("Frame", "TouchPlayMenuHeader", ns.root, "SecureHandlerBaseTemplate")
header:SetFrameRef("panel", panel)
header:SetFrameRef("dim", dim)
Menu.header = header

-- A tile that opens a game window (or Settings, Chat, Log out) closes the Menu after its action; it says so in its
-- "tp-closes" attribute, set out of combat. A tile with no secure path closes from ordinary code out of a fight.
local TILE_PRE = [[ if self:GetAttribute("tp-closes") then return nil, true end ]]
local TILE_POST = [[ owner:GetFrameRef("panel"):Hide(); owner:GetFrameRef("dim"):Hide() ]]
local OPEN_PRE = [[ if button == "LeftButton" then owner:GetFrameRef("dim"):Show(); owner:GetFrameRef("panel"):Show() end ]]

local title = Kit.GoldHeader(panel, "")
title:SetPoint("CENTER", panel, "TOP", 0, 0)
title:SetFrameLevel(110)
Menu.title = title

-- ---------------------------------------------------------------------------------------
-- Tiles

local function Text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, Kit.FONT_TITLE, size, "")
    fs:SetJustifyH("LEFT")
    return fs
end

local function Paint(tile, text, color)
    local fs = tile.sub
    if tile.shownSub ~= text then tile.shownSub = text; fs:SetText(text) end
    if tile.shownColor ~= color then
        tile.shownColor = color
        fs:SetTextColor(color[1], color[2], color[3])
    end
end

local function SetDot(tile, on)
    on = on and true or false
    if tile.dot:IsShown() ~= on then tile.dot:SetShown(on) end
end

local later              -- the "Coming in a later version" timer

local function ZoneButton()
    local cluster = _G.MinimapCluster
    local button = cluster and cluster.ZoneTextButton
    return type(button) == "table" and button or nil
end

-- Has the secure path this tile names (the game's button is there)?
local function HasSecurePath(tile)
    if tile.zone then return ZoneButton() ~= nil end
    return tile.click == nil or _G[tile.click] ~= nil
end

-- A fallback tile cannot work in a fight: the game refuses add-on code to show a panel then.
local function GreyedNow(tile)
    return tile.fallback ~= nil and not HasSecurePath(tile) and ns.InFight()
end

local function OnTile(tile)
    if tile.fallback and not HasSecurePath(tile) then
        if ns.InFight() then return end              -- greyed: nothing to do until the fight ends
        pcall(tile.fallback)                         -- a Blizzard function that is missing or changed is no reason to pause
    end
    if tile.key == "editLayout" then
        if later then later:Cancel() end
        Paint(tile, ns.T("menu.editLayout.later"), GOLD)
        later = C_Timer.NewTimer(LATER_SECONDS, function()
            later = nil
            Menu.Refresh()
        end)
        return
    end
    Menu.Close()
    if tile.key == "settings" then
        if ns.Feel then ns.Feel.Open() end
    elseif tile.key == "chat" then
        if ns.Chat and ns.Chat.Open then ns.Chat.Open() end
    end
end

-- The map tile: a secure click on the zone text button, the way the Hud's minimap does it.
local function ApplyZone(tile)
    local toggle = ZoneButton()
    if not toggle or tile:GetAttribute("clickbutton") == toggle then return end
    tile:SetAttribute("clickbutton", toggle)
    tile:SetAttribute("type", "click")
end

-- Whether a tap on the tile closes the Menu from its secure snippet (out of combat only: an attribute).
local function ApplyCloses(tile)
    local closes = tile.key ~= "editLayout" and HasSecurePath(tile) or nil
    if tile:GetAttribute("tp-closes") ~= closes then tile:SetAttribute("tp-closes", closes) end
end

Menu.tiles = {}
for i, def in ipairs(TILES) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local tile = CreateFrame("Button", "TouchPlayMenuTile" .. def.key, panel, "SecureActionButtonTemplate")
    tile:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    tile:SetSize(TILE_W, TILE_H)
    tile:SetPoint("TOPLEFT", panel, "TOPLEFT", TILE_X + col * (TILE_W + TILE_GAP_X), -(TILE_Y + row * (TILE_H + TILE_GAP_Y)))
    tile:RegisterForClicks("LeftButtonUp")
    tile.key, tile.fallback, tile.click, tile.zone = def.key, def.fallback, def.click, def.zone
    -- the secure part, set once: the game's own button is clicked from the macro
    if def.zone then
        ApplyZone(tile)
    elseif def.click then
        tile:SetAttribute("type", "macro")
        tile:SetAttribute("macrotext", "/click " .. def.click)
    end
    if def.macro then
        tile:SetAttribute("type", "macro")
        tile:SetAttribute("macrotext", def.macro)
    end
    ApplyCloses(tile)
    header:WrapScript(tile, "OnClick", TILE_PRE, TILE_POST)
    Kit.FitHit(tile)

    local face = Kit.Backdrop(tile, "tooltip", "tooltip")
    face:SetAllPoints(tile)
    face:EnableMouse(false)
    tile.face = face
    tile.icon = face:CreateTexture(nil, "ARTWORK")
    Kit.SetGlyph(tile.icon, def.icon)
    tile.icon:SetSize(44, 44)
    tile.icon:SetPoint("TOPLEFT", face, "TOPLEFT", 16, -16)
    tile.title = Text(face, 24)
    tile.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    tile.title:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 16, 50)
    tile.title:SetText(ns.T("menu." .. def.key))
    tile.sub = Text(face, 18)
    tile.sub:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 16, 22)
    tile.dot = face:CreateTexture(nil, "OVERLAY")
    tile.dot:SetTexture(DOT)
    tile.dot:SetSize(22, 22)
    tile.dot:SetPoint("TOPRIGHT", face, "TOPRIGHT", -14, -14)
    tile.dot:Hide()
    Kit.AddPress(tile, "rect", face, 2)      -- pressed: the pale-gold edge, then a short fade (polish pass)
    tile:HookScript("PostClick", function(self, mouse)
        Kit.Sound("tap")
        ns.Guard("menu tile", OnTile, self)
    end)
    Menu.tiles[def.key] = tile
end

-- ---------------------------------------------------------------------------------------
-- The live lines

local function Quests()
    local log = C_QuestLog
    local active, ready = 0, 0
    if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return 0, 0 end
    for i = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(i)
        if info and not info.isHeader then
            active = active + 1
            if log.IsComplete and log.IsComplete(info.questID) and not (log.IsFailed and log.IsFailed(info.questID)) then
                ready = ready + 1
            end
        end
    end
    return active, ready
end

-- (points waiting, how many when the game says): a count when the game gives one.
local function Talents()
    if GetUnspentTalentPoints then
        local ok, points = pcall(GetUnspentTalentPoints)
        if ok and type(points) == "number" and Plain(points) and points > 0 then return true, points end
    end
    local waiting = ns.Hud and ns.Hud.TalentWaiting and ns.Hud.TalentWaiting()
    return waiting and true or false, nil
end

local function FreeSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n = C_Container and C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(bag)
        if type(n) == "number" and Plain(n) then free = free + n end
    end
    return free
end

-- The best profession: its name and skill.
local function Profession()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local best, bestRank
    local list = { GetProfessions() }
    for i = 1, 5 do
        local index = list[i]
        if index then
            local name, _, rank = GetProfessionInfo(index)
            if type(name) == "string" and type(rank) == "number" and (not bestRank or rank > bestRank) then
                best, bestRank = name, rank
            end
        end
    end
    return best, bestRank
end

local function Zone()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
    if type(zone) == "string" and Plain(zone) then return zone end
    return ""
end

local function Whispers()
    return ns.Chat and ns.Chat.Unread and ns.Chat.Unread() or 0
end

local function RefreshTitle()
    local name, level = UnitName("player"), UnitLevel("player")
    local class = UnitClass and UnitClass("player") or ""
    if type(level) ~= "number" or not Plain(level) then level = 0 end
    local text = ns.T("menu.title", tostring(name or ""), level, tostring(class or ""))
    if Menu.shownTitle ~= text then Menu.shownTitle = text; title:SetLabel(text) end
end

function Menu.Refresh()
    local tiles = Menu.tiles
    RefreshTitle()
    Paint(tiles.character, ns.T("menu.character.sub"), WHITE)
    Paint(tiles.spellbook, ns.T("menu.spellbook.sub"), WHITE)
    local waiting, points = Talents()
    if not waiting then
        Paint(tiles.talents, ns.T("menu.talents.none"), WHITE)
    elseif not points then
        Paint(tiles.talents, ns.T("menu.talents.some"), GREEN)
    else
        Paint(tiles.talents, points == 1 and ns.T("menu.talents.one") or ns.T("menu.talents.many", points), GREEN)
    end
    SetDot(tiles.talents, waiting)
    local active, ready = Quests()
    if active == 0 then
        Paint(tiles.quests, ns.T("menu.quests.none"), WHITE)
    elseif ready > 0 then
        Paint(tiles.quests, ns.T("menu.quests.ready", active, ready), GREEN)
    else
        Paint(tiles.quests, ns.T("menu.quests.active", active), WHITE)
    end
    SetDot(tiles.quests, ready > 0)
    Paint(tiles.map, Zone(), WHITE)
    Paint(tiles.bags, ns.T("menu.bags.sub", FreeSlots()), WHITE)
    local profession, rank = Profession()
    if profession then
        Paint(tiles.professions, ns.T("menu.professions.sub", profession, rank), WHITE)
    else
        Paint(tiles.professions, ns.T("menu.professions.none"), WHITE)
    end
    Paint(tiles.social, ns.T("menu.social.sub"), WHITE)
    local whispers = Whispers()
    if whispers == 0 then
        Paint(tiles.chat, ns.T("menu.chat.none"), WHITE)
    elseif whispers == 1 then
        Paint(tiles.chat, ns.T("menu.chat.one"), GREEN)
    else
        Paint(tiles.chat, ns.T("menu.chat.many", whispers), GREEN)
    end
    SetDot(tiles.chat, whispers > 0)
    if not later then Paint(tiles.editLayout, ns.T("menu.editLayout.sub"), WHITE) end
    Paint(tiles.settings, ns.T("menu.settings.sub"), WHITE)
    Paint(tiles.logout, ns.T("menu.logout.sub"), WHITE)
    -- a tile with no secure path is greyed in a fight, and says when it works again
    for _, tile in pairs(tiles) do
        local off = GreyedNow(tile)
        if off then Paint(tile, ns.T("common.afterFight"), GREY) end
        local alpha = off and GREYED_ALPHA or 1
        if tile.face:GetAlpha() ~= alpha then tile.face:SetAlpha(alpha) end
    end
end

local function OnChange()
    if panel:IsShown() then Menu.Refresh() end
end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "BAG_UPDATE_DELAYED", "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, OnChange)
end

-- ---------------------------------------------------------------------------------------
-- The footer

local function Footer(label, x, onClick)
    local b = Kit.RedButton(panel, FOOTER_W, FOOTER_H, label)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -FOOTER_Y)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- The red button is the picture; this secure button over it closes the Menu from a snippet, so it works in a fight.
local function SecureClose(over, name, after)
    local b = CreateFrame("Button", name, panel, "SecureHandlerClickTemplate")
    b:SetAllPoints(over)
    b:SetFrameLevel(over:GetFrameLevel() + 2)
    b:RegisterForClicks("AnyUp")
    b:SetFrameRef("panel", panel)
    b:SetFrameRef("dim", dim)
    b:SetAttribute("_onclick", CLOSE_BODY)
    b:HookScript("PostClick", function()
        Kit.Sound("tap")
        if after then ns.Guard("menu footer", after) end
    end)
    over.secure = b
    Kit.AddPress(b, "rect", over)            -- the red button's own press look, lit by the secure button
    return b
end

local function ShowGuide()
    if ns.Guide then ns.Guide.Show(true) end
end

Menu.guideButton = Footer(ns.T("menu.guide"), 36, function()
    Menu.Close()
    ShowGuide()
end)
SecureClose(Menu.guideButton, "TouchPlayMenuGuide", ShowGuide)

Menu.saveButton = Footer(ns.T("menu.save"), 247)
-- the red button is the picture; this secure button over it does the /reload
local reload = CreateFrame("Button", "TouchPlayMenuReload", panel, "SecureActionButtonTemplate")
reload:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
reload:SetAllPoints(Menu.saveButton)
reload:SetFrameLevel(Menu.saveButton:GetFrameLevel() + 2)
reload:RegisterForClicks("AnyUp")
reload:SetAttribute("type", "macro")
reload:SetAttribute("macrotext", "/reload")
Menu.saveButton.secure = reload
Kit.AddPress(reload, "rect", Menu.saveButton)

Menu.closeButton = Footer(ns.T("common.close"), 676, function() Menu.Close() end)
SecureClose(Menu.closeButton, "TouchPlayMenuClose")

-- ---------------------------------------------------------------------------------------
-- Open and close

function Menu.IsOpen() return panel:IsShown() end

-- A new visit starts locked: the hold goes back over Log out (R28).
local function PutHold()
    local logout = Menu.tiles.logout
    ns.Hold.Release(logout)
    ns.Hold.Button(logout, ns.Hold.SECONDS, nil, { arm = true, parent = panel, key = "logout" })
end

-- Whoever showed or hid the panel (a secure snippet or the calls below), what is drawn on it follows here. Only
-- plain frames and text change, so this is safe in a fight.
panel:HookScript("OnShow", function()
    ns.Guard("menu open", function()
        Menu.Refresh()
        PutHold()
        Kit.Sound("open")
    end)
end)
panel:HookScript("OnHide", function()
    ns.Guard("menu close", function()
        ns.Hold.Release(Menu.tiles.logout)
        Kit.Sound("close")
    end)
end)

-- Opens the Menu from ordinary code. Out of a fight it shows the panel; in a fight only the secure Menu ring can
-- (the panel is protected), so this only redraws an open one.
function Menu.Open()
    if panel:IsShown() then Menu.Refresh(); return end
    if InCombatLockdown() then return end
    dim:Show()
    panel:Show()
end

-- Closes the Menu from ordinary code: out of a fight only (in a fight the secure dim, Close and tiles close it).
function Menu.Close()
    if not panel:IsShown() or InCombatLockdown() then return end
    panel:Hide()
    dim:Hide()
end

-- The Hud's Menu ring (Hud.lua makes it, with no secure action of its own) opens the Menu from the header. Set up
-- while the add-on loads, as every secure part is.
if ns.Hud and ns.Hud.menu then header:WrapScript(ns.Hud.menu, "OnClick", OPEN_PRE) end

-- ---------------------------------------------------------------------------------------
-- Module steps

function Menu:Layout()
    ns.Anchor(panel, "TL", PANEL_X, PANEL_Y)
    ns.Queue("menu map", function()       -- if the game's button came later
        ApplyZone(Menu.tiles.map)
        for _, tile in pairs(Menu.tiles) do ApplyCloses(tile) end
    end)
end

function Menu:Restore() Menu.Close() end
