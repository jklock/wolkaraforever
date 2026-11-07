-- Interface mobile : l'enregistrement.
--
-- Le jeu n'écrit WolkaraRoueDB sur le disque qu'en rechargeant l'interface ou en quittant
-- proprement. Sur le téléphone, une session finit souvent autrement : l'app balayée, iOS qui
-- la ferme en arrière-plan, la maison de la barre d'outils. Rien n'était alors écrit : le
-- 2026-11-05, une session entière n'a laissé aucune sauvegarde, et les sorts rangés pendant
-- celle-ci manquaient au lancement suivant.
--
-- Après un changement (un sort rangé ou retiré, un élément déplacé, un réglage), l'interface
-- se recharge donc d'elle-même dès qu'on a fini : hors combat, sans sélecteur, réglages, menu
-- ni mode Personnaliser ouverts, et rien touché depuis quelques secondes. C'est ce
-- rechargement qui écrit le fichier.

local _, ns = ...

local AFTER_CHANGE = 4  -- secondes sans nouveau changement
local AFTER_IDLE = 1.5  -- secondes sans rien d'ouvert
local changedAt, idleSince

function ns.MarkChanged()
    if ns.db then changedAt = GetTime() end
end

function ns.SavePending() return changedAt ~= nil end

local function Busy()
    if InCombatLockdown() or ns.editing then return true end
    for _, module in ipairs({ ns.Picker, ns.Settings, ns.Menu }) do
        if module and module.IsOpen and module:IsOpen() then return true end
    end
    return false
end

-- Une vérification : vrai quand elle a lancé l'enregistrement.
function ns.SaveTick(now)
    if not changedAt or not ns.db then return false end
    if Busy() then idleSince = nil; return false end
    idleSince = idleSince or now
    if now - changedAt < AFTER_CHANGE or now - idleSince < AFTER_IDLE then return false end
    changedAt, idleSince = nil, nil
    ns.db.justSaved = true
    ns.Print("enregistrement de tes réglages : l'interface se recharge.")
    ReloadUI()
    return true
end

local saver = CreateFrame("Frame")
local since = 0
saver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.5 then return end
    since = 0
    ns.SaveTick(GetTime())
end)

ns.On("PLAYER_LOGIN", function()
    if ns.db and ns.db.justSaved then
        ns.db.justSaved = nil
        ns.Print("réglages enregistrés.")
    end
end)
