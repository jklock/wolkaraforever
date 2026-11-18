-- TouchPlay: world taps, tuned for touch (phase-1 close-out, 18 Nov). On the iPad (16 Nov): "I could click an enemy NPC but
-- it was a bit challenging to get the click to be on target". A finger is wider than a mouse pointer, so while Touch
-- is on this file turns on what the game itself offers for aiming without a pointer (scope v2: "the game's own soft
-- targeting and Forever's controller targeting, tuned for touch"), all of it plain CVars the game's own settings write:
--
--   * Auto-target the enemy in front (Touch settings switch `autoTarget`): SoftTargetEnemy 3 = soft enemy targeting
--     for keys and mouse too (the game's own "Enable Action Targeting", Combat.lua:183-195; 1 = gamepad only, the
--     game's default; the app's chords are keys, so 1 does nothing for a touch player). A spell tapped with no target
--     then goes to the enemy the character faces. SoftTargetIconEnemy 1 marks that enemy (the game's "Interact Key
--     Icons" CVars, Accessibility.lua:176-206), so the player sees which one a tap will hit.
--   * Bigger name plates to tap (switch `bigPlates`): enemy plates on (nameplateShowEnemies) and shown out of a fight
--     too (nameplateShowAll, Nameplates.lua:461), Large size (nameplateSize 3 = Enum.NamePlateSize.Large,
--     Nameplates.lua:560-570; the game clamps a plate's tap area to the plate, NamePlateManagerDocumentation.lua:50) and
--     enemy plates kept apart (nameplateStackingTypes, Enemy bit, Nameplates.lua:528-548), so two plates never sit on
--     top of each other under one finger. A plate tap targets like a click on the model, only bigger.
--   * Always while Touch is on, no switch: SoftTargetIconInteract and SoftTargetIconGameObject 1, the game's mark over
--     the person or object the Interact button will use (Interact.lua names it under its word too).
--
-- SoftTargetInteract stays Interact.lua's own (raised to 3 since Task 11, kept through a pause). Never touched here:
-- autoSelfCast, the SELFCAST modifier, SoftTargetFriend (a friendly soft target would take a heal the game sends to
-- the player), enableMouseoverCast, SoftTargetForce (the target following the soft enemy: left for a device trial).
-- TouchPlay's own spell buttons ask for no unit (R40: `*type1`, no self, focus or mouseover cast; Cluster.lua), so the
-- game picks the unit: the target, else the soft enemy for a harmful spell, else the player for a helpful one.
--
-- The player's own values come first:
--   * a CVar this client does not know (GetCVar answers nil) is left alone; a value that already does the job (keys
--     already soft target, plates already Large or bigger) is not changed;
--   * the first value of each CVar Touch changes is kept account-wide in TouchPlayDB.targetHeld (name -> was, ours),
--     never overwritten by our own value (a /reload, a second character);
--   * Off, a pause and Edit Mode give every held value back exactly (only where it still reads ours);
--   * a value the player changes away from ours, while Touch is on or off, stands: Touch stops holding it and does not
--     apply it again for that character (TouchPlayCharDB.targetDeclined) until Defaults in Touch settings, or the
--     player ticks that switch again;
--   * no CVar is set while the game's combat lockdown is up: every change goes through ns.Queue (some, like the name
--     plate ones, are refused in a fight) and runs at the end of the fight.
-- /touch targeting prints what the client has (also the read-only arc, range and force CVars) and keeps it in
-- TouchPlayDB.targetLog for the Mac.

local ADDON_NAME, ns = ...

local Targeting = ns.Register("Targeting", {})

-- The switch each group follows; "interact" has none (on whenever Touch is).
local GROUP_KEY = { autoTarget = "autoTarget", bigPlates = "bigPlates" }

local function AtLeast(n) return function(cur) return (tonumber(cur) or 0) >= n end end

-- name, group, the value Touch sets (want), or a bit of a bitfield CVar (bit = the Enum.NamePlateStackType field);
-- ok(cur) says the current value already does the job (default: it is `want`).
Targeting.DEFS = {
    { name = "SoftTargetEnemy", group = "autoTarget", want = "3",
      ok = function(cur) local n = tonumber(cur); return n == 2 or n == 3 end },
    { name = "SoftTargetIconEnemy", group = "autoTarget", want = "1" },
    { name = "SoftTargetIconInteract", group = "interact", want = "1" },
    { name = "SoftTargetIconGameObject", group = "interact", want = "1" },
    { name = "nameplateShowEnemies", group = "bigPlates", want = "1" },
    { name = "nameplateShowAll", group = "bigPlates", want = "1" },
    { name = "nameplateSize", group = "bigPlates", want = "3", ok = AtLeast(3) },
    { name = "nameplateStackingTypes", group = "bigPlates", bit = "Enemy" },
}
local DEFS = Targeting.DEFS

-- Read only, for /touch targeting: the engine's own targeting CVars (not in the game's Lua, so their values are the
-- device's to show), and the ones Touch must never change.
Targeting.WATCH = {
    "SoftTargetInteract", "SoftTargetEnemyArc", "SoftTargetEnemyRange", "SoftTargetForce", "SoftTargetFriend",
    "SoftTargetInteractArc", "SoftTargetInteractRange", "SoftTargetNameplateEnemy", "SoftTargetNameplateInteract",
    "SoftTargetTooltipEnemy", "SoftTargetTooltipInteract", "SoftTargetLowPriorityIcons", "autoSelfCast",
    "enableMouseoverCast", "GamePadEnable", "ActionButtonUseKeyDown",
}

ns.L["targeting.status"] = "Targeting: auto-target %s, bigger name plates %s, %d held by Touch."
ns.L["targeting.on"] = "on"
ns.L["targeting.off"] = "off"
ns.L["targeting.unknown"] = "not in this client"
ns.L["targeting.held"] = "Touch's (yours %s)"
ns.L["targeting.declined"] = "yours, Touch stands aside"
ns.L["targeting.game"] = "the game's"

local LOG_MAX = 80

-- ---------------------------------------------------------------------------------------
-- The saved state

local function Table(owner, key)
    if type(owner) ~= "table" then return {} end
    local t = owner[key]
    if type(t) ~= "table" then t = {}; owner[key] = t end
    return t
end
local function Held() return Table(ns.db, "targetHeld") end           -- account-wide: name -> { was, ours }
local function Given() return Table(ns.db, "targetGiven") end         -- account-wide: name -> the value put back
local function Declined() return Table(ns.char, "targetDeclined") end -- per character: name -> true

local function Log(line)
    local db = ns.db
    if type(db) ~= "table" then return end
    local log = Table(db, "targetLog")
    log[#log + 1] = (date and date("%H:%M:%S ") or "") .. line
    while #log > LOG_MAX do table.remove(log, 1) end
end

function Targeting.Held(name) return ns.db ~= nil and type(ns.db.targetHeld) == "table" and ns.db.targetHeld[name] ~= nil end

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
    return (pcall(set, name, value))
end

local function BitIndex(def)
    local e = Enum and Enum.NamePlateStackType
    if not (def.bit and e and e[def.bit] and GetCVarBitfield and SetCVarBitfield) then return nil end
    return e[def.bit]
end

-- Whether the client knows this CVar (and, for a bit, the bitfield API), and its value now.
local function Current(def)
    local cur = Read(def.name)
    if cur == nil then return nil end
    if def.bit and not BitIndex(def) then return nil end
    return cur
end

local function Ok(def, cur)
    if def.bit then
        local ok, on = pcall(GetCVarBitfield, def.name, BitIndex(def))
        return ok and on and true or false
    end
    if def.ok then return def.ok(cur) end
    return cur == def.want
end

local function Set(def)
    if def.bit then return (pcall(SetCVarBitfield, def.name, BitIndex(def), true)) end
    return Write(def.name, def.want)
end

local function GroupOn(group)
    local key = GROUP_KEY[group]
    if not key then return true end
    return ns.Contract.GetFeel(key) == true
end

-- ---------------------------------------------------------------------------------------
-- Applying and giving back (only ever called out of the combat lockdown: Sync queues them)

-- Gives one held value back: only where it still reads ours; a value the player changed stands (and is theirs now).
local function GiveOne(name, held)
    local cur = Read(name)
    Held()[name] = nil
    if cur == nil then return end
    if cur ~= held.ours then
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

local function ApplyNow()
    local held, declined, given = Held(), Declined(), Given()
    for _, def in ipairs(DEFS) do
        local name = def.name
        local cur = Current(def)
        local h = held[name]
        if cur == nil then
            -- not in this client: nothing to do (a held entry from elsewhere stays for the Off that gives it back)
        elseif h then
            if cur ~= h.ours then
                held[name], declined[name] = nil, true            -- the player changed it while Touch was on
                Log(name .. " " .. cur .. " is the player's: Touch stands aside")
            elseif not GroupOn(def.group) then
                GiveOne(name, h)
            end
        elseif GroupOn(def.group) and not declined[name] then
            local back = given[name]
            given[name] = nil
            if back ~= nil and cur ~= back then
                declined[name] = true                             -- the player changed it while Touch was off
                Log(name .. " " .. cur .. " is the player's (changed while off): Touch stands aside")
            elseif not Ok(def, cur) then
                if Set(def) then
                    local now = Read(name)
                    if now ~= nil and now ~= cur then
                        held[name] = { was = cur, ours = now }
                        Log(name .. " " .. cur .. " > " .. now)
                    end
                else
                    Log(name .. " refused by the game: left " .. cur)
                end
            end
        end
    end
end

-- Brings the CVars in line with the state now: Touch on (not paused, not in Edit Mode) = the touch values of the
-- switched-on groups; anything else = everything given back. Out of a fight at once, else at the fight's end (the last
-- call wins: the state is read when it runs).
local function SyncNow()
    if type(ns.db) ~= "table" then return end
    if ns.IsActive() and not ns.inEditMode then ApplyNow() else GiveBackNow() end
end

function Targeting.Sync() ns.Queue("targeting", SyncNow) end
Targeting.Apply = Targeting.Sync

-- A Touch settings switch changed. Ticking one is the player's yes: what they had declined in that group is asked again.
function Targeting.FeelChanged(key)
    local group
    for g, k in pairs(GROUP_KEY) do if k == key then group = g end end
    if not group then return end
    if ns.Contract.GetFeel(key) == true then
        local declined, given = Declined(), Given()
        for _, def in ipairs(DEFS) do
            if def.group == group then declined[def.name], given[def.name] = nil, nil end
        end
    end
    if ns.IsActive() then Targeting.Sync() end
end

-- Defaults in Touch settings: every touch value is asked again for this character.
function Targeting.Reset()
    if ns.char then ns.char.targetDeclined = nil end
    if ns.db then ns.db.targetGiven = nil end
    if ns.IsActive() then Targeting.Sync() end
end

-- ---------------------------------------------------------------------------------------
-- /touch targeting

local function Describe(def)
    local cur = Current(def)
    if cur == nil then return def.name .. " " .. ns.T("targeting.unknown") end
    local h = Held()[def.name]
    if h then return def.name .. " " .. cur .. " (" .. ns.T("targeting.held", tostring(h.was)) .. ")" end
    if Declined()[def.name] then return def.name .. " " .. cur .. " (" .. ns.T("targeting.declined") .. ")" end
    return def.name .. " " .. cur .. " (" .. ns.T("targeting.game") .. ")"
end

function Targeting.Command()
    local on = function(key) return ns.T(GROUP_KEY[key] and ns.Contract.GetFeel(key) and "targeting.on" or "targeting.off") end
    local n = 0
    for _ in pairs(Held()) do n = n + 1 end
    local lines = { ns.T("targeting.status", on("autoTarget"), on("bigPlates"), n) }
    for _, def in ipairs(DEFS) do lines[#lines + 1] = Describe(def) end
    local watched, unknown = {}, {}
    for _, name in ipairs(Targeting.WATCH) do
        local v = Read(name)
        if v == nil then unknown[#unknown + 1] = name else watched[#watched + 1] = name .. "=" .. v end
    end
    local tail = table.concat(watched, ", ")
    if #unknown > 0 then tail = tail .. "; " .. ns.T("targeting.unknown") .. ": " .. table.concat(unknown, ", ") end
    lines[#lines + 1] = tail
    for _, line in ipairs(lines) do
        ns.Print(line)
        Log(line)
    end
end

-- ---------------------------------------------------------------------------------------
-- Module steps

function Targeting:Layout() Targeting.Sync() end
function Targeting:Restore() Targeting.Sync() end

-- Logging in with Touch off (or paused) after a session that ended with our values still set: put them back.
ns.On("PLAYER_ENTERING_WORLD", function()
    if ns.IsActive() then return end
    if next(Held()) ~= nil then Targeting.Sync() end
end, true)
