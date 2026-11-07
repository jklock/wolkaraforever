-- Interface mobile : les roues qui tournent.
--
-- Par défaut (réglages, lignes « Sorts à droite » et « Sorts à gauche » : Roue ou Arc), les sorts
-- de chaque côté forment une grande roue centrée sur le coin bas de l'écran, celle de gauche en
-- miroir de celle de droite. On n'en voit que le quart au-dessus du stick, vers le centre de
-- l'écran ; les autres sorts attendent hors de l'écran et reviennent quand on la fait tourner.
-- Elle ne passe jamais sous le stick (à droite, c'est là qu'est le saut).
--
-- On la fait tourner en glissant le doigt depuis un de ses sorts ; toucher un sort sans glisser
-- le lance, au moment où l'on relève le doigt. Ailleurs, rien n'est capté : un glissé à côté des
-- sorts reste à la caméra (la première version prenait tout le coin et volait la caméra). Hors
-- combat, les sorts suivent le doigt. En combat, le jeu ne laisse bouger ses boutons que par son
-- code sécurisé, qui ne voit que l'appui et le relâchement : la roue tourne alors d'autant de
-- crans au moment où l'on relève le doigt. Ce code sécurisé ne fait que de l'arithmétique et lit
-- des positions calculées d'avance.
--
-- La roue de gauche se calcule comme celle de droite vue dans un miroir : mêmes angles, mêmes
-- crans, positions retournées de gauche à droite. Rien ne dessine les roues : ni disque ni
-- ombre, seuls leurs sorts sont à l'écran.
--
-- Un glissé finit toujours. Les sorts d'une roue qui tourne ne se « glissent-déposent » pas :
-- le jeu aurait pris le glissé pour un glisser-déposer, qui peut ne jamais rendre au sort le
-- relâchement du doigt. La roue suivait alors le curseur après coup, et les deux roues
-- tournaient ensemble (2026-11-07). Hors combat, un glissé dont le doigt s'est relevé sans
-- que le jeu le dise se termine quand même, et en commencer un sur une roue arrête l'autre.

local _, ns = ...

local Turn = ns.Register("Roues tournantes", {})
ns.Turn = Turn

local SIZE = 64         -- un sort, comme les boutons libres
local FIRST = 95        -- le premier emplacement, en degrés depuis le bord (sens direct, vu de droite)
local SWIPE = 0.35      -- en crans : en deçà, le doigt a touché le sort ; au-delà, il a glissé

local SIDES = {
    right = { key = "free", name = "WolkaraMobileTurn", corner = "BOTTOMRIGHT", mirror = false },
    left = { key = "freeLeft", name = "WolkaraMobileTurnLeft", corner = "BOTTOMLEFT", mirror = true },
}
local ORDER = { "right", "left" }
local wheels, attached = {}, {}

local function Settings(wheel) return ns.db[wheel.key] end

function Turn:Enabled(side)
    local settings = ns.db and ns.db[SIDES[side or "right"].key]
    return settings ~= nil and settings.turn == true
end

-- La roue est centrée sur le coin bas ; son rayon passe au-dessus du stick.
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
-- L'angle se lit vu de droite ; à gauche, le miroir le retourne.
function Turn.Angle(index, offset, count, step)
    return FIRST + ((index - 1 + offset) % count) * step
end

local function Point(wheel, radius, degrees)
    local angle = math.rad(degrees)
    local x, y = radius * math.cos(angle), radius * math.sin(angle)
    if wheel.mirror then x = -x end
    return x, y
end

-- Les boutons ont la taille des boutons libres : un décalage se compte à leur échelle.
local function Place(wheel, offset)
    local band, buttons = wheel.band, attached[wheel.side]
    if not buttons or InCombatLockdown() then return end
    local count = band:GetAttribute("count") or 0
    local radius, step, scale = band.radius, band:GetAttribute("step"), band.buttonScale or 1
    for index = 1, count do
        local x, y = Point(wheel, radius, Turn.Angle(index, offset, count, step))
        buttons[index]:ClearAllPoints()
        buttons[index]:SetPoint("CENTER", band, wheel.corner, x / scale, y / scale)
    end
end

-- L'angle du doigt vu du coin de la roue (et, à gauche, dans le miroir), hors code sécurisé.
local function CursorAngle(wheel)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    local inward = wheel.mirror and x or UIParent:GetWidth() - x
    return math.deg(math.atan2(y, -inward))
end

-- Hors combat : un glissé laissé ouvert s'arrête, la roue revient au cran retenu.
local function Drop(wheel)
    wheel.dragging = false
    Place(wheel, wheel.band:GetAttribute("offset") or 0)
end

-- Hors combat : le doigt s'est relevé sans que le jeu le dise au sort. Le glissé se finit comme
-- le code sécurisé l'aurait fait : au cran le plus proche, retenu pour le prochain lancement.
local function Release(wheel)
    local band = wheel.band
    wheel.dragging = false
    local count = band:GetAttribute("count") or 0
    local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
    local offset = wheel.dragOffset or 0
    if count > 0 and (turns >= SWIPE or turns <= -SWIPE) then
        offset = (offset + math.floor(turns + 0.5)) % count
    end
    band:SetAttribute("offset", offset)
    Place(wheel, offset)
    Settings(wheel).turnOffset = offset
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
        local dx, dy = x * size, y * size
        if not owner:GetAttribute("mirror") then dx = size - dx end
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
    local corner = owner:GetAttribute("corner")
    for index = 1, count do
        local slot = (index - 1 + offset) % count
        local button = owner:GetFrameRef("b" .. index)
        button:ClearAllPoints()
        button:SetPoint("CENTER", owner, corner, owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
    end
]=]

-- Un glissé a tourné la roue : le sort sous le doigt n'est pas lancé. Si le jeu passe le clic
-- avant le relâchement, le glissé se mesure ici aussi.
local CLICK = [=[
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
    local from = owner:GetAttribute("downangle")
    if down or not from or not owner:GetAttribute("turning") then return end
]=] .. ANGLE .. [=[
    if not angle then return end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns >= ]=] .. SWIPE .. [=[ or turns <= -]=] .. SWIPE .. [=[ then return false end
]=]

function Turn:Init()
    for _, side in ipairs(ORDER) do
        local info = SIDES[side]
        local band = CreateFrame("Frame", info.name, UIParent, "SecureHandlerBaseTemplate")
        band:SetFrameStrata("BACKGROUND")  -- sous les sorts, eux-mêmes sous les fenêtres du jeu
        band:SetPoint(info.corner, UIParent, info.corner)
        band:EnableMouse(false)
        band:Hide()
        local wheel = { side = side, key = info.key, corner = info.corner, mirror = info.mirror, band = band }
        band:SetScript("OnUpdate", function()
            if not wheel.dragging or InCombatLockdown() then return end
            -- Le doigt relevé, d'après le jeu : cru seulement s'il l'a d'abord vu posé pendant ce
            -- glissé (l'état des boutons passe par la traduction de l'app, qu'on ne suppose pas).
            if IsMouseButtonDown then
                if IsMouseButtonDown("LeftButton") then
                    wheel.held = true
                elseif wheel.held then
                    Release(wheel)
                    return
                end
            end
            local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
            if turns < SWIPE and turns > -SWIPE then turns = 0 end
            Place(wheel, wheel.dragOffset + turns)
        end)
        wheels[side] = wheel
    end
end

-- Free nous confie ses boutons, une fois créés (avant notre Init : il passe avant nous).
function Turn:Attach(list, side) attached[side or "right"] = list end

-- Une fois, hors combat : le code sécurisé et le suivi du doigt accrochés à chaque sort. Ils
-- ne font rien tant que la roue n'est pas choisie (attribut turning de la bande).
local function Wrap(wheel)
    local buttons, band = attached[wheel.side], wheel.band
    if wheel.wrapped or not buttons or InCombatLockdown() then return end
    wheel.wrapped = true
    for _, button in ipairs(buttons) do
        SecureHandlerWrapScript(button, "OnMouseDown", band, DOWN)
        SecureHandlerWrapScript(button, "OnMouseUp", band, UP)
        SecureHandlerWrapScript(button, "OnClick", band, CLICK)
        button:HookScript("OnMouseDown", function()
            button.swiped = nil
            if InCombatLockdown() or not Turn:Enabled(wheel.side) then return end
            -- Un seul doigt tourne une roue : l'autre, si elle suivait encore, s'arrête.
            for _, other in pairs(wheels) do
                if other ~= wheel and other.dragging then Drop(other) end
            end
            wheel.dragging, wheel.dragFrom, wheel.dragOffset = true, CursorAngle(wheel), band:GetAttribute("offset") or 0
            wheel.held = false
        end)
        button:HookScript("OnMouseUp", function()
            if not wheel.dragging then return end
            wheel.dragging = false
            if InCombatLockdown() then return end
            -- Un glissé ne doit pas non plus ouvrir le sélecteur d'une case vide (PostClick).
            local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
            if turns >= SWIPE or turns <= -SWIPE then button.swiped = true end
            -- Le code sécurisé a déjà arrondi au cran le plus proche, ou laissé la roue où elle
            -- était pour un simple toucher ; on s'aligne dessus et on le retient.
            local offset = band:GetAttribute("offset") or 0
            Place(wheel, offset)
            Settings(wheel).turnOffset = offset
        end)
    end
end

-- Hors combat : la géométrie, les positions d'avance pour le code sécurisé, puis les sorts.
local function LayoutWheel(wheel)
    local buttons, band = attached[wheel.side], wheel.band
    if not buttons or InCombatLockdown() then return end
    Wrap(wheel)
    local turning = Turn:Enabled(wheel.side)
    band:SetAttribute("turning", turning)
    -- Un sort de la roue part au relâchement du doigt, pour qu'un glissé puisse l'annuler, et ne
    -- se glisse-dépose pas : le relâchement doit lui revenir (voir en tête).
    for _, button in ipairs(buttons) do
        if turning then
            button:SetAttribute("useOnKeyDown", false)
            pcall(button.RegisterForDrag, button)
        else
            button:SetAttribute("useOnKeyDown", nil)
            pcall(button.RegisterForDrag, button, "LeftButton")
        end
    end
    if not turning then band:Hide(); return end
    local settings = Settings(wheel)
    local count = math.max(0, math.min(settings.count, #buttons))
    local radius, step = Turn.Geometry(UIParent:GetWidth(), UIParent:GetHeight(), count, settings.spread)
    local size = radius + SIZE
    band.radius = radius
    band.buttonScale = (settings.scale or 100) / 100
    band:SetSize(size, size)
    band:SetAttribute("size", size)
    band:SetAttribute("mirror", wheel.mirror)
    band:SetAttribute("corner", wheel.corner)
    band:SetAttribute("count", count)
    band:SetAttribute("step", step)
    local offset = count > 0 and math.floor(tonumber(settings.turnOffset) or 0) % count or 0
    band:SetAttribute("offset", offset)
    for slot = 0, math.max(0, count - 1) do
        local x, y = Point(wheel, radius, FIRST + slot * step)
        band:SetAttribute("x" .. slot, x / band.buttonScale)
        band:SetAttribute("y" .. slot, y / band.buttonScale)
    end
    for index = 1, count do band:SetFrameRef("b" .. index, buttons[index]) end
    band:Show()
    Place(wheel, offset)
end

function Turn:Layout()
    for _, side in ipairs(ORDER) do
        if wheels[side] then LayoutWheel(wheels[side]) end
    end
end

-- Le combat fini, le cran où chaque roue s'est arrêtée est retenu.
ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for _, side in ipairs(ORDER) do
        local wheel = wheels[side]
        if wheel and attached[side] and Turn:Enabled(side) then
            Settings(wheel).turnOffset = wheel.band:GetAttribute("offset") or 0
        end
    end
end)
