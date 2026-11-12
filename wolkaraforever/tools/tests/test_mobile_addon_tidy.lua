-- The Interface mobile add-on's tidier screen (0.7, from the iPhone Duo interface of scarrdi94,
-- jklock/wolkaraforever#26), run outside the game with stand-ins for its frames:
--   - the experience bar says how far the level is, and when rest doubles it;
--   - the four big shortcuts are now one small menu tab under the minimap: it opens and closes
--     a compact quick menu by secure code (combat included), each entry closes it, the Menu
--     entry opens the tiles; it follows the minimap until moved, and goes with the setting off;
--   - an empty spell slot shows only while customising, while a spell waits on the cursor, or
--     when its whole wheel is empty (so an empty wheel is seen, filled and left; 2026-11-09).
-- And from the iPhone (2026-11-09): the target's portrait shows who is selected, and touching
-- the void drops the target (the game's deselectOnClick, given back as it was when turned off);
-- the quick menu saves ("Enregistrer") and its tab shows a dot while something waits to be
-- saved; a long press on a spell turns Customise on without casting, and the right-button drag
-- after it moves the spell: dropped on another slot, of either wheel, the two swap.
--
-- usage: luajit test_mobile_addon_tidy.lua <Hud.lua> <Shortcuts.lua> <Free.lua>

local hudPath = assert(arg[1], "usage: luajit test_mobile_addon_tidy.lua <Hud.lua> <Shortcuts.lua> <Free.lua>")
local shortcutsPath, freePath = assert(arg[2]), assert(arg[3])

local combat = false
InCombatLockdown = function() return combat end

-- A frame that takes any method; the ones these tests look at keep what they were given.
local created = {}
local function Frame(kind, name, parent, template)
    local frame = { kind = kind, name = name, parent = parent, template = template, shown = true,
        attributes = {}, refs = {}, scripts = {}, wraps = {} }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetFrameRef(key, other) self.refs[key] = other end
    function frame:GetFrameRef(key) return self.refs[key] end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:GetScript(script) return self.scripts[script] end
    function frame:HookScript(script, fn) self.scripts["hook" .. script] = fn end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(on) self.shown = on and true or false end
    function frame:IsShown() return self.shown end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:CreateTexture() return Frame("Texture") end
    function frame:SetText(text) self.text = text end
    function frame:SetValue(value) self.value = value end
    function frame:SetFormattedText(format, ...) self.formatted = { format, ... } end
    function frame:GetFrameLevel() return 1 end
    -- Methods (capitalised, as the game names them) answer anything; a missing field is nil, as on a
    -- real frame.
    setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
    if name then _G[name] = frame end
    created[#created + 1] = frame
    return frame
end
CreateFrame = Frame
UIParent = Frame("Frame", "UIParent")

local handlers = {}
local modules = {}
local ns = { MAX_FREE = 12, PAGES = 6, WHEELS = 4, editing = false, RELOAD = "/stopmacro [combat]\n/reload", QUESTION = "?" }
local savers, marked = {}, {}
function ns.OnSavePending(fn) savers[#savers + 1] = fn end
function ns.SavePending() return false end
function ns.SavePreClick(button, always) button.saveClicked = always end
function ns.MarkChanged(reason) marked[#marked + 1] = reason end
function ns.EntryIcon(entry) return entry and ("icon" .. entry.id) end
function ns.EntryName(entry) return entry and ("sort " .. entry.id) end
function ns.PageData(side, page)
    if type(side.pages) ~= "table" then side.pages = {} end
    if type(side.pages[page]) ~= "table" then side.pages[page] = {} end
    if type(side.pages[page].buttons) ~= "table" then side.pages[page].buttons = {} end
    return side.pages[page]
end
function ns.Register(name, module) modules[name] = module; return module end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end
function ns.Disc() return Frame("Texture") end
function ns.Box() return Frame("Texture") end
function ns.Label(_, _, text) local label = Frame("FontString"); label.text = text; return label end
function ns.Circle() return true end
function ns.EditFrame() return Frame("Texture") end
function ns.Surface(frame) frame.surfaced = true end
function ns.Movable(frame, store, key, default)
    frame.movableDefault = default
    function frame:PlaceSaved()
        local saved = store()[key]
        self.placedFrom = saved and "saved" or "default"
    end
end

-- 1. The experience bar's text.
assert(loadfile(hudPath))("WolkaraRoue", ns)
assert(ns.XPText(450, 1000, nil) == "45 %")
assert(ns.XPText(999, 1000, 0) == "99 %")
assert(ns.XPText(450, 1000, 1200) == "45 %  reposé", "rest is not said")
assert(ns.XPText(0, 0, nil) == "", "no level to reach, yet a text")

-- 1b. The experience bar shows whenever the game knows the experience ("l'xp s'affiche pas
-- toujours", iPhone, 2026-11-09).
local Hud = modules["Barres de vie"]
local xp, most, rested, blocked, healthFails = 0, 0, nil, false, false
UnitXP = function() return xp end
UnitXPMax = function() return most end
GetXPExhaustion = function() return rested end
IsXPUserDisabled = function() return blocked end
UnitExists = function(unit) return unit == "player" end
UnitLevel = function() return 20 end
UnitName = function() return "Essai" end
UnitHealth = function() if healthFails then error("health refused") end return 500 end
UnitHealthMax = function() return 1000 end
UnitPower, UnitPowerMax, UnitPowerType = function() return 100 end, function() return 200 end, function() return 0 end
ns.db = { hud = { enabled = true, scale = 100 } }
Hud:Init()
local bar = _G.WolkaraMobilePlayer.xp
local function Tick(seconds) Hud.clock.scripts.OnUpdate(Hud.clock, seconds) end
-- Just after a load the game may not know it yet: nothing to show...
Hud:Refresh()
assert(not bar.shown and ns.db.xpSeen.waiting == 1)
-- ...and the check every second shows it as soon as it does, with no event.
xp, most = 450, 1000
Tick(1.1)
assert(bar.shown and bar.text.text == "45 %" and bar.value == 450 and ns.db.xpSeen.shown == 1, "the bar waits for an event")
-- A failure on the health line no longer stops the experience.
healthFails, xp = true, 600
assert(not pcall(handlers.UNIT_HEALTH, "player"))
assert(bar.text.text == "60 %", "a health error stopped the experience bar")
healthFails = false
-- A moment where the game says nothing: the bar keeps what it showed, and notes it once.
most = 0
handlers.PLAYER_XP_UPDATE(); Tick(1); Tick(1)
assert(bar.shown and bar.text.text == "60 %" and ns.db.xpSeen.kept == 1, "a gap hid the bar")
-- Changes come through the check, once a second, and only when something changed.
xp, most = 700, 1000
Tick(0.5)
assert(bar.text.text == "60 %", "checked before the second")
Tick(0.6)
assert(bar.text.text == "70 %" and ns.db.xpSeen.shown == 1)
rested = 300
Tick(1)
assert(bar.text.text == "70 %  reposé")
-- Only blocked experience hides it.
blocked = true
Tick(1)
assert(not bar.shown and ns.db.xpSeen.hidden == 1)
blocked = false
Tick(1)
assert(bar.shown and ns.db.xpSeen.shown == 2)

-- 1c. Secret values: in a fight this client gives the add-on a health it may only hand to the
-- game's bars and texts - no sum, no comparison. On the iPhone (save of 2026-11-09) Hud.lua:254
-- stopped the update 38 times in two minutes, so the power bar and the target's effects stayed
-- as they were. A bare table behaves the same here: arithmetic or comparison on it fails.
local SECRET = {}
local playerFrame, targetFrame = _G.WolkaraMobilePlayer, _G.WolkaraMobileTarget
local power = 120
UnitPower = function() return power end
UnitHealth = function() return SECRET end
power = 150
handlers.UNIT_POWER_FREQUENT("player")
assert(playerFrame.power.value == 150, "a secret health stopped the power bar")
assert(playerFrame.health.value == SECRET, "the secret health was not handed to its bar")
assert(playerFrame.health.text.formatted and playerFrame.health.text.formatted[2] == SECRET, "the secret health is not written by the game")
-- A secret maximum: the bar is still filled and shown.
UnitPowerMax = function() return SECRET end
power = 90
handlers.UNIT_POWER_UPDATE("player")
assert(playerFrame.power.shown and playerFrame.power.value == 90, "a secret maximum hid the power bar")
UnitPowerMax = function() return 200 end
-- The target: its percent from the game, its effects without a secret count or time.
UnitExists = function() return true end
UnitIsDead, UnitIsFriend, UnitCanAttack = function() return false end, function() return false end, function() return true end
GetComboPoints = function() return SECRET end
UnitHealthPercent = function() return SECRET end
UnitAura = function(_, index, filter)
    if index == 1 and filter == "HARMFUL" then return "Poison", "poison-icon", SECRET, nil, SECRET, SECRET end
end
handlers.PLAYER_TARGET_CHANGED()
assert(targetFrame.health.text.formatted and targetFrame.health.text.formatted[1] == "%d %%", "the target's secret health has no percent")
local poison = targetFrame.auras[1]
assert(poison.shown, "the target's effect is gone")
assert(poison.count.text == "" and not poison.cooldown.shown, "a secret count or time was written")
assert(targetFrame.combo.text == "", "a secret combo count was written")
UnitHealth = function() return 500 end
UnitExists = function(unit) return unit == "player" end
UnitHealthPercent, UnitAura = nil, nil

-- 2. The menu tab and its quick menu.
local menuFrame = Frame("Frame", "WolkaraMobileMenu")
ns.Menu = { frame = menuFrame }
for _, name in ipairs({ "SpellbookMicroButton", "CharacterMicroButton", "QuestLogMicroButton" }) do Frame("Button", name) end
Minimap = Frame("Minimap", "Minimap")
local wraps = {}
SecureHandlerWrapScript = function(frame, script, header, pre, post)
    wraps[#wraps + 1] = { frame = frame, script = script, header = header, pre = pre, post = post }
end
assert(loadfile(shortcutsPath))("WolkaraRoue", ns)
local Shortcuts = modules["Raccourcis"]
Shortcuts:Init()
local tab, panel = _G.WolkaraMobileShortcuts, _G.WolkaraMobileQuickMenu
assert(tab and tab.template == "SecureHandlerClickTemplate", "the menu tab is not secure")
assert(panel and panel.template == "SecureHandlerBaseTemplate" and panel.surfaced and not panel.shown)
-- One tab only on the screen: the seven entries live in the quick menu.
local entries = {}
for _, frame in ipairs(created) do if frame.parent == panel and frame.kind == "Button" then entries[#entries + 1] = frame end end
assert(#entries == #Shortcuts.LIST and #entries == 7, #entries .. " entries")
-- Enregistrer: the game's own /reload (stopped in combat), always, through the save module.
local save = _G.WolkaraMobileShortcut7
assert(save.template == "SecureActionButtonTemplate" and save.attributes.type == "macro")
assert(save.attributes.macrotext == ns.RELOAD and Shortcuts.LIST[7].label == "Enregistrer")
save.scripts.PreClick(save, "LeftButton", false)
assert(save.saveClicked == true, "Enregistrer does not always save")
-- The tab's dot says something waits to be saved, and nothing else pops up.
assert(tab.dot and not tab.dot.shown and #savers == 1)
savers[1](true)
assert(tab.dot.shown, "no dot on the tab with something to save")
-- The tab's secure code opens and closes the quick menu, in combat too.
local function Run(frame, body) return assert(loadstring("local self = ...\n" .. body))(frame) end
combat = true
Run(tab, tab:GetAttribute("_onclick")); assert(panel.shown, "the tab did not open the quick menu")
Run(tab, tab:GetAttribute("_onclick")); assert(not panel.shown, "the tab did not close it")
combat = false
-- A game window entry clicks the game's own button and closes the quick menu after.
local spells = _G.WolkaraMobileShortcut2
assert(spells.attributes.type == "click" and spells.attributes.clickbutton == _G.SpellbookMicroButton)
local closing
for _, wrap in ipairs(wraps) do if wrap.frame == spells then closing = wrap end end
assert(closing and closing.script == "OnClick" and closing.header == panel, "an entry does not close the quick menu")
local owner = panel
panel:Show()
assert(select(2, assert(loadstring(closing.pre))()) == "close")
assert(loadstring("local owner = ...\n" .. closing.post))(owner)
assert(not panel.shown)
-- The Menu entry opens the tiles and closes the quick menu.
local menuEntry = _G.WolkaraMobileShortcut6
assert(menuEntry.template == "SecureHandlerClickTemplate")
menuFrame:Hide(); panel:Show()
Run(menuEntry, menuEntry:GetAttribute("_onclick"))
assert(menuFrame.shown and not panel.shown)
-- Placed at the top of the screen, left of the minimap and its + and - buttons, until moved
-- (asked on the iPhone, 2026-11-09: under the minimap it sat too low); then where it was put;
-- gone with the setting off.
ns.db = { shortcuts = { enabled = true, scale = 100 }, minimap = { shown = true } }
Shortcuts:Layout()
assert(tab.shown and tab.point[1] == "TOPRIGHT" and tab.point[2] == Minimap and tab.point[3] == "TOPLEFT", "the menu tab is not level with the minimap's top")
assert(tab.point[4] == -50 and tab.point[5] == 0, "the menu tab is not just left of the minimap's + and - buttons")
ns.db.minimap.shown = false
Shortcuts:Layout()
assert(tab.point[4] == -10, "the menu tab keeps room for the hidden minimap's buttons")
ns.db.minimap.shown = true
ns.db.shortcuts.scale = 125
Shortcuts:Layout()
assert(math.abs(tab.point[4] + 40) < 1e-9, "the menu tab's gap grows with its size")
ns.db.shortcuts.scale = 100
ns.db.shortcuts.pos = { point = "TOPRIGHT", x = -40, y = -200 }
Shortcuts:Layout()
assert(tab.placedFrom == "saved")
ns.db.shortcuts.enabled = false
panel:Show()
Shortcuts:Layout()
assert(not tab.shown and not panel.shown)
-- Customising closes the quick menu.
ns.db.shortcuts.enabled = true
Shortcuts:Layout(); panel:Show()
Shortcuts:SetEditing(true)
assert(not panel.shown)

-- 3. Empty spell slots.
local cursor = nil
GetCursorInfo = function() return cursor end
local under -- the slot under the finger
function ns.CreateActionButton(name, parent, _, getEntry, setEntry)
    local button = Frame("Button", name, parent, "SecureActionButtonTemplate")
    button.GetEntry = function() return getEntry() end
    button.SetEntry = function(_, entry) setEntry(entry) end
    button.icon = Frame("Texture")
    function button.icon:SetAlpha(alpha) self.alpha = alpha end
    function button:IsVisible() return self.shown end
    function button:IsMouseOver() return self == under end
    function button:SetAlpha(alpha) self.alpha = alpha end
    return button
end
ns.ApplyButton, ns.RefreshButton = function() end, function() end
ns.db.free = { count = 4, scale = 100, page = 1, pages = { { buttons = { { entry = { kind = "spell", id = 75 } }, {},
    { entry = { kind = "spell", id = 2973 } }, {} } } } }
ns.db.freeLeft = { count = 2, scale = 100, page = 1, pages = {} }
assert(loadfile(freePath))("WolkaraRoue", ns)
local Free = modules["Boutons libres"]
Free:Init()
local right = {}
for i = 1, 12 do right[i] = _G["WolkaraMobileFree" .. i] end
local function Shown() local list = {} for i = 1, 5 do list[i] = right[i].shown end return list end
Free:Layout()
local shown = Shown()
assert(shown[1] and not shown[2] and shown[3] and not shown[4] and not shown[5], "an empty slot of a wheel with spells shows in play")
-- A wheel with no spell at all shows its slots, pale: it is seen, a touch fills it, and a swipe
-- leaves it.
assert(_G.WolkaraMobileFreeLeft1.shown and _G.WolkaraMobileFreeLeft2.shown and not _G.WolkaraMobileFreeLeft3.shown, "the empty left wheel hides its slots")
assert(_G.WolkaraMobileFree2_1.shown and _G.WolkaraMobileFree2_4.shown and not _G.WolkaraMobileFree2_5.shown, "the empty second wheel hides its slots")
assert(right[1].alpha == 1 and _G.WolkaraMobileFreeLeft1.alpha == 0.6, "an empty wheel's slots are not pale, or a spell is")
-- Customising shows every slot to fill; done, only the spells again.
ns.editing = true; Free:SetEditing(true)
shown = Shown()
assert(shown[1] and shown[2] and shown[3] and shown[4] and not shown[5] and _G.WolkaraMobileFreeLeft2.shown)
ns.editing = false; Free:SetEditing(false)
shown = Shown()
assert(not shown[2] and not shown[4])
-- A spell taken from the spellbook shows where it can go; put down, they go again.
cursor = "spell"; handlers.CURSOR_CHANGED()
assert(right[2].shown and right[4].shown, "no empty slot to drop the spell on")
assert(right[2].alpha == 0.35, "an empty slot of a wheel with spells is not paler")
cursor = nil; handlers.CURSOR_CHANGED()
assert(not right[2].shown)
-- Not in combat: the slots are the game's secure buttons.
combat = true; cursor = "spell"; handlers.CURSOR_CHANGED()
assert(not right[2].shown)
combat = false; cursor = nil
-- Each side has room for six wheels of twelve slots; the first keeps the names it had.
assert(_G.WolkaraMobileFree6_12 and _G.WolkaraMobileFreeLeft6_1 and right[1].wmPage == 1 and _G.WolkaraMobileFree3_2.wmPage == 3)
ns.db.free.pages[2] = { buttons = { { entry = { kind = "spell", id = 1978 } } } }
Free:Layout()
assert(_G.WolkaraMobileFree2_1.shown and not _G.WolkaraMobileFree2_2.shown)

-- 4. The long press: Customise, without casting; then the right-button drag moves the spell.
function ns.SetEditing(on) ns.editing = on; Free:SetEditing(on) end
right[1]:OnLongPress()
assert(ns.editing and right[2].shown, "the long press did not turn Customise on")
right[1]:OnLongPress()
assert(ns.editing, "a second long press turned Customise off")
-- A left drag is the wheel's (Turn.lua): it moves nothing.
right[1].scripts.hookOnDragStart(right[1], "LeftButton")
local ghost = _G.WolkaraMobileMoveGhost
assert(not ghost or not ghost.shown, "a left drag picked up the spell")
right[1].scripts.hookOnDragStart(right[1], "RightButton")
ghost = _G.WolkaraMobileMoveGhost
assert(ghost and ghost.shown, "nothing follows the finger")
assert(right[1].icon.alpha == 0.3)
-- Dropped on another slot of the same wheel: the two spells swap, the change is recorded.
under = right[3]
right[1].scripts.hookOnDragStop(right[1])
assert(ns.db.free.pages[1].buttons[1].entry.id == 2973 and ns.db.free.pages[1].buttons[3].entry.id == 75, "the spells did not swap")
assert(not ghost.shown and right[1].icon.alpha == 1 and marked[#marked]:find("sort 75"))
-- Dropped on an empty slot of the other wheel: it moves there.
right[3].scripts.hookOnDragStart(right[3], "RightButton")
under = _G.WolkaraMobileFreeLeft2
right[3].scripts.hookOnDragStop(right[3])
assert(ns.db.free.pages[1].buttons[3].entry == nil and ns.db.freeLeft.pages[1].buttons[2].entry.id == 75)
-- Dropped beside every slot: nothing changes.
local before = #marked
right[1].scripts.hookOnDragStart(right[1], "RightButton")
under = nil
right[1].scripts.hookOnDragStop(right[1])
assert(#marked == before and ns.db.free.pages[1].buttons[1].entry.id == 2973)
-- Nothing to move from an empty slot, out of Customise, or in combat.
assert(Free.StartMove(right[2]) == false)
ns.SetEditing(false)
assert(Free.StartMove(right[1]) == false)
ns.SetEditing(true); combat = true
assert(Free.StartMove(right[1]) == false)
combat = false; ns.SetEditing(false)

-- 5. The target: its portrait, and touching the void drops it.
local portraits = {}
SetPortraitTexture = function(texture, unit) portraits[unit] = texture end
UnitExists = function() return true end
UnitIsDead, UnitIsFriend, UnitCanAttack = function() return false end, function() return false end, function() return true end
GetComboPoints = function() return 0 end
UnitAura = function() return nil end
local targetFrame = _G.WolkaraMobileTarget
assert(targetFrame.portrait and targetFrame.portrait.texture, "the target has no portrait")
handlers.PLAYER_TARGET_CHANGED()
assert(portraits.target == targetFrame.portrait.texture, "the target's portrait is not drawn")
-- At the very top, just right of the player bar, and narrower (asked on the iPhone, 2026-11-09:
-- centred one notch lower it was wider than needed); its effects wrap into rows under it.
local spot = targetFrame.movableDefault
assert(spot[1] == "TOPLEFT" and spot[2] == "TOPLEFT" and spot[3] == 12 + 280 + 8 and spot[4] == -10, "the target is not at the top, right of the player bar")
local mine = _G.WolkaraMobilePlayer.movableDefault
assert(mine[1] == "TOPLEFT" and mine[3] == 12 and mine[4] == -10, "the player bar moved")
local seventh, eighth = targetFrame.auras[7].point, targetFrame.auras[8].point
assert(seventh[4] == 6 * 33 and seventh[5] == -3, "the first row of effects is not as wide as the bar")
assert(eighth[2] == targetFrame and eighth[4] == 0 and eighth[5] == -3 - 33, "the effects do not wrap under the narrower bar")
local cvars = { deselectOnClick = "0" }
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = tostring(value) end
ns.db.hud = { enabled = true, scale = 100, deselect = true }
Hud.Deselect()
assert(cvars.deselectOnClick == "1" and ns.db.hud.deselectWas == "0", "touching the void does not drop the target")
Hud.Deselect()
assert(ns.db.hud.deselectWas == "0", "the player's own value was forgotten")
ns.db.hud.deselect = false
Hud.Deselect()
assert(cvars.deselectOnClick == "0" and ns.db.hud.deselectWas == nil, "the game's own value was not given back")
ns.db.hud.deselect = true
combat = true; Hud.Deselect(); combat = false
assert(cvars.deselectOnClick == "0", "a game setting changed in combat")
cvars.deselectOnClick = nil
Hud.Deselect()
assert(cvars.deselectOnClick == nil and ns.db.hud.deselectWas == nil, "a setting this client does not have was made up")

print("mobile add-on tidy screen: XP percent and rest said, secret health, power and effects handed to the game's bars and texts without stopping the update, one menu tab for a secure quick menu that closes after use, saves and follows the minimap, a dot while something waits, at the top left of the minimap, empty slots only to fill them or on an empty wheel, room for six wheels a side, long press to Customise and right-drag to move a spell, target portrait at the top right of the player bar, its effects in rows, touching the void drops the target: PASS")
