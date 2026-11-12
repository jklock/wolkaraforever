-- Interface mobile : le sélecteur. Toucher une case ouvre la grille de tes sorts, objets
-- utilisables, macros et actions toutes faites ; toucher une icône la range dans la case.
-- Des pages plutôt qu'un défilement, parce qu'un doigt ne fait pas défiler une liste du jeu.

local _, ns = ...

local COLUMNS, ROWS = 6, 3
local PER_PAGE = COLUMNS * ROWS
local CELL_W, CELL_H = 92, 100
local TABS = { { key = "spells", label = "Sorts" }, { key = "items", label = "Objets" },
               { key = "macros", label = "Macros" }, { key = "builtin", label = "Actions" } }

local Picker = ns.Register("Sélecteur", {})
ns.Picker = Picker

local BOOK = BOOKTYPE_SPELL or "spell"

local function CollectSpells()
    local list, seen = {}, {}
    local function add(spellID, name, icon)
        if not spellID or not name then return end
        if seen[name] then
            -- Les rangs d'un même sort se suivent : on garde le dernier, le plus haut.
            list[seen[name]].id = spellID
            list[seen[name]].icon = icon or list[seen[name]].icon
            return
        end
        list[#list + 1] = { kind = "spell", id = spellID, name = name, icon = icon }
        seen[name] = #list
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive and not item.isOffSpec
                        and (not spellType or item.itemType == spellType) then
                        add(item.spellID, item.name, item.iconID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
                local kind, spellID = GetSpellBookItemInfo(i, BOOK)
                local passive = IsPassiveSpell and IsPassiveSpell(i, BOOK)
                if kind == "SPELL" and spellID and not passive then
                    local name = GetSpellBookItemName and GetSpellBookItemName(i, BOOK) or ns.SpellName(spellID)
                    local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(i, BOOK) or ns.SpellIcon(spellID)
                    add(spellID, name, icon)
                end
            end
        end
    end
    return list
end

local function CollectItems()
    local list, seen = {}, {}
    local function add(id)
        if not id or seen[id] or not ns.ItemSpell(id) then return end
        seen[id] = true
        list[#list + 1] = { kind = "item", id = id, name = ns.ItemName(id) or ("Objet " .. id), icon = ns.ItemIcon(id) }
    end
    local slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    if slots and itemAt then
        for bag = 0, 4 do
            for slot = 1, (slots(bag) or 0) do add(itemAt(bag, slot)) end
        end
    end
    -- Les bijoux portés, qui ont souvent un effet à utiliser.
    for _, slot in ipairs({ 13, 14 }) do add(GetInventoryItemID("player", slot)) end
    return list
end

local function CollectMacros()
    local list = {}
    local global, perCharacter = GetNumMacros()
    local accountMax = MAX_ACCOUNT_MACROS or 120
    local function add(index)
        local name, icon = GetMacroInfo(index)
        if name then list[#list + 1] = { kind = "macro", id = name, name = name, icon = icon } end
    end
    for i = 1, global or 0 do add(i) end
    for i = accountMax + 1, accountMax + (perCharacter or 0) do add(i) end
    return list
end

local function CollectBuiltin()
    local list = {}
    for _, entry in ipairs(ns.BUILTIN) do
        list[#list + 1] = { kind = entry.kind, id = entry.id, name = entry.name, icon = entry.icon }
    end
    return list
end

local COLLECT = { spells = CollectSpells, items = CollectItems, macros = CollectMacros, builtin = CollectBuiltin }
local EMPTY = {
    spells = "Aucun sort actif dans le grimoire.",
    items = "Aucun objet utilisable dans tes sacs.",
    macros = "Aucune macro. Crée-en avec /macro.",
    builtin = "",
}

-- ---------------------------------------------------------------------------------------

local frame, title, pageLabel, emptyLabel, cells, tabButtons
local target, list, page, tab = nil, {}, 1, "spells"

local function Show()
    local first = (page - 1) * PER_PAGE
    for i = 1, PER_PAGE do
        local cell, entry = cells[i], list[first + i]
        cell.entry = entry
        if entry then
            cell.icon:SetTexture(entry.icon or ns.EntryIcon(entry) or ns.QUESTION)
            cell.name:SetText(entry.name or "")
            cell:Show()
        else
            cell:Hide()
        end
    end
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    pageLabel:SetText(page .. " / " .. pages)
    emptyLabel:SetText(#list == 0 and EMPTY[tab] or "")
    for _, button in ipairs(tabButtons) do
        button.back:SetVertexColor(button.key == tab and 0.85 or 0.18, button.key == tab and 0.68 or 0.18,
            button.key == tab and 0.3 or 0.22, 0.95)
    end
end

local function SelectTab(key)
    tab = key
    page = 1
    local ok, result = pcall(COLLECT[key])
    list = ok and result or {}
    if not ok then ns.Print("|cffff5555erreur|r en listant : " .. tostring(result)) end
    Show()
end

local function Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.back = ns.Box(button, "BACKGROUND", 0.18, 0.18, 0.22, 0.95)
    button.text = ns.Label(button, "GameFontHighlightLarge", text)
    button.text:SetPoint("CENTER")
    local highlight = ns.Box(button, "HIGHLIGHT", 1, 1, 1, 0.12)
    highlight:SetBlendMode("ADD")
    button:SetScript("OnClick", onClick)
    return button
end
ns.UIButton = Button

local function Build()
    frame = CreateFrame("Frame", "WolkaraMobilePicker", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetSize(COLUMNS * CELL_W + 40, ROWS * CELL_H + 170)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:Hide()
    ns.Box(frame, "BACKGROUND", 0.04, 0.05, 0.08, 0.96)

    title = ns.Label(frame, "GameFontNormalLarge", "Choisir pour cette case")
    title:SetPoint("TOP", 0, -12)

    tabButtons = {}
    local tabWidth = (COLUMNS * CELL_W) / #TABS - 6
    for i, info in ipairs(TABS) do
        local button = Button(frame, info.label, tabWidth, 34, function() SelectTab(info.key) end)
        button.key = info.key
        button:SetPoint("TOPLEFT", 20 + (i - 1) * (tabWidth + 8), -40)
        tabButtons[i] = button
    end

    cells = {}
    for i = 1, PER_PAGE do
        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(CELL_W - 6, CELL_H - 6)
        local column, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
        cell:SetPoint("TOPLEFT", 20 + column * CELL_W, -84 - row * CELL_H)
        ns.Box(cell, "BACKGROUND", 0.1, 0.1, 0.14, 0.9)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(54, 54)
        cell.icon:SetPoint("TOP", 0, -6)
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ns.Circle(cell, cell.icon)
        cell.name = ns.Label(cell, "GameFontHighlightSmall")
        cell.name:SetPoint("TOP", cell.icon, "BOTTOM", 0, -4)
        cell.name:SetWidth(CELL_W - 10)
        cell.name:SetHeight(26)
        cell.name:SetJustifyV("TOP")
        if cell.name.SetMaxLines then cell.name:SetMaxLines(2) end
        local highlight = ns.Box(cell, "HIGHLIGHT", 1, 1, 1, 0.12)
        highlight:SetBlendMode("ADD")
        cell:SetScript("OnClick", function(self)
            if not self.entry or not target then return end
            if InCombatLockdown() then ns.Print("on remplit les cases hors combat."); return end
            local entry = self.entry
            ns.AssignEntry(target, { kind = entry.kind, id = entry.id, name = entry.kind == "macrotext" and entry.name or nil,
                icon = entry.kind == "macrotext" and entry.icon or nil })
            Picker:Close()
        end)
        cells[i] = cell
    end

    emptyLabel = ns.Label(frame, "GameFontHighlight")
    emptyLabel:SetPoint("CENTER", 0, 10)

    local previous = Button(frame, "<", 70, 38, function()
        if page > 1 then page = page - 1; Show() end
    end)
    previous:SetPoint("BOTTOMLEFT", 20, 14)
    local nextPage = Button(frame, ">", 70, 38, function()
        if page < math.ceil(#list / PER_PAGE) then page = page + 1; Show() end
    end)
    nextPage:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    pageLabel = ns.Label(frame, "GameFontHighlight")
    pageLabel:SetPoint("LEFT", nextPage, "RIGHT", 12, 0)

    local close = Button(frame, "Fermer", 120, 38, function() Picker:Close() end)
    close:SetPoint("BOTTOMRIGHT", -20, 14)
    local clear = Button(frame, "Vider la case", 170, 38, function()
        if target and not InCombatLockdown() then ns.AssignEntry(target, nil) end
        Picker:Close()
    end)
    clear:SetPoint("RIGHT", close, "LEFT", -8, 0)
end

function Picker:Init() Build() end

function Picker:Open(button)
    if InCombatLockdown() or not frame then return end
    target = button
    title:SetText(button:GetEntry() and ("Remplacer : " .. (ns.EntryName(button:GetEntry()) or "")) or "Choisir pour cette case")
    frame:Show()
    SelectTab(tab)
end

function Picker:IsOpen() return frame ~= nil and frame:IsShown() end

function Picker:Close()
    target = nil
    if frame then frame:Hide() end
end

function Picker:CombatStarts() self:Close() end
