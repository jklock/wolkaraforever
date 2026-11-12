-- Mobile UI settings window.
local _, ns = ...

local Controls = ns.Register("Controls", {})
ns.Controls = Controls

local CREDITS = "Duo UI by scarrdi94  ·  built on Mobile Interface by pookee  ·  WolkaraForever by jklock"
local NAV_W, ROW_H, X1, X2, X3 = 150, 44, 0, 150, 330

local panel
local pages, navButtons, updaters = {}, {}, {}
local current

local function Apply()
    if InCombatLockdown() then ns.Print(ns.T("adjust the interface out of combat.")); return false end
    ns.MarkChanged()
    ns.Layout()
    ns.Refresh()
    for _, update in ipairs(updaters) do update() end
    return true
end

local function Text(page, text, x, y, template)
    local label = ns.Label(page, template or "GameFontHighlight", text)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    return label
end

local function Switch(page, x, y, get, set, onText, offText, width)
    local button = ns.UIButton(page, "", width or 90, 32, function()
        if InCombatLockdown() then return Apply() end
        set(not get()); Apply()
    end)
    button:SetPoint("TOPLEFT", x, y)
    updaters[#updaters + 1] = function()
        local on = get()
        button.text:SetText(on and (onText or ns.T("On")) or (offText or ns.T("Off")))
        button.back:SetVertexColor(on and 0.2 or 0.18, on and 0.45 or 0.18, on and 0.25 or 0.22, 0.95)
    end
    return button
end

local function Stepper(page, x, y, get, set, step, low, high, suffix)
    local minus = ns.UIButton(page, "-", 34, 32, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() - step, low, high)); Apply()
    end)
    minus:SetPoint("TOPLEFT", x, y)
    local value = ns.Label(page, "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(54)
    local plus = ns.UIButton(page, "+", 34, 32, function()
        if InCombatLockdown() then return Apply() end
        set(ns.Clamp(get() + step, low, high)); Apply()
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    updaters[#updaters + 1] = function() value:SetText(get() .. (suffix or "")) end
end

local function Button(page, x, y, text, width, onClick)
    local button = ns.UIButton(page, text, width, 32, onClick)
    button:SetPoint("TOPLEFT", x, y)
    return button
end

local function Row(page, y, caption)
    Text(page, caption, X1, y - 8)
    return y - ROW_H
end

local function Show(name)
    current = name
    for key, page in pairs(pages) do page:SetShown(key == name) end
    for key, button in pairs(navButtons) do
        button.back:SetVertexColor(key == name and 0.85 or 0.18, key == name and 0.68 or 0.18, key == name and 0.3 or 0.22, 0.95)
    end
end

local function Page(name, label, index)
    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", NAV_W + 40, -70)
    page:SetPoint("BOTTOMRIGHT", -20, 60)
    page:Hide()
    pages[name] = page
    local nav = ns.UIButton(panel, label, NAV_W - 10, 36, function() Show(name) end)
    nav:SetPoint("TOPLEFT", 20, -70 - (index - 1) * 42)
    navButtons[name] = nav
    return page
end

local function General(page)
    local y = 0
    y = Row(page, y, ns.T("Layout"))
    Switch(page, X2, y + ROW_H, function() return ns.DuoLayout() end,
        function(v) ns.db.layout = v and "duo" or "standard" end, "iPhone Duo", ns.T("Standard"), 150)
    y = Row(page, y, ns.T("Language"))
    local language = Button(page, X2, y + ROW_H, "", 150, function()
        if InCombatLockdown() then return Apply() end
        ns.NextLanguage(); Apply()
    end)
    updaters[#updaters + 1] = function() language.text:SetText(ns.LanguageName()) end
    y = Row(page, y, ns.T("Interface size"))
    Stepper(page, X2, y + ROW_H, function() return ns.db.ui.scale end, function(v) ns.db.ui.scale = v end, 10, 100, 220, ns.T("%"))
    y = Row(page, y, ns.T("Windows"))
    Switch(page, X2, y + ROW_H, function() return ns.Placement and ns.Placement.Settings().size == "large" end,
        function(v) if ns.Placement then ns.Placement.Settings().size = v and "large" or "fit" end end, ns.T("Large"), ns.T("Fit"), 150)
    y = Row(page, y, ns.T("Positions"))
    Button(page, X2, y + ROW_H, ns.T("Customize"), 150, function() panel:Hide(); ns.SetEditing(true) end)
    Button(page, X3, y + ROW_H, ns.T("Reset positions"), 180, function()
        if InCombatLockdown() then return Apply() end
        ns.ClearPositions(ns.db)
        ns.db.quests.pos = nil
        Apply()
    end)
    y = Row(page, y, ns.T("Tips"))
    Button(page, X2, y + ROW_H, ns.T("Show tips"), 150, function() panel:Hide(); if ns.ShowTips then ns.ShowTips() end end)
end

local function Combat(page)
    local function fan() return ns.Fan.Settings() end
    local function quick() return ns.Quick.Settings() end
    local y = 0
    y = Row(page, y, ns.T("Skill fan"))
    Switch(page, X2, y + ROW_H, function() return fan().enabled end, function(v) fan().enabled = v end)
    Stepper(page, X2 + 100, y + ROW_H, function() return fan().size end, function(v) fan().size = v end, 4, 40, 80)
    y = Row(page, y, ns.T("Reach"))
    Stepper(page, X2, y + ROW_H, function() return fan().radius end, function(v) fan().radius = v end, 2, 22, 50, "%")
    y = Row(page, y, ns.T("Fan style"))
    Switch(page, X2, y + ROW_H, function() return fan().style == "wheel" end,
        function(v) fan().style = v and "wheel" or "pages" end, ns.T("Wheel"), ns.T("Pages"), 120)
    y = Row(page, y, ns.T("Quick bar"))
    Switch(page, X2, y + ROW_H, function() return quick().enabled end, function(v) quick().enabled = v end)
    Stepper(page, X2 + 100, y + ROW_H, function() return quick().count end, function(v) quick().count = v end, 1, 3, 5)
    y = Row(page, y, ns.T("Buffs"))
    Switch(page, X2, y + ROW_H, function() return ns.Status and ns.Status.Settings().buffs end,
        function(v) if ns.Status then ns.Status.Settings().buffs = v end end, ns.T("On bar"), ns.T("Game's"), 120)
    y = Row(page, y, ns.T("Presets"))
    for slot = 1, 3 do
        Button(page, X2 + (slot - 1) * 90, y + ROW_H, ns.T("Load") .. " " .. slot, 84, function() if ns.LoadPreset then ns.LoadPreset(slot) end end)
        Button(page, X2 + (slot - 1) * 90, y + 4, ns.T("Save") .. " " .. slot, 84, function() if ns.SavePreset then ns.SavePreset(slot) end; Apply() end)
    end
end

local function Frames(page)
    local y = 0
    y = Row(page, y, ns.T("Health bars"))
    Switch(page, X2, y + ROW_H, function() return ns.db.hud.enabled end, function(v) ns.db.hud.enabled = v end)
    Stepper(page, X2 + 100, y + ROW_H, function() return ns.db.hud.scale end, function(v) ns.db.hud.scale = v end, 10, 50, 200, ns.T("%"))
    y = Row(page, y, ns.T("Party frames"))
    Switch(page, X2, y + ROW_H, function() return ns.db.partyFrames ~= false end, function(v) ns.db.partyFrames = v end)
    y = Row(page, y, ns.T("Quests"))
    Switch(page, X2, y + ROW_H, function() return ns.db.quests.enabled end, function(v) ns.db.quests.enabled = v end, ns.T("Mobile"), ns.T("Game"))
    Stepper(page, X2 + 100, y + ROW_H, function() return ns.db.quests.shown end, function(v) ns.db.quests.shown = v end, 1, 1, 5)
    y = Row(page, y, ns.T("Minimap"))
    Switch(page, X2, y + ROW_H, function() return ns.db.minimap.shown end, function(v) ns.db.minimap.shown = v end)
    Stepper(page, X2 + 100, y + ROW_H, function() return ns.db.minimap.scale end, function(v) ns.db.minimap.scale = v end, 10, 30, 150, ns.T("%"))
    y = Row(page, y, ns.T("Action bars"))
    Switch(page, X2, y + ROW_H, function() return not ns.db.blizzard.hideBars end,
        function(v) ns.db.blizzard.hideBars = not v end, ns.T("Shown"), ns.T("Hidden"), 120)
    y = Row(page, y, ns.T("Player/target frames"))
    Switch(page, X2, y + ROW_H, function() return not ns.db.blizzard.hideUnitFrames end,
        function(v) ns.db.blizzard.hideUnitFrames = not v end, ns.T("Shown"), ns.T("Hidden"), 120)
end

local function Chat(page)
    local y = 0
    y = Row(page, y, ns.T("Chat"))
    Switch(page, X2, y + ROW_H, function() return ns.db.chat.custom end, function(v) ns.db.chat.custom = v end, ns.T("Mobile"), ns.T("Game"))
    y = Row(page, y, ns.T("Text"))
    Stepper(page, X2, y + ROW_H, function() return ns.db.chat.fontSize end, function(v) ns.db.chat.fontSize = v end, 1, 10, 26)
    y = Row(page, y, ns.T("Chat button"))
    Switch(page, X2, y + ROW_H, function() return ns.ChatTab and ns.ChatTab.Settings().enabled end,
        function(v) if ns.ChatTab then ns.ChatTab.Settings().enabled = v end end, ns.T("Button"), ns.T("Strip"), 120)
end

local function Wheels(page)
    local y = 0
    Text(page, ns.T("Used by the Standard layout."), X1, y, "GameFontHighlightSmall")
    y = y - 28
    for index = 1, ns.MAX_WHEELS do
        local function wheel() return ns.db.wheels[index] end
        y = Row(page, y, index == 1 and ns.T("Wheel") or (ns.T("Wheel ") .. index))
        Switch(page, X2, y + ROW_H, function() return wheel().enabled end, function(v) wheel().enabled = v end, nil, nil, 70)
        Stepper(page, X2 + 80, y + ROW_H, function() return wheel().slots end, function(v) wheel().slots = v end, 1, 4, ns.MAX_SLOTS)
        Switch(page, X2 + 230, y + ROW_H, function() return wheel().open ~= "centre" end,
            function(v) wheel().open = v and "bouton" or "centre" end, ns.T("At button"), ns.T("Centered"), 110)
    end
    for _, side in ipairs({ { key = "free", label = ns.T("Right spells") }, { key = "freeLeft", label = ns.T("Left spells") } }) do
        y = Row(page, y, side.label)
        Stepper(page, X2, y + ROW_H, function() return ns.db[side.key].count end, function(v) ns.db[side.key].count = v end, 1, 0, ns.MAX_FREE)
        Switch(page, X2 + 150, y + ROW_H, function() return ns.db[side.key].turn end, function(v) ns.db[side.key].turn = v end, ns.T("Wheel"), "Arc", 90)
    end
    y = Row(page, y, ns.T("Shortcuts"))
    Switch(page, X2, y + ROW_H, function() return ns.db.shortcuts.enabled end, function(v) ns.db.shortcuts.enabled = v end)
end

local function Build()
    panel = CreateFrame("Frame", "WolkaraMobileControls", UIParent)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetSize(720, 520)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.07, 0.06, 0.05, 0.95)
    local title = ns.Label(panel, "GameFontNormalLarge", ns.T("Mobile UI"))
    title:SetPoint("TOP", 0, -20)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.79, 0.64, 0.36, 0.7)
    divider:SetSize(360, 1)
    divider:SetPoint("TOP", 0, -46)
    local close = ns.UIButton(panel, "X", 34, 30, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    -- Fermer écrit ce qui attend, sur le toucher lui-même (un /reload ne part pas d'une
    -- minuterie : mesuré sur l'iPhone, 2026-11-09).
    if ns.SaveOver then ns.SaveOver(close, function() panel:Hide() end) end

    General(Page("general", ns.T("General"), 1))
    Combat(Page("combat", ns.T("Combat"), 2))
    Frames(Page("frames", ns.T("Frames"), 3))
    Chat(Page("chat", ns.T("Chat"), 4))
    Wheels(Page("wheels", ns.T("Spell wheels"), 5))

    local credits = ns.Label(panel, "GameFontHighlightSmall", CREDITS)
    credits:SetPoint("BOTTOMLEFT", 24, 22)
    credits:SetTextColor(0.61, 0.57, 0.51)
    local done = ns.UIButton(panel, ns.T("Close"), 110, 34, function() panel:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -20, 14)
    if ns.SaveOver then ns.SaveOver(done, function() panel:Hide() end) end
    Show("general")
end

function Controls:Init()
    Build()
    if ns.Settings then
        function ns.Settings:Toggle() Controls:Toggle() end
        function ns.Settings:IsOpen() return panel ~= nil and panel:IsShown() end
    end
end

function Controls:Toggle(page)
    if not panel then return end
    if panel:IsShown() and not page then panel:Hide(); return end
    if InCombatLockdown() then ns.Print(ns.T("adjust the interface out of combat.")); return end
    for _, update in ipairs(updaters) do update() end
    if page then Show(page) end
    panel:SetScale(1)
    panel:SetScale(math.min(1, (UIParent:GetWidth() - 16) / panel:GetWidth(), (UIParent:GetHeight() - 16) / panel:GetHeight()))
    panel:Show()
end

function Controls:CombatStarts() if panel then panel:Hide() end end

local slash = SlashCmdList.WOLKARAMOBILE
SlashCmdList.WOLKARAMOBILE = function(message)
    if (message or ""):lower():match("^%s*controls%s*$") and ns.db then return Controls:Toggle("combat") end
    return slash(message)
end
