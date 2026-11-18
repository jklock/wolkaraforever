-- TouchPlay: the game's bars and frames that the touch screen replaces (rule 2).
--
-- Nothing is destroyed and no action slot is touched: each frame is moved into a hidden frame
-- (the WolkaraRoue Blizzard.lua method, used by action bar add-ons), so its key bindings keep
-- working and Restore puts it back on its own parent. The game's bars are protected, so every
-- move waits for the end of a fight (ns.Queue).
--
-- Edit Mode owns these frames and overrides Hide, SetShown, SetPoint and ClearAllPoints on
-- them: calling those from an add-on taints. So this file only reparents, clears
-- isShownExternal (as Bartender4 does), and drops the few events that make the game
-- re-show a bar. Edit Mode opening gives the frames back; closing hides them again.

local _, ns = ...

local Bars = ns.Register("Bars", {})

-- Names differ between game versions; the ones that do not exist are skipped.
Bars.HIDDEN = {
    "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
    "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
    "MicroMenuContainer", "BagsBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
    "SecondaryStatusTrackingBarContainer", "PlayerFrame", "TargetFrame", "TargetFrameToT",
    "ObjectiveTrackerFrame", "QuestWatchFrame", "Questie_BaseFrame",
    -- iPad run 1: this client (the Camelot game type) shows the controller's action bar at the bottom centre
    -- (a row of small buttons, a "+" and the large target buttons above it) because the app sends a game pad;
    -- and the minimap's own cluster (zone bar, coordinates, clock) sat next to the ring's own words. The Minimap
    -- itself lives in our ring (Hud), outside the cluster.
    "GamepadMainActionBarFrame", "MinimapCluster",
    -- iPad run 5: the game's own cast bar drew under ours (a second bar, the spell name under it). Its frame is
    -- Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml:482 (an Edit Mode cast bar system, so only reparented);
    -- under the gamepad UI it is not a managed frame and sits above GamepadMainActionBarFrame
    -- (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:1287). Ours is Units.playerCast.
    "PlayerCastingBarFrame",
}

-- Game frames holding action buttons that the touch screen does not stand in for: never hidden by the stray search.
Bars.KEEP = {
    ExtraAbilityContainer = true, ExtraActionBarFrame = true, ZoneAbilityFrame = true, OverrideActionBar = true,
    PossessActionBar = true, MainMenuBarVehicleLeaveButton = true, MultiCastActionBarFrame = true,
}

-- Events the game answers by re-showing or re-laying out a bar; dropped while hidden.
Bars.UNREGISTERED = {
    MainActionBar = { "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
}

local hider = CreateFrame("Frame")
hider:Hide()
Bars.hider = hider

local moved = {}        -- frame -> its parent before we moved it
local unregistered = {} -- frame -> the events we dropped from it
local hooked = {}       -- frame -> true once its Show is hooked
local want = false      -- the frames should be hidden now (set at once, the move may wait for combat)

local function Frames()
    local list = {}
    for _, name in ipairs(Bars.HIDDEN) do
        local frame = _G[name]
        if type(frame) == "table" and frame.GetParent then list[#list + 1] = { name = name, frame = frame } end
    end
    return list
end

local RehideSoon

local function HideFrame(name, frame)
    -- Edit Mode frames: the game's own "shown by someone else" flag would bring them back. Written only when it is
    -- set: an add-on's write to a game frame's field taints that field for the game's code that reads it (iPad run 7
    -- taint review), so no write at all when there is nothing to clear.
    if frame.system and frame.isShownExternal ~= nil then frame.isShownExternal = nil end
    if not hooked[frame] and frame.Show then
        hooked[frame] = true
        hooksecurefunc(frame, "Show", function()
            if want and frame:GetParent() ~= hider then RehideSoon() end
        end)
    end
    local events = Bars.UNREGISTERED[name]
    if events and not unregistered[frame] then
        unregistered[frame] = {}
        for _, event in ipairs(events) do
            if frame:IsEventRegistered(event) then
                frame:UnregisterEvent(event)
                table.insert(unregistered[frame], event)
            end
        end
    end
    if frame:GetParent() ~= hider then
        moved[frame] = frame:GetParent() or UIParent
        frame:SetParent(hider)
    end
end

-- ---------------------------------------------------------------------------------------
-- Stray action bars (iPad run 5): with the gamepad UI on, Blizzard_GamepadActionBars draws its own bars (two large
-- spell buttons above a row of seven small ones, bottom centre, under the chat strip). That add-on ships only its .toc
-- in this client's UI source (/tmp/wowui: ActionBar.lua, TargetActionBars/*.lua are not there), so its frame names
-- cannot be listed. Instead every action button the game made is found (EnumerateFrames), and the frame under
-- UIParent that holds it is hidden like the bars above, unless it is TouchPlay's own or in Bars.KEEP. Found again on
-- each Layout and ADDON_LOADED; /touch frames lists what was found (Bars.Strays) and what is under a point.

local strays = {}       -- frame -> its name or "<unnamed>", for the frames the search hid
local strayList = {}    -- the same, in the order found

-- An action button: a button whose action slot is set (the game's action buttons carry `action` or the "action"
-- attribute; a secure one may say type "action").
local function IsActionButton(frame)
    local kind = frame.GetObjectType and frame:GetObjectType()
    if kind ~= "Button" and kind ~= "CheckButton" then return false end
    if type(rawget(frame, "action")) == "number" then return true end
    if frame.GetAttribute then
        if type(frame:GetAttribute("action")) == "number" then return true end
        if frame:GetAttribute("type") == "action" then return true end
    end
    return false
end

local function NameOf(frame)
    local name = frame.GetName and frame:GetName()
    return type(name) == "string" and name or nil
end

-- TouchPlay's own frames: under its roots, or named TouchPlay*.
local function Ours(frame)
    local f, guard = frame, 0
    while f and guard < 40 do
        if f == ns.root or f == ns.moveRoot or f == hider then return true end
        local name = NameOf(f)
        if name and name:find("^TouchPlay") then return true end
        f, guard = f.GetParent and f:GetParent(), guard + 1
    end
    return false
end

-- The frame directly under UIParent that holds `frame` (nil when it is not under UIParent).
local function TopOf(frame)
    local f, guard = frame, 0
    while f and guard < 40 do
        local parent = f.GetParent and f:GetParent()
        if parent == UIParent then return f end
        f, guard = parent, guard + 1
    end
    return nil
end

local function FindStrays()
    if type(EnumerateFrames) ~= "function" then return end
    local frame = EnumerateFrames()
    while frame do
        local forbidden = frame.IsForbidden and frame:IsForbidden()
        if not forbidden and IsActionButton(frame) and not Ours(frame) then
            local top = TopOf(frame)
            local name = top and NameOf(top)
            if top and not strays[top] and not Bars.KEEP[name or ""] and not Ours(top)
                and not (top.IsForbidden and top:IsForbidden()) then
                strays[top] = name or "<unnamed>"
                strayList[#strayList + 1] = top
            end
        end
        frame = EnumerateFrames(frame)
    end
end
Bars.FindStrays = FindStrays

-- The frames the stray search hid: { name, ... } in the order found.
function Bars.Strays()
    local names = {}
    for i, frame in ipairs(strayList) do names[i] = strays[frame] end
    return names
end

local function HideAll()
    for _, item in ipairs(Frames()) do HideFrame(item.name, item.frame) end
    FindStrays()
    for _, frame in ipairs(strayList) do HideFrame(strays[frame], frame) end
end

local function RestoreAll()
    for frame, events in pairs(unregistered) do
        for _, event in ipairs(events) do frame:RegisterEvent(event) end
        unregistered[frame] = nil
    end
    for frame, parent in pairs(moved) do
        frame:SetParent(parent)
        moved[frame] = nil
    end
end

-- Its own queue key: a pending Restore must not be replaced by a re-hide, and a re-hide that
-- comes after Restore does nothing because `want` is already false.
function RehideSoon()
    ns.Queue("bars_rehide", function() if want then HideAll() end end)
end

function Bars.IsHidden(name)
    local frame = type(name) == "table" and name or _G[name]
    return type(frame) == "table" and frame.GetParent ~= nil and frame:GetParent() == hider
end

-- ---------------------------------------------------------------------------------------
-- /touch frames [x y]: what is drawn at a point (x, y in layout units from the top left, as the screenshots are
-- measured: px / screen height * 1024; with no point, where the pointer is, which is where the last tap landed), and
-- what the stray search hid. One summary line in chat; the full list is kept in TouchPlayDB.framelog (written to the
-- file at /reload or logout).
-- iPad run 7 ("/touch frames causes some sort of bug": BugSack's alert sounded as it was typed): the walk read every
-- frame's rect and compared it, and a frame whose rect the game hides from add-ons (a secret value) or whose getter
-- throws raised a Lua error straight out of the slash command, unguarded. Now each frame is read inside pcall with
-- read-only getters only (IsForbidden, IsVisible, GetRect, GetEffectiveScale, GetFrameStrata, GetFrameLevel, GetName,
-- GetParent, GetObjectType); a hidden or odd answer skips that frame; the command itself is guarded and refused in a
-- fight (a walk over every frame is a hitch there). Nothing on another frame is set, shown or called.

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8 }
local SHOW_MAX = 15

local function Plain(...)
    if not issecretvalue then return true end
    for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return false end end
    return true
end

-- A plain string or nil, read safely.
local function SafeName(frame)
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" and Plain(name) then return name end
    return nil
end

local function SafeParent(frame)
    local ok, parent = pcall(frame.GetParent, frame)
    if ok and type(parent) == "table" then return parent end
    return nil
end

local function Chain(frame)
    local name = SafeName(frame)
    if name then return name end
    local parts, parent, guard = {}, SafeParent(frame), 0
    while parent and guard < 8 do
        local pname = SafeName(parent)
        parts[#parts + 1] = pname or "?"
        if pname then break end
        parent, guard = SafeParent(parent), guard + 1
    end
    return "<unnamed> in " .. table.concat(parts, " > ")
end

local function SafeTop(frame)
    local f, guard = frame, 0
    while f and guard < 40 do
        local parent = SafeParent(f)
        if parent == UIParent then return f end
        f, guard = parent, guard + 1
    end
    return nil
end

-- One frame's facts, or nil when it is forbidden, hidden, or any answer is hidden from add-ons or throws.
local function Read(frame)
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not Plain(forbidden) or forbidden then return nil end
    end
    local ok, visible = pcall(frame.IsVisible, frame)
    if not ok or not Plain(visible) or not visible then return nil end
    local ok2, left, bottom, w, h = pcall(frame.GetRect, frame)
    if not ok2 or not Plain(left, bottom, w, h) then return nil end
    if type(left) ~= "number" or type(bottom) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return nil
    end
    local ok3, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok3 or not Plain(scale) or type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local ok4, strata = pcall(frame.GetFrameStrata, frame)
    if not ok4 or not Plain(strata) or type(strata) ~= "string" then strata = "?" end
    local ok5, level = pcall(frame.GetFrameLevel, frame)
    if not ok5 or not Plain(level) or type(level) ~= "number" then level = 0 end
    local ok6, kind = pcall(frame.GetObjectType, frame)
    if not ok6 or not Plain(kind) or type(kind) ~= "string" then kind = "?" end
    return { frame = frame, left = left, bottom = bottom, w = w, h = h, scale = scale, strata = strata,
        level = level, kind = kind }
end

-- Every visible frame whose rectangle holds the screen point (sx, sy), topmost first, as facts (see Read).
function Bars.FramesAt(sx, sy)
    local found = {}
    if type(EnumerateFrames) ~= "function" then return found end
    local ok, frame = pcall(EnumerateFrames)
    while ok and frame do
        local fact = Read(frame)
        if fact and fact.w > 0 and fact.h > 0 then
            local s = fact.scale
            if sx >= fact.left * s and sx <= (fact.left + fact.w) * s and sy >= fact.bottom * s
                and sy <= (fact.bottom + fact.h) * s then
                found[#found + 1] = fact
            end
        end
        ok, frame = pcall(EnumerateFrames, frame)
    end
    table.sort(found, function(a, b)
        local sa, sb = STRATA[a.strata] or 3, STRATA[b.strata] or 3
        if sa ~= sb then return sa > sb end
        return a.level > b.level
    end)
    return found
end

local function FramesLines(rest)
    local x, y = (rest or ""):match("^%s*(%-?[%d%.]+)[%s,]+(%-?[%d%.]+)")
    local sx, sy, where
    if x and ns.root then
        local s = ns.root:GetEffectiveScale() or 1
        sx, sy = tonumber(x) * s, (1024 - tonumber(y)) * s
        where = ("%s, %s"):format(x, y)
    else
        sx, sy = GetCursorPosition()
        where = "the pointer"
    end
    local lines = { ("frames at %s:"):format(where) }
    local found = Bars.FramesAt(sx, sy)
    for i = 1, math.min(#found, SHOW_MAX) do
        local f = found[i]
        local top = SafeTop(f.frame)
        lines[#lines + 1] = ("  %s (%s %dx%d, %s %d%s%s)"):format(Chain(f.frame), f.kind, f.w, f.h, f.strata, f.level,
            strays[f.frame] and ", hidden stray" or "", (top and top ~= f.frame) and (", under " .. Chain(top)) or "")
    end
    if #found == 0 then lines[#lines + 1] = "  nothing drawn there" end
    if #found > SHOW_MAX then lines[#lines + 1] = ("  ... and %d more"):format(#found - SHOW_MAX) end
    local hidden = Bars.Strays()
    lines[#lines + 1] = "hidden as stray action bars: " .. (#hidden > 0 and table.concat(hidden, ", ") or "none")
    return lines, found
end

function Bars.FramesCommand(rest)
    if InCombatLockdown() or (ns.InFight and ns.InFight()) then
        ns.Print("/touch frames: out of a fight only.")
        return
    end
    local ok, lines, found = pcall(FramesLines, rest)
    if not ok then
        local problem = tostring(lines)
        if type(ns.db) == "table" then ns.db.framelog = { "frames: could not list: " .. problem } end
        ns.Print("/touch frames: could not list (" .. problem .. ").")
        return
    end
    if type(ns.db) == "table" then ns.db.framelog = lines end
    local top = found[1] and Chain(found[1].frame) or "nothing"
    ns.Print(("%s %d frames, top: %s. Full list saved (/reload writes it)."):format(lines[1], #found, top))
end

-- While Edit Mode is open the game's frames are the game's (R44): a rebuild then leaves them alone.
function Bars:Layout()
    if ns.inEditMode then return end
    want = true
    ns.Queue("bars", HideAll)
    Bars.WatchLate()
end

function Bars:Restore()
    want = false
    ns.Queue("bars", RestoreAll)
end

function Bars:Init()
    if not EventRegistry then return end
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        ns.Guard("EditMode.Enter", function() Bars:Restore() end)
    end, Bars)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        ns.Guard("EditMode.Exit", function() if ns.IsActive() then Bars:Layout() end end)
    end, Bars)
end

-- Some frames are made later, when their add-on loads (Questie, the game's load-on-demand UI).
-- The named frames at once; the walk over every frame for stray bars once a row of loads has settled (many add-ons
-- load one after another at login).
local lookPending = false
ns.On("ADDON_LOADED", function()
    if not want then return end
    ns.Queue("bars_rehide_named", function()
        if want then for _, item in ipairs(Frames()) do HideFrame(item.name, item.frame) end end
    end)
    Bars.WatchLate()
    if lookPending then return end
    lookPending = true
    C_Timer.After(0.2, function()
        lookPending = false
        if want then RehideSoon() end
    end)
end)
-- Frames an add-on makes well after it loads, so neither the login Layout nor an ADDON_LOADED finds them: watched for
-- (one name lookup a second) while the touch screen is active, their add-on is loaded and the frame is not there yet,
-- for at most LATE_WATCH_SECONDS after each Layout / PLAYER_ENTERING_WORLD.
--   Questie_BaseFrame (Questie's tracker, iPad run 8: drawn at the right edge over the page boxes and the item
--   column): made in Questie's start-up thread (QuestieInit Stage 3 -> QuestieTracker.Initialize ->
--   TrackerBaseFrame.Initialize), seconds after PLAYER_LOGIN; the first start after an update compiles QuestieDB
--   first, so the wait is long. Rule: while TouchPlay is active its quest list is the tracker; Questie's tracker goes
--   into the hidden frame (its quest item buttons are its children and go with it), Off / pause / Edit Mode give it
--   back. Questie's settings, map pins and tooltips are not touched.
Bars.LATE = { { frame = "Questie_BaseFrame", addon = "Questie" } }
Bars.LATE_WATCH_SECONDS = 600
local LATE_STEP = 1
local lateUntil, lateWaiting = 0, false

local function AddOnLoaded(name)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(isLoaded) ~= "function" then return false end
    local ok, loaded = pcall(isLoaded, name)
    return ok and loaded and true or false
end

-- A late frame whose add-on is loaded but which is not made yet.
local function LateMissing()
    for _, item in ipairs(Bars.LATE) do
        if type(_G[item.frame]) ~= "table" and AddOnLoaded(item.addon) then return true end
    end
    return false
end

local function LateCheck()
    lateWaiting = false
    if not want then return end
    if not LateMissing() then RehideSoon(); return end
    if GetTime() >= lateUntil then return end
    lateWaiting = true
    C_Timer.After(LATE_STEP, LateCheck)
end

local function WatchLate()
    if not want or not LateMissing() then return end
    lateUntil = GetTime() + Bars.LATE_WATCH_SECONDS
    if lateWaiting then return end
    lateWaiting = true
    C_Timer.After(LATE_STEP, LateCheck)
end
Bars.WatchLate = WatchLate

ns.On("PLAYER_ENTERING_WORLD", function() WatchLate() end)

-- The layout changed (switching or applying one): the game puts its frames back.
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function()
    if want then RehideSoon() end
end)
