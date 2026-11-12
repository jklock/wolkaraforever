-- Interface mobile : les sacs.
--
-- Le jeu ouvre ses sacs dans le coin bas-droit, là où l'app pose le stick de la caméra et le
-- saut, et où tourne la roue de droite. Un toucher sur un sac y partait au saut : « quand
-- j'ouvre les sacs, le bouton de saut fout la merde » (iPhone, 2026-11-09 ; le journal de l'app
-- montre alors « jump caught » au milieu des clics droits sur les objets). L'app attrape pour le
-- saut tout le dessous du stick de la caméra, et ne sait rien des fenêtres du jeu : c'est aux
-- sacs de s'en écarter.
--
-- Jusqu'à la 0.7, on décalait d'une largeur fixe ceux que le jeu accrochait au bord droit de
-- l'écran, depuis UpdateContainerFrameAnchors : sur ce client, rien ne dit que cette fonction
-- existe ni que les sacs s'accrochent ainsi, et ils restaient sous le saut. Maintenant on part
-- de là où chaque pile de sacs est vraiment à l'écran, une fois que le jeu l'a placée (à son
-- ouverture, et chaque fois que le jeu les replace) : une pile qui entre dans le coin des
-- commandes, le bord droit de l'écran sur 36 % de sa largeur, glisse vers la gauche juste
-- assez pour en sortir, sans dépasser le bord gauche. Les autres ne bougent pas.
-- Hors combat seulement : le jeu protège leurs cases en combat ; un sac ouvert en combat est
-- placé dès que le combat finit. ns.db.bagsSeen garde le dernier placement, pour le mesurer.

local _, ns = ...

local Bags = ns.Register("Sacs", {})
local CLEAR = 0.36   -- la part de la largeur de l'écran, depuis la droite, laissée aux commandes
local MARGIN = 8
local pending, placing, waiting = false, false, false
Bags.CLEAR = CLEAR

local function Containers()
    local list = {}
    if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then list[#list + 1] = frame end
    end
    return list
end

local function IsContainer(frame, list)
    for _, container in ipairs(list) do if container == frame then return true end end
    return false
end

-- Le premier sac d'une pile : celui qui ne s'accroche pas à un autre sac.
local function RootOf(frame, list)
    for _ = 1, 20 do
        if not frame.GetNumPoints or frame:GetNumPoints() < 1 then return frame end
        local _, relative = frame:GetPoint(1)
        if relative and relative ~= frame and IsContainer(relative, list) then frame = relative else return frame end
    end
    return frame
end

-- Le rectangle d'un cadre en unités de UIParent : gauche, bas, droite, haut.
local function Rect(frame)
    local left, bottom, width, height = frame:GetRect()
    if not left then return nil end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, bottom * k, (left + width) * k, (bottom + height) * k
end

local function Note(seen)
    if type(ns.db) ~= "table" then return end
    seen.at = time and time() or nil
    seen.hook = type(UpdateContainerFrameAnchors) == "function"
    ns.db.bagsSeen = seen
end

function Bags.Place()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local list = Containers()
    local width = UIParent:GetWidth()
    local limit = width * (1 - CLEAR)
    -- Les piles de sacs ouverts, chacune avec le rectangle qui les entoure.
    local stacks, order = {}, {}
    for _, frame in ipairs(list) do
        if frame:IsShown() then
            local l, b, r, t = Rect(frame)
            if l then
                local root = RootOf(frame, list)
                local stack = stacks[root]
                if not stack then
                    stack = { root = root, l = l, b = b, r = r, t = t }
                    stacks[root] = stack
                    order[#order + 1] = stack
                else
                    stack.l, stack.b = math.min(stack.l, l), math.min(stack.b, b)
                    stack.r, stack.t = math.max(stack.r, r), math.max(stack.t, t)
                end
            end
        end
    end
    local seen = { stacks = #order, moved = 0 }
    for _, stack in ipairs(order) do
        seen.right = math.floor(stack.r / width * 100 + 0.5) / 100
        if stack.r > limit then
            local shift = math.min(stack.r - limit, stack.l - MARGIN)
            local root = stack.root
            local l, b = Rect(root)
            if shift > 0 and l then
                local k = UIParent:GetEffectiveScale() / root:GetEffectiveScale()
                placing = true
                root:ClearAllPoints()
                root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (l - shift) * k, b * k)
                placing = false
                seen.moved = seen.moved + 1
                seen.after = math.floor((stack.r - shift) / width * 100 + 0.5) / 100
            end
        end
    end
    Note(seen)
end

-- Après que le jeu a fini de placer ses sacs : au tour suivant.
local function Later()
    if placing or waiting then return end
    if C_Timer and C_Timer.After then
        waiting = true
        C_Timer.After(0, function()
            waiting = false
            ns.Guard("sacs", Bags.Place)
        end)
    else
        ns.Guard("sacs", Bags.Place)
    end
end
Bags.Later = Later

function Bags:Init()
    if type(UpdateContainerFrameAnchors) == "function" and hooksecurefunc then
        hooksecurefunc("UpdateContainerFrameAnchors", Later)
    end
    for _, frame in ipairs(Containers()) do
        if frame.HookScript then frame:HookScript("OnShow", Later) end
    end
end

ns.On("PLAYER_REGEN_ENABLED", function() if pending then Later() end end)
