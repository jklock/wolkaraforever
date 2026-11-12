-- Interface mobile : le bouton d'action commun aux roues et aux boutons libres.
--
-- Un bouton sécurisé du jeu, rond, avec la vraie icône, le temps de recharge et la couleur
-- de portée. Hors combat, toucher une case vide (ou n'importe quelle case en mode
-- Personnaliser) ouvre le sélecteur ; déposer un sort dessus le range aussi.

local _, ns = ...

-- Les actions toutes faites du sélecteur : des lignes de macro que le jeu exécute lui-même.
ns.BUILTIN = {
    { kind = "macrotext", id = "/targetenemy", name = "Target enemy", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { kind = "macrotext", id = "/startattack", name = "Auto attack", icon = "Interface\\Icons\\INV_Sword_04" },
    { kind = "macrotext", id = "/assist", name = "Assist", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { kind = "macrotext", id = "/targetfriend", name = "Target friend", icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { kind = "macrotext", id = "/cleartarget", name = "Clear target", icon = "Interface\\Icons\\Spell_Shadow_Teleport" },
    { kind = "macrotext", id = "/follow", name = "Follow", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
    { kind = "macrotext", id = "/sit", name = "Sit", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
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
    return entry.name and ns.T(entry.name) or entry.id
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
    if ns.editing or ns.slotEditing or not entry then
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

local LOCKOUT = { [17] = 6788, [592] = 6788, [600] = 6788, [3747] = 6788, [6065] = 6788, [6066] = 6788,
    [10898] = 6788, [10899] = 6788, [10900] = 6788, [10901] = 6788 }

local function Lockout(button, entry)
    local debuff = entry and entry.kind == "spell" and LOCKOUT[entry.id]
    if not debuff or not (AuraUtil and AuraUtil.FindAuraByName) then return false end
    local unit = (UnitExists("target") and UnitIsFriend("player", "target")) and "target" or "player"
    local name = ns.SpellName(debuff)
    local ok, auraName, _, _, _, duration, expiration = pcall(AuraUtil.FindAuraByName, name, unit, "HARMFUL")
    if not ok or not auraName then return false end
    button.icon:SetDesaturated(true)
    local timed = pcall(function()
        button.cooldown:SetCooldown(expiration - duration, duration)
        ticking[button] = expiration
        if button.timer then button.timer:SetText(ns.CooldownText(math.max(0, expiration - GetTime()))) end
    end)
    if not timed then button.cooldown:Hide() end
    return true
end

local function SecretCooldown(button, entry, start, duration, onGCD)
    local cooldown = button.cooldown
    local drawn = false
    if entry.kind == "spell" and C_Spell and C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        drawn = pcall(function() cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(entry.id)) end)
    end
    if not drawn then drawn = pcall(cooldown.SetCooldown, cooldown, start, duration) end
    if not drawn then cooldown:Hide(); return end
    cooldown:Show()
    ticking[button] = nil
    if button.timer then button.timer:SetText("") end
    local known, global = pcall(function() return onGCD == true end)
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(known and global) end
    button.icon:SetDesaturated(not (known and global))
    if not button.cooldownWatched then
        button.cooldownWatched = true
        cooldown:HookScript("OnCooldownDone", function() button.icon:SetDesaturated(false) end)
    end
end

function ns.UpdateCooldown(button)
    local entry = button:GetEntry()
    local start, duration, enable, onGCD
    if entry and entry.kind == "spell" then
        start, duration, enable, onGCD = ns.SpellCooldown(entry.id)
    elseif entry and entry.kind == "item" then
        start, duration, enable = ns.ItemCooldown(entry.id)
    end
    local plain, active = pcall(function() return start and duration and duration > 0 and enable ~= 0 and enable ~= false end)
    if not plain then return SecretCooldown(button, entry, start, duration, onGCD) end
    local real = active and duration > GLOBAL_COOLDOWN
    if not real and Lockout(button, entry) then return end
    if active then
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
        ns.Print(ns.T("slots can only be filled out of combat."))
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

    -- Une case vide ou le mode Personnaliser : le toucher sert à ranger, pas à lancer.
    -- Un objet tenu au curseur ne range que là où ranger a un sens : pendant Personnaliser,
    -- ou dans une case vide. Sinon le toucher lance le sort et l'objet reste au curseur -
    -- mesuré sur l'iPhone, 2026-11-09 : ranger par mégarde un objet tenu par-dessus un sort
    -- lancé.
    button:SetScript("PreClick", function(self)
        if InCombatLockdown() or self.swiped then return end
        local placing = GetCursorInfo() and (ns.editing or ns.slotEditing or not self:GetEntry())
        if ns.editing or ns.slotEditing or placing or not self:GetEntry() then
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

if ns.On then
    ns.On("PLAYER_LOGIN", function()
        if GetCVar and SetCVar and GetCVar("countdownForCooldowns") == "0" then pcall(SetCVar, "countdownForCooldowns", "1") end
    end)
end
