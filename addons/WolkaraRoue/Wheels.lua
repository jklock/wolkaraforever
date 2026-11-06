-- Interface mobile : les roues. Jusqu'à quatre, chacune avec son bouton doré (à placer où
-- l'on veut), son nombre de cases, sa taille et son ouverture : autour de son bouton, ou au
-- centre de l'écran. Le bouton ouvre et ferme la roue en combat aussi, parce qu'il est
-- sécurisé : le jeu le laisse faire.

local _, ns = ...

local SLOT_SIZE = 64
local TOGGLE_SIZE = 72
-- En proportion de l'écran : la roue 1 au bord droit au-dessus des sorts du stick droit, la
-- roue 2 au bord gauche, les roues 3 et 4 un peu plus vers l'intérieur.
local DEFAULT_TOGGLES = {
    ns.Spot(0.94, 0.55),
    ns.Spot(0.06, 0.50),
    ns.Spot(0.80, 0.55),
    ns.Spot(0.20, 0.50),
}

local Wheels = ns.Register("Roues", {})
ns.Wheels = Wheels
local wheels = {}

local function Settings(index) return ns.db.wheels[index] end

local function BuildWheel(index)
    local wheel = { index = index, slots = {} }

    local ring = CreateFrame("Frame", "WolkaraMobileRing" .. index, UIParent, "SecureHandlerBaseTemplate")
    ring:SetFrameStrata("DIALOG")
    ring:SetSize(2, 2)
    ring:SetPoint("CENTER")
    ring:Hide()
    wheel.ring = ring

    local backdrop = ring:CreateTexture(nil, "BACKGROUND")
    backdrop:SetTexture(ns.WHITE)
    backdrop:SetVertexColor(0, 0, 0, 0.30)
    backdrop:SetPoint("CENTER")
    ns.Circle(ring, backdrop)
    wheel.backdrop = backdrop

    for i = 1, ns.MAX_SLOTS do
        local slot = ns.CreateActionButton("WolkaraMobileRing" .. index .. "Slot" .. i, ring, SLOT_SIZE,
            function() return Settings(index).entries[i] end,
            function(entry) Settings(index).entries[i] = entry end)
        slot.OnAssigned = function() if i == 1 then wheel:RefreshToggle() end end
        wheel.slots[i] = slot
    end

    -- Au centre : fermer.
    local close = CreateFrame("Button", "WolkaraMobileRing" .. index .. "Close", ring, "SecureHandlerClickTemplate")
    close:SetSize(48, 48)
    close:SetPoint("CENTER")
    close:RegisterForClicks("AnyUp")
    close:SetFrameRef("ring", ring)
    close:SetAttribute("_onclick", [=[ self:GetFrameRef("ring"):Hide() ]=])
    ns.Disc(close, "BACKGROUND", 0.12, 0.12, 0.15, 0.9, 0)
    local cross = ns.Label(close, "GameFontNormalLarge", "X")
    cross:SetPoint("CENTER", 0, 1)
    local closeHighlight = ns.Disc(close, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    closeHighlight:SetBlendMode("ADD")

    -- Le bouton doré.
    local toggle = CreateFrame("Button", "WolkaraMobileToggle" .. index, UIParent, "SecureHandlerClickTemplate")
    toggle:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    -- Sous les fenêtres du jeu : il restait par-dessus la fiche du personnage ouverte.
    toggle:SetFrameStrata("LOW")
    toggle:RegisterForClicks("AnyUp")
    toggle:SetFrameRef("ring", ring)
    toggle:SetAttribute("_onclick", [=[
        local ring = self:GetFrameRef("ring")
        if ring:IsShown() then ring:Hide() else ring:Show() end
    ]=])
    local d = DEFAULT_TOGGLES[index]
    toggle:SetPoint("CENTER")
    ns.Disc(toggle, "BACKGROUND", 0.85, 0.68, 0.3, 0.95, 3)
    wheel.toggleIcon = toggle:CreateTexture(nil, "ARTWORK")
    wheel.toggleIcon:SetAllPoints()
    wheel.toggleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(toggle, wheel.toggleIcon)
    local label = ns.Label(toggle, "GameFontNormal", index == 1 and "Roue" or ("Roue " .. index))
    label:SetPoint("TOP", toggle, "BOTTOM", 0, -4)
    local toggleHighlight = ns.Disc(toggle, "HIGHLIGHT", 1, 1, 1, 0.2, 0)
    toggleHighlight:SetBlendMode("ADD")
    wheel.toggleGlow = ns.EditFrame(toggle)
    ns.Movable(toggle, function() return Settings(index) end, "toggle", d)
    toggle.OnMoved = function() wheel:Place() end
    wheel.toggle = toggle

    ring:HookScript("OnShow", function() wheel:Refresh() end)
    local since = 0
    ring:HookScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.2 then return end
        since = 0
        for i = 1, Settings(index).slots do ns.UpdateState(wheel.slots[i]) end
    end)

    function wheel:RefreshToggle()
        self.toggleIcon:SetTexture(ns.EntryIcon(Settings(index).entries[1]) or "Interface\\Icons\\INV_Misc_Book_09")
    end

    -- Où la roue s'ouvre : autour de son bouton, sans sortir de l'écran, ou au centre.
    function wheel:Place()
        if InCombatLockdown() then return end
        local settings = Settings(index)
        local scale = settings.scale / 100
        ring:SetScale(scale)
        local half = settings.radius + SLOT_SIZE / 2 + 12
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local x, y = width / 2, height / 2
        if settings.open ~= "centre" then
            local cx, cy = toggle:GetCenter()
            if cx then
                local factor = toggle:GetEffectiveScale() / UIParent:GetEffectiveScale()
                x, y = cx * factor, cy * factor
            end
        end
        local margin = half * scale
        x = ns.Clamp(x, margin, math.max(margin, width - margin))
        y = ns.Clamp(y, margin, math.max(margin, height - margin))
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    function wheel:Layout()
        local settings = Settings(index)
        if settings.enabled then
            toggle:Show()
            toggle:PlaceSaved()
        else
            toggle:Hide()
            ring:Hide()
        end
        local span = (settings.radius + SLOT_SIZE / 2 + 16) * 2
        backdrop:SetSize(span, span)
        for i = 1, ns.MAX_SLOTS do
            local slot = self.slots[i]
            if i <= settings.slots then
                local angle = math.rad(90 - (i - 1) * 360 / settings.slots)
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", ring, "CENTER", math.cos(angle) * settings.radius, math.sin(angle) * settings.radius)
                slot:Show()
            else
                slot:Hide()
            end
            ns.ApplyButton(slot)
        end
        self:Place()
        if ns.editing and settings.enabled then ring:Show() end
    end

    function wheel:Refresh()
        for i = 1, ns.MAX_SLOTS do ns.RefreshButton(self.slots[i]) end
        self:RefreshToggle()
    end

    return wheel
end

function Wheels:Init()
    for index = 1, ns.MAX_WHEELS do wheels[index] = BuildWheel(index) end
end

function Wheels:Layout()
    for _, wheel in ipairs(wheels) do ns.Guard("roue " .. wheel.index, wheel.Layout, wheel) end
end

function Wheels:Refresh()
    for _, wheel in ipairs(wheels) do wheel:Refresh() end
end

function Wheels:SetEditing(on)
    for _, wheel in ipairs(wheels) do
        wheel.toggleGlow:SetShown(on)
        if not on then wheel.ring:Hide() end
    end
end

function Wheels:CombatStarts()
    for _, wheel in ipairs(wheels) do
        for i = 1, ns.MAX_SLOTS do
            if wheel.slots[i].suppressed then ns.ApplyButton(wheel.slots[i]) end
        end
    end
end

local function UpdateCooldowns()
    for _, wheel in ipairs(wheels) do
        if wheel.ring:IsShown() then
            for i = 1, ns.MAX_SLOTS do ns.UpdateCooldown(wheel.slots[i]) end
        end
    end
end
ns.On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
local function Changed()
    if not ns.db then return end
    Wheels:Refresh()
    if not InCombatLockdown() then
        for _, wheel in ipairs(wheels) do
            for i = 1, ns.MAX_SLOTS do ns.ApplyButton(wheel.slots[i]) end
        end
    end
end
ns.On("SPELLS_CHANGED", Changed)
ns.On("UPDATE_MACROS", Changed)
ns.On("BAG_UPDATE", function() if ns.db then Wheels:Refresh() end end)
