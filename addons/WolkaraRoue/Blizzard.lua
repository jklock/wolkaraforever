-- Interface mobile : ce que l'on range de l'interface du jeu, parce que l'addon le remplace
-- par plus grand ou que c'est inutilisable au doigt.
--
--   barres de sorts (et l'expérience qu'elles portaient)  -> roues et boutons libres
--   cadres du joueur et de la cible                        -> barres de vie
--   suivi des objectifs sous la mini-carte                 -> carte des quêtes
--   le chat (rangé par le module Chat)                     -> chat mobile
--
-- Rien n'est caché : tout est rangé dans un cadre invisible, comme le font les addons de
-- barres d'action. Le jeu ne le réaffiche pas de lui-même, les raccourcis clavier ou manette
-- des barres marchent toujours, et chaque interrupteur du panneau Mobile remet en place.

local _, ns = ...

local Blizzard = ns.Register("Interface du jeu", {})
local hider = CreateFrame("Frame")
hider:Hide()

-- Selon la version du jeu, les cadres ne portent pas les mêmes noms : on prend ceux qui
-- existent.
local GROUPS = {
    bars = { "MainMenuBar", "MainActionBar", "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground",
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
        "MultiBar5", "MultiBar6", "MultiBar7", "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar",
        "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
    units = { "PlayerFrame", "TargetFrame", "TargetFrameToT" },
    tracker = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" },
}

local moved = {}

local function Hide(group)
    for _, name in ipairs(GROUPS[group]) do
        local frame = _G[name]
        if frame and frame.GetParent and frame:GetParent() ~= hider then
            moved[frame] = { parent = frame:GetParent() or UIParent, group = group }
            frame:SetParent(hider)
        end
    end
end

local function Restore(group)
    for frame, info in pairs(moved) do
        if info.group == group then
            frame:SetParent(info.parent)
            moved[frame] = nil
        end
    end
end

local function Set(group, hidden)
    if hidden then Hide(group) else Restore(group) end
end

function Blizzard:Layout()
    local settings = ns.db.blizzard
    Set("bars", settings.hideBars)
    -- Les cadres d'origine ne partent que si nos barres de vie sont là pour les remplacer.
    Set("units", settings.hideUnitFrames and ns.db.hud.enabled)
    Set("tracker", ns.db.quests.enabled)
end

-- Certains cadres sont créés plus tard (addons du jeu chargés à la demande).
ns.On("ADDON_LOADED", function()
    if ns.db and not InCombatLockdown() then Blizzard:Layout() end
end)
