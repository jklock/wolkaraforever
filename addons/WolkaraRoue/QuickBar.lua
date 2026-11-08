-- Collapsible quick bar on the left edge (iPhone Duo layout).
local _, ns = ...

local Quick = ns.Register("Quick bar", {})
ns.Quick = Quick

local PAGES, MAX_SLOTS = 5, 5
local TOP = 0.40
local EDGE = 6
local TAB_W, TAB_H = 24, 52
local GAP = 8

local container, handle, pager
local holders, slots = {}, {}

local DEFAULTS = { enabled = true, count = 5, size = 46, open = true, seeded = false, page = 1 }

local function Settings()
    local db = ns.db
    if type(db.quick) ~= "table" then db.quick = {} end
    local quick = db.quick
    for key, value in pairs(DEFAULTS) do
        if quick[key] == nil then quick[key] = value end
    end
    if type(quick.pages) ~= "table" then
        quick.pages = {}
        if type(quick.entries) == "table" then quick.pages[1] = quick.entries end
    end
    for page = 1, PAGES do
        if type(quick.pages[page]) ~= "table" then quick.pages[page] = {} end
    end
    quick.entries = nil
    quick.count = ns.Clamp(math.floor(tonumber(quick.count) or 4), 3, MAX_SLOTS)
    quick.size = ns.Clamp(tonumber(quick.size) or 46, 36, 64)
    quick.page = ns.Clamp(math.floor(tonumber(quick.page) or 1), 1, PAGES)
    if not quick.fiveSlots then
        quick.fiveSlots = true
        if quick.count == 4 then quick.count = 5 end
    end
    return quick
end

Quick.Settings = function() return Settings() end

function Quick:Enabled()
    return ns.DuoLayout() and type(ns.db.quick) == "table" and ns.db.quick.enabled == true
end

local function Seed(quick)
    if quick.seeded then return end
    quick.seeded = true
    local source = ns.db.freeLeft and ns.db.freeLeft.buttons
    if type(source) ~= "table" then return end
    local slot = 1
    for index = 1, ns.MAX_FREE do
        local stored = source[index]
        if slot > MAX_SLOTS then break end
        if type(stored) == "table" and type(stored.entry) == "table" and stored.entry.kind then
            local entry = {}
            for key, value in pairs(stored.entry) do entry[key] = value end
            quick.pages[1][slot] = entry
            slot = slot + 1
        end
    end
end

local function Arrow(open)
    return open and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
end

function Quick:Init()
    local quick = Settings()
    Seed(quick)

    container = CreateFrame("Frame", "WolkaraMobileQuick", UIParent, "SecureHandlerBaseTemplate")
    container:SetFrameStrata("LOW")
    container:SetSize(2, 2)
    container:SetPoint("TOPLEFT")
    container:Hide()
    for page = 1, PAGES do
        local holder = CreateFrame("Frame", "WolkaraMobileQuickPage" .. page, container, "SecureHandlerBaseTemplate")
        holder:SetAllPoints(container)
        holders[page] = holder
        slots[page] = {}
        for index = 1, MAX_SLOTS do
            local button = ns.CreateActionButton("WolkaraMobileQuick" .. page .. "Slot" .. index, holder, quick.size,
                function() return Settings().pages[page][index] end,
                function(entry) Settings().pages[page][index] = entry end)
            button:SetAttribute("useOnKeyDown", true)
            slots[page][index] = button
        end
    end

    pager = CreateFrame("Button", "WolkaraMobileQuickPager", container, "SecureHandlerClickTemplate")
    pager:RegisterForClicks("AnyDown")
    for page = 1, PAGES do pager:SetFrameRef("page" .. page, holders[page]) end
    pager:SetAttribute("_onclick", [=[
        local page = (self:GetAttribute("page") or 1) % 5 + 1
        self:SetAttribute("page", page)
        for index = 1, 5 do
            local holder = self:GetFrameRef("page" .. index)
            if index == page then holder:Show() else holder:Hide() end
        end
    ]=])
    ns.Box(pager, "BACKGROUND", 0.05, 0.05, 0.08, 0.75)
    pager.label = ns.Label(pager, "GameFontNormalSmall")
    pager.label:SetPoint("CENTER")
    local pagerHighlight = ns.Box(pager, "HIGHLIGHT", 1, 1, 1, 0.15)
    pagerHighlight:SetBlendMode("ADD")
    pager:HookScript("OnClick", function(self)
        local page = self:GetAttribute("page") or 1
        self.label:SetText(page .. "/" .. PAGES)
        if ns.db and type(ns.db.quick) == "table" then ns.db.quick.page = page end
    end)

    handle = CreateFrame("Button", "WolkaraMobileQuickTab", UIParent, "SecureHandlerClickTemplate")
    handle:SetFrameStrata("LOW")
    handle:RegisterForClicks("AnyUp")
    handle:SetFrameRef("container", container)
    handle:SetAttribute("_onclick", [=[
        if self:GetAttribute("held") then self:SetAttribute("held", nil); return end
        local container = self:GetFrameRef("container")
        if container:IsShown() then container:Hide(); self:SetAttribute("open", false)
        else container:Show(); self:SetAttribute("open", true) end
    ]=])
    ns.Box(handle, "BACKGROUND", 0.05, 0.05, 0.08, 0.75)
    handle.arrow = handle:CreateTexture(nil, "ARTWORK")
    handle.arrow:SetSize(22, 22)
    handle.arrow:SetPoint("CENTER", 0, 0)
    local highlight = ns.Box(handle, "HIGHLIGHT", 1, 1, 1, 0.15)
    highlight:SetBlendMode("ADD")
    handle:HookScript("OnClick", function(self)
        local open = self:GetAttribute("open") and true or false
        self.arrow:SetTexture(Arrow(open))
        if ns.db and type(ns.db.quick) == "table" then ns.db.quick.open = open end
    end)
    handle:Hide()
end

local function HideLeft()
    for index = 1, ns.MAX_FREE do
        local button = _G["WolkaraMobileFreeLeft" .. index]
        if button then button:Hide() end
    end
end

function Quick:Layout()
    if not container or InCombatLockdown() then return end
    local quick = Settings()
    if not quick.enabled or not ns.DuoLayout() then container:Hide(); handle:Hide(); return end

    local top = UIParent:GetHeight() * TOP
    local size = quick.size
    local pagerHeight = math.floor(size * 0.55)
    local x = EDGE + TAB_W + 6
    local first = top + pagerHeight + GAP
    local height = pagerHeight + GAP + quick.count * size + (quick.count - 1) * GAP

    pager:ClearAllPoints()
    pager:SetSize(size, pagerHeight)
    pager:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -top)
    pager:SetHitRectInsets(-4, -4, -4, -4)
    pager:SetAttribute("page", quick.page)
    pager.label:SetText(quick.page .. "/" .. PAGES)

    handle:ClearAllPoints()
    handle:SetSize(TAB_W, TAB_H)
    handle:SetHitRectInsets(-6, -8, -10, -10)
    handle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", EDGE, -(top + (height - TAB_H) / 2))

    for page = 1, PAGES do
        for index, button in ipairs(slots[page]) do
            button:ClearAllPoints()
            if index <= quick.count then
                button:SetSize(size, size)
                button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -(first + (index - 1) * (size + GAP)))
                local extra = math.floor(GAP / 2)
                button:SetHitRectInsets(-extra, -extra, -extra, -extra)
                button:Show()
            else
                button:Hide()
            end
            ns.ApplyButton(button)
        end
        holders[page]:SetShown(page == quick.page)
    end
    handle:SetAttribute("open", quick.open)
    handle.arrow:SetTexture(Arrow(quick.open))
    container:SetShown(quick.open)
    handle:Show()
    HideLeft()
    self:Refresh()
end

function Quick:Refresh()
    if not container then return end
    local count = ns.db and ns.db.quick and ns.db.quick.count or 4
    for page = 1, PAGES do
        for index, button in ipairs(slots[page]) do
            if index <= count then
                ns.RefreshButton(button)
                button:SetAlpha((button:GetEntry() or ns.editing or ns.slotEditing) and 1 or 0.45)
            end
        end
    end
end

function Quick:SetEditing() self:Refresh() end

function Quick:CombatStarts()
    for page = 1, PAGES do
        for _, button in ipairs(slots[page]) do
            if button.suppressed then ns.ApplyButton(button) end
        end
    end
end

local function Each(fn)
    for page = 1, PAGES do
        for _, button in ipairs(slots[page]) do fn(button) end
    end
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.3 or not container or not container:IsShown() then return end
    since = 0
    for page = 1, PAGES do
        if holders[page]:IsShown() then
            for _, button in ipairs(slots[page]) do if button:IsShown() then ns.UpdateState(button) end end
        end
    end
end)

ns.On("SPELL_UPDATE_COOLDOWN", function() if container and ns.db then Each(ns.UpdateCooldown) end end)
ns.On("BAG_UPDATE_COOLDOWN", function() if container and ns.db then Each(ns.UpdateCooldown) end end)
ns.On("BAG_UPDATE", function() if container and ns.db then Quick:Refresh() end end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if not (ns.db and handle and type(ns.db.quick) == "table") then return end
    ns.db.quick.open = handle:GetAttribute("open") and true or false
    ns.db.quick.page = pager:GetAttribute("page") or 1
end)

local slash = SlashCmdList.WOLKARAMOBILE
SlashCmdList.WOLKARAMOBILE = function(message)
    local command, value = (message or ""):lower():match("^%s*quick%s*(%S*)%s*(%S*)")
    if not command or not ns.db then return slash(message) end
    if InCombatLockdown() then ns.Print("change the quick bar out of combat."); return end
    local quick = Settings()
    local number = tonumber(value)
    if command == "on" then quick.enabled = true
    elseif command == "off" then quick.enabled = false
    elseif command == "count" and number then quick.count = ns.Clamp(math.floor(number), 3, MAX_SLOTS)
    elseif command == "size" and number then quick.size = ns.Clamp(number, 36, 64)
    else
        ns.Print("/mobile quick on, off, count 3-5, size 36-64. Now: " .. (quick.enabled and "on" or "off")
            .. ", " .. quick.count .. " slots per page, size " .. quick.size .. ".")
        return
    end
    ns.MarkChanged(); ns.Layout(); ns.Refresh()
    ns.Print("quick bar " .. (quick.enabled and "on" or "off") .. ", " .. quick.count .. " slots per page, size " .. quick.size .. ".")
end
