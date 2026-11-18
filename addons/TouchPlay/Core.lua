-- TouchPlay: the core.
--
-- Every module registers here and gets the same steps: Init once when the add-on loads,
-- Layout out of combat whenever the screen is (re)built, Refresh for what it shows, and
-- Restore to give the game's own frames back. Each step runs inside a guard: an error in any
-- module pauses the add-on, gives the game's bars back (after the fight if one is on, a game
-- rule) and shows "Touch screen paused, tap to report" once.
--
-- Nothing here automates an action: every spell, target and loot comes from a tap.
-- Guard, error memory, Register, Each and On are ported from WolkaraRoue Core.lua (MIT).

local ADDON_NAME, ns = ...

ns.NOTICE = "Touch screen paused, tap to report"

local modules = {}
ns.modules = modules
ns.paused = false
ns.loggedIn = false

-- False for a value the game hides in a fight (a "secret"): such a value is never compared, searched,
-- counted or used as a table key. One helper for every module.
function ns.Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

function ns.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe9b45cTouch|r: " .. tostring(text))
end

local function Trace(problem)
    return tostring(problem) .. (debugstack and ("\n" .. debugstack(2, 2, 0)) or "")
end

-- The last errors stay in the saved variables (TouchPlayDB.errors, at most 8): the game
-- keeps no log the Mac can read. The same error takes one line, with a count.
local KEEP_ERRORS = 8
function ns.RememberError(text)
    local db = ns.db
    if type(db) ~= "table" then return end
    if type(db.errors) ~= "table" then db.errors = {} end
    text = tostring(text):sub(1, 400)
    local now = time and time() or nil
    for _, seen in ipairs(db.errors) do
        if seen.text == text then
            seen.count, seen.last = (tonumber(seen.count) or 1) + 1, now
            return
        end
    end
    table.insert(db.errors, 1, { text = text, count = 1, first = now, last = now })
    while #db.errors > KEEP_ERRORS do table.remove(db.errors) end
end

-- Runs fn; on an error, remembers it and pauses the add-on. Returns true when fn ran cleanly.
function ns.Guard(label, fn, ...)
    local ok, problem = xpcall(fn, Trace, ...)
    if not ok then
        ns.lastError = label .. ": " .. tostring(problem)
        ns.RememberError(ns.lastError)
        ns.Pause(label)
    end
    return ok
end

function ns.Register(name, module)
    module.name = name
    modules[#modules + 1] = module
    ns[name] = module
    return module
end

-- Calls module[method] on every module, each inside the guard. Once paused, only Restore runs.
function ns.Each(method, ...)
    for _, module in ipairs(modules) do
        if ns.paused and method ~= "Restore" then return end
        local fn = module[method]
        if fn then ns.Guard(module.name .. "." .. method, fn, module, ...) end
    end
end

-- ---------------------------------------------------------------------------------------
-- Changes that the game allows only out of combat

local queue, queueOrder = {}, {}

-- Runs fn now when not in combat; otherwise once when the fight ends. A later call with the
-- same key replaces the earlier one.
function ns.Queue(key, fn)
    if not InCombatLockdown() then
        queue[key] = nil
        fn()
        return
    end
    if not queue[key] then queueOrder[#queueOrder + 1] = key end
    queue[key] = fn
end

-- A fight is on. PLAYER_REGEN_DISABLED comes just before the game's lockdown starts (InCombatLockdown() still says
-- no while it is handled) and PLAYER_REGEN_ENABLED just after it ends, so what a fight greys asks here, not the
-- lockdown. Protected changes still ask InCombatLockdown(): the moment before a fight is the last one they work.
ns.fighting = false
function ns.InFight() return ns.fighting or InCombatLockdown() end

local function FlushQueue()
    local order = queueOrder
    queueOrder = {}
    for _, key in ipairs(order) do
        local fn = queue[key]
        queue[key] = nil
        if fn then ns.Guard("queue " .. key, fn) end
    end
end

-- ---------------------------------------------------------------------------------------
-- Pause, on and off

-- Only Jump, Dive/Dismount and Interact (and the keys that are not the app's, like bare F12) keep their keys when
-- Touch is paused or off. Never raises: a failure is remembered and does not stop the rest of the pause or the
-- switch-off.
local function KeepMovementKeys()
    if ns.Contract and ns.Contract.OnPause then
        local ok, problem = pcall(ns.Contract.OnPause)
        if not ok then
            ns.lastError = "Contract.OnPause: " .. tostring(problem)
            ns.RememberError(ns.lastError)
        end
    end
end

-- Tells the in-world signal (Signal.lua) that Touch was switched On or Off (method "OnSwitch", with the new state)
-- or paused ("OnPause"). Never raises, like KeepMovementKeys: a failure is remembered and the rest goes on.
local function Signal(method, ...)
    if ns.Signal and ns.Signal[method] then
        local ok, problem = pcall(ns.Signal[method], ...)
        if not ok then
            ns.lastError = "Signal." .. method .. ": " .. tostring(problem)
            ns.RememberError(ns.lastError)
        end
    end
end

function ns.Pause(reason, kind)
    if ns.paused then return end
    ns.paused = true
    ns.pauseReason = reason
    ns.pauseKind = kind
    KeepMovementKeys()
    Signal("OnPause")
    ns.Queue("mode", function()
        ns.Each("Restore")
        if ns.root then ns.root:Hide() end
    end)
    -- the pause card (mockup 91), once per pause; kind is "game" when the game's performance check named the add-on
    if not ns.noticeShown then
        ns.noticeShown = true
        ns.Print(ns.NOTICE)
        if ns.ShowNotice then pcall(ns.ShowNotice, kind) end
    end
end

-- What a tap on the notice does: BugSack when it is loaded, else the error in the chat.
function ns.Report()
    if BugSack and BugSack.OpenSack then
        BugSack:OpenSack()
    else
        ns.Print(ns.lastError or "No error recorded.")
    end
end

function ns.SetEnabled(on)
    on = on and true or false
    ns.db.enabled = on
    if on then
        ns.paused = false
        ns.noticeShown, ns.pauseKind = false, nil       -- the next pause shows its card again
        -- the pause card has nothing more to say (and, open, it would keep the app's taps plain: ruling A30)
        if ns.Perf and ns.Perf.Hide and not (ns.Perf.IsExplaining and ns.Perf.IsExplaining()) then
            local ok, problem = pcall(ns.Perf.Hide)
            if not ok then ns.RememberError("Perf.Hide: " .. tostring(problem)) end
        end
        ns.Queue("mode", function()
            if ns.root and not ns.inEditMode then ns.root:Show() end
            ns.Each("Layout")
            ns.Each("Refresh")
        end)
        Signal("OnSwitch", true)
        ns.Print("Touch screen on. Type /touch to switch it off.")
    else
        -- Off puts everything back: the app's keys stop driving the hidden buttons, and only
        -- Jump, Dive/Dismount and Interact keep their keys (as in a pause).
        KeepMovementKeys()
        ns.Queue("mode", function()
            ns.Each("Restore")
            if ns.root then ns.root:Hide() end
        end)
        Signal("OnSwitch", false)
        ns.Print("Touch screen off. Type /touch to switch it on.")
    end
end

function ns.IsActive() return ns.db ~= nil and ns.db.enabled and not ns.paused end

-- ---------------------------------------------------------------------------------------
-- Edit Mode (R44): one flag for every module. Opening it gives the game all its frames back (every module's
-- Restore: the bars, the minimap, the mirror timers, the chat) and hides our screen; the move root (Interact, Jump,
-- Dive) stays. While it is open a Layout that would hide or move a game frame leaves it alone (Bars, Hud, Chat
-- read ns.inEditMode). Closing it lays everything out again. The game keeps Edit Mode out of fights.

ns.inEditMode = false
local editModeOwner = {}

local function EditModeEnter()
    ns.inEditMode = true
    if not ns.IsActive() then return end
    ns.Queue("mode", function()
        ns.Each("Restore")
        if ns.root then ns.root:Hide() end
    end)
end

local function EditModeExit()
    ns.inEditMode = false
    if not ns.IsActive() then return end
    ns.Queue("mode", function()
        if ns.root then ns.root:Show() end
        ns.Each("Layout")
        ns.Each("Refresh")
    end)
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", function() ns.Guard("EditMode.Enter", EditModeEnter) end, editModeOwner)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ns.Guard("EditMode.Exit", EditModeExit) end, editModeOwner)
end

-- ---------------------------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
local handlers = {}

-- A module asks for an event; an event this client does not know is ignored. Handlers do not
-- run while the add-on is off or paused, unless `always` is set (the core's own).
function ns.On(event, fn, always)
    if not handlers[event] then
        handlers[event] = {}
        if not pcall(events.RegisterEvent, events, event) then
            handlers[event] = nil
            return
        end
    end
    table.insert(handlers[event], { fn = fn, always = always })
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, handler in ipairs(list) do
        if handler.always or ns.IsActive() then ns.Guard(event, handler.fn, ...) end
    end
end)

local function LoadSavedVariables()
    if type(TouchPlayDB) ~= "table" then TouchPlayDB = {} end
    if type(TouchPlayCharDB) ~= "table" then TouchPlayCharDB = {} end
    if TouchPlayDB.enabled == nil then TouchPlayDB.enabled = true end
    ns.db, ns.char = TouchPlayDB, TouchPlayCharDB
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME or ns.initialised then return end
    ns.initialised = true
    LoadSavedVariables()
    ns.Each("Init")
end, true)

ns.On("PLAYER_LOGIN", function()
    ns.loggedIn = true
    if not ns.initialised then
        ns.initialised = true
        LoadSavedVariables()
        ns.Each("Init")
    end
    if not ns.db.enabled then
        -- Off from the start keeps the same keys as switching Off in a session (R11).
        KeepMovementKeys()
        if ns.root then ns.Queue("mode", function() ns.root:Hide() end) end
        return
    end
    ns.Queue("mode", function()
        ns.Each("Layout")
        ns.Each("Refresh")
    end)
    -- In a fight the layout waits; what the cards show can still update now.
    if InCombatLockdown() then ns.Each("Refresh") end
end, true)

-- The core's own fight flag comes first (Core loads first, so its handlers are the first of each event).
ns.On("PLAYER_REGEN_DISABLED", function() ns.fighting = true end, true)
ns.On("PLAYER_REGEN_ENABLED", function()
    ns.fighting = false
    FlushQueue()
end, true)

-- ---------------------------------------------------------------------------------------
-- /touch

SLASH_TOUCHPLAY1 = "/touch"
SlashCmdList.TOUCHPLAY = function(message)
    if not ns.db then
        ns.Print("Not ready yet.")
        return
    end
    local command = ((message or ""):match("^%s*(%S*)") or ""):lower()
    local word = ((message or ""):match("^%s*%S+%s+(%S+)") or ""):lower()
    if command == "tip" or command == "help" then
        if ns.Tip and ns.Tip.Show then ns.Tip.Show() end
    elseif command == "error" then
        ns.Report()
    elseif command == "keys" then
        -- /touch keys switches the key diagnostic (Keylog.lua); /touch keys list prints the app's keys
        if word == "list" then
            if ns.Contract then ns.Contract.PrintKeys() end
        elseif ns.Keylog then
            ns.Keylog.Command(word)
        end
    elseif command == "perf" then
        if ns.Perf then ns.Perf.Print() end
    elseif command == "frames" then
        -- /touch frames [x y] lists what is drawn at a point and the stray action bars hidden (Bars.lua)
        if ns.Bars and ns.Bars.FramesCommand then ns.Bars.FramesCommand((message or ""):match("^%s*%S+(.*)$")) end
    elseif command == "windows" then
        -- /touch windows logs every window the overlay detector sees open or close (Signal.lua)
        if ns.Signal and ns.Signal.WindowsCommand then ns.Signal.WindowsCommand(word) end
    elseif command == "targeting" then
        -- /touch targeting: the soft targeting and name plate CVars, Touch's and the player's (Targeting.lua)
        if ns.Targeting then ns.Targeting.Command() end
    elseif command == "sharp" then
        -- /touch sharp: the physical size, RenderScale and resampling, Touch's and the player's (Sharp.lua, ruling A39)
        if ns.Sharp then ns.Sharp.Command() end
    else
        ns.SetEnabled(not ns.db.enabled)
    end
end
