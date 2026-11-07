-- Interface mobile : le bouton d'action commun aux roues et aux boutons libres.
--
-- Un bouton sécurisé du jeu, rond, avec la vraie icône, le temps de recharge et la couleur
-- de portée. Hors combat, toucher une case vide (ou n'importe quelle case en mode
-- Personnaliser) ouvre le sélecteur ; déposer un sort dessus le range aussi.

local _, ns = ...

-- Les actions toutes faites du sélecteur : des lignes de macro que le jeu exécute lui-même.
ns.BUILTIN = {
    { kind = "macrotext", id = "/targetenemy", name = "Cibler un ennemi", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { kind = "macrotext", id = "/startattack", name = "Attaque auto", icon = "Interface\\Icons\\INV_Sword_04" },
    { kind = "macrotext", id = "/assist", name = "Assister", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { kind = "macrotext", id = "/targetfriend", name = "Cibler un allié", icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { kind = "macrotext", id = "/cleartarget", name = "Effacer la cible", icon = "Interface\\Icons\\Spell_Shadow_Teleport" },
    { kind = "macrotext", id = "/follow", name = "Suivre", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
    { kind = "macrotext", id = "/sit", name = "S'asseoir", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
}

function ns.EntryIcon(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return ns.SpellIcon(entry.id) end
    if entry.kind == "item" then return ns.ItemIcon(entry.id) end
    if entry.kind == "macro" then
        local _, icon = GetMacroInfo(entry.id)
        return icon
    end
    if entry.kind == "macrotext" then return entry.icon end
end

function ns.EntryName(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return ns.SpellName(entry.id) end
    if entry.kind == "item" then return ns.ItemName(entry.id) end
    return entry.name or entry.id
end

-- Le sort, l'objet ou la macro d'un bouton, en attributs sécurisés. Hors combat seulement.
function ns.ApplyButton(button)
    if InCombatLockdown() then return false end
    button.suppressed = nil
    local entry = button:GetEntry()
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macro", nil)
    button:SetAttribute("macrotext", nil)
    if ns.editing or not entry then
        button:SetAttribute("type", nil)
    elseif entry.kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", ns.SpellName(entry.id) or entry.id)
    elseif entry.kind == "item" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. entry.id)
    elseif entry.kind == "macro" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", entry.id)
    elseif entry.kind == "macrotext" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.id)
    end
    return true
end

-- Le temps qui reste avant de pouvoir relancer, écrit en grand sur le sort, et son icône en
-- gris jusque-là : le balayage seul ne se lisait pas sur un petit bouton rond, et les chiffres
-- du jeu dépendent d'une option souvent désactivée. Le recharge global (moins de 2 s, après
-- chaque sort) garde son balayage, sans chiffre ni gris.
local GLOBAL_COOLDOWN = 2
local ticking = {}

function ns.CooldownText(remaining)
    if remaining >= 60 then return math.ceil(remaining / 60) .. "m" end
    if remaining >= 3 then return tostring(math.ceil(remaining)) end
    return string.format("%.1f", remaining)
end

local function StopTimer(button)
    ticking[button] = nil
    if button.timer then button.timer:SetText("") end
    button.icon:SetDesaturated(false)
end

local ticker = CreateFrame("Frame")
local sinceTick = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < 0.1 then return end
    sinceTick = 0
    local now = GetTime()
    for button, ends in pairs(ticking) do
        if ends - now <= 0 then StopTimer(button) else button.timer:SetText(ns.CooldownText(ends - now)) end
    end
end)

function ns.UpdateCooldown(button)
    local entry = button:GetEntry()
    local start, duration, enable
    if entry and entry.kind == "spell" then
        start, duration, enable = ns.SpellCooldown(entry.id)
    elseif entry and entry.kind == "item" then
        start, duration, enable = ns.ItemCooldown(entry.id)
    end
    if start and duration and duration > 0 and enable ~= 0 and enable ~= false then
        if CooldownFrame_Set then
            CooldownFrame_Set(button.cooldown, start, duration, 1)
        else
            button.cooldown:SetCooldown(start, duration)
            button.cooldown:Show()
        end
        if duration > GLOBAL_COOLDOWN and button.timer then
            ticking[button] = start + duration
            button.timer:SetText(ns.CooldownText(math.max(0, start + duration - GetTime())))
            button.icon:SetDesaturated(true)
        else
            StopTimer(button)
        end
    else
        if button.cooldown.Clear then button.cooldown:Clear() end
        button.cooldown:Hide()
        StopTimer(button)
    end
end

function ns.UpdateState(button)
    local entry = button:GetEntry()
    if not entry then return end
    local usable, noPower, inRange = true, false, nil
    if entry.kind == "spell" then
        usable, noPower = ns.SpellUsable(entry.id)
        inRange = ns.SpellInRange(entry.id)
    elseif entry.kind == "item" then
        usable = (ns.ItemCount(entry.id) or 0) > 0
    end
    if inRange == false then
        button.icon:SetVertexColor(0.95, 0.3, 0.3)
    elseif noPower then
        button.icon:SetVertexColor(0.4, 0.5, 1)
    elseif usable == false then
        button.icon:SetVertexColor(0.45, 0.45, 0.45)
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
end

function ns.RefreshButton(button)
    local entry = button:GetEntry()
    button.count:SetText("")
    if entry then
        button.icon:SetTexture(ns.EntryIcon(entry) or ns.QUESTION)
        button.icon:Show()
        button.plus:Hide()
        if entry.kind == "item" then
            local count = ns.ItemCount(entry.id) or 0
            if count ~= 1 then button.count:SetText(count) end
        end
    else
        button.icon:Hide()
        button.plus:Show()
    end
    button.icon:SetVertexColor(1, 1, 1)
    button.editGlow:SetShown(ns.editing)
    ns.UpdateCooldown(button)
    ns.UpdateState(button)
end

-- Ranger une entrée dans un bouton : enregistre, redessine, et réapplique hors combat.
function ns.AssignEntry(button, entry)
    button:SetEntry(entry)
    ns.MarkChanged()
    ns.RefreshButton(button)
    ns.ApplyButton(button)
    if button.OnAssigned then button:OnAssigned() end
end

function ns.AssignFromCursor(button)
    if InCombatLockdown() then
        ns.Print("on remplit les cases hors combat.")
        return
    end
    local entry = ns.CursorEntry()
    if not entry then return end
    local previous = button:GetEntry()
    ns.AssignEntry(button, entry)
    ClearCursor()
    -- Comme une barre d'action : ce qui était dans la case passe au curseur.
    if previous and previous.kind ~= "macrotext" then ns.PickupEntry(previous) end
end

-- getEntry et setEntry disent où l'entrée est rangée (une roue, un bouton libre).
function ns.CreateActionButton(name, parent, size, getEntry, setEntry)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:SetSize(size, size)
    -- Les deux, parce que le gabarit d'action ne réagit qu'à l'un des deux selon le réglage
    -- « lancer à l'appui » du jeu ; il choisit lui-même lequel.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.GetEntry = function() return getEntry() end
    button.SetEntry = function(_, entry) setEntry(entry) end

    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 4)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local round = ns.Circle(button, button.icon)

    button.plus = ns.Label(button, "GameFontNormalHuge", "+")
    button.plus:SetPoint("CENTER")
    button.plus:SetTextColor(0.55, 0.55, 0.55)

    button.count = ns.Label(button, "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -8, 8)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    if round and button.cooldown.SetSwipeTexture then button.cooldown:SetSwipeTexture(ns.CIRCLE) end
    if button.cooldown.SetUseCircularEdge then button.cooldown:SetUseCircularEdge(true) end
    if button.cooldown.SetSwipeColor then button.cooldown:SetSwipeColor(0, 0, 0, 0.75) end
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
    -- Au-dessus du balayage : le temps qui reste.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
    button.timer = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    button.timer:SetPoint("CENTER")
    button.timer:SetTextColor(1, 1, 1)
    button.timer:SetShadowOffset(1, -1)

    button.editGlow = ns.Disc(button, "OVERLAY", 1, 0.8, 0.2, 0.28, 0)
    button.editGlow:Hide()
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    highlight:SetBlendMode("ADD")

    -- Un curseur plein, une case vide ou le mode Personnaliser : le toucher sert à ranger,
    -- pas à lancer.
    button:SetScript("PreClick", function(self)
        if InCombatLockdown() or self.swiped then return end
        if ns.editing or GetCursorInfo() or not self:GetEntry() then
            self:SetAttribute("type", nil)
            self.suppressed = true
        end
    end)
    button:SetScript("PostClick", function(self, _, down)
        -- Un glissé sur la roue l'a fait tourner : ni lancer ni sélecteur (Turn.lua).
        if self.swiped and not down then self.swiped = nil; return end
        if InCombatLockdown() or down or not self.suppressed then return end
        if GetCursorInfo() then
            ns.AssignFromCursor(self)
        elseif ns.Picker then
            ns.Picker:Open(self)
        end
        ns.ApplyButton(self)
    end)
    button:SetScript("OnReceiveDrag", function(self) ns.AssignFromCursor(self) end)
    return button
end
