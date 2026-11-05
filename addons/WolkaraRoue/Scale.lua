-- Interface mobile : la taille de toute l'interface. Sur un écran de tablette, l'interface du
-- jeu est réglée comme pour un grand moniteur : le texte des quêtes et du chat y fait à peine
-- un millimètre. On agrandit tout ensemble (170 % par défaut), cadres du jeu compris, pour
-- que le texte se lise et qu'un bouton fasse environ un centimètre sous le doigt.
--
-- Ce module passe en premier : les autres placent leurs éléments en proportion de l'écran,
-- une fois la taille appliquée.

local _, ns = ...

local Scale = ns.Register("Taille de l'interface", {})
local base, applied

local function Apply()
    if InCombatLockdown() then return end
    local current = UIParent:GetScale()
    -- Le jeu a pu recalculer sa propre taille (changement d'écran) : on repart de la sienne.
    if not applied or math.abs(current - applied) > 0.001 then base = current end
    applied = base * ns.db.ui.scale / 100
    UIParent:SetScale(applied)
end

function Scale:Layout() Apply() end

local function Recompute()
    if not ns.db then return end
    local function again()
        -- Pas de remise à zéro ici : si la taille du jeu n'a pas changé, la nôtre est déjà
        -- appliquée et on ne doit pas l'agrandir une seconde fois.
        if InCombatLockdown() then return end
        ns.Layout()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, again) else again() end
end
ns.On("UI_SCALE_CHANGED", Recompute)
ns.On("DISPLAY_SIZE_CHANGED", Recompute)
