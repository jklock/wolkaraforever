-- TouchPlay: the spell picker (rule 4): change or remove what a spell button does.
--
-- "Change spell" on an action card (or a tap on an empty button, which shows a +) opens a sheet
-- on the school of the spell being replaced: school chips, a grid of the spellbook (6 columns of
-- 64 icons with names, a green dot on spells already on a button), "Put on button" and "Cancel".
-- The button being changed shows a pulsing gold dashed ring. After Put, the button flashes once
-- with the spell's name above it.
--
-- The item column (ItemRail.lua) uses the same sheet: Picker.OpenItem(index) opens it on the Items tab for one of the
-- column's four slots, with the tab row hidden; "Pin to slot" pins the chosen item there (ItemRail.Pin), so the
-- slot keeps that item, grey with 0 when none is left. Items of the slot's own kind come first.
--
-- Placing goes through the game's own cursor: C_Spell.PickupSpell (or C_Item.PickupItem, or the mount
-- journal's C_MountJournal.Pickup), then PlaceAction(slot), then ClearCursor(). Mounts are never summoned
-- by this add-on (SummonByID is protected): the button the player makes does that when tapped. Removing is PickupAction(slot), ClearCursor(). The game
-- does not allow either in a fight, so neither is ever called then: the sheet greys "Put on
-- button" and says why instead.
--
-- Ranks: this client's spellbook lists every known rank of a spell as its own item (its own spell id), with the
-- rank text in subName and C_SpellBook.IsSpellBookItemLowRank marking the ones below the highest. One row per
-- spell is shown at its highest rank, with a "Rank N" control to pick a lower one; "Show all ranks" (the game's
-- own spellbook checkbox, CVar ShowAllSpellRanks, is the starting value; the choice is kept in
-- TouchPlayDB.showAllRanks) lists every rank as its own row. Placing puts that exact rank's spell id.
--
-- Mounts tab: besides Put on button, "Put on Mount button" pins the chosen mount (or the random favourite) to the
-- Dive ring's Mount face (R50, Interact.PinMount): a tap there summons it. Greyed in a fight, like Put.
--
-- Spellbook names and icons go only to SetText and SetTexture: they are never compared or used
-- as keys. The one text lookup (Picker.Entries("Frost")) is behind a hidden-value check; inside
-- the picker everything works by index. The pulse and the flash are animation groups: no
-- OnUpdate anywhere.

local ADDON_NAME, ns = ...

local Picker = ns.Register("Picker", {})
local Kit = ns.Kit

ns.L["picker.title"] = "Choose a spell for this button"
ns.L["picker.put"] = "Put on button"
ns.L["picker.legend"] = "already on a button"
ns.L["picker.items"] = "Items"
ns.L["picker.mounts"] = "Mounts"
ns.L["picker.randomMount"] = "Random favourite mount"
ns.L["picker.pinMount"] = "Put on Mount button"
ns.L["picker.chooseFirst"] = "Choose one above first"
ns.L["picker.chooseMount"] = "Choose a mount above first"
ns.L["picker.showAllRanks"] = "Show all ranks"
ns.L["picker.none"] = "Nothing to choose here."
ns.L["picker.plus"] = "+"
ns.L["picker.itemTitle"] = "Choose an item for this slot"
ns.L["picker.pin"] = "Pin to slot"
ns.L["picker.legendRail"] = "already pinned in the column"

-- Mockup 93, in layout units: the sheet's top-left, size, and the parts inside it.
local SHEET_X, SHEET_Y, SHEET_W, SHEET_H = 40, 420, 960, 580
local TABS_X, TABS_Y = 24, 54
local COLS, ROWS = 6, 2
local PER_PAGE = COLS * ROWS
local CELL_W, CELL_H = 136, 148
local GRID_X, GRID_Y, GRID_STEP = 26, 132, 150       -- the first cell's top-left, and the step
local ICON = 64
local FRAME_RATIO = 1.68                              -- the Quickslot frame is 1.68 x the icon
local PUT_X, PUT_Y, PUT_W, PUT_H = 520, 500, 220, 56
local CANCEL_X, CANCEL_W = 750, 190
local LEGEND_X, LEGEND_Y = 26, 510
local CHIP_X, CHIP_Y = 20, 530                      -- "Show all ranks", under the legend
local PIN_W, PIN_H = 260, 44                         -- "Put on Mount button", in the chip's place on Mounts
local RANK_H = 28                                    -- the rank control's art; its tap area grows to 44
local MENU_W, MENU_ROW = 210, 44                     -- the rank list: one 44 high row per rank
local MENU_MAX = 16
local ARROW = 44
local ITEMS = "Items"                                 -- the Items tab's key; not a spellbook name
local MOUNTS = "Mounts"                               -- the Mounts tab's key
local RANDOM_MOUNT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local RANDOM_MOUNT_SPELL = 150544                     -- Summon Random Favorite Mount: only its picture is used

local FRAME_ART = "Interface\\Buttons\\UI-Quickslot2"
local DISC_ART = "Interface\\Minimap\\UI-Minimap-Background"
local GLOW_ART = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ARROW_ART = "Interface\\Buttons\\UI-SpellbookIcon-"
local DROP_ART = "Interface\\Buttons\\Arrow-Down-Up"

local GOLD = { 1, 0.82, 0 }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Text equality for the one text-keyed lookup: a hidden value is never "the same".
local function SameText(a, b)
    if Secret(a) or Secret(b) then return false end
    return a == b
end

local function NewText(parent, size, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, font or Kit.FONT_TITLE, size, "")
    return fs
end

-- ---------------------------------------------------------------------------------------
-- What is on a button now (the green dots)

local onSpell, onItem, onMount = {}, {}, {}

local function ScanButtons()
    for k in pairs(onSpell) do onSpell[k] = nil end
    for k in pairs(onItem) do onItem[k] = nil end
    for k in pairs(onMount) do onMount[k] = nil end
    local Cluster = ns.Cluster
    if not Cluster or not GetActionInfo then return end
    for page = 1, 4 do
        for i = 1, 7 do
            local kind, id = GetActionInfo(Cluster.Slot(page, i))
            if type(id) == "number" and not Secret(id) then
                if kind == "spell" then onSpell[id] = true
                elseif kind == "item" then onItem[id] = true
                elseif kind == "summonmount" then onMount[id] = true end
            end
        end
    end
end

local function IsOnButton(entry)
    if entry.kind == "item" then return onItem[entry.id] == true end
    if entry.kind == "mount" then return onMount[entry.id] == true end
    return (onSpell[entry.id] or (entry.base ~= nil and onSpell[entry.base])) == true
end

-- ---------------------------------------------------------------------------------------
-- Entries: what a tab holds

-- The tabs, in order: one per spell school the spellbook shows, then Items.
local function TabList()
    local list = {}
    local book = C_SpellBook
    local lines = book and book.GetNumSpellBookSkillLines and book.GetNumSpellBookSkillLines() or 0
    for i = 1, lines do
        local info = book.GetSpellBookSkillLineInfo(i)
        if info and not info.isGuild and not info.shouldHide and info.offSpecID == nil then
            list[#list + 1] = { line = i, name = info.name, offset = info.itemIndexOffset,
                count = info.numSpellBookItems }
        end
    end
    if C_MountJournal and C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetDisplayedMountInfo then
        list[#list + 1] = { mounts = true, name = MOUNTS }
    end
    list[#list + 1] = { items = true, name = ITEMS }
    return list
end

-- The player's choice for "Show all ranks", else the game's own spellbook checkbox, else off.
function Picker.ShowAllRanks()
    local saved = TouchPlayDB and TouchPlayDB.showAllRanks
    if type(saved) == "boolean" then return saved end
    local cvar = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("ShowAllSpellRanks")
    return cvar == "1"
end

local function PlainText(v)
    return type(v) == "string" and not Secret(v)
end

-- The number in a rank's text ("Rank 7"), nil when it has none or is hidden.
local function RankNumber(text)
    return PlainText(text) and tonumber(text:match("%d+")) or nil
end

-- Highest first: by the number in the rank text when every rank has one, else the spellbook's order
-- (the highest known rank is first already).
local function SortRanks(ranks)
    for _, r in ipairs(ranks) do
        if not RankNumber(r.rank) then return end
    end
    table.sort(ranks, function(a, b) return RankNumber(a.rank) > RankNumber(b.rank) end)
end

local function SpellEntries(tab)
    local out = {}
    local book = C_SpellBook
    if not book or not book.GetSpellBookItemInfo then return out end
    local spell = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local rows, byName, lows = {}, {}, {}
    for slot = tab.offset + 1, tab.offset + tab.count do
        local item = book.GetSpellBookItemInfo(slot, bank)
        if item and item.itemType == spell and not item.isPassive and not item.isOffSpec then
            local id = item.spellID or item.actionID
            if type(id) == "number" and not Secret(id) then
                local rank = { id = id, base = item.actionID, icon = item.iconID, rank = item.subName or "" }
                local low = book.IsSpellBookItemLowRank and book.IsSpellBookItemLowRank(slot, bank) == true
                local row = { name = item.name, ranks = { rank }, first = rank }
                if low then
                    lows[#lows + 1] = row
                else
                    rows[#rows + 1] = row
                    if PlainText(item.name) then byName[item.name] = row end
                end
            end
        end
    end
    -- a lower rank joins the row of its highest rank (found by the spell's name); one with no row of its own stays a row
    for _, row in ipairs(lows) do
        local top = PlainText(row.name) and byName[row.name]
        if top then top.ranks[#top.ranks + 1] = row.first else rows[#rows + 1] = row end
    end
    local all = Picker.ShowAllRanks()
    for _, row in ipairs(rows) do
        if #row.ranks > 1 then SortRanks(row.ranks) end
        if all then
            for _, r in ipairs(row.ranks) do
                local entry = { kind = "spell", id = r.id, base = r.base, icon = r.icon, name = row.name, rank = r.rank }
                entry.onButton = IsOnButton(entry)
                out[#out + 1] = entry
            end
        else
            local top = row.ranks[1]
            local entry = { kind = "spell", id = top.id, base = top.base, icon = top.icon, name = row.name, rank = top.rank }
            if #row.ranks > 1 then entry.ranks, entry.rankIndex = row.ranks, 1 end
            entry.onButton = IsOnButton(entry)
            out[#out + 1] = entry
        end
    end
    return out
end

local function ItemEntries()
    local out = {}
    local container, itemApi = C_Container, C_Item
    if not container or not itemApi or not itemApi.GetItemSpell then return out end
    local seen = {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, container.GetContainerNumSlots(bag) or 0 do
            local info = container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" and not Secret(id) and not seen[id] and itemApi.GetItemSpell(id) then
                seen[id] = true
                local entry = { kind = "item", id = id, icon = info.iconFileID, name = info.itemName }
                entry.onButton = IsOnButton(entry)
                out[#out + 1] = entry
            end
        end
    end
    return out
end

-- The collected mounts the journal shows this player (its own filters decide what that is; they are never
-- changed here): the random favourite first when there is a favourite, then favourites, then the rest, each
-- alphabetical. Names are plain text, but a hidden one is left out rather than compared.
local function MountEntries()
    local out = {}
    local journal = C_MountJournal
    if not journal or not journal.GetNumDisplayedMounts or not journal.GetDisplayedMountInfo then return out end
    local anyFavourite = false
    for i = 1, journal.GetNumDisplayedMounts() or 0 do
        local name, _, icon, _, _, _, favourite, _, _, hidden, collected, id = journal.GetDisplayedMountInfo(i)
        if collected and not hidden and type(id) == "number" and not Secret(id) and type(name) == "string" and not Secret(name) then
            local entry = { kind = "mount", id = id, icon = icon, name = name, favourite = favourite == true }
            entry.onButton = IsOnButton(entry)
            out[#out + 1] = entry
            if entry.favourite then anyFavourite = true end
        end
    end
    table.sort(out, function(a, b)
        if a.favourite ~= b.favourite then return a.favourite end
        return a.name < b.name
    end)
    if anyFavourite then
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(RANDOM_MOUNT_SPELL)
        table.insert(out, 1, { kind = "mount", id = 0, random = true, icon = icon or RANDOM_MOUNT_ICON,
            name = ns.T("picker.randomMount"), onButton = false })
    end
    return out
end

-- The Items tab for a slot of the item column: the slot's own kind first (bag order inside each group), a green dot
-- on what the column already pins.
local function RailEntries(list, index)
    local rail = ns.ItemRail
    local cat = rail and rail.SlotCategory and rail.SlotCategory(index)
    local own, rest = {}, {}
    for _, entry in ipairs(list) do
        entry.onButton = rail ~= nil and rail.PinnedSlot(entry.id) ~= nil
        local kind = rail and rail.Classify(entry.id)
        if kind and kind.cat == cat then own[#own + 1] = entry else rest[#rest + 1] = entry end
    end
    for _, entry in ipairs(rest) do own[#own + 1] = entry end
    return own
end

local function EntriesFor(tab)
    ScanButtons()
    if tab.items then
        local list = ItemEntries()
        if Picker.rail then list = RailEntries(list, Picker.rail) end
        return list
    end
    if tab.mounts then return MountEntries() end
    return SpellEntries(tab)
end

-- Entries(tab): tab is "General", a school's name as the spellbook shows it, or "Items".
function Picker.Entries(tab)
    local list = TabList()
    for _, t in ipairs(list) do
        if SameText(tab, t.items and ITEMS or t.mounts and MOUNTS or t.name) then return EntriesFor(t) end
    end
    return {}
end

-- ---------------------------------------------------------------------------------------
-- The pieces: dim layer, sheet, grid, ring and flash. Frame levels are set before the children
-- are made, so the parts stack the way the mockup does.

local dim = CreateFrame("Frame", nil, ns.root)
dim:SetFrameStrata(Kit.SHEET_STRATA)   -- the picker and its parts sit above every window (iPad run 6)
dim:SetAllPoints(ns.root)
dim:SetFrameLevel(40)
dim:EnableMouse(false)                 -- the cluster stays tappable: a fight can start any time
dim.shade = dim:CreateTexture(nil, "BACKGROUND")
dim.shade:SetColorTexture(0, 0, 0, 0.35)
dim.shade:SetAllPoints(dim)
dim:Hide()
Picker.dim = dim

local sheet = Kit.Backdrop(ns.root, "gold", "dark")
sheet:SetFrameStrata(Kit.SHEET_STRATA)
sheet:SetSize(SHEET_W, SHEET_H)
sheet:SetFrameLevel(50)
sheet:EnableMouse(true)
sheet:Hide()
Picker.sheet = sheet
ns.Anchor(sheet, "BL", SHEET_X, SHEET_Y, "side")

local title = Kit.GoldHeader(sheet, ns.T("picker.title"))
title:SetPoint("CENTER", sheet, "TOP", 0, 0)
title:SetFrameLevel(55)
Picker.title = title

local cells = {}
Picker.cells = cells

local function PaintCell(cell)
    local picked = cell.entry ~= nil and cell.entry == Picker.selected
    cell.selectBox:SetShown(picked)
    if picked then cell.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else cell.label:SetTextColor(1, 1, 1) end
end

local function PaintCells()
    for _, cell in ipairs(cells) do PaintCell(cell) end
end

local RefreshPut

local function OnCellClick(cell)
    if not cell.entry then return end
    Picker.selected = cell.entry
    PaintCells()
    ns.Guard("picker choose", RefreshPut)
end

local function NewCell(index)
    local cell = CreateFrame("Button", nil, sheet)
    cell:SetSize(CELL_W, CELL_H)
    cell.col, cell.row = (index - 1) % COLS + 1, math.floor((index - 1) / COLS) + 1
    cell:SetPoint("TOPLEFT", sheet, "TOPLEFT",
        GRID_X + (cell.col - 1) * GRID_STEP, -(GRID_Y + (cell.row - 1) * GRID_STEP))
    cell:RegisterForClicks("LeftButtonUp")
    -- the gold box round the chosen spell
    cell.selectBox = Kit.Backdrop(cell, "tooltip", "tooltip")
    cell.selectBox:SetAllPoints(cell)
    cell.selectBox:EnableMouse(false)
    cell.selectBox:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.16)
    cell.selectBox:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    cell.selectBox:Hide()
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON, ICON)
    cell.icon:SetPoint("TOP", cell, "TOP", 0, -8)
    local frame = cell:CreateTexture(nil, "OVERLAY")
    frame:SetTexture(FRAME_ART)
    local off = (math.floor(ICON * FRAME_RATIO + 0.5) - ICON) / 2
    frame:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -off, off)
    frame:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", off, -off)
    cell.frame = frame
    cell.label = NewText(cell, 15)
    cell.label:SetWidth(CELL_W - 4)
    cell.label:SetPoint("TOP", cell, "TOP", 0, -86)
    cell.label:SetJustifyH("CENTER")
    cell.label:SetJustifyV("TOP")
    -- the green dot: the game's round disc, tinted
    cell.dot = cell:CreateTexture(nil, "OVERLAY")
    cell.dot:SetTexture(DISC_ART)
    cell.dot:SetVertexColor(0.12, 1, 0, 1)
    cell.dot:SetSize(14, 14)
    cell.dot:SetPoint("TOPLEFT", cell, "TOPLEFT", 104, -6)
    -- the rank: "Rank 7" under the name; with lower ranks known it is a button with a drop arrow that opens the list
    local rank = CreateFrame("Button", nil, cell)
    rank:SetSize(CELL_W - 24, RANK_H)
    rank:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
    rank:RegisterForClicks("LeftButtonUp")
    rank.label = NewText(rank, 14)
    rank.label:SetTextColor(0.62, 0.62, 0.62)
    rank.label:SetPoint("CENTER", rank, "CENTER", -8, 0)
    rank.arrow = rank:CreateTexture(nil, "OVERLAY")
    rank.arrow:SetTexture(DROP_ART)
    rank.arrow:SetSize(14, 14)
    rank.arrow:SetPoint("LEFT", rank.label, "RIGHT", 4, 0)
    rank.cell = cell
    Kit.FitHit(rank)
    rank:SetScript("OnClick", function(self) ns.Guard("picker rank", Picker.ToggleRankMenu, self.cell) end)
    rank:HookScript("PostClick", function() Kit.Sound("tap") end)
    rank:Hide()
    cell.rankButton = rank
    cell:SetScript("OnClick", OnCellClick)
    cell:HookScript("PostClick", function() Kit.Sound("tap") end)
    -- pressed (polish pass): the cell's edge in pale gold (the chosen one keeps its gold box under it)
    Kit.AddPress(cell, "rect", cell, 0)
    Kit.AddPress(rank, "rect", rank, 0)
    return cell
end
for i = 1, PER_PAGE do cells[i] = NewCell(i) end

local noneText = NewText(sheet, 17)
noneText:SetTextColor(0.62, 0.62, 0.62)
noneText:SetPoint("TOP", sheet, "TOP", 0, -240)
noneText:SetText(ns.T("picker.none"))
noneText:Hide()
Picker.noneText = noneText

-- Page arrows, for a school with more than 12 spells.
local pageText = NewText(sheet, 16, Kit.FONT_NUMBER)
pageText:SetTextColor(0.62, 0.62, 0.62)
pageText:SetSize(60, 20)
pageText:SetPoint("TOPLEFT", sheet, "TOPLEFT", 350, -(PUT_Y + 14))
Picker.pageText = pageText

local function NewArrow(direction, x)
    local b = CreateFrame("Button", nil, sheet)
    b:SetSize(ARROW, ARROW)
    b:SetPoint("TOPLEFT", sheet, "TOPLEFT", x, -(PUT_Y + 6))
    b:SetNormalTexture(ARROW_ART .. direction .. "Page-Up")
    b:SetPushedTexture(ARROW_ART .. direction .. "Page-Down")
    b:SetDisabledTexture(ARROW_ART .. direction .. "Page-Disabled")
    b:RegisterForClicks("LeftButtonUp")
    b:HookScript("PostClick", function() Kit.Sound("tap") end)
    Kit.AddPress(b, "square", b, 0)
    return b
end
local prevButton = NewArrow("Prev", 296)
local nextButton = NewArrow("Next", 416)
Picker.prevButton, Picker.nextButton = prevButton, nextButton

-- The legend: the green dot and what it means.
local legendDot = sheet:CreateTexture(nil, "OVERLAY")
legendDot:SetTexture(DISC_ART)
legendDot:SetVertexColor(0.12, 1, 0, 1)
legendDot:SetSize(14, 14)
legendDot:SetPoint("TOPLEFT", sheet, "TOPLEFT", LEGEND_X, -(LEGEND_Y + 3))
local legend = NewText(sheet, 15)
legend:SetTextColor(0.62, 0.62, 0.62)
legend:SetJustifyH("LEFT")
legend:SetPoint("TOPLEFT", sheet, "TOPLEFT", LEGEND_X + 22, -LEGEND_Y)
legend:SetText(ns.T("picker.legend"))

local putButton = Kit.RedButton(sheet, PUT_W, PUT_H, ns.T("picker.put"))
putButton:SetPoint("TOPLEFT", sheet, "TOPLEFT", PUT_X, -PUT_Y)
local cancelButton = Kit.RedButton(sheet, CANCEL_W, PUT_H, ns.T("common.cancel"))
cancelButton:SetPoint("TOPLEFT", sheet, "TOPLEFT", CANCEL_X, -PUT_Y)
Picker.putButton, Picker.cancelButton = putButton, cancelButton

-- Mounts tab only: pin the chosen mount to the Mount ring (R50).
local pinButton = Kit.RedButton(sheet, PIN_W, PIN_H, ns.T("picker.pinMount"))
pinButton:SetPoint("TOPLEFT", sheet, "TOPLEFT", CHIP_X, -CHIP_Y)
pinButton:Hide()
Picker.pinButton = pinButton

-- "Show all ranks": the game's own spellbook checkbox, kept for this account.
local rankChip = Kit.Chip(sheet, ns.T("picker.showAllRanks"))
rankChip:SetPoint("TOPLEFT", sheet, "TOPLEFT", CHIP_X, -CHIP_Y)
rankChip:Hide()
Picker.rankChip = rankChip

-- The list of ranks one row offers: a tooltip-style panel of 44 high rows, highest first.
local rankMenu = Kit.Backdrop(sheet, "gold", "dark")
rankMenu:SetFrameLevel(58)
rankMenu:EnableMouse(true)
rankMenu:Hide()
rankMenu.buttons = {}
Picker.rankMenu = rankMenu

-- The pulsing gold dashed ring round the button being changed: 8 dashes on each side.
local DASHES, DASH_FILL, DASH_THICK = 8, 0.62, 3
local ring = CreateFrame("Frame", nil, ns.root)
ring:SetFrameStrata(Kit.SHEET_STRATA)
ring:SetFrameLevel(60)
ring:EnableMouse(false)
ring:Hide()
ring.dashes = {}
for i = 1, 4 * DASHES do
    local d = ring:CreateTexture(nil, "OVERLAY")
    d:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    ring.dashes[i] = d
end
ring.pulse = ring:CreateAnimationGroup()
ring.pulse:SetLooping("BOUNCE")
do
    local a = ring.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.55)
    a:SetSmoothing("IN_OUT")
end
Picker.ring = ring

local function LayoutRing(size)
    ring:SetSize(size, size)
    local seg = size / DASHES
    local len = seg * DASH_FILL
    for i, d in ipairs(ring.dashes) do
        local side, k = math.floor((i - 1) / DASHES), (i - 1) % DASHES
        d:ClearAllPoints()
        if side == 0 then                       -- top
            d:SetSize(len, DASH_THICK); d:SetPoint("TOPLEFT", ring, "TOPLEFT", k * seg, 0)
        elseif side == 1 then                   -- bottom
            d:SetSize(len, DASH_THICK); d:SetPoint("BOTTOMLEFT", ring, "BOTTOMLEFT", k * seg, 0)
        elseif side == 2 then                   -- left
            d:SetSize(DASH_THICK, len); d:SetPoint("TOPLEFT", ring, "TOPLEFT", 0, -k * seg)
        else                                    -- right
            d:SetSize(DASH_THICK, len); d:SetPoint("TOPRIGHT", ring, "TOPRIGHT", 0, -k * seg)
        end
    end
end

-- The flash after Put: a gold glow with the spell's name above it, once.
local flash = CreateFrame("Frame", nil, ns.root)
flash:SetFrameStrata(Kit.SHEET_STRATA)
flash:SetFrameLevel(60)
flash:EnableMouse(false)
flash:SetSize(ICON, ICON)
flash:SetAlpha(0)
flash:Hide()
flash.glow = flash:CreateTexture(nil, "ARTWORK")
flash.glow:SetTexture(GLOW_ART)
flash.glow:SetBlendMode("ADD")
flash.glow:SetVertexColor(1, 0.9, 0.55, 1)
flash.glow:SetPoint("CENTER", flash, "CENTER", 0, 0)
flash.label = NewText(flash, 30)
flash.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
flash.label:SetWidth(280)
flash.label:SetPoint("BOTTOM", flash, "CENTER", 0, 44)
flash.group = flash:CreateAnimationGroup()
do
    local up = flash.group:CreateAnimation("Alpha")
    up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.15); up:SetOrder(1)
    local hold = flash.group:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(0.9); hold:SetOrder(2)
    local down = flash.group:CreateAnimation("Alpha")
    down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.55); down:SetOrder(3)
end
flash.group:SetScript("OnFinished", function() flash:Hide() end)
Picker.flash = flash

-- ---------------------------------------------------------------------------------------
-- Buttons, the + on empty ones

local function ButtonFor(slot)
    local Cluster = ns.Cluster
    if not Cluster then return nil end
    for _, b in ipairs(Cluster.buttons) do
        if b:GetAttribute("action") == slot then return b end
    end
end

local function UpdatePlus(b)
    if not b.plus then return end
    local slot = b:GetAttribute("action")
    local empty = type(slot) == "number" and not HasAction(slot)
    if b.plusOn ~= empty then
        b.plusOn = empty
        b.plus:SetShown(empty)
    end
end

local function UpdateAllPlus()
    local Cluster = ns.Cluster
    if not Cluster then return end
    for _, b in ipairs(Cluster.buttons) do UpdatePlus(b) end
end

local function OnButtonClick(self, button)
    if button ~= "LeftButton" or ns.InFight() then return end
    local slot = self:GetAttribute("action")
    if type(slot) == "number" and not HasAction(slot) then
        ns.Guard("picker empty tap", Picker.Open, slot)
    end
end

local function OnButtonAttribute(self, name)
    if name == "action" then UpdatePlus(self) end
end

local function SetUpButton(b)
    b.plus = b:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(b.plus, Kit.FONT_TITLE, math.floor(b:GetWidth() * 0.6), "")
    b.plus:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
    b.plus:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.plus:SetText(ns.T("picker.plus"))
    b.plus:Hide()
    b:HookScript("PostClick", OnButtonClick)
    b:HookScript("OnAttributeChanged", OnButtonAttribute)
    UpdatePlus(b)
end

-- ---------------------------------------------------------------------------------------
-- Tabs and the grid

local tabs, tabCount

local function CloseRankMenu()
    rankMenu:Hide()
    Picker.menuCell = nil
end

local function ShowPage(page)
    CloseRankMenu()
    local entries = Picker.entries or {}
    local count = math.max(1, math.ceil(#entries / PER_PAGE))
    page = math.min(math.max(page, 1), count)
    Picker.page, Picker.pageCount = page, count
    for i, cell in ipairs(cells) do
        local e = entries[(page - 1) * PER_PAGE + i]
        cell.entry = e
        if e then
            cell.icon:SetTexture(e.icon)
            cell.label:SetText(e.name)
            cell.dot:SetShown(e.onButton)
            local rank = cell.rankButton
            local shown = PlainText(e.rank) and e.rank ~= "" or (e.rank ~= nil and Secret(e.rank))
            if shown then
                rank.label:SetText(e.rank)
                local choice = e.ranks ~= nil
                rank.arrow:SetShown(choice)
                rank:EnableMouse(choice)
                rank.label:SetTextColor(choice and GOLD[1] or 0.62, choice and GOLD[2] or 0.62, choice and GOLD[3] or 0.62)
                rank:Show()
            else
                rank:Hide()
            end
            cell:Show()
        else
            cell:Hide()
        end
    end
    PaintCells()
    pageText:SetText(page .. "/" .. count)
    pageText:SetShown(count > 1)
    prevButton:SetShown(count > 1)
    nextButton:SetShown(count > 1)
    if page <= 1 then prevButton:Disable() else prevButton:Enable() end
    if page >= count then nextButton:Disable() else nextButton:Enable() end
    noneText:SetShown(#entries == 0)
end

-- Picks rank i of the row in `cell`: the row now stands for that rank's spell id, and is chosen for Put.
local function ChooseRank(cell, i)
    local e = cell and cell.entry
    local r = e and e.ranks and e.ranks[i]
    if not r then return end
    e.rankIndex, e.id, e.base, e.icon, e.rank = i, r.id, r.base, r.icon, r.rank
    e.onButton = IsOnButton(e)
    Picker.selected = e
    ShowPage(Picker.page or 1)
    if RefreshPut then RefreshPut() end
end

local function NewMenuButton(i)
    local b = CreateFrame("Button", nil, rankMenu)
    b:SetSize(MENU_W - 20, MENU_ROW)
    b:SetPoint("TOPLEFT", rankMenu, "TOPLEFT", 10, -(10 + (i - 1) * MENU_ROW))
    b:RegisterForClicks("LeftButtonUp")
    b.label = NewText(b, 17)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.index = i
    b:SetScript("OnClick", function(self) ns.Guard("picker rank choose", function()
        local cell = Picker.menuCell
        CloseRankMenu()
        ChooseRank(cell, self.index)
    end) end)
    b:HookScript("PostClick", function() Kit.Sound("tap") end)
    Kit.AddPress(b, "rect", b, 0)
    return b
end

-- Opens (or closes) the list of ranks under a row's rank control.
function Picker.ToggleRankMenu(cell)
    if Picker.menuCell == cell then CloseRankMenu(); return end
    local e = cell and cell.entry
    if not e or not e.ranks then return end
    CloseRankMenu()
    local n = math.min(#e.ranks, MENU_MAX)
    for i = 1, n do
        local b = rankMenu.buttons[i] or NewMenuButton(i)
        rankMenu.buttons[i] = b
        b.label:SetText(e.ranks[i].rank)
        if i == e.rankIndex then b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else b.label:SetTextColor(1, 1, 1) end
        b:Show()
    end
    for i = n + 1, #rankMenu.buttons do rankMenu.buttons[i]:Hide() end
    rankMenu:SetSize(MENU_W, 20 + n * MENU_ROW)
    local x = GRID_X + (cell.col - 1) * GRID_STEP
    x = math.min(x, SHEET_W - MENU_W - 20)
    rankMenu:ClearAllPoints()
    rankMenu:SetPoint("TOPLEFT", sheet, "TOPLEFT", x, -(GRID_Y - 8))
    Picker.menuCell = cell
    rankMenu:Show()
end

-- Shows every rank as its own row (or one row per spell) and keeps the choice for the account.
function Picker.SetShowAllRanks(on)
    on = on and true or false
    if TouchPlayDB then TouchPlayDB.showAllRanks = on end
    if sheet:IsShown() and Picker.tabPos then ns.Guard("picker ranks", Picker.Reshow) end
end

local function OnChipClick()
    Picker.SetShowAllRanks(not Picker.ShowAllRanks())
end

rankChip:SetScript("OnClick", function() ns.Guard("picker ranks", OnChipClick) end)

local function ShowTab(pos)
    local tab = Picker.tabList[pos]
    if not tab then return end
    Picker.tabPos = pos
    Picker.tab = tab.name
    Picker.selected = nil
    Picker.entries = EntriesFor(tab)
    rankChip:SetShown(not tab.items and not tab.mounts)
    pinButton:SetShown(tab.mounts == true and ns.Interact ~= nil and ns.Interact.PinMount ~= nil)
    rankChip:SetOn(Picker.ShowAllRanks())
    tabs:SetSelected(pos)
    ShowPage(1)
    if RefreshPut then RefreshPut() end
end

-- A swipe (Swipe.lua): the next (+1) or previous (-1) page; past the last or first page, the next or previous tab
-- (only while the tab row is shown: the item column's Items tab stands alone), on its first or last page. Answers
-- whether it turned.
function Picker.Turn(dir)
    if not sheet:IsShown() then return false end
    local page, count = Picker.page or 1, Picker.pageCount or 1
    if dir > 0 and page < count then ShowPage(page + 1); return true end
    if dir < 0 and page > 1 then ShowPage(page - 1); return true end
    local list, pos = Picker.tabList, Picker.tabPos
    if not (tabs and tabs:IsShown() and list and pos) then return false end
    local to = pos + (dir > 0 and 1 or -1)
    if not list[to] then return false end
    ShowTab(to)
    if dir < 0 then ShowPage(Picker.pageCount or 1) end
    return true
end

-- Lists the open tab again (the rank setting changed); the same cell stays chosen when it is still there.
function Picker.Reshow()
    ShowTab(Picker.tabPos)
end

local function RefreshTabs()
    local list = TabList()
    Picker.tabList = list
    -- The schools of a character do not change while the game runs, so the tab row is made once
    -- (and again only if the spellbook gains or loses a school).
    if tabs and tabCount == #list then return end
    if tabs then tabs:Hide() end
    local labels = {}
    for i, t in ipairs(list) do
        labels[i] = t.items and ns.T("picker.items") or t.mounts and ns.T("picker.mounts") or t.name
    end
    tabs = Kit.Tabs(sheet, labels)
    tabs:SetPoint("TOPLEFT", sheet, "TOPLEFT", TABS_X, -TABS_Y)
    tabs:SetOnSelect(function(pos) ns.Guard("picker tab", ShowTab, pos) end)
    tabCount = #list
    Picker.tabs = tabs
end

-- The tab to open on: the school of the spell in the slot, Items for an item, else the first.
local function HomeTab(slot)
    local list = Picker.tabList
    local kind, id = GetActionInfo(slot)
    if kind == "item" then return #list end
    if kind == "summonmount" then
        for pos, t in ipairs(list) do
            if t.mounts then return pos end
        end
    end
    local book = C_SpellBook
    if kind == "spell" and type(id) == "number" and not Secret(id)
        and book and book.FindSpellBookSlotForSpell and book.GetSpellBookItemInfo then
        local at, bank = book.FindSpellBookSlotForSpell(id, true)
        local item = at and book.GetSpellBookItemInfo(at, bank)
        local line = item and item.skillLineIndex
        if line then
            for pos, t in ipairs(list) do
                if t.line == line then return pos end
            end
        end
    end
    return 1
end

-- ---------------------------------------------------------------------------------------
-- Put on button: greyed in a fight, with the reason

-- Pressed while greyed with nothing chosen (polish pass): the button says what to do, next to it, for a moment.
putButton.touchRefused = function()
    if Picker.selected == nil then return ns.T("picker.chooseFirst") end
end
pinButton.touchRefused = function()
    local e = Picker.selected
    if e == nil or e.kind ~= "mount" then return ns.T("picker.chooseMount") end
end

function RefreshPut()
    local fight = ns.InFight() and not Picker.rail        -- pinning is only a saved choice: fine in a fight
    local ready = Picker.selected ~= nil and not fight
    putButton:SetEnabledWithReason(ready, fight and ns.T("card.afterFight") or nil)
    pinButton:SetEnabledWithReason(ready and Picker.selected.kind == "mount", nil)
end

local function ShowRingOn(b)
    if not b then ring:Hide(); ring.pulse:Stop(); return end
    LayoutRing(b:GetWidth() * b:GetScale() + 10)       -- the button may be scaled by Button size
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    ring:Show()
    -- reduce motion: the ring stays lit and steady
    if ns.ReduceMotion() then ring.pulse:Stop() else ring.pulse:Play() end
end

local function ShowRing(slot) ShowRingOn(ButtonFor(slot)) end

local flashTimer
local FLASH_STILL_SECONDS = 1.6

local function ShowFlashOn(b, entry)
    if not b then return end
    local name = entry.name
    if name == nil then
        if entry.kind == "item" then
            name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id)
        elseif entry.kind == "mount" then
            name = nil
        else
            name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.id)
        end
    end
    local scale = b:GetScale()
    flash:SetSize(b:GetWidth() * scale, b:GetHeight() * scale)
    flash.glow:SetSize(b:GetWidth() * scale * 1.7, b:GetHeight() * scale * 1.7)
    -- "Scorch, Rank 3": joined only when both are plain text (a hidden name goes to SetText on its own)
    if PlainText(name) and PlainText(entry.rank) and entry.rank ~= "" then name = name .. ", " .. entry.rank end
    flash.label:SetText(name or "")
    flash:ClearAllPoints()
    flash:SetPoint("CENTER", b, "CENTER", 0, 0)
    flash:Show()
    flash.group:Stop()
    if flashTimer then flashTimer:Cancel(); flashTimer = nil end
    if ns.ReduceMotion() then
        -- reduce motion: the name shows without the glow or the fade, and goes away by itself
        flash.glow:Hide()
        flashTimer = C_Timer.NewTimer(FLASH_STILL_SECONDS, function() flashTimer = nil; flash:Hide() end)
    else
        flash.glow:Show()
        flash.group:Play()
    end
end

local function ShowFlash(slot, entry, onFrame) ShowFlashOn(onFrame or ButtonFor(slot), entry) end
-- The same flash on any button (the item column's drop, ItemRail.Drop).
Picker.Flash = ShowFlashOn

-- ---------------------------------------------------------------------------------------
-- The public steps

-- Reduce motion changed: an open ring turns steady, or pulses again.
function Picker.SyncMotion()
    if not ring:IsShown() then return end
    if ns.ReduceMotion() then ring.pulse:Stop() else ring.pulse:Play() end
end

function Picker.Close()
    local was = sheet:IsShown()
    sheet:Hide()
    CloseRankMenu()
    dim:Hide()
    ring.pulse:Stop()
    ring:Hide()
    Picker.slot, Picker.selected, Picker.rail = nil, nil, nil
    if was then Kit.Sound("close") end
end

Picker.Cancel = Picker.Close

-- The sheet's words for a spell button or for a slot of the item column.
local function SetMode(rail)
    title:SetLabel(rail and ns.T("picker.itemTitle") or ns.T("picker.title"))
    putButton.label:SetText(rail and ns.T("picker.pin") or ns.T("picker.put"))
    legend:SetText(rail and ns.T("picker.legendRail") or ns.T("picker.legend"))
    if tabs then tabs:SetShown(not rail) end
end

function Picker.Open(slot)
    if type(slot) ~= "number" then return end
    Picker.slot, Picker.rail = slot, nil
    Picker.selected = nil
    RefreshTabs()
    SetMode(false)
    ShowTab(HomeTab(slot))
    dim:Show()
    local was = sheet:IsShown()
    sheet:Show()
    ShowRing(slot)
    RefreshPut()
    if not was then Kit.Sound("open") end
end

-- The sheet for slot `index` (1 to 4) of the item column, on the Items tab.
function Picker.OpenItem(index)
    local rail = ns.ItemRail
    local button = rail and rail.buttons[index]
    if not button then return end
    Picker.slot, Picker.rail = nil, index
    Picker.selected = nil
    RefreshTabs()
    SetMode(true)
    ShowTab(#Picker.tabList)                  -- the Items tab is the last
    dim:Show()
    local was = sheet:IsShown()
    sheet:Show()
    ShowRingOn(button)
    RefreshPut()
    if not was then Kit.Sound("open") end
end

-- The journal's display position of a mount, found by its id when the player taps Put: the list may have
-- changed since the tab was drawn. Only called from Picker.Put, so only from a tap.
local function MountDisplayIndex(mountID)
    local journal = C_MountJournal
    if not journal or not journal.GetNumDisplayedMounts or not journal.GetDisplayedMountID then return nil end
    for i = 1, journal.GetNumDisplayedMounts() or 0 do
        if journal.GetDisplayedMountID(i) == mountID then return i end
    end
end

-- Puts entry ({ kind = "spell"|"item"|"mount", id = }) on the button at `slot`. Returns true when the
-- game took it. Never in a fight: the game blocks it, so nothing is called.
function Picker.Put(slot, entry)
    if InCombatLockdown() then return false end
    if type(slot) ~= "number" or type(entry) ~= "table" then return false end
    if GetCursorInfo() ~= nil then ClearCursor() end      -- a stale cursor would be placed instead
    if entry.kind == "item" then
        (C_Item and C_Item.PickupItem or PickupItem)(entry.id)
    elseif entry.kind == "mount" then
        -- index 0 is the journal's own "Summon Random Favorite Mount" button
        local index = entry.random and 0 or MountDisplayIndex(entry.id)
        if index and C_MountJournal and C_MountJournal.Pickup then C_MountJournal.Pickup(index) end
    else
        (C_Spell and C_Spell.PickupSpell or PickupSpell)(entry.id)
    end
    local placed = false
    if GetCursorInfo() ~= nil then            -- placing with an empty cursor would do the wrong thing
        PlaceAction(slot)
        placed = true
    end
    ClearCursor()
    if placed then
        UpdateAllPlus()
        ShowFlash(slot, entry)
    end
    return placed
end

-- Empties the button at `slot`. Never in a fight.
function Picker.Remove(slot)
    if InCombatLockdown() then return false end
    if type(slot) ~= "number" then return false end
    if GetCursorInfo() ~= nil then ClearCursor() end
    PickupAction(slot)
    ClearCursor()
    UpdateAllPlus()
    return true
end

local function OnPutClick()
    if Picker.rail and Picker.selected then
        -- pinning changes nothing the game protects (the column's buttons follow after a fight), so it works in one
        local index, entry = Picker.rail, Picker.selected
        ns.ItemRail.Pin(index, entry.id)
        ShowFlashOn(ns.ItemRail.buttons[index], entry)
        Picker.Close()
        return
    end
    if not Picker.slot or not Picker.selected then return end
    if Picker.Put(Picker.slot, Picker.selected) then Picker.Close() end
end

-- Pins a mount entry to the Mount ring: the random favourite (entry.random) or that mount. Never in a fight (the
-- ring's macro is protected). Returns true when pinned.
function Picker.PinMount(entry)
    if InCombatLockdown() or type(entry) ~= "table" or entry.kind ~= "mount" then return false end
    local Interact = ns.Interact
    if not Interact or not Interact.PinMount then return false end
    Interact.PinMount(not entry.random and entry.id or nil)
    if Interact.dive then ShowFlash(nil, entry, Interact.dive) end
    return true
end

local function OnPinClick()
    if not Picker.selected then return end
    if Picker.PinMount(Picker.selected) then Picker.Close() end
end
pinButton:SetScript("OnClick", function() ns.Guard("picker pin mount", OnPinClick) end)

putButton:SetScript("OnClick", function() ns.Guard("picker put", OnPutClick) end)
cancelButton:SetScript("OnClick", function() ns.Guard("picker cancel", Picker.Close) end)
prevButton:SetScript("OnClick", function() ns.Guard("picker page", ShowPage, (Picker.page or 1) - 1) end)
nextButton:SetScript("OnClick", function() ns.Guard("picker page", ShowPage, (Picker.page or 1) + 1) end)

-- ---------------------------------------------------------------------------------------
-- Module steps

local function OnSlotsChanged()
    UpdateAllPlus()
    if sheet:IsShown() and Picker.entries then
        ScanButtons()
        for _, e in ipairs(Picker.entries) do
            if Picker.rail then e.onButton = ns.ItemRail.PinnedSlot(e.id) ~= nil else e.onButton = IsOnButton(e) end
        end
        ShowPage(Picker.page or 1)
    end
end

function Picker:Init()
    local Cluster = ns.Cluster
    if Cluster then
        for _, b in ipairs(Cluster.buttons) do SetUpButton(b) end
    end
    ns.On("ACTIONBAR_SLOT_CHANGED", OnSlotsChanged)
    ns.On("ACTIONBAR_PAGE_CHANGED", UpdateAllPlus)
    ns.On("PLAYER_ENTERING_WORLD", UpdateAllPlus)
    ns.On("PLAYER_REGEN_DISABLED", RefreshPut)
    ns.On("PLAYER_REGEN_ENABLED", RefreshPut)
end

function Picker:Layout()
    ns.Anchor(sheet, "BL", SHEET_X, SHEET_Y, "side")
    UpdateAllPlus()
end

function Picker:Restore()
    Picker.Close()
end
