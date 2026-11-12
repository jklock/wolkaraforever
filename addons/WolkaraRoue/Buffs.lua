-- Interface mobile : les effets du joueur (améliorations, affaiblissements). Ce sont ceux du jeu,
-- avec leurs durées, leurs bulles d'aide et leur annulation (appui long), mais en petit, juste
-- sous ta barre en haut à gauche, les affaiblissements dessous : à leur place d'origine, en haut
-- à droite près de la mini-carte, ils recouvraient les raccourcis. Ils étaient à droite de ta
-- barre ; ta cible y est depuis la 0.9.1 (demandé sur l'iPhone, 2026-11-09), et la carte des
-- quêtes descend sous eux. Barres de vie éteintes, ils reprennent la place que leur donne le jeu.
--
-- Le jeu (son Mode Édition) les replace parfois de lui-même : on repasse derrière, hors combat.

local _, ns = ...

local Buffs = ns.Register("Effets du joueur", {})
ns.Buffs = Buffs

local SCALE = 0.65
local FRAMES = { "BuffFrame", "DebuffFrame" }
local GAP = 8
local placing, moved, waiting = false, false, false

local function Apply()
    local player = ns.HudPlayer
    if ns.db.hud.enabled and player then
        local anchor, relative, x, y = player, "BOTTOMLEFT", 0, -GAP / 2 / SCALE
        for _, name in ipairs(FRAMES) do
            local frame = _G[name]
            if frame and frame.ClearAllPoints then
                frame:SetScale(SCALE)
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", anchor, relative, x, y)
                anchor, relative, x, y = frame, "BOTTOMLEFT", 0, -4
            end
        end
        moved = true
    elseif moved then
        for _, name in ipairs(FRAMES) do
            local frame = _G[name]
            if frame and frame.SetScale then
                frame:SetScale(1)
                if frame.ApplySystemAnchor then frame:ApplySystemAnchor() end
            end
        end
        moved = false
    end
end

function Buffs.Place()
    if placing or not ns.db then return end
    if InCombatLockdown() then waiting = true; return end
    waiting = false
    placing = true
    local ok, problem = pcall(Apply)
    placing = false
    if not ok then error(problem, 0) end
end

local function Later()
    if placing then return end
    if C_Timer and C_Timer.After then C_Timer.After(0, function() ns.Guard("effets du joueur", Buffs.Place) end)
    else ns.Guard("effets du joueur", Buffs.Place) end
end

function Buffs:Init()
    if not hooksecurefunc then return end
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if frame and frame.SetPoint then hooksecurefunc(frame, "SetPoint", Later) end
    end
end

function Buffs:Layout() Buffs.Place() end

ns.On("EDIT_MODE_LAYOUTS_UPDATED", Later)
ns.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(1, Later) else Later() end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if waiting then Later() end end)
