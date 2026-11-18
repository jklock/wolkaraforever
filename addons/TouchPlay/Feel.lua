-- TouchPlay: Touch settings, the feel (rule 8, Task 14; mockups 31, 87, 88).
--
-- The player's switches and sliders live in TouchPlayDB.feel; the names and their defaults are
-- Contract.FEEL_DEFAULTS (one table, Task 3) and Contract.GetFeel reads them. Feel.Set checks a value, keeps
-- it and applies it:
--   * hold, turnWithView: the contract list (TPC1;hold=..;hand=..;turn=..) is written at once;
--   * leftHanded, stand, buttonSize, textSize: the layout is rebuilt (ns.Each("Layout"), which ends with the
--     contract), queued with ns.Queue so a fight delays it. A slider dragged along does not rebuild at every
--     step: the rebuild waits 0.3 s after the last change;
--   * floatingNumbers: the game's own combat text setting (enableFloatingCombatText);
--   * reduceMotion: "auto" follows the game's setting until the player picks yes or no (ns.ReduceMotion in
--     Style.lua; Units, Picker and Loot read it);
--   * holdRisky, tapSounds, edgeRun: read where they are used (Hold.lua, Style.lua's sounds, the app);
--   * autoTarget, bigPlates (the Targeting group, 18 Nov, no mockup: defaults pending the tester's approval): the
--     game's soft targeting and bigger enemy name plates, applied and given back by Targeting.lua.
--   * sharpScreen (ruling A39, 18 Nov, Layout under Text size): the game's RenderScale and resampling while the app
--     draws at the panel's own pixels, applied and given back by Sharp.lua.
-- Where the layout moves (left-handed, stand, size) is ns.Anchor's job in Style.lua: one place.
--
-- The panel uses the game's own checkbox and slider art. "Game settings ›" opens the game's own settings with
-- Settings.OpenToCategory (this client has no GameMenuButtonOptions to click securely), so it is greyed in a fight
-- (R32). The panel holds no secure button, so the game does not protect it: it opens and closes in a fight too.
-- Vibration is greyed: iPads cannot vibrate.

local ADDON_NAME, ns = ...

local Feel = ns.Register("Feel", {})
local Kit = ns.Kit

ns.L["feel.title"] = "Touch settings"
ns.L["feel.layout"] = "Layout"
ns.L["feel.touch"] = "Touch"
ns.L["feel.feedback"] = "Feedback"
ns.L["feel.targeting"] = "Targeting"
ns.L["feel.autoTarget"] = "Auto-target the enemy in front"
ns.L["feel.autoTarget.note"] = "a spell with no target hits the enemy you face"
ns.L["feel.bigPlates"] = "Bigger name plates to tap"
ns.L["feel.bigPlates.note"] = "enemy plates always shown, larger, not stacked"
ns.L["feel.sharpScreen"] = "Sharp screen"
ns.L["feel.sharpScreen.note"] = "Sharp buttons and text; the 3D world stays as light as now"
ns.L["feel.leftHanded"] = "Left-handed layout"
ns.L["feel.leftHanded.note"] = "swaps the walk side and the spell side"
ns.L["feel.stand"] = "iPad on a stand"
ns.L["feel.stand.note"] = "moves buttons down, nearer the table"
ns.L["feel.buttonSize"] = "Button size"
ns.L["feel.textSize"] = "Text size"
ns.L["feel.small"] = "Small"
ns.L["feel.large"] = "Large"
ns.L["feel.normal"] = "Normal"
ns.L["feel.hold"] = "Hold time"
ns.L["feel.hold.note"] = "how long before a hold opens the info card"
ns.L["feel.quick"] = "Quick"
ns.L["feel.slow"] = "Slow"
ns.L["feel.seconds"] = "%.2f s"
ns.L["feel.times"] = "%.2fx"
ns.L["feel.turnWithView"] = "Character turns with the view"
ns.L["feel.turnWithView.note"] = "recommended"
-- ruling A34: auto-run locks by sliding up onto the lock above the stick (the app reads this switch from the saved file:
-- off, the lock is not drawn and nothing locks; TouchGamepad.m _edgeRun)
ns.L["feel.edgeRun"] = "Auto-run lock above the walk stick"
ns.L["feel.edgeRun.note"] = "slide up onto it and let go to keep running"
ns.L["feel.reloadLine"] = "Touch buttons changed. Tap Done, then Reload to give them to the app."
ns.L["feel.holdRisky"] = "Risky actions need a hold"
ns.L["feel.holdRisky.note"] = "release spirit, hearth, log out, delete"
ns.L["feel.tapSounds"] = "Tap sounds"
ns.L["feel.floatingNumbers"] = "Floating damage numbers"
ns.L["feel.reduceMotion"] = "Reduce motion"
ns.L["feel.reduceMotion.note"] = "follows the iPad setting unless you change it here"
ns.L["feel.vibration"] = "Vibration"
ns.L["feel.vibration.note"] = "iPhone only: iPads cannot vibrate"
ns.L["feel.gameSettings"] = "Game settings ›"
ns.L["feel.defaults"] = "Defaults"
ns.L["feel.done"] = "Done"

-- 18 Nov: the Targeting group made the panel one group longer; rows are 44 apart (the checkbox's own height, so no two
-- rows' taps meet), a header 34 above its first row (36 before a slider). Ruling A39 added the Sharp screen row: the
-- groups now start 40 under the group before (was 46) and the panel starts at 66 (was 77), so it still ends 9 above
-- the screen's bottom (66 + 949 = 1015) and its top stays under the app's 60-unit top band.
local PANEL_W, PANEL_H, PANEL_X, PANEL_Y = 945, 949, 210, 66
Feel.PANEL_W = PANEL_W
-- A slider row's columns (iPad run 7: "LargeNormal", and the hold note ran under "Quick"): the label at 37 with its
-- note under it; the left word right-aligned in LEFT_WORD_W before the track; the track; the right word in
-- RIGHT_WORD_W after it; the value right-aligned in VALUE_W at the panel's right edge (31 in).
local TRACK_X, TRACK_W, WORD_GAP, LEFT_WORD_W, RIGHT_WORD_W, VALUE_W = 500, 210, 12, 90, 70, 100
local NOTE_W = TRACK_X - WORD_GAP - LEFT_WORD_W - 37 - 10
local REBUILD_SECONDS = 0.3
local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.62, 0.62, 0.62 }
local LAYOUT = { leftHanded = true, stand = true, buttonSize = true, textSize = true }
local CHECK_UP, CHECK_ON = "Interface\\Buttons\\UI-CheckBox-Up", "Interface\\Buttons\\UI-CheckBox-Check"
local THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
local WHITE_ART = "Interface\\Buttons\\WHITE8x8"

-- ---------------------------------------------------------------------------------------
-- Reading and changing a setting

function Feel.Get(key) return ns.Contract.GetFeel(key) end

local function Valid(key, value)
    local default = ns.Contract.FEEL_DEFAULTS[key]
    if default == nil then return nil end
    if key == "reduceMotion" then
        if type(value) == "boolean" then return value end
        return nil
    end
    if type(value) ~= type(default) then return nil end
    if type(value) == "number" then
        if value ~= value then return nil end
        local range = ns.Contract.FEEL_RANGES[key]
        if range then value = math.max(range[1], math.min(range[2], value)) end
    end
    return value
end

local pending
-- Paused or off, a rebuild does nothing: a Layout would take the game's frames again. Switching on lays out anew.
local function RebuildNow()
    if not ns.IsActive() then return end
    ns.Each("Layout")
    ns.Each("Refresh")
end

local function Rebuild()
    pending = nil
    if not ns.IsActive() then return end
    ns.Queue("feel layout", RebuildNow)
end

local function ScheduleRebuild()
    if pending then pending:Cancel() end
    pending = C_Timer.NewTimer(REBUILD_SECONDS, Rebuild)
end

local function SetCombatText(on)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, "enableFloatingCombatText", on and "1" or "0") end
end

-- Reduce motion changed (either way): running pulses stop, stopped ones start again.
local function SyncMotion()
    if ns.Picker and ns.Picker.SyncMotion then ns.Picker.SyncMotion() end
    ns.Each("Refresh")
end

local Repaint

local function Changed(key)
    if key == "floatingNumbers" then SetCombatText(Feel.Get(key)) end
    if ns.Targeting then ns.Targeting.FeelChanged(key) end
    if ns.Sharp then ns.Sharp.FeelChanged(key) end
    if LAYOUT[key] then
        ScheduleRebuild()
    else
        ns.Contract.Write()
    end
    if key == "reduceMotion" then SyncMotion() end
    if Repaint then Repaint() end
end

-- Checks, keeps and applies a value; a value of the wrong kind changes nothing, a number is held inside its range.
function Feel.Set(key, value)
    value = Valid(key, value)
    if value == nil then return end
    if type(ns.db.feel) ~= "table" then ns.db.feel = {} end
    ns.db.feel[key] = value
    Changed(key)
end

-- Every setting back to its default.
function Feel.Defaults()
    ns.db.feel = {}
    SetCombatText(Feel.Get("floatingNumbers"))
    ScheduleRebuild()
    ns.Contract.Write()
    SyncMotion()
    if ns.Targeting then ns.Targeting.Reset() end
    if ns.Sharp then ns.Sharp.Reset() end
    if Repaint then Repaint() end
end

-- ---------------------------------------------------------------------------------------
-- The panel

local dim = CreateFrame("Button", nil, ns.root)
dim:SetAllPoints(ns.root)
dim:SetFrameStrata("DIALOG")
dim:SetFrameLevel(90)
dim:RegisterForClicks("LeftButtonUp")
dim.shade = dim:CreateTexture(nil, "BACKGROUND")
dim.shade:SetAllPoints(dim)
dim.shade:SetColorTexture(0, 0, 0, 0.6)
dim:Hide()
Feel.dim = dim

local panel = Kit.Backdrop(ns.root, "gold", "dark")
panel:SetSize(PANEL_W, PANEL_H)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(100)
panel:EnableMouse(true)
panel:Hide()
ns.Anchor(panel, "TL", PANEL_X, PANEL_Y)
Feel.panel = panel

local title = Kit.GoldHeader(panel, ns.T("feel.title"))
title:SetPoint("CENTER", panel, "TOP", 0, 0)
title:SetFrameLevel(110)
Feel.title = title

local function Text(parent, size, color, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, font or Kit.FONT_TITLE, size, "")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

Feel.headers = {}
local function Header(textKey, y)
    local fs = Text(panel, 22, GOLD)
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 37, -(y - 12))
    fs:SetText(ns.T(textKey))
    Feel.headers[textKey] = fs
end

Feel.rows = {}
Feel.rowY = {}             -- each row's centre, from the panel's top (for the layout check)

-- A label, and a smaller note after it, on the row centred at y.
local function LabelAndNote(key, y, x, noteWidth)
    local r = Feel.rows[key]
    r.label = Text(panel, 21, WHITE)
    r.label:SetPoint("LEFT", panel, "TOPLEFT", x, -y)
    r.label:SetText(ns.T("feel." .. key))
    if ns.L["feel." .. key .. ".note"] then
        r.note = Text(panel, 16, GREY)
        r.note:SetPoint("LEFT", r.label, "RIGHT", 14, -1)
        r.note:SetText(ns.T("feel." .. key .. ".note"))
    end
    return r
end

-- A checkbox in the game's own art; a tap anywhere on the row's words ticks it too.
local function Check(key, y, enabled)
    local r = {}
    Feel.rows[key] = r
    Feel.rowY[key] = y
    local box = CreateFrame("Button", nil, panel)
    box:SetSize(44, 44)
    box:SetPoint("LEFT", panel, "TOPLEFT", 31, -y)
    box:SetNormalTexture(CHECK_UP)
    box:SetPushedTexture(CHECK_UP)
    box:SetHitRectInsets(0, -(PANEL_W - 31 - 44 - 60), 0, 0)
    box:RegisterForClicks("LeftButtonUp")
    r.box = box
    r.check = box:CreateTexture(nil, "OVERLAY")
    r.check:SetTexture(CHECK_ON)
    r.check:SetAllPoints(box)
    r.check:Hide()
    LabelAndNote(key, y, 83)
    if enabled == false then
        box:Disable()
        r.label:SetTextColor(0.45, 0.45, 0.45)
        r.note:SetTextColor(0.45, 0.45, 0.45)
        box:GetNormalTexture():SetDesaturated(true)
        box:SetAlpha(0.5)
    else
        box:SetScript("OnClick", function()
            Kit.Sound("tap")
            local on = key == "reduceMotion" and ns.ReduceMotion() or Feel.Get(key)
            Feel.Set(key, not on)
        end)
    end
    Kit.AddPress(box, "square", box, -4)     -- pressed: the box's edge in pale gold (polish pass)
    return r
end

-- A slider in the game's own art: a track, a gold fill, the game's slider button. Its words in their own columns.
local function Slider(key, y, minValue, maxValue, step, leftKey, rightKey, format)
    local r = { format = format }
    Feel.rows[key] = r
    Feel.rowY[key] = y
    r.label = Text(panel, 21, WHITE)
    r.label:SetText(ns.T("feel." .. key))
    if ns.L["feel." .. key .. ".note"] then
        r.label:SetPoint("LEFT", panel, "TOPLEFT", 37, -(y - 9))
        r.note = Text(panel, 15, GREY)
        r.note:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -1)
        r.note:SetWidth(NOTE_W)
        r.note:SetWordWrap(false)
        r.note:SetText(ns.T("feel." .. key .. ".note"))
    else
        r.label:SetPoint("LEFT", panel, "TOPLEFT", 37, -y)
    end
    local s = CreateFrame("Slider", nil, panel)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(TRACK_W, 44)
    s:SetPoint("LEFT", panel, "TOPLEFT", TRACK_X, -y)
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = Kit.Backdrop(s, "tooltip", "tooltip")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(14)
    track:EnableMouse(false)
    r.fill = s:CreateTexture(nil, "ARTWORK")
    r.fill:SetTexture(WHITE_ART)
    r.fill:SetVertexColor(0.78, 0.6, 0.2, 0.9)
    r.fill:SetHeight(8)
    r.fill:SetPoint("LEFT", s, "LEFT", 3, 0)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(THUMB)
    thumb:SetSize(32, 32)
    s:SetThumbTexture(thumb)
    s.leftLabel = Text(panel, 17, GREY)
    s.leftLabel:SetPoint("RIGHT", s, "LEFT", -WORD_GAP, 0)
    s.leftLabel:SetWidth(LEFT_WORD_W)
    s.leftLabel:SetJustifyH("RIGHT")
    s.leftLabel:SetWordWrap(false)
    s.leftLabel:SetText(ns.T(leftKey))
    s.rightLabel = Text(panel, 17, GREY)
    s.rightLabel:SetPoint("LEFT", s, "RIGHT", WORD_GAP, 0)
    s.rightLabel:SetWidth(RIGHT_WORD_W)
    s.rightLabel:SetWordWrap(false)
    s.rightLabel:SetText(ns.T(rightKey))
    r.value = Text(panel, 19, GOLD)
    r.value:SetPoint("RIGHT", panel, "TOPRIGHT", -31, -y)
    r.value:SetWidth(VALUE_W)
    r.value:SetJustifyH("RIGHT")
    r.value:SetWordWrap(false)
    s:SetScript("OnValueChanged", function(_, value)
        if r.painting then return end
        Feel.Set(key, value)
    end)
    r.slider = s
    return r
end

local function ValueText(key, value)
    if key == "hold" then return ns.T("feel.seconds", value) end
    if math.abs(value - 1) < 0.025 then return ns.T("feel.normal") end
    return ns.T("feel.times", value)
end

Header("feel.layout", 47)
Check("leftHanded", 81)
Check("stand", 125)
Slider("buttonSize", 169, 0.8, 1.4, 0.05, "feel.small", "feel.large")
Slider("textSize", 213, 0.8, 1.4, 0.05, "feel.small", "feel.large")
Check("sharpScreen", 257)
Header("feel.touch", 297)
Slider("hold", 333, 0.3, 0.8, 0.05, "feel.quick", "feel.slow")
Check("turnWithView", 377)
Check("edgeRun", 421)
Check("holdRisky", 465)
Header("feel.targeting", 505)
Check("autoTarget", 539)
Check("bigPlates", 583)
Header("feel.feedback", 623)
Check("tapSounds", 657)
Check("floatingNumbers", 701)
Check("reduceMotion", 745)
Check("vibration", 789, false)

-- Game settings ›: the game's own settings panel, which the game refuses to add-on code in a fight (R32): the
-- row is greyed then, says "After the fight" and does nothing; out of a fight the call runs inside pcall (a
-- missing or changed Blizzard function must never pause TouchPlay). This client has no GameMenuButtonOptions, so
-- there is no secure button to click instead, and no secure child here (it would make the panel protected).
do
    local r = { }
    Feel.rows.gameSettings = r
    Feel.rowY.gameSettings = 835
    local face = Kit.Backdrop(panel, "tooltip", "tooltip")
    face:SetSize(PANEL_W - 62, 44)
    face:SetPoint("LEFT", panel, "TOPLEFT", 31, -Feel.rowY.gameSettings)
    face:EnableMouse(false)
    r.face = face
    r.label = Text(face, 21, GOLD)
    r.label:SetPoint("LEFT", face, "LEFT", 20, 0)
    r.label:SetText(ns.T("feel.gameSettings"))
    r.note = Text(face, 17, GREY)
    r.note:SetPoint("RIGHT", face, "RIGHT", -20, 0)
    r.note:SetText("")
    local button = CreateFrame("Button", "TouchPlayGameSettings", panel)
    button:SetAllPoints(face)
    button:SetFrameLevel(face:GetFrameLevel() + 2)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        Kit.Sound("tap")
        ns.Guard("game settings", function()
            if ns.InFight() then return end               -- greyed: nothing to do until the fight ends
            if Settings and Settings.OpenToCategory then
                pcall(Settings.OpenToCategory, Settings.INTERFACE_CATEGORY_ID)
            end
            Feel.Close()
        end)
    end)
    r.button = button
    -- pressed: the row's edge; in a fight it lights grey and says why (the row says "After the fight" too)
    button.touchRefused = function() return ns.InFight() and ns.T("common.afterFight") or nil end
    Kit.AddPress(button, "rect", face, 0)
end

-- Greyed with "After the fight" while a fight is on.
local function RefreshGameRow()
    local r = Feel.rows.gameSettings
    local off = ns.InFight() and true or false
    local text = off and ns.T("common.afterFight") or ""
    if r.note:GetText() ~= text then r.note:SetText(text) end
    local alpha = off and 0.45 or 1
    if r.face:GetAlpha() ~= alpha then r.face:SetAlpha(alpha) end
end

Feel.defaultsButton = Kit.RedButton(panel, 180, 44, ns.T("feel.defaults"))
Feel.defaultsButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 42, -(PANEL_H - 82))
Feel.defaultsButton:SetScript("OnClick", function() Feel.Defaults() end)
Feel.doneButton = Kit.RedButton(panel, 181, 44, ns.T("feel.done"))
Feel.doneButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 724, -(PANEL_H - 82))
Feel.doneButton:SetScript("OnClick", function() Feel.Close() end)
dim:SetScript("OnClick", function() Feel.Close() end)

-- iPad run 7: the contract's "Reload to give them to the app" notice sits under the panel; the panel says it itself,
-- between Defaults and Done, and Done uncovers the notice with its (secure) Reload button.
Feel.reloadLine = Text(panel, 16, GOLD)
Feel.reloadLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 240, -(PANEL_H - 84))
Feel.reloadLine:SetWidth(470)
Feel.reloadLine:SetJustifyH("CENTER")
Feel.reloadLine:SetText(ns.T("feel.reloadLine"))
Feel.reloadLine:Hide()

-- Shows what is set: ticks, slider positions and their words.
function Repaint()
    RefreshGameRow()
    local reload = ns.Contract and ns.Contract.NeedsReload and ns.Contract.NeedsReload() or false
    if Feel.reloadLine:IsShown() ~= reload then Feel.reloadLine:SetShown(reload) end
    for key, r in pairs(Feel.rows) do
        if r.check and key ~= "vibration" then
            local on = key == "reduceMotion" and ns.ReduceMotion() or Feel.Get(key)
            local shown = on == true
            if r.check:IsShown() ~= shown then r.check:SetShown(shown) end
        elseif r.slider then
            local value = Feel.Get(key)
            r.painting = true
            r.slider:SetValue(value)
            r.painting = false
            local min, max = r.slider:GetMinMaxValues()
            r.fill:SetWidth(math.max(1, (TRACK_W - 6) * (value - min) / (max - min)))
            r.value:SetText(ValueText(key, value))
        end
    end
end
Feel.Repaint = Repaint

local function OnFight() if panel:IsShown() then RefreshGameRow() end end
ns.On("PLAYER_REGEN_DISABLED", OnFight)
ns.On("PLAYER_REGEN_ENABLED", OnFight)

function Feel.IsOpen() return panel:IsShown() end

function Feel.Open()
    Repaint()
    dim:Show()
    panel:Show()
    Kit.Sound("open")
end

function Feel.Close()
    if not panel:IsShown() then return end
    panel:Hide()
    dim:Hide()
    Kit.Sound("close")
end

-- ---------------------------------------------------------------------------------------
-- Module steps

function Feel:Layout() ns.Anchor(panel, "TL", PANEL_X, PANEL_Y) end

function Feel:Restore() Feel.Close() end
