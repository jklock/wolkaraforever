-- TouchPlay: the animation clock, /touch perf and the pause card (rule 7, scope section 6; mockups 90, 91).
--
--   * ns.Animate(frame, kind, seconds [, alpha]) moves a plain frame's alpha: "fadein" (to 1, shows the frame),
--     "fadeout" (to 0, then hides it and gives it back its full alpha), "fadeto" (to `alpha`). One shared frame holds the
--     only OnUpdate; it is set when the first animation starts and taken away when the last one ends, so an idle
--     screen has none. Reduce motion makes every kind instant. ns.Animate.Cancel(frame) stops one where it is.
--   * /touch perf prints the add-on's recent average and peak time (C_AddOnProfiler), "within budget" under 0.5 ms.
--   * The pause card (mockup 91): "Touch buttons are paused", why, "Turn touch back on" (switches Touch on in the game's
--     add-on list and reloads, through a secure /reload macro button made at load) and "Not now". It lives on
--     ns.moveRoot, which a pause never hides, next to the Interact and Jump faces. The words are a plain panel; the
--     two buttons are a frame of their own, which the game protects (it holds the secure /reload): after a pause in
--     a fight the words show at once and the buttons when the fight ends.
--   * The game's own performance check (Blizzard_AddOnPerformance) opens the static popup
--     ADDON_PERFORMANCE_SPECIFIC_ERROR naming the add-on (Disable / Ignore). We watch StaticPopup_Show, never touch
--     that popup, and show only the words of our card beside it, saying what its buttons do. It does not pause us
--     (R39): the player decides there. Disable reloads with Touch off; Ignore keeps Touch on, and our words go when
--     the popup hides. ADDON_ACTION_FORBIDDEN for the add-on pauses it, with the plain "hit a problem" wording.
--
-- Nothing here acts for the player: no cast, target, use, loot or interact call, and no ReloadUI from our own code.

local ADDON_NAME, ns = ...

local Kit = ns.Kit
local Perf = ns.Register("Perf", {})

local BUDGET_MS = 0.5

ns.L["perf.line"] = "Touch is using %.2f ms on average (peak %.2f ms): %s."
ns.L["perf.within"] = "within budget"
ns.L["perf.over"] = "over budget (0.5 ms)"
ns.L["perf.unavailable"] = "The performance readout is not available in this client."
ns.L["pause.title"] = "Touch buttons are paused"
ns.L["pause.reason.game"] = "The game switched off the touch add-on because it was running slowly."
ns.L["pause.reason.error"] = "Touch buttons hit a problem and stopped."
ns.L["pause.tail"] = "Your normal bars are back, so you can still play with the walk stick, Jump and Interact."
ns.L["pause.turnOn"] = "Turn touch back on"
ns.L["pause.notNow"] = "Not now"
ns.L["perf.popup.title"] = "Touch is running slowly"
ns.L["perf.popup.text"] = "The game asks whether to switch the touch add-on off. Disable switches it off and reloads. Ignore keeps touch on."

-- ---------------------------------------------------------------------------------------
-- The animation clock

local clock = CreateFrame("Frame")
local active, activeCount = {}, 0          -- the running animations, packed
local byFrame = {}                         -- frame -> its animation
local spare = {}                           -- finished animation records, kept for the next one

local KINDS = { fadein = true, fadeout = true, fadeto = true }

-- Show and Hide are protected only for a secure frame, and only in a fight.
local function CanShow(frame)
    return not (frame.IsProtected and frame:IsProtected() and InCombatLockdown())
end

local function Release(a)
    byFrame[a.frame] = nil
    a.frame = nil
    spare[#spare + 1] = a
end

-- Puts the frame at its end state. The record is released (or was never kept) before Hide runs, because an OnHide
-- script may start another animation on the same frame: it must not find this finished record still in use.
local function Finish(a, kept)
    local frame, to, hide = a.frame, a.to, a.hide
    if kept then Release(a) end
    frame:SetAlpha(to)
    if hide and CanShow(frame) then
        frame:Hide()
        frame:SetAlpha(1)
    end
end

local function Step(_, elapsed)
    local i = 1
    while i <= activeCount do
        local a = active[i]
        a.t = a.t + elapsed
        local done = a.t >= a.seconds
        if done then
            active[i] = active[activeCount]
            active[activeCount] = nil
            activeCount = activeCount - 1
            Finish(a, true)
        else
            a.frame:SetAlpha(a.from + (a.to - a.from) * (a.t / a.seconds))
            i = i + 1
        end
    end
    if activeCount == 0 then clock:SetScript("OnUpdate", nil) end
end

local function Remove(frame)
    local a = byFrame[frame]
    if not a then return false end
    for i = 1, activeCount do
        if active[i] == a then
            active[i] = active[activeCount]
            active[activeCount] = nil
            activeCount = activeCount - 1
            break
        end
    end
    Release(a)
    if activeCount == 0 then clock:SetScript("OnUpdate", nil) end
    return true
end

local function Animate(frame, kind, seconds, alpha)
    if not KINDS[kind] then error("TouchPlay: unknown animation " .. tostring(kind), 2) end
    Remove(frame)
    local to = kind == "fadein" and 1 or (kind == "fadeout" and 0 or alpha or 0)
    local from
    if kind == "fadein" and not frame:IsShown() then
        -- coming from nothing: shown at alpha 0, then up (a secure frame in a fight keeps its alpha)
        if CanShow(frame) then
            frame:SetAlpha(0)
            frame:Show()
        end
    end
    from = frame:GetAlpha()
    if ns.ReduceMotion() or not seconds or seconds <= 0 or from == to then
        local a = { frame = frame, to = to, hide = kind == "fadeout" }
        Finish(a)
        return
    end
    local a = table.remove(spare) or {}
    a.frame, a.from, a.to, a.t, a.seconds, a.hide = frame, from, to, 0, seconds, kind == "fadeout"
    byFrame[frame] = a
    activeCount = activeCount + 1
    active[activeCount] = a
    if activeCount == 1 then clock:SetScript("OnUpdate", Step) end
end

ns.Animate = setmetatable({
    Cancel = function(frame) Remove(frame) end,
}, { __call = function(_, ...) return Animate(...) end })

function ns.Animating() return activeCount end

-- ---------------------------------------------------------------------------------------
-- /touch perf

-- The recent average and the peak in milliseconds, or nil when this client cannot tell (no profiler, it is off, or
-- the numbers are hidden).
function Perf.Readout()
    local api, metric = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if type(api) ~= "table" or type(api.GetAddOnMetric) ~= "function" or type(metric) ~= "table" then return nil end
    if metric.RecentAverageTime == nil or metric.PeakTime == nil then return nil end
    if type(api.IsEnabled) == "function" then
        local ok, enabled = pcall(api.IsEnabled)
        if ok and not enabled then return nil end
    end
    local okA, recent = pcall(api.GetAddOnMetric, ADDON_NAME, metric.RecentAverageTime)
    local okB, peak = pcall(api.GetAddOnMetric, ADDON_NAME, metric.PeakTime)
    if not (okA and okB) or not ns.Plain(recent) or not ns.Plain(peak) then return nil end
    if type(recent) ~= "number" or type(peak) ~= "number" then return nil end
    return recent, peak
end

function Perf.Print()
    local recent, peak = Perf.Readout()
    if not recent then
        ns.Print(ns.T("perf.unavailable"))
        return
    end
    ns.Print(ns.T("perf.line", recent, peak, ns.T(recent < BUDGET_MS and "perf.within" or "perf.over")))
end

-- ---------------------------------------------------------------------------------------
-- The pause card (mockup 91: the panel 690 x 176 at (338, 147), the two buttons 286 x 47 under it)

local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 338, 147, 690, 176
local BUTTON_W, BUTTON_H, BUTTON_TOP = 286, 47, 198
local GOLD = { 1, 0.82, 0 }

-- The words: a plain frame, so they show in a fight too.
local panel = Kit.Backdrop(ns.moveRoot, "gold", "dark")
panel:SetSize(PANEL_W, PANEL_H)
panel:SetFrameStrata("FULLSCREEN_DIALOG")
panel:SetFrameLevel(100)
panel:EnableMouse(true)
panel:Hide()
ns.Anchor(panel, "TL", PANEL_X, PANEL_Y)
Perf.panel = panel

local title = panel:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(title, Kit.FONT_TITLE, 24, "")
title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
title:SetJustifyH("LEFT")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 25, -20)
title:SetText(ns.T("pause.title"))

local body = panel:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(body, Kit.FONT_TITLE, 18, "")
body:SetTextColor(1, 1, 1)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetWidth(PANEL_W - 50)
body:SetPoint("TOPLEFT", panel, "TOPLEFT", 25, -66)

-- The two buttons under the words. "Turn touch back on" is a secure /reload, so the game protects this frame: it
-- shows and hides out of combat only.
local card = CreateFrame("Frame", "TouchPlayPauseCard", ns.moveRoot)
card:SetSize(PANEL_W, BUTTON_H)
card:SetFrameStrata("FULLSCREEN_DIALOG")
card:SetFrameLevel(100)
card:EnableMouse(false)
card:Hide()
ns.Anchor(card, "TL", PANEL_X, PANEL_Y + BUTTON_TOP)
Perf.card = card

local turnOn = Kit.RedButton(card, BUTTON_W, BUTTON_H, ns.T("pause.turnOn"))
turnOn:SetPoint("TOPLEFT", card, "TOPLEFT", 42, 0)
local notNow = Kit.RedButton(card, BUTTON_W, BUTTON_H, ns.T("pause.notNow"))
notNow:SetPoint("TOPLEFT", card, "TOPLEFT", 362, 0)
Perf.turnOn, Perf.notNow = turnOn, notNow

-- The red button is the picture; this secure button over it does the /reload. It is made here, at load, because a
-- reload asked for from our own code in a fight would be refused. Before the secure macro runs (PreClick) the add-on
-- is switched on in our saved setting and in the game's add-on list, so the interface that loads is the touch screen.
local reload = CreateFrame("Button", "TouchPlayPauseReload", card, "SecureActionButtonTemplate")
reload:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
reload:SetAllPoints(turnOn)
reload:SetFrameLevel(turnOn:GetFrameLevel() + 2)
reload:RegisterForClicks("AnyUp")
reload:SetAttribute("type", "macro")
reload:SetAttribute("macrotext", "/reload")
reload:HookScript("PreClick", function()
    if ns.db then ns.db.enabled = true end
    local list = C_AddOns
    if list and list.EnableAddOn then pcall(list.EnableAddOn, ADDON_NAME) end
end)
Kit.AddPress(reload, "rect", turnOn)       -- the red button's own press look, lit by the secure button
Perf.reloadButton = reload

local buttonsWanted = false        -- a pause in a fight: the buttons show when it ends
local explaining                   -- the game's performance popup our words stand beside (R39)

local function HideButtons()
    buttonsWanted = false
    if not card:IsShown() then return end
    if InCombatLockdown() then
        ns.Queue("pause buttons", function() if not panel:IsShown() then card:Hide() end end)
    else
        card:Hide()
    end
end

local function Hide()
    explaining = nil
    ns.Animate.Cancel(panel)
    panel:SetAlpha(1)
    panel:Hide()
    HideButtons()
end
Perf.Hide = Hide
notNow:SetScript("OnClick", Hide)

-- The buttons show with the words; in a fight they wait for its end (the game protects them).
local function ShowButtons()
    if InCombatLockdown() then
        buttonsWanted = true
    else
        buttonsWanted = false
        card:Show()
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if buttonsWanted and panel:IsShown() and not explaining then ShowButtons() end
end, true)

-- kind: "game" (the game switched the add-on off) or anything else (an error in the add-on).
-- The words as the pause card: in their mockup place, above everything, taking touches (nothing under them acts).
local function WordsAsCard()
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    ns.Anchor(panel, "TL", PANEL_X, PANEL_Y)
end

-- The words beside the game's popup: hung under its bottom edge (or below y 340 when it cannot be found), no higher
-- than its strata, taking no touch, so its Disable and Ignore are never covered.
local POPUP_GAP, BELOW_POPUP_Y = 12, 340
local function WordsBesidePopup(dialog)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(false)
    if type(dialog) == "table" and dialog.GetBottom then
        panel:ClearAllPoints()
        panel:SetPoint("TOP", dialog, "BOTTOM", 0, -POPUP_GAP)
    else
        ns.Anchor(panel, "TL", PANEL_X, BELOW_POPUP_Y)
    end
end

function Perf.ShowCard(kind)
    explaining = nil
    WordsAsCard()
    local reason = ns.T(kind == "game" and "pause.reason.game" or "pause.reason.error")
    title:SetText(ns.T("pause.title"))
    body:SetText(reason .. " " .. ns.T("pause.tail"))
    ns.Animate(panel, "fadein", 0.2)
    ShowButtons()
end
ns.ShowNotice = Perf.ShowCard

-- The words only, beside the game's performance popup (R39): what its two buttons do. Nothing is paused.
function Perf.ShowExplanation(dialog)
    explaining = dialog or true
    WordsBesidePopup(dialog)
    title:SetText(ns.T("perf.popup.title"))
    body:SetText(ns.T("perf.popup.text"))
    HideButtons()
    ns.Animate(panel, "fadein", 0.2)
end

function Perf.IsExplaining() return explaining ~= nil and panel:IsShown() end

function Perf.CardTitle() return title:GetText() end
function Perf.CardText() return body:GetText() end

-- ---------------------------------------------------------------------------------------
-- The game's own checks

-- The game's performance check opens ADDON_PERFORMANCE_SPECIFIC_ERROR with the add-on's name as the text argument and as
-- the data (AddOnPerformance.lua). The popup is the game's: it is only read here, never pressed, hidden or changed.
local PERFORMANCE_POPUP = "ADDON_PERFORMANCE_SPECIFIC_ERROR"

-- The popup that is up for `which` (the game's own finder, else its four popup frames).
local function FindPopup(which, data)
    if type(StaticPopup_FindVisible) == "function" then
        local ok, dialog = pcall(StaticPopup_FindVisible, which, data)
        if ok and dialog then return dialog end
    end
    for i = 1, 4 do
        local dialog = _G["StaticPopup" .. i]
        if dialog and dialog.which == which and dialog:IsShown() then return dialog end
    end
end

local hookedPopups = {}

-- The game's popup went (Ignore, Escape, or Disable before its reload): our words go with it.
local function OnPopupHidden(dialog)
    if explaining == dialog then Hide() end
end

local function OnPopupShown(which, text, _, data)
    if which ~= PERFORMANCE_POPUP then return end
    if not (ns.Plain(text) and ns.Plain(data)) or (text ~= ADDON_NAME and data ~= ADDON_NAME) then return end
    if not ns.IsActive() then return end
    ns.RememberError("The game's performance check named " .. ADDON_NAME)
    local dialog = FindPopup(which, data)
    if dialog and not hookedPopups[dialog] and dialog.HookScript then
        hookedPopups[dialog] = true
        dialog:HookScript("OnHide", OnPopupHidden)
    end
    Perf.ShowExplanation(dialog)
end
if type(StaticPopup_Show) == "function" then
    hooksecurefunc("StaticPopup_Show", function(...) pcall(OnPopupShown, ...) end)
end

ns.On("ADDON_ACTION_FORBIDDEN", function(who, what)
    if not ns.Plain(who) or who ~= ADDON_NAME then return end
    ns.lastError = "ADDON_ACTION_FORBIDDEN: " .. (ns.Plain(what) and tostring(what) or "?")
    ns.RememberError(ns.lastError)
    ns.Pause("forbidden", "error")
end, true)

-- Blocked (a protected call in a fight) is the add-on's own queue to fix: kept for the Mac to read, no pause.
ns.On("ADDON_ACTION_BLOCKED", function(who, what)
    if not ns.Plain(who) or who ~= ADDON_NAME then return end
    ns.RememberError("ADDON_ACTION_BLOCKED: " .. (ns.Plain(what) and tostring(what) or "?"))
end, true)

-- ---------------------------------------------------------------------------------------
-- Module steps

-- Layout runs only when Touch is on and not paused: a card left over from before is put away (the words beside a
-- performance popup that is still up stay).
function Perf:Layout()
    if not Perf.IsExplaining() then Hide() end
end
