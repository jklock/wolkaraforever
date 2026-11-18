-- TouchPlay: the hold. A frame over a button that takes the touches until the finger has stayed
-- long enough (rule 11, R28, R29). Used by the risky popups (Popups.lua), the hearth item's card
-- (InfoCard.lua) and Menu > Log out (Menu.lua).
--
--   * The press must last Hold.SECONDS (0.8 by default). The timer only marks the hold ready ("Let go
--     to confirm"); the accept, or the unlock, runs inside the touch's own release (R29).
--   * Letting go early shows "Hold to confirm"; sliding off cancels.
--   * opts.arm (R28): the release only unlocks. The frame stops taking touches and reads "Tap to
--     confirm" for 3 s, and the player's next real tap lands on the button underneath, which is a
--     protected action our code never calls (it would run tainted).
--   * With feel.holdRisky off, Hold.Button gives nothing back and the button is a plain tap.
-- No timer or OnUpdate runs unless a touch is down.

local ADDON_NAME, ns = ...

local Hold = ns.Register("Hold", {})
local Kit = ns.Kit

ns.L["popup.hold"] = "Hold to confirm"
ns.L["popup.tapConfirm"] = "Tap to confirm"
ns.L["popup.letGo"] = "Let go to confirm"

Hold.SECONDS = 0.8

local MESSAGE_SECONDS, ARMED_SECONDS, TICK = 1.2, 3, 0.05
local WHITE = "Interface\\Buttons\\WHITE8x8"

local Plain = ns.Plain

-- The hold needs the add-on on and the setting on (default on).
function Hold.Enabled()
    if not ns.IsActive() then return false end
    local feel = ns.db and ns.db.feel
    local on
    if type(feel) == "table" then on = feel.holdRisky end
    if type(on) ~= "boolean" then
        on = ns.Contract and ns.Contract.FEEL_DEFAULTS and ns.Contract.FEEL_DEFAULTS.holdRisky
        if on == nil then on = true end
    end
    return on
end

-- The hold: a frame over a button that takes the touches until the finger has stayed long enough

local holds = {}                 -- button -> hold (reused)

local function CancelPress(h)
    if h.timer then h.timer:Cancel(); h.timer = nil end
    if h.ticker then h.ticker:Cancel(); h.ticker = nil end
    h.pressAt, h.progress, h.ready = nil, 0, false
    h.bar:Hide()
end

-- Only changes what changed: the game enables and disables its buttons often (DEATH does it every frame).
local function Paint(h)
    local text = h.message or (h.ready and ns.T("popup.letGo")) or (h.armed and ns.T("popup.tapConfirm")) or h.idle
    local on = (h.active and text ~= nil and h.button:IsEnabled()) and true or false
    if on and h.painted ~= text then h.painted = text; h.face.label:SetText(text) end
    if h.face:IsShown() ~= on then h.face:SetShown(on) end
    local mouse = (h.active and not h.armed) and true or false
    if h.mouseOn ~= mouse then h.mouseOn = mouse; h:EnableMouse(mouse) end
end

local function Relock(h)
    if h.armTimer then h.armTimer:Cancel(); h.armTimer = nil end
    h.armed = false
    Paint(h)
end

-- R29: the 0.8 s timer only marks the hold ready (the fill is full, the label says "Let go to confirm").
-- Nothing runs from the timer: the accept, or the unlock, runs inside the touch's own OnMouseUp.
local function Ready(h)
    h.timer = nil
    if h.ticker then h.ticker:Cancel(); h.ticker = nil end
    h.ready, h.progress = true, 1
    h.bar:SetWidth(math.max(1, h:GetWidth()))
    Paint(h)
end

local function Complete(h)
    CancelPress(h)
    if h.opts.arm then
        h.armed = true
        h.armTimer = C_Timer.NewTimer(ARMED_SECONDS, h.relock)
    end
    Paint(h)
    if h.onDone then ns.Guard("popup hold", h.onDone, h) end
end

local function Tick(h)
    if not h.pressAt then return end
    local p = (GetTime() - h.pressAt) / h.seconds
    h.progress = p < 0 and 0 or (p > 1 and 1 or p)
    h.bar:SetWidth(math.max(1, h:GetWidth() * h.progress))
end

local function Press(h)
    if not h.active or h.armed or not h.button:IsEnabled() then return end
    CancelPress(h)
    if h.msgTimer then h.msgTimer:Cancel(); h.msgTimer = nil end
    h.message = nil
    h.pressAt = GetTime()
    h.timer = C_Timer.NewTimer(h.seconds, h.readyFn)
    h.ticker = C_Timer.NewTicker(TICK, h.tick)
    h.bar:SetWidth(1)
    h.bar:Show()
    Paint(h)
end

local function Let(h)
    if not h.pressAt then return end
    if h.ready then Complete(h); return end
    CancelPress(h)
    h.message = ns.T("popup.hold")
    h.msgTimer = C_Timer.NewTimer(MESSAGE_SECONDS, h.clear)
    Paint(h)
end

-- Sliding off the button cancels: the release that follows does nothing.
local function Leave(h)
    if not h.pressAt then return end
    CancelPress(h)
    Paint(h)
end

local function NewHold(button, opts)
    local parent = opts.parent
    local h = CreateFrame("Frame", nil, parent or UIParent)
    h:SetAllPoints(button)
    if parent then
        h:SetFrameLevel(button:GetFrameLevel() + 20)
    else
        h:SetFrameStrata("FULLSCREEN_DIALOG")
        h:SetFrameLevel(500)
    end
    h.button, h.progress = button, 0
    h.face = Kit.RedButton(h, 100, 40, "")
    h.face:EnableMouse(false)
    h.face:SetAllPoints(h)
    h.face:Hide()
    h.bar = CreateFrame("Frame", nil, h)
    h.bar:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.bar:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.bar:SetFrameLevel(h.face:GetFrameLevel() + 2)
    h.bar:EnableMouse(false)
    local fill = h.bar:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(h.bar)
    fill:SetTexture(WHITE)
    fill:SetVertexColor(1, 0.55, 0.2, 0.6)
    h.bar:Hide()
    h.readyFn = function() Ready(h) end
    h.tick = function() Tick(h) end
    h.relock = function() h.armTimer = nil; Relock(h) end
    h.clear = function() h.msgTimer, h.message = nil, nil; Paint(h) end
    h:SetScript("OnMouseDown", Press)
    h:SetScript("OnMouseUp", Let)
    h:SetScript("OnLeave", Leave)
    h:SetScript("OnHide", CancelPress)
    -- pressed (polish pass): lit while the finger is down, after the SetScripts (which drop hooks)
    Kit.AddPress(h, "rect", h, 3)
    return h
end

-- Puts a hold over `button`: the press must last `seconds` (0.8 by default); then the label says "Let go to
-- confirm" and the release runs `onDone(hold)` (R29: never a timer). Letting go early shows "Hold to
-- confirm"; sliding off cancels. opts.arm: the release only unlocks (the button takes the next real tap for 3
-- seconds and the face says "Tap to confirm"); onDone, if any, still runs. opts.label is the face's text
-- while idle; opts.parent keeps the hold in a frame that hides with the button; opts.key names what the
-- button stands for: the same key again (a card drawn twice) keeps an unlock or a press in progress. Returns
-- the hold, or nil when holds are off (the button is then a plain tap).
function Hold.Button(button, seconds, onDone, opts)
    if not Hold.Enabled() then
        Hold.Release(button)
        return nil
    end
    opts = opts or {}
    local h = holds[button] or NewHold(button, opts)
    holds[button] = h
    local same = h.active and opts.key ~= nil and h.opts and h.opts.key == opts.key
    if not same then
        CancelPress(h)
        if h.msgTimer then h.msgTimer:Cancel(); h.msgTimer = nil end
        if h.armTimer then h.armTimer:Cancel(); h.armTimer = nil end
        h.armed, h.message = false, nil
    end
    h.seconds, h.onDone, h.opts, h.idle = seconds or Hold.SECONDS, onDone, opts, opts.label
    h.active = true
    ns.Kit.SetFont(h.face.label, Kit.FONT_TITLE, math.max(14, math.floor((button:GetHeight() or 0) * 0.42 + 0.5)), "")
    h:Show()
    Paint(h)
    return h
end

function Hold.Release(button)
    local h = holds[button]
    if not h then return end
    CancelPress(h)
    if h.msgTimer then h.msgTimer:Cancel(); h.msgTimer = nil end
    if h.armTimer then h.armTimer:Cancel(); h.armTimer = nil end
    h.armed, h.message, h.active = false, nil, false
    h.face:Hide()
    h:Hide()
end

-- Paints the hold again after its button was enabled or disabled (a disabled button shows the game's own face).
function Hold.Refresh(button)
    local h = holds[button]
    if h and h.active then Paint(h) end
end

-- The hold over `button`, if there is one (for a test, or a caller that wants to read its state).
function Hold.For(button) return holds[button] end

function Hold.ReleaseAll()
    for button in pairs(holds) do Hold.Release(button) end
end

function Hold:Restore() Hold.ReleaseAll() end
