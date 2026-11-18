-- TouchPlay: info cards (rule 4). Holding any button, card or person opens a card: the game's own
-- tooltip text, bigger, with the actions a right click would give. A hold never casts or acts.
--
-- The lines come from the game itself: a hidden GameTooltip is filled with SetAction, SetBagItem,
-- SetHyperlink, SetUnit or SetUnitAura and its lines are copied one by one, with their colours.
-- That text can be hidden in a fight (a "secret"), so it only ever goes to SetText: nothing here
-- compares it, joins it, measures it with maths or uses it as a key.
--
-- The card opens beside what was held, never over it (right side first, left when it does not
-- fit), with a small gold arrow pointing back. Past 330 units of text it scrolls inside the card.
--
-- Actions that the game protects in a fight (change a button, use or equip an item, target) are
-- greyed with the reason. Add-ons can add lines and actions: TouchPlay.AddCardLine and
-- TouchPlay.AddCardAction. A hook that fails is skipped and remembered; it never pauses the add-on.

local ADDON_NAME, ns = ...

local InfoCard = ns.Register("InfoCard", {})
local Kit = ns.Kit

ns.L["card.change"] = "Change spell"
ns.L["card.remove"] = "Remove"
ns.L["card.use"] = "Use"
ns.L["card.equip"] = "Equip"
ns.L["card.link"] = "Link"
ns.L["card.sell"] = "Sell"
ns.L["card.whisper"] = "Whisper"
ns.L["card.invite"] = "Invite"
ns.L["card.target"] = "Target"
ns.L["card.cancelBuff"] = "Cancel buff"
ns.L["card.showOnMap"] = "Show on map"
ns.L["card.untrack"] = "Untrack"
ns.L["card.inspect"] = "Inspect"
ns.L["card.trade"] = "Trade"
ns.L["card.follow"] = "Follow"
ns.L["card.back"] = "Back"
ns.L["card.afterFight"] = "You can change buttons after this fight."
ns.L["card.afterFightDo"] = "You can do this after this fight."
ns.L["card.unitGone"] = "That one is not nearby now."
ns.L["card.notNow"] = "That is not available now."
ns.L["card.emptyButton"] = "Empty button"
ns.L["card.emptyHint"] = "Nothing on this button yet."
ns.L["card.nothingHere"] = "Nothing here"
ns.L["card.autocastOn"] = "Autocast: on"
ns.L["card.autocastOff"] = "Autocast: off"

local REF_W, REF_H = 1366, 1024
local MARGIN, GAP = 8, 12             -- from the screen edge; between the card and what was held
local SCROLL_AT = 330                 -- body height after which the card scrolls
local PAD, ROW_GAP = 20, 4
local ICON, ICON_SPACE = 56, 64       -- picture size; width kept free beside it
local BAR_W = 26                      -- the gold scroll bar and its gap
local BODY_FONT = 16
local ARROW = 26
local ARROW_ART = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local MAX_BUTTONS = 4

local TipOf                           -- the hidden tooltip, made on first use
local card, catcher                   -- the card (Kit.Card) and the tap-away layer behind it
local secureButton                    -- the secure button over a card button the game protects (Use, Target, Autocast)
local current                         -- what the card shows now: { subject, anchor, model }

-- ---------------------------------------------------------------------------------------
-- Placement (pure)

local function Clamp(v, lo, hi)
    if v > hi then v = hi end
    if v < lo then v = lo end
    return v
end

-- Whether two { x, y, w, h } rectangles share any area.
local function Meet(ax, ay, aw, ah, b)
    return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end

-- Where the card's top-left goes, in layout units from the screen's top-left. (ax, ay, aw, ah)
-- is what was held. Right side first; left when it does not fit; kept 8 units inside the screen.
-- `avoid` (optional): rectangles { x, y, w, h } the card must keep off (iPad run 5: the card's buttons sat over the
-- chat strip and the app's toolbar, and a tap on Change spell opened the keyboard). The card moves up or down, the
-- shorter way that stays on the screen, until it meets none of them (when no way fits, it stays where it is).
function InfoCard.Place(cardW, cardH, ax, ay, aw, ah, screenW, avoid)
    local right = ax + aw + GAP
    local left = ax - GAP - cardW
    local x, side
    if right + cardW <= screenW - MARGIN then
        x, side = right, "right"
    elseif left >= MARGIN then
        x, side = left, "left"
    else
        if screenW - (ax + aw) >= ax then x, side = right, "right" else x, side = left, "left" end
        x = Clamp(x, MARGIN, math.max(MARGIN, screenW - MARGIN - cardW))
    end
    local lowest = math.max(MARGIN, REF_H - MARGIN - cardH)
    local y = Clamp(ay + ah / 2 - cardH / 2, MARGIN, lowest)
    if type(avoid) == "table" and #avoid > 0 then
        local function Clear(cy)
            if cy < MARGIN - 1e-6 or cy > lowest + 1e-6 then return false end
            for _, r in ipairs(avoid) do
                if Meet(x, cy, cardW, cardH, r) then return false end
            end
            return true
        end
        if not Clear(y) then
            -- the nearest clear place among the edges of what is in the way (above or below each one)
            local best
            local candidates = { MARGIN, lowest }
            for _, r in ipairs(avoid) do
                candidates[#candidates + 1] = r.y - GAP - cardH
                candidates[#candidates + 1] = r.y + r.h + GAP
            end
            for _, cy in ipairs(candidates) do
                if Clear(cy) and (not best or math.abs(cy - y) < math.abs(best - y)) then best = cy end
            end
            if best then y = best end
        end
    end
    return x, y, side
end

-- What the card keeps off, in layout units from the screen's top-left (the root's real width): the chat strip (a tap
-- there opens the keyboard), the walk stick's side (the lower part of the left third, the right third when
-- left-handed: the app reserves that third for the stick, below the quest list at y 460) and the app's toolbar bands
-- (ns.AppBands). Into `list`.
InfoCard.STICK_TOP = 470
local function RootRect(frame)
    if type(frame) ~= "table" or not frame.GetRect or not frame:IsVisible() then return nil end
    local l, b, w, h = frame:GetRect()
    if type(l) ~= "number" then return nil end
    local k = frame:GetEffectiveScale() / ns.root:GetEffectiveScale()
    return l * k, REF_H - (b + h) * k, w * k, h * k
end
function InfoCard.KeepOff(list, rootW)
    list = list or {}
    for i = #list, 1, -1 do list[i] = nil end
    rootW = rootW or REF_W
    local x, y, w, h = RootRect(ns.Chat and ns.Chat.strip)
    if x then list[#list + 1] = { name = "chat strip", x = x, y = y, w = w, h = h } end
    local third = rootW / 3
    local stickX = (ns.LeftHanded and ns.LeftHanded()) and rootW - third or 0
    list[#list + 1] = { name = "walk stick", x = stickX, y = InfoCard.STICK_TOP, w = third, h = REF_H - InfoCard.STICK_TOP }
    if ns.AppBands then
        for _, band in ipairs(ns.AppBands()) do
            list[#list + 1] = { name = band.name, x = band.x, y = band.y, w = band.w, h = band.h }
        end
    end
    return list
end

-- ---------------------------------------------------------------------------------------
-- Hooks (scope "moddable")

local lineHooks, actionHooks = {}, {}
TouchPlay = TouchPlay or {}

-- fn(subject) returns a line: a string, or { text =, r =, g =, b = }. Added under the game's lines.
function TouchPlay.AddCardLine(kind, fn)
    if type(fn) ~= "function" then return end
    lineHooks[kind] = lineHooks[kind] or {}
    table.insert(lineHooks[kind], fn)
end

-- fn(subject) runs when the button is tapped. At most four buttons fit, so hooks come last. The optional
-- isShown(subject, model) says whether the button appears at all (a hook that fails, or answers anything
-- but true, hides it); without it the button always appears.
function TouchPlay.AddCardAction(kind, label, fn, isShown)
    if type(fn) ~= "function" or type(label) ~= "string" then return end
    if isShown ~= nil and type(isShown) ~= "function" then return end
    actionHooks[kind] = actionHooks[kind] or {}
    table.insert(actionHooks[kind], { label = label, fn = fn, isShown = isShown })
end

local function Remember(label, problem)
    ns.RememberError(label .. ": " .. tostring(problem))
end

-- ---------------------------------------------------------------------------------------
-- Helpers over the game's API (the names differ between game versions)

local function Func(namespace, name)
    local space = namespace and _G[namespace]
    if type(space) == "table" and space[name] then return space[name] end
    return _G[name]
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A size read from the text on a font string. Hidden text may answer a hidden size: then the
-- fallback is used, so no maths ever touches it.
local function Measure(fs, fallback)
    local ok, h = pcall(fs.GetStringHeight, fs)
    if ok and type(h) == "number" and not Secret(h) and h > 0 then return h end
    return fallback
end

local function InFight() return ns.InFight() end

-- ---------------------------------------------------------------------------------------
-- Reading the game's tooltip

local function Tip()
    if TipOf then return TipOf end
    TipOf = CreateFrame("GameTooltip", "TouchPlayCardTip", UIParent, "GameTooltipTemplate")
    TipOf:SetAlpha(0)
    return TipOf
end

-- Copies the lines of `tip` into model.lines; line 1 becomes the title. Text and colours are
-- stored as they are and only handed to SetText / SetTextColor later.
local function CopyLines(tip, model)
    local name = tip:GetName()
    local n = tip:NumLines()
    if type(n) ~= "number" then n = 0 end
    for i = 1, n do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        if left then
            local line = { left = left:GetText() }
            line.lr, line.lg, line.lb = left:GetTextColor()
            if right and right:IsShown() then
                line.hasRight = true
                line.right = right:GetText()
                line.rr, line.rg, line.rb = right:GetTextColor()
            end
            if i == 1 then
                model.title, model.tr, model.tg, model.tb = line.left, line.lr, line.lg, line.lb
                model.titled = true
                if line.hasRight then
                    model.lines[#model.lines + 1] = { hasRight = true, right = line.right,
                        lr = 1, lg = 1, lb = 1, rr = line.rr, rg = line.rg, rb = line.rb }
                end
            else
                model.lines[#model.lines + 1] = line
            end
        end
    end
    return n > 0
end

-- Fills the hidden tooltip with `fill(tip)` and copies it. False when the game gave nothing.
local function ReadFrom(model, fill)
    local tip = Tip()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetAlpha(0)
    tip:ClearLines()
    -- a game function that changed is no reason to pause: the card shows without its lines
    local done, ok = pcall(fill, tip)
    if not done then Remember("card tooltip", ok) end
    local got = done and ok ~= false and CopyLines(tip, model)
    tip:Hide()
    return got
end

-- ---------------------------------------------------------------------------------------
-- The actions (what each button does). Each is run(subject) and sits behind a pcall.

local function Insert(link)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insert and insert(link) then return end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then open(link) end
end

local function UnitFullName(unit)
    return (GetUnitName or UnitName)(unit, true)
end

local function Entry(labelKey, run, opts)
    local e = { label = ns.T(labelKey), run = run }
    if opts then for k, v in pairs(opts) do e[k] = v end end
    return e
end

local function Close() InfoCard.Hide() end

local function ActionButtons(subject, model)
    local slot = subject.slot
    local list = model.buttons
    if ns.Picker and ns.Picker.Open then
        list[#list + 1] = Entry("card.change", function() ns.Picker.Open(slot) end,
            { fightLocked = true, reasonKey = "card.afterFight" })
    end
    if model.filled and ns.Picker and ns.Picker.Remove then
        list[#list + 1] = Entry("card.remove", function() ns.Picker.Remove(slot) end,
            { fightLocked = true, reasonKey = "card.afterFight" })
    end
    list[#list + 1] = Entry("common.close", Close)
end

-- What a secure button carries is decided where the card is drawn, out of a fight (PrepareSecure), never from a
-- tap: the game runs the action itself when the player taps the button (TargetUnit and using an item are
-- restricted for add-on code, R35, R37).
local function Noop() end

-- Use: the secure "item" action takes "bag slot" and uses it (or equips it) as the game's own bag buttons do.
local function ItemAttrs(entry) return { type = "item", item = entry.bag .. " " .. entry.slot } end

-- Splitting and deleting belong to the bags screen (phase 3), not to the card.
local function ItemButtons(subject, model)
    local list, bag, slot, link = model.buttons, subject.bag, subject.slot, model.link
    if bag and slot then
        local locked = { fightLocked = true, reasonKey = "card.afterFightDo" }
        list[#list + 1] = model.equippable
            and Entry("card.equip", function()
                (Func("C_Item", "EquipItemByName"))(link)
            end, locked)
            or Entry("card.use", Noop,
                { fightLocked = true, reasonKey = "card.afterFightDo", secureFn = ItemAttrs,
                  bag = bag, slot = slot,
                  hold = ns.Popups and ns.Popups.ItemNeedsHold(model.itemID) or false,
                  holdLabel = ns.Popups and ns.Popups.ItemLabel(model.itemID) or nil,
                  holdKey = ("%s:%s:%s"):format(tostring(model.itemID), tostring(bag), tostring(slot)) })
        list[#list + 1] = Entry("card.link", function() Insert(link) end)
        if model.vendor then
            list[#list + 1] = Entry("card.sell", function() (Func("C_Container", "UseContainerItem"))(bag, slot) end, locked)
        end
    else
        list[#list + 1] = Entry("card.link", function() Insert(link) end)
        list[#list + 1] = Entry("common.close", Close)
    end
end

-- A unit is remembered by its full name and its GUID, never by the token it was held through:
-- "mouseover" is gone the moment the finger is on the card, and "target" may change. A token is
-- used only while it still points at the same unit (the GUID matches); a hidden GUID cannot be
-- compared, so the comparison sits behind a pcall and counts as "not the same".
local TOKENS = { "target", "focus", "mouseover" }

local function SameGuid(token, guid) return UnitGUID(token) == guid end

local function StableToken(model)
    local unit = model.unit
    if unit == "player" then return "player" end
    if not UnitGUID or Secret(model.guid) then return nil end    -- a hidden GUID cannot be matched
    if unit ~= "mouseover" and UnitExists(unit) then
        local ok, same = pcall(SameGuid, unit, model.guid)
        if ok and same then return unit end
    end
    for _, token in ipairs(TOKENS) do
        if UnitExists(token) then
            local ok, same = pcall(SameGuid, token, model.guid)
            if ok and same then return token end
        end
    end
end

-- A button that needs a token (inspect, trade, follow) runs on the stable one, or does nothing
-- and shows why.
local function NeedsToken(fn)
    return function()
        local token = StableToken(current.model)
        if token then fn(token) else InfoCard.Refresh(); return "stay" end
    end
end

-- Target: the secure "target" action on a token that events keep true (the player, target and focus: the card
-- redraws its secure button on PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED), else the exact-name macro. "mouseover"
-- (gone the moment the finger is on the card) and party or raid tokens (they shift with the group) are never written
-- into a secure button: no event here refreshes them. A hidden
-- name cannot go into a macro: then there is nothing to target with (nil), and the button is greyed.
local FRESH_TOKENS = { player = true, target = true, focus = true, pet = true }   -- "pet" is always the current pet

local function TargetAttrs(entry, model)
    local token = StableToken(model)
    if token and FRESH_TOKENS[token] then return { type = "target", unit = token } end
    local name = model.name
    if type(name) == "string" and not Secret(name) then return { type = "macro", macrotext = "/targetexact " .. name } end
end
local targetOpts = { fightLocked = true, reasonKey = "card.afterFightDo", secureFn = TargetAttrs, goneKey = "card.unitGone" }

local function UnitButtons(model)
    local list, unit, name = model.buttons, model.unit, model.name
    if model.page == 2 then
        local needs = { needsToken = true, reasonKey = "card.unitGone" }
        local fight = { needsToken = true, fightLocked = true, reasonKey = "card.afterFightDo" }
        if type(InspectUnit) == "function" then
            list[#list + 1] = Entry("card.inspect", NeedsToken(InspectUnit), needs)
        end
        if type(InitiateTrade) == "function" then
            list[#list + 1] = Entry("card.trade", NeedsToken(InitiateTrade), fight)
        end
        if type(FollowUnit) == "function" then
            list[#list + 1] = Entry("card.follow", NeedsToken(FollowUnit), fight)
        end
        list[#list + 1] = Entry("card.back", function() InfoCard.SetPage(1) end, { keep = true })
        return
    end
    local more = Entry("common.more", function() InfoCard.SetPage(2) end, { keep = true })
    if unit == "player" then
        list[#list + 1] = Entry("common.close", Close)
    elseif model.friendlyPlayer then
        list[#list + 1] = Entry("card.whisper", function()
            local send = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
            if send then send(name) end
        end)
        if model.inParty then
            list[#list + 1] = Entry("card.target", Noop, targetOpts)
        else
            list[#list + 1] = Entry("card.invite", function() (Func("C_PartyInfo", "InviteUnit"))(name) end)
        end
        -- More holds only the actions that exist in this game
        if type(InspectUnit) == "function" or type(InitiateTrade) == "function"
            or type(FollowUnit) == "function" then
            list[#list + 1] = more
        end
    else
        list[#list + 1] = Entry("card.target", Noop, targetOpts)
        list[#list + 1] = Entry("common.close", Close)
    end
end

local function AuraButtons(subject, model)
    local list = model.buttons
    if subject.unit == "player" and model.helpful then
        list[#list + 1] = Entry("card.cancelBuff", function() CancelUnitBuff("player", subject.index) end,
            { fightLocked = true, reasonKey = "card.afterFightDo" })
    end
    list[#list + 1] = Entry("common.close", Close)
end

-- Show on map: the game's own map toggle is refused to add-on code in a fight (and taints the map out of one), so
-- it is the card's secure entry: a secure click on the zone text button the Hud's minimap uses (its own OnClick is
-- ToggleWorldMap). The quest is super-tracked first, in the secure button's PreClick (not a protected call).
local function ZoneButton()
    local cluster = _G.MinimapCluster
    local button = cluster and cluster.ZoneTextButton
    if type(button) == "table" then return button end
end

local function MapAttrs()
    local button = ZoneButton()
    if button then return { type = "click", clickbutton = button } end
end

local function QuestButtons(subject, model)
    local list, id = model.buttons, subject.questID
    list[#list + 1] = Entry("card.showOnMap", Noop, { fightLocked = true, reasonKey = "card.afterFightDo",
        secureFn = MapAttrs, preClick = function()
            local space = C_SuperTrack
            if space and space.SetSuperTrackedQuestID and type(id) == "number" then space.SetSuperTrackedQuestID(id) end
        end })
    list[#list + 1] = Entry("card.untrack", function()
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(id) end
    end)
    list[#list + 1] = Entry("common.close", Close)
end

-- ---------------------------------------------------------------------------------------
-- Building what a subject shows

local function UnitModel(subject, model, unit)
    if not UnitExists(unit) then
        model.buttons[1] = Entry("common.close", Close)
        return
    end
    -- the game's own words for the unit; the unit's kind picks the buttons
    local got = ReadFrom(model, function(tip) return tip:SetUnit(unit) end)
    if not got then
        model.title, model.tr, model.tg, model.tb, model.titled = UnitName(unit), 1, 1, 1, true
    end
    model.unit, model.page = unit, 1
    model.name = UnitFullName(unit)
    model.guid = UnitGUID and UnitGUID(unit)
    model.friendlyPlayer = UnitIsPlayer(unit) and not UnitCanAttack("player", unit)
    model.inParty = unit ~= "player" and UnitInParty and UnitInParty(unit) or false
    UnitButtons(model)
end

-- The rank of a spell ("Rank 3") under its name. The game's own spell tooltip carries it on the title line; when
-- it did not come through, the spell's own subtext is added, so a button never hides which rank it casts.
local function AddRank(model, id)
    local get = Func("C_Spell", "GetSpellSubtext")
    if type(get) ~= "function" or type(id) ~= "number" or Secret(id) then return end
    local ok, text = pcall(get, id)
    if not ok or type(text) ~= "string" or Secret(text) or text == "" then return end
    for _, line in ipairs(model.lines) do
        if (not Secret(line.left) and line.left == text) or (not Secret(line.right) and line.right == text) then return end
    end
    table.insert(model.lines, 1, { hasRight = true, right = text, lr = 1, lg = 1, lb = 1, rr = 0.62, rg = 0.62, rb = 0.62 })
end

local BUILDERS = {}

function BUILDERS.action(subject, model)
    local slot = subject.slot
    model.filled = slot ~= nil and HasAction(slot)
    if model.filled then
        ReadFrom(model, function(tip) return tip:SetAction(slot) end)
        model.icon, model.hasIcon = GetActionTexture(slot), true
        local kind, id = GetActionInfo(slot)
        if kind == "spell" then AddRank(model, id) end
    else
        model.title, model.tr, model.tg, model.tb, model.titled = ns.T("card.emptyButton"), 1, 1, 1, true
        model.lines[1] = { left = ns.T("card.emptyHint"), lr = 0.62, lg = 0.62, lb = 0.62 }
    end
    ActionButtons(subject, model)
end

-- A spell by id (a stance or form button): the game's spell tooltip, the spell's own picture.
function BUILDERS.spell(subject, model)
    local id = subject.spellID
    local got = type(id) == "number" and ReadFrom(model, function(tip) return tip:SetSpellByID(id) end)
    if got then
        local texture = Func("C_Spell", "GetSpellTexture")
        model.icon = texture and texture(id)
        model.hasIcon = model.icon ~= nil
        AddRank(model, id)
    end
    model.buttons[1] = Entry("common.close", Close)
end

-- A pet action by its slot: the game's pet tooltip. An action that can autocast gets an Autocast
-- button saying whether it is on. Toggling autocast is a protected game function, so the button is
-- a secure macro (set out of combat, /petautocasttoggle <name>) under the card's button.
function BUILDERS.petAction(subject, model)
    local index = subject.index
    local name, texture, isToken, _, autoAllowed, autoOn
    if type(index) == "number" and GetPetActionInfo then
        name, texture, isToken, _, autoAllowed, autoOn = GetPetActionInfo(index)
    end
    if not name then
        model.buttons[1] = Entry("common.close", Close)
        return
    end
    ReadFrom(model, function(tip) return tip:SetPetAction(index) end)
    local icon = texture and (isToken and _G[texture] or texture)
    if icon then model.icon, model.hasIcon = icon, true end
    if autoAllowed and not isToken then
        model.buttons[1] = Entry(autoOn and "card.autocastOn" or "card.autocastOff", function() end,
            { fightLocked = true, reasonKey = "card.afterFightDo", secure = "/petautocasttoggle " .. name })
    end
    model.buttons[#model.buttons + 1] = Entry("common.close", Close)
end

-- When the hidden tooltip gave nothing (a card would read "Nothing here"), the item's own name and quality colour
-- still make a title (iPad run 4: a held item slot showed "Nothing here").
local function ItemTitleFallback(model, id, info)
    if model.titled then return end
    local name = info and info.itemName
    local quality = info and info.quality
    local get = Func("C_Item", "GetItemInfo")
    if type(name) ~= "string" and type(get) == "function" then
        local ok, itemName, _, itemQuality = pcall(get, model.link or ("item:" .. tostring(id)))
        if ok then name, quality = itemName, itemQuality end
    end
    if type(name) ~= "string" then return end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    model.title, model.titled = name, true
    model.tr, model.tg, model.tb = 1, 1, 1
    if color then model.tr, model.tg, model.tb = color.r, color.g, color.b end
end

function BUILDERS.item(subject, model)
    local bag, slot = subject.bag, subject.slot
    local info
    if bag and slot then
        local get = Func("C_Container", "GetContainerItemInfo")
        info = get(bag, slot)
        model.link = info and info.hyperlink or Func("C_Container", "GetContainerItemLink")(bag, slot)
        ReadFrom(model, function(tip) return tip:SetBagItem(bag, slot) end)
        local equippable = Func("C_Item", "IsEquippableItem")
        model.equippable = model.link and equippable and equippable(model.link) or false
        model.vendor = MerchantFrame ~= nil and MerchantFrame:IsShown()
    else
        model.link = subject.link
        ReadFrom(model, function(tip) return tip:SetHyperlink(subject.link) end)
    end
    ItemTitleFallback(model, info and info.itemID or (subject.link and tonumber(subject.link:match("item:(%d+)"))), info)
    if info then
        model.itemID = info.itemID
        model.icon, model.hasIcon = info.iconFileID, true
        local color = info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
        if color then model.border = color end
    end
    ItemButtons(subject, model)
end

-- An item column slot with nothing in it: says so and how to fill it. Change item opens the picker's Items tab.
function BUILDERS.railSlot(subject, model)
    local rail = ns.ItemRail
    local cat = rail and rail.SlotCategory and rail.SlotCategory(subject.rail)
    if cat then
        model.title, model.tr, model.tg, model.tb, model.titled = ns.T("items.slot." .. cat), 1, 0.82, 0, true
        model.lines[#model.lines + 1] = { left = ns.T("items.empty"), lr = 1, lg = 1, lb = 1 }
        model.lines[#model.lines + 1] = { left = ns.T("items.fill." .. cat), lr = 0.85, lg = 0.85, lb = 0.85 }
    end
    if ns.Picker and ns.Picker.OpenItem then
        model.buttons[#model.buttons + 1] = Entry("items.change", function() ns.Picker.OpenItem(subject.rail) end)
    end
    model.buttons[#model.buttons + 1] = Entry("common.close", Close)
end

function BUILDERS.unit(subject, model)
    UnitModel(subject, model, subject.unit)
end

function BUILDERS.aura(subject, model)
    local unit, index = subject.unit, subject.index
    local filter = subject.filter or "HELPFUL"
    model.helpful = filter ~= "HARMFUL"
    ReadFrom(model, function(tip) return tip:SetUnitAura(unit, index, filter) end)
    -- the picture: the aura's own, handed straight to the texture
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if ok and data and not Secret(data) then
        local good, icon = pcall(function() return data.icon end)
        if good then model.icon, model.hasIcon = icon, true end
    end
    AuraButtons(subject, model)
end

function BUILDERS.questObjective(subject, model)
    local id = subject.questID
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    model.title, model.tr, model.tg, model.tb, model.titled = title or ns.T("card.nothingHere"), 1, 0.82, 0, true
    local objectives = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    for _, objective in ipairs(objectives or {}) do
        local done = objective.finished
        model.lines[#model.lines + 1] = { left = objective.text,
            lr = done and 0.62 or 1, lg = done and 0.62 or 1, lb = done and 0.62 or 1 }
    end
    QuestButtons(subject, model)
end

function BUILDERS.world(subject, model)
    if UnitExists("mouseover") then
        UnitModel(subject, model, "mouseover")
        return
    end
    -- no unit under the finger: what the game's own tooltip shows (a plant, a chest, a sign)
    if GameTooltip and GameTooltip:IsShown() and CopyLines(GameTooltip, model) then
        model.buttons[1] = Entry("common.close", Close)
        return
    end
    model.buttons[1] = Entry("common.close", Close)
end

-- A colour channel from a hook: a plain number from 0 to 1, else white.
local function Channel(v)
    if Secret(v) then return 1 end
    if type(v) == "number" and v >= 0 and v <= 1 then return v end
    return 1
end

-- Hook lines for this kind. Whatever a hook returns is checked here; a hook that fails or answers
-- something odd is skipped (and remembered when it raised).
local function ApplyLineHooks(subject, model)
    for _, fn in ipairs(lineHooks[subject.kind] or {}) do
        local ok, result = pcall(fn, subject)
        if not ok then
            Remember("card line hook", result)
        elseif type(result) == "string" then
            model.lines[#model.lines + 1] = { left = result, lr = 1, lg = 1, lb = 1 }
        elseif type(result) == "table" and type(result.text) == "string" then
            model.lines[#model.lines + 1] = { left = result.text,
                lr = Channel(result.r), lg = Channel(result.g), lb = Channel(result.b) }
        end
    end
end

local function ApplyActionHooks(subject, model)
    for _, hook in ipairs(actionHooks[subject.kind] or {}) do
        if #model.buttons >= MAX_BUTTONS then break end
        local shown = true
        if hook.isShown then
            local ok, result = pcall(hook.isShown, subject, model)
            if not ok then Remember("card action visibility " .. hook.label, result) end
            shown = ok and result == true
        end
        if shown then model.buttons[#model.buttons + 1] = { label = hook.label, hook = hook.fn } end
    end
end

-- ---------------------------------------------------------------------------------------
-- The card

local function PlaceArrow(side, anchorMidY, y)
    local arrow = card.arrow
    arrow:ClearAllPoints()
    local h = card:GetHeight()
    local at = Clamp(anchorMidY - y, ARROW, math.max(ARROW, h - ARROW))
    if side == "right" then
        arrow:SetPoint("RIGHT", card, "TOPLEFT", 4, -at)
        arrow:SetTexCoord(1, 0, 0, 1)
    else
        arrow:SetPoint("LEFT", card, "TOPRIGHT", -4, -at)
        arrow:SetTexCoord(0, 1, 0, 1)
    end
end

-- The held thing's rectangle in layout units from the screen's top-left. Without one the card
-- opens in the middle of the screen.
local function AnchorRect(anchor)
    local rootW = ns.root:GetWidth()
    if type(rootW) ~= "number" or rootW <= 0 then rootW = REF_W end
    if type(anchor) == "table" and anchor.GetRect then
        local l, b, w, h = anchor:GetRect()
        if type(l) == "number" then
            local k = anchor:GetEffectiveScale() / ns.root:GetEffectiveScale()
            return l * k, REF_H - (b + h) * k, w * k, h * k, rootW
        end
    end
    return rootW / 2, REF_H / 2, 0, 0, rootW
end

local keepOff = {}
local function PlaceCard(anchor)
    local ax, ay, aw, ah, rootW = AnchorRect(anchor)
    local w, h = card:GetSize()
    local x, y, side = InfoCard.Place(w, h, ax, ay, aw, ah, rootW, InfoCard.KeepOff(keepOff, rootW))
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", ns.root, "TOPLEFT", x, -y)
    card.placeX, card.placeY = x, y
    PlaceArrow(side, ay + ah / 2, y)
    card.side = side
end

-- Rows live in the scroll child; a row is a left and a right font string.
local function Row(i)
    local row = card.rows[i]
    if not row then
        row = {}
        for _, key in ipairs({ "left", "right" }) do
            local fs = card.content:CreateFontString(nil, "OVERLAY")
            ns.Kit.SetFont(fs, Kit.FONT_TITLE, BODY_FONT, "")
            fs:SetJustifyV("TOP")
            fs:SetJustifyH(key == "left" and "LEFT" or "RIGHT")
            row[key] = fs
        end
        card.rows[i] = row
    end
    return row
end

-- Writes the rows for `width` units wide; returns the total height. Rows beside the picture are
-- narrower. `top` is how far down the card the body starts.
local function FillRows(model, width, top)
    local y = 0
    for i, line in ipairs(model.lines) do
        local row = Row(i)
        local avail = width
        if card.hasIcon and top + y < 14 + ICON + 4 then avail = width - ICON_SPACE end
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -y)
        row.left:SetWidth(line.hasRight and avail * 0.62 or avail)
        row.left:SetText(line.left)
        row.left:SetTextColor(line.lr, line.lg, line.lb)
        row.left:Show()
        local h = Measure(row.left, BODY_FONT)
        if line.hasRight then
            row.right:ClearAllPoints()
            row.right:SetPoint("TOPRIGHT", card.content, "TOPLEFT", avail, -y)
            row.right:SetWidth(avail * 0.36)
            row.right:SetText(line.right)
            row.right:SetTextColor(line.rr, line.rg, line.rb)
            row.right:Show()
            local hr = Measure(row.right, BODY_FONT)
            if hr > h then h = hr end
        else
            row.right:Hide()
        end
        y = y + h + ROW_GAP
    end
    for i = #model.lines + 1, #card.rows do
        card.rows[i].left:Hide()
        card.rows[i].right:Hide()
    end
    return y
end

local function ButtonClick(button)
    local model = current and current.model
    local entry = model and model.buttons[button.tpIndex]
    if not entry then return end
    if entry.fightLocked and InFight() then return end       -- greyed: nothing to do until the fight ends
    ns.Guard("card button", function()
        local subject = current.subject
        local ok, result
        if entry.hook then ok, result = pcall(entry.hook, subject) else ok, result = pcall(entry.run, subject) end
        if not ok then Remember("card action " .. tostring(entry.label), result) end
        -- a button that could not act ("stay") leaves the card open, greyed with its reason
        if not entry.keep and not (ok and result == "stay") then InfoCard.Hide() end
    end)
end

-- Enabled or greyed by the fight; one reason line for the whole card.
local function ApplyFight()
    local model = current and current.model
    if not model then return end
    local fight = InFight()
    local reason
    for i, entry in ipairs(model.buttons) do
        local button = card.buttons[i]
        local why
        if fight and entry.fightLocked then why = entry.reasonKey
        elseif entry.needsToken and not StableToken(model) then why = "card.unitGone"
        elseif entry.secureFn and not entry.secureFn(entry, model) then why = entry.goneKey or "card.notNow" end
        button:SetEnabledWithReason(why == nil)
        reason = reason or why
    end
    if reason then
        card.reason:SetText(ns.T(reason))
        card.reason:Show()
    else
        card.reason:Hide()
    end
    local extra = reason and 22 or 0
    if card.extra ~= extra then
        card.extra = extra
        card:SetHeight(card.baseHeight + extra)
    end
end

-- The secure button sits over the card button whose entry carries a secure action (entry.secure: a macro text, or
-- entry.secureFn: a function that answers the attributes). It hangs from UIParent, never from the card (R41): a
-- protected frame inside the card, or anchored to it, would make the game protect the card, which must open, close
-- and move in a fight (rule 4). So it is placed with points of its own, worked out over its card button, and its
-- place and attributes change out of combat only. It is put away when a fight starts (PLAYER_REGEN_DISABLED, the
-- last moment the game allows it) and whenever the card closes out of combat; in a fight the card's own button is
-- greyed (those entries are fightLocked), and when the fight ends it is set up again. Nothing here touches it while
-- the add-on loads, so a login in a fight works.
local SECURE_KEYS = { "type", "unit", "macrotext", "item", "clickbutton" }

local function HideSecure()
    if not secureButton or InCombatLockdown() then return end
    if secureButton:IsShown() then secureButton:Hide() end
    secureButton.over, secureButton.preClick = nil, nil
end

-- The card button's rectangle in layout units (left, top, width, height), from where the card was put and where
-- the kit put the button in it (its BOTTOMLEFT on the card's BOTTOMLEFT).
local function ButtonRect(button)
    local point, relative, relativePoint, ox, oy = button:GetPoint(1)
    if point ~= "BOTTOMLEFT" or relative ~= card or relativePoint ~= "BOTTOMLEFT" then return nil end
    local w, h = button:GetSize()
    return card.placeX + ox, card.placeY + card:GetHeight() - oy - h, w, h
end

local function PrepareSecure(model)
    if not secureButton or InFight() or InCombatLockdown() then return end
    local index
    for i, entry in ipairs(model.buttons) do
        if entry.secure or entry.secureFn then index = i end
    end
    if index == nil or not card.placeX then
        HideSecure()
        return
    end
    local entry = model.buttons[index]
    local attrs
    if entry.secureFn then
        attrs = entry.secureFn(entry, model)
    else
        attrs = { type = "macro", macrotext = entry.secure }
    end
    local button = card.buttons[index]
    local left, top, w, h = ButtonRect(button)
    if not attrs or not left then
        HideSecure()
        return
    end
    secureButton:SetScale(ns.root:GetScale())          -- the same units as the layout root
    secureButton:ClearAllPoints()
    secureButton:SetPoint("TOPLEFT", ns.root, "TOPLEFT", left, -top)
    secureButton:SetSize(w, h)
    secureButton:SetFrameLevel(button:GetFrameLevel() + 3)
    for _, key in ipairs(SECURE_KEYS) do secureButton:SetAttribute(key, attrs[key]) end
    secureButton.over, secureButton.preClick = button, entry.preClick
    secureButton:Show()
end

local function Render(model)
    -- the buttons first, with no title text yet: the kit's fit must never read the copied text
    card.title:SetText("")
    local entries = {}
    for i, entry in ipairs(model.buttons) do
        entries[i] = { label = entry.label, onClick = ButtonClick }
    end
    card:SetButtons(entries)
    for i = 1, #entries do card.buttons[i].tpIndex = i end
    -- Task 13: a button whose action cannot be undone (the hearth item's Use) is unlocked by a hold; the
    -- tap after it does the work
    local popups = ns.Popups
    if popups then
        for i = 1, #card.buttons do
            local entry = model.buttons[i]
            if entry and entry.hold then
                popups.HoldButton(card.buttons[i], popups.HOLD_SECONDS, nil,
                    { arm = true, parent = card, label = entry.holdLabel, key = entry.holdKey })
            else
                popups.ReleaseHold(card.buttons[i])
            end
        end
    end

    -- picture
    card.hasIcon = model.hasIcon == true
    card.iconFrame:SetShown(card.hasIcon)
    if card.hasIcon then
        card.iconTexture:SetTexture(model.icon)
        local c = model.border
        if c then card.iconFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        else card.iconFrame:SetBackdropBorderColor(1, 1, 1, 1) end
    end

    -- title
    local inner = card:GetWidth() - 2 * PAD
    card.title:SetWidth(card.hasIcon and inner - ICON_SPACE or inner)
    card.title:SetText(model.title)
    card.title:SetTextColor(model.tr, model.tg, model.tb)
    local titleH = Measure(card.title, 23)
    local top = 14 + titleH + 6

    -- body: laid out full width first; past the limit, again narrower with the bar
    local width = inner
    local total = FillRows(model, width, top)
    local scrolling = total > SCROLL_AT
    if scrolling then
        width = inner - BAR_W
        total = FillRows(model, width, top)
    end
    local bodyH = math.min(total, SCROLL_AT)
    card.content:SetSize(width, math.max(total, 1))
    card.body:ClearAllPoints()
    card.body:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -top)
    card.body:SetSize(width, math.max(bodyH, 1))
    card.body:SetVerticalScroll(0)
    card.scroll:SetShown(scrolling)
    if scrolling then
        card.scroll:ClearAllPoints()
        card.scroll:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD + 4, -top)
        card.scroll:SetSize(BAR_W - 6, bodyH)
        card.scroll:SetMinMaxValues(0, total - bodyH)
        card.scroll:SetValue(0)
        card.maxScroll = total - bodyH
    else
        card.maxScroll = 0
    end

    local height = top + bodyH + 10 + 44 + 14
    card.baseHeight = math.max(height, 140)
    card.extra = 0
    card:SetHeight(card.baseHeight)
    card.reason:ClearAllPoints()
    card.reason:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", PAD, 14 + 44 + 4)
    card.reason:SetWidth(inner)
end

local function BuildFrame()
    if card then return end
    catcher = CreateFrame("Button", nil, ns.root)
    catcher:SetAllPoints(ns.root)
    catcher:SetFrameStrata("DIALOG")
    catcher:RegisterForClicks("AnyDown")
    catcher:SetScript("OnClick", function() InfoCard.Hide() end)
    catcher:Hide()

    card = Kit.Card(ns.root)
    card:SetFrameStrata("DIALOG")
    card:SetFrameLevel(catcher:GetFrameLevel() + 5)
    card:EnableMouse(true)
    card:Hide()
    InfoCard.frame = card
    InfoCard.catcher = catcher

    card.arrow = card:CreateTexture(nil, "OVERLAY")
    card.arrow:SetTexture(ARROW_ART)
    card.arrow:SetSize(ARROW, ARROW)

    card.iconFrame = Kit.Backdrop(card, "tooltip", "tooltip")
    card.iconFrame:SetSize(ICON + 4, ICON + 4)
    card.iconFrame:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD + 2, -14)
    card.iconTexture = card.iconFrame:CreateTexture(nil, "ARTWORK")
    card.iconTexture:SetPoint("TOPLEFT", card.iconFrame, "TOPLEFT", 3, -3)
    card.iconTexture:SetPoint("BOTTOMRIGHT", card.iconFrame, "BOTTOMRIGHT", -3, 3)
    card.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.body = CreateFrame("ScrollFrame", nil, card)
    card.content = CreateFrame("Frame", nil, card.body)
    card.body:SetScrollChild(card.content)
    card.body:EnableMouseWheel(true)
    card.rows = {}

    -- the gold bar on the right; dragging it scrolls the text
    card.scroll = CreateFrame("Slider", nil, card)
    card.scroll:SetOrientation("VERTICAL")
    card.scroll:SetHitRectInsets(-10, -10, 0, 0)
    local thumb = card.scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.72, 0.55, 0.1, 1)
    thumb:SetSize(8, 60)
    card.scroll:SetThumbTexture(thumb)
    card.scroll:SetScript("OnValueChanged", function(_, value) card.body:SetVerticalScroll(value) end)
    card.scroll:Hide()
    InfoCard.scroll = card.scroll
    card.body:SetScript("OnMouseWheel", function(_, delta)
        if not card.scroll:IsShown() then return end
        card.scroll:SetValue(Clamp(card.scroll:GetValue() - delta * 40, 0, card.maxScroll))
    end)

    card.reason = card:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(card.reason, Kit.FONT_TITLE, 13, "")
    card.reason:SetTextColor(0.85, 0.85, 0.85)
    card.reason:SetJustifyH("LEFT")
    card.reason:Hide()
    card.maxScroll, card.extra, card.baseHeight = 0, 0, 140

    card:SetScript("OnHide", function()
        catcher:Hide()
        HideSecure()
    end)
    card:SetScript("OnShow", function() catcher:Show() end)
    -- an open card hands the app's taps back to the game (ruling A30, Signal.lua); after the SetScripts, which
    -- would drop the hooks
    if ns.Signal and ns.Signal.Track then ns.Signal.Track(card) end
end

-- Made while the add-on loads, as every secure frame is; its attributes stay empty until a card needs them.
secureButton = CreateFrame("Button", "TouchPlayCardSecure", UIParent, "SecureActionButtonTemplate")
secureButton:SetFrameStrata("DIALOG")   -- the card's own strata, set once here: never changed in a fight
secureButton:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
secureButton:RegisterForClicks("AnyUp")
secureButton:Hide()
-- what the entry wants done just before the game's action (Show on map super-tracks its quest); never a protected call
secureButton:HookScript("PreClick", function(self)
    if self.preClick then
        local ok, problem = pcall(self.preClick)
        if not ok then Remember("card pre-click", problem) end
    end
end)
-- the card button under it shows the press (polish pass): the finger lands on this secure button, not on it
secureButton:HookScript("OnMouseDown", function(self, mouse)
    if self.over and (mouse == nil or mouse == "LeftButton") then Kit.PressDown(self.over) end
end)
secureButton:HookScript("OnMouseUp", function(self, mouse)
    if self.over and (mouse == nil or mouse == "LeftButton") then Kit.PressUp(self.over) end
end)
secureButton:HookScript("PostClick", function() InfoCard.Hide() end)
InfoCard.secureButton = secureButton

-- ---------------------------------------------------------------------------------------
-- Public

-- subject: { kind = "action", slot = n } | { kind = "spell", spellID = id } | { kind = "petAction", index = n } | { kind = "item", bag = b, slot = s } or { link = ... }
-- | { kind = "unit", unit = ... } | { kind = "aura", unit =, index = } | { kind = "questObjective",
-- questID = } | { kind = "world" }. anchor: the frame that was held (a point, when none).
function InfoCard.Show(subject, anchor)
    if type(subject) ~= "table" then return end
    local build = BUILDERS[subject.kind]
    if not build then return end
    BuildFrame()
    local model = { lines = {}, buttons = {} }
    build(subject, model)
    if not model.titled then
        model.title, model.tr, model.tg, model.tb = ns.T("card.nothingHere"), 1, 1, 1
    end
    ApplyLineHooks(subject, model)
    ApplyActionHooks(subject, model)
    current = { subject = subject, anchor = anchor, model = model }
    Render(model)
    ApplyFight()
    PlaceCard(anchor)
    if not card:IsShown() then Kit.Sound("open") end
    card:Show()
    PrepareSecure(model)
    -- no game tooltip over or beside the card (iPad run 7); the card took what it needed from it above
    if ns.Tooltip then ns.Tooltip.CardOpened() end
end

function InfoCard.Hide()
    -- a closed card starts locked again: no unlock or half-made hold is left on its buttons
    if card and ns.Popups then
        for i = 1, #card.buttons do ns.Popups.ReleaseHold(card.buttons[i]) end
    end
    if card and card:IsShown() then
        card:Hide()
        Kit.Sound("close")
    end
    HideSecure()
    current = nil
end

-- A unit card's second page (Inspect, Trade, Follow) and back: only the buttons change.
function InfoCard.SetPage(page)
    local model = current and current.model
    if not model or not model.unit then return end
    model.page = page
    model.buttons = {}
    UnitButtons(model)
    ApplyActionHooks(current.subject, model)
    Render(model)
    ApplyFight()
    PlaceCard(current.anchor)
    PrepareSecure(model)
end

-- A swipe (Swipe.lua) on a unit card: its second page (+1) or back to the first (-1). Answers whether it turned.
function InfoCard.Turn(dir)
    local model = current and current.model
    if not model or not model.unit or not card:IsShown() then return false end
    local to = dir > 0 and 2 or 1
    if (model.page or 1) == to then return false end
    InfoCard.SetPage(to)
    return true
end

-- Greys or frees the buttons again (the fight, or the unit it was about, changed). The card's height may change with
-- the reason line, so the secure button is placed over its button again (out of combat; PrepareSecure checks).
function InfoCard.Refresh()
    if card and card:IsShown() then
        ApplyFight()
        if current then PrepareSecure(current.model) end
    end
end

function InfoCard.IsShown() return card ~= nil and card:IsShown() end

-- Test and layout helpers: the card's title text, a button by its label, the reason line.
function InfoCard.Title() return card and card.title:GetText() end

function InfoCard.Button(label)
    if not card then return nil end
    for i = 1, card.buttonCount do
        local b = card.buttons[i]
        if b.label:GetText() == label then return b end
    end
end

function InfoCard.ReasonText()
    if card and card.reason:IsShown() then return card.reason:GetText() end
end

-- ---------------------------------------------------------------------------------------
-- Module steps

local function OnFightChange()
    if card and card:IsShown() then
        ApplyFight()
        if current then PrepareSecure(current.model) end
    end
end

-- A fight starts: the secure button goes now, while the game still allows it (the card stays, greyed).
local function OnFightStart()
    HideSecure()
    OnFightChange()
end

function InfoCard:Init()
    BuildFrame()
    -- the world key: a hold on empty ground asks for the card of what is under the finger
    local hold = _G.TouchPlayWorldHold
    if hold then
        hold:HookScript("PostClick", function(_, _, down)
            if down then return end
            ns.Guard("world hold", InfoCard.Show, { kind = "world" }, nil)
        end)
    end
    ns.On("PLAYER_REGEN_DISABLED", OnFightStart)
    ns.On("PLAYER_REGEN_ENABLED", OnFightChange)
    ns.On("PLAYER_TARGET_CHANGED", OnFightChange)
    ns.On("PLAYER_FOCUS_CHANGED", OnFightChange)
end

function InfoCard:Restore()
    InfoCard.Hide()
end
