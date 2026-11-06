-- Interface mobile : la roue qui tourne.
--
-- Par défaut (réglages, ligne « Sorts à droite » : Roue ou Arc), les sorts à droite forment une
-- grande roue centrée sur le coin bas-droit de l'écran. On n'en voit que le quart au-dessus et
-- à gauche du stick droit ; les autres sorts attendent hors de l'écran et reviennent quand on
-- la fait tourner. Elle ne passe jamais sous le stick, où est le saut.
--
-- On la fait tourner en glissant le doigt depuis un de ses sorts ; toucher un sort sans glisser
-- le lance, au moment où l'on relève le doigt. Ailleurs, rien n'est capté : un glissé à côté des
-- sorts reste à la caméra (la première version prenait tout le coin et volait la caméra). Hors
-- combat, les sorts suivent le doigt. En combat, le jeu ne laisse bouger ses boutons que par son
-- code sécurisé, qui ne voit que l'appui et le relâchement : la roue tourne alors d'autant de
-- crans au moment où l'on relève le doigt. Ce code sécurisé ne fait que de l'arithmétique et lit
-- des positions calculées d'avance.

local _, ns = ...

local Turn = ns.Register("Roue tournante", {})
ns.Turn = Turn

local SIZE = 64         -- un sort, comme les boutons libres
local FIRST = 95        -- le premier emplacement, en degrés depuis la droite (sens direct)
local SWIPE = 0.35      -- en crans : en deçà, le doigt a touché le sort ; au-delà, il a glissé

local band, buttons, wrapped, dragging, dragFrom, dragOffset

local function Settings() return ns.db.free end

function Turn:Enabled() return ns.db ~= nil and Settings().turn == true end

-- La roue est centrée sur le coin bas-droit ; son rayon passe au-dessus du stick droit.
-- Les sorts s'y suivent serrés : d'un centre au suivant, 1,25 taille de sort à « Écart des
-- sorts » 100 %, de 1,11 (presque bord à bord) à 60 % jusqu'à 1,53 à 180 %.
function Turn.Geometry(width, height, count, spread)
    local stick = math.sqrt((width * ns.STICK_X) ^ 2 + (height * ns.STICK_Y) ^ 2)
    local radius = stick + height * 0.15
    local apart = SIZE * (0.9 + 0.35 * (spread or 100) / 100)
    local step = math.deg(2 * math.asin(math.min(1, apart / (2 * radius))))
    return radius, step
end

-- L'emplacement d'un sort (1 à count) pour un décalage donné, fractionnaire pendant un glissé.
function Turn.Angle(index, offset, count, step)
    return FIRST + ((index - 1 + offset) % count) * step
end

local function Point(radius, degrees)
    local angle = math.rad(degrees)
    return radius * math.cos(angle), radius * math.sin(angle)
end

-- Les boutons ont la taille des boutons libres : un décalage se compte à leur échelle.
local function Place(offset)
    if not band or InCombatLockdown() then return end
    local count = band:GetAttribute("count") or 0
    local radius, step, scale = band.radius, band:GetAttribute("step"), band.buttonScale or 1
    for index = 1, count do
        local x, y = Point(radius, Turn.Angle(index, offset, count, step))
        buttons[index]:ClearAllPoints()
        buttons[index]:SetPoint("CENTER", band, "BOTTOMRIGHT", x / scale, y / scale)
    end
end

-- L'angle du doigt vu du coin, en degrés, hors code sécurisé.
local function CursorAngle()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return math.deg(math.atan2(y / scale, x / scale - UIParent:GetWidth()))
end

-- Le même angle dans le code sécurisé, qui n'a que l'arithmétique : la position du doigt sur
-- la bande (0 à 1 depuis son coin bas-gauche) devient un angle entre 90 et 180 degrés, par une
-- approximation de l'arc tangente juste à un tiers de degré près. Ces extraits sont accrochés
-- à chaque sort de la roue : self est le sort, owner la bande.
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
            angle = 180 - a
        end
    end
]=]

local DOWN = [=[
    if not owner:GetAttribute("turning") then return end
    owner:SetAttribute("swiped", nil)
]=] .. ANGLE .. [=[
    owner:SetAttribute("downangle", angle)
]=]

local UP = [=[
    if not owner:GetAttribute("turning") then return end
]=] .. ANGLE .. [=[
    local from = owner:GetAttribute("downangle")
    owner:SetAttribute("downangle", nil)
    local count = owner:GetAttribute("count")
    if not angle or not from or not count or count < 1 then return end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns < ]=] .. SWIPE .. [=[ and turns > -]=] .. SWIPE .. [=[ then return end
    owner:SetAttribute("swiped", true)
    turns = turns + 0.5
    turns = turns - turns % 1
    local offset = (owner:GetAttribute("offset") + turns) % count
    owner:SetAttribute("offset", offset)
    for index = 1, count do
        local slot = (index - 1 + offset) % count
        local button = owner:GetFrameRef("b" .. index)
        button:ClearAllPoints()
        button:SetPoint("CENTER", owner, "BOTTOMRIGHT", owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
    end
]=]

-- Un glissé a tourné la roue : le sort sous le doigt n'est pas lancé.
local CLICK = [=[
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
]=]

function Turn:Init()
    band = CreateFrame("Frame", "WolkaraMobileTurn", UIParent, "SecureHandlerBaseTemplate")
    band:SetFrameStrata("BACKGROUND")  -- sous les sorts, eux-mêmes sous les fenêtres du jeu
    band:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
    band:EnableMouse(false)
    band.disc = band:CreateTexture(nil, "BACKGROUND")
    band.disc:SetTexture(ns.WHITE)
    band.disc:SetVertexColor(0.05, 0.05, 0.08, 0.22)
    ns.Circle(band, band.disc)
    band:Hide()
    band:SetScript("OnUpdate", function()
        if not dragging or InCombatLockdown() then return end
        local turns = (CursorAngle() - dragFrom) / (band:GetAttribute("step") or 20)
        if turns < SWIPE and turns > -SWIPE then turns = 0 end
        Place(dragOffset + turns)
    end)
end

-- Free nous confie ses boutons de droite, une fois créés.
function Turn:Attach(list) buttons = list end

-- Une fois, hors combat : le code sécurisé et le suivi du doigt accrochés à chaque sort. Ils
-- ne font rien tant que la roue n'est pas choisie (attribut turning de la bande).
local function Wrap()
    if wrapped or not band or not buttons or InCombatLockdown() then return end
    wrapped = true
    for _, button in ipairs(buttons) do
        SecureHandlerWrapScript(button, "OnMouseDown", band, DOWN)
        SecureHandlerWrapScript(button, "OnMouseUp", band, UP)
        SecureHandlerWrapScript(button, "OnClick", band, CLICK)
        button:HookScript("OnMouseDown", function()
            if InCombatLockdown() or not Turn:Enabled() then return end
            dragging, dragFrom, dragOffset = true, CursorAngle(), band:GetAttribute("offset") or 0
        end)
        button:HookScript("OnMouseUp", function()
            if not dragging then return end
            dragging = false
            if InCombatLockdown() then return end
            -- Un glissé ne doit pas non plus ouvrir le sélecteur d'une case vide (PostClick).
            local turns = (CursorAngle() - dragFrom) / (band:GetAttribute("step") or 20)
            if turns >= SWIPE or turns <= -SWIPE then button.swiped = true end
            -- Le code sécurisé a déjà arrondi au cran le plus proche, ou laissé la roue où elle
            -- était pour un simple toucher ; on s'aligne dessus et on le retient.
            local offset = band:GetAttribute("offset") or 0
            Place(offset)
            Settings().turnOffset = offset
        end)
    end
end

-- Hors combat : la géométrie, les positions d'avance pour le code sécurisé, puis les sorts.
function Turn:Layout()
    if not band or not buttons or InCombatLockdown() then return end
    Wrap()
    local turning = self:Enabled()
    band:SetAttribute("turning", turning)
    -- Un sort de la roue part au relâchement du doigt, pour qu'un glissé puisse l'annuler.
    for _, button in ipairs(buttons) do
        if turning then button:SetAttribute("useOnKeyDown", false) else button:SetAttribute("useOnKeyDown", nil) end
    end
    if not turning then band:Hide(); return end
    local settings = Settings()
    local count = math.max(0, math.min(settings.count, #buttons))
    local radius, step = Turn.Geometry(UIParent:GetWidth(), UIParent:GetHeight(), count, settings.spread)
    local size = radius + SIZE
    band.radius = radius
    band.buttonScale = (settings.scale or 100) / 100
    band:SetSize(size, size)
    band.disc:ClearAllPoints()
    band.disc:SetPoint("CENTER", band, "BOTTOMRIGHT")
    band.disc:SetSize(2 * (radius + SIZE / 2 + 8), 2 * (radius + SIZE / 2 + 8))
    band:SetAttribute("size", size)
    band:SetAttribute("count", count)
    band:SetAttribute("step", step)
    local offset = count > 0 and math.floor(tonumber(settings.turnOffset) or 0) % count or 0
    band:SetAttribute("offset", offset)
    for slot = 0, math.max(0, count - 1) do
        local x, y = Point(radius, FIRST + slot * step)
        band:SetAttribute("x" .. slot, x / band.buttonScale)
        band:SetAttribute("y" .. slot, y / band.buttonScale)
    end
    for index = 1, count do band:SetFrameRef("b" .. index, buttons[index]) end
    band:Show()
    Place(offset)
end

-- Le combat fini, le cran où la roue s'est arrêtée est retenu.
ns.On("PLAYER_REGEN_ENABLED", function()
    if band and ns.db and Turn:Enabled() then Settings().turnOffset = band:GetAttribute("offset") or 0 end
end)
