-- Corner skill fan (iPhone Duo layout).
local _, ns = ...

local Fan = ns.Register("Corner fan", {})
ns.Fan = Fan

local PAGES, SHOWN, PER_PAGE = 2, 5, 10
local FIRST, LAST = 9, 81
local TOP_RING = 13
local TAB_ANGLE, PAGE_ANGLE = 58, 82
local SMALL = 0.72
local REACH = 0.22
local REACH_SMALL = 0.40
local SWIPE = 0.35
local HOLD = 3

local root, tab, flip, jump, range, flash, setButton
local JUMP = 0.16
local FLIP_RADIUS, FLIP_ANGLE = 0.20, 45
local pages, buttons = {}, {}

local DEFAULTS = { enabled = true, size = 56, radius = 30, page = 1, seeded = false, style = "wheel" }
local DUO_LAYOUT = 2

local function Settings()
    local db = ns.db
    if type(db.fan) ~= "table" then db.fan = {} end
    local fan = db.fan
    for key, value in pairs(DEFAULTS) do
        if fan[key] == nil then fan[key] = value end
    end
    if type(fan.pages) ~= "table" then fan.pages = {} end
    if type(fan.offsets) ~= "table" then fan.offsets = {} end
    for page = 1, PAGES do
        if type(fan.pages[page]) ~= "table" then fan.pages[page] = {} end
        fan.offsets[page] = ns.Clamp(math.floor(tonumber(fan.offsets[page]) or 0), 0, PER_PAGE - SHOWN)
    end
    if fan.duoLayout ~= DUO_LAYOUT then
        fan.duoLayout = DUO_LAYOUT
        fan.size, fan.radius = DEFAULTS.size, DEFAULTS.radius
    end
    fan.size = ns.Clamp(tonumber(fan.size) or 56, 40, 80)
    fan.radius = ns.Clamp(tonumber(fan.radius) or 30, 22, 50)
    fan.page = (fan.page == 2) and 2 or 1
    if not fan.wheelDefault then fan.wheelDefault = true; fan.style = "wheel" end
    if fan.style ~= "wheel" then fan.style = "pages" end
    return fan
end

Fan.Settings = function() return Settings() end

function Fan:Enabled()
    return ns.DuoLayout() and type(ns.db.fan) == "table" and ns.db.fan.enabled == true
end

local function Seed(fan)
    if fan.seeded then return end
    fan.seeded = true
    local source = ns.db.free and ns.db.free.buttons
    if type(source) ~= "table" then return end
    local slot = 1
    for index = 1, ns.MAX_FREE do
        local stored = source[index]
        if slot > SHOWN then break end
        if type(stored) == "table" and type(stored.entry) == "table" and stored.entry.kind then
            local entry = {}
            for key, value in pairs(stored.entry) do entry[key] = value end
            fan.pages[1][slot] = entry
            slot = slot + 1
        end
    end
end

local function Icon(path, fallback)
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return fallback end
    return path
end

local function Polar(radius, degrees)
    local angle = math.rad(degrees)
    return -radius * math.cos(angle), radius * math.sin(angle)
end

local function BuildSmall(name, template)
    local button = CreateFrame("Button", name, root, template)
    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 4)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(button, button.icon)
    button.label = ns.Label(button, "GameFontNormal")
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetShadowOffset(1, -1)
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    highlight:SetBlendMode("ADD")
    return button
end

function ns.HoldToSwap(button, onHeld, slot)
    local sweep = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    sweep:SetAllPoints()
    if sweep.SetHideCountdownNumbers then sweep:SetHideCountdownNumbers(true) end
    if sweep.SetSwipeColor then sweep:SetSwipeColor(1, 0.82, 0.2, 0.6) end
    if sweep.SetReverse then sweep:SetReverse(true) end
    local since, fromX, fromY
    local function Stop()
        since = nil
        if sweep.Clear then sweep:Clear() else sweep:Hide() end
    end
    button:HookScript("OnMouseDown", function()
        if InCombatLockdown() or ns.editing then return end
        button:SetAttribute("held", nil)
        since = 0
        fromX, fromY = GetCursorPosition()
        sweep:SetCooldown(GetTime(), HOLD)
    end)
    button:HookScript("OnMouseUp", Stop)
    button:HookScript("OnHide", Stop)
    button:HookScript("OnUpdate", function(self, elapsed)
        if not since then return end
        if InCombatLockdown() then Stop(); return end
        since = since + elapsed
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if fromX and x and scale and scale > 0 and math.abs(x - fromX) + math.abs(y - fromY) > 48 * scale then Stop(); return end
        if since >= HOLD then
            Stop()
            if onHeld then onHeld() else self:SetAttribute("held", true) end
            if ns.EnterEditMode then ns.EnterEditMode(slot) else ns.SetEditing(true) end
        end
    end)
end

local ANGLE = [=[
    local x, y = owner:GetMousePosition()
    local angle
    if x then
        local size = owner:GetAttribute("size")
        local dx, dy = (1 - x) * size, y * size
        if dx <= 0 then angle = 90
        else
            local t = dy / dx
            local inverse = t > 1
            if inverse then t = 1 / t end
            local a = 45 * t + 15.64 * t * (1 - t)
            if inverse then a = 90 - a end
            angle = a
        end
    end
]=]

local DOWN = [=[
    if not owner:GetAttribute("wheel") then return end
    owner:SetAttribute("swiped", nil)
]=] .. ANGLE .. [=[
    owner:SetAttribute("downangle", angle)
]=]

local FLIPSET = [=[
    local offset = owner:GetAttribute("offset") > 0 and 0 or owner:GetAttribute("most")
    owner:SetAttribute("offset", offset)
    local shown = owner:GetAttribute("shown")
    for index = 1, owner:GetAttribute("count") do
        local button = owner:GetFrameRef("b" .. index)
        local slot = index - offset
        if slot >= 1 and slot <= shown then
            button:ClearAllPoints()
            button:SetPoint("CENTER", owner, "BOTTOMRIGHT", owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
            button:Show()
        else
            button:Hide()
        end
    end
]=]

local UP = [=[
    if not owner:GetAttribute("wheel") then return end
]=] .. ANGLE .. [=[
    local from = owner:GetAttribute("downangle")
    owner:SetAttribute("downangle", nil)
    if not angle or not from then return end
    local turns = (from - angle) / owner:GetAttribute("step")
    if turns < ]=] .. SWIPE .. [=[ and turns > -]=] .. SWIPE .. [=[ then return end
    owner:SetAttribute("swiped", true)
]=] .. FLIPSET .. [=[
]=]

local CLICK = [=[
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
]=]

function Fan:Init()
    ns.DuoLayout()
    local fan = Settings()
    Seed(fan)

    root = CreateFrame("Frame", "WolkaraMobileFan", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("LOW")
    root:Hide()

    for page = 1, PAGES do
        local holder = CreateFrame("Frame", "WolkaraMobileFanPage" .. page, root, "SecureHandlerBaseTemplate")
        holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
        holder:SetSize(2, 2)
        holder:EnableMouse(false)
        pages[page] = holder
        buttons[page] = {}
        for index = 1, PER_PAGE do
            local button = ns.CreateActionButton("WolkaraMobileFan" .. page .. "Skill" .. index, holder, fan.size,
                function() return Settings().pages[page][index] end,
                function(entry) Settings().pages[page][index] = entry end)
            SecureHandlerWrapScript(button, "OnMouseDown", holder, DOWN)
            SecureHandlerWrapScript(button, "OnMouseUp", holder, UP)
            SecureHandlerWrapScript(button, "OnClick", holder, CLICK)
            button:HookScript("OnMouseDown", function()
                button.downOffset = holder:GetAttribute("offset")
                button.downAngle = ns.FanCursorAngle()
                if ns.fanDebug then
                    ns.Print(("fan down: wheel=%s secure angle=%s cursor angle=%s"):format(tostring(holder:GetAttribute("wheel")),
                        tostring(holder:GetAttribute("downangle")), tostring(button.downAngle)))
                end
            end)
            button:HookScript("OnMouseUp", function()
                local from, to = button.downAngle, ns.FanCursorAngle()
                button.downAngle = nil
                if ns.fanDebug then
                    ns.Print(("fan up: secure swiped=%s offset=%s cursor angle %s -> %s"):format(tostring(holder:GetAttribute("swiped")),
                        tostring(holder:GetAttribute("offset")), tostring(from), tostring(to)))
                end
                if not InCombatLockdown() and holder:GetAttribute("wheel") and not holder:GetAttribute("swiped") and from and to then
                    ns.FanTurn(page, (from - to) / (holder:GetAttribute("step") or 18))
                end
                if holder:GetAttribute("offset") ~= button.downOffset then ns.FanFeedback(); ns.FanArrow() end
                if InCombatLockdown() then return end
                local db = ns.db and ns.db.fan
                if type(db) == "table" and type(db.offsets) == "table" then
                    db.offsets[page] = holder:GetAttribute("offset") or 0
                end
            end)
            holder:SetFrameRef("b" .. index, button)
            buttons[page][index] = button
        end
    end

    jump = CreateFrame("Frame", "WolkaraMobileJumpArt", root)
    jump:EnableMouse(false)
    jump:SetFrameLevel(root:GetFrameLevel() + 1)
    jump.disc = ns.Disc(jump, "BACKGROUND", 0.06, 0.06, 0.09, 0.72, 0)
    jump.rim = ns.Disc(jump, "BORDER", 1, 0.82, 0.3, 0.18, 0)
    jump.rim:ClearAllPoints()
    jump.icon = jump:CreateTexture(nil, "ARTWORK")
    jump.icon:SetTexture(Icon("Interface\\Icons\\Ability_HeroicLeap", "Interface\\Icons\\Ability_Kick"))
    jump.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    jump.iconFrame = CreateFrame("Frame", nil, jump)
    jump.icon:SetParent(jump.iconFrame)
    ns.Circle(jump.iconFrame, jump.icon)
    jump.label = ns.Label(jump, "GameFontNormalSmall", "Jump")
    flash = CreateFrame("Frame", nil, root)
    flash:EnableMouse(false)
    flash:SetFrameLevel(root:GetFrameLevel() + 2)
    flash.disc = ns.Disc(flash, "BACKGROUND", 1, 0.82, 0.3, 1, 0)
    flash:SetAlpha(0)
    flash.anim = flash:CreateAnimationGroup()
    local rise = flash.anim:CreateAnimation("Alpha")
    rise:SetFromAlpha(0); rise:SetToAlpha(0.28); rise:SetDuration(0.07); rise:SetOrder(1)
    local fall = flash.anim:CreateAnimation("Alpha")
    fall:SetFromAlpha(0.28); fall:SetToAlpha(0); fall:SetDuration(0.25); fall:SetOrder(2)
    range = ns.Label(root, "GameFontNormalSmall")
    range:SetTextColor(1, 0.82, 0.3)

    tab = BuildSmall("WolkaraMobileFanTab", "SecureActionButtonTemplate")
    tab:RegisterForClicks("AnyUp", "AnyDown")
    tab:SetAttribute("useOnKeyDown", true)
    tab:SetAttribute("type", "macro")
    tab:SetAttribute("macrotext", "/targetenemy")
    tab.icon:SetTexture(Icon("Interface\\Icons\\Ability_Hunter_SniperTraining", "Interface\\Icons\\Ability_Hunter_SniperShot"))
    tab.icon:SetAlpha(0.55)
    tab.label:SetText("Tab")

    flip = BuildSmall("WolkaraMobileFanFlip", "SecureHandlerClickTemplate")
    flip:RegisterForClicks("AnyUp")
    for page = 1, PAGES do flip:SetFrameRef("page" .. page, pages[page]) end
    flip:SetAttribute("_onclick", [=[
        if self:GetAttribute("held") then self:SetAttribute("held", nil); return end
        local page = self:GetAttribute("page") == 1 and 2 or 1
        self:SetAttribute("page", page)
        local one, two = self:GetFrameRef("page1"), self:GetFrameRef("page2")
        if page == 1 then one:Show(); two:Hide() else one:Hide(); two:Show() end
    ]=])
    flip.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_04")
    flip.icon:SetAlpha(0.45)
    flip:HookScript("OnClick", function(self)
        local page = self:GetAttribute("page") == 2 and 2 or 1
        self.label:SetText(page .. "/" .. PAGES)
        if ns.db and type(ns.db.fan) == "table" then ns.db.fan.page = page end
    end)

    setButton = CreateFrame("Button", "WolkaraMobileFanSet", root, "SecureHandlerClickTemplate")
    setButton:RegisterForClicks("AnyDown")
    setButton:SetFrameRef("flip", flip)
    for page = 1, PAGES do setButton:SetFrameRef("page" .. page, pages[page]) end
    setButton:SetAttribute("_onclick", [=[
        local flip = self:GetFrameRef("flip")
        local owner = self:GetFrameRef(flip:GetAttribute("page") == 2 and "page2" or "page1")
        if not owner:GetAttribute("wheel") then return end
]=] .. FLIPSET)
    setButton.arrow = setButton:CreateTexture(nil, "ARTWORK")
    setButton.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    setButton.arrow:SetPoint("CENTER")
    local glow = ns.Disc(setButton, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    glow:SetBlendMode("ADD")
    setButton:HookScript("OnClick", function() ns.FanFeedback(); ns.FanArrow() end)
    flip:HookScript("OnClick", function() ns.FanArrow() end)

end

function ns.FanFirstSlot()
    if not flip then return nil end
    local page = flip:GetAttribute("page") == 2 and 2 or 1
    local offset = pages[page]:GetAttribute("offset") or 0
    return buttons[page][offset + 1]
end

function ns.FanLockIcon() end

function ns.FanArrow()
    if not setButton then return end
    local page = flip:GetAttribute("page") == 2 and 2 or 1
    local later = (pages[page]:GetAttribute("offset") or 0) > 0
    setButton.arrow:SetRotation(math.rad(later and -45 or 135))
end

function ns.FanFeedback()
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836, "Master") end
    if flash and flash.anim then flash.anim:Stop(); flash.anim:Play() end
end

function ns.FanCursorAngle()
    if not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not x or not scale or scale == 0 then return nil end
    local dx, dy = UIParent:GetWidth() - x / scale, y / scale
    if dx <= 0 then return 90 end
    return math.deg(math.atan(dy / dx))
end

function ns.FanTurn(page, turns)
    if InCombatLockdown() or (turns < SWIPE and turns > -SWIPE) then return end
    local holder = pages[page]
    local offset = (holder:GetAttribute("offset") or 0) > 0 and 0 or (holder:GetAttribute("most") or 0)
    holder:SetAttribute("offset", offset)
    holder:SetAttribute("swiped", true)
    local shown = holder:GetAttribute("shown") or SHOWN
    for index, button in ipairs(buttons[page]) do
        local slot = index - offset
        if index <= (holder:GetAttribute("count") or SHOWN) and slot >= 1 and slot <= shown then
            button:ClearAllPoints()
            button:SetPoint("CENTER", holder, "BOTTOMRIGHT", holder:GetAttribute("x" .. slot), holder:GetAttribute("y" .. slot))
            button:Show()
        else
            button:Hide()
        end
    end
end

local function Place(button, x, y, size, reach)
    button:ClearAllPoints()
    button:SetSize(size, size)
    button:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", x, y)
    local extra = math.floor(size * reach + 0.5)
    button:SetHitRectInsets(-extra, -extra, -extra, -extra)
end

function Fan:Layout()
    if not root or InCombatLockdown() then return end
    local fan = Settings()
    if not fan.enabled or not ns.DuoLayout() then root:Hide(); return end

    local height = UIParent:GetHeight()
    local outer = height * fan.radius / 100
    local top = height * (fan.radius + TOP_RING) / 100
    local size, small = fan.size, math.floor(fan.size * SMALL + 0.5)
    local step = (LAST - FIRST) / (SHOWN - 1)
    local wheel = fan.style == "wheel"
    local count = wheel and PER_PAGE or SHOWN
    for page = 1, PAGES do
        local holder = pages[page]
        local offset = wheel and fan.offsets[page] or 0
        holder:SetSize(outer + size, outer + size)
        holder:SetAttribute("size", outer + size)
        holder:SetAttribute("wheel", wheel)
        holder:SetAttribute("step", step)
        holder:SetAttribute("shown", SHOWN)
        holder:SetAttribute("count", count)
        holder:SetAttribute("most", count - SHOWN)
        holder:SetAttribute("offset", offset)
        for slot = 1, SHOWN do
            local x, y = Polar(outer, FIRST + (slot - 1) * step)
            holder:SetAttribute("x" .. slot, x)
            holder:SetAttribute("y" .. slot, y)
        end
        for index, button in ipairs(buttons[page]) do
            local slot = index - offset
            button:SetAttribute("useOnKeyDown", not wheel)
            if index <= count and slot >= 1 and slot <= SHOWN then
                local x, y = Polar(outer, FIRST + (slot - 1) * step)
                Place(button, x, y, size, REACH)
                button:SetFrameLevel(root:GetFrameLevel() + 4)
                button:Show()
            else
                button:SetSize(size, size)
                button:Hide()
            end
            ns.ApplyButton(button)
        end
    end
    local tx, ty = Polar(top, TAB_ANGLE)
    Place(tab, tx, ty, small, REACH_SMALL)
    local fx, fy = Polar(top, PAGE_ANGLE)
    Place(flip, fx, fy, small, REACH_SMALL)
    tab:SetFrameLevel(root:GetFrameLevel() + 6)
    local radius = height * JUMP
    jump:ClearAllPoints()
    jump:SetSize(radius * 2, radius * 2)
    jump:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", 0, 0)
    jump.rim:SetPoint("TOPLEFT", -2, 2)
    jump.rim:SetPoint("BOTTOMRIGHT", 2, -2)
    local iconSize = radius * 0.55
    jump.iconFrame:ClearAllPoints()
    jump.iconFrame:SetSize(iconSize, iconSize)
    jump.iconFrame:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", -radius * 0.42, radius * 0.42)
    jump.icon:SetAllPoints(jump.iconFrame)
    local rx, ry = Polar(outer + size * 0.85, FIRST)
    range:ClearAllPoints()
    range:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", rx, ry + size * 0.15)
    range:SetShown(wheel)
    local sx, sy = Polar(height * FLIP_RADIUS, FLIP_ANGLE)
    local setSize = math.floor(size * 0.62 + 0.5)
    setButton:ClearAllPoints()
    setButton:SetSize(setSize, setSize)
    setButton:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", sx, sy)
    setButton:SetHitRectInsets(-8, -8, -8, -8)
    setButton:SetFrameLevel(root:GetFrameLevel() + 6)
    setButton.arrow:SetSize(setSize * 1.15, setSize * 1.15)
    setButton:SetShown(wheel)
    ns.FanArrow()
    local reach = (outer + size * 0.7) * 2
    flash:ClearAllPoints()
    flash:SetSize(reach, reach)
    flash:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", 0, 0)
    jump.label:Hide()
    flip:SetFrameLevel(root:GetFrameLevel() + 6)

    flip:SetAttribute("page", fan.page)
    flip.label:SetText(fan.page .. "/" .. PAGES)
    for page = 1, PAGES do pages[page]:SetShown(page == fan.page) end
    root:Show()
    self:Refresh()
end

function Fan:Refresh()
    if not root then return end
    for page = 1, PAGES do
        for _, button in ipairs(buttons[page]) do
            ns.RefreshButton(button)
            button:SetAlpha((button:GetEntry() or ns.editing or ns.slotEditing) and 1 or 0.35)
        end
    end
end

function Fan:SetEditing() self:Refresh(); ns.FanLockIcon() end

function Fan:CombatStarts()
    for page = 1, PAGES do
        for _, button in ipairs(buttons[page]) do
            if button.suppressed then ns.ApplyButton(button) end
        end
    end
end

local function Each(fn)
    if not root then return end
    for page = 1, PAGES do
        for _, button in ipairs(buttons[page]) do fn(button) end
    end
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.2 or not root or not root:IsShown() then return end
    since = 0
    for page = 1, PAGES do
        if pages[page]:IsShown() then
            for _, button in ipairs(buttons[page]) do
                if button:IsShown() then ns.UpdateState(button) end
            end
            if range and range:IsShown() then
                local first = (page - 1) * PER_PAGE + (pages[page]:GetAttribute("offset") or 0) + 1
                range:SetText(first .. "-" .. (first + SHOWN - 1))
            end
        end
    end
end)

local function Cooldowns() if ns.db then Each(ns.UpdateCooldown) end end
ns.On("SPELL_UPDATE_COOLDOWN", Cooldowns)
ns.On("BAG_UPDATE_COOLDOWN", Cooldowns)
ns.On("PLAYER_TARGET_CHANGED", Cooldowns)
ns.On("UNIT_AURA", function(unit) if unit == "player" or unit == "target" then Cooldowns() end end)
ns.On("BAG_UPDATE", function() if ns.db then Fan:Refresh() end end)
ns.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    Fan:Refresh()
    if not InCombatLockdown() then Each(ns.ApplyButton) end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if not (ns.db and flip and type(ns.db.fan) == "table") then return end
    ns.db.fan.page = flip:GetAttribute("page") == 2 and 2 or 1
    for page = 1, PAGES do ns.db.fan.offsets[page] = pages[page]:GetAttribute("offset") or 0 end
end)

local function HideRight()
    if not ns.DuoLayout() then return end
    for index = 1, ns.MAX_FREE do
        local button = _G["WolkaraMobileFree" .. index]
        if button then button:Hide() end
    end
end
local baseLayout = Fan.Layout
function Fan:Layout()
    baseLayout(self)
    if root and not InCombatLockdown() and self:Enabled() then HideRight() end
end

local slash = SlashCmdList.WOLKARAMOBILE
SlashCmdList.WOLKARAMOBILE = function(message)
    local command, value = (message or ""):lower():match("^%s*fan%s*(%S*)%s*(%S*)")
    if not command or not ns.db then return slash(message) end
    if InCombatLockdown() then ns.Print("change the fan out of combat."); return end
    local fan = Settings()
    local number = tonumber(value)
    if command == "on" then fan.enabled = true
    elseif command == "off" then fan.enabled = false
    elseif command == "size" and number then fan.size = ns.Clamp(number, 40, 80)
    elseif command == "reach" and number then fan.radius = ns.Clamp(number, 22, 50)
    elseif command == "pages" or command == "wheel" then fan.style = command
    elseif command == "debug" then ns.fanDebug = not ns.fanDebug; ns.Print("fan debug " .. (ns.fanDebug and "on" or "off") .. "."); return
    else
        ns.Print("/mobile fan on, off, pages, wheel, size 40-80, reach 22-50. Now: " .. (fan.enabled and "on" or "off")
            .. ", " .. fan.style .. ", size " .. fan.size .. ", reach " .. fan.radius .. ".")
        return
    end
    ns.MarkChanged(); ns.Layout(); ns.Refresh()
    ns.Print("fan " .. (fan.enabled and "on" or "off") .. ", " .. fan.style .. ", size " .. fan.size .. ", reach " .. fan.radius .. ".")
end
