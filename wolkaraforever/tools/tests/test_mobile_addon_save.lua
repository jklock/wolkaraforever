-- The Interface mobile add-on's save (addons/WolkaraRoue/Save.lua), run outside the game with
-- the few WoW functions it calls stubbed. The game writes WolkaraRoueDB only on a reload or a
-- clean exit, and reloads for an add-on only from a real touch on its own /reload. Until 0.7 a
-- change made an "Enregistrer" button pop up mid-screen a few seconds later, in the middle of
-- play ("de manière random", iPhone, 2026-11-09). What is asserted: nothing ever pops up or
-- reloads by itself; a change is recorded with its reason and said once to whoever shows that
-- something waits (the dot on the menu tab); the save buttons (Terminé, Fermer) reload through a
-- secure /reload only when something waits and never in combat, then do their own job; the
-- quick menu's Enregistrer always reloads; after the reload the add-on says it saved.
--
-- usage: luajit test_mobile_addon_save.lua <path to Save.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_save.lua <path to Save.lua>")

local combat, reloads = false, 0
local frames, printed, handlers = {}, {}, {}

InCombatLockdown = function() return combat end
ReloadUI = function() reloads = reloads + 1 end
GetTime = function() return 0 end
time = function() return 1000 end
CreateFrame = function(_, name, parent, template)
    local frame = { name = name, parent = parent, template = template, attributes = {}, scripts = {}, shown = true }
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetFrameLevel() return 1 end
    for _, method in ipairs({ "SetAllPoints", "SetFrameLevel", "RegisterForClicks", "SetSize", "SetPoint" }) do
        frame[method] = function() end
    end
    frames[#frames + 1] = frame
    return frame
end
UIParent = {}

local ns = { db = {}, editing = false }
function ns.Print(message) printed[#printed + 1] = message end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end

assert(loadfile(path))("WolkaraRoue", ns)

-- Nothing runs by itself: no frame ticks, nothing shows, nothing reloads.
for _, frame in ipairs(frames) do assert(not frame.scripts.OnUpdate, "something still ticks to reload") end
assert(#frames == 0 and reloads == 0 and not ns.SaveTick, "a save button pops up by itself")

-- A change is recorded with its reason, newest first, eight at most, and said once.
local told = 0
ns.OnSavePending(function(on) assert(on == true); told = told + 1 end)
assert(not ns.SavePending())
ns.MarkChanged("taille de la mini-carte")
assert(ns.SavePending() and told == 1 and ns.db.saveLog[1].reason == "taille de la mini-carte" and ns.db.saveLog[1].at == 1000)
for i = 1, 10 do ns.MarkChanged("réglage " .. i) end
assert(told == 1, "the pending change was said more than once")
assert(#ns.db.saveLog == 8 and ns.db.saveLog[1].reason == "réglage 10")
assert(#frames == 0 and reloads == 0, "a change popped something up")

-- Terminé and Fermer: a transparent secure button over each, whose touch reloads through the
-- game's own /reload when something waits (out of combat), then does the button's job.
local done = { GetFrameLevel = function() return 3 end }
local finished = 0
local over = ns.SaveOver(done, function() finished = finished + 1 end)
assert(over.template == "SecureActionButtonTemplate" and over.parent == done)
assert(over.attributes.macrotext == "/stopmacro [combat]\n/reload" and ns.RELOAD == over.attributes.macrotext)
ns.db.justSaved = nil
over.scripts.PreClick(over, "LeftButton", true)
assert(over.attributes.type == "macro" and ns.db.justSaved == true, "Terminé does not save what waits")
over.scripts.PostClick(over, "LeftButton", true)
assert(finished == 0, "the job ran on the press")
over.scripts.PostClick(over, "LeftButton", false)
assert(finished == 1)
-- In combat its attributes are left alone: the macro's own [combat] stops the reload.
combat = true
over.attributes.type = nil
over.scripts.PreClick(over, "LeftButton", false)
assert(over.attributes.type == nil)
combat = false

-- After the reload the add-on says it saved, once, and nothing waits any more.
handlers.PLAYER_LOGIN()
assert(ns.db.justSaved == nil and printed[#printed] == "réglages enregistrés.")
local fresh = { On = function() end, Guard = ns.Guard }
assert(loadfile(path))("WolkaraRoue", fresh)
fresh.db = {}
assert(not fresh.SavePending())

-- With nothing waiting, Terminé only does its job.
local quiet = fresh.SaveOver(done, function() finished = finished + 1 end)
quiet.scripts.PreClick(quiet, "LeftButton", false)
assert(quiet.attributes.type == nil and fresh.db.justSaved == nil, "Terminé reloads with nothing to save")
quiet.scripts.PostClick(quiet, "LeftButton", false)
assert(finished == 2)
-- The quick menu's Enregistrer reloads whatever waits.
fresh.SavePreClick(quiet, true)
assert(quiet.attributes.type == "macro" and fresh.db.justSaved == true)

-- Before the settings are loaded a change is not recorded.
fresh.db = nil
fresh.MarkChanged("trop tôt")
assert(not fresh.SavePending())

print("mobile add-on save: nothing pops up or reloads by itself, each change kept with its reason and said once, Terminé and Fermer save through a secure /reload only when something waits and never in combat, Enregistrer always, said after: PASS")
