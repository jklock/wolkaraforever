-- TouchPlay: the game's own popups made for fingers, and a hold for what cannot be undone
-- (rule 11, Task 13; mockups 12, 13, 15, 80, 104).
--
--   * Skin: StaticPopup1..4 get 52 unit buttons and 18 unit text on every OnShow (HookScript, a
--     secure post-hook). Nobody's click handler changes: no SetScript, no SetParent, no attribute
--     on a popup or its buttons. An ordinary popup is restyled at once, in a fight too; a protected
--     one only when the game allows (ns.Queue).
--   * Under-thumb guard: for 0.4 s after a popup appears a separate frame of ours, above the popup,
--     takes the touches, dims the buttons and says why (mockup 12), so a tap already on its way
--     cannot answer a question it never saw. When several popups are up the top one wears "1 of N";
--     a timed popup (the game's dialog.timeleft) gets a thin bar that turns red in the last 10 s
--     and ticks once a second there (feel.tapSounds ~= false).
--   * Hold (R29): when feel.holdRisky is on (default), the accept button of every popup in
--     Popups.RISKY (and the spirit healer's) needs a 0.8 s hold, done by Hold.lua (the generic hold:
--     it fills while the finger stays, the timer only marks it ready, the accept or the unlock runs
--     inside the touch's own release). Popups.HoldButton is an alias for Hold.Button.
--   * Protected accepts (R28): the finished hold of a popup whose accept calls a function the API
--     documentation marks as restricted never calls it, and never calls :Click(), from our code
--     (it would run tainted). It only unlocks: the frame stops taking touches and reads "Tap to
--     confirm" for 3 s, and the player's next real tap lands on the game's own button. An
--     unprotected accept (RepopMe, ...) runs through the game's own button, from the release.
--
-- What each RISKY popup's accept calls (from /tmp/wowui, GameDialogDefs.lua; HasRestrictions is the
-- API documentation's flag for a restricted function):
--   DEATH                    OnButton1 -> RepopMe: no flag, unprotected.
--   RECOVER_CORPSE_INSTANCE  no buttons and no accept (text only): nothing to hold.
--   CONFIRM_LEAVE_BATTLEFIELD OnAccept -> LeaveBattlefield: not in the documentation, taken as unprotected.
--   DELETE_ITEM              OnAccept -> DeleteCursorItem / C_Item.DeleteItem: HasRestrictions, protected path.
--   (DELETE_GOOD_ITEM is not held, R31: typing DELETE is already its confirmation.)
--   ABANDON_QUEST            OnAccept -> C_QuestLog.AbandonQuest: no flag, unprotected.
--   CAMP                     only a Cancel button (CancelLogout); the log out itself starts from the Menu.
--   CONFIRM_BINDER           OnAccept -> C_PlayerInteractionManager.ConfirmationInteraction: no flag, unprotected.
--   XP_LOSS family (spirit healer) -> ConfirmationInteraction: no flag, unprotected.
-- The only popup text read is the spirit healer's (to put its question above the game's cost line), and
-- only when it is a plain string. No timer or OnUpdate runs unless a touch is down, a popup was just shown,
-- or a timed popup is up (the bar's own OnUpdate, 0.1 s steps).

local ADDON_NAME, ns = ...

local Popups = ns.Register("Popups", {})
local Kit = ns.Kit

ns.L["popup.holdRelease"] = "Hold to release spirit"
ns.L["popup.holdReturn"] = "Hold to return"
ns.L["popup.notNow"] = "Not now"
ns.L["popup.holdHome"] = "Hold to go home"
ns.L["popup.corpseAway"] = "Your corpse is %d yards away, free to reach."
ns.L["popup.spiritQuestion"] = "Return to life now?"
ns.L["popup.wake"] = "Buttons wake up after a moment, so a tap already on its way cannot answer."
ns.L["popup.count"] = "%d of %d"

-- R31: DELETE_GOOD_ITEM is not here: typing DELETE is already its confirmation.
Popups.RISKY = { "DEATH", "RECOVER_CORPSE_INSTANCE", "CONFIRM_LEAVE_BATTLEFIELD", "DELETE_ITEM",
    "ABANDON_QUEST", "CAMP", "CONFIRM_BINDER" }
Popups.SPIRIT_HEALER = { "XP_LOSS", "XP_LOSS_NO_SICKNESS_NO_DURABILITY" }
Popups.PROTECTED_ACCEPT = { DELETE_ITEM = true }
Popups.RISKY_ITEMS = { [6948] = "popup.holdHome" }  -- the hearth item, and the words on its idle button
Popups.GUARD_SECONDS, Popups.HOLD_SECONDS = 0.4, 0.8

local BUTTON_H, BUTTON_FONT, TEXT_SIZE = 52, 22, 18
local PINK = "|cffff8070"
local WHITE_TEXT = "|cffffffff"
local WARN = { 1, 0.13, 0.13 }
local GOLD = { 1, 0.82, 0 }
local DIM = { 0, 0, 0, 0.55 }
local TIMER_H, TIMER_RED_SECONDS = 6, 10
local WHITE = "Interface\\Buttons\\WHITE8x8"
local LABELS = { DEATH = "popup.holdRelease", XP_LOSS = "popup.holdReturn",
    XP_LOSS_NO_SICKNESS_NO_DURABILITY = "popup.holdReturn" }

local NEEDS, SPIRIT = {}, {}
for _, which in ipairs(Popups.RISKY) do NEEDS[which] = true end
for _, which in ipairs(Popups.SPIRIT_HEALER) do NEEDS[which], SPIRIT[which] = true, true end

local Plain = ns.Plain

-- Layout units to the popups' own space (they are children of UIParent, not of our root).
local function Unit(n) return n * (ns.root and ns.root:GetScale() or 1) end

-- The hold lives in Hold.lua (Task 14 split it out); the old names stay as aliases.
local Hold = ns.Hold
Popups.HoldEnabled, Popups.HoldButton, Popups.ReleaseHold = Hold.Enabled, Hold.Button, Hold.Release
Popups.RefreshHold, Popups.ReleaseAllHolds = Hold.Refresh, Hold.ReleaseAll

function Popups.NeedsHold(which) return Plain(which) and NEEDS[which] == true and Popups.HoldEnabled() end
function Popups.ItemNeedsHold(itemID) return Plain(itemID) and Popups.RISKY_ITEMS[itemID] ~= nil and Popups.HoldEnabled() end
-- The words on an item's idle hold button ("Hold to go home"), or nil.
function Popups.ItemLabel(itemID)
    local key = Plain(itemID) and Popups.RISKY_ITEMS[itemID]
    return key and ns.T(key) or nil
end

-- ---------------------------------------------------------------------------------------
-- The popups

local hooked, saved, guards, fresh = {}, {}, {}, {}

local function ButtonOf(dialog, i)
    if dialog.GetButton then return dialog:GetButton(i) end
    return _G[dialog:GetName() .. "Button" .. i]
end

local function TextOf(dialog)
    return dialog.GetTextFontString and dialog:GetTextFontString() or dialog.Text
end

-- Keeps the game's own font to give back, and writes the new size only when it differs.
local function SetFontOnce(region, record, key, size)
    if not region or not region.SetFont then return end
    if not record[key] then record[key] = { region:GetFont() } end
    local _, current = region:GetFont()
    if current ~= size then ns.Kit.SetFont(region, Kit.FONT_TITLE, size, "") end
end

local function ApplySkin(dialog)
    if not dialog:IsShown() then return end
    local s = saved[dialog]
    if not s then s = { buttons = {} }; saved[dialog] = s end
    SetFontOnce(TextOf(dialog), s, "font", Unit(TEXT_SIZE))
    for i = 1, 5 do
        local b = i < 5 and ButtonOf(dialog, i) or dialog.ExtraButton
        if b then
            local r = s.buttons[b]
            if not r then r = { height = b:GetHeight() }; s.buttons[b] = r end
            if b:GetHeight() ~= Unit(BUTTON_H) then b:SetHeight(Unit(BUTTON_H)) end
            SetFontOnce(b.GetFontString and b:GetFontString(), r, "font", Unit(BUTTON_FONT))
        end
    end
end

local function UnSkin(dialog)
    local s = saved[dialog]
    if not s then return end
    saved[dialog] = nil
    local text = TextOf(dialog)
    if text and s.font and s.font[1] then text:SetFont(unpack(s.font)) end
    for b, r in pairs(s.buttons) do
        if r.height and r.height > 0 then b:SetHeight(r.height) end
        local fs = b.GetFontString and b:GetFontString()
        if fs and r.font and r.font[1] then fs:SetFont(unpack(r.font)) end
    end
end

-- Buttons 52 units tall and text 18 units, never touching what a button does. An ordinary popup is
-- restyled at once, in a fight too; a protected one waits until the game allows (ns.Queue).
function Popups.Skin(dialog)
    if dialog:IsProtected() then
        ns.Queue("popup skin " .. tostring(dialog:GetName()), function() ApplySkin(dialog) end)
    else
        ApplySkin(dialog)
    end
end

-- The accept of a popup whose accept is not restricted runs through the game's own button, inside the
-- release of the touch (R29).
local function AcceptThrough(h)
    h.button:Click()
    local dialog = h.opts.dialog
    if dialog and dialog:IsShown() then Relock(h) end       -- a popup that stays (XP_LOSS asks twice)
end

-- ---------------------------------------------------------------------------------------
-- The guard frame: the 0.4 s that takes touches, dims the buttons and says why; the "1 of N" badge; the time bar

local function TapSounds()
    local feel = ns.db and ns.db.feel
    return not (type(feel) == "table" and feel.tapSounds == false)
end

local function StopTimer(g)
    g.timerBar:SetScript("OnUpdate", nil)
    g.timerBar:Hide()
    g.total = nil
end

-- A timed popup's own time left (the game counts dialog.timeleft down): the bar shrinks, turns red in the
-- last 10 seconds and ticks once per second there. Run from the bar's own OnUpdate, which exists only while a
-- timed popup is shown (the game calls Resize every frame only for popups with an expiry text, not for all).
local function TimerStep(g)
    local left = g.dialog.timeleft
    if not Plain(left) or type(left) ~= "number" or left <= 0 or not g.total then StopTimer(g); return end
    local frac = left / g.total
    frac = frac > 1 and 1 or frac
    g.frac = frac
    local width = math.max(1, math.floor(g.dialog:GetWidth() * frac))
    if g.fillWidth ~= width then g.fillWidth = width; g.fill:SetWidth(width) end
    local red = left <= TIMER_RED_SECONDS
    if g.red ~= red then
        g.red = red
        if red then g.fill:SetVertexColor(WARN[1], WARN[2], WARN[3]) else g.fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    if red then
        local second = math.ceil(left)
        if second ~= g.lastSecond then
            g.lastSecond = second
            if TapSounds() then Kit.Sound("tap") end
        end
    end
end

local function StartTimer(g, left)
    g.total, g.lastSecond, g.red, g.fillWidth, g.acc = left, nil, nil, nil, 0
    g.timerBar:SetScript("OnUpdate", g.onUpdate)
    g.timerBar:Show()
    TimerStep(g)
end

local function Guard(dialog)
    local g = guards[dialog]
    if g then return g end
    g = CreateFrame("Frame", nil, UIParent)
    g.dialog = dialog
    g:SetAllPoints(dialog)
    g:SetFrameStrata("FULLSCREEN_DIALOG")
    g:SetFrameLevel(400)
    g.note = g:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(g.note, Kit.FONT_TITLE, 16, "")
    g.note:SetTextColor(1, 1, 1)
    g.note:Hide()
    g.wake = g:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(g.wake, Kit.FONT_TITLE, 16, "")
    g.wake:SetTextColor(0.62, 0.62, 0.62)
    g.wake:SetJustifyH("CENTER")
    g.wake:SetPoint("TOP", dialog, "BOTTOM", 0, -18)
    g.wake:SetText(ns.T("popup.wake"))
    g.wake:Hide()
    g.badge = g:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(g.badge, Kit.FONT_TITLE, 18, "")
    g.badge:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    g.badge:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, -10)
    g.badge:Hide()
    g.dims = {}
    for i = 1, 5 do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(DIM[1], DIM[2], DIM[3], DIM[4])
        t:Hide()
        g.dims[i] = t
    end
    local bar = CreateFrame("Frame", nil, g)
    bar:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -4)
    bar:SetPoint("TOPRIGHT", dialog, "BOTTOMRIGHT", 0, -4)
    bar:SetHeight(TIMER_H)
    bar:EnableMouse(false)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetColorTexture(0, 0, 0, 0.7)
    g.fill = bar:CreateTexture(nil, "ARTWORK")
    g.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    g.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    g.fill:SetTexture(WHITE)
    g.fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    bar:Hide()
    g.timerBar = bar
    g.onUpdate = function(_, elapsed)
        g.acc = (g.acc or 0) + elapsed
        if g.acc < 0.1 then return end
        g.acc = 0
        TimerStep(g)
    end
    g.expire = function()
        g.timer = nil
        g:EnableMouse(false)
        g.wake:Hide()
        for i = 1, #g.dims do g.dims[i]:Hide() end
    end
    guards[dialog] = g
    return g
end

function Popups.GuardFor(dialog) return guards[dialog] end

-- "1 of N" on the top shown popup when more than one is up; the others are never hidden or moved.
local function UpdateBadges()
    local count, top = 0, nil
    for i = 1, 4 do
        local d = _G["StaticPopup" .. i]
        if d and hooked[d] and d:IsShown() then
            count = count + 1
            top = top or d
        end
    end
    for _, g in pairs(guards) do
        if g.badge:IsShown() then g.badge:Hide() end
    end
    if count > 1 and ns.IsActive() then
        local g = Guard(top)
        g.badge:SetText(ns.T("popup.count", 1, count))
        g.badge:Show()
    end
end

local function SpiritExtras(dialog, g, b1)
    -- the question in white, then the game's own cost line in its own colour (the text is read only when it is plain)
    local text = TextOf(dialog)
    if text and text.GetText then
        local original = text:GetText()
        local question = ns.T("popup.spiritQuestion")
        -- a hidden (secret) string is never compared or searched: it is left as the game wrote it
        if Plain(original) and type(original) == "string" and original ~= ""
            and not original:find(question, 1, true) then
            text:SetText(WHITE_TEXT .. question .. "|r\n" .. PINK .. original .. "|r")
        end
    end
    local b2 = ButtonOf(dialog, 2)
    if b2 and Popups.HoldEnabled() then b2:SetText(ns.T("popup.notNow")) end
    local yards = ns.Corpse and ns.Corpse.CurrentYards and ns.Corpse.CurrentYards()
    if yards and b1 then
        g.note:ClearAllPoints()
        g.note:SetPoint("BOTTOM", b1, "TOP", 0, 8)
        g.note:SetText(ns.T("popup.corpseAway", yards))
        g.note:Show()
    end
end

local function Shown(dialog)
    fresh[dialog] = true
    Popups.Skin(dialog)
    local g = Guard(dialog)
    if g.timer then g.timer:Cancel() end
    g.note:Hide()
    g:Show()
    g:EnableMouse(true)
    g.timer = C_Timer.NewTimer(Popups.GUARD_SECONDS, g.expire)
    -- mockup 12: the buttons dim, and a line says why, until the guard is down
    for i = 1, #g.dims do
        local b = i < 5 and ButtonOf(dialog, i) or dialog.ExtraButton
        local t = g.dims[i]
        if b and b:IsShown() then
            t:ClearAllPoints()
            t:SetAllPoints(b)
            t:Show()
        else
            t:Hide()
        end
    end
    g.wake:SetWidth(Unit(340))
    g.wake:Show()
    local left = dialog.timeleft
    if Plain(left) and type(left) == "number" and left > 0 then StartTimer(g, left) else StopTimer(g) end
    local which = dialog.which
    local b1 = ButtonOf(dialog, 1)
    if b1 then
        if Popups.NeedsHold(which) and b1:IsShown() then
            local arm = Popups.PROTECTED_ACCEPT[which] == true
            Popups.HoldButton(b1, Popups.HOLD_SECONDS, (not arm) and AcceptThrough or nil,
                { arm = arm, dialog = dialog, label = LABELS[which] and ns.T(LABELS[which]) or nil })
        else
            Popups.ReleaseHold(b1)
        end
    end
    if Plain(which) and SPIRIT[which] then SpiritExtras(dialog, g, b1) end
    UpdateBadges()
end

local function Closed(dialog)
    fresh[dialog] = nil
    local g = guards[dialog]
    if g then
        if g.timer then g.timer:Cancel(); g.timer = nil end
        g:EnableMouse(false)
        g.note:Hide()
        g.wake:Hide()
        for i = 1, #g.dims do g.dims[i]:Hide() end
        StopTimer(g)
        g:Hide()
    end
    local b1 = ButtonOf(dialog, 1)
    if b1 then Popups.ReleaseHold(b1) end
    UpdateBadges()
end

local function OnShow(dialog)
    if ns.IsActive() then ns.Guard("popup show", Shown, dialog) end
end

local function OnHide(dialog)
    ns.Guard("popup hide", Closed, dialog)
end

local function RefreshButton(button)
    Popups.RefreshHold(button)
end

local function HookAll()
    for i = 1, 4 do
        local dialog = _G["StaticPopup" .. i]
        if dialog and not hooked[dialog] then
            hooked[dialog] = true
            dialog:HookScript("OnShow", OnShow)
            dialog:HookScript("OnHide", OnHide)
            -- the game lays the popup out right after showing it: look once more then (a timed popup's
            -- Resize comes every frame, so only the first one counts)
            if type(dialog.Resize) == "function" then
                hooksecurefunc(dialog, "Resize", function(self)
                    if fresh[self] and ns.IsActive() then fresh[self] = nil; Popups.Skin(self) end
                end)
            end
            for k = 1, 4 do
                local b = ButtonOf(dialog, k)
                if b then
                    for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
                        if type(b[method]) == "function" then hooksecurefunc(b, method, RefreshButton) end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------
-- Module steps

function Popups:Init() HookAll() end

function Popups:Layout()
    HookAll()
    for dialog in pairs(hooked) do
        if dialog:IsShown() then Popups.Skin(dialog) end
    end
end

function Popups:Restore()
    Popups.ReleaseAllHolds()
    for dialog in pairs(guards) do Closed(dialog) end
    for dialog in pairs(hooked) do UnSkin(dialog) end
end
