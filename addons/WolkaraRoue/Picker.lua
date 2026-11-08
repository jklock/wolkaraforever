-- Interface mobile : le sélecteur. Toucher une case ouvre la grille de tes sorts, objets
-- utilisables, macros et actions toutes faites ; toucher une icône la range dans la case.
-- Des pages plutôt qu'un défilement, parce qu'un doigt ne fait pas défiler une liste du jeu.

local _, ns = ...

local COLUMNS, ROWS = 5, 3
local PER_PAGE = COLUMNS * ROWS
local CELL_W, CELL_H = 86, 92
local RAIL_W = 124
local CATEGORIES = {
    { key = "spells", label = "Spells", filters = { "All", "Class", "General" } },
    { key = "professions", label = "Professions" },
    { key = "mounts", label = "Mounts", filters = { "All", "Usable", "Favorites" } },
    { key = "toys", label = "Toys", filters = { "All", "Favorites" } },
    { key = "pets", label = "Pets", filters = { "All", "Favorites" } },
    { key = "items", label = "Items" },
    { key = "macros", label = "Macros" },
    { key = "builtin", label = "Actions" },
}

local Picker = ns.Register("Picker", {})
ns.Picker = Picker

local BOOK = BOOKTYPE_SPELL or "spell"

local function CollectSpells()
    local list, seen = {}, {}
    local group = "general"
    local function add(spellID, name, icon)
        if not spellID or not name then return end
        if seen[name] then
            -- Les rangs d'un même sort se suivent : on garde le dernier, le plus haut.
            list[seen[name]].id = spellID
            list[seen[name]].icon = icon or list[seen[name]].icon
            return
        end
        list[#list + 1] = { kind = "spell", id = spellID, name = name, icon = icon, group = group }
        seen[name] = #list
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            group = line == 1 and "general" or "class"
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
            group = tab == 1 and "general" or "class"
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
        list[#list + 1] = { kind = "item", id = id, name = ns.ItemName(id) or (ns.T("Item ") .. id), icon = ns.ItemIcon(id) }
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
        list[#list + 1] = { kind = entry.kind, id = entry.id, name = ns.T(entry.name), icon = entry.icon }
    end
    return list
end

local function CollectProfessions()
    return ns.ProfessionSpells and ns.ProfessionSpells() or {}
end

local function CollectMounts()
    local list = {}
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then return list end
    for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
        local name, spellID, icon, _, usable, _, favorite, _, _, hidden, collected = C_MountJournal.GetMountInfoByID(mountID)
        if name and spellID and collected and not hidden then
            list[#list + 1] = { kind = "spell", id = spellID, name = name, icon = icon, usable = usable, favorite = favorite }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function CollectToys()
    local list = {}
    if not (C_ToyBox and C_ToyBox.GetToyFromIndex and (C_ToyBox.GetNumFilteredToys or C_ToyBox.GetNumToys)) then return list end
    local count = C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys() or C_ToyBox.GetNumToys()
    for i = 1, count do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID and itemID > 0 and (not PlayerHasToy or PlayerHasToy(itemID)) then
            local _, name, icon, favorite = C_ToyBox.GetToyInfo(itemID)
            if name then
                list[#list + 1] = { kind = "macrotext", id = "/use " .. name, name = name, icon = icon, favorite = favorite }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function CollectPets()
    local list = {}
    if not (C_PetJournal and C_PetJournal.GetNumPets and C_PetJournal.GetPetInfoByIndex) then return list end
    for i = 1, (C_PetJournal.GetNumPets()) do
        local petID, _, owned, customName, _, favorite, _, speciesName, icon = C_PetJournal.GetPetInfoByIndex(i)
        if petID and owned then
            local name = (customName and customName ~= "") and customName or speciesName or ""
            list[#list + 1] = { kind = "macrotext", id = '/run C_PetJournal.SummonPetByGUID("' .. petID .. '")',
                name = name, icon = icon, favorite = favorite }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local COLLECT = { spells = CollectSpells, professions = CollectProfessions, mounts = CollectMounts, toys = CollectToys,
    pets = CollectPets, items = CollectItems, macros = CollectMacros, builtin = CollectBuiltin }
local EMPTY = {
    spells = "No active spells in your spellbook.",
    professions = "No professions learned yet.",
    mounts = "No mounts collected yet.",
    toys = "No toys collected yet.",
    pets = "No pets collected yet.",
    items = "No usable items in your bags.",
    macros = "No macros yet. Create one with /macro.",
    builtin = "",
}

-- ---------------------------------------------------------------------------------------

local frame, title, pageLabel, emptyLabel, cells, railButtons, chips, presetChips
local target, all, list, page, category, filter = nil, {}, {}, 1, "spells", "All"
local selectedPreset = 1

local function Category(key)
    for _, info in ipairs(CATEGORIES) do if info.key == key then return info end end
end

local function Filtered()
    if filter == "All" then return all end
    local out = {}
    for _, entry in ipairs(all) do
        if (filter == "Class" and entry.group == "class") or (filter == "General" and entry.group == "general")
            or (filter == "Usable" and entry.usable) or (filter == "Favorites" and entry.favorite) then
            out[#out + 1] = entry
        end
    end
    return out
end

local function SameEntry(a, b)
    return a and b and a.kind == b.kind and a.id == b.id
end

local function Pill(parent, width, height)
    local pill = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pill:SetSize(width, height)
    if pill.SetBackdrop then
        pill:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    end
    pill.text = ns.Label(pill, "GameFontHighlightSmall")
    pill.text:SetPoint("CENTER")
    if pill.text.SetWordWrap then pill.text:SetWordWrap(false) end
    function pill:SetOn(on, empty)
        if self.SetBackdropColor then
            if on then self:SetBackdropColor(0.84, 0.65, 0.16, 0.95); self:SetBackdropBorderColor(0.84, 0.65, 0.16, 1)
            else self:SetBackdropColor(0.16, 0.14, 0.11, 0.95); self:SetBackdropBorderColor(0.36, 0.29, 0.20, empty and 0.6 or 0.9) end
        end
        if on then self.text:SetTextColor(0.16, 0.1, 0.02)
        elseif empty then self.text:SetTextColor(0.61, 0.57, 0.51)
        else self.text:SetTextColor(0.91, 0.89, 0.83) end
    end
    return pill
end

local function PresetSaved(slot) return ns.db and ns.db.layouts and ns.db.layouts[slot] ~= nil end

local function ShowPresets()
    for slot, chip in ipairs(presetChips) do
        local saved = PresetSaved(slot)
        chip.text:SetText(tostring(slot))
        chip:SetOn(slot == selectedPreset, not saved)
        chip.active:SetShown(ns.db and ns.db.presetActive == slot)
    end
end

local function Show()
    list = Filtered()
    local first = (page - 1) * PER_PAGE
    local current = target and target:GetEntry()
    for i = 1, PER_PAGE do
        local cell, entry = cells[i], list[first + i]
        cell.entry = entry
        if entry then
            cell.icon:SetTexture(entry.icon or ns.EntryIcon(entry) or ns.QUESTION)
            cell.name:SetText(entry.name or "")
            cell.current:SetShown(SameEntry(entry, current))
            cell.star:SetShown(entry.favorite and true or false)
            cell:Show()
        else
            cell:Hide()
        end
    end
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    pageLabel:SetText(page .. " / " .. pages)
    emptyLabel:SetText(#all == 0 and ns.T(EMPTY[category]) or (#list == 0 and ns.T("Nothing here with this filter.") or ""))
    for _, button in ipairs(railButtons) do
        local on = button.key == category
        button.bar:SetShown(on)
        button.glow:SetShown(on)
        button.text:SetTextColor(on and 1 or 0.91, on and 0.82 or 0.89, on and 0.29 or 0.83)
    end
    local info = Category(category)
    for i, chip in ipairs(chips) do
        local name = info.filters and info.filters[i]
        if name then
            chip.filter = name
            chip.text:SetText(ns.T(name))
            chip:SetWidth(chip.text:GetStringWidth() + 26)
            chip:SetOn(name == filter)
            chip:Show()
        else
            chip:Hide()
        end
    end
    ShowPresets()
end

local function Recollect()
    local ok, result = pcall(COLLECT[category])
    all = ok and result or {}
    if not ok then ns.Print(ns.T("|cffff5555error|r while listing: ") .. tostring(result)) end
    page = math.max(1, math.min(page, math.ceil(#Filtered() / PER_PAGE)))
    Show()
end

local function SelectCategory(key)
    category = key
    filter = "All"
    page = 1
    local ok, result = pcall(COLLECT[key])
    all = ok and result or {}
    if not ok then ns.Print(ns.T("|cffff5555error|r while listing: ") .. tostring(result)) end
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

local function SmallButton(parent, text, width, height, onClick)
    local button = Button(parent, text, width, height, onClick)
    button.text:SetFontObject("GameFontHighlight")
    return button
end

local function Build()
    frame = CreateFrame("Frame", "WolkaraMobilePicker", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local gridW = COLUMNS * CELL_W
    frame:SetSize(20 + RAIL_W + 14 + gridW + 20, 520)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:Hide()
    ns.Box(frame, "BACKGROUND", 0.06, 0.06, 0.08, 0.95)

    title = ns.Label(frame, "GameFontNormalLarge", ns.T("Choose for this slot"))
    title:SetPoint("TOP", 0, -16)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.79, 0.64, 0.36, 0.7)
    divider:SetSize(260, 1)
    divider:SetPoint("TOP", 0, -40)

    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", 20, -50)
    strip:SetPoint("TOPRIGHT", -20, -50)
    strip:SetHeight(34)
    ns.Box(strip, "BACKGROUND", 0.04, 0.03, 0.03, 0.7)
    local label = ns.Label(strip, "GameFontHighlightSmall", ns.T("Preset"))
    label:SetPoint("LEFT", 10, 0)
    label:SetTextColor(0.61, 0.57, 0.51)
    presetChips = {}
    for slot = 1, 3 do
        local chip = Pill(strip, 40, 24)
        if slot == 1 then chip:SetPoint("LEFT", label, "RIGHT", 10, 0) else chip:SetPoint("LEFT", presetChips[slot - 1], "RIGHT", 6, 0) end
        chip.active = chip:CreateTexture(nil, "OVERLAY")
        chip.active:SetSize(6, 6)
        chip.active:SetPoint("TOPRIGHT", -4, -4)
        chip.active:SetColorTexture(0.3, 1, 0.4, 1)
        chip:SetScript("OnClick", function() selectedPreset = slot; ShowPresets() end)
        presetChips[slot] = chip
    end
    local save = SmallButton(strip, ns.T("Save"), 60, 26, function()
        if ns.SavePreset then ns.SavePreset(selectedPreset) end
        ShowPresets()
    end)
    save:SetPoint("RIGHT", -6, 0)
    local load = SmallButton(strip, ns.T("Load"), 60, 26, function()
        if ns.LoadPreset then ns.LoadPreset(selectedPreset) end
        ShowPresets(); Show()
    end)
    load:SetPoint("RIGHT", save, "LEFT", -6, 0)

    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", 20, -96)
    rail:SetSize(RAIL_W, ROWS * CELL_H + 70)
    ns.Box(rail, "BACKGROUND", 0.04, 0.03, 0.03, 0.7)
    railButtons = {}
    for i, info in ipairs(CATEGORIES) do
        local button = CreateFrame("Button", nil, rail)
        button:SetSize(RAIL_W, 36)
        button:SetPoint("TOPLEFT", 0, -6 - (i - 1) * 38)
        button.key = info.key
        button.text = ns.Label(button, "GameFontHighlight", ns.T(info.label))
        button.text:SetPoint("LEFT", 14, 0)
        button.bar = button:CreateTexture(nil, "ARTWORK")
        button.bar:SetColorTexture(1, 0.82, 0.29, 1)
        button.bar:SetSize(3, 28)
        button.bar:SetPoint("LEFT")
        button.glow = button:CreateTexture(nil, "BACKGROUND")
        button.glow:SetAllPoints()
        button.glow:SetColorTexture(1, 0.82, 0.29, 0.08)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
        button:SetScript("OnClick", function() SelectCategory(info.key) end)
        railButtons[i] = button
    end

    local gridLeft = 20 + RAIL_W + 14
    chips = {}
    for i = 1, 3 do
        local chip = Pill(frame, 60, 24)
        if i == 1 then chip:SetPoint("TOPLEFT", gridLeft, -98) else chip:SetPoint("LEFT", chips[i - 1], "RIGHT", 6, 0) end
        chip:SetScript("OnClick", function(self) filter = self.filter; page = 1; Show() end)
        chips[i] = chip
    end

    cells = {}
    for i = 1, PER_PAGE do
        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(CELL_W - 4, CELL_H - 4)
        local column, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
        cell:SetPoint("TOPLEFT", gridLeft + column * CELL_W, -132 - row * CELL_H)
        local holder = CreateFrame("Frame", nil, cell)
        holder:SetSize(48, 48)
        holder:SetPoint("TOP", 0, -4)
        cell.ring = ns.Disc(holder, "BACKGROUND", 0.54, 0.43, 0.23, 1, 3)
        cell.current = ns.Disc(holder, "BORDER", 1, 0.82, 0.29, 1, 3)
        cell.current:Hide()
        cell.icon = holder:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints()
        cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ns.Circle(holder, cell.icon)
        cell.star = holder:CreateTexture(nil, "OVERLAY")
        cell.star:SetSize(16, 16)
        cell.star:SetPoint("TOPRIGHT", 4, 4)
        cell.star:SetTexture("Interface\\Common\\FavoritesIcon")
        cell.star:Hide()
        local press = ns.Disc(holder, "HIGHLIGHT", 1, 1, 1, 0.15, 0)
        press:SetBlendMode("ADD")
        cell.name = ns.Label(cell, "GameFontHighlightSmall")
        cell.name:SetPoint("TOP", holder, "BOTTOM", 0, -5)
        cell.name:SetWidth(CELL_W - 6)
        cell.name:SetHeight(26)
        cell.name:SetJustifyV("TOP")
        if cell.name.SetMaxLines then cell.name:SetMaxLines(2) end
        cell:SetScript("OnClick", function(self)
            if not self.entry or not target then return end
            if InCombatLockdown() then ns.Print(ns.T("slots can only be filled out of combat.")); return end
            local entry = self.entry
            ns.AssignEntry(target, { kind = entry.kind, id = entry.id, name = entry.kind == "macrotext" and entry.name or nil,
                icon = entry.kind == "macrotext" and entry.icon or nil })
            if ns.editMode then Picker:Open(target) else Picker:Close() end
        end)
        cells[i] = cell
    end

    emptyLabel = ns.Label(frame, "GameFontHighlight")
    emptyLabel:SetPoint("CENTER", frame, "TOPLEFT", gridLeft + gridW / 2, -132 - ROWS * CELL_H / 2)

    local pagerY = -132 - ROWS * CELL_H - 4
    pageLabel = ns.Label(frame, "GameFontHighlight")
    pageLabel:SetPoint("TOP", frame, "TOPLEFT", gridLeft + gridW / 2, pagerY - 10)
    local previous = SmallButton(frame, "<", 40, 30, function()
        if page > 1 then page = page - 1; Show() end
    end)
    previous:SetPoint("RIGHT", pageLabel, "LEFT", -14, 0)
    local nextPage = SmallButton(frame, ">", 40, 30, function()
        if page < math.ceil(#list / PER_PAGE) then page = page + 1; Show() end
    end)
    nextPage:SetPoint("LEFT", pageLabel, "RIGHT", 14, 0)

    local editAll = SmallButton(frame, ns.T("Edit mode"), 130, 30, function()
        if ns.editMode then
            if ns.ExitEditMode then ns.ExitEditMode() end
        elseif ns.EnterEditMode then
            ns.EnterEditMode(target)
        end
    end)
    editAll:SetPoint("TOPRIGHT", -14, -10)
    frame.editAll = editAll
    local close = Button(frame, ns.T("Close"), 160, 36, function()
        if ns.editMode and ns.ExitEditMode then ns.ExitEditMode() else Picker:Close() end
    end)
    frame.closeButton = close
    close:SetPoint("BOTTOMRIGHT", -20, 14)
    local clear = Button(frame, ns.T("Clear slot"), 130, 36, function()
        if target and not InCombatLockdown() then ns.AssignEntry(target, nil) end
        if ns.editMode and target then Picker:Open(target) else Picker:Close() end
    end)
    clear:SetPoint("RIGHT", close, "LEFT", -8, 0)
end

function Picker:Init() Build() end

function Picker:Open(button)
    if InCombatLockdown() or not frame then return end
    target = button
    title:SetText(button:GetEntry() and (ns.T("Replace: ") .. (ns.EntryName(button:GetEntry()) or "")) or ns.T("Choose for this slot"))
    if frame.editAll then frame.editAll:SetShown(not ns.editMode) end
    if frame.closeButton then
        frame.closeButton.text:SetText(ns.editMode and ns.T("Save & Close") or ns.T("Close"))
        if ns.SkinPrimary then ns.SkinPrimary(frame.closeButton, ns.editMode) end
    end
    if ns.db and ns.db.presetActive then selectedPreset = ns.db.presetActive end
    frame:Show()
    Recollect()
end

function Picker:IsOpen() return frame ~= nil and frame:IsShown() end

function Picker:Close()
    target = nil
    if frame then frame:Hide() end
end

function Picker:CombatStarts() self:Close() end

ns.On("BAG_UPDATE_DELAYED", function() if frame and frame:IsShown() and category == "items" then SelectCategory("items") end end)
