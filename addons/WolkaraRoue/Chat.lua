-- Interface mobile : le chat, refait comme une messagerie de téléphone.
--
-- Le chat du jeu disparaît ; ne reste que sa zone de saisie, invisible, qui sert de passage
-- pour envoyer. À sa place :
--   * en bas au centre, un fil discret des derniers messages, qui s'effacent seuls, avec le
--     nombre de messages privés non lus ; un toucher l'ouvre ;
--   * ouvert, un panneau à onglets (Tout, Groupe, Guilde, Privé, Système) en gros texte, avec
--     des flèches pour remonter, et en bas le choix de la conversation : Dire, Groupe, Guilde,
--     Général ou Répondre. Toucher le nom d'un joueur choisit de lui écrire en privé.
-- Pour écrire : le bouton clavier de l'app, en haut. Entrée envoie à la conversation choisie,
-- parce que l'app appuie d'abord sur F12, que ce module relie à « ouvrir la saisie sur la
-- conversation choisie ». Une commande (/…) passe par la touche / du jeu, sans conversation.

local _, ns = ...

local Chat = ns.Register("Chat", {})
local MAX_MESSAGES = 300
local OPEN_KEY = "F12"

local messages = {}
local tab = "all"
local target = { kind = "say" }
local lastWhisper
local unread = 0
local ticker, panel, list, tabButtons, chips, hint, badge, opener
local hider = CreateFrame("Frame")
hider:Hide()

local TABS = {
    { key = "all", label = "Tout" }, { key = "group", label = "Groupe" }, { key = "guild", label = "Guilde" },
    { key = "whisper", label = "Privé" }, { key = "system", label = "Système" },
}

-- Ce que chaque message du jeu devient : son étiquette, ses onglets, et s'il passe dans le fil.
local SOCIAL = { all = true }
local EVENTS = {
    CHAT_MSG_SAY = { label = "Dire", tabs = SOCIAL, ticker = true },
    CHAT_MSG_YELL = { label = "Crier", tabs = SOCIAL, ticker = true },
    CHAT_MSG_EMOTE = { emote = true, tabs = SOCIAL, ticker = true },
    CHAT_MSG_TEXT_EMOTE = { raw = true, tabs = SOCIAL, ticker = true },
    CHAT_MSG_PARTY = { label = "Groupe", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_PARTY_LEADER = { label = "Chef", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_RAID = { label = "Raid", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_RAID_LEADER = { label = "Chef de raid", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_RAID_WARNING = { label = "Alerte", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_INSTANCE_CHAT = { label = "Instance", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { label = "Instance", tabs = { all = true, group = true }, ticker = true },
    CHAT_MSG_GUILD = { label = "Guilde", tabs = { all = true, guild = true }, ticker = true },
    CHAT_MSG_OFFICER = { label = "Officier", tabs = { all = true, guild = true }, ticker = true },
    CHAT_MSG_WHISPER = { label = "De", tabs = { all = true, whisper = true }, ticker = true, incoming = true },
    CHAT_MSG_WHISPER_INFORM = { label = "À", tabs = { all = true, whisper = true }, ticker = true },
    CHAT_MSG_CHANNEL = { channel = true, tabs = SOCIAL, ticker = true },
    CHAT_MSG_MONSTER_SAY = { label = "Dit", tabs = SOCIAL },
    CHAT_MSG_MONSTER_YELL = { label = "Crie", tabs = SOCIAL },
    CHAT_MSG_MONSTER_WHISPER = { label = "Murmure", tabs = SOCIAL },
    CHAT_MSG_MONSTER_EMOTE = { emote = true, tabs = SOCIAL },
    CHAT_MSG_SYSTEM = { raw = true, tabs = { all = true, system = true }, ticker = true },
    CHAT_MSG_LOOT = { raw = true, tabs = { system = true } },
    CHAT_MSG_MONEY = { raw = true, tabs = { system = true } },
    CHAT_MSG_COMBAT_XP_GAIN = { raw = true, tabs = { system = true } },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { raw = true, tabs = { system = true } },
    CHAT_MSG_SKILL = { raw = true, tabs = { system = true } },
}

local TARGETS = {
    { kind = "say", label = "Dire" }, { kind = "party", label = "Groupe" }, { kind = "guild", label = "Guilde" },
    { kind = "general", label = "Général" }, { kind = "whisper", label = "Répondre" },
}

-- ---------------------------------------------------------------------------------------
-- Messages

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

local function Format(event, info, text, author, channelIndex, channelBase)
    local stamp = date and date("%H:%M ") or ""
    if info.raw then return stamp .. text end
    if info.emote then return stamp .. PlayerLink(author) .. " " .. text end
    local label = info.label
    if info.channel then
        label = (channelIndex and (channelIndex .. ". ") or "") .. (channelBase ~= "" and channelBase or "Canal")
    end
    return ("%s[%s] %s : %s"):format(stamp, label, PlayerLink(author), text)
end

local function Shows(entry) return entry.tabs[tab] end

local function Add(event, text, author, _, _, _, _, _, channelIndex, channelBase)
    local info = EVENTS[event]
    if not info or type(text) ~= "string" then return end
    local r, g, b = Color(event, channelIndex)
    local entry = { line = Format(event, info, text, author, channelIndex, channelBase), r = r, g = g, b = b,
        tabs = info.tabs, ticker = info.ticker }
    messages[#messages + 1] = entry
    if #messages > MAX_MESSAGES then table.remove(messages, 1) end
    if info.incoming and author then
        lastWhisper = author
        if not (panel and panel:IsShown() and tab == "whisper") then unread = unread + 1 end
    end
    if panel and panel:IsShown() and Shows(entry) then list:AddMessage(entry.line, r, g, b) end
    if ticker and entry.ticker then ticker:AddMessage(entry.line, r, g, b) end
    if badge then Chat:UpdateBadge() end
end

local function Rebuild()
    list:Clear()
    for _, entry in ipairs(messages) do
        if Shows(entry) then list:AddMessage(entry.line, entry.r, entry.g, entry.b) end
    end
    list:ScrollToBottom()
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

local function OpenInput()
    if ChatFrame_OpenChat then ChatFrame_OpenChat(Prefix(), DEFAULT_CHAT_FRAME) end
end

local function UpdateChips()
    if not chips then return end
    for _, chip in ipairs(chips) do
        local selected = chip.kind == target.kind
        if chip.kind == "whisper" then
            local name = target.name or lastWhisper
            chip.text:SetText(name and ("À " .. (Ambiguate and Ambiguate(name, "short") or name)) or "Répondre")
        end
        chip.back:SetVertexColor(selected and 0.85 or 0.18, selected and 0.68 or 0.18, selected and 0.3 or 0.22, 0.95)
    end
end

local function UpdateTabs()
    for _, button in ipairs(tabButtons) do
        local selected = button.key == tab
        button.back:SetVertexColor(selected and 0.85 or 0.18, selected and 0.68 or 0.18, selected and 0.3 or 0.22, 0.95)
    end
end

-- ---------------------------------------------------------------------------------------
-- Le chat du jeu : rangé, sauf sa saisie, qui reste au-dessus du fil pour faire le passage.

local moved = {}
local function GameChat()
    local list = {}
    local function add(frame) if frame then list[#list + 1] = frame end end
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
            "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }) do
        add(_G[name])
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        add(_G["ChatFrame" .. i])
        add(_G["ChatFrame" .. i .. "Tab"])
        add(_G["ChatFrame" .. i .. "ButtonFrame"])
    end
    return list
end

local boxParent
local function TuckGameChat(on)
    local box = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox
    if on then
        for _, frame in ipairs(GameChat()) do
            if frame:GetParent() ~= hider then
                moved[frame] = frame:GetParent() or UIParent
                frame:SetParent(hider)
            end
        end
        if box and not boxParent then
            boxParent = box:GetParent() or UIParent
            box:SetParent(UIParent)
            box:SetFrameStrata("DIALOG")
            box:ClearAllPoints()
            box:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, UIParent:GetHeight() * 0.16)
            box:SetWidth(UIParent:GetWidth() * 0.42)
        end
    else
        for frame, parent in pairs(moved) do
            frame:SetParent(parent)
            moved[frame] = nil
        end
        if box and boxParent then
            box:SetParent(boxParent)
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

local function ArrowButton(parent, texture, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(44, 44)
    button:SetNormalTexture(texture .. "-Up")
    button:SetPushedTexture(texture .. "-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

local function Open()
    if ns.editing then return end
    panel:Show()
    ticker:Hide()
    if tab == "whisper" or unread > 0 then unread = 0 end
    Chat:UpdateBadge()
    Rebuild()
    UpdateChips()
end

local function Close()
    panel:Hide()
    if ns.db.chat.custom then ticker:Show() end
end

function Chat:UpdateBadge()
    badge:SetText(unread > 0 and (unread .. (unread == 1 and " nouveau privé" or " nouveaux privés")) or "")
end

function Chat:Init()
    -- Le fil : les derniers messages, discrets, qui s'effacent seuls.
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
    badge = ns.Label(ticker, "GameFontNormal")
    badge:SetPoint("BOTTOMRIGHT", ticker, "TOPRIGHT", 0, 4)
    badge:SetTextColor(1, 0.5, 1)
    local open = ns.Label(ticker, "GameFontDisable", "Toucher pour ouvrir le chat")
    open:SetPoint("BOTTOMLEFT", ticker, "TOPLEFT", 0, 4)
    ns.Movable(ticker, function() return ns.db.chat end, "pos", { "BOTTOM", "BOTTOM", 0, 16 })

    -- Le panneau ouvert.
    panel = CreateFrame("Frame", "WolkaraMobileChat", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("BOTTOM", ticker, "BOTTOM", 0, -6)
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.03, 0.04, 0.07, 0.92)

    tabButtons = {}
    for i, info in ipairs(TABS) do
        local button = ns.UIButton(panel, info.label, 90, 38, function()
            tab = info.key
            if tab == "whisper" then unread = 0; Chat:UpdateBadge() end
            UpdateTabs(); Rebuild()
        end)
        button.key = info.key
        button:SetPoint("TOPLEFT", 10 + (i - 1) * 96, -8)
        tabButtons[i] = button
    end
    local close = ns.UIButton(panel, "Fermer", 100, 38, Close)
    close:SetPoint("TOPRIGHT", -10, -8)

    list = CreateFrame("ScrollingMessageFrame", "WolkaraMobileChatList", panel)
    list:SetJustifyH("LEFT")
    list:SetMaxLines(MAX_MESSAGES)
    list:SetFading(false)
    list:EnableMouse(true)
    if list.SetHyperlinksEnabled then list:SetHyperlinksEnabled(true) end
    list:SetPoint("TOPLEFT", 12, -54)
    list:SetPoint("BOTTOMRIGHT", -62, 92)
    list:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local name = link:match("^player:([^:]+)")
        if name then
            target = { kind = "whisper", name = name }
            UpdateChips()
            hint:SetText("Message privé à " .. (Ambiguate and Ambiguate(name, "short") or name) .. " : touche le clavier en haut pour écrire.")
        elseif SetItemRef then
            SetItemRef(link, text, button, self)
        end
    end)

    local up = ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", function()
        for _ = 1, 3 do list:ScrollUp() end
    end)
    up:SetPoint("TOPRIGHT", -10, -58)
    local down = ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", function()
        for _ = 1, 3 do list:ScrollDown() end
    end)
    down:SetPoint("TOP", up, "BOTTOM", 0, -8)
    local bottom = ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd", function() list:ScrollToBottom() end)
    bottom:SetPoint("TOP", down, "BOTTOM", 0, -8)

    local to = ns.Label(panel, "GameFontNormal", "Envoyer à :")
    to:SetPoint("BOTTOMLEFT", 12, 56)
    chips = {}
    for i, info in ipairs(TARGETS) do
        local chip = ns.UIButton(panel, info.label, i == 5 and 150 or 100, 36, function()
            target = { kind = info.kind }
            if info.kind == "whisper" then target.name = lastWhisper end
            UpdateChips()
            hint:SetText("Touche le clavier en haut de l'écran pour écrire ; Entrée envoie.")
        end)
        chip.kind = info.kind
        if i == 1 then chip:SetPoint("LEFT", to, "RIGHT", 10, 0) else chip:SetPoint("LEFT", chips[i - 1], "RIGHT", 6, 0) end
        chips[i] = chip
    end
    hint = ns.Label(panel, "GameFontHighlight", "Touche le clavier en haut de l'écran pour écrire ; Entrée envoie.")
    hint:SetPoint("BOTTOMLEFT", 12, 18)
    hint:SetPoint("BOTTOMRIGHT", -12, 18)
    hint:SetJustifyH("LEFT")

    -- F12 : la touche que l'app envoie avant un message.
    opener = CreateFrame("Button", "WolkaraMobileChatOpener", UIParent)
    opener:SetScript("OnClick", function() ns.Guard("ouvrir la saisie", OpenInput) end)

    UpdateTabs()
    -- Les messages de l'addon, quand le chat du jeu est rangé.
    ns.ChatAdd = function(line)
        if not ns.db or not ns.db.chat.custom then return false end
        messages[#messages + 1] = { line = line, r = 1, g = 1, b = 1, tabs = { all = true, system = true }, ticker = true }
        if #messages > MAX_MESSAGES then table.remove(messages, 1) end
        if panel:IsShown() and (tab == "all" or tab == "system") then list:AddMessage(line) end
        ticker:AddMessage(line)
        return true
    end
end

function Chat:Layout()
    local settings = ns.db.chat
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local size = settings.fontSize
    ticker:SetSize(width * 0.40, size * 3 + 16)
    SetFont(ticker, size)
    panel:SetSize(width * 0.54, height * 0.52)
    SetFont(list, size)
    ticker:PlaceSaved()
    if settings.custom then
        TuckGameChat(true)
        if not panel:IsShown() then ticker:Show() end
    else
        TuckGameChat(false)
        ticker:Hide()
        panel:Hide()
        local frame = ChatFrame1
        if frame and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, frame, size) end
    end
    -- La touche d'ouverture sert dans les deux cas : l'app envoie F12 avant chaque message.
    if SetOverrideBindingClick then
        ClearOverrideBindings(opener)
        SetOverrideBindingClick(opener, true, OPEN_KEY, "WolkaraMobileChatOpener", "LeftButton")
    end
end

function Chat:SetEditing(on)
    ticker.glow:SetShown(on)
    ticker.back:SetVertexColor(0, 0, 0, on and 0.45 or 0.25)
    if on then panel:Hide(); ticker:Show() end
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
