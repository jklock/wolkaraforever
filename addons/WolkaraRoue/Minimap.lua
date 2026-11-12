-- Interface mobile : la mini-carte. Agrandie avec le reste de l'interface, elle prenait près
-- d'un tiers de la hauteur de l'écran et recouvrait le raccourci Menu. Le panneau Mobile règle
-- sa taille (60 % par défaut) ou la range, avec tout ce qui l'entoure (nom de la zone, heure,
-- suivi), dans un cadre invisible comme les autres cadres du jeu que l'addon remplace.
--
-- La toucher ouvre la carte du monde : plus besoin d'un bouton Carte à l'écran (idée de
-- scarrdi94, #26). Le bouton droit garde ce que le jeu en fait.
--
-- Au doigt, sans ouvrir le panneau : « + » et « - » à gauche de la carte changent sa taille
-- (10 % par appui, de 30 à 150 %), et pincer au-dessus d'elle la zoome. L'app transmet le
-- pincement en molette là où sont les doigts ; la mini-carte la reçoit maintenant au lieu de la
-- laisser à la caméra.

local _, ns = ...

local Mini = ns.Register("Mini-carte", {})
ns.Minimap = Mini
local hider = CreateFrame("Frame")
hider:Hide()
local home
local STEP, SMALLEST, LARGEST = 10, 30, 150
local sizer

function Mini.Resize(delta)
    if InCombatLockdown() or not ns.db then return end
    local settings = ns.db.minimap
    local scale = math.max(SMALLEST, math.min(LARGEST, (settings.scale or 60) + delta))
    if scale == settings.scale then return end
    settings.scale = scale
    if ns.MarkChanged then ns.MarkChanged("taille de la mini-carte") end
    Mini:Layout()
end

-- Un cran de molette (ou de pincement) : un niveau de zoom, dans les bornes du jeu.
function Mini.Zoom(map, delta)
    if not map or not map.GetZoom or not map.SetZoom then return end
    local levels = map.GetZoomLevels and map:GetZoomLevels() or 6
    local zoom = map:GetZoom() + (delta > 0 and 1 or -1)
    map:SetZoom(math.max(0, math.min(levels - 1, zoom)))
end

function Mini.OpenMap(map, button)
    if button == "RightButton" and map.wmGameUp then return map.wmGameUp(map, button) end
    if ToggleWorldMap then ToggleWorldMap() end
end

local function Sizer()
    local map = _G.Minimap
    if sizer or not map or not ns.UIButton then return sizer end
    if map.GetScript and map.SetScript then
        map.wmGameUp = map:GetScript("OnMouseUp")
        map:SetScript("OnMouseUp", Mini.OpenMap)
    end
    if map.EnableMouseWheel then
        map:EnableMouseWheel(true)
        -- Une version du jeu qui zoome déjà à la molette garde la sienne.
        if not map:GetScript("OnMouseWheel") then map:SetScript("OnMouseWheel", Mini.Zoom) end
    end
    sizer = CreateFrame("Frame", "WolkaraMobileMinimapSize", UIParent)
    sizer:SetSize(34, 74)
    sizer:SetFrameStrata("MEDIUM")
    sizer:SetPoint("TOPRIGHT", map, "TOPLEFT", -6, 0)
    local larger = ns.UIButton(sizer, "+", 34, 34, function() Mini.Resize(STEP) end)
    larger:SetPoint("TOP")
    local smaller = ns.UIButton(sizer, "-", 34, 34, function() Mini.Resize(-STEP) end)
    smaller:SetPoint("BOTTOM")
    sizer.larger, sizer.smaller = larger, smaller
    return sizer
end

function Mini:Layout()
    local cluster = _G.MinimapCluster
    if not cluster then return end
    local settings = ns.db.minimap
    local controls = Sizer()
    if settings.shown then
        if cluster:GetParent() == hider then cluster:SetParent(home or UIParent) end
        cluster:SetScale(settings.scale / 100)
        if controls then controls:Show() end
    else
        if cluster:GetParent() ~= hider then
            home = cluster:GetParent() or UIParent
            cluster:SetParent(hider)
        end
        if controls then controls:Hide() end
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
