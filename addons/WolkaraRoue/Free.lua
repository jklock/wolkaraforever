-- Interface mobile : les boutons libres. Des sorts toujours à l'écran, en arc autour des
-- sticks comme dans un jeu mobile : autour du stick droit (caméra) par défaut, et en option
-- autour du stick gauche. Chacun se remplit par le sélecteur et se déplace en mode
-- Personnaliser. Une case vide reste discrète tant qu'on ne personnalise pas.

local _, ns = ...

local SIZE = 64
-- Le centre des sticks de l'app, mesuré sur l'écran du Duo : à 12 % du bord, 22 % du bas.
local STICK_X, STICK_Y = 0.12, 0.222
-- Première rangée serrée autour du stick, deuxième rangée au-delà.
local INNER, OUTER = 0.165, 0.275

local Free = ns.Register("Boutons libres", {})
local groups = {}

local function Arc(side, index, count)
    return function()
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local cx = side == "right" and width * (1 - STICK_X) or width * STICK_X
        local cy = height * STICK_Y
        local radius, slot, slots
        if index <= 4 then
            radius, slot, slots = INNER, index, math.min(4, count)
        else
            radius, slot, slots = OUTER, index - 4, count - 4
        end
        -- De la verticale vers l'intérieur de l'écran : de 90° à 180° à droite, de 90° à 0° à gauche.
        local t = slots <= 1 and 0.5 or (slot - 1) / (slots - 1)
        local degrees = side == "right" and (90 + 90 * t) or (90 - 90 * t)
        local distance = height * radius
        return { "CENTER", "BOTTOMLEFT", cx + math.cos(math.rad(degrees)) * distance,
            cy + math.sin(math.rad(degrees)) * distance }
    end
end

local function BuildGroup(side, key, prefix)
    local group = { side = side, key = key, buttons = {} }
    local function settings() return ns.db[key] end
    local function store(index)
        local list = settings().buttons
        if type(list[index]) ~= "table" then list[index] = {} end
        return list[index]
    end
    for index = 1, ns.MAX_FREE do
        local button = ns.CreateActionButton(prefix .. index, UIParent, SIZE,
            function() return store(index).entry end,
            function(entry) store(index).entry = entry end)
        button:SetFrameStrata("MEDIUM")
        button:RegisterForDrag("LeftButton")
        ns.Movable(button, function() return store(index) end, "pos",
            function() return Arc(side, index, settings().count)() end)
        button:Hide()
        local since = 0
        button:HookScript("OnUpdate", function(self, elapsed)
            since = since + elapsed
            if since < 0.25 then return end
            since = 0
            ns.UpdateState(self)
        end)
        group.buttons[index] = button
    end

    function group:Layout()
        local scale = settings().scale / 100
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then
                button:SetScale(scale)
                button:PlaceSaved()
                button:Show()
            else
                button:Hide()
            end
            ns.ApplyButton(button)
        end
    end

    function group:Refresh()
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then
                ns.RefreshButton(button)
                button:SetAlpha((button:GetEntry() or ns.editing) and 1 or 0.35)
            end
        end
    end

    function group:Each(fn)
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then fn(button) end
        end
    end
    return group
end

function Free:Init()
    groups[1] = BuildGroup("right", "free", "WolkaraMobileFree")
    groups[2] = BuildGroup("left", "freeLeft", "WolkaraMobileFreeLeft")
end

function Free:Layout()
    for _, group in ipairs(groups) do ns.Guard("boutons " .. group.side, group.Layout, group) end
    self:Refresh()
end

function Free:Refresh()
    for _, group in ipairs(groups) do group:Refresh() end
end

function Free:SetEditing() self:Refresh() end

function Free:CombatStarts()
    for _, group in ipairs(groups) do
        group:Each(function(button) if button.suppressed then ns.ApplyButton(button) end end)
    end
end

local function UpdateCooldowns()
    if not ns.db then return end
    for _, group in ipairs(groups) do group:Each(ns.UpdateCooldown) end
end
ns.On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE", function() if ns.db then Free:Refresh() end end)
ns.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    Free:Refresh()
    if not InCombatLockdown() then
        for _, group in ipairs(groups) do group:Each(ns.ApplyButton) end
    end
end)
