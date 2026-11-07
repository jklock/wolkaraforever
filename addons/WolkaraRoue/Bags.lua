-- Interface mobile : les sacs.
--
-- Le jeu ouvre ses sacs dans le coin bas-droit, sous le stick droit et la roue : on ne pouvait
-- plus toucher ce qu'ils contiennent. Une fois que le jeu les a placés, on décale vers la
-- gauche ceux qui partent du bord droit, d'un peu plus que la largeur de la roue. Hors combat
-- seulement : leurs cases sont protégées et le jeu ne les laisse pas bouger en combat ; un sac
-- ouvert en combat est décalé dès que le combat finit.

local _, ns = ...

local Bags = ns.Register("Sacs", {})
local pending = false
local SHIFT = 0.36  -- de la largeur de l'écran

local function Containers()
    local list = {}
    if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then list[#list + 1] = frame end
    end
    return list
end

-- Appelé juste après que le jeu a replacé ses sacs (il repart de zéro à chaque fois).
function Bags.Shift()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local shift = UIParent:GetWidth() * SHIFT
    for _, frame in ipairs(Containers()) do
        if frame:IsShown() and frame:GetNumPoints() > 0 then
            local point, relative, relativePoint, x, y = frame:GetPoint(1)
            if (relative == nil or relative == UIParent) and relativePoint and relativePoint:find("RIGHT") then
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, relativePoint, (x or 0) - shift, y or 0)
            end
        end
    end
end

function Bags:Init()
    if type(UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", Bags.Shift)
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pending and type(UpdateContainerFrameAnchors) == "function" then UpdateContainerFrameAnchors() end
end)
