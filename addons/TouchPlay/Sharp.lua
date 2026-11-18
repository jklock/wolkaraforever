-- TouchPlay: Sharp screen (ruling A39, 18 Nov).
--
-- The app draws the game at backing scale 0.75 today: 908 x 626 pixels for the whole frame, stretched 2.67 times to the
-- 2420 x 1668 panel, so every button and letter is soft. The app will let the game draw at the panel's own pixels
-- (backing scale 2.0, or 1.5); this file then lowers the game's RenderScale so the 3D world keeps today's pixel count
-- (about 908 px wide) and is upscaled by the game itself (ResampleQuality, FidelityFX where this client offers it),
-- while the UI is drawn on top at full size. Buttons and text become sharp; the world costs about what it costs now.
-- The app never writes Config.wtf (a render profile choice never edits the game's files): these CVars are TouchPlay's.
--
-- While the "Sharp screen" switch (Touch settings, Layout; default on) is on and Touch is active:
--   * RenderScale = WORLD_WIDTH / the physical width (GetPhysicalScreenSize), at least GetMinRenderScale() where the
--     client has it, on the game's own slider step (Graphics.lua: 100 steps from min to max), never above 1. A physical
--     width of NATIVE_FROM px or less (the app still at 0.75: 908 px) changes nothing.
--   * ResampleQuality 3 (FidelityFX Super Resolution 1.0, Graphics.lua:1309-1324) where the game's Graphics page lists
--     it (RESAMPLE_QUALITY_FSR), else 1 (Bilinear); with FSR, ResampleSharpness SHARPNESS (0..2, 0 = sharpest,
--     Graphics.lua:1538-1561) where the client has that CVar.
--   * useUiScale 1 + uiscale 768 / 626 within the game's slider (1.15 at most) so the game's own windows keep their
--     0.75 size (ruling A39b, below), unless the player already uses their own UI scale; the two go together (the
--     player's own slider value keeps Use UI Scale on; unticking it gives the slider value back).
--   * re-evaluated on DISPLAY_SIZE_CHANGED, UI_SCALE_CHANGED, entering the world and every layout.
-- The player's own values come first (the same rules as Targeting.lua):
--   * a CVar this client does not know (GetCVar answers nil) is left alone; a value that already does the job is kept;
--   * the first value of each CVar Touch changes is kept account-wide in TouchPlayDB.sharpHeld (name -> was, ours),
--     never overwritten by our own value (a /reload, a second character, a new physical size at the next launch);
--   * Off, a pause, Edit Mode, the switch off, or a launch back at today's size give every held value back exactly
--     (only where it still reads ours);
--   * a value the player changes away from ours, while Touch is on or off, stands for that character
--     (TouchPlayCharDB.sharpDeclined) until Defaults in Touch settings or the switch is ticked again;
--   * no CVar is set under the combat lockdown: every change goes through ns.Queue("sharp").
-- /touch sharp prints the physical size, the chosen values, the game's min scale and whether the app's backing scale
-- looks native (physical width NATIVE_LOOK px or more), and keeps it in TouchPlayDB.sharpLog for the Mac.

local ADDON_NAME, ns = ...

local Sharp = ns.Register("Sharp", {})

Sharp.WORLD_WIDTH = 908        -- today's 3D width: 1210 points x 0.75
Sharp.NATIVE_FROM = 1000       -- physical widths at or under this: the app still draws at 0.75, nothing changes
Sharp.NATIVE_LOOK = 2000       -- /touch sharp: the backing scale looks native (2420 at 2.0 on the 11-inch)
Sharp.FSR, Sharp.BILINEAR = "3", "1"
-- FidelityFX's sharpening in stops (0 = sharpest, 2 = none): AMD's FSR 1 default. The world is upscaled 2.67x at
-- backing 2.0, past FSR's 2x design range (plan risk R2), so a mild value; the player's own slider wins.
Sharp.SHARPNESS = "0.2"
-- The game's windows (ruling A39b, 18 Nov): with "Use UI Scale" off the game sizes UIParent pixel for pixel, at
-- 768 / the physical height (PixelUtil.lua:3-6: one UI unit at scale 1 = physical height / 768 px; GetDefaultScale is
-- the engine's, not in Lua). At 908 x 626 that is 1.2268 (UIParent 626 units tall); at 2420 x 1668 0.4604 (1668 units),
-- so every game window (bags, map, character, other add-ons'), drawn in fixed UI units, covers 2.67x less screen.
-- Touch's own layout divides by UIParent's height (Style.lua) and never moved. While Sharp screen is on at a native
-- size, Touch turns Use UI Scale on at today's scale, 768 / OLD_HEIGHT, within the game's UI Scale slider (Graphics.lua:
-- 931: 0.65 .. 1.15, step 0.01): 1.15 at most, so game windows come out 94 % of their old size, drawn at the panel's
-- pixels. A player already using their own UI scale (Use UI Scale on) never saw them shrink: left alone.
Sharp.OLD_HEIGHT = 626         -- today's physical height: 834 points x 0.75
Sharp.UI_UNITS = 768           -- the game's screen height in UI units at scale 1
Sharp.UI_MIN, Sharp.UI_MAX, Sharp.UI_STEP = 0.65, 1.15, 0.01
Sharp.UI_NAMES = { uiscale = true, useUiScale = true }
-- uiscale before useUiScale: Use UI Scale comes on with the right scale already in place
Sharp.NAMES = { "RenderScale", "ResampleQuality", "ResampleSharpness", "uiscale", "useUiScale" }
local NAMES = Sharp.NAMES

ns.L["sharp.on"] = "on"
ns.L["sharp.off"] = "off"
ns.L["sharp.status"] = "Sharp screen %s. Physical %dx%d: %s."
ns.L["sharp.native"] = "native (the app draws at the panel's own pixels)"
ns.L["sharp.notNative"] = "not native (the app still draws below the panel's pixels)"
ns.L["sharp.noSize"] = "Sharp screen %s. This client has no GetPhysicalScreenSize: nothing changes."
ns.L["sharp.chosen"] = "Chosen: RenderScale %s (3D world %d px wide), ResampleQuality %s%s."
ns.L["sharp.chosenNone"] = "Chosen: nothing (RenderScale stays the game's)."
ns.L["sharp.range"] = "Game's render scale: min %s, max %s."
ns.L["sharp.unknown"] = "unknown"
ns.L["sharp.notInClient"] = "not in this client"
ns.L["sharp.held"] = "Touch's (yours %s)"
ns.L["sharp.declined"] = "yours, Touch stands aside"
ns.L["sharp.game"] = "the game's"
ns.L["sharp.ui"] = "UI scale %s: game windows as at 908x626 (today's %s%s)."
ns.L["sharp.uiMax"] = ", the game's max %s holds it: about %d %% of their old size"
ns.L["sharp.uiOwn"] = "UI scale: your own UI scale (Use UI Scale on): left as it is."
ns.L["sharp.uiNone"] = "UI scale: the game's."
ns.L["sharp.uiNow"] = "UIParent scale now %s (game default %s)."

local LOG_MAX = 80

-- ---------------------------------------------------------------------------------------
-- The saved state

local function Table(owner, key)
    if type(owner) ~= "table" then return {} end
    local t = owner[key]
    if type(t) ~= "table" then t = {}; owner[key] = t end
    return t
end
local function Held() return Table(ns.db, "sharpHeld") end           -- account-wide: name -> { was, ours }
local function Given() return Table(ns.db, "sharpGiven") end         -- account-wide: name -> the value put back
local function Declined() return Table(ns.char, "sharpDeclined") end -- per character: name -> true

local function Log(line)
    local db = ns.db
    if type(db) ~= "table" then return end
    local log = Table(db, "sharpLog")
    log[#log + 1] = (date and date("%H:%M:%S ") or "") .. line
    while #log > LOG_MAX do table.remove(log, 1) end
end

function Sharp.Held(name) return ns.db ~= nil and type(ns.db.sharpHeld) == "table" and ns.db.sharpHeld[name] ~= nil end

-- ---------------------------------------------------------------------------------------
-- Reading and writing a CVar (never raises: an unknown or refused CVar is left alone)

local function Read(name)
    local get = GetCVar or (C_CVar and C_CVar.GetCVar)
    if not get then return nil end
    local ok, value = pcall(get, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function Write(name, value)
    local set = SetCVar or (C_CVar and C_CVar.SetCVar)
    if not set then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

-- The same value: numbers within a hair (the game may read "0.375" back as "0.375000"), else the same text.
local function Same(a, b)
    if a == nil or b == nil then return a == b end
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < 1e-4 end
    return tostring(a) == tostring(b)
end

local function Call(fn)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn)
    if not ok then return nil end
    return a, b
end

-- ---------------------------------------------------------------------------------------
-- What to set

-- The RenderScale that keeps the 3D world WORLD_WIDTH px wide at this physical width, or nil (nothing to lower).
function Sharp.Scale(width, minScale, maxScale)
    width = tonumber(width)
    if not width or width <= Sharp.NATIVE_FROM then return nil end
    local s = Sharp.WORLD_WIDTH / width
    local lo, hi = tonumber(minScale), tonumber(maxScale)
    if lo and hi and hi > lo then
        local step = (hi - lo) / 100                   -- the game's own slider: 100 steps from min to max
        s = math.max(lo, math.min(hi, s))
        s = lo + math.floor((s - lo) / step + 0.5) * step
    else
        s = math.floor(s * 1000 + 0.5) / 1000
        if lo then s = math.max(lo, s) end
    end
    if s >= 1 - 1e-6 then return nil end
    return s
end

-- "0.375", "0.5", "0.3725": at most four decimals, no trailing zeros.
function Sharp.Format(n)
    local s = string.format("%.4f", n)
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

-- The UI scale that gives the game's windows today's size at this physical size, and today's scale before the
-- game's slider range held it, or nil (the app still at 0.75, or no size). lo/hi default to the slider's 0.65 .. 1.15.
function Sharp.UiScale(width, height, lo, hi)
    width, height = tonumber(width), tonumber(height)
    if not width or not height or width <= Sharp.NATIVE_FROM or height <= Sharp.OLD_HEIGHT then return nil end
    local wanted = Sharp.UI_UNITS / Sharp.OLD_HEIGHT
    lo, hi = tonumber(lo) or Sharp.UI_MIN, tonumber(hi) or Sharp.UI_MAX
    local s = math.max(lo, math.min(hi, wanted))
    s = math.floor(s / Sharp.UI_STEP + 0.5) * Sharp.UI_STEP
    if s > hi then s = hi end
    return s, wanted
end

local function PhysicalSize() return Call(GetPhysicalScreenSize) end
local function Range() return (Call(GetMinRenderScale)), (Call(GetMaxRenderScale)) end
local function HasFSR() return RESAMPLE_QUALITY_FSR ~= nil end

-- The player uses their own UI scale (Use UI Scale on, not by Touch): their windows never followed the pixels.
local function OwnUiScale()
    return Read("useUiScale") == "1" and not (type(ns.db) == "table" and type(ns.db.sharpHeld) == "table"
        and ns.db.sharpHeld.useUiScale ~= nil)
end

-- name -> the value Touch wants now (switch on, a native-looking size), or nil.
local function Wanted()
    if ns.Contract.GetFeel("sharpScreen") ~= true then return nil end
    local w, h = PhysicalSize()
    local lo, hi = Range()
    local scale = Sharp.Scale(w, lo, hi)
    if not scale then return nil end
    local fsr = HasFSR()
    local want = {
        RenderScale = Sharp.Format(scale),
        ResampleQuality = fsr and Sharp.FSR or Sharp.BILINEAR,
        ResampleSharpness = fsr and Sharp.SHARPNESS or nil,
    }
    -- the two UI scale CVars go together: either the player's own (declined, or already theirs) stops both
    local ui = Sharp.UiScale(w, h)
    local declined = type(ns.char) == "table" and type(ns.char.sharpDeclined) == "table" and ns.char.sharpDeclined or {}
    if ui and Read("useUiScale") ~= nil and Read("uiscale") ~= nil and not OwnUiScale()
        and not declined.uiscale and not declined.useUiScale then
        want.uiscale, want.useUiScale = Sharp.Format(ui), "1"
    end
    return want
end

-- ---------------------------------------------------------------------------------------
-- Applying and giving back (only ever called out of the combat lockdown: Sync queues them)

-- name -> a value asked of the game this session that it did not keep (a floor it does not tell Lua about): asking
-- again at every event would only set it again (and may fire DISPLAY_SIZE_CHANGED each time). Cleared when the game
-- keeps what was asked, on a give-back, on Defaults and on ticking the switch.
local asked = {}

local function Ask(name, w)
    asked[name] = w
    if not Write(name, w) then return false end
    if Same(Read(name), w) then asked[name] = nil end
    return true
end

-- Gives one held value back: only where it still reads ours; a value the player changed stands (and is theirs now).
local function GiveOne(name, held)
    local cur = Read(name)
    -- the player's own uiscale works only with Use UI Scale on: it stays on (still held, so Defaults or ticking the
    -- switch can take both up again and give the player's original back later)
    if name == "useUiScale" and Declined().uiscale and Same(cur, held.ours) then return end
    Held()[name] = nil
    asked[name] = nil
    if cur == nil then return end
    if not Same(cur, held.ours) then
        Declined()[name] = true
        Log(name .. " " .. cur .. " is the player's: left as it is")
        return
    end
    if held.was ~= nil and Write(name, held.was) then
        Given()[name] = held.was
        Log(name .. " " .. cur .. " > " .. tostring(held.was) .. " (given back)")
    end
end

local function GiveBackNow()
    local list = {}
    for name, held in pairs(Held()) do list[#list + 1] = { name, held } end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    for _, item in ipairs(list) do
        if type(item[2]) == "table" then GiveOne(item[1], item[2]) else Held()[item[1]] = nil end
    end
end

-- One pass; true when it found a value the player changed (the next pass lets its pair go at once).
local function ApplyPass()
    local want = Wanted()
    local held, declined, given = Held(), Declined(), Given()
    local found = false
    for _, name in ipairs(NAMES) do
        local cur = Read(name)
        local h = held[name]
        local w = want and want[name]
        if cur == nil then
            -- not in this client: nothing to do (a held entry from elsewhere stays for the Off that gives it back)
        elseif h then
            if not Same(cur, h.ours) then
                held[name], declined[name] = nil, true            -- the player changed it while Touch was on
                found = true
                Log(name .. " " .. cur .. " is the player's: Touch stands aside")
            elseif w == nil then
                GiveOne(name, h)                                  -- the switch is off, or the app is back at 0.75
            elseif not Same(cur, w) and not Same(asked[name], w) then
                if Ask(name, w) then                              -- a new physical size: follow it, keep the original
                    h.ours = Read(name) or w
                    Log(name .. " " .. cur .. " > " .. h.ours .. " (new size)")
                end
            end
        elseif w ~= nil and not declined[name] then
            local back = given[name]
            given[name] = nil
            if back ~= nil and not Same(cur, back) then
                declined[name] = true                             -- the player changed it while Touch was off
                found = true
                Log(name .. " " .. cur .. " is the player's (changed while off): Touch stands aside")
            elseif not Same(cur, w) and not Same(asked[name], w) then
                if Ask(name, w) then
                    local now = Read(name)
                    if now ~= nil and not Same(now, cur) then
                        held[name] = { was = cur, ours = now }
                        Log(name .. " " .. cur .. " > " .. now)
                    end
                else
                    Log(name .. " refused by the game: left " .. cur)
                end
            end
        end
    end
    return found
end

local function ApplyNow()
    if ApplyPass() then ApplyPass() end
end

-- Brings the CVars in line with the state now: Touch on (not paused, not in Edit Mode) = the sharp values; anything
-- else = everything given back. Out of a fight at once, else at the fight's end (the state is read when it runs).
local function SyncNow()
    if type(ns.db) ~= "table" then return end
    if ns.IsActive() and not ns.inEditMode then ApplyNow() else GiveBackNow() end
end

function Sharp.Sync() ns.Queue("sharp", SyncNow) end

-- A Touch settings switch changed. Ticking Sharp screen is the player's yes: what they had declined is asked again.
function Sharp.FeelChanged(key)
    if key ~= "sharpScreen" then return end
    if ns.Contract.GetFeel(key) == true then
        local declined, given = Declined(), Given()
        for _, name in ipairs(NAMES) do declined[name], given[name] = nil, nil end
    end
    asked = {}
    Sharp.Sync()
end

-- Defaults in Touch settings: every sharp value is asked again for this character.
function Sharp.Reset()
    if ns.char then ns.char.sharpDeclined = nil end
    if ns.db then ns.db.sharpGiven = nil end
    asked = {}
    Sharp.Sync()
end

-- ---------------------------------------------------------------------------------------
-- /touch sharp

local function Describe(name)
    local cur = Read(name)
    if cur == nil then return name .. " " .. ns.T("sharp.notInClient") end
    local h = Held()[name]
    if h then return name .. " " .. cur .. " (" .. ns.T("sharp.held", tostring(h.was)) .. ")" end
    if Declined()[name] then return name .. " " .. cur .. " (" .. ns.T("sharp.declined") .. ")" end
    return name .. " " .. cur .. " (" .. ns.T("sharp.game") .. ")"
end

function Sharp.Command()
    local on = ns.T(ns.Contract.GetFeel("sharpScreen") == true and "sharp.on" or "sharp.off")
    local w, h = PhysicalSize()
    local lines = {}
    if not w then
        lines[1] = ns.T("sharp.noSize", on)
    else
        local native = (tonumber(w) or 0) >= Sharp.NATIVE_LOOK
        lines[1] = ns.T("sharp.status", on, math.floor(tonumber(w) + 0.5), math.floor((tonumber(h) or 0) + 0.5),
            ns.T(native and "sharp.native" or "sharp.notNative"))
    end
    local want = Wanted()
    if want then
        local quality = want.ResampleQuality
        local tail = (quality == Sharp.FSR and " (FidelityFX)" or " (Bilinear)")
            .. (want.ResampleSharpness and (", ResampleSharpness " .. want.ResampleSharpness) or "")
        lines[#lines + 1] = ns.T("sharp.chosen", want.RenderScale,
            math.floor((tonumber(w) or 0) * tonumber(want.RenderScale) + 0.5), quality, tail)
    else
        lines[#lines + 1] = ns.T("sharp.chosenNone")
    end
    local ui, uiWanted = Sharp.UiScale(w, h)
    if want and want.uiscale then
        local held = ui and ui < uiWanted - 1e-6
        lines[#lines + 1] = ns.T("sharp.ui", want.uiscale, string.format("%.2f", uiWanted),
            held and ns.T("sharp.uiMax", Sharp.Format(Sharp.UI_MAX), math.floor(ui / uiWanted * 100 + 0.5)) or "")
    elseif OwnUiScale() then
        lines[#lines + 1] = ns.T("sharp.uiOwn")
    else
        lines[#lines + 1] = ns.T("sharp.uiNone")
    end
    local now = UIParent and UIParent.GetScale and select(2, pcall(UIParent.GetScale, UIParent))
    local default = Call(GetDefaultScale)
    lines[#lines + 1] = ns.T("sharp.uiNow", tonumber(now) and Sharp.Format(now) or ns.T("sharp.unknown"),
        tonumber(default) and Sharp.Format(default) or ns.T("sharp.unknown"))
    local lo, hi = Range()
    lines[#lines + 1] = ns.T("sharp.range", lo and tostring(lo) or ns.T("sharp.unknown"), hi and tostring(hi) or ns.T("sharp.unknown"))
    for _, name in ipairs(NAMES) do lines[#lines + 1] = Describe(name) end
    for _, line in ipairs(lines) do
        ns.Print(line)
        Log(line)
    end
end

-- ---------------------------------------------------------------------------------------
-- Module steps

function Sharp:Layout() Sharp.Sync() end
function Sharp:Restore() Sharp.Sync() end

ns.On("DISPLAY_SIZE_CHANGED", function() Sharp.Sync() end)
ns.On("UI_SCALE_CHANGED", function() Sharp.Sync() end)
-- Entering the world, on or off: on = the sharp values for this size; off (or paused) after a session that ended with
-- our values still set = put them back.
ns.On("PLAYER_ENTERING_WORLD", function() Sharp.Sync() end, true)
