-- Interface mobile : le chat, refait comme une messagerie de téléphone.
--
-- Le chat du jeu disparaît ; ne reste que sa zone de saisie, invisible tant qu'on n'écrit pas,
-- qui sert de passage pour envoyer. À sa place, en bas au centre, entre les deux roues :
--   * un fil des derniers messages, qui s'effacent seuls. Au-dessus, deux onglets passent d'un
--     toucher de la discussion (les joueurs) au système (butin, expérience, compétences), et le
--     nombre de messages privés non lus s'affiche à droite. Toucher le fil l'ouvre en grand ;
--   * ouvert, le même chat en grand, posé au même endroit : onglets Discussion, Privé, Système
--     et Tout, flèches pour remonter, et en bas le choix de la conversation : Dire, Groupe,
--     Guilde, Général ou Répondre. Toucher le nom d'un joueur choisit de lui écrire en privé.
-- Tout se dimensionne sur la place entre les deux sticks : rien ne déborde ni ne se chevauche.
-- Pour écrire : le bouton clavier de la barre de l'app, juste sous le chat. Entrée envoie à la
-- conversation choisie, Dire par défaut, parce que l'app appuie d'abord sur F12, que ce module
-- relie à « ouvrir la saisie sur la conversation choisie ». Une commande (/…) passe par la
-- touche / du jeu, sans conversation.
-- « Masquer », à droite des onglets rapides, range le chat dans un bouton posé juste à gauche
-- du clavier de la barre de l'app : il compte ce que les joueurs disent entre-temps, et le
-- toucher rouvre le fil. Écrire reste possible chat masqué.

local _, ns = ...

local Chat = ns.Register("Chat", {})
ns.Chat = Chat
local MAX_MESSAGES = 300
local LINES = 3          -- dans le fil
local OPEN_KEY = "F12"
local PAD, GAP, ROW, HINT, ARROW, QUICK_H = 8, 6, 36, 20, 44, 28
local BOTTOM = 0.12      -- en hauteur d'écran : sous le chat, la barre de l'app
local STRIP = 0.36       -- en largeur d'écran : le fil, entre les sorts les plus bas des roues
local HIDE_W = 84        -- le bouton Masquer
-- La barre de l'app repliée, mesurée sur l'iPhone Duo (2026-11-06) : 96 x 34 pt au centre d'un
-- écran de 669 pt de haut, à 42 pt du bas, son clavier à gauche. Le chat masqué devient un
-- bouton de 44 x 34 pt, 8 pt à gauche de ce clavier, à sa hauteur. En hauteur d'écran :
local BAR_HALF, BAR_BOTTOM, BAR_HEIGHT, BAR_GAP, MINI_WIDTH = 48 / 669, 42 / 669, 34 / 669, 8 / 669, 44 / 669

local messages = {}
local target = { kind = "say" }
local lastWhisper
local unread = 0
local pending = 0        -- ce que les joueurs ont dit depuis que le chat est masqué
local ticker, panel, list, tabButtons, quick, chips, to, hint, badge, opener, close, arrows, holder
local hideButton, mini, miniCount
local hider = CreateFrame("Frame")
hider:Hide()

local TABS = {
    { key = "talk", label = "Discussion" }, { key = "whisper", label = "Privé" },
    { key = "system", label = "Système" }, { key = "all", label = "Tout" },
}
local QUICK = { { key = "talk", label = "Discussion" }, { key = "system", label = "Système" } }
local KNOWN = { talk = true, whisper = true, system = true, all = true }

-- Ce que chaque message du jeu devient : son étiquette et ses onglets.
local TALK = { all = true, talk = true }
local PRIVATE = { all = true, talk = true, whisper = true }
local NPC = { all = true }
local SYSTEM = { system = true }
local EVENTS = {
    CHAT_MSG_SAY = { label = "Dire", tabs = TALK },
    CHAT_MSG_YELL = { label = "Crier", tabs = TALK },
    CHAT_MSG_EMOTE = { emote = true, tabs = TALK },
    CHAT_MSG_TEXT_EMOTE = { raw = true, tabs = TALK },
    CHAT_MSG_PARTY = { label = "Groupe", tabs = TALK },
    CHAT_MSG_PARTY_LEADER = { label = "Chef", tabs = TALK },
    CHAT_MSG_RAID = { label = "Raid", tabs = TALK },
    CHAT_MSG_RAID_LEADER = { label = "Chef de raid", tabs = TALK },
    CHAT_MSG_RAID_WARNING = { label = "Alerte", tabs = TALK },
    CHAT_MSG_INSTANCE_CHAT = { label = "Instance", tabs = TALK },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { label = "Instance", tabs = TALK },
    CHAT_MSG_GUILD = { label = "Guilde", tabs = TALK },
    CHAT_MSG_OFFICER = { label = "Officier", tabs = TALK },
    CHAT_MSG_WHISPER = { label = "De", tabs = PRIVATE, incoming = true },
    CHAT_MSG_WHISPER_INFORM = { label = "À", tabs = PRIVATE },
    CHAT_MSG_CHANNEL = { channel = true, tabs = TALK },
    CHAT_MSG_MONSTER_SAY = { label = "Dit", tabs = NPC },
    CHAT_MSG_MONSTER_YELL = { label = "Crie", tabs = NPC },
    CHAT_MSG_MONSTER_WHISPER = { label = "Murmure", tabs = NPC },
    CHAT_MSG_MONSTER_EMOTE = { emote = true, tabs = NPC },
    CHAT_MSG_SYSTEM = { raw = true, tabs = { all = true, system = true } },
    CHAT_MSG_LOOT = { raw = true, tabs = SYSTEM },
    CHAT_MSG_MONEY = { raw = true, tabs = SYSTEM },
    CHAT_MSG_COMBAT_XP_GAIN = { raw = true, tabs = SYSTEM },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { raw = true, tabs = SYSTEM },
    CHAT_MSG_SKILL = { raw = true, tabs = SYSTEM },
}

local TARGETS = {
    { kind = "say", label = "Dire" }, { kind = "party", label = "Groupe" }, { kind = "guild", label = "Guilde" },
    { kind = "general", label = "Général" }, { kind = "whisper", label = "Répondre" },
}

local WRITE = "Pour écrire, touche le clavier juste sous le chat ; Entrée envoie."

-- ---------------------------------------------------------------------------------------
-- Messages

local function Tab()
    local tab = ns.db and ns.db.chat.tab
    return KNOWN[tab] and tab or "talk"
end

local function Color(event, channelIndex)
    local key = event:sub(10)
    if key == "CHANNEL" and channelIndex then key = "CHANNEL" .. channelIndex end
    local info = ChatTypeInfo and (ChatTypeInfo[key] or ChatTypeInfo[event:sub(10)])
    if info then return info.r or 1, info.g or 1, info.b or 1 end
    return 1, 1, 1
end

local function PlayerLink(name)
    if not name or name == "" then return "" end
    local short = Ambiguate and Ambiguate(name, "short") or name
    return ("|Hplayer:%s|h%s|h"):format(name, short)
end

local function Short(name) return Ambiguate and Ambiguate(name, "short") or name end

local function Format(info, text, author, channelIndex, channelBase)
    local stamp = date and date("%H:%M ") or ""
    if info.raw then return stamp .. text end
    if info.emote then return stamp .. PlayerLink(author) .. " " .. text end
    local label = info.label
    if info.channel then
        label = (channelIndex and (channelIndex .. ". ") or "") .. (channelBase ~= "" and channelBase or "Canal")
    end
    return ("%s[%s] %s : %s"):format(stamp, label, PlayerLink(author), text)
end

local function Shows(entry) return entry.tabs[Tab()] end

local function Store(entry)
    messages[#messages + 1] = entry
    if #messages > MAX_MESSAGES then table.remove(messages, 1) end
    if not Shows(entry) then return end
    if panel and panel:IsShown() then list:AddMessage(entry.line, entry.r, entry.g, entry.b) end
    if ticker then ticker:AddMessage(entry.line, entry.r, entry.g, entry.b) end
end

local UpdateChips

local function Add(event, text, author, _, _, _, _, _, channelIndex, channelBase)
    local info = EVENTS[event]
    if not info or type(text) ~= "string" then return end
    local r, g, b = Color(event, channelIndex)
    if info.incoming and author then
        lastWhisper = author
        if not (panel and panel:IsShown() and Tab() == "whisper") then unread = unread + 1 end
    end
    Store({ line = Format(info, text, author, channelIndex, channelBase), r = r, g = g, b = b, tabs = info.tabs })
    if badge then Chat:UpdateBadge() end
    if info.incoming and UpdateChips then UpdateChips() end
    if mini and info.tabs.talk and ns.db and ns.db.chat.hidden then
        pending = pending + 1
        Chat:UpdateMini()
    end
end

-- Le panneau reprend tout l'onglet ; le fil, ses derniers messages, qui s'effacent comme les autres.
local function Rebuild()
    if panel:IsShown() then
        list:Clear()
        for _, entry in ipairs(messages) do
            if Shows(entry) then list:AddMessage(entry.line, entry.r, entry.g, entry.b) end
        end
        list:ScrollToBottom()
    end
    ticker:Clear()
    local recent = {}
    for i = #messages, 1, -1 do
        if Shows(messages[i]) then
            recent[#recent + 1] = messages[i]
            if #recent == LINES then break end
        end
    end
    for i = #recent, 1, -1 do ticker:AddMessage(recent[i].line, recent[i].r, recent[i].g, recent[i].b) end
end

-- ---------------------------------------------------------------------------------------
-- Envoyer : la conversation choisie devient le début de la ligne dans la saisie du jeu.

local function Prefix()
    if target.kind == "say" then return "/s " end
    if target.kind == "party" then return (IsInRaid and IsInRaid()) and "/raid " or "/p " end
    if target.kind == "guild" then return "/g " end
    if target.kind == "general" then return "/1 " end
    if target.kind == "whisper" then
        local name = target.name or lastWhisper
        if name then return "/w " .. name .. " " end
    end
    return ""
end
Chat.Prefix = Prefix

local function OpenInput()
    if ChatFrame_OpenChat then ChatFrame_OpenChat(Prefix(), DEFAULT_CHAT_FRAME) end
end

local function Paint(button, selected)
    button.back:SetVertexColor(selected and 0.85 or 0.18, selected and 0.68 or 0.18, selected and 0.3 or 0.22, 0.95)
end

function UpdateChips()
    if not chips then return end
    for _, chip in ipairs(chips) do
        if chip.kind == "whisper" then
            local name = target.name or lastWhisper
            chip.text:SetText(name and ("À " .. Short(name)) or "Répondre")
        end
        Paint(chip, chip.kind == target.kind)
    end
end

local function UpdateTabs()
    local tab = Tab()
    for _, button in ipairs(tabButtons) do Paint(button, button.key == tab) end
    for _, button in ipairs(quick) do Paint(button, button.key == tab) end
end

local function SetTab(key)
    ns.db.chat.tab = key
    if key == "whisper" then unread = 0 end
    Chat:UpdateBadge()
    UpdateTabs()
    Rebuild()
end
Chat.SetTab = SetTab

-- ---------------------------------------------------------------------------------------
-- Le chat du jeu : rangé, sauf sa saisie, posée sur le fil et invisible tant qu'on n'écrit pas.

local moved = {}
local function GameChat()
    local frames = {}
    local function add(frame) if frame then frames[#frames + 1] = frame end end
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
            "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }) do
        add(_G[name])
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        add(_G["ChatFrame" .. i])
        add(_G["ChatFrame" .. i .. "Tab"])
        add(_G["ChatFrame" .. i .. "ButtonFrame"])
    end
    return frames
end

local function GameBox() return (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox end

-- La saisie ne se montre que pendant qu'on écrit. Son cadre porteur est à nous : le jeu règle la
-- transparence de la saisie elle-même (style de chat « classique »), pas celle du porteur.
local function ShowBox(on) holder:SetAlpha(on and 1 or 0) end

local boxParent, boxHooked
local function TuckGameChat(on)
    local box = GameBox()
    if on then
        for _, frame in ipairs(GameChat()) do
            if frame:GetParent() ~= hider then
                moved[frame] = frame:GetParent() or UIParent
                frame:SetParent(hider)
            end
        end
        if box then
            if not boxParent then boxParent = box:GetParent() or UIParent end
            if not boxHooked then
                boxHooked = true
                box:HookScript("OnEditFocusGained", function() ShowBox(true) end)
                box:HookScript("OnEditFocusLost", function() ShowBox(false) end)
            end
            box:SetParent(holder)
            box:SetFrameStrata("FULLSCREEN_DIALOG")
            box:EnableMouse(false)
            box:ClearAllPoints()
            box:SetPoint("BOTTOMLEFT", ticker, "BOTTOMLEFT", 0, 0)
            box:SetPoint("BOTTOMRIGHT", ticker, "BOTTOMRIGHT", 0, 0)
            ShowBox(box.HasFocus and box:HasFocus())
        end
    else
        for frame, parent in pairs(moved) do
            frame:SetParent(parent)
            moved[frame] = nil
        end
        if box and boxParent then
            box:SetParent(boxParent)
            box:EnableMouse(true)
            boxParent = nil
            if FCF_DockUpdate then pcall(FCF_DockUpdate) end
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- Interface

local function SetFont(frame, size)
    local font, _, flags = (ChatFontNormal or GameFontNormal):GetFont()
    if font then frame:SetFont(font, size, flags) end
end

-- Une rangée de boutons de même largeur, de x à x + width, sans jamais dépasser : un texte trop
-- long se coupe au lieu de déborder sur le voisin.
local function Row(parent, buttons, anchor, x, y, width, height)
    local each = (width - GAP * (#buttons - 1)) / #buttons
    for i, button in ipairs(buttons) do
        button:SetSize(each, height)
        button:ClearAllPoints()
        button:SetPoint(anchor, parent, anchor, x + (i - 1) * (each + GAP), y)
        button.text:SetWidth(math.max(1, each - 8))
        if button.text.SetWordWrap then button.text:SetWordWrap(false) end
    end
    return each
end
Chat.Row = Row

local function ArrowButton(parent, texture, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ARROW, ARROW)
    button:SetNormalTexture(texture .. "-Up")
    button:SetPushedTexture(texture .. "-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

-- Ce qui se voit : le fil, ou le panneau ouvert, ou, chat masqué, son bouton près du clavier.
-- Le mode Personnaliser montre toujours le fil, pour qu'on puisse le déplacer.
local function Arrange()
    local settings = ns.db.chat
    if not settings.custom then
        ticker:Hide(); panel:Hide(); mini:Hide()
        return
    end
    if settings.hidden and not ns.editing then
        panel:Hide(); ticker:Hide(); mini:Show()
    else
        mini:Hide()
        if not panel:IsShown() then ticker:Show() end
    end
    Chat:UpdateMini()
end

local function Open()
    if ns.editing then return end
    panel:Show()
    ticker:Hide()
    if Tab() == "whisper" then unread = 0 end
    Chat:UpdateBadge()
    Rebuild()
    UpdateChips()
end

local function Close()
    panel:Hide()
    Arrange()
    Rebuild()
end
Chat.Open, Chat.Close = Open, Close

-- Comme l'onglet, l'état masqué est retenu au prochain enregistrement, sans en provoquer un :
-- recharger l'interface pour si peu se verrait plus que le chat.
local function SetHidden(on)
    ns.db.chat.hidden = on and true or false
    pending = 0
    Arrange()
    if not on then Rebuild() end
end
Chat.SetHidden = SetHidden

function Chat:UpdateBadge()
    badge:SetText(unread > 0 and (unread .. (unread == 1 and " nouveau privé" or " nouveaux privés")) or "")
end

function Chat:UpdateMini()
    if not miniCount then return end
    miniCount:SetText(pending > 99 and "99+" or pending > 0 and tostring(pending) or "")
end

-- Le panneau ouvert : onglets et croix en haut, messages et flèches au milieu, conversation en bas.
local function LayoutPanel(width, height)
    panel:SetSize(width, height)
    close:SetSize(ARROW, ROW)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
    Row(panel, tabButtons, "TOPLEFT", PAD, -PAD, width - 2 * PAD - ARROW - GAP, ROW)

    to:ClearAllPoints()
    to:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + ROW / 2)
    local label = (to:GetStringWidth() or 30) + GAP
    Row(panel, chips, "BOTTOMLEFT", PAD + label, PAD, width - 2 * PAD - label, ROW)
    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD + ROW + 4)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + ROW + 4)

    local top = PAD + ROW + GAP
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(PAD + ARROW + GAP), PAD + ROW + 4 + HINT + GAP)
    for i, arrow in ipairs(arrows) do
        arrow:ClearAllPoints()
        arrow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(top + (i - 1) * (ARROW + GAP)))
    end
end

-- Au-dessus du fil : les deux onglets rapides à gauche, Masquer à droite, et au-dessus de lui
-- les privés non lus.
local function LayoutStrip(width)
    Row(ticker, quick, "TOPLEFT", 0, QUICK_H + 4, width * 0.6 - GAP, QUICK_H)
    local hideWidth = math.min(HIDE_W, width * 0.4 - GAP)
    hideButton:SetSize(hideWidth, QUICK_H)
    hideButton.text:SetWidth(math.max(1, hideWidth - 8))
    hideButton:ClearAllPoints()
    hideButton:SetPoint("TOPRIGHT", ticker, "TOPRIGHT", 0, QUICK_H + 4)
    badge:ClearAllPoints()
    badge:SetPoint("BOTTOMRIGHT", hideButton, "TOPRIGHT", 0, 4)
end

-- Le chat masqué : son bouton, juste à gauche du clavier de la barre de l'app.
local function LayoutMini(height)
    local size = height * BAR_HEIGHT
    mini:SetSize(height * MINI_WIDTH, size)
    mini:ClearAllPoints()
    mini:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -height * (BAR_HALF + BAR_GAP), height * BAR_BOTTOM)
    mini.icon:SetSize(size * 0.8, size * 0.8)
end

function Chat:Init()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("FULLSCREEN_DIALOG")
    holder:SetAllPoints(UIParent)
    holder:EnableMouse(false)
    holder:SetAlpha(0)

    -- Le fil : les derniers messages de l'onglet, discrets, qui s'effacent seuls.
    ticker = CreateFrame("ScrollingMessageFrame", "WolkaraMobileChatTicker", UIParent)
    ticker:SetFrameStrata("LOW")
    ticker:SetJustifyH("LEFT")
    ticker:SetMaxLines(40)
    ticker:SetFading(true)
    ticker:SetTimeVisible(20)
    if ticker.SetHyperlinksEnabled then ticker:SetHyperlinksEnabled(false) end
    ticker:EnableMouse(true)
    ticker:SetScript("OnMouseUp", function() Open() end)
    ticker.back = ns.Box(ticker, "BACKGROUND", 0, 0, 0, 0.25)
    ticker.glow = ns.EditFrame(ticker)
    quick = {}
    for i, info in ipairs(QUICK) do
        local button = ns.UIButton(ticker, info.label, 100, QUICK_H, function() SetTab(info.key) end)
        button.text:SetFontObject("GameFontHighlight")
        button.key = info.key
        quick[i] = button
    end
    hideButton = ns.UIButton(ticker, "Masquer", HIDE_W, QUICK_H, function() SetHidden(true) end)
    hideButton.text:SetFontObject("GameFontHighlight")
    if hideButton.text.SetWordWrap then hideButton.text:SetWordWrap(false) end
    badge = ns.Label(ticker, "GameFontNormal")
    badge:SetTextColor(1, 0.5, 1)
    ns.Movable(ticker, function() return ns.db.chat end, "pos",
        function() return { "BOTTOM", "BOTTOM", 0, UIParent:GetHeight() * BOTTOM } end)

    -- Le chat masqué : une bulle, et en rose ce qui a été dit depuis.
    mini = ns.UIButton(UIParent, "", 44, 34, function() SetHidden(false) end)
    mini:SetFrameStrata("LOW")
    mini.back:SetVertexColor(0.05, 0.05, 0.08, 0.7)
    mini.icon = mini:CreateTexture(nil, "ARTWORK")
    mini.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    mini.icon:SetPoint("CENTER")
    miniCount = ns.Label(mini, "GameFontNormal")
    miniCount:SetTextColor(1, 0.5, 1)
    miniCount:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -2, -2)
    mini:Hide()
    Chat.mini = mini

    -- Le panneau ouvert, posé sur le fil.
    panel = CreateFrame("Frame", "WolkaraMobileChat", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("BOTTOM", ticker, "BOTTOM", 0, 0)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.03, 0.04, 0.07, 0.92)

    tabButtons = {}
    for i, info in ipairs(TABS) do
        local button = ns.UIButton(panel, info.label, 90, ROW, function() SetTab(info.key) end)
        button.key = info.key
        tabButtons[i] = button
    end
    close = ns.UIButton(panel, "X", ARROW, ROW, Close)

    list = CreateFrame("ScrollingMessageFrame", "WolkaraMobileChatList", panel)
    list:SetJustifyH("LEFT")
    list:SetMaxLines(MAX_MESSAGES)
    list:SetFading(false)
    list:EnableMouse(true)
    if list.SetHyperlinksEnabled then list:SetHyperlinksEnabled(true) end
    list:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local name = link:match("^player:([^:]+)")
        if name then
            target = { kind = "whisper", name = name }
            UpdateChips()
            hint:SetText("Message privé à " .. Short(name) .. " : touche le clavier juste sous le chat.")
        elseif SetItemRef then
            SetItemRef(link, text, button, self)
        end
    end)

    arrows = {
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", function()
            for _ = 1, 3 do list:ScrollUp() end
        end),
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", function()
            for _ = 1, 3 do list:ScrollDown() end
        end),
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd", function() list:ScrollToBottom() end),
    }

    to = ns.Label(panel, "GameFontNormal", "À :")
    chips = {}
    for i, info in ipairs(TARGETS) do
        local chip = ns.UIButton(panel, info.label, 100, ROW, function()
            target = { kind = info.kind }
            if info.kind == "whisper" then target.name = lastWhisper end
            UpdateChips()
            hint:SetText(WRITE)
        end)
        chip.kind = info.kind
        chips[i] = chip
    end
    hint = ns.Label(panel, "GameFontHighlightSmall", WRITE)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(false) end

    -- F12 : la touche que l'app envoie avant un message.
    opener = CreateFrame("Button", "WolkaraMobileChatOpener", UIParent)
    opener:SetScript("OnClick", function() ns.Guard("ouvrir la saisie", OpenInput) end)

    -- Les messages de l'addon, quand le chat du jeu est rangé : rares et utiles, ils passent dans
    -- les deux onglets rapides.
    ns.ChatAdd = function(line)
        if not ns.db or not ns.db.chat.custom then return false end
        Store({ line = line, r = 1, g = 1, b = 1, tabs = { all = true, system = true, talk = true } })
        return true
    end
end

function Chat:Layout()
    local settings = ns.db.chat
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local size = settings.fontSize
    if not KNOWN[settings.tab] then settings.tab = "talk" end
    ticker:SetSize(W * STRIP, size * LINES + 14)
    SetFont(ticker, size)
    LayoutStrip(W * STRIP)
    -- Le panneau ouvert tient entre les deux sticks.
    local side = W * ns.STICK_X + H * 0.10
    LayoutPanel(ns.Clamp(W - 2 * side, W * 0.5, W - 16), H * 0.55)
    SetFont(list, size)
    LayoutMini(H)
    ticker:PlaceSaved()
    UpdateTabs()
    UpdateChips()
    if settings.custom then
        TuckGameChat(true)
    else
        TuckGameChat(false)
        local frame = ChatFrame1
        if frame and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, frame, size) end
    end
    Arrange()
    -- La touche d'ouverture sert dans les deux cas : l'app envoie F12 avant chaque message.
    if SetOverrideBindingClick then
        ClearOverrideBindings(opener)
        SetOverrideBindingClick(opener, true, OPEN_KEY, "WolkaraMobileChatOpener", "LeftButton")
    end
end

function Chat:SetEditing(on)
    ticker.glow:SetShown(on)
    ticker.back:SetVertexColor(0, 0, 0, on and 0.45 or 0.25)
    if on then panel:Hide() end
    Arrange()
end

for event in pairs(EVENTS) do
    ns.On(event, function(...) Add(event, ...) end)
end

-- Le jeu replace parfois son chat (Mode Édition, changement de zone) : on repasse derrière.
local function Again()
    if ns.db and ns.db.chat.custom and not InCombatLockdown() then TuckGameChat(true) end
end
ns.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(2, Again) else Again() end
end)
ns.On("UPDATE_CHAT_WINDOWS", Again)
