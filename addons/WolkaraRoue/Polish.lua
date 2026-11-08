-- Press feedback, proc glows, cast bars, animations, low-health edge, tips and saved layouts.
local _, ns = ...

local Polish = ns.Register("Polish", {})
ns.Polish = Polish

local hider = CreateFrame("Frame")
hider:Hide()

local function Slots()
    local list = {}
    for page = 1, 2 do for index = 1, 10 do list[#list + 1] = _G["WolkaraMobileFan" .. page .. "Skill" .. index] end end
    for page = 1, 5 do for index = 1, 5 do list[#list + 1] = _G["WolkaraMobileQuick" .. page .. "Slot" .. index] end end
    return list
end

local function PressFeedback(button)
    if not button or button.wmPress then return end
    button.wmPress = ns.Disc(button, "OVERLAY", 0, 0, 0, 0.35, 0)
    button.wmPress:Hide()
    button.wmGlow = ns.Disc(button, "BACKGROUND", 1, 0.82, 0.29, 0.45, 9)
    button.wmGlow:SetDrawLayer("BACKGROUND", -8)
    button.wmGlow:SetBlendMode("ADD")
    button.wmGlow:Hide()
    local function Up() button.wmPress:Hide(); button.wmGlow:Hide() end
    button:HookScript("OnMouseDown", function() button.wmPress:Show(); button.wmGlow:Show() end)
    button:HookScript("OnMouseUp", Up)
    button:HookScript("OnHide", Up)
end

local function ProcRing(button)
    if button.wmProc then return button.wmProc end
    local ring = CreateFrame("Frame", nil, button)
    ring:SetAllPoints()
    ring:SetFrameLevel(button:GetFrameLevel() + 2)
    local disc = ns.Disc(ring, "OVERLAY", 1, 0.85, 0.3, 0.55, 6)
    disc:SetBlendMode("ADD")
    local pulse = ring:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.5)
    ring.pulse = pulse
    ring:Hide()
    button.wmProc = ring
    return ring
end

local function SameSpell(entry, spellID)
    if not entry or entry.kind ~= "spell" then return false end
    if entry.id == spellID then return true end
    local a, b = ns.SpellName(entry.id), ns.SpellName(spellID)
    return a ~= nil and a == b
end

local function ShowProcs(spellID, on)
    for _, button in ipairs(Slots()) do
        if button and button.GetEntry and SameSpell(button:GetEntry(), spellID) then
            local ring = ProcRing(button)
            ring:SetShown(on)
            if on then ring.pulse:Play() else ring.pulse:Stop() end
        end
    end
end

local function CastBar(name, parent, width)
    local bar = CreateFrame("StatusBar", name, parent or UIParent)
    bar:SetSize(width, 14)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0.75, 0.2)
    bar:SetMinMaxValues(0, 1)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -3, 3); back:SetPoint("BOTTOMRIGHT", 3, -3)
    back:SetColorTexture(0.05, 0.04, 0.03, 0.85)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(20, 20)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -6, 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.text = ns.Label(bar, "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", 6, 0)
    bar.time = ns.Label(bar, "GameFontHighlightSmall")
    bar.time:SetPoint("RIGHT", -6, 0)
    bar:Hide()
    bar:SetScript("OnUpdate", function(self)
        if not self.startMS then return end
        local ok, done, left = pcall(function()
            local now = GetTime() * 1000
            local span = self.endMS - self.startMS
            local part = (now - self.startMS) / span
            if self.channel then part = 1 - part end
            return part, (self.endMS - now) / 1000
        end)
        if ok then
            self:SetValue(math.max(0, math.min(1, done)))
            self.time:SetText(left > 0 and string.format("%.1f", left) or "")
        else
            self:SetValue(1); self.time:SetText("")
        end
    end)
    return bar
end

local playerBar, targetBar
local function StartCast(bar, unit)
    if not bar then return end
    local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if not name and UnitChannelInfo then
        name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        channel = name ~= nil
    end
    if not name then bar:Hide(); bar.startMS = nil; return end
    bar.startMS, bar.endMS, bar.channel = startMS, endMS, channel
    bar.icon:SetTexture(texture)
    bar.text:SetText(name)
    local known, locked = pcall(function() return notInterruptible == true end)
    locked = known and locked
    if unit == "player" then bar:SetStatusBarColor(1, 0.75, 0.2)
    elseif locked then bar:SetStatusBarColor(0.6, 0.6, 0.6)
    else bar:SetStatusBarColor(1, 0.45, 0.1) end
    bar:Show()
end
local function StopCast(bar) if bar then bar:Hide(); bar.startMS = nil end end

local function FadeIn(frame, slide)
    if not frame or frame.wmIn then return end
    local group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.12)
    if slide and not (frame.IsProtected and frame:IsProtected()) then
        local move = group:CreateAnimation("Translation")
        move:SetOffset(-slide, 0); move:SetDuration(0.12)
        local start = group:CreateAnimation("Translation")
        start:SetOffset(slide, 0); start:SetDuration(0); start:SetOrder(1)
        move:SetOrder(2); fade:SetOrder(2)
    end
    frame.wmIn = group
    frame:HookScript("OnShow", function() group:Stop(); group:Play() end)
end

local edge
local function Edge()
    edge = CreateFrame("Frame", "WolkaraMobileLowHealth", UIParent)
    edge:SetAllPoints()
    edge:SetFrameStrata("BACKGROUND")
    edge:EnableMouse(false)
    local red, clear = CreateColor and CreateColor(0.8, 0, 0, 0.45), CreateColor and CreateColor(0.8, 0, 0, 0)
    local function Side(anchors, size, vertical, from, to)
        local t = edge:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ns.WHITE)
        for _, a in ipairs(anchors) do t:SetPoint(a, edge, a) end
        if vertical then t:SetHeight(size) else t:SetWidth(size) end
        if not (t.SetGradient and red and pcall(t.SetGradient, t, vertical and "VERTICAL" or "HORIZONTAL", from, to)) then
            t:SetVertexColor(0.8, 0, 0, 0.15)
        end
    end
    Side({ "TOPLEFT", "TOPRIGHT" }, 60, true, clear, red)
    Side({ "BOTTOMLEFT", "BOTTOMRIGHT" }, 60, true, red, clear)
    Side({ "TOPLEFT", "BOTTOMLEFT" }, 70, false, red, clear)
    Side({ "TOPRIGHT", "BOTTOMRIGHT" }, 70, false, clear, red)
    local pulse = edge:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.5); fade:SetDuration(0.8)
    edge.pulse = pulse
    edge:Hide()
end
local function CheckHealth()
    if not edge then return end
    local ok, low = pcall(function()
        local most = UnitHealthMax("player")
        return most > 0 and not UnitIsDeadOrGhost("player") and UnitHealth("player") / most < 0.3
    end)
    local show = ok and low and ns.DuoLayout() or false
    if show ~= edge:IsShown() then
        edge:SetShown(show)
        if show then edge.pulse:Play() else edge.pulse:Stop() end
    end
end

local tips
local TIPS = {
    "Swipe along the skill arc, or tap the arrow, to switch between skills 1-5 and 6-10.",
    "Hold the move stick fully forward for 2 seconds, then slide onto the lock to auto-run.",
    "Tap Edit (under the menu button) to change your skills: tap a slot, then a spell.",
    "The menu button under the minimap opens your quick menu; choose its entries in Menu.",
    "Tap Chat to peek at the latest lines, tap the lines to open the full chat.",
}
function ns.ShowTips()
    if not tips then
        tips = CreateFrame("Frame", "WolkaraMobileTips", UIParent)
        tips:SetFrameStrata("FULLSCREEN_DIALOG")
        tips:SetSize(560, 74 + #TIPS * 34 + 60)
        tips:SetPoint("CENTER")
        tips:EnableMouse(true)
        ns.Box(tips, "BACKGROUND", 0.07, 0.06, 0.05, 0.95)
        local title = ns.Label(tips, "GameFontNormalLarge", ns.T("Tips"))
        title:SetPoint("TOP", 0, -18)
        for i, line in ipairs(TIPS) do
            local text = ns.Label(tips, "GameFontHighlight", ns.T(line))
            text:SetPoint("TOPLEFT", 24, -54 - (i - 1) * 34)
            text:SetWidth(512); text:SetJustifyH("LEFT")
        end
        local ok = ns.UIButton(tips, ns.T("Got it"), 160, 40, function() tips:Hide(); if ns.db then ns.db.tipsSeen = true end end)
        ok:SetPoint("BOTTOM", 0, 16)
        if ns.Skin and ns.Skin.Surface then ns.Skin.Surface(tips, "panel", 2) end
        if ns.Skin and ns.Skin.Button then ns.Skin.Button(ok) end
        FadeIn(tips)
    end
    tips:SetScale(math.min(1, (UIParent:GetHeight() - 20) / tips:GetHeight(), (UIParent:GetWidth() - 20) / tips:GetWidth()))
    tips:Show()
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v) end
    return out
end
function ns.PresetName(slot) return (ns.T("Preset %d")):format(slot) end

function ns.SavePreset(slot)
    if InCombatLockdown() or not ns.db then ns.Print(ns.T("change the controls out of combat.")); return end
    ns.db.layouts = ns.db.layouts or {}
    ns.db.layouts[slot] = { fan = Copy(ns.db.fan and ns.db.fan.pages), quick = Copy(ns.db.quick and ns.db.quick.pages) }
    ns.db.presetActive = slot
    ns.Print((ns.T("Preset saved: %s.")):format(ns.PresetName(slot)))
    ns.MarkChanged()
end

function ns.LoadPreset(slot)
    if InCombatLockdown() or not ns.db then ns.Print(ns.T("change the controls out of combat.")); return end
    local saved = ns.db.layouts and ns.db.layouts[slot]
    if not saved then ns.Print((ns.T("%s is empty: save to it first.")):format(ns.PresetName(slot))); return end
    if saved.fan and ns.db.fan then ns.db.fan.pages = Copy(saved.fan) end
    if saved.quick and ns.db.quick then ns.db.quick.pages = Copy(saved.quick) end
    ns.db.presetActive = slot
    ns.Print((ns.T("Preset loaded: %s.")):format(ns.PresetName(slot)))
    ns.MarkChanged(); ns.Layout(); ns.Refresh()
end

ns.SaveLayout, ns.LoadLayout = ns.SavePreset, ns.LoadPreset

function Polish:Init()
    if ns.db then ns.db.presetNames = nil end
    playerBar = CastBar("WolkaraMobileCastBar", UIParent, 280)
    targetBar = CastBar("WolkaraMobileTargetCastBar", UIParent, 300)
    Edge()
end

function Polish:Layout()
    if InCombatLockdown() then return end
    local duo = ns.DuoLayout()
    for _, button in ipairs(Slots()) do PressFeedback(button) end
    playerBar:ClearAllPoints()
    playerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 13, UIParent:GetHeight() * 0.36)
    local target = _G.WolkaraMobileTarget
    targetBar:ClearAllPoints()
    if target then targetBar:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 62, -44) else targetBar:SetPoint("TOP", UIParent, "TOP", 0, -170) end
    for _, name in ipairs({ "PlayerCastingBarFrame", "CastingBarFrame" }) do
        local frame = _G[name]
        if frame then
            if duo and frame:GetParent() ~= hider then frame.wmHome = frame:GetParent(); frame:SetParent(hider)
            elseif not duo and frame:GetParent() == hider then frame:SetParent(frame.wmHome or UIParent) end
        end
    end
    for _, name in ipairs({ "WolkaraMobilePicker", "WolkaraMobileControls", "WolkaraMobileBuffPanel", "WolkaraMobileChat", "WolkaraMobileSettings" }) do
        FadeIn(_G[name])
    end
    FadeIn(_G.WolkaraMobileMenu and _G.WolkaraMobileMenu.card)
    FadeIn(_G.WolkaraMobileQuickMenu, 18)
    FadeIn(_G.WolkaraMobileChatTicker)
    if IsSpellOverlayed then
        for _, button in ipairs(Slots()) do
            local entry = button and button.GetEntry and button:GetEntry()
            if entry and entry.kind == "spell" then
                local on = IsSpellOverlayed(entry.id) and true or false
                local ring = ProcRing(button)
                ring:SetShown(on)
                if on then ring.pulse:Play() else ring.pulse:Stop() end
            end
        end
    end
    CheckHealth()
    if duo and ns.db and not ns.db.tipsSeen and C_Timer and C_Timer.After then
        ns.db.tipsSeen = true
        C_Timer.After(3, function() if not InCombatLockdown() then ns.ShowTips() end end)
    end
end

ns.On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(spellID) if ns.db then ShowProcs(spellID, true) end end)
ns.On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(spellID) if ns.db then ShowProcs(spellID, false) end end)
local function Cast(unit)
    if not ns.db or not ns.DuoLayout() then return end
    if unit == "player" then StartCast(playerBar, "player") elseif unit == "target" then StartCast(targetBar, "target") end
end
local function Stop(unit)
    if unit == "player" then StopCast(playerBar) elseif unit == "target" then StopCast(targetBar) end
end
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
    ns.On(event, Cast)
end
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    ns.On(event, Stop)
end
ns.On("PLAYER_TARGET_CHANGED", function() if ns.db and ns.DuoLayout() then StartCast(targetBar, "target") end end)
ns.On("UNIT_HEALTH", function(unit) if unit == "player" and ns.db then CheckHealth() end end)
ns.On("UNIT_MAXHEALTH", function(unit) if unit == "player" and ns.db then CheckHealth() end end)
