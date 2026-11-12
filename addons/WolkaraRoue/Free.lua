-- Interface mobile : les sorts autour des sticks. De chaque côté, des roues de sorts (quatre par
-- défaut, réglage « Roues »), dont on voit une à la fois : Turn.lua les fait tourner, et passer
-- de l'une à l'autre par leurs onglets ou d'un glissé en diagonale. Chaque case se remplit par
-- le sélecteur, ou en y lâchant un sort pris dans le grimoire. Une case vide ne paraît qu'en
-- personnalisant, quand un sort pris au curseur attend d'y être posé, ou quand toute sa roue est
-- vide : une roue vide montre ses cases, pour qu'on la voie, qu'un toucher la remplisse et
-- qu'un glissé en reparte (demandé sur l'iPhone, 2026-11-09).
--
-- L'appui long sur un sort, comme sur l'écran d'accueil de l'iPhone : il passe en mode
-- Personnaliser, sans lancer le sort, et glisser ensuite déplace ce sort ; lâché sur une autre
-- case (de n'importe quelle roue visible, des deux côtés), les deux échangent leur place
-- (demandé sur l'iPhone, 2026-11-09). L'app donne l'appui long au jeu en clic droit, puis le
-- glissé qui le suit en glissé du bouton droit : c'est ce glissé-là qui déplace ; celui du
-- bouton gauche (un doigt qui glisse tout de suite) fait toujours tourner la roue, ou changer de
-- roue. Le déplacement n'emprunte pas le curseur du jeu : rien ne peut y rester accroché. En
-- combat, l'appui long lance le sort comme un toucher.

local _, ns = ...

local SIZE = 64
-- Le centre des sticks de l'app, mesuré sur l'écran du Duo : à 12 % du bord, 22 % du bas.
local STICK_X, STICK_Y = 0.12, 0.222
ns.STICK_X, ns.STICK_Y = STICK_X, STICK_Y

local Free = ns.Register("Boutons libres", {})
ns.Free = Free
local groups = {}
local moving, ghost

local function LongPress()
    if not ns.editing then ns.SetEditing(true) end
end

local function BuildGroup(side, key, prefix)
    local group = { side = side, key = key, buttons = {}, pages = {} }
    local function settings() return ns.db[key] end
    local function store(page, index)
        local list = ns.PageData(settings(), page).buttons
        if type(list[index]) ~= "table" then list[index] = {} end
        return list[index]
    end
    for page = 1, ns.PAGES do
        local list = {}
        for index = 1, ns.MAX_FREE do
            -- La roue 1 garde les noms d'avant la 0.8.
            local name = page == 1 and (prefix .. index) or (prefix .. page .. "_" .. index)
            local button = ns.CreateActionButton(name, UIParent, SIZE,
                function() return store(page, index).entry end,
                function(entry) store(page, index).entry = entry end)
            -- Sous les fenêtres du jeu (fiche, sacs, sorts), qui s'ouvrent par-dessus.
            button:SetFrameStrata("LOW")
            button.wmSide, button.wmPage, button.wmIndex = side, page, index
            button.OnLongPress = LongPress
            button:HookScript("OnDragStart", function(self, mouse)
                if mouse == "RightButton" then Free.StartMove(self) end
            end)
            button:HookScript("OnDragStop", function(self) if moving == self then Free.Drop() end end)
            button:Hide()
            local since = 0
            button:HookScript("OnUpdate", function(self, elapsed)
                since = since + elapsed
                if since < 0.25 then return end
                since = 0
                ns.UpdateState(self)
            end)
            list[index] = button
            group.buttons[#group.buttons + 1] = button
        end
        group.pages[page] = list
    end

    -- Les roues sans aucun sort dans leurs `count` cases.
    local function EmptyWheels(count)
        local empty = {}
        for page, list in ipairs(group.pages) do
            empty[page] = true
            for index = 1, math.min(count, #list) do
                if list[index]:GetEntry() ~= nil then empty[page] = false; break end
            end
        end
        return empty
    end
    -- Une case vide ne s'affiche qu'en mode Personnaliser, quand un sort pris dans le grimoire
    -- attend d'être posé, ou quand toute sa roue est vide : en jeu, une roue remplie ne montre
    -- que ses sorts (idée de scarrdi94, #26).
    local function Visible(button, empty)
        return button:GetEntry() ~= nil or ns.editing or ns.CursorHolds() or empty[button.wmPage] == true
    end

    function group:Layout()
        local count, scale = settings().count, settings().scale / 100
        local empty = EmptyWheels(count)
        for _, button in ipairs(self.buttons) do
            if button.wmIndex <= count then
                button:SetScale(scale)
                -- La roue place elle-même ses sorts, et certains hors de l'écran.
                button:SetClampedToScreen(false)
                button:SetShown(Visible(button, empty))
            else
                button:Hide()
            end
            ns.ApplyButton(button)
        end
    end

    -- Seulement ce qui se voit : un curseur qui prend ou pose un sort.
    function group:Show()
        local count = settings().count
        local empty = EmptyWheels(count)
        for _, button in ipairs(self.buttons) do
            if button.wmIndex <= count then button:SetShown(Visible(button, empty)) end
        end
    end

    -- Une case vide est pâle ; celles d'une roue vide un peu moins, pour qu'on voie la roue.
    function group:Refresh()
        local count = settings().count
        local empty = EmptyWheels(count)
        for _, button in ipairs(self.buttons) do
            if button.wmIndex <= count then
                ns.RefreshButton(button)
                local alpha = 1
                if not button:GetEntry() and not ns.editing then alpha = empty[button.wmPage] and 0.6 or 0.35 end
                button:SetAlpha(alpha)
            end
        end
    end

    function group:Each(fn)
        local count = settings().count
        for _, button in ipairs(self.buttons) do
            if button.wmIndex <= count then fn(button) end
        end
    end
    return group
end

function Free:Init()
    groups[1] = BuildGroup("right", "free", "WolkaraMobileFree")
    groups[2] = BuildGroup("left", "freeLeft", "WolkaraMobileFreeLeft")
    if ns.Turn then
        ns.Turn:Attach(groups[1].pages, "right")
        ns.Turn:Attach(groups[2].pages, "left")
    end
end

function Free:Layout()
    for _, group in ipairs(groups) do ns.Guard("boutons " .. group.side, group.Layout, group) end
    self:Refresh()
end

function Free:Refresh()
    for _, group in ipairs(groups) do group:Refresh() end
end

-- ---------------------------------------------------------------------------------------
-- Déplacer un sort (mode Personnaliser, glissé du bouton droit après un appui long)

local function Ghost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", "WolkaraMobileMoveGhost", UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(SIZE, SIZE)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetAllPoints()
    ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(ghost, ghost.icon)
    ghost:Hide()
    ghost:SetScript("OnUpdate", function(self)
        if not moving then self:Hide(); return end
        -- Le doigt relevé sans que le jeu le dise au sort : le déplacement se finit quand même.
        if IsMouseButtonDown then
            if IsMouseButtonDown("RightButton") then
                self.held = true
            elseif self.held then
                Free.Drop()
                return
            end
        end
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    return ghost
end

-- Le sort part avec le doigt : son icône le suit, sa case pâlit.
function Free.StartMove(button)
    if not ns.editing or InCombatLockdown() or moving or not button:GetEntry() then return false end
    moving = button
    local g = Ghost()
    g.icon:SetTexture(ns.EntryIcon(button:GetEntry()) or ns.QUESTION)
    g:SetScale(button:GetScale())
    g.held = false
    g:Show()
    button.icon:SetAlpha(0.3)
    return true
end

-- La case sous le doigt, parmi celles qu'on voit.
local function Under(except)
    for _, group in ipairs(groups) do
        for _, button in ipairs(group.buttons) do
            if button ~= except and button:IsVisible() and button:IsMouseOver() then return button end
        end
    end
    return nil
end

-- Le doigt relevé : sur une autre case, les deux sorts échangent leur place ; ailleurs, rien
-- ne change.
function Free.Drop()
    local source = moving
    if not source then return false end
    moving = nil
    if ghost then ghost:Hide() end
    source.icon:SetAlpha(1)
    if InCombatLockdown() then return false end
    local target = Under(source)
    if not target then return false end
    local carried, there = source:GetEntry(), target:GetEntry()
    source:SetEntry(there)
    target:SetEntry(carried)
    ns.MarkChanged("sort déplacé : " .. (ns.EntryName(carried) or "?"))
    Free:Layout()
    return true
end

local function CancelMove()
    if not moving then return end
    moving.icon:SetAlpha(1)
    moving = nil
    if ghost then ghost:Hide() end
end

-- Entrer en mode Personnaliser montre les cases vides, en sortir les range (hors combat : le
-- mode Personnaliser ne s'ouvre pas en combat).
function Free:SetEditing(on)
    if not on then CancelMove() end
    if not InCombatLockdown() then
        for _, group in ipairs(groups) do ns.Guard("boutons " .. group.side, group.Layout, group) end
    end
    self:Refresh()
end

function Free:CombatStarts()
    CancelMove()
    for _, group in ipairs(groups) do
        group:Each(function(button) if button.suppressed then ns.ApplyButton(button) end end)
    end
end

local function UpdateCooldowns()
    if not ns.db then return end
    for _, group in ipairs(groups) do
        group:Each(function(button) if button:GetEntry() then ns.UpdateCooldown(button) end end)
    end
end
function ns.CursorHolds() return GetCursorInfo ~= nil and GetCursorInfo() ~= nil end
-- Un sort pris au curseur fait paraître les cases vides, le reposer les range. Le curseur change
-- souvent (survoler un personnage suffit) : seulement quand il prend ou pose quelque chose.
local holding = false
local function CursorChanged()
    if not ns.db or InCombatLockdown() then return end
    local holds = ns.CursorHolds()
    if holds == holding then return end
    holding = holds
    for _, group in ipairs(groups) do ns.Guard("boutons " .. group.side, group.Show, group) end
    Free:Refresh()
end
ns.On("CURSOR_CHANGED", CursorChanged)
ns.On("CURSOR_UPDATE", CursorChanged)
ns.On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE", function() if ns.db then Free:Refresh() end end)
ns.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    Free:Refresh()
    if not InCombatLockdown() then
        for _, group in ipairs(groups) do group:Each(ns.ApplyButton) end
    end
end)
