-- TouchPlay: the item column (rule 6): four secure item buttons on the right edge that fill
-- themselves with your best food, drink, healing potion and mana potion (a mana gem also counts as a mana
-- potion, for the game versions that have them).
--
-- Each category takes the usable item (required level at or under yours) with the highest required
-- level, then the highest stack. A pinned item keeps its slot, grey with 0 when none is left. An item
-- that runs out leaves its slot empty (dashed, with a +) until something new arrives.
--
-- What is food, drink, a healing potion or a mana potion comes from the game's own item data: class
-- Consumable, subclass Food & Drink (the use spell's name tells food from drink) or Potion (the use spell's or
-- the item's name tells healing from mana). Items whose data has not arrived yet are asked again when
-- GET_ITEM_INFO_RECEIVED comes.
--
-- Filling a slot by hand (iPad run 4: the player could not tell how): tap or hold an empty slot, and its card
-- says so and offers "Change item", which opens the picker's Items tab for that slot; hold a filled slot for
-- Change item and Pin / Unpin; hold any bag item for Pin. A pin keeps one item in its slot (any item that
-- has a use), grey with 0 when none is left.
--
-- Secure attributes (*type1, item) change only out of combat, through ns.Queue, so a better item found
-- in a fight lands when the fight ends. Counts, cooldowns and the grey 0 are plain textures and text,
-- so they stay current in a fight. A tap uses the item; a hold (the right click) opens its info card
-- and never uses it.
--
-- After a fight, when health or mana is under 50%, food and drink glow; in a fight the healing potion glows under
-- 25% health and the mana potion under 25% mana. The comparison is made by a step curve the game evaluates
-- (UnitHealthPercent / UnitPowerPercent take it, R43); the answer only ever becomes an alpha.
-- Nothing here is used for you: every use is a tap.

local ADDON_NAME, ns = ...

local ItemRail = ns.Register("ItemRail", {})

ns.L["items.pin"] = "Pin"
ns.L["items.unpin"] = "Unpin"
ns.L["items.change"] = "Change item"
ns.L["items.plus"] = "+"
ns.L["items.slot.food"] = "Food slot"
ns.L["items.slot.drink"] = "Drink slot"
ns.L["items.slot.health"] = "Healing potion slot"
ns.L["items.slot.mana"] = "Mana potion slot"
ns.L["items.empty"] = "Nothing in your bags for this slot."
ns.L["items.fill.food"] = "Carry food and it fills in by itself, or pin an item: tap Change item."
ns.L["items.fill.drink"] = "Carry drink and it fills in by itself, or pin an item: tap Change item."
ns.L["items.fill.health"] = "Carry healing potions and it fills in by itself, or pin an item: tap Change item."
ns.L["items.fill.mana"] = "Carry mana potions and it fills in by itself, or pin an item: tap Change item."
ns.L["items.dropNo"] = "Only food, drink, potions and items you can use go here."

-- Mockup numbers (layout units, 1366 x 1024): 48 x 48 at x 1300, y 300 + 66 * i.
local SIZE, X, Y0, STEP = 48, 1300, 300, 66
local CORNER = "TR"                   -- the corner the contract counts the item areas from
-- The column is placed from the bottom-right corner, so Button size scales it with the spell cluster and it keeps
-- its place above the page boxes (I5). When large buttons would take it into the minimap's touch area (which ends
-- at y 220: the disc is centred at y 134, 172 across), the four sit in a row just over the page boxes instead,
-- right-aligned with them (page box 4 ends at x 1342, the row is at y 566), with the column's 20-unit gap.
local MAP_BOTTOM, MAP_GAP = 220, 4
local PAGE_RIGHT, PAGE_TOP, ROW_GAP = 1342, 566, 20
local FRAME_ART = "Interface\\Buttons\\UI-Quickslot2"
local FRAME_RATIO = 1.68              -- the Quickslot frame is 1.68 x the icon
local PIN_ART = "Interface\\Buttons\\UI-CheckBox-Check"
local LOW_PERCENT = 50

-- The slots, top to bottom.
local CATS = { "food", "drink", "health", "mana" }
local INDEX = { food = 1, drink = 2, health = 3, mana = 4 }
ItemRail.CATS = CATS

-- The mana gems of the game (the game gives them no class of their own): Agate, Jade, Citrine, Ruby, Emerald.
-- They fill the mana slot, as a mana potion does.
local GEMS = { [5514] = true, [5513] = true, [8007] = true, [8008] = true, [22044] = true }
-- The spells the game's food and drink use: Food (433) and Drink (430).
local FOOD_SPELL, DRINK_SPELL = 433, 430
local CLASS_CONSUMABLE, SUB_POTION, SUB_FOOD_DRINK = 0, 1, 5

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- ---------------------------------------------------------------------------------------
-- Choosing (pure)

local best = {}                       -- scratch: the best entry so far, per category

-- Is a better than b: the higher required level, then the higher stack, then the lower id.
local function Better(a, b)
    local ar, br = a.req or 0, b.req or 0
    if ar ~= br then return ar > br end
    local ac, bc = a.count or 0, b.count or 0
    if ac ~= bc then return ac > bc end
    return a.id < b.id
end

-- bagItems: a list of { id =, cat =, req =, count = }; pins: { food = id, ... }.
-- Returns { food =, drink =, health =, mana = } (an item id, or nil for an empty slot). `out` may be
-- passed to reuse a table.
function ItemRail.Choose(bagItems, playerLevel, pins, out)
    out = out or {}
    for _, cat in ipairs(CATS) do best[cat] = nil end
    for _, item in ipairs(bagItems) do
        local cat = item.cat
        if INDEX[cat] and (item.count or 0) > 0 and (item.req or 0) <= (playerLevel or 0) then
            local current = best[cat]
            if not current or Better(item, current) then best[cat] = item end
        end
    end
    for _, cat in ipairs(CATS) do
        local pinned = pins and pins[cat]
        if pinned then
            out[cat] = pinned
        else
            out[cat] = best[cat] and best[cat].id or nil
        end
        best[cat] = nil
    end
    return out
end

-- ---------------------------------------------------------------------------------------
-- What an item is (from the game's own item data, remembered once known)

local known = {}                      -- item id -> { cat =, req = }, or false for "not ours"
local pending = false                 -- some item's data had not arrived yet

local function Lower(value)
    if type(value) ~= "string" or Secret(value) then return "" end
    return value:lower()
end

-- Food or drink from the item's use spell: Drink (430) and Food (433) by id and by the name the game gives them
-- (so another language still works), then by the words the game's other food and drink spells use ("Refreshment",
-- "Food & Drink"). Anything else that restores is food. nil while the item's use spell is not known yet (an item
-- with no use cannot be eaten from the column anyway).
local function SpellCategory(id)
    local spellName, spellID = C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    if spellID == DRINK_SPELL then return "drink" end
    if spellID == FOOD_SPELL then return "food" end
    if type(spellName) ~= "string" or Secret(spellName) then return nil end
    if spellName == C_Spell.GetSpellName(DRINK_SPELL) then return "drink" end
    if spellName == C_Spell.GetSpellName(FOOD_SPELL) then return "food" end
    local text = spellName:lower()
    if text:find("drink", 1, true) or text:find("refresh", 1, true) then return "drink" end
    return "food"
end

-- Healing or mana potion from the use spell's name ("Healing Potion", "Mana Potion") or the item's own name
-- ("Greater Healing Potion"); anything else (an elixir-like potion, a resistance potion) is not ours.
local function PotionCategory(id, itemName)
    local spellName = C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    local text = Lower(spellName) .. " " .. Lower(itemName)
    if text:find("heal", 1, true) then return "health" end
    if text:find("mana", 1, true) then return "mana" end
end

-- { cat =, req = } for a food, drink, healing or mana potion; false for anything else; nil when the game
-- has not told us yet (asked again later).
local function Classify(id)
    local hit = known[id]
    if hit ~= nil then return hit end
    local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(id)
    if not class then pending = true; return nil end
    local cat, itemName, minLevel
    if GEMS[id] then
        cat = "mana"
    elseif class == CLASS_CONSUMABLE and (sub == SUB_POTION or sub == SUB_FOOD_DRINK) then
        itemName, _, _, _, minLevel = C_Item.GetItemInfo(id)     -- only for the kinds we may want
        if sub == SUB_POTION then
            cat = PotionCategory(id, itemName)
            if not cat and type(itemName) ~= "string" then pending = true; return nil end
        else
            cat = SpellCategory(id)
            if not cat then pending = true; return nil end
        end
    end
    if not cat then known[id] = false; return false end
    if GEMS[id] then minLevel = select(5, C_Item.GetItemInfo(id)) end
    if type(minLevel) ~= "number" then pending = true; return nil end
    known[id] = { cat = cat, req = minLevel }
    return known[id]
end
ItemRail.Classify = Classify

-- ---------------------------------------------------------------------------------------
-- Pins (TouchPlayCharDB.pins: { food = id, drink = id, health = id, mana = id })

local function Pins()
    local char = ns.char
    if not char then return nil end
    if type(char.pins) ~= "table" then char.pins = {} end
    local pins = char.pins
    -- the slots were food, drink, gem and potion before iPad run 4: a pinned gem is the mana slot's pin now, a
    -- pinned potion could have been either kind, so it goes back to filling itself
    if pins.gem ~= nil or pins.potion ~= nil then
        if pins.mana == nil then pins.mana = pins.gem end
        pins.gem, pins.potion = nil, nil
    end
    return pins
end

local Sync                            -- defined below

function ItemRail.Pin(slotIndex, itemID)
    local cat, pins = CATS[slotIndex], Pins()
    if not cat or not pins or type(itemID) ~= "number" then return end
    pins[cat] = itemID
    Sync()
end

function ItemRail.Unpin(slotIndex)
    local cat, pins = CATS[slotIndex], Pins()
    if not cat or not pins then return end
    pins[cat] = nil
    Sync()
end

-- The slot an item is pinned to, or nil (the picker's green dot).
function ItemRail.PinnedSlot(itemID)
    local pins = Pins()
    if not pins or type(itemID) ~= "number" then return nil end
    for index, cat in ipairs(CATS) do
        if pins[cat] == itemID then return index end
    end
end

-- What the card for an empty or filled slot says: the slot's category, its name and how to fill it.
function ItemRail.SlotCategory(slotIndex) return CATS[slotIndex] end

function ItemRail.IsPinned(slotIndex)
    local pins = Pins()
    local b = ItemRail.buttons[slotIndex]
    return pins ~= nil and b ~= nil and b.itemID ~= nil and pins[CATS[slotIndex]] == b.itemID
end

-- ---------------------------------------------------------------------------------------
-- The buttons

ItemRail.buttons = {}
local buttons = ItemRail.buttons

local function DashedEdge(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:EnableMouse(false)
    local function dash(x, y, w, h)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 0.3)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    end
    for p = 0, SIZE - 1, 10 do
        local len = math.min(6, SIZE - p)
        dash(p, 0, len, 2)
        dash(p, SIZE - 2, len, 2)
        dash(0, p, 2, len)
        dash(SIZE - 2, p, 2, len)
    end
    return f
end

-- A gold ring around the button, outset 18% of its size, whose alpha the low-health or low-mana
-- curve decides.
local function GlowRing(button)
    local ring = ns.Kit.Backdrop(button, "tooltip", "tooltip")
    local outset = SIZE * 0.18
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", -outset, outset)
    ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", outset, -outset)
    ring:SetBackdropColor(0, 0, 0, 0)
    ring:SetBackdropBorderColor(1, 0.88, 0.4, 1)
    ring:EnableMouse(false)
    ring:SetFrameLevel(button:GetFrameLevel() + 3)
    ring:SetAlpha(0)
    return ring
end

-- The pinned mark: a gold-bordered chip with the game's gold check, at the top right.
local function PinMark(button)
    local mark = ns.Kit.Backdrop(button, "tooltip", "tooltip")
    mark:SetSize(22, 22)
    mark:SetPoint("TOPLEFT", button, "TOPLEFT", 30, 8)
    mark:SetBackdropBorderColor(1, 0.82, 0, 1)
    mark:EnableMouse(false)
    mark:SetFrameLevel(button:GetFrameLevel() + 6)
    local check = mark:CreateTexture(nil, "OVERLAY")
    check:SetTexture(PIN_ART)
    check:SetPoint("TOPLEFT", mark, "TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -2, 2)
    mark:Hide()
    return mark
end

-- A hold asks the info card about the stack the button shows; it never uses the item. An empty slot has nothing
-- to use: a tap or a hold on it opens the card that says how to fill it (iPad run 4).
local function OnPostClick(self, button)
    if self.dropping then return end            -- a tap that drops an item (ItemRail.AfterClick): nothing else
    local id = self.itemID
    if not (button == "RightButton" or (button == "LeftButton" and not id)) then return end
    ns.Guard("itemrail hold", function()
        if not ns.InfoCard then return end
        local subject
        if not id then
            subject = { kind = "railSlot", rail = self.index }
        elseif self.bag and self.slot then
            subject = { kind = "item", bag = self.bag, slot = self.slot, rail = self.index }
        else
            subject = { kind = "item", link = "item:" .. id, rail = self.index }
        end
        ns.InfoCard.Show(subject, self)
    end)
end

-- A tap on a slot with an item on the cursor (iPad run 7): a drag let go somewhere else leaves the item there, and the
-- game's own slots place it on a click too. Out of a fight the slot's secure item is taken off for that one click
-- (PreClick), so the click uses nothing, and the item is dropped (PostClick: ItemRail.Drop pins it and the slot's item
-- follows). In a fight the secure attributes cannot change: the click does what it always does and the drop waits.
function ItemRail.BeforeClick(self, button)
    if button ~= "LeftButton" or InCombatLockdown() then return end
    local kind = GetCursorInfo()
    if kind ~= "item" then return end
    self.dropping, self.typeBeforeDrop = true, self:GetAttribute("*type1")
    self:SetAttribute("*type1", nil)
end

function ItemRail.AfterClick(self)
    if not self.dropping then return end
    -- the slot's own action back first; the pin then changes it (Update) when the item changed
    if not InCombatLockdown() then self:SetAttribute("*type1", self.typeBeforeDrop) end
    self.dropping, self.typeBeforeDrop = nil, nil
    ns.Guard("itemrail click drop", ItemRail.Drop, self.index, "click")
end

local function NewButton(i)
    local b = CreateFrame("Button", "TouchPlayItem" .. i, ns.root, "SecureActionButtonTemplate")
    b.index = i
    b:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    -- Only a left click uses the item (*type1: with any keys held, as the app sends them); a right click, the
    -- hold, has nothing to do.
    b:SetAttribute("type", nil)
    b:SetAttribute("type2", nil)

    -- the game's Quickslot frame over the icon, 1.68 x the icon, centred
    b:SetNormalTexture(FRAME_ART)
    local frame = b:GetNormalTexture()
    local off = (math.floor(SIZE * FRAME_RATIO + 0.5) - SIZE) / 2
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", b, "TOPLEFT", -off, off)
    frame:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", off, -off)
    b.frameArt = frame

    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.cooldown = CreateFrame("Cooldown", "TouchPlayItem" .. i .. "Cooldown", b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b)

    b.count = b:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(b.count, ns.Kit.FONT_NUMBER, 13, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 1)

    b.empty = DashedEdge(b)
    -- an empty slot invites a tap: a gold +, as the spell buttons show
    b.plus = b:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(b.plus, ns.Kit.FONT_TITLE, 30, "")
    b.plus:SetTextColor(1, 0.82, 0, 0.85)
    b.plus:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.plus:SetText(ns.T("items.plus"))
    b.plus:Hide()
    b.pin = PinMark(b)
    -- Rings (mockups 32, 19, 75): food and drink light after a fight when health or mana is low; in a
    -- fight the healing potion lights at low health and the mana potion at low mana.
    if i <= 2 then
        b.healthGlow, b.manaGlow = GlowRing(b), GlowRing(b)
    elseif i == INDEX.mana then
        b.manaGlow = GlowRing(b)
    elseif i == INDEX.health then
        b.healthGlow = GlowRing(b)
    end

    b:RegisterForDrag("LeftButton")         -- a drop target, as the game's own slots are (iPad run 7)
    b:HookScript("PreClick", ItemRail.BeforeClick)
    b:HookScript("OnMouseDown", function() if b.itemID then b.icon:SetAlpha(0.7) end end)
    b:HookScript("OnMouseUp", function() ItemRail.Paint(i) end)
    ns.Kit.AddPress(b, "square")            -- pressed: the pale-gold edge, as the spell buttons (mockup 10)
    b:HookScript("PostClick", function(self, button)
        if button == "LeftButton" and self.itemID then ns.Kit.Sound("tap") end
    end)
    b:HookScript("PostClick", OnPostClick)
    b:HookScript("PostClick", ItemRail.AfterClick)
    -- an item dragged from the bags (or the picker) and let go on the slot pins it there (ItemRail.Drop)
    b:HookScript("OnReceiveDrag", function(self) ns.Guard("itemrail drop", ItemRail.Drop, self.index, "OnReceiveDrag") end)
    return b
end
for i = 1, #CATS do buttons[i] = NewButton(i) end

local function Place()
    for i, b in ipairs(buttons) do ns.Anchor(b, "BR", X, Y0 + (i - 1) * STEP, true) end
    if buttons[1].touchAnchor.y >= MAP_BOTTOM + MAP_GAP then return end
    local n = #buttons
    for i, b in ipairs(buttons) do
        ns.Anchor(b, "BR", PAGE_RIGHT - SIZE - (n - i) * STEP, PAGE_TOP - ROW_GAP - SIZE, true)
    end
end
Place()

-- ---------------------------------------------------------------------------------------
-- Painting: textures and text only, so it is safe in a fight

local function Paint(i)
    local b = buttons[i]
    local id = b.itemID
    if not id then
        b.icon:Hide()
        b.frameArt:SetAlpha(0)
        b.count:SetText("")
        b.empty:Show()
        b.plus:Show()
        b.pin:Hide()
        b.cooldown:Clear()
        return
    end
    local pinned = ItemRail.IsPinned(i)
    local count = C_Item.GetItemCount(id) or 0
    local gone = count <= 0
    b.empty:Hide()
    b.plus:Hide()
    b.frameArt:SetAlpha(1)
    b.icon:Show()
    b.icon:SetTexture(C_Item.GetItemIconByID(id))
    b.icon:SetDesaturated(gone)
    if gone then b.icon:SetVertexColor(0.5, 0.5, 0.5) else b.icon:SetVertexColor(1, 1, 1) end
    b.icon:SetAlpha(gone and 0.6 or 1)
    b.count:SetText(tostring(count))
    b.pin:SetShown(pinned)
    -- the cooldown values go straight to the sweep; a hidden one is refused from add-on code, so it is skipped
    local start, duration = C_Item.GetItemCooldown(id)
    if ns.Plain(start) and ns.Plain(duration) then b.cooldown:SetCooldown(start, duration) end
end

ItemRail.Paint = Paint
local function PaintAll() for i = 1, #buttons do Paint(i) end end

-- ---------------------------------------------------------------------------------------
-- Scanning the bags and filling the buttons

local stacks, byId, chosen = {}, {}, {}

local function Scan()
    for id in pairs(byId) do byId[id] = nil end
    local n = 0
    local container = C_Container
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, container.GetContainerNumSlots(bag) or 0 do
            local info = container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" and not Secret(id) then
                local entry = byId[id]
                if entry then
                    entry.count = entry.count + (info.stackCount or 1)
                elseif entry == nil then
                    local kind = Classify(id)
                    if kind then
                        n = n + 1
                        entry = stacks[n] or {}
                        stacks[n] = entry
                        entry.id, entry.cat, entry.req = id, kind.cat, kind.req
                        entry.count, entry.bag, entry.slot = info.stackCount or 1, bag, slot
                        byId[id] = entry
                    else
                        byId[id] = false
                    end
                end
            end
        end
    end
    for i = n + 1, #stacks do stacks[i] = nil end
end

-- Out of combat only (through ns.Queue): scan, choose, set the secure attributes, paint.
local function Update()
    pending = false
    Scan()
    ItemRail.Choose(stacks, UnitLevel("player"), Pins(), chosen)
    for i, cat in ipairs(CATS) do
        local b, id = buttons[i], chosen[cat]
        if b.itemID ~= id then
            b.itemID = id
            if id then
                b:SetAttribute("*type1", "item")
                b:SetAttribute("item", "item:" .. id)
            else
                b:SetAttribute("*type1", nil)
                b:SetAttribute("item", nil)
            end
        end
        local entry = id and byId[id]
        if entry then b.bag, b.slot = entry.bag, entry.slot else b.bag, b.slot = nil, nil end
    end
    PaintAll()
end

-- In a fight the counts, the grey 0 and the cooldowns still follow the bags; the buttons themselves
-- change when the fight ends.
function Sync()
    if InCombatLockdown() then PaintAll() end
    ns.Queue("itemrail", Update)
end

local function UpdateCooldowns()
    for i, b in ipairs(buttons) do
        if b.itemID then
            local start, duration = C_Item.GetItemCooldown(b.itemID)
            if ns.Plain(start) and ns.Plain(duration) then b.cooldown:SetCooldown(start, duration) end
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- The glow after a fight

-- Step curves: 1 under the percentage, 0 from it up (the game's percentages run 0 to 1). The game evaluates
-- the curve on the (possibly hidden) percentage and the answer goes straight into SetAlpha; nothing compares it.
local curves = {}
local function LowCurve(percent)
    local curve = curves[percent]
    if curve == nil then
        curve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Step)
            curve:AddPoint(0, 1)
            curve:AddPoint(percent / 100, 0)
        end
        curves[percent] = curve
    end
    return curve
end

local MANA = 0
local CALM_PERCENT, FIGHT_PERCENT = 50, 25

-- Out of a fight (alive): food and drink glow under 50% health or mana. In a fight: the mana potion glows
-- under 25% mana and the healing potion under 25% health (the player card's low-health line).
-- Hoisted: this runs on every health and power event, and a closure made here would be garbage each time.
local function HealthGlow(curve) return UnitHealthPercent("player", true, curve) end
local function PowerGlow(curve) return UnitPowerPercent("player", MANA, false, curve) end

local function UpdateGlow()
    local calm, urgent = LowCurve(CALM_PERCENT), LowCurve(FIGHT_PERCENT)
    local off = not calm or not urgent or UnitIsDeadOrGhost("player")
    local fight = ns.InFight()
    local mana = UnitPowerType("player") == MANA
    -- an empty slot has nothing to use: it never glows
    for i = 1, 2 do
        local b = buttons[i]
        local empty = not b.itemID
        b.healthGlow:SetAlpha((off or fight or empty) and 0 or HealthGlow(calm))
        b.manaGlow:SetAlpha((off or fight or empty or not mana) and 0 or PowerGlow(calm))
    end
    local manaSlot, healthSlot = buttons[INDEX.mana], buttons[INDEX.health]
    manaSlot.manaGlow:SetAlpha((off or not fight or not mana or not manaSlot.itemID) and 0 or PowerGlow(urgent))
    healthSlot.healthGlow:SetAlpha((off or not fight or not healthSlot.itemID) and 0 or HealthGlow(urgent))
end

local unitEvents = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    pcall(unitEvents.RegisterUnitEvent, unitEvents, event, "player")
end
unitEvents:SetScript("OnEvent", function()
    if ns.IsActive() then ns.Guard("itemrail glow", UpdateGlow) end
end)

-- ---------------------------------------------------------------------------------------
-- Events

ns.On("BAG_UPDATE_DELAYED", Sync)
ns.On("PLAYER_ENTERING_WORLD", Sync)
ns.On("PLAYER_LEVEL_UP", Sync)
ns.On("GET_ITEM_INFO_RECEIVED", function() if pending then Sync() end end)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("PLAYER_REGEN_DISABLED", UpdateGlow)
ns.On("PLAYER_REGEN_ENABLED", UpdateGlow)
ns.On("PLAYER_UPDATE_RESTING", UpdateGlow)
ns.On("PLAYER_DEAD", UpdateGlow)
ns.On("PLAYER_ALIVE", UpdateGlow)
ns.On("PLAYER_UNGHOST", UpdateGlow)

-- ---------------------------------------------------------------------------------------
-- Drop an item on a slot (iPad run 5)
--
-- While a window is open the app sends a drag as a real mouse drag (ruling A33): the bags pick the item up (the game's
-- OnDragStart) and letting go over a slot is the slot's OnReceiveDrag. An item that can be used from the column (food,
-- drink, a potion, anything with a use) is pinned to that slot, as Change item -> Pin to slot does (the slot's secure
-- item follows out of a fight, as every pin does), the cursor is emptied (ClearCursor puts the item back in its bag
-- place) and the slot flashes the item's name. Anything else: the cursor is emptied the same way, the slot shakes
-- (still under Reduce motion) and a short line says why. The slot's own click is not touched: OnReceiveDrag is
-- hooked, never set.

local note = ns.root:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(note, ns.Kit.FONT_TITLE, 15, "")
note:SetTextColor(1, 0.82, 0)
note:SetJustifyH("RIGHT")
note:Hide()
ItemRail.note = note
local noteTimer
local NOTE_SECONDS = 2.5

local function Shake(b)
    if ns.ReduceMotion and ns.ReduceMotion() then return end
    for _, region in ipairs({ b.icon, b.frameArt }) do
        if region and region.CreateAnimationGroup then
            region.shake = region.shake or (function()
                local group = region:CreateAnimationGroup()
                for i, dx in ipairs({ -6, 12, -12, 6 }) do
                    local move = group:CreateAnimation("Translation")
                    move:SetOffset(dx, 0)
                    move:SetDuration(0.05)
                    move:SetOrder(i)
                end
                return group
            end)()
            region.shake:Stop()
            region.shake:Play()
        end
    end
end

local function Refuse(b)
    Shake(b)
    ns.Kit.Sound("error")
    note:SetText(ns.T("items.dropNo"))
    note:ClearAllPoints()
    note:SetPoint("RIGHT", b, "LEFT", -10, 0)
    note:Show()
    if noteTimer then noteTimer:Cancel() end
    noteTimer = C_Timer.NewTimer(NOTE_SECONDS, function() noteTimer = nil; note:Hide() end)
end

-- Whether an item can be used from the column: one of its kinds, or any item with a use.
local function Usable(id)
    if Classify(id) then return true end
    local spell = C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    return spell ~= nil
end

-- An item on the cursor let go on slot `index`: pinned there, or refused. Answers whether it was an item.
local function Log(b, via, kind, id, result)
    if not (ns.Keylog and ns.Keylog.Drop) then return end
    local cursor = kind and (tostring(kind) .. ":" .. (Secret(id) and "?" or tostring(id))) or "-"
    ns.Keylog.Drop(b, via or "?", cursor, result)
end

function ItemRail.Drop(index, via)
    local b = buttons[index]
    local kind, id = GetCursorInfo()
    if not b then return false end
    if kind ~= "item" then
        Log(b, via, kind, id, "none")
        return false
    end
    if type(id) ~= "number" or Secret(id) or not Usable(id) then
        Log(b, via, kind, id, "refused")
        ClearCursor()
        Refuse(b)
        return true
    end
    Log(b, via, kind, id, "pinned")
    ItemRail.Pin(index, id)
    ClearCursor()
    if noteTimer then noteTimer:Cancel(); noteTimer = nil end
    note:Hide()
    if ns.Picker and ns.Picker.Flash then ns.Picker.Flash(b, { kind = "item", id = id }) end
    ns.Kit.Sound("tap")
    return true
end

-- ---------------------------------------------------------------------------------------
-- Pin and Unpin on the item card

local function ItemIdOf(subject)
    if type(subject) ~= "table" then return nil end
    if subject.bag and subject.slot then
        local info = C_Container.GetContainerItemInfo(subject.bag, subject.slot)
        local id = info and info.itemID
        if type(id) == "number" and not Secret(id) then return id end
        return nil
    end
    if type(subject.link) == "string" then return tonumber(subject.link:match("item:(%d+)")) end
end

-- The held item's kind and id when it can be pinned: nil for armour and the like.
local function Pinnable(subject)
    local id = ItemIdOf(subject)
    local kind = id and Classify(id)
    if kind then return id, kind end
end

-- The slot the held item is pinned to: the slot it was held in when that slot pins it (any item can be pinned
-- there), else the slot of its own kind.
local function PinnedSlot(subject)
    local id, pins = ItemIdOf(subject), Pins()
    if not id or not pins then return nil end
    if subject.rail and pins[CATS[subject.rail]] == id then return subject.rail end
    local kind = Classify(id)
    if kind and pins[kind.cat] == id then return INDEX[kind.cat] end
end

if TouchPlay and TouchPlay.AddCardAction then
    -- Change item: the picker's Items tab for the slot that was held (a hold on the column, not on a bag item)
    TouchPlay.AddCardAction("item", ns.T("items.change"), function(subject)
        if ns.Picker and ns.Picker.OpenItem and subject.rail then ns.Picker.OpenItem(subject.rail) end
    end, function(subject)
        return subject.rail ~= nil and ns.Picker ~= nil and ns.Picker.OpenItem ~= nil
    end)
    -- Pin shows for a pinnable item that is not pinned; Unpin for the one that is.
    TouchPlay.AddCardAction("item", ns.T("items.pin"), function(subject)
        local id, kind = Pinnable(subject)
        if kind then ItemRail.Pin(INDEX[kind.cat], id) end
    end, function(subject)
        local _, kind = Pinnable(subject)
        return kind ~= nil and PinnedSlot(subject) == nil
    end)
    TouchPlay.AddCardAction("item", ns.T("items.unpin"), function(subject)
        local slot = PinnedSlot(subject)
        if slot then ItemRail.Unpin(slot) end
    end, function(subject)
        return PinnedSlot(subject) ~= nil
    end)
end

-- ---------------------------------------------------------------------------------------
-- Module steps

function ItemRail:Init()
    Pins()
    local Contract = ns.Contract
    if not Contract then return end
    for i, b in ipairs(buttons) do
        local name = b:GetName()
        Contract.Area("item" .. i, b, { anchor = CORNER,
            tap = { click = name, button = "LeftButton" },
            hold = { click = name, button = "RightButton" } })
    end
end

function ItemRail:Layout()
    ns.Queue("itemrail layout", Place)
end

function ItemRail:Refresh()
    Sync()
    UpdateGlow()
end
