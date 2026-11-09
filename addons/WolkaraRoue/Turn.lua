-- Interface mobile : les roues qui tournent.
--
-- Les sorts de chaque côté forment une grande roue centrée sur le coin bas de l'écran, celle de
-- gauche en miroir de celle de droite. On n'en voit que le quart au-dessus du stick, vers le
-- centre de l'écran ; les autres sorts attendent hors de l'écran et reviennent quand on la fait
-- tourner. Elle ne passe jamais sous le stick (à droite, c'est là qu'est le saut).
--
-- Chaque côté a ses roues : quatre par défaut, de une à six (réglage « Roues »), demandé sur
-- l'iPhone le 2026-11-09. On en voit une à la fois, vide ou non : une roue vide montre ses cases
-- (Free.lua), qu'un toucher remplit. On passe à une autre de deux façons, en combat aussi : par
-- ses onglets numérotés, en arc juste au-dessus de la roue, qui disent aussi laquelle on voit ;
-- ou d'un glissé en diagonale depuis la roue, vers le centre de l'écran pour la suivante, vers
-- le coin pour la précédente, en boucle. La roue qui arrive s'allume sort après sort, dans le
-- sens du glissé. Un glissé est une diagonale s'il fait au moins PAGE_SWIPE unités et s'écarte
-- de moins de 35° de la diagonale : le long de la roue, là où l'on glisse pour la faire tourner,
-- le doigt va à plus de 45° de là, sur tout le quart visible.
--
-- On la fait tourner en glissant le doigt depuis un de ses sorts, le long de la roue ; toucher
-- un sort sans glisser le lance, au moment où l'on relève le doigt. Ailleurs, rien n'est capté :
-- un glissé à côté des sorts reste à la caméra. Hors combat, les sorts suivent le doigt. En
-- combat, le jeu ne laisse bouger ses boutons que par son code sécurisé, qui ne voit que l'appui
-- et le relâchement : la roue tourne alors d'autant de crans, ou passe à une autre, au moment
-- où l'on relève le doigt. Ce code sécurisé ne fait que de l'arithmétique et lit des positions
-- calculées d'avance. Il ne suit que le bouton gauche : l'appui long, que l'app donne en clic
-- droit, et le glissé du bouton droit qui le suit sont à Free.lua (déplacer un sort).
--
-- La roue de gauche se calcule comme celle de droite vue dans un miroir : mêmes angles, mêmes
-- crans, positions retournées de gauche à droite. Rien ne dessine les roues : ni disque ni
-- ombre, seuls leurs sorts (et leurs onglets) sont à l'écran.
--
-- Le code sécurisé est accroché à chaque sort par le gabarit de l'appui et du relâchement
-- (attributs _onmousedown et _onmouseup) : le jeu refuse d'envelopper ces deux moments
-- (« Unsupported script type 'OnMouseDown' », 2026-11-09). Hors combat, l'addon calcule aussi
-- le relâchement lui-même, comme le ferait le code sécurisé.
--
-- Un glissé finit toujours. Un glissé du bouton gauche n'est jamais un glisser-déposer du jeu,
-- qui peut ne jamais rendre au sort le relâchement du doigt (la roue suivait alors le curseur
-- après coup, et les deux roues tournaient ensemble, 2026-11-07). Hors combat, un glissé dont le
-- doigt s'est relevé sans que le jeu le dise se termine quand même, et en commencer un sur une
-- roue arrête les autres.

local _, ns = ...

local Turn = ns.Register("Roues tournantes", {})
ns.Turn = Turn

local SIZE = 64         -- un sort, comme les boutons libres
local FIRST = 95        -- le premier emplacement, en degrés depuis le bord (sens direct, vu de droite)
local TAB_LOW = 135     -- l'onglet le plus bas, sur la diagonale du quart visible
local SWIPE = 0.35      -- en crans : en deçà, le doigt a touché le sort ; au-delà, il a glissé
local PAGE_SWIPE = 40   -- en unités : la longueur d'un glissé en diagonale qui change de roue
local DIAGONAL = 2      -- (le long)² ≥ 2 (en travers)² : à moins de 35° de la diagonale
local REACH = 3         -- la bande dépasse la roue de trois sorts : un glissé qui finit au-delà se lit
local TAB, TAB_GAP = 34, 8          -- un onglet de roue, et l'écart entre deux
local FADE, STAGGER = 0.22, 0.045   -- une roue qui arrive : chaque sort en FADE, le suivant STAGGER après
Turn.SWIPE, Turn.PAGE_SWIPE = SWIPE, PAGE_SWIPE
Turn.FADE, Turn.STAGGER = FADE, STAGGER

local SIDES = {
    right = { key = "free", name = "WolkaraMobileTurn", corner = "BOTTOMRIGHT", mirror = false },
    left = { key = "freeLeft", name = "WolkaraMobileTurnLeft", corner = "BOTTOMLEFT", mirror = true },
}
local ORDER = { "right", "left" }
local sides, attached = {}, {}
local animator, playing

local function PageSettings(wheel) return ns.PageData(ns.db[wheel.key], wheel.page) end

-- Toujours vrai depuis la 0.8 (le mode « Arc » est parti) ; gardé pour qui le demande.
function Turn:Enabled() return true end

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

-- Un glissé de (dx, dy), dx compté du coin vers l'intérieur de l'écran (retourné à gauche), dy
-- vers le haut : 1 en diagonale vers le centre de l'écran (la roue suivante), -1 vers le coin
-- (la précédente), 0 sinon.
function Turn.Diagonal(dx, dy)
    if dx * dx + dy * dy < PAGE_SWIPE * PAGE_SWIPE then return 0 end
    local along, across = dx + dy, dx - dy
    if along * along < DIAGONAL * across * across then return 0 end
    return along > 0 and 1 or -1
end

local function Point(wheel, radius, degrees)
    local angle = math.rad(degrees)
    local x, y = radius * math.cos(angle), radius * math.sin(angle)
    if wheel.mirror then x = -x end
    return x, y
end

-- Les boutons ont la taille des boutons libres : un décalage se compte à leur échelle.
local function Place(wheel, offset)
    local band, buttons = wheel.band, wheel.buttons
    if not buttons or InCombatLockdown() or not band.radius then return end
    local count = band:GetAttribute("count") or 0
    local radius, step, scale = band.radius, band:GetAttribute("step"), band.buttonScale or 1
    for index = 1, count do
        local x, y = Point(wheel, radius, Turn.Angle(index, offset, count, step))
        buttons[index]:ClearAllPoints()
        buttons[index]:SetPoint("CENTER", band, wheel.corner, x / scale, y / scale)
    end
end

-- Le doigt vu du coin de la roue, hors code sécurisé : vers l'intérieur de l'écran, et en haut.
local function CursorPoint(wheel)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    return wheel.mirror and x or UIParent:GetWidth() - x, y
end
local function AngleOf(px, py) return math.deg(math.atan2(py, -px)) end

-- ---------------------------------------------------------------------------------------
-- Les roues d'un côté

-- La roue d'à côté dans un sens (1 ou -1), en boucle parmi les roues du côté ; nil s'il n'y en
-- a qu'une.
function Turn.NextPage(side, direction)
    local state = sides[side]
    if not state then return nil end
    local pages = state.pager:GetAttribute("pages") or 1
    if pages < 2 then return nil end
    local page = state.pager:GetAttribute("page") or 1
    return (page - 1 + direction) % pages + 1
end

-- Hors combat : montre la roue `page` d'un côté, cache les autres.
function Turn.ShowPage(side, page)
    local state = sides[side]
    if not state or InCombatLockdown() then return end
    for index, wheel in ipairs(state.wheels) do wheel.band:SetShown(index == page) end
    state.pager:SetAttribute("page", page)
    if ns.db then ns.db[state.key].page = page end
end

function Turn.Step(side, direction)
    local target = Turn.NextPage(side, direction)
    if target then Turn.ShowPage(side, target) end
    return target
end

function Turn.CurrentPage(side)
    local state = sides[side]
    return state and state.pager:GetAttribute("page") or 1
end

-- Les onglets d'un côté disent quelle roue on voit : le sien doré, les autres sombres. Rien que
-- des couleurs, qui changent aussi en combat.
local function Highlight(state)
    local page = state.pager:GetAttribute("page") or 1
    for index, tab in ipairs(state.tabs) do
        if index == page then
            tab.face:SetVertexColor(1, 0.82, 0.3, 0.95)
            tab.rim:SetVertexColor(1, 0.93, 0.62, 1)
            tab.label:SetTextColor(0.13, 0.09, 0.02, 1)
        else
            tab.face:SetVertexColor(0.05, 0.05, 0.08, 0.88)
            tab.rim:SetVertexColor(1, 0.82, 0.3, 0.45)
            tab.label:SetTextColor(0.92, 0.92, 0.92, 0.9)
        end
    end
end

-- Les onglets, en arc juste au-dessus de la roue : le plus bas sur la diagonale, les autres en
-- montant vers le bord de l'écran ; de la 1 à gauche à la dernière à droite, des deux côtés.
-- Sur l'écran du Duo (951 x 669 points, 2026-11-09), un arc centré sur la diagonale touchait le
-- coin du chat ; partir de la diagonale vers le haut le laisse libre, jusqu'à six onglets.
-- Aucun quand il n'y a qu'une roue.
local function LayoutTabs(state, radius, scale, wheels, count)
    local info = SIDES[state.side]
    local distance = radius + SIZE * scale / 2 + 12 + TAB / 2
    local apart = math.deg((TAB + TAB_GAP) / distance)
    for index, tab in ipairs(state.tabs) do
        if wheels > 1 and count > 0 and index <= wheels then
            -- À droite, la 1 est la plus basse ; à gauche, en miroir, c'est la dernière.
            local rank = info.mirror and (wheels - index) or (index - 1)
            local x, y = Point(info, distance, TAB_LOW - rank * apart)
            tab:ClearAllPoints()
            tab:SetPoint("CENTER", UIParent, info.corner, x, y)
            tab:Show()
        else
            tab:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- Hors combat : le doigt suivi par l'addon

-- Un glissé laissé ouvert s'arrête, la roue revient au cran retenu.
local function Drop(wheel)
    wheel.dragging = false
    Place(wheel, wheel.band:GetAttribute("offset") or 0)
end

-- Le doigt s'est relevé (dit au sort, ou vu par l'addon). Une diagonale passe à une autre roue
-- (le code sécurisé l'a normalement déjà fait) ; sinon le glissé se finit comme le code
-- sécurisé l'aurait fait : au cran le plus proche, retenu pour le prochain lancement. Vrai si le
-- doigt a glissé.
local function Release(wheel)
    local band, state = wheel.band, wheel.state
    wheel.dragging = false
    local px, py = CursorPoint(wheel)
    local direction = Turn.Diagonal(px - wheel.fromX, py - wheel.fromY)
    if direction ~= 0 then
        Place(wheel, wheel.dragOffset or 0)
        if state.pager:GetAttribute("page") == wheel.page then
            Turn.Step(wheel.side, direction)
        elseif ns.db then
            ns.db[wheel.key].page = state.pager:GetAttribute("page")
        end
        return true
    end
    local count = band:GetAttribute("count") or 0
    local turns = (AngleOf(px, py) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
    local offset = wheel.dragOffset or 0
    local swiped = turns >= SWIPE or turns <= -SWIPE
    if count > 0 and swiped then
        offset = (offset + math.floor(turns + 0.5)) % count
    end
    band:SetAttribute("offset", offset)
    Place(wheel, offset)
    PageSettings(wheel).turnOffset = offset
    return swiped
end

local function Follow(wheel)
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
    local px, py = CursorPoint(wheel)
    -- En route pour une autre roue : celle-ci ne tourne pas.
    if Turn.Diagonal(px - wheel.fromX, py - wheel.fromY) ~= 0 then
        Place(wheel, wheel.dragOffset)
        return
    end
    local turns = (AngleOf(px, py) - wheel.dragFrom) / (wheel.band:GetAttribute("step") or 20)
    if turns < SWIPE and turns > -SWIPE then turns = 0 end
    Place(wheel, wheel.dragOffset + turns)
end

local function Pressed(wheel, button, mouse)
    if mouse and mouse ~= "LeftButton" then return end
    button.swiped = nil
    if InCombatLockdown() then return end
    -- Un seul doigt tourne une roue : les autres, si elles suivaient encore, s'arrêtent.
    for _, state in pairs(sides) do
        for _, other in ipairs(state.wheels) do
            if other ~= wheel and other.dragging then Drop(other) end
        end
    end
    local px, py = CursorPoint(wheel)
    wheel.dragging, wheel.held = true, false
    wheel.fromX, wheel.fromY, wheel.dragFrom = px, py, AngleOf(px, py)
    wheel.dragOffset = wheel.band:GetAttribute("offset") or 0
end

local function Lifted(wheel, button, mouse)
    if mouse and mouse ~= "LeftButton" then return end
    if not wheel.dragging then return end
    wheel.dragging = false
    if InCombatLockdown() then return end
    -- Un glissé ne doit pas non plus ouvrir le sélecteur d'une case vide (PostClick).
    if Release(wheel) then button.swiped = true end
end

-- ---------------------------------------------------------------------------------------
-- La roue qui arrive

-- Par-dessus chaque sort, un petit cadre à nous, qui ne prend aucun toucher et n'a pas de code
-- sécurisé : un voile sombre et un éclat doré. Le sort, bouton protégé du jeu, n'est jamais
-- touché : l'effet joue aussi en combat. Créé une fois, hors combat.
local function Effect(button)
    if button.wmArrive then return button.wmArrive end
    local fx = CreateFrame("Frame", nil, button)
    fx:SetAllPoints()
    fx:EnableMouse(false)
    fx:SetFrameLevel(button:GetFrameLevel() + 4)
    fx.veil = ns.Disc(fx, "ARTWORK", 0.02, 0.02, 0.04, 0.92, 4)
    fx.flash = ns.Disc(fx, "OVERLAY", 1, 0.84, 0.36, 1, 8)
    fx.flash:SetBlendMode("ADD")
    fx.flash:SetAlpha(0)
    fx:Hide()
    button.wmArrive = fx
    return fx
end

local function Finish()
    if playing then
        for _, item in ipairs(playing) do item.fx:Hide() end
        playing = nil
    end
    if animator then animator:Hide() end
end

-- Chaque sort se dévoile à son tour, avec un éclat qui monte puis s'éteint.
local function Tick()
    if not playing then Finish(); return end
    local now, done = GetTime() - playing.start, true
    for _, item in ipairs(playing) do
        local p = (now - item.delay) / FADE
        if p < 1 then done = false end
        p = math.max(0, math.min(1, p))
        local eased = 1 - (1 - p) * (1 - p)
        item.fx.veil:SetAlpha(1 - eased)
        item.fx.flash:SetAlpha(0.55 * math.sin(math.pi * p))
    end
    if done then Finish() end
end

-- `wheel` vient de paraître à la place de la roue `before` : ses sorts à l'écran s'allument du
-- haut de la roue vers le bas pour la suivante (ou par un onglet), de bas en haut pour la
-- précédente.
local function Animate(wheel, before)
    Finish()
    local band, buttons = wheel.band, wheel.buttons
    local count = band:GetAttribute("count") or 0
    if count < 1 or not buttons or not animator then return end
    local pages = wheel.state.pager:GetAttribute("pages") or 1
    local backward = pages > 2 and wheel.page == (before - 2) % pages + 1
    local offset, step = band:GetAttribute("offset") or 0, band:GetAttribute("step") or 20
    local list, last = {}, 0
    for index = 1, math.min(count, #buttons) do
        local button = buttons[index]
        local slot = (index - 1 + offset) % count
        -- Seulement ce qui se voit : une case affichée, sur le quart de roue à l'écran.
        if button.wmArrive and button:IsShown() and FIRST + slot * step <= 182 then
            list[#list + 1] = { fx = button.wmArrive, slot = slot }
            last = math.max(last, slot)
        end
    end
    if #list == 0 then return end
    for _, item in ipairs(list) do
        item.delay = (backward and (last - item.slot) or item.slot) * STAGGER
        item.fx.veil:SetAlpha(1)
        item.fx.flash:SetAlpha(0)
        item.fx:Show()
    end
    list.start = GetTime()
    playing = list
    animator:Show()
end

-- La roue de ce côté vient de paraître (onglet, diagonale, en combat ou non) : ses onglets le
-- disent, et elle s'allume. La disposition n'anime rien : elle note elle-même la roue qu'on voit.
local function Arrived(wheel)
    local state = wheel.state
    if state.visible == wheel.page then return end
    local before = state.visible
    state.visible = wheel.page
    Highlight(state)
    if not before then return end
    Animate(wheel, before)
    -- Pour le relire depuis le Mac dans la sauvegarde : combien de roues sont arrivées, dont en
    -- combat (le code sécurisé n'écrit rien ; ceci, si).
    if ns.db then
        local seen = type(ns.db.wheelSeen) == "table" and ns.db.wheelSeen or {}
        ns.db.wheelSeen = seen
        seen.arrived = (tonumber(seen.arrived) or 0) + 1
        if InCombatLockdown() then seen.combat = (tonumber(seen.combat) or 0) + 1 end
        seen.at = time and time() or nil
    end
end

-- ---------------------------------------------------------------------------------------
-- Le code sécurisé

-- La position du doigt sur la bande, vue de son coin : px vers l'intérieur de l'écran (retourné
-- à gauche), py vers le haut ; et son angle, entre 90 et 180 degrés, par une approximation de
-- l'arc tangente juste à un tiers de degré près (le code sécurisé n'a que l'arithmétique). Ces
-- extraits sont accrochés à chaque sort : self est le sort, owner la bande de sa roue.
local POSITION = [=[
    local mx, my = owner:GetMousePosition()
    local px, py, angle
    if mx then
        local size = owner:GetAttribute("size")
        px, py = mx * size, my * size
        if not owner:GetAttribute("mirror") then px = size - px end
        if px <= 0 then angle = 90
        else
            local t = py / px
            local inverse = t > 1
            if inverse then t = 1 / t end
            local a = 45 * t + 15.64 * t * (1 - t)
            if inverse then a = 90 - a end
            angle = 180 - a
        end
    end
]=]

-- Le glissé depuis l'appui (fx, fy) : 1 ou -1 en diagonale (Turn.Diagonal), 0 sinon.
local DIAGONAL_CODE = [=[
    local diagonal = 0
    if px and fx then
        local dx, dy = px - fx, py - fy
        if dx * dx + dy * dy >= ]=] .. PAGE_SWIPE * PAGE_SWIPE .. [=[ then
            local along, across = dx + dy, dx - dy
            if along * along >= ]=] .. DIAGONAL .. [=[ * across * across then
                if along > 0 then diagonal = 1 else diagonal = -1 end
            end
        end
    end
]=]

-- Montre la roue `target` du côté de `pager`, cache les autres : commun au glissé en diagonale
-- et aux onglets.
local SWITCH = [=[
    for i = 1, ]=] .. ns.PAGES .. [=[ do
        local band = pager:GetFrameRef("band" .. i)
        if band then
            if i == target then band:Show() else band:Hide() end
        end
    end
    pager:SetAttribute("page", target)
]=]

-- Le bouton de la souris : « button », dans le gabarit de l'appui et du relâchement. S'il ne
-- venait pas, tout serait pris pour le bouton gauche, comme avant la 0.8.
local DOWN = [=[
    if button and button ~= "LeftButton" then return end
    owner:SetAttribute("swiped", nil)
]=] .. POSITION .. [=[
    owner:SetAttribute("downangle", angle)
    owner:SetAttribute("downx", px)
    owner:SetAttribute("downy", py)
]=]

local UP = [=[
    if button and button ~= "LeftButton" then return end
]=] .. POSITION .. [=[
    local from, fx, fy = owner:GetAttribute("downangle"), owner:GetAttribute("downx"), owner:GetAttribute("downy")
    owner:SetAttribute("downangle", nil)
    local count = owner:GetAttribute("count")
    if not angle or not from or not count or count < 1 then return end
]=] .. DIAGONAL_CODE .. [=[
    if diagonal ~= 0 then
        owner:SetAttribute("swiped", true)
        local pager = owner:GetFrameRef("pager")
        local page, pages = pager:GetAttribute("page"), pager:GetAttribute("pages")
        if page and pages and pages > 1 then
            local target = (page - 1 + diagonal) % pages + 1
]=] .. SWITCH .. [=[
        end
        return
    end
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
        local spell = owner:GetFrameRef("b" .. index)
        spell:ClearAllPoints()
        spell:SetPoint("CENTER", owner, corner, owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
    end
]=]

-- Accrochés au sort lui-même (gabarit de l'appui et du relâchement) : self est le sort, la
-- bande se retrouve par sa référence.
local PRESS = [=[
    local owner = self:GetFrameRef("wheel")
    if not owner then return end
]=] .. DOWN
local LIFT = [=[
    local owner = self:GetFrameRef("wheel")
    if not owner then return end
]=] .. UP

-- Un glissé a tourné la roue ou changé de roue : le sort sous le doigt n'est pas lancé. Si le
-- jeu passe le clic avant le relâchement, le glissé se mesure ici aussi.
local CLICK = [=[
    if button and button ~= "LeftButton" then return end
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
    local from, fx, fy = owner:GetAttribute("downangle"), owner:GetAttribute("downx"), owner:GetAttribute("downy")
    if down or not from then return end
]=] .. POSITION .. [=[
    if not angle then return end
]=] .. DIAGONAL_CODE .. [=[
    if diagonal ~= 0 then return false end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns >= ]=] .. SWIPE .. [=[ or turns <= -]=] .. SWIPE .. [=[ then return false end
]=]

-- Un onglet touché montre sa roue (gabarit du clic sécurisé : self est l'onglet).
local TAB_CLICK = [=[
    local pager = self:GetFrameRef("pager")
    if not pager then return end
    local target, pages = self:GetAttribute("page"), pager:GetAttribute("pages")
    if not target or not pages or target > pages or target == pager:GetAttribute("page") then return end
]=] .. SWITCH

-- ---------------------------------------------------------------------------------------

-- L'onglet d'une roue : un rond numéroté, cerclé d'or.
local function MakeTab(state, info, index)
    local tab = CreateFrame("Button", info.name .. "Tab" .. index, UIParent, "SecureHandlerClickTemplate")
    tab:SetFrameStrata("LOW")
    tab:SetSize(TAB, TAB)
    tab:RegisterForClicks("AnyUp")
    tab:SetHitRectInsets(-3, -3, -6, -6)
    tab:SetAttribute("page", index)
    tab:SetFrameRef("pager", state.pager)
    tab:SetAttribute("_onclick", TAB_CLICK)
    tab.rim = ns.Disc(tab, "BACKGROUND", 1, 0.82, 0.3, 0.45, 1)
    tab.face = ns.Disc(tab, "BORDER", 0.05, 0.05, 0.08, 0.88, -1)
    tab.label = ns.Label(tab, "GameFontNormal", tostring(index))
    tab.label:SetPoint("CENTER", 0, 0)
    local glow = ns.Disc(tab, "HIGHLIGHT", 1, 1, 1, 0.2, 0)
    glow:SetBlendMode("ADD")
    tab:Hide()
    return tab
end

function Turn:Init()
    animator = CreateFrame("Frame")
    animator:Hide()
    animator:SetScript("OnUpdate", Tick)
    for _, side in ipairs(ORDER) do
        local info = SIDES[side]
        -- Ce qui sait quelle roue on voit (attribut page) et combien le côté en a (pages), pour
        -- le code sécurisé du glissé et des onglets.
        local pager = CreateFrame("Frame", info.name .. "Pages", UIParent, "SecureHandlerBaseTemplate")
        pager:SetAttribute("pages", ns.WHEELS or ns.PAGES)
        pager:SetAttribute("page", 1)
        local state = { side = side, key = info.key, pager = pager, wheels = {}, tabs = {} }
        for page = 1, ns.PAGES do
            -- Une bande par roue : un carré invisible sur le coin, qui ne prend aucun toucher ; les
            -- sorts de la roue sont ses enfants, si bien que la cacher cache la roue.
            local band = CreateFrame("Frame", page == 1 and info.name or (info.name .. page), UIParent,
                "SecureHandlerBaseTemplate")
            band:SetFrameStrata("LOW")
            band:SetPoint(info.corner, UIParent, info.corner)
            band:EnableMouse(false)
            band:Hide()
            band:SetAttribute("page", page)
            band:SetFrameRef("pager", pager)
            pager:SetFrameRef("band" .. page, band)
            local wheel = { side = side, key = info.key, page = page, corner = info.corner,
                mirror = info.mirror, band = band, state = state }
            band:SetScript("OnUpdate", function() Arrived(wheel); Follow(wheel) end)
            state.wheels[page] = wheel
        end
        for index = 1, ns.PAGES do state.tabs[index] = MakeTab(state, info, index) end
        sides[side] = state
    end
end

-- Free nous confie ses boutons, une liste par roue, une fois créés (avant notre Init : il passe
-- avant nous).
function Turn:Attach(pages, side) attached[side or "right"] = pages end

-- Une fois, hors combat : chaque sort rejoint la bande de sa roue, avec le code sécurisé, le
-- suivi du doigt et son effet d'arrivée.
local function Wrap(state)
    local pages = attached[state.side]
    if state.wrapped or not pages or InCombatLockdown() then return end
    state.wrapped = true
    for page, wheel in ipairs(state.wheels) do
        local band, buttons = wheel.band, pages[page] or {}
        wheel.buttons = buttons
        for _, button in ipairs(buttons) do
            button:SetParent(band)
            button:SetFrameStrata("LOW")
            if button.securePressRelease ~= false then
                button:SetFrameRef("wheel", band)
                button:SetAttribute("_onmousedown", PRESS)
                button:SetAttribute("_onmouseup", LIFT)
            end
            SecureHandlerWrapScript(button, "OnClick", band, CLICK)
            button:HookScript("OnMouseDown", function(_, mouse) Pressed(wheel, button, mouse) end)
            button:HookScript("OnMouseUp", function(_, mouse) Lifted(wheel, button, mouse) end)
            Effect(button)
        end
    end
end

-- Hors combat : la géométrie, les positions d'avance pour le code sécurisé, le nombre de roues,
-- celle qu'on voit, les sorts, puis les onglets.
local function LayoutSide(state)
    if InCombatLockdown() or not ns.db then return end
    Wrap(state)
    if not state.wrapped then return end
    local settings = ns.db[state.key]
    -- La roue qu'on voit et le cran de chacune sont d'abord ceux de l'écran : en combat, seul le
    -- code sécurisé les change, et le jeu peut refaire la disposition à la fin du combat avant
    -- que PLAYER_REGEN_ENABLED ne les ait retenus ; repartir de la sauvegarde ramenait alors la
    -- roue à son ancien cran.
    if state.laidOut then
        settings.page = state.pager:GetAttribute("page") or settings.page
        for _, wheel in ipairs(state.wheels) do
            local live = wheel.band:GetAttribute("offset")
            if live then PageSettings(wheel).turnOffset = live end
        end
    end
    state.laidOut = true
    local count = math.max(0, math.min(tonumber(settings.count) or 0, ns.MAX_FREE))
    local wheels = math.max(1, math.min(ns.PAGES, math.floor(tonumber(settings.wheels) or ns.WHEELS or 1)))
    state.pager:SetAttribute("pages", wheels)
    local current = math.max(1, math.min(wheels, math.floor(tonumber(settings.page) or 1)))
    settings.page = current
    state.pager:SetAttribute("page", current)
    local radius, step = Turn.Geometry(UIParent:GetWidth(), UIParent:GetHeight(), count, settings.spread)
    local size = radius + SIZE * REACH
    local scale = (settings.scale or 100) / 100
    for page, wheel in ipairs(state.wheels) do
        local band, buttons = wheel.band, wheel.buttons
        -- Un sort de la roue part au relâchement du doigt, pour qu'un glissé puisse l'annuler. Il
        -- ne se glisse-dépose qu'au bouton droit (après un appui long, pour le déplacer).
        for _, button in ipairs(buttons) do
            button:SetAttribute("useOnKeyDown", false)
            pcall(button.RegisterForDrag, button, "RightButton")
        end
        local n = math.min(count, #buttons)
        band.radius = radius
        band.buttonScale = scale
        band:SetSize(size, size)
        band:SetAttribute("size", size)
        band:SetAttribute("mirror", wheel.mirror)
        band:SetAttribute("corner", wheel.corner)
        band:SetAttribute("count", n)
        band:SetAttribute("step", step)
        local offset = n > 0 and math.floor(tonumber(PageSettings(wheel).turnOffset) or 0) % n or 0
        band:SetAttribute("offset", offset)
        for slot = 0, math.max(0, n - 1) do
            local x, y = Point(wheel, radius, FIRST + slot * step)
            band:SetAttribute("x" .. slot, x / band.buttonScale)
            band:SetAttribute("y" .. slot, y / band.buttonScale)
        end
        for index = 1, n do band:SetFrameRef("b" .. index, buttons[index]) end
        band:SetShown(page == current)
        Place(wheel, offset)
    end
    LayoutTabs(state, radius, scale, wheels, count)
    state.visible = current
    Highlight(state)
end

function Turn:Layout()
    for _, side in ipairs(ORDER) do
        if sides[side] then LayoutSide(sides[side]) end
    end
    -- La taille de l'écran en unités de l'interface, relue depuis le Mac pour placer les éléments
    -- (les onglets, le chat, les quêtes se la partagent).
    if ns.db then
        ns.db.screenSeen = { width = math.floor(UIParent:GetWidth() + 0.5), height = math.floor(UIParent:GetHeight() + 0.5) }
    end
end

-- Le combat fini, la roue qu'on voit et le cran où chacune s'est arrêtée sont retenus.
ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for _, side in ipairs(ORDER) do
        local state = sides[side]
        if state and state.wrapped then
            ns.db[state.key].page = state.pager:GetAttribute("page") or ns.db[state.key].page
            for _, wheel in ipairs(state.wheels) do
                PageSettings(wheel).turnOffset = wheel.band:GetAttribute("offset") or 0
            end
        end
    end
end)
