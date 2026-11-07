-- Interface mobile : la mini-carte. Agrandie avec le reste de l'interface, elle prenait près
-- d'un tiers de la hauteur de l'écran et recouvrait le raccourci Menu. Le panneau Mobile règle
-- sa taille (60 % par défaut) ou la range, avec tout ce qui l'entoure (nom de la zone, heure,
-- suivi), dans un cadre invisible comme les autres cadres du jeu que l'addon remplace.

local _, ns = ...

local Mini = ns.Register("Mini-carte", {})
ns.Minimap = Mini
local hider = CreateFrame("Frame")
hider:Hide()
local home

function Mini:Layout()
    local cluster = _G.MinimapCluster
    if not cluster then return end
    local settings = ns.db.minimap
    if settings.shown then
        if cluster:GetParent() == hider then cluster:SetParent(home or UIParent) end
        cluster:SetScale(settings.scale / 100)
    elseif cluster:GetParent() ~= hider then
        home = cluster:GetParent() or UIParent
        cluster:SetParent(hider)
    end
end

-- Le Mode Édition du jeu remet sa propre taille à la mini-carte : on repasse derrière.
local function Again()
    if ns.db and not InCombatLockdown() then ns.Guard("mini-carte", Mini.Layout, Mini) end
end
ns.On("EDIT_MODE_LAYOUTS_UPDATED", Again)
ns.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(1, Again) else Again() end
end)
