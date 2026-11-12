-- Interface mobile : l'enregistrement.
--
-- Le jeu n'écrit WolkaraRoueDB sur le disque qu'en rechargeant l'interface ou en quittant
-- proprement. Sur le téléphone, une session finit souvent autrement : l'app balayée, iOS qui
-- la ferme en arrière-plan, la maison de la barre d'outils. Rien n'était alors écrit : le
-- 2026-11-05, une session entière n'a laissé aucune sauvegarde, et les sorts rangés pendant
-- celle-ci manquaient au lancement suivant. Et le jeu ne recharge l'interface pour un add-on
-- que sur un vrai toucher, par son propre /reload : appelé par une minuterie, ReloadUI ne fait
-- rien (mesuré sur l'iPhone, 2026-11-09).
--
-- Jusqu'à la 0.7, un changement faisait donc paraître, quelques secondes plus tard et en plein
-- jeu, un bouton « Enregistrer » au milieu de l'écran : il « apparaissait de manière random »
-- (iPhone, 2026-11-09). Maintenant rien ne surgit pendant qu'on joue. On enregistre en
-- finissant ce qu'on faisait : « Terminé » du mode Personnaliser et « Fermer » des réglages
-- rechargent l'interface s'il y a quelque chose à écrire. Entre-temps, un point doré sur le
-- bouton « ☰ » le rappelle, et son menu rapide a « Enregistrer » ; la tuile Quitter enregistre
-- aussi. Chaque changement note sa raison dans ns.db.saveLog, pour savoir ce qui l'a demandé.

local _, ns = ...

ns.RELOAD = "/stopmacro [combat]\n/reload"
local KEEP_LOG = 8
local pending = false
local listeners = {}

-- fn(pending) : appelée quand il y a quelque chose à enregistrer.
function ns.OnSavePending(fn) listeners[#listeners + 1] = fn end

function ns.MarkChanged(reason)
    local db = ns.db
    if not db then return end
    if type(db.saveLog) ~= "table" then db.saveLog = {} end
    table.insert(db.saveLog, 1, { reason = tostring(reason or "?"), at = time and time() or nil })
    while #db.saveLog > KEEP_LOG do table.remove(db.saveLog) end
    if pending then return end
    pending = true
    for _, fn in ipairs(listeners) do ns.Guard("enregistrement", fn, true) end
end

function ns.SavePending() return pending end

-- Juste avant le clic d'un bouton d'enregistrement : le /reload du jeu s'il y a quelque chose
-- à écrire (hors combat), rien sinon ; la ligne « réglages enregistrés » suivra le rechargement.
function ns.SavePreClick(secure, always)
    if InCombatLockdown() then return end
    local save = ns.db ~= nil and (pending or always == true)
    secure:SetAttribute("type", save and "macro" or nil)
    if save then ns.db.justSaved = true end
end

-- Un bouton sécurisé transparent posé sur `button` (Terminé, Fermer) : enregistre s'il y a
-- quelque chose à écrire, puis fait ce que fait le bouton (`after`).
function ns.SaveOver(button, after)
    local over = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    over:SetAllPoints(button)
    over:SetFrameLevel(button:GetFrameLevel() + 5)
    over:RegisterForClicks("AnyUp", "AnyDown")
    over:SetAttribute("macrotext", ns.RELOAD)
    over:SetScript("PreClick", function(self) ns.SavePreClick(self) end)
    over:SetScript("PostClick", function(_, _, down)
        if not down and after then ns.Guard("enregistrement", after) end
    end)
    return over
end

ns.On("PLAYER_LOGIN", function()
    if ns.db and ns.db.justSaved then
        ns.db.justSaved = nil
        ns.Print("réglages enregistrés.")
    end
end)
