-- Interface mobile (WolkaraForever) : le cœur.
--
-- Chaque module (roues, boutons libres, raccourcis, barres de vie, chat, réglages) s'inscrit
-- ici et reçoit les mêmes étapes : Init une fois, Layout hors combat dès que la disposition
-- change, Refresh pour l'affichage, SetEditing pour le mode Personnaliser. Une erreur dans un
-- module est affichée dans le chat et n'empêche pas les autres de marcher.
--
-- Rien ici ne lit ni ne modifie la mémoire du jeu, et rien n'automatise une action : chaque
-- sort part d'un toucher, exactement comme un clic sur une barre d'action.

local ADDON_NAME, ns = ...
ns.MAX_WHEELS = 4  -- les roues dorées d'avant la 0.6, gardées pour relire une vieille sauvegarde
ns.MAX_SLOTS = 12
ns.MAX_FREE = 12
-- Chaque côté a ses roues de sorts : quatre par défaut, de une à six (réglage « Roues »). On en
-- voit une à la fois ; un glissé en diagonale ou un onglet au-dessus d'elle passe à une autre,
-- même vide (demandé sur l'iPhone, 2026-11-09).
ns.PAGES = 6   -- au plus, de chaque côté
ns.WHEELS = 4  -- par défaut
ns.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local modules = {}
local loggedIn = false
local pendingLayout = false
ns.editing = false

function ns.Print(message)
    local line = "|cff66ccffMobile|r : " .. message
    -- Le chat mobile range celui du jeu : nos messages passent alors par lui.
    if ns.ChatAdd and ns.ChatAdd(line) then return end
    DEFAULT_CHAT_FRAME:AddMessage(line)
end

local reported = 0
local function Trace(message)
    return tostring(message) .. (debugstack and ("\n" .. debugstack(2, 2, 0)) or "")
end
-- Les dernières erreurs restent dans la sauvegarde (ns.db.errors, 8 au plus, avec leur nombre
-- et leurs heures) : le jeu ne les écrit dans aucun journal, et le chat ne se relit pas
-- depuis le Mac. Une même erreur ne prend qu'une ligne.
local KEEP_ERRORS = 8
function ns.RememberError(text)
    local db = ns.db
    if type(db) ~= "table" then return end
    if type(db.errors) ~= "table" then db.errors = {} end
    text = tostring(text):sub(1, 400)
    local now = time and time() or nil
    for _, seen in ipairs(db.errors) do
        if seen.text == text then
            seen.count, seen.last = (tonumber(seen.count) or 1) + 1, now
            return
        end
    end
    table.insert(db.errors, 1, { text = text, count = 1, first = now, last = now })
    while #db.errors > KEEP_ERRORS do table.remove(db.errors) end
end

function ns.Guard(label, fn, ...)
    local ok, problem = xpcall(fn, Trace, ...)
    if not ok then
        ns.lastError = label .. " : " .. problem
        ns.RememberError(ns.lastError)
        if reported < 5 then
            reported = reported + 1
            if loggedIn then ns.Print("|cffff5555erreur|r (" .. label .. ") : " .. problem) end
        end
    end
    return ok
end

function ns.Register(name, module)
    module.name = name
    modules[#modules + 1] = module
    return module
end

function ns.Each(method, ...)
    for _, module in ipairs(modules) do
        local fn = module[method]
        if fn then ns.Guard(module.name .. "." .. method, fn, module, ...) end
    end
end

-- La disposition ne change que hors combat ; en combat, elle attend la fin du combat.
function ns.Layout()
    if InCombatLockdown() then pendingLayout = true; return end
    ns.Each("Layout")
end

function ns.Refresh() ns.Each("Refresh") end

function ns.SetEditing(on)
    if InCombatLockdown() then
        if on then ns.Print("on personnalise hors combat.") end
        return
    end
    if ns.editing == (on and true or false) then return end
    ns.editing = on and true or false
    ns.Each("SetEditing", ns.editing)
    ns.Layout()
    if ns.editing then
        ns.Print("mode Personnaliser : touche une case pour choisir son sort, appui long puis glisse pour déplacer un sort, change de roue par ses onglets ou d'un glissé en diagonale, puis Terminé.")
    end
end

-- Les données d'une des roues d'un côté (ns.db.free ou ns.db.freeLeft) : ses sorts et son cran.
function ns.PageData(side, page)
    if type(side.pages) ~= "table" then side.pages = {} end
    local data = side.pages[page]
    if type(data) ~= "table" then
        data = {}
        side.pages[page] = data
    end
    if type(data.buttons) ~= "table" then data.buttons = {} end
    return data
end

-- Vrai si la roue a au moins un sort dans ses `count` premières cases.
function ns.PageHasEntries(side, page, count)
    local data = type(side.pages) == "table" and side.pages[page]
    if type(data) ~= "table" or type(data.buttons) ~= "table" then return false end
    for index = 1, count or ns.MAX_FREE do
        local button = data.buttons[index]
        if type(button) == "table" and button.entry then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------------------
-- Compatibilité : le client Forever expose tantôt l'ancienne API, tantôt les espaces C_*.

function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function ns.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

function ns.SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if type(info) == "table" then return info.startTime, info.duration, info.isEnabled end
        return info
    end
    if GetSpellCooldown then return GetSpellCooldown(id) end
end

function ns.SpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
    if IsUsableSpell then
        local name = ns.SpellName(id)
        if name then return IsUsableSpell(name) end
    end
    return true, false
end

function ns.SpellInRange(id)
    if not UnitExists("target") then return nil end
    if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(id, "target") end
    if IsSpellInRange then
        local name = ns.SpellName(id)
        local result = name and IsSpellInRange(name, "target")
        if result == 1 then return true elseif result == 0 then return false end
    end
    return nil
end

function ns.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

function ns.ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
end

function ns.ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
    if GetItemCount then return GetItemCount(id) end
    return 0
end

function ns.ItemSpell(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) end
    if GetItemSpell then return GetItemSpell(id) end
end

function ns.ItemCooldown(id)
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
end

function ns.PickupEntry(entry)
    if entry.kind == "spell" then
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(entry.id) elseif PickupSpell then PickupSpell(entry.id) end
    elseif entry.kind == "item" then
        if C_Item and C_Item.PickupItem then C_Item.PickupItem(entry.id) elseif PickupItem then PickupItem(entry.id) end
    elseif entry.kind == "macro" then
        PickupMacro(entry.id)
    end
end

-- Ce que le curseur tient, sous la forme d'une case : un sort, un objet ou une macro.
function ns.CursorEntry()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        if b == "pet" then
            ns.Print("les techniques de familier ne vont pas dans une case.")
            return nil
        end
        local spellID = c
        if not spellID and a and GetSpellBookItemInfo then
            local _, id = GetSpellBookItemInfo(a, b)
            spellID = id
        end
        if spellID then return { kind = "spell", id = spellID } end
    elseif kind == "item" and a then
        return { kind = "item", id = a }
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        if name then return { kind = "macro", id = name } end
    elseif kind then
        ns.Print("seuls les sorts, les objets et les macros vont dans une case.")
    end
    return nil
end

-- Toutes les positions enregistrées, pour revenir à la disposition par défaut.
function ns.ClearPositions(db)
    for i = 1, ns.MAX_WHEELS do if type(db.wheels[i]) == "table" then db.wheels[i].toggle = nil end end
    if type(db.shortcuts) == "table" then db.shortcuts.pos = nil end
    if type(db.hud) == "table" then db.hud.player = nil; db.hud.target = nil end
    if type(db.chat) == "table" then db.chat.pos = nil end
    if type(db.quests) == "table" then db.quests.pos = nil end
end

-- 0.6 : les sorts de la roue dorée 1 passent dans la roue qui tourne à gauche, aux places libres
-- et sans doublon, et la roue dorée s'éteint. Elle garde ses sorts : la rallumer la retrouve.
function ns.MigrateGoldenWheel(db)
    local golden, left = db.wheels[1], db.freeLeft
    if type(left.buttons) ~= "table" then left.buttons = {} end
    local function Stored(index) return type(left.buttons[index]) == "table" and left.buttons[index].entry end
    local last = 0
    local function Has(entry)
        for index = 1, ns.MAX_FREE do
            local stored = Stored(index)
            if stored and stored.kind == entry.kind and stored.id == entry.id then return true end
        end
        return false
    end
    for index = 1, ns.MAX_FREE do if Stored(index) then last = index end end
    local slot = 1
    for i = 1, golden.slots do
        local entry = golden.entries[i]
        if type(entry) == "table" and entry.kind and not Has(entry) then
            while slot <= ns.MAX_FREE and Stored(slot) do slot = slot + 1 end
            if slot > ns.MAX_FREE then break end
            if type(left.buttons[slot]) ~= "table" then left.buttons[slot] = {} end
            left.buttons[slot].entry = { kind = entry.kind, id = entry.id }
            last = math.max(last, slot)
        end
    end
    golden.enabled = false
    left.turn = true
    left.count = math.max(tonumber(left.count) or 0, 4, last)
end

-- Une position par défaut en proportion de l'écran : x et y de 0 à 1 depuis le bas à gauche.
-- Calculée au moment de placer, donc juste quelle que soit la taille de l'interface.
function ns.Spot(fx, fy, dx, dy)
    return function()
        return { "CENTER", "BOTTOMLEFT", UIParent:GetWidth() * fx + (dx or 0), UIParent:GetHeight() * fy + (dy or 0) }
    end
end

function ns.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- ---------------------------------------------------------------------------------------
-- Habillage commun

function ns.Circle(frame, texture)
    if frame.CreateMaskTexture and texture.AddMaskTexture then
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(ns.CIRCLE, "CLAMPTOEDGE", "CLAMPTOEDGE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
        return true
    end
    return false
end

function ns.Disc(frame, layer, r, g, b, a, inset)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetTexture(ns.WHITE)
    texture:SetVertexColor(r, g, b, a)
    texture:SetPoint("TOPLEFT", -inset, inset)
    texture:SetPoint("BOTTOMRIGHT", inset, -inset)
    ns.Circle(frame, texture)
    return texture
end

function ns.Box(frame, layer, r, g, b, a)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetTexture(ns.WHITE)
    texture:SetVertexColor(r, g, b, a)
    texture:SetAllPoints()
    return texture
end

function ns.Label(frame, template, text)
    local label = frame:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    if text then label:SetText(text) end
    return label
end

-- Un cadre que le mode Personnaliser laisse déplacer au doigt, et dont la place est gardée.
-- `save` reçoit la position, `place` la remet ; `default` sert tant que rien n'est enregistré.
function ns.Movable(frame, store, key, default)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:HookScript("OnDragStart", function(self)
        if ns.editing and not InCombatLockdown() then self:StartMoving(); self.moving = true end
    end)
    frame:HookScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = nil
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        local target = store()
        target[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
        if ns.MarkChanged then ns.MarkChanged("déplacé : " .. (self:GetName() or "?")) end
        if frame.OnMoved then frame:OnMoved() end
    end)
    function frame:PlaceSaved()
        if InCombatLockdown() then return end
        local saved = store()[key]
        self:ClearAllPoints()
        if type(saved) == "table" and saved.point then
            self:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
        else
            local d = type(default) == "function" and default() or default
            self:SetPoint(d[1], UIParent, d[2] or d[1], d[3] or 0, d[4] or 0)
        end
    end
end

-- Une poignée : glisser ce bouton en mode Personnaliser déplace tout le bloc qui le porte.
function ns.DragHandle(handle, frame)
    handle:RegisterForDrag("LeftButton")
    handle:HookScript("OnDragStart", function()
        local start = frame:GetScript("OnDragStart")
        if start then start(frame) end
    end)
    handle:HookScript("OnDragStop", function()
        local stop = frame:GetScript("OnDragStop")
        if stop then stop(frame) end
    end)
end

-- Le contour jaune du mode Personnaliser.
function ns.EditFrame(frame)
    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(ns.WHITE)
    glow:SetVertexColor(1, 0.82, 0.2, 0.22)
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:Hide()
    return glow
end

-- ---------------------------------------------------------------------------------------
-- Réglages

-- Les roues dorées (un bouton qui ouvre un cercle de sorts) restent dans le panneau, éteintes :
-- depuis la 0.6, la roue qui tourne à gauche fait leur travail.
local function Wheel()
    return {
        enabled = false,
        slots = 8,
        scale = 100,
        radius = 110,
        open = "bouton", -- autour du bouton, ou au centre de l'écran
        entries = {},
    }
end

local function Defaults()
    local wheels = {}
    for i = 1, ns.MAX_WHEELS do wheels[i] = Wheel(i) end
    return {
        version = 2,
        wheels = wheels,
        ui = { scale = 170 },
        -- Chaque côté : `wheels` roues de `count` cases, leurs sorts et leur cran dans `pages`,
        -- et `page`, celle qu'on voit.
        free = { count = 4, wheels = ns.WHEELS, scale = 100, spread = 100, page = 1, pages = {} },
        freeLeft = { count = 4, wheels = ns.WHEELS, scale = 100, spread = 100, page = 1, pages = {} },
        shortcuts = { enabled = true, scale = 100 },
        -- deselect : toucher le vide (le sol, le ciel) retire la cible.
        hud = { enabled = true, scale = 100, deselect = true },
        chat = { custom = true, fontSize = 16, tab = "talk", hidden = false },
        minimap = { shown = true, scale = 60 },
        blizzard = { hideBars = true, hideUnitFrames = true },
        quests = { enabled = true, collapsed = false, shown = 3 },
        welcomed = false,
    }
end

local function Fill(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Fill(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function LoadSettings()
    local saved = type(WolkaraRoueDB) == "table" and WolkaraRoueDB or {}
    -- La première version n'avait qu'une roue, réglée à plat : elle devient la roue 1.
    if not saved.version then
        local first = Wheel(1)
        if type(saved.entries) == "table" then first.entries = saved.entries end
        if tonumber(saved.slots) then first.slots = saved.slots end
        if tonumber(saved.scale) then first.scale = saved.scale end
        if tonumber(saved.radius) then first.radius = saved.radius end
        if saved.position == "centre" then first.open = "centre" end
        local welcomed = saved.welcomed
        saved = { wheels = { first }, welcomed = welcomed }
    end
    Fill(saved, Defaults())
    for i = 1, ns.MAX_WHEELS do
        local wheel = saved.wheels[i]
        wheel.slots = ns.Clamp(tonumber(wheel.slots) or 8, 4, ns.MAX_SLOTS)
        wheel.scale = ns.Clamp(tonumber(wheel.scale) or 100, 50, 200)
        wheel.radius = ns.Clamp(tonumber(wheel.radius) or 140, 80, 320)
    end
    saved.free.count = ns.Clamp(tonumber(saved.free.count) or 4, 0, ns.MAX_FREE)
    saved.freeLeft.count = ns.Clamp(tonumber(saved.freeLeft.count) or 4, 0, ns.MAX_FREE)
    saved.minimap.scale = ns.Clamp(tonumber(saved.minimap.scale) or 60, 30, 150)
    saved.free.spread = ns.Clamp(tonumber(saved.free.spread) or 100, 60, 180)
    saved.freeLeft.spread = ns.Clamp(tonumber(saved.freeLeft.spread) or 100, 60, 180)
    for _, key in ipairs({ "free", "freeLeft" }) do
        saved[key].wheels = ns.Clamp(math.floor(tonumber(saved[key].wheels) or ns.WHEELS), 1, ns.PAGES)
    end
    saved.ui.scale = ns.Clamp(tonumber(saved.ui.scale) or 170, 100, 220)
    -- La disposition 3 (interface agrandie, éléments placés en proportion de l'écran) remet
    -- une fois les positions par défaut : les anciennes étaient faites pour l'interface d'origine.
    if (tonumber(saved.layoutVersion) or 0) < 3 then
        ns.ClearPositions(saved)
        for i = 1, ns.MAX_WHEELS do
            if saved.wheels[i].radius == 140 then saved.wheels[i].radius = 110 end
        end
        if saved.chat.fontSize == 15 then saved.chat.fontSize = 16 end
        saved.layoutVersion = 3
    end
    -- La disposition 4 (0.6) : la roue dorée devient la roue qui tourne à gauche, en miroir de
    -- celle de droite. Ses sorts y passent, aux places libres, et le chat repart en bas.
    if (tonumber(saved.layoutVersion) or 0) < 4 then
        ns.MigrateGoldenWheel(saved)
        saved.chat.pos = nil
        saved.layoutVersion = 4
    end
    -- La disposition 5 (0.7) : les quatre raccourcis deviennent un petit bouton « ☰ » ; leur
    -- ancienne place ne lui va pas, il repart sous la mini-carte.
    if (tonumber(saved.layoutVersion) or 0) < 5 then
        saved.shortcuts.pos = nil
        saved.layoutVersion = 5
    end
    -- La disposition 6 (0.8) : quatre roues par côté. Les sorts de chaque côté et son cran
    -- deviennent sa roue 1 ; les roues dorées et le mode « Arc » s'en vont.
    if (tonumber(saved.layoutVersion) or 0) < 6 then
        for _, key in ipairs({ "free", "freeLeft" }) do
            local side = saved[key]
            local first = ns.PageData(side, 1)
            if type(side.buttons) == "table" then
                for index, button in pairs(side.buttons) do
                    if type(button) == "table" and button.entry and first.buttons[index] == nil then
                        first.buttons[index] = { entry = button.entry }
                    end
                end
            end
            if tonumber(side.turnOffset) then first.turnOffset = tonumber(side.turnOffset) end
            side.buttons, side.turnOffset, side.turn = nil, nil, nil
            side.page = 1
        end
        saved.layoutVersion = 6
    end
    -- La disposition 7 (0.9) : le bouton « ☰ » monte en haut de l'écran, à gauche de la
    -- mini-carte ; sa place d'avant, sous elle, ne lui va plus.
    if (tonumber(saved.layoutVersion) or 0) < 7 then
        saved.shortcuts.pos = nil
        saved.layoutVersion = 7
    end
    -- La disposition 8 (0.9.1) : la cible monte tout en haut, à droite de ta barre ; tes effets
    -- passent sous ta barre et la carte des quêtes sous eux. Leurs places d'avant ne vont plus.
    if (tonumber(saved.layoutVersion) or 0) < 8 then
        saved.hud.target = nil
        saved.quests.pos = nil
        saved.layoutVersion = 8
    end
    for _, key in ipairs({ "free", "freeLeft" }) do
        local side = saved[key]
        for page = 1, ns.PAGES do ns.PageData(side, page) end
        side.page = ns.Clamp(math.floor(tonumber(side.page) or 1), 1, side.wheels)
    end
    WolkaraRoueDB = saved
    ns.db = saved
end

-- ---------------------------------------------------------------------------------------
-- Événements

local events = CreateFrame("Frame")
local handlers = {}

-- Un module demande un événement ; un événement inconnu de ce client est ignoré.
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not pcall(events.RegisterEvent, events, event) then
            handlers[event] = nil
            return
        end
    end
    table.insert(handlers[event], fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do ns.Guard(event, fn, ...) end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    LoadSettings()
    ns.Each("Init")
end)

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    if not ns.db then LoadSettings(); ns.Each("Init") end
    ns.Layout()
    ns.Refresh()
    if ns.lastError then ns.Print("|cffff5555erreur au chargement|r : " .. ns.lastError) end
    if not ns.db.welcomed then
        ns.db.welcomed = true
        ns.Print("touche une case vide d'une roue pour y mettre un sort, glisse depuis un sort pour la faire tourner, et l'engrenage des raccourcis règle tout.")
    end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
    -- Le dernier moment où le jeu laisse changer les boutons avant le combat.
    if ns.editing then ns.SetEditing(false) end
    ns.Each("CombatStarts")
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingLayout then
        pendingLayout = false
        ns.Each("Layout")
    end
end)

-- ---------------------------------------------------------------------------------------
-- /mobile et /roue

SLASH_WOLKARAMOBILE1 = "/mobile"
SLASH_WOLKARAMOBILE2 = "/roue"
SlashCmdList.WOLKARAMOBILE = function(message)
    if not ns.db then
        ns.Print("pas encore prête" .. (ns.lastError and (" : " .. ns.lastError) or "."))
        return
    end
    local command = ((message or ""):match("^%s*(%S*)") or ""):lower()
    if command == "erreur" then
        ns.Print(ns.lastError or "aucune erreur.")
    elseif command == "personnaliser" or command == "modifier" then
        ns.SetEditing(not ns.editing)
    elseif command == "reset" then
        if InCombatLockdown() then ns.Print("pas en combat."); return end
        local old = ns.db
        WolkaraRoueDB = nil
        LoadSettings()
        for i = 1, ns.MAX_WHEELS do ns.db.wheels[i].entries = old.wheels[i] and old.wheels[i].entries or {} end
        -- Les sorts des roues restent aussi, chacun à sa place dans sa roue.
        for _, key in ipairs({ "free", "freeLeft" }) do
            for page = 1, ns.PAGES do
                local before = type(old[key].pages) == "table" and old[key].pages[page]
                if type(before) == "table" and type(before.buttons) == "table" then
                    for index, button in pairs(before.buttons) do
                        if type(button) == "table" and button.entry then
                            ns.PageData(ns.db[key], page).buttons[index] = { entry = button.entry }
                            ns.db[key].count = math.max(ns.db[key].count, math.min(index, ns.MAX_FREE))
                            ns.db[key].wheels = math.max(ns.db[key].wheels, page)
                        end
                    end
                end
            end
        end
        ns.db.welcomed = true
        ns.MarkChanged("réglages par défaut")
        ns.Layout(); ns.Refresh()
        ns.Print("réglages et positions par défaut remis (les sorts des roues restent).")
    elseif ns.Settings then
        ns.Settings:Toggle()
    end
end
