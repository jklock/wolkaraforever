-- TouchPlay: loot toasts and the loot card (mockups 01, 78).
--
--   * a toast for every item the player gets (CHAT_MSG_LOOT, the player's own lines only): icon,
--     name in the quality colour, count; it flies to the Bags ring (read from Hud.bags) and
--     fades; four at most, from a pool;
--   * the loot card on LOOT_OPENED: money, items and quest items (gold outline, "quest item ·
--     <quest>") as rows, "Take all" and "Close". Money only: "Take" and "Close". Bags full: items
--     dimmed, a red line, "Take money" and "Open bags". With auto-loot on the game takes
--     everything it can, so the card only appears when full bags leave items behind;
--   * taking loot is only ever a tap: the only LootSlot calls are in Loot.TakeAll and
--     Loot.TakeMoney, run from a button click. No event takes anything;
--   * while our card is up the game's own loot window is made invisible (alpha 0) and untouchable
--     (mouse off on it and its children). It is never hidden or reparented (R26): its own
--     open/close logic, hide animation, ESC and bind-on-pickup popup keep running, and its
--     OnHide (which closes the loot) never fires because of us. It is given back as it was
--     when the card hides (once the game has hidden it, if it is still closing), on a pause and
--     on Off. Bind on pickup keeps the game's own popup (Task 14 skins it).
--   * with auto-loot on, the card opens only when full bags leave items behind: at LOOT_OPENED,
--     or later when the game fills the last slot (ERR_INV_FULL, a slot cleared, bags changed)
--     while the loot window is still open. Showing takes nothing.
--
-- Loot data is plain, but names are still passed straight to SetText and every compare is
-- guarded, as in the other files.

local ADDON_NAME, ns = ...

local Loot = ns.Register("Loot", {})
local Kit = ns.Kit

ns.L["loot.takeAll"] = "Take all"
ns.L["loot.take"] = "Take"
ns.L["loot.takeMoney"] = "Take money"
ns.L["loot.openBags"] = "Open bags"
ns.L["loot.money"] = "money"
ns.L["loot.currency"] = "currency"
ns.L["loot.questItem"] = "quest item"
ns.L["loot.quest"] = "quest item · %s"
ns.L["loot.full"] = "Your bags are full. Take the money; the items stay here until you make room."
ns.L["loot.fullTaken"] = "Your bags are full. The money is taken; the items stay here until you make room."
ns.L["loot.more"] = "+ %d more"
ns.L["loot.gold"] = "%d gold"
ns.L["loot.silver"] = "%d silver"
ns.L["loot.copper"] = "%d copper"
ns.L["loot.quality0"] = "junk"
ns.L["loot.quality1"] = "common"
ns.L["loot.quality2"] = "uncommon"
ns.L["loot.quality3"] = "rare"
ns.L["loot.quality4"] = "epic"
ns.L["loot.quality5"] = "legendary"

-- ---------------------------------------------------------------------------------------
-- Numbers (layout units)

local TOAST_W, TOAST_H, TOAST_X, TOAST_Y, TOAST_STEP, TOASTS = 260, 44, 690, 230, 52, 4
local TOAST_HOLD, TOAST_FLY = 1.4, 0.55
local CARD_W, CARD_X, CARD_Y, CARD_PAD = 420, 473, 180, 16
local ROW_H, ROW_ICON, MAX_ROWS = 64, 48, 8
local BUTTON_H, RED_H, MORE_H = 44, 46, 24
local GOLD = { 1, 0.82, 0 }
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

local function Num(value) return Plain(value) and type(value) == "number" and value or nil end

local function QualityColour(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------------------
-- Toasts

local toasts = {}
Loot.toasts = toasts
local toastSeq = 0

local function ToastDone(group) group:GetParent():Hide() end

for i = 1, TOASTS do
    local t = Kit.Backdrop(ns.root, "tooltip", "tooltip")
    t:SetSize(TOAST_W, TOAST_H)
    t:SetFrameLevel(30)
    t:EnableMouse(false)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(32, 32)
    t.icon:SetPoint("LEFT", t, "LEFT", 8, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.name = t:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(t.name, Kit.FONT_TITLE, 16, "")
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.name:SetSize(TOAST_W - 112, 20)
    t.name:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
    t.count = t:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(t.count, Kit.FONT_NUMBER, 16, "OUTLINE")
    t.count:SetTextColor(1, 1, 1)
    t.count:SetPoint("RIGHT", t, "RIGHT", -12, 0)
    t.group = t:CreateAnimationGroup()
    t.move = t.group:CreateAnimation("Translation")
    t.move:SetDuration(TOAST_FLY)
    t.move:SetStartDelay(TOAST_HOLD)
    t.move:SetSmoothing("IN")
    t.fade = t.group:CreateAnimation("Alpha")
    t.fade:SetFromAlpha(1)
    t.fade:SetToAlpha(0)
    t.fade:SetDuration(TOAST_FLY)
    t.fade:SetStartDelay(TOAST_HOLD)
    t.group:SetScript("OnFinished", ToastDone)
    t:Hide()
    toasts[i] = t
end

-- Left-handed, the toasts start just right of the mirrored quest list (380 to 720 in mockup 87: x 730), wherever
-- the list is; right-handed as the mockup. Toasts on screen are not moved.
local TOAST_GAP = 10
local function ToastX()
    local quest = ns.LeftHanded() and ns.Hud and ns.Hud.quest and ns.Hud.quest.touchAnchor
    if quest then return quest.x + quest.w + TOAST_GAP end
    return TOAST_X
end

local function PlaceToasts()
    local x = ToastX()
    for _, t in ipairs(toasts) do
        if t:IsShown() then return end
    end
    for i, t in ipairs(toasts) do ns.Anchor(t, "TL", x, TOAST_Y + (i - 1) * TOAST_STEP) end
end
PlaceToasts()

-- The loot lines that are the player's own (the game's own global strings, made into patterns).
local function Pattern(format)
    local p = format:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local MANY, ONE = {}, {}
for _, name in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF" }) do
    local one = _G[name] or ({ LOOT_ITEM_SELF = "You receive loot: %s.", LOOT_ITEM_PUSHED_SELF = "You receive item: %s.",
        LOOT_ITEM_CREATED_SELF = "You create: %s." })[name]
    local many = _G[name .. "_MULTIPLE"] or one:gsub("%%s%.", "%%sx%%d.")
    MANY[#MANY + 1] = Pattern(many)
    ONE[#ONE + 1] = Pattern(one)
end

-- The item link and count of one of the player's loot lines, or nil.
local function ParseLoot(text)
    for _, p in ipairs(MANY) do
        local link, n = text:match(p)
        if link then return link, tonumber(n) or 1 end
    end
    for _, p in ipairs(ONE) do
        local link = text:match(p)
        if link then return link, 1 end
    end
end

local function QualityOf(link, id)
    local get = C_Item and C_Item.GetItemQualityByID
    local q = id and get and get(id)
    if type(q) == "number" then return q end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    if hex and ITEM_QUALITY_COLORS then
        local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        for quality = 0, 8 do
            local c = ITEM_QUALITY_COLORS[quality]
            if c and math.abs(c.r - r) < 0.01 and math.abs(c.g - g) < 0.01 and math.abs(c.b - b) < 0.01 then
                return quality
            end
        end
    end
    return 1
end

local function IconOf(id)
    local icon = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)))
    return icon or UNKNOWN_ICON
end

-- A free toast, else the oldest one (it starts again).
local function PickToast()
    local oldest = toasts[1]
    for _, t in ipairs(toasts) do
        if not t:IsShown() then return t end
        if (t.seq or 0) < (oldest.seq or 0) then oldest = t end
    end
    return oldest
end

local function ShowToast(link, count)
    PlaceToasts()                 -- the quest list may have moved since the last layout (none is on screen then)
    local t = PickToast()
    toastSeq = toastSeq + 1
    t.seq = toastSeq
    local id = tonumber(link:match("|Hitem:(%d+)"))
    t.name:SetText(link:match("%[(.-)%]") or link)
    t.name:SetTextColor(QualityColour(QualityOf(link, id)))
    t.icon:SetTexture(IconOf(id))
    t.count:SetText("x" .. count)
    t.count:SetShown(count > 1)
    -- it flies to the Bags ring: the offset from where it sits to the ring's centre
    local ring, a = ns.Hud and ns.Hud.bags and ns.Hud.bags.touchAnchor, t.touchAnchor
    t.flyX, t.flyY = 0, 0
    -- reduce motion: it fades where it is instead of flying to the ring
    if ring and a and not ns.ReduceMotion() then
        t.flyX = (ring.x + ring.w / 2) - (a.x + a.w / 2)
        t.flyY = -((ring.y + ring.h / 2) - (a.y + a.h / 2))
    end
    t.move:SetOffset(t.flyX, t.flyY)
    t.group:Stop()
    t:Show()
    t.group:Play()
end

ns.On("CHAT_MSG_LOOT", function(text)
    if not Plain(text) or type(text) ~= "string" then return end
    local link, count = ParseLoot(text)
    if link and link:find("|Hitem:", 1, true) then ShowToast(link, count) end
end)

-- ---------------------------------------------------------------------------------------
-- The card: slots

local T_NONE, T_ITEM, T_MONEY, T_CURRENCY = 0, 1, 2, 3
do
    local e = Enum and Enum.LootSlotType
    if e then T_NONE, T_ITEM, T_MONEY, T_CURRENCY = e.None, e.Item, e.Money, e.Currency end
end

-- "money", "item" or "currency" for a slot that still holds something, else nil.
local function SlotKind(slot)
    local kind = GetLootSlotType and GetLootSlotType(slot)
    if kind == T_MONEY then return "money" end
    if kind == T_ITEM then return "item" end
    if kind == T_CURRENCY then return "currency" end
    return nil
end

local function FreeSlots()
    local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not get then return 1 end
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n = Num(get(bag))
        if n then free = free + n end
    end
    return free
end

local function MoneyText(copper)
    local parts = {}
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if gold > 0 then parts[#parts + 1] = ns.T("loot.gold", gold) end
    if silver > 0 then parts[#parts + 1] = ns.T("loot.silver", silver) end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = ns.T("loot.copper", rest) end
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------------------
-- The card: frame and rows

local card = Kit.Backdrop(ns.root, "tooltip", "tooltip")
card:SetFrameStrata(Kit.SHEET_STRATA)   -- above every window, as the other sheets (iPad run 6)
card:SetSize(CARD_W, 120)
card:SetFrameLevel(45)
card:Hide()
Loot.card = card

-- ---------------------------------------------------------------------------------------
-- The game's loot window: invisible and untouchable while our card is up

local lootOpen, dismissed = false, false   -- the game's loot window is open; the player closed our card
local gameHidden, giveBackPending, savedAlpha = false, false, 1
local mouseOff, mouseOffN = {}, 0       -- frames whose mouse we switched off
local hooked = false

-- Mouse off on a frame and everything under it that has it on (the game makes the loot rows as
-- the window opens, so this runs again while the card is up).
local function QuietMouse(...)
    for i = 1, select("#", ...) do
        local frame = select(i, ...)
        if frame.IsMouseEnabled and frame:IsMouseEnabled() and not (frame.IsProtected and frame:IsProtected()) then
            mouseOffN = mouseOffN + 1
            mouseOff[mouseOffN] = frame
            frame:EnableMouse(false)
        end
        if frame.GetChildren then QuietMouse(frame:GetChildren()) end
    end
end

local function GiveGameLootBackNow()
    giveBackPending = false
    if not gameHidden then return end
    gameHidden = false
    local window = _G.LootFrame
    if window then
        -- a window that is up is never given back invisible (a hide animation can leave alpha 0)
        window:SetAlpha(savedAlpha == 0 and window:IsShown() and 1 or savedAlpha)
    end
    for i = 1, mouseOffN do
        mouseOff[i]:EnableMouse(true)
        mouseOff[i] = nil
    end
    mouseOffN = 0
end

local function OnGameLootHide()
    if giveBackPending then GiveGameLootBackNow() end
end

local function HideGameLoot()
    local window = _G.LootFrame
    if not window then return end
    giveBackPending = false
    if not gameHidden then
        gameHidden = true
        savedAlpha = window:GetAlpha()
    elseif window:GetAlpha() ~= 0 then
        savedAlpha = window:GetAlpha()      -- the game set it (its open animation ends at 1)
    end
    window:SetAlpha(0)
    QuietMouse(window)
end

-- The game's open animation (ScrollingFlatPanel.xml: ShowAnim, setToFinalAlpha) ends by setting the
-- window's alpha back to 1, and the loot ScrollBox makes rows after our sweep. While our card is
-- up, both put our change back; once it is down these do nothing.
local function ReapplyLate()
    if card:IsShown() then HideGameLoot() end
end
local function OnShowAnimPlay()
    if card:IsShown() then HideGameLoot() end
end
local function OnShowAnimFinished()
    if not card:IsShown() then return end
    HideGameLoot()
    C_Timer.After(0, ReapplyLate)           -- in case the final alpha is set after this script
end
local function OnRowAcquired(_, row)
    if card:IsShown() and row then QuietMouse(row) end
end

local function HookGameLoot(window)
    if hooked then return end
    hooked = true
    if window.HookScript then window:HookScript("OnHide", OnGameLootHide) end
    local anim = window.ShowAnim
    if anim and anim.HookScript then
        anim:HookScript("OnPlay", OnShowAnimPlay)
        anim:HookScript("OnFinished", OnShowAnimFinished)
    end
    local box = window.ScrollBox
    if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
        pcall(box.RegisterCallback, box, ScrollBoxListMixin.Event.OnAcquiredFrame, OnRowAcquired, Loot)
    end
end

-- The card hid: the window comes back now, or as soon as the game has hidden it.
local function GiveGameLootBack()
    local window = _G.LootFrame
    if gameHidden and window and window:IsShown() then
        giveBackPending = true
        return
    end
    GiveGameLootBackNow()
end

local function ShowCard()
    card:Show()
    if _G.LootFrame then HookGameLoot(_G.LootFrame) end
    HideGameLoot()
end

local function HideCard()
    card:Hide()
    GiveGameLootBack()
end

local rows = {}
Loot.rows = rows
for i = 1, MAX_ROWS do
    local row = Kit.Backdrop(card, "tooltip", "tooltip")
    row:SetSize(CARD_W - 2 * CARD_PAD, ROW_H - 4)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + (i - 1) * ROW_H))
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_ICON, ROW_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.count = row:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(row.count, Kit.FONT_NUMBER, 14, "OUTLINE")
    row.count:SetTextColor(1, 1, 1)
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -2, 2)
    row.name = row:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(row.name, Kit.FONT_TITLE, 19, "")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetSize(CARD_W - 2 * CARD_PAD - ROW_ICON - 34, 22)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.sub = row:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(row.sub, Kit.FONT_TITLE, 14, "")
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.sub:SetSize(CARD_W - 2 * CARD_PAD - ROW_ICON - 34, 18)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.quest, row.dim = false, false
    row:Hide()
    rows[i] = row
end

local redLine = card:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(redLine, Kit.FONT_TITLE, 16, "")
redLine:SetTextColor(1, 0.35, 0.3)
redLine:SetJustifyH("LEFT")
redLine:SetJustifyV("TOP")
redLine:SetWidth(CARD_W - 2 * CARD_PAD)
redLine:Hide()
Loot.redLine = redLine

local moreLine = card:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(moreLine, Kit.FONT_TITLE, 14, "")
moreLine:SetTextColor(0.62, 0.62, 0.62)
moreLine:Hide()
Loot.moreLine = moreLine

local function ButtonClick(self) ns.Guard("loot button", self.action) end
local buttonWidth = (CARD_W - 2 * CARD_PAD - 10) / 2
local button1 = Kit.RedButton(card, buttonWidth, BUTTON_H, ns.T("loot.takeAll"))
button1:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD, CARD_PAD)
local button2 = Kit.RedButton(card, buttonWidth, BUTTON_H, ns.T("common.close"))
button2:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
for _, b in ipairs({ button1, button2 }) do b:SetScript("OnClick", ButtonClick) end
Loot.button1, Loot.button2 = button1, button2

-- ---------------------------------------------------------------------------------------
-- The card: what a tap does (the only places that take loot)

function Loot.TakeAll()
    for slot = 1, GetNumLootItems() do
        if SlotKind(slot) then LootSlot(slot) end
    end
end

function Loot.TakeMoney()
    for slot = 1, GetNumLootItems() do
        if SlotKind(slot) == "money" then LootSlot(slot) end
    end
end

function Loot.Close()
    dismissed = true
    if CloseLoot then CloseLoot() end
    HideCard()
end

-- Opening the bags is refused to add-on code in a fight (R32): Open bags is greyed then and does nothing; out of a
-- fight the game's own call runs inside pcall (a missing or changed Blizzard function is no reason to pause).
function Loot.OpenBags()
    if ns.InFight() then return end
    local open = OpenAllBags or ToggleAllBags
    if open then pcall(open) end
end

button1.action, button2.action = Loot.TakeAll, Loot.Close

-- Greyed with "After the fight" while Open bags cannot work; every other button always works.
local function Greyed(button)
    local off = button.action == Loot.OpenBags and ns.InFight()
    if button:IsEnabled() == (not off) and (button.reason ~= nil) == off then return end
    button:SetEnabledWithReason(not off, off and ns.T("common.afterFight") or nil)
end

local function SetButton(button, label, action)
    button.label:SetText(label)
    button.action = action
    Greyed(button)
end

local function OnFightChange()
    if not card:IsShown() then return end
    Greyed(button1)
    Greyed(button2)
end
ns.On("PLAYER_REGEN_DISABLED", OnFightChange)
ns.On("PLAYER_REGEN_ENABLED", OnFightChange)

-- ---------------------------------------------------------------------------------------
-- The card: filling it

local function ItemExtra(slot)
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = Plain(link) and type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if not id or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, itemType, _, equipLoc = C_Item.GetItemInfoInstant(id)
    local text = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
    if type(text) ~= "string" then text = itemType end
    if type(text) == "string" and text ~= "" then return text:lower() end
end

local function FillRow(row, slot, kind, full)
    local texture, item, quantity, _, quality, locked, isQuest, questID = GetLootSlotInfo(slot)
    quality = Num(quality) or 1
    row.slot, row.kind = slot, kind
    row.icon:SetTexture(texture)
    if kind == "money" then
        local copper = Num(quantity)
        row.name:SetText(copper and MoneyText(copper) or item)
        row.name:SetTextColor(1, 1, 1)
        row.sub:SetText(ns.T("loot.money"))
        row.count:Hide()
    else
        row.name:SetText(item)
        row.name:SetTextColor(QualityColour(quality))
        local count = Num(quantity)
        row.count:SetText(count and count > 1 and tostring(count) or "")
        row.count:SetShown(count ~= nil and count > 1)
    end
    local quest = Plain(isQuest) and isQuest and true or false
    local questTitle
    questID = Num(questID)
    if questID then
        quest = true
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        if Plain(title) and type(title) == "string" and title ~= "" then questTitle = title end
    end
    if kind == "item" then
        if quest then
            row.sub:SetText(questTitle and ns.T("loot.quest", questTitle) or ns.T("loot.questItem"))
        else
            local text = ns.T("loot.quality" .. quality)
            local extra = ItemExtra(slot)
            row.sub:SetText(extra and (text .. " · " .. extra) or text)
        end
    elseif kind == "currency" then
        row.sub:SetText(ns.T("loot.currency"))
    end
    row.sub:SetTextColor(quest and GOLD[1] or 0.62, quest and GOLD[2] or 0.62, quest and GOLD[3] or 0.62)
    row.quest = quest and kind ~= "money"
    if row.quest then
        row:SetBackdropColor(90 / 255, 70 / 255, 16 / 255, 0.9)
        row:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    else
        row:SetBackdropColor(0, 0, 0, 0)
        row:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if Plain(locked) and locked then row.icon:SetVertexColor(0.9, 0, 0) else row.icon:SetVertexColor(1, 1, 1) end
    row.dim = full and kind ~= "money" or false
    row.icon:SetDesaturated(row.dim)
    row:SetAlpha(row.dim and 0.5 or 1)
    row:Show()
end

-- Reads the open loot window into the card. Returns how many slots hold something, whether any
-- is not money, and whether the bags are full for them.
local function Rebuild()
    local total = GetNumLootItems and GetNumLootItems() or 0
    local live, anyItem, moneySlot = 0, false, false
    for slot = 1, total do
        local kind = SlotKind(slot)
        if kind then
            live = live + 1
            if kind == "money" then moneySlot = true else anyItem = true end
        end
    end
    local full = anyItem and FreeSlots() == 0
    local shown = 0
    for pass = 1, 2 do                      -- money first, then the rest
        for slot = 1, total do
            local kind = SlotKind(slot)
            if kind and (kind == "money") == (pass == 1) and shown < MAX_ROWS then
                shown = shown + 1
                FillRow(rows[shown], slot, kind, full)
            end
        end
    end
    for i = shown + 1, MAX_ROWS do rows[i]:Hide() end
    local y = CARD_PAD + shown * ROW_H
    local height = y + 12 + BUTTON_H + CARD_PAD
    moreLine:ClearAllPoints()
    if live > shown then
        moreLine:SetText(ns.T("loot.more", live - shown))
        moreLine:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + 8, -y)
        moreLine:Show()
        y = y + MORE_H
        height = height + MORE_H
    else
        moreLine:Hide()
    end
    redLine:ClearAllPoints()
    if full then
        redLine:SetText(ns.T(moneySlot and "loot.full" or "loot.fullTaken"))
        redLine:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
        redLine:Show()
        height = height + RED_H
        if moneySlot then
            SetButton(button1, ns.T("loot.takeMoney"), Loot.TakeMoney)
            SetButton(button2, ns.T("loot.openBags"), Loot.OpenBags)
        else
            SetButton(button1, ns.T("loot.openBags"), Loot.OpenBags)
            SetButton(button2, ns.T("common.close"), Loot.Close)
        end
    else
        redLine:Hide()
        SetButton(button1, ns.T(anyItem and "loot.takeAll" or "loot.take"), Loot.TakeAll)
        SetButton(button2, ns.T("common.close"), Loot.Close)
    end
    card:SetHeight(height)
    ns.Anchor(card, "TL", CARD_X, CARD_Y)
    return live, anyItem, full
end

-- ---------------------------------------------------------------------------------------
-- Events

ns.On("LOOT_OPENED", function(isAuto)
    lootOpen, dismissed = true, false
    if isAuto == nil then isAuto = GetCVar and GetCVar("autoLootDefault") == "1" end
    isAuto = isAuto == true or isAuto == 1
    local live, _, full = Rebuild()
    if live == 0 or (isAuto and not full) then HideCard() else ShowCard() end
end)

-- A slot was taken or changed, or the bags filled. A card that is up follows; one that is not up
-- opens when the window is still open and full bags leave items behind (auto-loot that only half
-- fitted). It opens only for that, and not again after the player closed it.
local function Update()
    if not lootOpen and not card:IsShown() then return end
    local live, _, full = Rebuild()
    if live == 0 then
        HideCard()
    elseif card:IsShown() then
        HideGameLoot()
    elseif lootOpen and full and not dismissed then
        ShowCard()
    end
end
ns.On("LOOT_SLOT_CLEARED", Update)
ns.On("LOOT_SLOT_CHANGED", Update)
ns.On("BAG_UPDATE_DELAYED", Update)
ns.On("UI_ERROR_MESSAGE", function(_, message)
    if Plain(message) and message == ERR_INV_FULL then Update() end
end)
ns.On("LOOT_CLOSED", function()
    lootOpen = false
    HideCard()
end)

-- ---------------------------------------------------------------------------------------
-- Module steps

function Loot:Layout()
    PlaceToasts()
    ns.Anchor(card, "TL", CARD_X, CARD_Y)
end

function Loot:Restore()
    lootOpen = false
    card:Hide()
    GiveGameLootBackNow()
    for _, t in ipairs(toasts) do
        t.group:Stop()
        t:Hide()
    end
end
