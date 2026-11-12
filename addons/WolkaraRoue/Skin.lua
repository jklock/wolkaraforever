-- Shared style for panels, cards, buttons and slots.
local _, ns = ...

local Skin = ns.Register("Skin", {})
ns.Skin = Skin

local BRONZE = { 0.54, 0.43, 0.23, 0.95 }
local EDGE = { 0.36, 0.29, 0.20, 0.9 }
local GOLD = { 1, 0.82, 0.29 }
local WARM = { 0.91, 0.89, 0.83 }
local MUTED = { 0.61, 0.57, 0.51 }
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

local function HideBackground(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            region:SetAlpha(0)
        end
    end
end

local function Surface(frame, kind, pad)
    if frame.wmSkin then return frame.wmSkin end
    local skin = CreateFrame("Frame", nil, frame, backdropTemplate)
    pad = pad or 0
    skin:SetPoint("TOPLEFT", -pad, pad)
    skin:SetPoint("BOTTOMRIGHT", pad, -pad)
    skin:SetFrameLevel(frame:GetFrameLevel())
    if skin.SetBackdrop then
        skin:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = kind == "panel" and 16 or 12,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        skin:SetBackdropColor(0.07, 0.06, 0.05, kind == "panel" and 0.94 or 0.82)
        local edge = kind == "panel" and BRONZE or EDGE
        skin:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
    end
    HideBackground(frame)
    frame.wmSkin = skin
    return skin
end
Skin.Surface = Surface

local TAB_WORDS = { "Spells", "Items", "Macros", "Actions", "Chat", "Whispers", "System", "All",
    "Say", "Party", "Guild", "General", "Reply" }
local tabWord = {}
local function IsGold(r, g, b) return r > 0.5 and g > 0.35 and b < 0.35 and r > g end
local function IsGreen(r, g, b) return g > r + 0.12 and g > 0.35 end

local function Paint(button)
    local r, g, b = button.back:GetVertexColor()
    local on = IsGold(r, g, b) or IsGreen(r, g, b)
    button.wmBusy = true
    if button.wmPrimary then
        button.back:SetVertexColor(0.55, 0.08, 0.08, 0.98)
        button.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    elseif button.wmTab then
        button.back:SetVertexColor(0, 0, 0, 0)
        button.wmLine:SetShown(on)
        local c = on and GOLD or MUTED
        button.text:SetTextColor(c[1], c[2], c[3])
    elseif on then
        button.back:SetVertexColor(0.84, 0.65, 0.16, 0.95)
        button.text:SetTextColor(0.16, 0.10, 0.02)
    else
        button.back:SetVertexColor(0.13, 0.11, 0.09, 0.95)
        button.text:SetTextColor(WARM[1], WARM[2], WARM[3])
    end
    button.wmBusy = false
end

function Skin.Button(button)
    if button.wmButton or type(button.back) ~= "table" or type(button.text) ~= "table" then return end
    if type(button.back.SetVertexColor) ~= "function" or type(button.text.SetTextColor) ~= "function" then return end
    button.wmButton = true
    local text = button.text.GetText and button.text:GetText()
    local parent = button:GetParent()
    local inPanel = parent == _G.WolkaraMobilePicker or parent == _G.WolkaraMobileChat or parent == _G.WolkaraMobileChatTicker
    if inPanel and text and tabWord[text] then
        button.wmTab = true
        button.wmLine = button:CreateTexture(nil, "OVERLAY")
        button.wmLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        button.wmLine:SetHeight(2)
        button.wmLine:SetPoint("BOTTOMLEFT", 6, 1)
        button.wmLine:SetPoint("BOTTOMRIGHT", -6, 1)
    else
        local edge = CreateFrame("Frame", nil, button, backdropTemplate)
        edge:SetAllPoints()
        edge:SetFrameLevel(button:GetFrameLevel())
        if edge.SetBackdrop then
            edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
            edge:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 0.9)
        end
    end
    if button.wmTab and parent == _G.WolkaraMobileChat then Surface(button, "hud", 0) end
    hooksecurefunc(button.back, "SetVertexColor", function() if not button.wmBusy then Paint(button) end end)
    Paint(button)
end

function ns.SkinPrimary(button, on)
    if not button or type(button.back) ~= "table" then return end
    Skin.Button(button)
    button.wmPrimary = on and true or nil
    Paint(button)
end

function Skin.Ring(button, width)
    if not button or button.wmRing then return end
    button.wmRing = ns.Disc(button, "BACKGROUND", BRONZE[1], BRONZE[2], BRONZE[3], 1, width or 6)
    button.wmRing:SetDrawLayer("BACKGROUND", -7)
end

local function Fade(frame)
    if not frame or frame.wmFade then return end
    HideBackground(frame)
    local fade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    fade:SetPoint("TOPLEFT", -10, 14)
    fade:SetPoint("BOTTOMRIGHT", 10, -6)
    fade:SetTexture(ns.WHITE)
    local ok = fade.SetGradient and CreateColor and pcall(fade.SetGradient, fade, "VERTICAL", CreateColor(0, 0, 0, 0.62), CreateColor(0, 0, 0, 0))
    if not ok and fade.SetGradientAlpha then ok = pcall(fade.SetGradientAlpha, fade, "VERTICAL", 0, 0, 0, 0.62, 0, 0, 0, 0) end
    if not ok then fade:SetVertexColor(0, 0, 0, 0.4) end
    frame.wmFade = fade
end

local function Descendants(frame, visit)
    for _, child in ipairs({ frame:GetChildren() }) do
        visit(child)
        Descendants(child, visit)
    end
end

local function Apply()
    for _, word in ipairs(TAB_WORDS) do tabWord[ns.T(word)] = true; tabWord[word] = true end
    local menu = _G.WolkaraMobileMenu
    for _, frame in ipairs({ menu and menu.card, _G.WolkaraMobilePicker, _G.WolkaraMobileChat, _G.WolkaraMobileSettings,
        _G.WolkaraMobileControls, _G.WolkaraMobileBuffPanel, _G.WolkaraMobileQuickMenu }) do
        if frame then Surface(frame, "panel", 2) end
    end
    for _, frame in ipairs({ _G.WolkaraMobileQuests, _G.WolkaraMobileTarget, _G.WolkaraMobileQuickTab, _G.WolkaraMobileQuickPager,
        _G.WolkaraMobileQuickMenuTab, ns.ChatTab and ns.ChatTab.button, _G.WolkaraMobileParty1, _G.WolkaraMobileParty2,
        _G.WolkaraMobileParty3, _G.WolkaraMobileParty4 }) do
        if frame then Surface(frame, "hud", 2) end
    end
    for _, frame in ipairs({ menu and menu.card, _G.WolkaraMobilePicker, _G.WolkaraMobileChat, _G.WolkaraMobileChatTicker,
        _G.WolkaraMobileSettings, _G.WolkaraMobileControls, _G.WolkaraMobileBuffPanel }) do
        if frame then Descendants(frame, Skin.Button) end
    end
    if ns.ChatTab and ns.ChatTab.button then Skin.Button(ns.ChatTab.button) end
    local card = menu and menu.card
    if card then
        for _, child in ipairs({ card:GetChildren() }) do
            if child.GetObjectType and child:GetObjectType() == "Button" and type(child.back) ~= "table" then Surface(child, "hud", 0) end
        end
    end
    for page = 1, 2 do
        for index = 1, 10 do Skin.Ring(_G["WolkaraMobileFan" .. page .. "Skill" .. index]) end
    end
    for page = 1, 5 do
        for index = 1, 5 do Skin.Ring(_G["WolkaraMobileQuick" .. page .. "Slot" .. index]) end
    end
    for _, name in ipairs({ "WolkaraMobileFanTab", "WolkaraMobileFanFlip", "WolkaraMobileDuoBags", "WolkaraMobileDuoEdit" }) do
        Skin.Ring(_G[name], 3)
    end
    for i = 1, 40 do Skin.Ring(_G["WolkaraMobileQuickMenu" .. i], 3) end
    Skin.Ring(_G.WolkaraMobileQuickMenuMain, 3)
    Fade(_G.WolkaraMobileChatTicker)
end

function Skin:Init()
    if ns.UIButton then
        local make = ns.UIButton
        ns.UIButton = function(...)
            local button = make(...)
            if Skin.ready then Skin.Button(button) end
            return button
        end
    end
end

function Skin:Layout()
    if not Skin.ready then Skin.ready = true; Apply() end
end
