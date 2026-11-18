-- TouchPlay: the contract. The one-line list of touch areas and their keys that the
-- WolkaraForever app reads at game start (contract v1).
--
-- A module registers each touch area with Contract.Area(name, frame, opts); the frame has been
-- placed with ns.Anchor, which keeps its mockup position in frame.touchAnchor. Contract.Write
-- turns the areas into the string
--   TPC1;hold=<s>;hand=<L|R>;turn=<0|1>;world=<key>;outline=<area>,<area>,...;areas=<area>|<area>|...
--   area: <name>,<anchor>,<dx>,<dy>,<w>,<h>,<tap>,<hold>,<press>
-- (outline= lists the areas that always draw something: the app gives only those its gold press outline, see DRAWN
-- below; an app that does not know the field ignores it) and keeps it in TouchPlayDB.contract (the game saves it at logout or reload). The app taps
-- a key; Contract.Apply binds that key to the area's secure button or game command.
--
-- Keys come from the fixed area-name list (NAMES, then EXTRA_NAMES), never from the order areas register in, so
-- an area that is not registered keeps its key free and the others never shift. v1's 26 names keep their keys;
-- the class bar and pet areas added on 16 Nov take keys after them (see EXTRA_NAMES below).
--
-- The list only reaches the app when the game saves it (a reload or a logout), so an area stands for what the
-- character can have, never for what is on screen this moment: a list that followed the screen would ask for a
-- reload every time a pet is called or a vehicle entered.
--
-- Load this file after every module that registers an area (last in the .toc): its Layout
-- reads each frame's placement, so the other modules must have laid out before it.

local ADDON_NAME, ns = ...

local REF_W, REF_H = 1366, 1024      -- the mockups' size in layout units
local MIN_TAP = 44

local Contract = ns.Register("Contract", {})

ns.L["contract.reload"] = "Touch buttons changed. Reload to give them to the app."
ns.L["contract.reloadButton"] = "Reload"
ns.L["contract.keys.header"] = "Touch areas and their keys (hold Ctrl, Alt and Shift with each key):"
ns.L["contract.keys.world"] = "world: %s"
ns.L["contract.keys.line"] = "%s: tap %s, hold %s, press %s"
ns.L["contract.keys.none"] = "No touch areas yet."

-- ---------------------------------------------------------------------------------------
-- Names and keys

Contract.NAMES = {
    "spell1", "spell2", "spell3", "spell4", "spell5", "spell6", "spell7",
    "page1", "page2", "page3", "page4", "nexttarget",
    "item1", "item2", "item3", "item4",
    "bags", "menu", "player", "target", "quest", "minimap", "chat",
    "interact", "jump", "dive",
}

-- The game builds a key chord in the fixed order ALT, CTRL, SHIFT, META (Blizzard_SharedXML KeyCommand.lua and
-- BindingUtil.lua), and looks a binding up by that string. A chord written in another order ("CTRL-ALT-SHIFT-F2")
-- is never found, so the key falls through to the bare key. Every key in the pool is therefore in the game's order.
local PREFIX = "ALT-CTRL-SHIFT-"

-- F1..F12, 1..9, 0, then the letters except W, A, S, D: 44 keys, in this order (ruling A22).
-- The app's walk stick holds the plain W, A, S and D keys, and it sends keys by key code: a chord on
-- one of those letters shares the key code, so its key-up would release the held walk key.
local WALK_LETTERS = { W = true, A = true, S = true, D = true }
local POOL = {}
do
    local function add(key) POOL[#POOL + 1] = PREFIX .. key end
    for i = 1, 12 do add("F" .. i) end
    for i = 1, 9 do add(tostring(i)) end
    add("0")
    for c = ("A"):byte(), ("Z"):byte() do
        local letter = string.char(c)
        if not WALK_LETTERS[letter] then add(letter) end
    end
end
Contract.POOL = POOL
Contract.WORLD_KEY = POOL[1]

-- Which names have which kind of key.
local function HasTap(name) return name ~= "jump" and name ~= "dive" end
local function HasHold(name)
    return name:match("^spell%d$") ~= nil or name:match("^item%d$") ~= nil
        or name == "player" or name == "target" or name == "quest"
        or name == "interact"       -- the app sends it on an aim-lift over Interact: cancels a ground-spell aim
end
local function HasPress(name) return name == "jump" or name == "dive" end

-- KEYS[name] = { tap =, hold =, press = }: the pool, handed out down the name list.
local KEYS = {}
do
    local nextKey = 2                  -- POOL[1] is the world key
    for _, name in ipairs(Contract.NAMES) do
        KEYS[name] = {}
        if HasTap(name) then KEYS[name].tap = POOL[nextKey]; nextKey = nextKey + 1 end
    end
    for _, name in ipairs(Contract.NAMES) do
        if HasHold(name) then KEYS[name].hold = POOL[nextKey]; nextKey = nextKey + 1 end
    end
    for _, name in ipairs(Contract.NAMES) do
        if HasPress(name) then KEYS[name].press = POOL[nextKey]; nextKey = nextKey + 1 end
    end
end

-- ---------------------------------------------------------------------------------------
-- The class bars and the pet (16 Nov): areas added after v1's 26, keys handed out after v1's, so no v1 key moves.
--
-- pet1..pet10 are the pet row's slots and stance1..stance10 the stance row's; slot k of either row has the same
-- tap and hold key, because a character has one row or the other (ClassBars registers one, never both; Write
-- refuses two areas on one key). petcard is the pet's card, leave the vehicle's Leave, petfeed the hunter's Feed
-- pet. The app reads these as it reads any area: the contract stays TPC1.
--
-- Keys: the two the v1 list left free (Y and Z, which every app build can send) go to slot 1 and slot 2's taps;
-- the rest are keys the app must learn to send (NEW_KEYS: the keypad and F13..F19). An app that does not know a
-- key gives that area no key: the area still takes the finger, and nothing happens.
Contract.NEW_KEYS = {
    "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0",
    "NUMPADPLUS", "NUMPADMINUS", "NUMPADMULTIPLY", "NUMPADDIVIDE", "NUMPADDECIMAL",
    "F13", "F14", "F15", "F16", "F17", "F18", "F19",
}
local SLOTS = 10
Contract.EXTRA_NAMES = { "petcard" }
for i = 1, SLOTS do Contract.EXTRA_NAMES[#Contract.EXTRA_NAMES + 1] = "pet" .. i end
for i = 1, SLOTS do Contract.EXTRA_NAMES[#Contract.EXTRA_NAMES + 1] = "stance" .. i end
Contract.EXTRA_NAMES[#Contract.EXTRA_NAMES + 1] = "leave"
Contract.EXTRA_NAMES[#Contract.EXTRA_NAMES + 1] = "petfeed"

-- Every area name, v1's first, in the order the contract lists them.
Contract.ALL_NAMES = {}
for _, name in ipairs(Contract.NAMES) do Contract.ALL_NAMES[#Contract.ALL_NAMES + 1] = name end
for _, name in ipairs(Contract.EXTRA_NAMES) do Contract.ALL_NAMES[#Contract.ALL_NAMES + 1] = name end

-- Whether an area always draws something, in every state the character can be in (the press outline, app 7f94abf:
-- the app outlines the areas in the contract's outline= list and no others; an unlisted area still takes the finger
-- and sends its keys). Every area name must choose, true or false: a name with no flag stops the add-on at load, so
-- a new area cannot reach the app by accident with the wrong outline. true = something is always there to outline
-- (an item slot that is empty still shows its dashed "+" card). false = it can be empty or hidden (the target card
-- with no target, the quest list, the pet and stance rows, the pet card, Feed pet, Leave).
local DRAWN = {}
Contract.DRAWN = DRAWN
do
    local function flag(drawn, names) for _, name in ipairs(names) do DRAWN[name] = drawn end end
    flag(true, { "spell1", "spell2", "spell3", "spell4", "spell5", "spell6", "spell7",
        "page1", "page2", "page3", "page4", "nexttarget", "item1", "item2", "item3", "item4",
        "bags", "menu", "player", "minimap", "chat", "interact", "jump", "dive" })
    flag(false, { "target", "quest", "petcard", "leave", "petfeed" })
    for i = 1, SLOTS do flag(false, { "pet" .. i, "stance" .. i }) end
    for _, name in ipairs(Contract.ALL_NAMES) do
        assert(type(DRAWN[name]) == "boolean", "TouchPlay: area " .. name .. " must say whether it is always drawn (Contract.DRAWN)")
    end
    for name in pairs(DRAWN) do
        local real = false
        for _, n in ipairs(Contract.ALL_NAMES) do if n == name then real = true end end
        assert(real, "TouchPlay: Contract.DRAWN names " .. name .. ", which is not an area")
    end
end

do
    local used = {}
    for _, keys in pairs(KEYS) do
        for _, key in pairs(keys) do used[key] = true end
    end
    used[POOL[1]] = true
    local extra = {}
    for _, key in ipairs(POOL) do if not used[key] then extra[#extra + 1] = key end end
    for _, key in ipairs(Contract.NEW_KEYS) do extra[#extra + 1] = PREFIX .. key end
    Contract.EXTRA_POOL = extra
    local nextKey = 1
    local function take()
        local key = assert(extra[nextKey], "TouchPlay: the extra key pool is smaller than the new areas need")
        nextKey = nextKey + 1
        return key
    end
    local taps, holds = {}, {}
    for i = 1, SLOTS do taps[i] = take() end
    for i = 1, SLOTS do holds[i] = take() end
    for i = 1, SLOTS do
        KEYS["pet" .. i] = { tap = taps[i], hold = holds[i] }
        KEYS["stance" .. i] = { tap = taps[i], hold = holds[i] }
    end
    KEYS.petcard = { tap = take(), hold = take() }
    KEYS.leave = { tap = take() }
    KEYS.petfeed = { tap = take() }
end

-- Load-time checks: the pool covers every key the areas need, and none is a walk letter.
do
    local needed = 1                                   -- the world key
    for _, name in ipairs(Contract.NAMES) do
        if HasTap(name) then needed = needed + 1 end
        if HasHold(name) then needed = needed + 1 end
        if HasPress(name) then needed = needed + 1 end
    end
    assert(#POOL >= needed, "TouchPlay: the key pool is smaller than the areas need")
    for _, key in ipairs(POOL) do
        assert(not key:match("%-[WASD]$"), "TouchPlay: the key pool holds a walk key: " .. key)
    end
end

-- The tap, hold and press key of an area name (nil where the name has none).
function Contract.KeysFor(name)
    local keys = KEYS[name]
    if not keys then return nil end
    return keys.tap, keys.hold, keys.press
end

-- ---------------------------------------------------------------------------------------
-- Feel settings (read at every Write)

-- The one table of Touch settings and their defaults (Feel.lua edits them, TouchPlayDB.feel keeps the
-- changes). reduceMotion is "auto": it follows the game's own setting until the player picks yes or no.
Contract.FEEL_DEFAULTS = {
    leftHanded = false, stand = false, buttonSize = 1.0, textSize = 1.0, hold = 0.45,
    turnWithView = true, edgeRun = true, holdRisky = true, tapSounds = true, floatingNumbers = true,
    reduceMotion = "auto",
    -- Targeting (18 Nov, no mockup: defaults pending the tester's approval): the game's soft targeting and bigger
    -- enemy name plates while Touch is on (Targeting.lua)
    autoTarget = true, bigPlates = true,
    -- Sharp screen (ruling A39, 18 Nov): the game's RenderScale keeps the 3D world at today's pixels while the app
    -- draws at the panel's own (Sharp.lua)
    sharpScreen = true,
}
Contract.FEEL_RANGES = { buttonSize = { 0.8, 1.4 }, textSize = { 0.8, 1.4 }, hold = { 0.3, 0.8 } }

-- A setting as the add-on uses it: the saved value when it is of the right kind (numbers kept inside
-- their range), else the default. Nothing here writes.
function Contract.GetFeel(key)
    local default = Contract.FEEL_DEFAULTS[key]
    if default == nil then return nil end
    local saved = ns.db and ns.db.feel
    local value
    if type(saved) == "table" then value = saved[key] end
    if key == "reduceMotion" then
        if type(value) == "boolean" then return value end
        return default
    end
    if type(value) ~= type(default) then return default end
    if type(value) == "number" then
        if value ~= value then return default end
        local range = Contract.FEEL_RANGES[key]
        if range then value = math.max(range[1], math.min(range[2], value)) end
    end
    return value
end

-- The three settings the contract carries, as the add-on uses them (the hold kept inside its range).
local function Feel()
    return Contract.GetFeel("hold"), Contract.GetFeel("leftHanded"), Contract.GetFeel("turnWithView")
end

-- Two decimals at most, no trailing zeros: 0.45 -> "0.45", 0.6 -> "0.6", 1 -> "1".
local function FormatSeconds(seconds)
    local text = ("%.2f"):format(seconds):gsub("0+$", ""):gsub("%.$", "")
    return text
end

-- ---------------------------------------------------------------------------------------
-- Areas

local areas = {}
local CORNERS = { TL = true, TR = true, BL = true, BR = true }
local KINDS = { "tap", "hold", "press" }

local function CheckAction(name, kind, spec)
    if spec == nil then return end
    if not KEYS[name][kind] then
        error("TouchPlay: area " .. name .. " has no " .. kind .. " key", 3)
    end
    if type(spec) ~= "table" or (type(spec.click) ~= "string" and type(spec.command) ~= "string") then
        error("TouchPlay: area " .. name .. " " .. kind .. " needs a click button name or a command", 3)
    end
end

-- Registers (or replaces) an area. opts.anchor is the screen corner the numbers count from
-- (the frame's own anchor corner when left out); opts.tap, opts.hold, opts.press say what the
-- key does: { click = buttonName, button = mouseButton } or { command = bindingCommand }.
function Contract.Area(name, frame, opts)
    if not KEYS[name] then error("TouchPlay: unknown area " .. tostring(name), 2) end
    opts = opts or {}
    if opts.anchor ~= nil and not CORNERS[opts.anchor] then
        error("TouchPlay: area " .. name .. " has unknown corner " .. tostring(opts.anchor), 2)
    end
    for _, kind in ipairs(KINDS) do CheckAction(name, kind, opts[kind]) end
    areas[name] = {
        frame = frame, anchor = opts.anchor, tap = opts.tap, hold = opts.hold, press = opts.press,
    }
end

-- Takes an area away (a stance the character no longer has, a class bar row it does not use).
function Contract.Drop(name)
    if not KEYS[name] then error("TouchPlay: unknown area " .. tostring(name), 2) end
    areas[name] = nil
end

-- Whether an area is registered now.
function Contract.Has(name) return areas[name] ~= nil end

local function Round(value) return math.floor(value + 0.5) end

-- The area's numbers: corner, dx, dy, w, h in whole layout units. dx and dy run from the
-- screen corner to the area's own matching corner. An area under 44 units grows to 44 around
-- the same centre (the add-on grows the tap area the same way).
local function Geometry(name, area)
    local a = area.frame.touchAnchor
    if not a or not a.x or not a.w then
        error("TouchPlay: area " .. name .. " was never placed with ns.Anchor", 0)
    end
    local corner = area.anchor or a.corner
    -- a left-handed element sits on the other side: the corner it counts from flips with it
    if a.mirrored and area.anchor then corner = ns.MirrorCorner(corner) end
    local x, y, w, h = a.x, a.y, a.w, a.h
    if w < MIN_TAP then x = x - (MIN_TAP - w) / 2; w = MIN_TAP end
    if h < MIN_TAP then y = y - (MIN_TAP - h) / 2; h = MIN_TAP end
    x, y, w, h = Round(x), Round(y), Round(w), Round(h)
    local dx = (corner == "TL" or corner == "BL") and x or REF_W - (x + w)
    local dy = (corner == "TL" or corner == "TR") and y or REF_H - (y + h)
    return corner, dx, dy, w, h
end

-- ---------------------------------------------------------------------------------------
-- The reload notice: shown when the written list differs from the one the app read

local notice = ns.Kit.Card(ns.root)
notice:SetFrameStrata(ns.Kit.SHEET_STRATA)   -- above every window, as the other cards (iPad run 6)
notice:SetLines({ ns.T("contract.reload") })
notice:SetButtons({ { label = ns.T("contract.reloadButton") } })
notice:SetFrameLevel(50)
notice:Hide()
Contract.notice = notice

-- Where the notice goes: below the cards and the Bags and Menu rings (y 192), centred; clear of every touch area laid
-- out now (the quest list moves with the hand). Out of combat only: the notice holds the secure reload.
local NOTICE_Y, NOTICE_GAP = 192, 10
local placed = {}

local function Clear(x, y, w, h)
    local function hits(frame, always)
        if not frame or not frame.touchAnchor or not (always or frame:IsShown()) then return false end
        local a = frame.touchAnchor
        local ox, oy, ow, oh = ns.TapRect(a.x, a.y, a.w, a.h)
        return x < ox + ow and ox < x + w and y < oy + oh and oy < y + h
    end
    for _, area in pairs(areas) do
        if hits(area.frame, true) then return false end
    end
    local bars = ns.ClassBars
    for _, b in ipairs(bars and bars.pet or {}) do if hits(b, true) then return false end end
    for _, b in ipairs(bars and bars.stance or {}) do if hits(b) then return false end end
    for _, o in ipairs(ns.ThumbAreas(placed)) do
        if x < o.x + o.w and o.x < x + w and y < o.y + o.h and o.y < y + h then return false end
    end
    return x >= 0 and x + w <= REF_W and y + h <= REF_H
end

local function PlaceNotice()
    local w, h = notice:GetSize()
    local x, y = (REF_W - w) / 2, NOTICE_Y
    local quest = areas.quest and areas.quest.frame.touchAnchor
    if not Clear(x, y, w, h) and quest then
        if Clear(quest.x + quest.w + NOTICE_GAP, y, w, h) then
            x = quest.x + quest.w + NOTICE_GAP
        elseif Clear(x, quest.y + quest.h + NOTICE_GAP, w, h) then
            y = quest.y + quest.h + NOTICE_GAP
        end
    end
    ns.Anchor(notice, "TL", x, y)
end
PlaceNotice()

-- The red button is the picture; this secure button over it does the /reload (out of combat).
local reload = CreateFrame("Button", "TouchPlayReloadButton", notice, "SecureActionButtonTemplate")
reload:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
reload:SetAllPoints(notice.buttons[1])
reload:SetFrameLevel(notice.buttons[1]:GetFrameLevel() + 2)
reload:RegisterForClicks("AnyUp")
reload:SetAttribute("type", "macro")
reload:SetAttribute("macrotext", "/reload")
ns.Kit.AddPress(reload, "rect", notice.buttons[1])   -- the red button's own press look
Contract.reloadButton = reload

-- ---------------------------------------------------------------------------------------
-- The world key: a secure button with no action yet (Task 6 gives it the mouseover card)

local worldHold = CreateFrame("Button", "TouchPlayWorldHold", UIParent, "SecureActionButtonTemplate")
worldHold:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
worldHold:RegisterForClicks("AnyUp", "AnyDown")
worldHold:Hide()
Contract.WorldHold = worldHold

-- ---------------------------------------------------------------------------------------
-- Write

local needsReload = false
-- Whether what the app reads (the contract list, the auto-run switch) differs from what it read at this login.
function Contract.NeedsReload() return needsReload end

-- Builds the contract string, keeps it in TouchPlayDB.contract and returns it. When it differs
-- from the list the app read at game start, offers the reload.
function Contract.Write()
    local hold, left, turn = Feel()
    local list, outline, owners = {}, {}, { [Contract.WORLD_KEY] = "world" }
    for _, name in ipairs(Contract.ALL_NAMES) do
        local area = areas[name]
        if area then
            local corner, dx, dy, w, h = Geometry(name, area)
            local keys = KEYS[name]
            -- two areas on one key would bind it twice (pet k and stance k share theirs): never write that
            for _, kind in ipairs(KINDS) do
                local key = area[kind] and keys[kind]
                if key then
                    if owners[key] then
                        error("TouchPlay: areas " .. owners[key] .. " and " .. name .. " share the key " .. key, 0)
                    end
                    owners[key] = name
                end
            end
            if DRAWN[name] then outline[#outline + 1] = name end
            list[#list + 1] = ("%s,%s,%d,%d,%d,%d,%s,%s,%s"):format(name, corner, dx, dy, w, h,
                area.tap and keys.tap or "", area.hold and keys.hold or "", area.press and keys.press or "")
        end
    end
    local text = ("TPC1;hold=%s;hand=%s;turn=%d;world=%s;outline=%s;areas=%s"):format(
        FormatSeconds(hold), left and "L" or "R", turn and 1 or 0, Contract.WORLD_KEY,
        table.concat(outline, ","), table.concat(list, "|"))
    ns.db.contract = text
    -- the app also reads the auto-run switch from the saved file (TouchContract.m AKParseEdgeRun), written at a reload
    local changed = text ~= Contract.loadedAtLogin or Contract.GetFeel("edgeRun") ~= Contract.edgeRunAtLogin
    needsReload = changed
    ns.Queue("contract notice", function()
        PlaceNotice()
        notice:SetShown(changed)
        if ns.Feel and ns.Feel.IsOpen and ns.Feel.IsOpen() then ns.Feel.Repaint() end
        -- the first-run guide waits for the notice to be answered (the reload), so the two never share the
        -- screen (iPad run 1); with nothing to reload it may start now
        if not changed and ns.Guide and ns.Guide.MaybeStart then ns.Guard("guide start", ns.Guide.MaybeStart) end
    end)
    return text
end

-- ---------------------------------------------------------------------------------------
-- Bindings

local owner = CreateFrame("Frame", "TouchPlayBindings", UIParent)

-- A spec with a gate (a secure handler, Hud's quest gate) is not bound here: the gate gets the key and binds it
-- itself only while its content is there ("key" and "live" attributes; its snippet does the binding, in a fight too).
local gates = {}            -- gate -> true for every gate an area names

local function Bind(key, spec)
    if spec.gate then
        gates[spec.gate] = true
        spec.gate:SetAttribute("key", key)
        spec.gate:SetAttribute("live", true)
        return
    end
    if spec.click then
        SetOverrideBindingClick(owner, true, key, spec.click, spec.button)
    else
        SetOverrideBinding(owner, true, key, spec.command)
    end
end

-- What stays bound when the add-on pauses: Jump, Dive/Dismount and Interact.
local KEEP = { jump = "press", dive = "press", interact = "tap" }

-- Keys that are not part of the contract (the app does not read them) and stay bound through a
-- pause and when the add-on is switched Off: key -> { command = ... } or { click = ... }. The chat
-- strip asks for bare F12, which the keyboard's Send key types first, so typing never goes nowhere.
local keepKeys = {}

-- Registers a key that stays bound always. Takes effect at the next Apply or OnPause.
function Contract.KeepKey(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table"
        or (type(spec.click) ~= "string" and type(spec.command) ~= "string") then
        error("TouchPlay: KeepKey needs a key and a { click = } or { command = }", 2)
    end
    keepKeys[key] = spec
end

-- ---------------------------------------------------------------------------------------
-- Press feedback from the keys (polish pass, 18 Nov)
--
-- The app sends a tap's key down and up when the finger lifts, and a press key (Jump, Dive) down when it lands and up
-- when it lifts. A keyboard frame that passes every key on (as /touch keys does, so the bindings and the game still
-- get them) sees each key of a bound area and lights that area's press look (Kit.PressDown at the key's down,
-- Kit.PressUp at its up). Only the area's tap and press keys light it; a hold opens the info card, the app draws the
-- hold ring. The key up releases what its down lit whatever modifiers are left by then, so nothing stays lit.
-- EnableKeyboard waits for the end of a fight (the game protects it); once on it stays on, in a fight too.

local pressByKey = {}       -- "ALT-CTRL-SHIFT-<key>" -> the area's frame, for the keys bound now
local pressKind = {}        -- the same keys -> "tap" or "press" (a press key is held while the finger is down)
local litByKey = {}         -- bare key -> the frame its down lit
local litTap = nil          -- the one tap area lit now: { key = bare key, frame = its frame }
Contract.pressByKey = pressByKey

local function AllHeld()
    return IsAltKeyDown and IsAltKeyDown() and IsControlKeyDown and IsControlKeyDown()
        and IsShiftKeyDown and IsShiftKeyDown()
end

-- Why a look can stay lit (iPad, 18 Nov): the key down lights the area, then a window opens (the Bags button), or the
-- keyboard goes to another box, or the frame hides, and the key up never reaches this watcher. So every look also lets
-- go on any of: a window opening or closing (Signal), a fight starting or ending, one of our sheets showing, the area
-- or this watcher hiding, the pulse box taking focus; a tap area also after Kit.PRESS_TAP_MAX seconds; and only one
-- tap area is ever lit (a new tap key's down lets the earlier one go). A press key (Jump, Dive, Mount) has no time
-- limit: it is lit for as long as the finger is down, unless one of the above happens.
function Contract.ReleaseLit()
    for key in pairs(litByKey) do litByKey[key] = nil end
    litTap = nil
    if ns.Kit.PressLetGoAll then ns.Kit.PressLetGoAll() end
end

local function OnPressKeyDown(_, key)
    if type(key) ~= "string" or not AllHeld() then return end
    local frame = pressByKey[PREFIX .. key]
    if not frame or not frame.touchPress then return end
    local tap = pressKind[PREFIX .. key] ~= "press"
    if tap and litTap and litTap.frame ~= frame then
        local earlier = litTap
        litTap = nil
        litByKey[earlier.key] = nil
        ns.Kit.PressUp(earlier.frame)           -- one tap area lit at a time
    end
    litByKey[key] = frame
    if tap then litTap = { key = key, frame = frame } end
    ns.Kit.PressDown(frame, tap and ns.Kit.PRESS_TAP_MAX or nil)
end

local function OnPressKeyUp(_, key)
    local frame = type(key) == "string" and litByKey[key]
    if not frame then return end
    litByKey[key] = nil
    if litTap and litTap.key == key then litTap = nil end
    ns.Kit.PressUp(frame)
end

local pressKeys = CreateFrame("Frame", "TouchPlayPressKeys", UIParent)
pressKeys:SetScript("OnKeyDown", function(self, key) ns.Guard("press key", OnPressKeyDown, self, key) end)
pressKeys:SetScript("OnKeyUp", function(self, key) ns.Guard("press key", OnPressKeyUp, self, key) end)
pressKeys:HookScript("OnHide", function() ns.Guard("press key", Contract.ReleaseLit) end)
Contract.pressKeys = pressKeys
ns.On("PLAYER_REGEN_DISABLED", function() Contract.ReleaseLit() end, true)
ns.On("PLAYER_REGEN_ENABLED", function() Contract.ReleaseLit() end, true)

local function ListenForKeys()
    pressKeys:SetPropagateKeyboardInput(true)   -- every key still reaches the bindings and the game
    pressKeys:EnableKeyboard(true)
    pressKeys:Show()
end

local function BindAll(keepOnly)
    ClearOverrideBindings(owner)
    for key in pairs(pressByKey) do pressByKey[key] = nil; pressKind[key] = nil end
    for gate in pairs(gates) do gate:SetAttribute("live", false) end
    for key, spec in pairs(keepKeys) do Bind(key, spec) end
    if not keepOnly then Bind(Contract.WORLD_KEY, { click = "TouchPlayWorldHold" }) end
    for _, name in ipairs(Contract.ALL_NAMES) do
        local area = areas[name]
        if area then
            for _, kind in ipairs(KINDS) do
                if area[kind] and (not keepOnly or KEEP[name] == kind) then
                    Bind(KEYS[name][kind], area[kind])
                    if kind ~= "hold" then
                        pressByKey[KEYS[name][kind]] = area.frame
                        pressKind[KEYS[name][kind]] = kind
                    end
                end
            end
        end
    end
end

-- Binds every area's keys and the world key, replacing what was bound. Waits for the end of a
-- fight (the game refuses binding changes in combat).
function Contract.Apply()
    ns.Queue("contract bindings", function() BindAll(false) end)
end

-- The add-on paused: only the keys for Jump, Dive/Dismount and Interact (and the KeepKey keys) stay. Called from
-- ns.Pause; shares the queue key with Apply, so the last of the two wins.
local function ReleaseAll()
    for key in pairs(litByKey) do litByKey[key] = nil end
    litTap = nil
    if ns.Kit.PressReleaseAll then ns.Kit.PressReleaseAll() end
end
ns.On("PLAYER_LEAVING_WORLD", ReleaseAll, true)

function Contract.OnPause()
    ReleaseAll()
    ns.Queue("contract bindings", function() BindAll(true) end)
end

-- ---------------------------------------------------------------------------------------
-- /touch keys

local function Short(key) return key and key:sub(#PREFIX + 1) or "-" end

function Contract.PrintKeys()
    ns.Print(ns.T("contract.keys.header"))
    ns.Print(ns.T("contract.keys.world", Short(Contract.WORLD_KEY)))
    local any = false
    for _, name in ipairs(Contract.ALL_NAMES) do
        local area = areas[name]
        if area then
            any = true
            local keys = KEYS[name]
            ns.Print(ns.T("contract.keys.line", name, Short(area.tap and keys.tap),
                Short(area.hold and keys.hold), Short(area.press and keys.press)))
        end
    end
    if not any then ns.Print(ns.T("contract.keys.none")) end
end

-- ---------------------------------------------------------------------------------------
-- Module steps

-- The list the app read at game start is the one saved before this session wrote anything.
function Contract:Init()
    Contract.loadedAtLogin = ns.db.contract
    Contract.edgeRunAtLogin = Contract.GetFeel("edgeRun")
    ns.Queue("press keys", ListenForKeys)
end

function Contract:Layout()
    Contract.laidOut = true
    Contract.Write()
    Contract.Apply()
end

-- A module changed which areas it has after the first layout (a stance learnt, a class bar row): write and bind again.
function Contract.Changed()
    if not Contract.laidOut then return end       -- the first layout writes everything anyway
    Contract.Write()
    Contract.Apply()
end
