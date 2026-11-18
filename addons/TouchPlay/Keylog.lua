-- TouchPlay: /touch keys, a key diagnostic (nothing here is part of play).
--
-- The iPad app sends each touch button's key as a Ctrl-Alt-Shift chord. The game looks a chord up in its own order
-- (ALT-CTRL-SHIFT-), which the contract keys use now; this log stays to show what really arrives. This logs what the game really receives, so the Mac can read it after a /reload:
--   * a keyboard frame (it passes every key on, so bindings and the game still get them) logs every OnKeyDown and
--     OnKeyUp: the key name, the modifier flags, and the binding the game would run for the key;
--   * MODIFIER_STATE_CHANGED (key, down) is logged too, where the client has it;
--   * a PreClick hook on TouchPlay's own secure buttons logs each click that arrives (button, mouse button, down).
-- Every line goes to the chat (short form) and to TouchPlayDB.keylog (full form, the last 400 lines).
--
-- Line formats (full form, fields joined by " | ", T = GetTime() in seconds with milliseconds):
--   key:      T | KD or KU | <key> | mod=CAS | L=CAS | R=CAS | bind=<action> | ovr=<action> | ovr2=<action>
--   modifier: T | MODSTATE | <key> | down=<n> | mod=CAS | L=CAS | R=CAS
--   click:    T | CLICK | <button name> | <mouse button> | down=<0 or 1> | mod=CAS
--   drop:     T | DROP | <item slot> | OnReceiveDrag or click | cursor=<kind:id or -> | pinned, refused or none
--             (iPad run 7: what reached an item slot when something was let go on it; ItemRail.lua)
--   marks:    T | START and T | STOP
-- CAS are the letters C (Control), A (Alt), S (Shift) when that modifier is down, "-" when it is not and "?" when the
-- client has no such function. mod= is IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown; L= and R= are the left and right
-- versions (IsLeftControlKeyDown and so on). bind= is GetBindingAction(key); ovr= is GetBindingAction("ALT-CTRL-SHIFT-"
-- order prefix + key, true) with the modifiers held now (the game's order, TouchPlay's keys); ovr2= is the same with
-- the prefix in the old order (CTRL-ALT-SHIFT-), kept to diagnose a key bound the wrong way round. "-" means no binding. A modifier key's own events skip the binding lookups.
-- The chat gets the same without the time, L= and R=.
--
-- Off changes nothing: no frame takes keys, no event is registered, and a click hook (a game hook cannot be taken
-- away once set) returns at once. Switching On or Off waits for the end of a fight (EnableKeyboard is a protected
-- function); Off in a fight stops the logging at once and finishes after the fight.

local ADDON_NAME, ns = ...

local Keylog = ns.Register("Keylog", {})

local KEEP = 400            -- lines kept in TouchPlayDB.keylog

ns.L["keylog.on"] = "Key log on. Every key and button click prints here and is kept in TouchPlayDB.keylog. /touch keys off stops it."
ns.L["keylog.off"] = "Key log off."
ns.L["keylog.combat"] = "The key log can only be switched on out of a fight."
ns.L["keylog.cleared"] = "Key log cleared."
ns.L["keylog.usage"] = "Use /touch keys [on|off|clear|list]. With no word it switches the key log on or off."

local on = false            -- logging now
local active                -- the keyboard frame while the logger exists
local spare                 -- the frame kept after Off, for the next On (a frame cannot be destroyed)
local hooked = {}           -- buttons that carry the click hook

-- ---------------------------------------------------------------------------------------
-- What a line says

local function Mark(fn, letter)
    if type(fn) ~= "function" then return "?" end
    local ok, down = pcall(fn)
    if not ok then return "?" end
    return down and letter or "-"
end

local function Mods(c, a, s) return Mark(c, "C") .. Mark(a, "A") .. Mark(s, "S") end

local function Held(fn)
    if type(fn) ~= "function" then return false end
    local ok, down = pcall(fn)
    return ok and down and true or false
end

-- The prefix for the modifiers held now, in the game's order (ALT-CTRL-SHIFT-) or the old order (CTRL-ALT-SHIFT-).
local function Prefix(gameOrder)
    local c, a, s = Held(IsControlKeyDown), Held(IsAltKeyDown), Held(IsShiftKeyDown)
    local out = ""
    if gameOrder then
        if a then out = out .. "ALT-" end
        if c then out = out .. "CTRL-" end
    else
        if c then out = out .. "CTRL-" end
        if a then out = out .. "ALT-" end
    end
    if s then out = out .. "SHIFT-" end
    return out
end

local function Binding(key, override)
    if type(GetBindingAction) ~= "function" then return "?" end
    local ok, action = pcall(GetBindingAction, key, override)
    if not ok then return "?" end
    if action == nil or action == "" then return "-" end
    return tostring(action)
end

local function IsModifierName(key)
    if type(key) ~= "string" then return false end
    return key:match("^[LR]?CTRL$") ~= nil or key:match("^[LR]?ALT$") ~= nil
        or key:match("^[LR]?SHIFT$") ~= nil or key:match("^[LR]?META$") ~= nil
end

local function Stamp() return ("%.3f"):format(GetTime()) end

local function Join(separator, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
    return table.concat(parts, separator)
end

-- Adds one line to the saved log (the oldest go past KEEP) and prints the short form.
local function Emit(full, short)
    local db = ns.db
    if type(db) == "table" then
        local log = db.keylog
        if type(log) ~= "table" then
            log = {}
            db.keylog = log
        end
        log[#log + 1] = full
        while #log > KEEP do table.remove(log, 1) end
    end
    if short then ns.Print(short) end
end

local function Sides()
    return Mods(IsLeftControlKeyDown, IsLeftAltKeyDown, IsLeftShiftKeyDown),
        Mods(IsRightControlKeyDown, IsRightAltKeyDown, IsRightShiftKeyDown)
end

local function LogKey(kind, key)
    local mod = Mods(IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown)
    local left, right = Sides()
    local bind, ovr, ovr2 = "-", "-", "-"
    if not IsModifierName(key) then
        bind = Binding(key, false)
        ovr = Binding(Prefix(true) .. tostring(key), true)
        ovr2 = Binding(Prefix(false) .. tostring(key), true)
    end
    Emit(Join(" | ", Stamp(), kind, key, "mod=" .. mod, "L=" .. left, "R=" .. right, "bind=" .. bind, "ovr=" .. ovr,
            "ovr2=" .. ovr2),
        Join(" ", kind, key, "mod=" .. mod, "bind=" .. bind, "ovr=" .. ovr, "ovr2=" .. ovr2))
end

local function LogModifierState(key, down)
    local mod = Mods(IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown)
    local left, right = Sides()
    Emit(Join(" | ", Stamp(), "MODSTATE", key, "down=" .. tostring(down), "mod=" .. mod, "L=" .. left, "R=" .. right),
        Join(" ", "MODSTATE", key, "down=" .. tostring(down), "mod=" .. mod))
end

local function LogClick(button, mouseButton, down)
    local name = button and button.GetName and button:GetName() or "?"
    local mod = Mods(IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown)
    local d = down and 1 or 0
    Emit(Join(" | ", Stamp(), "CLICK", name, tostring(mouseButton), "down=" .. d, "mod=" .. mod),
        Join(" ", "CLICK", name, tostring(mouseButton), "down=" .. d, "mod=" .. mod))
end

-- The handlers never raise into the game: a failure is remembered (like the core's guard) and the next key goes on.
local function Safe(fn, ...)
    local ok, problem = pcall(fn, ...)
    if not ok then ns.RememberError("Keylog: " .. tostring(problem)) end
end

local function OnKeyDown(_, key) if on then Safe(LogKey, "KD", key) end end
local function OnKeyUp(_, key) if on then Safe(LogKey, "KU", key) end end
local function OnEvent(_, event, key, down)
    if on and event == "MODIFIER_STATE_CHANGED" then Safe(LogModifierState, key, down) end
end
local function OnPreClick(self, mouseButton, down) if on then Safe(LogClick, self, mouseButton, down) end end

-- ---------------------------------------------------------------------------------------
-- The logger: a keyboard frame that passes every key on, and the click hooks

local function ButtonNames()
    local names = {}
    for i = 1, 7 do names[#names + 1] = "TouchPlaySpell" .. i end
    for i = 1, 4 do names[#names + 1] = "TouchPlayPage" .. i end
    for i = 1, 4 do names[#names + 1] = "TouchPlayItem" .. i end
    for _, name in ipairs({ "TouchPlayNextTarget", "TouchPlayBags", "TouchPlayMenu", "TouchPlayQuest", "TouchPlayMinimap",
        "TouchPlayPlayer", "TouchPlayTarget", "TouchPlayDismount", "TouchPlayStopAim" }) do
        names[#names + 1] = name
    end
    return names
end

local function HookButtons()
    for _, name in ipairs(ButtonNames()) do
        local button = _G[name]
        if type(button) == "table" and button.HookScript and not hooked[button] then
            hooked[button] = true
            button:HookScript("PreClick", OnPreClick)
        end
    end
end

local function Build()
    local frame = active or spare or CreateFrame("Frame", "TouchPlayKeylog", UIParent)
    spare = nil
    frame:SetScript("OnKeyDown", OnKeyDown)
    frame:SetScript("OnKeyUp", OnKeyUp)
    frame:SetPropagateKeyboardInput(true)       -- the keys still reach the bindings and the game
    frame:EnableKeyboard(true)
    frame:SetScript("OnEvent", OnEvent)
    pcall(frame.RegisterEvent, frame, "MODIFIER_STATE_CHANGED")
    frame:Show()
    active = frame
    HookButtons()
end

local function Teardown()
    local frame = active
    if not frame or on then return end      -- (switched on again before a fight's end: the logger stays)
    active = nil
    frame:SetScript("OnKeyDown", nil)
    frame:SetScript("OnKeyUp", nil)
    frame:SetScript("OnEvent", nil)
    frame:UnregisterAllEvents()
    frame:EnableKeyboard(false)
    frame:Hide()
    spare = frame
end

-- ---------------------------------------------------------------------------------------
-- The switch

function Keylog.IsOn() return on end

-- An item slot was dropped on (ItemRail.Drop): which way it came, what the cursor held, what happened.
function Keylog.Drop(button, via, cursor, result)
    if not on then return end
    Safe(function()
        local name = button and button.GetName and button:GetName() or "?"
        Emit(Join(" | ", Stamp(), "DROP", name, via, "cursor=" .. cursor, result),
            Join(" ", "DROP", name, via, "cursor=" .. cursor, result))
    end)
end

-- The keyboard frame while the logger exists, else nil.
function Keylog.Frame() return active end

function Keylog.Set(want)
    want = want and true or false
    if want == on then return end
    if want then
        if InCombatLockdown() then
            ns.Print(ns.T("keylog.combat"))
            return
        end
        on = true
        Build()
        Emit(Join(" | ", Stamp(), "START"))
        ns.Print(ns.T("keylog.on"))
    else
        on = false              -- the handlers and hooks stop at once
        Emit(Join(" | ", Stamp(), "STOP"))
        ns.Queue("keylog", Teardown)
        ns.Print(ns.T("keylog.off"))
    end
end

function Keylog.Clear()
    if type(ns.db) == "table" then ns.db.keylog = nil end
    ns.Print(ns.T("keylog.cleared"))
end

-- /touch keys [on|off|clear]
function Keylog.Command(word)
    word = (word or ""):lower()
    if word == "" then Keylog.Set(not on)
    elseif word == "on" then Keylog.Set(true)
    elseif word == "off" then Keylog.Set(false)
    elseif word == "clear" then Keylog.Clear()
    else ns.Print(ns.T("keylog.usage")) end
end
