-- Player and target frames, buff row and buff panel (iPhone Duo layout).
local _, ns = ...

local Status = ns.Register("Status", {})
ns.Status = Status

local MAX = 12
local SIZE = 30
local PER_ROW = 6
local TOP_X = 0.545
local icons = {}
local panel, hit, FillPanel
local rows, cancels = {}, {}
local hider = CreateFrame("Frame")
hider:Hide()
local homes = {}
local DEFAULTS = { buffs = true }

local function Settings()
    local db = ns.db
    if type(db.status) ~= "table" then db.status = {} end
    for key, value in pairs(DEFAULTS) do
        if db.status[key] == nil then db.status[key] = value end
    end
    return db.status
end
Status.Settings = function() return Settings() end

local function Player() return _G.WolkaraMobilePlayer end

local function Present(value)
    if issecretvalue and issecretvalue(value) then return true end
    return value ~= nil
end

local function Aura(index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local found, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
        if not found or not Present(aura) then return false end
        local ok, icon, count, duration, expiration = pcall(function() return aura.icon, aura.applications, aura.duration, aura.expirationTime end)
        if ok then return true, icon, count, duration, expiration end
        return true
    end
    if UnitAura then
        local ok, name, icon, count, _, duration, expiration = pcall(UnitAura, "player", index, filter)
        if not ok or not Present(name) then return false end
        return true, icon, count, duration, expiration
    end
    return false
end

local function Build(player)
    for i = 1, MAX do
        local aura = CreateFrame("Frame", nil, UIParent)
        aura:SetFrameStrata("LOW")
        aura:SetSize(SIZE, SIZE)
        aura.time = ns.Label(aura, "GameFontHighlightSmall")
        aura.time:SetPoint("TOP", aura, "BOTTOM", 0, -1)
        aura.border = ns.Box(aura, "BACKGROUND", 0, 0, 0, 0.8)
        aura.border:ClearAllPoints()
        aura.border:SetPoint("TOPLEFT", -1, 1)
        aura.border:SetPoint("BOTTOMRIGHT", 1, -1)
        aura.icon = aura:CreateTexture(nil, "ARTWORK")
        aura.icon:SetAllPoints()
        aura.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        aura.count = ns.Label(aura, "NumberFontNormalSmall")
        aura.count:SetPoint("BOTTOMRIGHT", 2, -2)
        aura.cooldown = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
        aura.cooldown:SetAllPoints()
        if aura.cooldown.SetReverse then aura.cooldown:SetReverse(true) end
        if aura.cooldown.SetHideCountdownNumbers then aura.cooldown:SetHideCountdownNumbers(true) end
        aura:Hide()
        icons[i] = aura
    end
end

local function UpdateAuras()
    local player = Player()
    if not player then return end
    if #icons == 0 then Build(player) end
    local shown = 0
    if Settings().buffs then
        for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
            local index = 1
            while shown < MAX do
                local present, icon, count, duration, expiration = Aura(index, filter)
                if not present then break end
                shown = shown + 1
                local aura = icons[shown]
                local column, row = (shown - 1) % PER_ROW, math.floor((shown - 1) / PER_ROW)
                aura:ClearAllPoints()
                aura:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() * TOP_X + column * (SIZE + 8), -6 - row * (SIZE + 18))
                aura.ends = expiration
                pcall(aura.icon.SetTexture, aura.icon, icon)
                aura.border:SetVertexColor(filter == "HARMFUL" and 0.8 or 0, 0, 0, 0.9)
                local counted, label = pcall(function() return (count and count > 1) and count or "" end)
                aura.count:SetText(counted and label or "")
                local timed = pcall(function()
                    if duration and duration > 0 and expiration then aura.cooldown:SetCooldown(expiration - duration, duration) else error() end
                end)
                aura.cooldown:SetShown(timed)
                aura:Show()
                index = index + 1
            end
        end
    end
    for i = shown + 1, #icons do icons[i]:Hide() end
    if hit and player then
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() * TOP_X - 4, -2)
        hit:SetSize(math.min(shown, PER_ROW) * (SIZE + 8) + 8, (shown > PER_ROW and 2 or 1) * (SIZE + 18) + 4)
        hit:SetShown(shown > 0)
    end
    FillPanel()
end

local function UpdateXP()
    local player = Player()
    local bar = player and player.xp
    if not bar then return end
    local xp, most = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    if most <= 0 then bar:Hide(); return end
    bar:SetHeight(9)
    bar:SetMinMaxValues(0, most)
    bar:SetValue(xp)
    local rested = GetXPExhaustion and GetXPExhaustion() or nil
    bar:SetStatusBarColor(0.6, 0.3, 0.85)
    bar.text:SetFontObject("NumberFontNormalSmall")
    bar.text:SetText(math.floor(xp * 100 / most) .. ns.T("%") .. ((rested and rested > 0) and ("  " .. ns.T("rested")) or ""))
    bar:Show()
end

local BLIZZARD = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }
local function TuckBlizzard()
    if InCombatLockdown() then return end
    local hide = Settings().buffs
    for _, name in ipairs(BLIZZARD) do
        local frame = _G[name]
        if frame then
            if hide and frame:GetParent() ~= hider then
                homes[name] = frame:GetParent() or UIParent
                frame:SetParent(hider)
            elseif not hide and frame:GetParent() == hider then
                frame:SetParent(homes[name] or UIParent)
            end
        end
    end
end

local PANEL_ROWS = 12

local function AuraDetail(index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local found, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
        if not found or not Present(aura) then return false end
        local ok, name, icon, expiration = pcall(function() return aura.name, aura.icon, aura.expirationTime end)
        if ok then return true, name, icon, expiration end
        return true
    end
    if UnitAura then
        local ok, name, icon, _, _, _, expiration = pcall(UnitAura, "player", index, filter)
        if not ok or not Present(name) then return false end
        return true, name, icon, expiration
    end
    return false
end

FillPanel = function()
    if not panel or not panel:IsShown() then return end
    local row = 0
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local index = 1
        while row < PANEL_ROWS do
            local present, name, icon, expiration = AuraDetail(index, filter)
            if not present then break end
            row = row + 1
            local line = rows[row]
            pcall(line.icon.SetTexture, line.icon, icon)
            pcall(line.name.SetText, line.name, name)
            line.name:SetTextColor(filter == "HARMFUL" and 1 or 1, filter == "HARMFUL" and 0.4 or 0.9, filter == "HARMFUL" and 0.4 or 0.6)
            local timed, left = pcall(function()
                if not expiration or expiration == 0 then return "" end
                return ns.CooldownText(math.max(0, expiration - GetTime()))
            end)
            line.time:SetText(timed and left or "")
            line:Show()
            local cancel = cancels[row]
            if cancel and not InCombatLockdown() then
                cancel:SetAttribute("index", index)
                cancel:SetAttribute("filter", filter)
                cancel:SetShown(filter == "HELPFUL")
            end
            index = index + 1
        end
    end
    for i = row + 1, PANEL_ROWS do
        rows[i]:Hide()
        if cancels[i] and not InCombatLockdown() then cancels[i]:Hide() end
    end
    panel:SetHeight(64 + math.max(row, 1) * 40)
end

local function TogglePanel()
    if panel:IsShown() then
        panel:Hide()
        if not InCombatLockdown() then for _, cancel in ipairs(cancels) do cancel:Hide() end end
        return
    end
    panel:Show()
    FillPanel()
end

local function BuildPanel()
    panel = CreateFrame("Frame", "WolkaraMobileBuffPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(380, 120)
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -UIParent:GetWidth() * 0.18, -100)
    panel:EnableMouse(true)
    ns.Box(panel, "BACKGROUND", 0.04, 0.05, 0.08, 0.95)
    local title = ns.Label(panel, "GameFontNormalLarge", ns.T("Buffs"))
    title:SetPoint("TOPLEFT", 12, -12)
    local hint = ns.Label(panel, "GameFontHighlightSmall", ns.T("Tap a buff to cancel it (out of combat)."))
    hint:SetPoint("TOPLEFT", 12, -34)
    local close = ns.UIButton(panel, "X", 36, 30, TogglePanel)
    close:SetPoint("TOPRIGHT", -6, -6)
    for i = 1, PANEL_ROWS do
        local line = CreateFrame("Frame", nil, panel)
        line:SetSize(356, 36)
        line:SetPoint("TOPLEFT", 12, -56 - (i - 1) * 40)
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(34, 34)
        line.icon:SetPoint("LEFT")
        line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        line.name = ns.Label(line, "GameFontHighlight")
        line.name:SetPoint("LEFT", line.icon, "RIGHT", 10, 0)
        line.name:SetWidth(240); line.name:SetJustifyH("LEFT")
        line.time = ns.Label(line, "GameFontNormal")
        line.time:SetPoint("RIGHT", -4, 0)
        line:Hide()
        rows[i] = line
        local cancel = CreateFrame("Button", "WolkaraMobileBuffCancel" .. i, UIParent, "SecureActionButtonTemplate")
        cancel:SetFrameStrata("FULLSCREEN")
        cancel:SetAllPoints(line)
        cancel:RegisterForClicks("AnyUp")
        cancel:SetAttribute("type", "cancelaura")
        cancel:SetAttribute("unit", "player")
        cancel:HookScript("OnClick", function() if C_Timer and C_Timer.After then C_Timer.After(0.2, FillPanel) end end)
        cancel:Hide()
        cancels[i] = cancel
    end
    panel:Hide()
    local since = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.5 then return end
        since = 0
        FillPanel()
    end)

    local player = Player()
    hit = CreateFrame("Button", "WolkaraMobileBuffsHit", UIParent)
    hit:SetFrameStrata("MEDIUM")
    hit:RegisterForClicks("AnyUp")
    hit:SetScript("OnClick", TogglePanel)
end

function Status:Init() BuildPanel() end

function Status:CombatStarts()
    for _, cancel in ipairs(cancels) do cancel:Hide() end
end

function Status:Layout()
    TuckBlizzard()
    UpdateAuras()
    UpdateXP()
end

function Status:Refresh()
    UpdateAuras()
    UpdateXP()
end

ns.On("UNIT_AURA", function(unit) if unit == "player" and ns.db then UpdateAuras() end end)
ns.On("PLAYER_XP_UPDATE", function() if ns.db then UpdateXP() end end)
ns.On("UPDATE_EXHAUSTION", function() if ns.db then UpdateXP() end end)
ns.On("PLAYER_LEVEL_UP", function() if ns.db then UpdateXP() end end)
ns.On("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    if C_Timer and C_Timer.After then C_Timer.After(1, function() TuckBlizzard(); UpdateAuras(); UpdateXP() end) end
end)

local clock = CreateFrame("Frame")
local tick = 0
clock:SetScript("OnUpdate", function(_, elapsed)
    tick = tick + elapsed
    if tick < 0.5 then return end
    tick = 0
    for _, aura in ipairs(icons) do
        if aura:IsShown() then
            local ok, text = pcall(function()
                if not aura.ends or aura.ends == 0 then return "" end
                return ns.CooldownText(math.max(0, aura.ends - GetTime()))
            end)
            aura.time:SetText(ok and text or "")
        end
    end
end)

local card, badge
local function Short(value)
    if value >= 10000 then return string.format("%.1fk", value / 1000) end
    return tostring(value)
end
local function BarText(fontString, current, most, withPercent)
    local ok, text = pcall(function()
        local line = Short(current) .. " / " .. Short(most)
        if withPercent and most > 0 then line = line .. "   " .. math.floor(current * 100 / most + 0.5) .. "%" end
        return line
    end)
    if ok then fontString:SetText(text); return end
    if pcall(fontString.SetFormattedText, fontString, "%s / %s", current, most) then return end
    fontString:SetText("")
end
local busyName = false
local function Restyle()
    local player = Player()
    if not player then return end
    if not card then
        card = CreateFrame("Frame", nil, player, BackdropTemplateMixin and "BackdropTemplate" or nil)
        card:SetPoint("TOPLEFT", -4, 4)
        card:SetPoint("BOTTOMRIGHT", 4, -12)
        card:SetFrameLevel(player:GetFrameLevel())
        if card.SetBackdrop then
            card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            card:SetBackdropColor(0.04, 0.05, 0.08, 0.82)
            card:SetBackdropBorderColor(0.55, 0.5, 0.4, 0.9)
        end
        for _, region in ipairs({ player:GetRegions() }) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND" then region:SetAlpha(0) end
        end
        if player.portrait then
            badge = CreateFrame("Frame", nil, player.portrait)
            badge:SetSize(24, 24)
            badge:SetPoint("BOTTOMRIGHT", player.portrait, "BOTTOMRIGHT", 5, -3)
            badge:SetFrameLevel(player.portrait:GetFrameLevel() + 5)
            ns.Disc(badge, "ARTWORK", 0.85, 0.65, 0.15, 1, 0)
            badge.text = ns.Label(badge, "GameFontHighlightSmall")
            badge.text:SetPoint("CENTER", 0, 0)
            badge.text:SetTextColor(0.1, 0.07, 0.02)
        end
        if hooksecurefunc then
            local busyText = false
            local function Follow(bar, health)
                if not (bar and bar.text) then return end
                hooksecurefunc(bar.text, "SetText", function()
                    if busyText then return end
                    busyText = true
                    if health then BarText(bar.text, UnitHealth("player"), UnitHealthMax("player"), true)
                    else BarText(bar.text, UnitPower("player"), UnitPowerMax("player"), false) end
                    busyText = false
                end)
            end
            Follow(player.health, true); Follow(player.power, false)
        end
        if player.name and hooksecurefunc then
            hooksecurefunc(player.name, "SetText", function(fontString, text)
                if busyName or type(text) ~= "string" then return end
                local ok, plain = pcall(string.gsub, text, "%s+|cffbbbbbb.-|r$", "")
                if ok and plain ~= text then busyName = true; fontString:SetText(plain); busyName = false end
            end)
        end
    end
    if badge then badge.text:SetText(UnitLevel and UnitLevel("player") or "") end
    if player.health and player.health.text then BarText(player.health.text, UnitHealth("player"), UnitHealthMax("player"), true) end
    if player.power and player.power.text and player.power:IsShown() then BarText(player.power.text, UnitPower("player"), UnitPowerMax("player"), false) end
end

local baseLayout = Status.Layout
function Status:Layout() baseLayout(self); Restyle() end
local baseRefresh = Status.Refresh
function Status:Refresh() baseRefresh(self); Restyle() end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    ns.On(event, function(unit) if unit == "player" and ns.db then Restyle() end end)
end
ns.On("PLAYER_LEVEL_UP", function() if ns.db then Restyle() end end)

local targetPortrait, targetBadge
local busyTarget = false
local function Target() return _G.WolkaraMobileTarget end

local function TargetLevel()
    local level = UnitLevel and UnitLevel("target") or 0
    local kind = UnitClassification and UnitClassification("target") or "normal"
    local text = (level and level > 0) and tostring(level) or "??"
    if kind == "elite" or kind == "rareelite" then text = text .. "+" end
    local color = (level and level > 0) and (GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
        or GetQuestDifficultyColor and GetQuestDifficultyColor(level)) or { r = 1, g = 0.1, b = 0.1 }
    return text, color or { r = 1, g = 0.82, b = 0 }
end

local function TargetNameColor()
    if UnitIsPlayer and UnitIsPlayer("target") then
        local _, class = UnitClass("target")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
    end
    local reaction = UnitReaction and UnitReaction("target", "player")
    if reaction and reaction <= 3 then return 1, 0.25, 0.2 end
    if reaction == 4 then return 1, 0.85, 0.2 end
    return 0.35, 1, 0.35
end

local auraRow, auraIcons = nil, {}
local MAX_DEBUFFS, MAX_BUFFS, DEBUFF_SIZE, BUFF_SIZE = 8, 4, 30, 22
local DISPEL_COLORS = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }
local auraHider = CreateFrame("Frame")
auraHider:Hide()

local function AuraIcon(size)
    local icon = CreateFrame("Frame", nil, auraRow)
    icon:SetSize(size, size)
    icon.ring = ns.Disc(icon, "BACKGROUND", 0.4, 0.1, 0.1, 1, 2)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(icon, icon.texture)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    if icon.cooldown.SetReverse then icon.cooldown:SetReverse(true) end
    pcall(icon.cooldown.SetSwipeTexture, icon.cooldown, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    pcall(icon.cooldown.SetUseCircularEdge, icon.cooldown, true)
    icon.count = ns.Label(icon, "NumberFontNormalSmall")
    icon.count:SetPoint("BOTTOMRIGHT", 3, -2)
    icon:Hide()
    return icon
end

local function ReadAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or not Present(aura) then return nil, false end
        return aura, true
    end
    if UnitAura then
        local ok, name, texture, count, kind, duration, expiration, source = pcall(UnitAura, unit, index, filter)
        if not ok or not Present(name) then return nil, false end
        return { icon = texture, applications = count, dispelName = kind, duration = duration,
            expirationTime = expiration, isFromPlayerOrPlayerPet = source == "player" or source == "pet" }, true
    end
    return nil, false
end

local function ShowAura(icon, aura, harmful)
    if not pcall(function() icon.texture:SetTexture(aura.icon) end) then icon.texture:SetTexture(nil) end
    local counted = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
        and pcall(function() icon.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("target", aura.auraInstanceID, 2, 99)) end)
    if not counted then
        local ok, label = pcall(function() return (aura.applications and aura.applications > 1) and aura.applications or "" end)
        icon.count:SetText(ok and label or "")
    end
    local timed = C_UnitAuras and C_UnitAuras.GetAuraDuration and icon.cooldown.SetCooldownFromDurationObject
        and pcall(function() icon.cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration("target", aura.auraInstanceID)) end)
    timed = timed or pcall(function()
        if aura.duration and aura.duration > 0 and aura.expirationTime then
            icon.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
        else
            error()
        end
    end)
    icon.cooldown:SetShown(timed)
    local mine = pcall(function() if aura.isFromPlayerOrPlayerPet ~= true then error() end end)
    local known, kind = pcall(function() return DISPEL_COLORS[aura.dispelName] end)
    local color = (harmful and mine) and { 1, 0.82, 0.29 } or (known and kind) or (harmful and { 0.4, 0.1, 0.1 } or { 0.54, 0.43, 0.23 })
    icon.ring:SetVertexColor(color[1], color[2], color[3], 1)
    icon:Show()
end

local function UpdateTargetAuras()
    if not auraRow then return end
    local shown, x = 0, 0
    local function fill(filter, limit, size, harmful)
        local count, index = 0, 1
        while count < limit and index <= 40 do
            local aura, present = ReadAura("target", index, filter)
            if not present then break end
            shown = shown + 1
            local icon = auraIcons[shown]
            if not icon or icon.size ~= size then
                if icon then icon:Hide() end
                icon = AuraIcon(size); icon.size = size; auraIcons[shown] = icon
            end
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", auraRow, "TOPLEFT", x, harmful and 0 or -(DEBUFF_SIZE - BUFF_SIZE) / 2)
            ShowAura(icon, aura, harmful)
            x = x + size + 4
            count = count + 1
            index = index + 1
        end
    end
    if UnitExists and UnitExists("target") then
        fill("HARMFUL", MAX_DEBUFFS, DEBUFF_SIZE, true)
        if shown > 0 then x = x + 6 end
        fill("HELPFUL", MAX_BUFFS, BUFF_SIZE, false)
    end
    for i = shown + 1, #auraIcons do auraIcons[i]:Hide() end
end

local function RestyleTarget()
    local target = Target()
    if not target then return end
    if not targetPortrait then
        if InCombatLockdown() then return end
        target:SetWidth(380)
        auraRow = CreateFrame("Frame", nil, target)
        auraRow:SetSize(380 - 62, DEBUFF_SIZE)
        auraRow:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 62, -6)
        for _, aura in ipairs(target.auras or {}) do aura:SetParent(auraHider) end
        targetPortrait = CreateFrame("Frame", nil, target)
        targetPortrait:SetSize(52, 52)
        targetPortrait:SetPoint("LEFT", target, "LEFT", 3, 0)
        targetPortrait:SetFrameLevel(target:GetFrameLevel() + 3)
        ns.Disc(targetPortrait, "BACKGROUND", 0.05, 0.05, 0.08, 0.9, 2)
        local ring = ns.Disc(targetPortrait, "BACKGROUND", 0.54, 0.43, 0.23, 1, 4)
        ring:SetDrawLayer("BACKGROUND", -7)
        targetPortrait.texture = targetPortrait:CreateTexture(nil, "ARTWORK")
        targetPortrait.texture:SetAllPoints()
        ns.Circle(targetPortrait, targetPortrait.texture)
        targetBadge = CreateFrame("Frame", nil, targetPortrait)
        targetBadge:SetSize(24, 24)
        targetBadge:SetPoint("BOTTOMRIGHT", targetPortrait, "BOTTOMRIGHT", 6, -4)
        targetBadge:SetFrameLevel(targetPortrait:GetFrameLevel() + 3)
        targetBadge.disc = ns.Disc(targetBadge, "ARTWORK", 0.12, 0.1, 0.08, 1, 0)
        targetBadge.text = ns.Label(targetBadge, "GameFontHighlightSmall")
        targetBadge.text:SetPoint("CENTER", 0, 0)
        target.name:ClearAllPoints()
        target.name:SetPoint("TOPLEFT", 64, -3)
        target.name:SetPoint("TOPRIGHT", -24, -3)
        target.health:ClearAllPoints()
        target.health:SetPoint("TOPLEFT", 62, -20)
        target.health:SetPoint("TOPRIGHT", -6, -20)
        if hooksecurefunc then
            hooksecurefunc(target.name, "SetText", function(fontString, text)
                if busyTarget or type(text) ~= "string" then return end
                busyTarget = true
                local ok, plain = pcall(string.gsub, text, "%s+|cffbbbbbb.-|r$", "")
                if ok then fontString:SetText(plain) end
                fontString:SetTextColor(TargetNameColor())
                busyTarget = false
            end)
            hooksecurefunc(target.health.text, "SetText", function()
                if busyTarget then return end
                busyTarget = true
                BarText(target.health.text, UnitHealth("target"), UnitHealthMax("target"), true)
                busyTarget = false
            end)
        end
    end
    if not (UnitExists and UnitExists("target")) then return end
    if SetPortraitTexture then SetPortraitTexture(targetPortrait.texture, "target") end
    local text, color = TargetLevel()
    targetBadge.text:SetText(text)
    targetBadge.text:SetTextColor(color.r or 1, color.g or 0.82, color.b or 0)
    target.name:SetTextColor(TargetNameColor())
    busyTarget = true
    BarText(target.health.text, UnitHealth("target"), UnitHealthMax("target"), true)
    busyTarget = false
end

local layoutWithTarget = Status.Layout
function Status:Layout() layoutWithTarget(self); if not InCombatLockdown() or targetPortrait then RestyleTarget() end end
ns.On("PLAYER_TARGET_CHANGED", function() if ns.db then RestyleTarget() end end)
ns.On("UNIT_PORTRAIT_UPDATE", function(unit) if unit == "target" and ns.db then RestyleTarget() end end)
ns.On("UNIT_HEALTH", function(unit) if unit == "target" and ns.db and targetPortrait then RestyleTarget() end end)

ns.On("UNIT_AURA", function(unit) if unit == "target" and ns.db then UpdateTargetAuras() end end)
ns.On("PLAYER_TARGET_CHANGED", function() if ns.db then UpdateTargetAuras() end end)
