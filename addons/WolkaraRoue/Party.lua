-- Party frames (iPhone Duo layout).
local _, ns = ...

local Party = ns.Register("Party", {})
ns.Party = Party

local MAX, W, H, GAP = 4, 230, 38, 6
local frames = {}
local grouped, restorePending = false, false

local function Short(value)
    if value >= 10000 then return string.format("%.1fk", value / 1000) end
    return tostring(value)
end

local function Update(frame)
    local unit = frame.unit
    if not UnitExists(unit) then return end
    local name = UnitName(unit) or ""
    frame.name:SetText(name)
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then frame.name:SetTextColor(color.r, color.g, color.b) else frame.name:SetTextColor(1, 0.82, 0.29) end
    local health, most = UnitHealth(unit), UnitHealthMax(unit)
    if not pcall(frame.health.SetMinMaxValues, frame.health, 0, most) then frame.health:SetMinMaxValues(0, 1) end
    pcall(frame.health.SetValue, frame.health, health)
    local state
    if UnitIsConnected and not UnitIsConnected(unit) then state = ns.T("Offline")
    elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then state = ns.T("Dead") end
    if state then
        frame.status:SetText(state)
    else
        local ok, text = pcall(function() return math.floor(health * 100 / most + 0.5) .. "%" end)
        if not ok and UnitHealthPercent then
            ok = pcall(frame.status.SetFormattedText, frame.status, "%d%%", UnitHealthPercent(unit, true, CurveConstants and CurveConstants.ScaleTo100))
            text = nil
        end
        if text then frame.status:SetText(text) elseif not ok then frame.status:SetText("") end
    end
    local power, powerMost = UnitPower(unit), UnitPowerMax(unit)
    if not pcall(frame.power.SetMinMaxValues, frame.power, 0, powerMost) then frame.power:SetMinMaxValues(0, 1) end
    pcall(frame.power.SetValue, frame.power, power)
    local pcolor = PowerBarColor and PowerBarColor[UnitPowerType(unit)]
    if pcolor then frame.power:SetStatusBarColor(pcolor.r, pcolor.g, pcolor.b) end
    frame:SetAlpha((state == ns.T("Offline")) and 0.55 or 1)
end

local function Bar(parent, height, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b)
    bar:SetHeight(height)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.5)
    return bar
end

function Party:Init()
    for i = 1, MAX do
        local frame = CreateFrame("Button", "WolkaraMobileParty" .. i, UIParent, "SecureUnitButtonTemplate")
        frame:SetSize(W, H)
        frame:SetFrameStrata("LOW")
        frame:RegisterForClicks("AnyUp")
        frame.unit = "party" .. i
        frame:SetAttribute("unit", frame.unit)
        frame:SetAttribute("type1", "target")
        frame.name = ns.Label(frame, "GameFontNormalSmall")
        frame.name:SetPoint("TOPLEFT", 8, -5)
        frame.name:SetPoint("TOPRIGHT", -48, -5)
        frame.name:SetJustifyH("LEFT")
        frame.status = ns.Label(frame, "GameFontHighlightSmall")
        frame.status:SetPoint("TOPRIGHT", -8, -5)
        frame.health = Bar(frame, 12, 0.18, 0.62, 0.2)
        frame.health:SetPoint("TOPLEFT", 6, -19)
        frame.health:SetPoint("TOPRIGHT", -6, -19)
        frame.power = Bar(frame, 4, 0.2, 0.35, 0.9)
        frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -2)
        frame.power:SetPoint("TOPRIGHT", frame.health, "BOTTOMRIGHT", 0, -2)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        frame:Hide()
        frames[i] = frame
    end
end

local function QuestCard() return _G.WolkaraMobileQuests end

local function MakeRoom(on)
    local quests = ns.db and ns.db.quests
    if type(quests) ~= "table" then return end
    if on and not grouped then
        grouped = true
        quests.collapsedBeforeParty = quests.collapsed and true or false
        quests.collapsed = true
        ns.Refresh()
    elseif not on and (grouped or quests.collapsedBeforeParty ~= nil) then
        local wasGrouped = grouped
        grouped = false
        quests.collapsed = quests.collapsedBeforeParty and true or false
        quests.collapsedBeforeParty = nil
        ns.Refresh()
        if wasGrouped then
            if InCombatLockdown() then restorePending = true else ns.Layout() end
        end
        return
    end
    if grouped then
        local card, player = QuestCard(), _G.WolkaraMobilePlayer
        if card and player then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", player, "TOPRIGHT", 14, 0)
        end
    end
end

local function InParty()
    if IsInRaid and IsInRaid() then return GetNumGroupMembers and GetNumGroupMembers() > 0 end
    return (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) > 0
end

function Party:Layout()
    if not frames[1] or InCombatLockdown() then return end
    local on = ns.DuoLayout() and ns.db.hud and ns.db.hud.enabled ~= false and ns.db.partyFrames ~= false
    local player = _G.WolkaraMobilePlayer
    for i, frame in ipairs(frames) do
        if on then
            frame:ClearAllPoints()
            if i == 1 then
                frame:SetPoint("TOPLEFT", player or UIParent, player and "BOTTOMLEFT" or "TOPLEFT", 0, player and -18 or -90)
            else
                frame:SetPoint("TOPLEFT", frames[i - 1], "BOTTOMLEFT", 0, -GAP)
            end
            RegisterUnitWatch(frame)
        else
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
    end
    MakeRoom(on and InParty())
    self:Refresh()
end

function Party:Refresh()
    for _, frame in ipairs(frames) do if frame:IsShown() then Update(frame) end end
end

local function Changed(unit)
    if not ns.db then return end
    for _, frame in ipairs(frames) do
        if frame.unit == unit and frame:IsShown() then Update(frame) end
    end
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_FLAGS" }) do
    ns.On(event, Changed)
end
ns.On("GROUP_ROSTER_UPDATE", function()
    if not ns.db or not ns.DuoLayout() then return end
    MakeRoom(InParty())
    Party:Refresh()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if restorePending then restorePending = false; ns.Layout() end
end)
