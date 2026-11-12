-- The Interface mobile add-on's settings (addons/WolkaraRoue/Core.lua), run outside the game: a
-- 0.5 save moves to 0.6 once, then to 0.8's wheels, each side's spells and notch becoming its
-- first wheel, the arc setting gone. The golden wheel's spells go into the left turning wheel,
-- in its free places and without duplicates, and the golden wheel is switched off but keeps
-- them; the left wheel turns and shows at least four spells; the chat goes back to its new place
-- at the bottom; the minimap gets its default size. A fresh install starts the same way, and a
-- save that has already moved is left as the player set it.
--
-- From the iPhone (2026-11-09): each side has four wheels by default and keeps the number the
-- player sets, one to six, the wheel shown within them; "/mobile reset" keeps every wheel that
-- has a spell; the menu tab, moved to the top of the screen, starts there once. And, given
-- Settings.lua, the settings panel sets the wheels side by side - how many, how many spells on
-- each, their size and spacing - and says under them how to go from one wheel to the next.
--
-- usage: luajit test_mobile_addon_settings.lua <path to Core.lua> [<path to Settings.lua>]

local path = assert(arg[1], "usage: luajit test_mobile_addon_settings.lua <Core.lua> [<Settings.lua>]")
local panelPath = arg[2]

local onEvent
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript(_, fn) onEvent = fn end
    return frame
end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
InCombatLockdown = function() return false end

local ns = {}
assert(loadfile(path))("WolkaraRoue", ns)
local marked = {}
function ns.MarkChanged(reason) marked[#marked + 1] = reason end
local function Load(saved)
    WolkaraRoueDB = saved
    ns.db = nil
    onEvent(nil, "ADDON_LOADED", "WolkaraRoue")
    return ns.db
end
local function Entry(db, index, key, page)
    local button = db[key or "freeLeft"].pages[page or 1].buttons[index]
    return type(button) == "table" and button.entry or nil
end
-- Each side has room for six wheels, its number of them, the one shown among them, and no old
-- layout left.
local function Wheels(db)
    assert(ns.PAGES == 6 and ns.WHEELS == 4)
    for _, key in ipairs({ "free", "freeLeft" }) do
        local side = db[key]
        for page = 1, ns.PAGES do assert(type(side.pages[page].buttons) == "table", key .. " wheel " .. page) end
        assert(side.wheels >= 1 and side.wheels <= ns.PAGES, key .. " has " .. tostring(side.wheels) .. " wheels")
        assert(side.page >= 1 and side.page <= side.wheels, key .. " shows a wheel it does not have")
        assert(side.buttons == nil and side.turnOffset == nil and side.turn == nil)
    end
    return true
end

-- A 0.5 save: the golden wheel on, with spells; the left side had one spell and one moved slot.
local db = Load({
    version = 2, layoutVersion = 3,
    wheels = { { enabled = true, slots = 8, scale = 100, radius = 110, open = "bouton", entries = {
        [1] = { kind = "spell", id = 100 }, [2] = { kind = "spell", id = 200 },
        [4] = { kind = "item", id = 300 }, [5] = { kind = "spell", id = 500 } } } },
    free = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 2, buttons = { [1] = { entry = { kind = "spell", id = 9 } } } },
    freeLeft = { count = 0, scale = 100, spread = 100, buttons = {
        [1] = { entry = { kind = "spell", id = 500 } }, [2] = { pos = { point = "CENTER", x = 1, y = 2 } } } },
    chat = { custom = true, fontSize = 18, pos = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40 } },
})
assert(db.layoutVersion == 8 and Wheels(db))
assert(db.free.wheels == 4 and db.freeLeft.wheels == 4, "a side does not start with four wheels")
assert(db.wheels[1].enabled == false and db.wheels[1].entries[4].id == 300, "the golden wheel lost its spells or stayed on")
assert(db.freeLeft.count == 4, "the left wheel does not show four spells")
assert(Entry(db, 1).id == 500, "the left wheel's own spell was replaced")
assert(Entry(db, 2).id == 100, "a free place was not filled")
assert(Entry(db, 3).id == 200 and Entry(db, 4).kind == "item" and Entry(db, 4).id == 300)
assert(Entry(db, 5) == nil, "a spell already in the left wheel was added twice")
assert(db.chat.pos == nil and db.chat.fontSize == 18 and db.chat.tab == "talk", "the chat kept its old place")
assert(db.minimap.shown == true and db.minimap.scale == 60)
assert(db.free.pages[1].turnOffset == 2 and Entry(db, 1, "free").id == 9, "the right wheel changed")
assert(Entry(db, 1, "free", 2) == nil and Entry(db, 1, "freeLeft", 4) == nil, "a new wheel is not empty")

-- More spells than four: the left wheel shows them all.
db = Load({ version = 2, layoutVersion = 3, wheels = { { enabled = true, slots = 8, entries = {
    { kind = "spell", id = 1 }, { kind = "spell", id = 2 }, { kind = "spell", id = 3 },
    { kind = "spell", id = 4 }, { kind = "spell", id = 5 }, { kind = "spell", id = 6 } } } } })
assert(db.freeLeft.count == 6 and Entry(db, 6).id == 6)

-- A fresh install: the same start, nothing to move.
db = Load(nil)
assert(db.layoutVersion == 8 and db.freeLeft.count == 4 and Wheels(db) and Entry(db, 1) == nil)
for i = 1, ns.MAX_WHEELS do assert(db.wheels[i].enabled == false, "a golden wheel is on by default") end

-- Already moved: the player's own choices stay.
db.wheels[1].enabled = true
db.freeLeft.count = 2
db.chat.pos = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 90 }
db = Load(db)
assert(db.wheels[1].enabled == true and db.freeLeft.count == 2 and db.chat.pos.y == 90, "the move ran twice")

-- A 0.7 save (layout 5): each side's spells and notch become its first wheel, once; the wheel
-- shown is kept within the side's wheels.
db = Load({ version = 2, layoutVersion = 5,
    free = { count = 6, scale = 100, spread = 100, turn = true, turnOffset = 3,
        buttons = { [2] = { entry = { kind = "spell", id = 75 } }, [5] = { entry = { kind = "item", id = 6948 } } } },
    freeLeft = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 1,
        buttons = { [1] = { entry = { kind = "spell", id = 13163 } } } } })
assert(db.layoutVersion == 8 and Wheels(db))
assert(Entry(db, 2, "free").id == 75 and Entry(db, 5, "free").id == 6948 and db.free.pages[1].turnOffset == 3)
assert(Entry(db, 1).id == 13163 and db.freeLeft.pages[1].turnOffset == 1 and db.free.page == 1)
db.free.pages[3].buttons[1] = { entry = { kind = "spell", id = 1978 } }
db.free.page = 9
db = Load(db)
assert(Entry(db, 1, "free", 3).id == 1978 and Entry(db, 2, "free").id == 75 and db.free.page == 4, "the wheels moved twice")

-- The number of wheels the player sets stays, one to six, and the wheel shown stays within it.
db.free.wheels, db.free.page = 2, 3
db.freeLeft.wheels = 9
db = Load(db)
assert(db.free.wheels == 2 and db.free.page == 2 and db.freeLeft.wheels == 6 and Wheels(db))
db.free.wheels = 0
db = Load(db)
assert(db.free.wheels == 1 and db.free.page == 1)
db.free.wheels = 4

-- The menu tab moves to the top of the screen once (layout 7): a place set before goes, a place
-- set after stays.
db = Load({ version = 2, layoutVersion = 6, shortcuts = { enabled = true, scale = 100, pos = { point = "TOPRIGHT", x = -20, y = -170 } } })
assert(db.layoutVersion == 8 and db.shortcuts.pos == nil, "the menu tab kept its place under the minimap")
db.shortcuts.pos = { point = "TOPRIGHT", x = -60, y = -10 }
db = Load(db)
assert(db.shortcuts.pos and db.shortcuts.pos.x == -60, "a place set after the move was lost")

-- The target moves to the top, right of the player bar, and the quest card under the player's
-- effects, once (layout 8): places set before go, places set after stay.
db = Load({ version = 2, layoutVersion = 7, hud = { enabled = true, scale = 100, target = { point = "TOP", x = 0, y = -96 } },
    quests = { enabled = true, shown = 3, pos = { point = "TOPLEFT", x = 12, y = -92 } } })
assert(db.layoutVersion == 8 and db.hud.target == nil and db.quests.pos == nil, "the target or the quest card kept its old place")
db.hud.target = { point = "TOPLEFT", x = 400, y = -10 }
db = Load(db)
assert(db.hud.target and db.hud.target.x == 400, "a place set after the move was lost")

-- "/mobile reset" puts the settings back but keeps every spell, and every wheel that has one.
db.free.wheels = 6
db.free.pages[6].buttons[2] = { entry = { kind = "spell", id = 2973 } }
db.freeLeft.wheels = 2
db.freeLeft.pages[2].buttons[1] = { entry = { kind = "spell", id = 1494 } }
db.free.scale = 150
SlashCmdList.WOLKARAMOBILE("reset")
db = ns.db
assert(db.free.scale == 100 and Wheels(db), "reset kept a setting")
assert(Entry(db, 2, "free", 6).id == 2973 and db.free.wheels == 6, "reset lost the sixth wheel and its spell")
assert(Entry(db, 1, "freeLeft", 2).id == 1494 and db.freeLeft.wheels == 4, "reset did not go back to four wheels")

-- An error caught by the guard stays in the save, once per kind with its count, eight at most:
-- the game logs none of them, and the chat cannot be read from the Mac.
local function Fail(label, message) return ns.Guard(label, function() error(message, 0) end) end
assert(Fail("expérience", "boom") == false)
Fail("expérience", "boom")
assert(#db.errors == 1 and db.errors[1].count == 2 and db.errors[1].text:find("^expérience : boom"), "the error is not kept")
for i = 1, 10 do Fail("autre", "problème " .. i) end
assert(#db.errors == 8 and db.errors[1].text:find("problème 10"), "the newest errors are not the ones kept")
db = Load(db)
assert(#db.errors == 8, "the kept errors went at load")

local panelSaid = ""
if panelPath then
    -- The settings panel, with stand-ins for its frames: every label and button in the order the
    -- panel makes them.
    local made = {}
    local function Widget(kind)
        local widget = { kind = kind, shown = true }
        setmetatable(widget, { __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return function() end end
        end })
        function widget:SetText(text) self.text = text end
        function widget:Show() self.shown = true end
        function widget:Hide() self.shown = false end
        function widget:IsShown() return self.shown end
        function widget:SetWidth(width) self.width = width end
        function widget:GetWidth() return self.width or 700 end
        function widget:SetHeight(height) self.height = height end
        function widget:GetHeight() return self.height or 500 end
        function widget:CreateTexture() return Widget("Texture") end
        function widget:CreateFontString()
            local label = Widget("FontString")
            made[#made + 1] = label
            return label
        end
        return widget
    end
    CreateFrame = function(kind) return Widget(kind) end
    UIParent = Widget("Frame")
    function ns.UIButton(_, text, _, _, click)
        local button = Widget("Button")
        button.caption, button.click = text, click
        button.text, button.back = Widget("FontString"), Widget("Texture")
        made[#made + 1] = button
        return button
    end
    assert(loadfile(panelPath))("WolkaraRoue", ns)
    ns.Settings:Init()
    local function Find(text, from)
        for i = from or 1, #made do if made[i].text == text or made[i].caption == text then return i end end
    end
    -- The wheel rows, in this order, each with the right side's stepper then the left side's.
    local rows = {}
    for _, label in ipairs({ "Roues", "Sorts par roue", "Taille des sorts", "Écart des sorts" }) do
        rows[#rows + 1] = assert(Find(label), "no row " .. label)
        assert(#rows == 1 or rows[#rows] > rows[#rows - 1], "the wheel rows are out of order")
    end
    local right = Find("Droite", rows[1])
    local rightMinus, rightPlus = made[Find("-", right)], made[Find("+", right)]
    local rightValue = made[Find("+", right) - 1]
    local left = Find("Gauche", rows[1])
    local leftMinus, leftPlus = made[Find("-", left)], made[Find("+", left)]
    assert(right < left and left < rows[2], "the wheels row does not hold the right then the left stepper")
    -- One more wheel on the right: five, said on the panel and recorded for the save; never
    -- past six, never under one.
    ns.db.free.wheels, ns.db.freeLeft.wheels = 4, 4
    rightPlus.click()
    assert(ns.db.free.wheels == 5 and ns.db.freeLeft.wheels == 4, "the + did not add a wheel on the right")
    assert(rightValue.text == "5", "the panel does not say five wheels")
    assert(marked[#marked] == "réglage : roues droite", "the change is not recorded as the right side's wheels")
    rightPlus.click(); rightPlus.click()
    assert(ns.db.free.wheels == 6, "more than six wheels")
    for _ = 1, 8 do leftMinus.click() end
    assert(ns.db.freeLeft.wheels == 1, "fewer than one wheel")
    leftPlus.click(); rightMinus.click()
    assert(ns.db.freeLeft.wheels == 2 and ns.db.free.wheels == 5)
    -- The spells on each wheel: the next row.
    local count = made[Find("+", Find("Droite", rows[2]))]
    local before = ns.db.free.count
    count.click()
    assert(ns.db.free.count == before + 1, "the spells-per-wheel + does not add a spell")
    -- How to go from one wheel to the next, said under the rows.
    local hint
    for i = rows[4], #made do
        local text = made[i].text
        if type(text) == "string" and text:find("diagonale") and text:find("onglets") then hint = i end
    end
    assert(hint and hint > rows[4], "the panel does not say how to change wheels")
    panelSaid = ", the panel sets each side's wheels (one to six) and spells per wheel and says how to change wheels"
end

print("mobile add-on settings: 0.5 golden wheel moved into the left wheel once, no duplicate or overwrite, chat and minimap defaults, a 0.7 save moved once into its wheels, four wheels a side by default and the player's number kept within one to six, the menu tab moved to the top once, reset keeps every wheel with a spell, caught errors kept in the save" .. panelSaid .. ": PASS")
