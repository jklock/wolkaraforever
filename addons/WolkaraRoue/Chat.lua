-- Interface mobile : le chat. En bandeau compact en bas au centre, entre les deux pouces (là
-- où était la barre de sorts), avec une police plus grande, un fond qui aide à lire et les
-- messages qui s'effacent seuls. Une bulle l'affiche ou le masque d'un toucher ; un message
-- privé le fait revenir. Pour écrire : le clavier de l'app, dont Entrée envoie dans le chat.

local _, ns = ...

local Chat = ns.Register("Chat", {})
local bubble
local hidden = false
local hiddenFrames = {}

-- Seulement ce qui est affiché : une fenêtre de chat inutilisée garde son onglet caché.
local function Candidates()
    local list = {}
    local function add(frame) if frame then list[#list + 1] = frame end end
    add(_G.GeneralDockManager)
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        add(_G["ChatFrame" .. i])
        add(_G["ChatFrame" .. i .. "Tab"])
    end
    return list
end

local function SetChatShown(shown)
    if shown then
        for frame in pairs(hiddenFrames) do frame:Show() end
        wipe(hiddenFrames)
    else
        for _, frame in ipairs(Candidates()) do
            if frame:IsShown() then
                hiddenFrames[frame] = true
                frame:Hide()
            end
        end
    end
    hidden = not shown
    bubble.text:SetText(shown and "Chat" or "Chat (caché)")
end

local function ApplyStyle()
    local frame = ChatFrame1
    if not frame or not ns.db or InCombatLockdown() then return end
    local size = ns.db.chat.fontSize
    if FCF_SetChatWindowFontSize then
        pcall(FCF_SetChatWindowFontSize, nil, frame, size)
    else
        local font, _, flags = frame:GetFont()
        if font then frame:SetFont(font, size, flags) end
    end
    if frame.SetFading then frame:SetFading(true) end
    if frame.SetTimeVisible then frame:SetTimeVisible(25) end
    if FCF_SetWindowAlpha then pcall(FCF_SetWindowAlpha, frame, 0.45) end
    if ns.db.chat.moveUp then
        pcall(function()
            local width, height = UIParent:GetWidth(), UIParent:GetHeight()
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 16)
            frame:SetSize(width * 0.36, height * 0.17)
            if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(frame) end
        end)
    end
end

-- Le Mode Édition du jeu replace le chat après nous : on repasse derrière lui.
local function ApplyLater(delay)
    if C_Timer and C_Timer.After then C_Timer.After(delay, ApplyStyle) else ApplyStyle() end
end

function Chat:Init()
    bubble = CreateFrame("Button", "WolkaraMobileChatBubble", UIParent)
    bubble:SetSize(110, 36)
    bubble:SetFrameStrata("MEDIUM")
    bubble:RegisterForClicks("AnyUp")
    ns.Box(bubble, "BACKGROUND", 0.05, 0.05, 0.08, 0.75)
    bubble.text = ns.Label(bubble, "GameFontHighlight", "Chat")
    bubble.text:SetPoint("CENTER")
    local highlight = ns.Box(bubble, "HIGHLIGHT", 1, 1, 1, 0.12)
    highlight:SetBlendMode("ADD")
    bubble.glow = ns.EditFrame(bubble)
    bubble:SetScript("OnClick", function()
        if ns.editing then return end
        SetChatShown(hidden)
    end)
    -- Juste au-dessus du coin gauche du bandeau.
    ns.Movable(bubble, function() return ns.db.chat end, "pos", function()
        return { "BOTTOMLEFT", "BOTTOM", -UIParent:GetWidth() * 0.18, UIParent:GetHeight() * 0.17 + 24 }
    end)
end

function Chat:Layout()
    if ns.db.chat.bubble then
        bubble:PlaceSaved()
        bubble:Show()
    else
        bubble:Hide()
        if hidden then SetChatShown(true) end
    end
    ApplyStyle()
end

function Chat:SetEditing(on) bubble.glow:SetShown(on) end

ns.On("PLAYER_ENTERING_WORLD", function() ApplyLater(2) end)
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function() ApplyLater(0.5) end)
-- Un message privé fait réapparaître le chat, pour ne pas le manquer.
ns.On("CHAT_MSG_WHISPER", function() if hidden and bubble then SetChatShown(true) end end)
