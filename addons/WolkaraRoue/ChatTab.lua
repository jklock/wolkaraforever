-- Chat button with peek and expanded states (iPhone Duo layout).
local _, ns = ...

local ChatTab = ns.Register("Chat tab", {})
ns.ChatTab = ChatTab

local tab, typeRow
local unread = 0
local state = "closed"
local DEFAULTS = { enabled = true }
local PILL_W, PILL_H, PILL_Y = 120, 30, 4
local TYPE_Y, TYPE_H = 0.583, 0.05
local PANEL_TOP, PANEL_H, PANEL_W = 0.20, 0.42, 0.72
local PEEK_W = 0.40
local PEEK_LINES = 6

local function Settings()
    local db = ns.db
    if type(db.chatTab) ~= "table" then db.chatTab = {} end
    for key, value in pairs(DEFAULTS) do
        if db.chatTab[key] == nil then db.chatTab[key] = value end
    end
    return db.chatTab
end
ChatTab.Settings = function() return Settings() end

local function On() return ns.DuoLayout() and Settings().enabled and ns.db.chat and ns.db.chat.custom end
local function Panel() return _G.WolkaraMobileChat end
local function Ticker() return _G.WolkaraMobileChatTicker end

local function Label()
    if not tab then return end
    tab.text:SetText(unread > 0 and (ns.T("Chat") .. " (" .. unread .. ")") or ns.T("Chat"))
    local lit = unread > 0 or state ~= "closed"
    tab.back:SetVertexColor(lit and 0.55 or 0.10, lit and 0.40 or 0.10, lit and 0.12 or 0.14, 0.85)
end

local function PlacePeek()
    local ticker = Ticker()
    if not ticker then return end
    ticker:ClearAllPoints()
    ticker:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, PILL_Y + PILL_H + 6)
    ticker:SetWidth(UIParent:GetWidth() * PEEK_W)
    local size = (ns.db and ns.db.chat and tonumber(ns.db.chat.fontSize)) or 16
    ticker:SetHeight(size * PEEK_LINES + 14)
end

local function PlacePanel()
    local panel = Panel()
    if not panel then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    panel:ClearAllPoints()
    panel:SetPoint("TOP", UIParent, "TOP", 0, -H * PANEL_TOP)
    panel:SetHeight(H * PANEL_H)
    typeRow:ClearAllPoints()
    typeRow:SetFrameStrata(panel:GetFrameStrata())
    typeRow:SetFrameLevel(panel:GetFrameLevel() + 20)
    typeRow:SetHeight(H * TYPE_H)
    local bottom = H * (PANEL_TOP + PANEL_H - TYPE_Y - TYPE_H / 2)
    typeRow:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, bottom)
    typeRow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, bottom)
end

local function Apply()
    if not tab then return end
    local panel, ticker = Panel(), Ticker()
    if not On() then
        tab:Hide(); typeRow:Hide()
        if ticker and ns.db and ns.db.chat and ns.db.chat.custom and not (panel and panel:IsShown()) then ticker:Show() end
        return
    end
    tab:Show()
    if state == "expanded" and panel and panel:IsShown() then
        PlacePanel(); typeRow:Show()
        if ticker then ticker:Hide() end
    elseif state == "peek" then
        typeRow:Hide()
        if panel and panel:IsShown() then panel:Hide() end
        PlacePeek()
        if ticker then ticker:Show() end
    else
        state = "closed"
        typeRow:Hide()
        if ticker then ticker:Hide() end
    end
    Settings().state = state
    Label()
end

local function Toggle()
    local panel = Panel()
    if state == "closed" then
        state = "peek"
    else
        state = "closed"
        if panel and panel:IsShown() and ns.Chat and ns.Chat.Close then ns.Chat.Close() end
    end
    Apply()
end

function ChatTab:Init()
    ChatTab.savedState = Settings().state
    tab = ns.UIButton(UIParent, ns.T("Chat"), PILL_W, PILL_H, Toggle)
    tab:SetFrameStrata("MEDIUM")
    tab.text:SetFontObject("GameFontNormal")
    ChatTab.button = tab
    tab:Hide()
    typeRow = CreateFrame("Frame", "WolkaraMobileChatTypeRow", UIParent)
    typeRow:SetFrameStrata("DIALOG")
    typeRow:EnableMouse(true)
    typeRow:SetScript("OnMouseUp", function(self)
        if not self:IsMouseOver() then return end
        local signal = _G.WolkaraMobileKeyboardSignal
        if not signal then return end
        signal:SetText("")
        signal:SetFocus()
        C_Timer.After(0.3, function() if signal:HasFocus() then signal:ClearFocus() end end)
    end)
    local signal = _G.WolkaraMobileKeyboardSignal
    if signal then
        signal:SetScript("OnEnterPressed", signal.ClearFocus)
        signal:SetScript("OnEscapePressed", signal.ClearFocus)
    end
    ns.Box(typeRow, "BACKGROUND", 0.03, 0.025, 0.02, 0.95)
    typeRow.channel = ns.Label(typeRow, "GameFontNormal")
    typeRow.channel:SetPoint("LEFT", 12, 0)
    typeRow.text = ns.Label(typeRow, "GameFontHighlight", ns.T("Tap to type..."))
    typeRow.text:SetPoint("LEFT", typeRow.channel, "RIGHT", 6, 0)
    typeRow.text:SetTextColor(0.61, 0.57, 0.51)
    ns.OnChatChannel = function(label)
        typeRow.channel:SetText(((label and label ~= "") and label or ns.T("Say")) .. ":")
    end
    ns.OnChatChannel(ns.chatChannelLabel)
    if ns.Skin and ns.Skin.Surface then ns.Skin.Surface(typeRow, "hud", 0) end
    typeRow:Hide()
    Label()
end

local hooked = false
local function Hook()
    if hooked then return end
    local panel, ticker = Panel(), Ticker()
    if not (panel and ticker) then return end
    hooked = true
    ticker:HookScript("OnShow", function(self) if On() and state ~= "peek" then self:Hide() end end)
    panel:HookScript("OnShow", function()
        if not On() then return end
        state = "expanded"; unread = 0
        Apply()
    end)
    panel:HookScript("OnHide", function()
        if not On() then return end
        if state == "expanded" then state = "peek" end
        Apply()
    end)
    for _, child in ipairs({ panel:GetChildren() }) do
        if type(child.text) == "table" and child.text.GetText and child.text:GetText() == "X" then child:Hide(); child.Show = child.Hide end
    end
end

function ChatTab:Layout()
    if not tab then return end
    Hook()
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, PILL_Y)
    tab:SetHitRectInsets(-6, -6, -8, -4)
    Apply()
end

function ChatTab:SetEditing() Apply() end

local function Whisper()
    if state == "expanded" then return end
    unread = unread + 1
    Label()
end
ns.On("CHAT_MSG_WHISPER", Whisper)
ns.On("CHAT_MSG_BN_WHISPER", Whisper)

ns.On("PLAYER_ENTERING_WORLD", function(initialLogin, reloading)
    if not (ns.db and tab and On()) then return end
    local saved = ChatTab.savedState
    ChatTab.savedState = nil
    if reloading and (saved == "peek" or saved == "expanded") then
        state = "peek"
        Apply()
        if saved == "expanded" and ns.Chat and ns.Chat.Open and not InCombatLockdown() then ns.Chat.Open() end
    elseif initialLogin then
        state = "closed"
        Apply()
    end
end)
