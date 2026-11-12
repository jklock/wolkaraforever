-- Interface mobile : les fenêtres du jeu.
--
-- Agrandies avec toute l'interface (170 %), les fenêtres du jeu débordaient : la croix de la
-- carte du monde sortait de l'écran, et le bas des fenêtres de gauche (quête, PNJ, marchand,
-- journal) passait sous le stick gauche, qui prenait le toucher : « Terminer la quête » ne
-- répondait pas. À chaque ouverture, la fenêtre est réduite juste ce qu'il faut, jamais au-delà
-- de sa taille d'origine, et elle reste dans la place libre :
--   * entre les deux sticks, sur toute la hauteur, si elle y tient ;
--   * sinon au-dessus des sticks, sur toute la largeur, si elle y est plus grande ;
--   * la carte du monde prend tout l'écran : on la regarde, et sa croix reste en haut à droite.
-- Le jeu la place comme d'habitude ; il la décale seulement pour qu'elle reste dans cette place
-- (SetClampedToScreen et ses marges). En combat, le jeu ne laisse pas toucher à ses fenêtres
-- protégées : celles-là sont ajustées à la fin du combat.

local _, ns = ...

local Windows = ns.Register("Fenêtres du jeu", {})
ns.Windows = Windows

local MARGIN = 10
-- Autour du centre de chaque stick (ns.STICK_X, ns.STICK_Y) : l'anneau dessiné par l'app et une
-- marge, en hauteur d'écran.
local STICK_ZONE = 0.10
local WHOLE_SCREEN = { WorldMapFrame = true }
-- Les fenêtres connues ; les autres sont prises quand le jeu les ouvre (ShowUIPanel). Selon la
-- version du jeu, toutes n'existent pas, et certaines n'arrivent qu'avec leur module.
local NAMES = {
    "WorldMapFrame", "QuestFrame", "GossipFrame", "QuestLogFrame", "MerchantFrame", "LootFrame",
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "TaxiFrame", "FriendsFrame", "MailFrame",
    "BankFrame", "TradeFrame", "ClassTrainerFrame", "TalentFrame", "ItemTextFrame", "GameMenuFrame",
    "SettingsPanel", "InterfaceOptionsFrame", "VideoOptionsFrame", "PVEFrame", "LFGParentFrame",
    "PVPFrame", "CollectionsJournal", "EncounterJournal", "AchievementFrame", "AuctionFrame",
    "AuctionHouseFrame", "ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "GuildFrame",
    "CommunitiesFrame", "MacroFrame", "KeyBindingFrame", "HelpFrame",
}

local natural, pending, watched = {}, {}, {}
local busy = false

-- La taille et la place d'une fenêtre, en unités de l'interface : l'échelle à lui donner (par
-- rapport à l'interface), puis ce qu'elle doit laisser libre sur chaque côté et en bas.
-- `largest` est son échelle d'origine : on ne l'agrandit jamais.
function Windows.Placement(W, H, width, height, largest, whole)
    if whole then
        return math.min(largest, (W - 2 * MARGIN) / width, (H - 2 * MARGIN) / height), MARGIN, MARGIN
    end
    local side = W * ns.STICK_X + H * STICK_ZONE + MARGIN
    local low = H * ns.STICK_Y + H * STICK_ZONE + MARGIN
    local between = math.min(largest, (W - 2 * side) / width, (H - 2 * MARGIN) / height)
    local above = math.min(largest, (W - 2 * MARGIN) / width, (H - low - MARGIN) / height)
    if between >= above then return between, side, MARGIN end
    return above, MARGIN, low
end

-- Ce que la croix de fermeture dépasse du cadre, à droite et en haut, en unités de la fenêtre :
-- elle est parfois posée à cheval sur le bord, et c'est elle qu'il faut garder à l'écran.
local function Overhang(frame)
    local close = frame.CloseButton or (type(frame.BorderFrame) == "table" and frame.BorderFrame.CloseButton)
        or _G[(frame:GetName() or "") .. "CloseButton"]
    if type(close) ~= "table" or not close.GetRight or not close:IsShown() then return 0, 0 end
    local frameRight, frameTop, closeRight, closeTop = frame:GetRight(), frame:GetTop(), close:GetRight(), close:GetTop()
    if not (frameRight and frameTop and closeRight and closeTop) then return 0, 0 end
    local f, c = frame:GetEffectiveScale(), close:GetEffectiveScale()
    return math.max(0, (closeRight * c - frameRight * f) / f), math.max(0, (closeTop * c - frameTop * f) / f)
end

function Windows.Fit(frame)
    if busy or type(frame) ~= "table" or not frame.IsShown or not frame:IsShown() then return end
    if InCombatLockdown() and frame:IsProtected() then pending[frame] = true; return end
    -- Une fenêtre dont la taille vient de ses ancres suivrait l'échelle : on n'y touche pas.
    if frame:GetNumPoints() > 1 then return end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width < 1 or height < 1 then return end
    if natural[frame] == nil then natural[frame] = frame:GetScale() or 1 end
    local ui = UIParent:GetEffectiveScale()
    local parent = frame:GetParent()
    local parentScale = parent and parent:GetEffectiveScale() / ui or 1
    local right, top = Overhang(frame)
    local scale, side, low = Windows.Placement(UIParent:GetWidth(), UIParent:GetHeight(), width + right,
        height + top, natural[frame] * parentScale, WHOLE_SCREEN[frame:GetName() or ""])
    busy = true
    if math.abs(frame:GetScale() - scale / parentScale) > 0.001 then frame:SetScale(scale / parentScale) end
    frame:SetClampedToScreen(true)
    -- Les marges se comptent dans les unités de la fenêtre : une unité y vaut `scale` de l'interface.
    frame:SetClampRectInsets(-side / scale, side / scale + right, MARGIN / scale + top, -low / scale)
    busy = false
end

-- Une fenêtre qui se dimensionne en s'ouvrant (la carte) est reprise une image plus tard.
local function Again(frame)
    if C_Timer and C_Timer.After then C_Timer.After(0, function() Windows.Fit(frame) end) end
end

function Windows.Watch(frame)
    if type(frame) ~= "table" or watched[frame] or not frame.HookScript then return end
    watched[frame] = true
    frame:HookScript("OnShow", function(self) Windows.Fit(self); Again(self) end)
    frame:HookScript("OnSizeChanged", function(self) Windows.Fit(self) end)
end

local function WatchKnown()
    for _, name in ipairs(NAMES) do Windows.Watch(_G[name]) end
end

function Windows:Init()
    WatchKnown()
    if type(ShowUIPanel) == "function" and hooksecurefunc then
        hooksecurefunc("ShowUIPanel", function(frame)
            if type(frame) == "table" and frame.IsShown then Windows.Watch(frame); Windows.Fit(frame) end
        end)
    end
end

-- La taille de l'interface a changé : les fenêtres ouvertes se réajustent.
function Windows:Layout()
    for frame in pairs(watched) do
        if frame:IsShown() then Windows.Fit(frame) end
    end
end

ns.On("ADDON_LOADED", function() if ns.db then WatchKnown() end end)
ns.On("PLAYER_REGEN_ENABLED", function()
    for frame in pairs(pending) do
        pending[frame] = nil
        Windows.Fit(frame)
    end
end)
