-- iPad run 5: a sideways swipe turns pages, in TouchPlay's paged panels and the game's paged windows (out of a fight).
-- While a window is open the app sends a swipe as a left down at its start and a left up at its lift (ruling A33):
-- the game's GLOBAL_MOUSE_DOWN and GLOBAL_MOUSE_UP.
dofile("tests/stub.lua")

-- The middle of `frame` in screen units, and a point `dx`, `dy` layout units from it (y up).
local function middle(frame)
    local l, b, w, h = frame:GetRect()
    local s = frame:GetEffectiveScale()
    return (l + w / 2) * s, (b + h / 2) * s
end

local function swipe(frame, dx, dy)
    local x, y = middle(frame)
    Stub.pointer(x, y); Stub.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    local k = ns.root:GetEffectiveScale()
    Stub.pointer(x + dx * k, y + (dy or 0) * k); Stub.fire("GLOBAL_MOUSE_UP", "LeftButton")
end

local function cellOf(name)
    for _, cell in ipairs(ns.Picker.cells) do
        if cell:IsShown() and cell.label:GetText() == name then return cell end
    end
end

local function longSchool()
    Stub.reset(); Stub.loadAll(); Stub.login(); Stub.fire("PLAYER_ENTERING_WORLD")
    local many = {}
    for i = 1, 14 do many[i] = { id = 1000 + i, name = "Spell " .. i } end
    Stub.spellbook.lines[4].spells = many
    Stub.actions[2] = 122; ns.Picker.Open(2); Stub.click(ns.Picker.tabs.buttons[4])
    assert(ns.Picker.pageCount == 2 and ns.Picker.pageText:GetText() == "1/2")
    return ns.Picker
end

T("swipe_left_on_the_picker_turns_to_the_next_page_and_right_back", function()
    local Picker = longSchool()
    swipe(Picker.sheet, -120, 10)
    assert(Picker.page == 2 and Picker.pageText:GetText() == "2/2" and cellOf("Spell 13"), "next page, label updated")
    swipe(Picker.sheet, 120, -10)
    assert(Picker.page == 1 and Picker.pageText:GetText() == "1/2" and cellOf("Spell 1"), "back")
    assert(not ns.paused, ns.lastError)
end)

T("swipe_past_the_last_page_goes_to_the_next_tab_and_back_to_its_last_page", function()
    local Picker = longSchool()
    local tab = Picker.tabPos
    swipe(Picker.sheet, -120); swipe(Picker.sheet, -120)
    assert(Picker.tabPos == tab + 1 and Picker.page == 1, "the next tab")
    swipe(Picker.sheet, 120)
    assert(Picker.tabPos == tab and Picker.page == 2, "back: the tab before, on its last page")
end)

T("short_upright_or_dragging_moves_are_not_swipes", function()
    local Picker = longSchool()
    swipe(Picker.sheet, -50, 0); assert(Picker.page == 1, "under 60 units")
    swipe(Picker.sheet, -100, 80); assert(Picker.page == 1, "not mostly sideways")
    swipe(Picker.sheet, -100, 49); assert(Picker.page == 2, "sideways enough")
    swipe(Picker.sheet, 100, 0); assert(Picker.page == 1)
    Stub.cursor = { kind = "item", id = 4540 }        -- an item being dragged
    swipe(Picker.sheet, -120, 0); assert(Picker.page == 1, "a drag is not a swipe")
    Stub.cursor = nil
    local x, y = middle(Picker.sheet)                  -- a right click (a hold, in a window) is not a swipe
    Stub.pointer(x, y); Stub.fire("GLOBAL_MOUSE_DOWN", "RightButton")
    Stub.pointer(x - 200, y); Stub.fire("GLOBAL_MOUSE_UP", "RightButton")
    assert(Picker.page == 1)
    -- started outside the sheet: nothing
    Stub.pointer(1, 1); Stub.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    Stub.pointer(x - 200, y); Stub.fire("GLOBAL_MOUSE_UP", "LeftButton")
    assert(Picker.page == 1)
end)

T("swipe_through_the_guide_steps", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    ns.Guide.Show()
    ns.Guide.dim.touchAnchor = { x = 0, y = 0, w = 1366, h = 1024 }   -- the dim covers the screen
    assert(ns.Guide.step == 1)
    swipe(ns.Guide.dim, -150)
    assert(ns.Guide.step == 2 and ns.Guide.counter:GetText():find("2"), "the counter follows")
    swipe(ns.Guide.dim, 150)
    assert(ns.Guide.step == 1)
    swipe(ns.Guide.dim, 150)
    assert(ns.Guide.step == 1, "nothing before the first")
end)

T("swipe_a_unit_card_to_its_second_page", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Stub.setTarget("player"); Stub.applyUnitWatch()
    ns.InfoCard.Show({ kind = "unit", unit = "target" }, ns.Units.target)
    assert(ns.InfoCard.IsShown())
    local frame = ns.InfoCard.frame
    frame.touchAnchor = { x = frame.placeX, y = frame.placeY, w = frame:GetWidth(), h = frame:GetHeight() }
    swipe(frame, -120)
    local labels = {}
    for i = 1, frame.buttonCount do labels[#labels + 1] = frame.buttons[i].label:GetText() end
    assert(table.concat(labels, "|"):find(ns.T("card.back"), 1, true), "page 2: " .. table.concat(labels, "|"))
    swipe(frame, 120)
    labels = {}
    for i = 1, frame.buttonCount do labels[#labels + 1] = frame.buttons[i].label:GetText() end
    assert(table.concat(labels, "|"):find(ns.T("common.more"), 1, true), "page 1 again")
end)

-- The game's merchant window: its own page buttons are clicked (plain Lua paging, nothing protected behind it).
local function merchant()
    local window = CreateFrame("Frame", "MerchantFrame", UIParent)
    window.touchAnchor = { x = 100, y = 100, w = 400, h = 500 }
    local clicks = { next = 0, prev = 0 }
    for _, spec in ipairs({ { "MerchantNextPageButton", "next" }, { "MerchantPrevPageButton", "prev" } }) do
        local b = CreateFrame("Button", spec[1], window)
        b:SetScript("OnClick", function() clicks[spec[2]] = clicks[spec[2]] + 1 end)
    end
    return window, clicks
end

T("swipe_on_the_merchant_clicks_its_page_buttons_out_of_a_fight", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local window, clicks = merchant()
    swipe(window, -120)
    assert(clicks.next == 1 and clicks.prev == 0)
    swipe(window, 120)
    assert(clicks.prev == 1)
    _G.MerchantNextPageButton:Disable()
    swipe(window, -120); assert(clicks.next == 1, "a greyed button is not clicked")
    _G.MerchantNextPageButton:Enable()
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    swipe(window, -120); assert(clicks.next == 1, "not in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    swipe(window, -120); assert(clicks.next == 2)
    ns.SetEnabled(false)
    swipe(window, -120); assert(clicks.next == 2, "Off: nothing")
    window:Hide(); _G.MerchantFrame = nil; _G.MerchantNextPageButton = nil; _G.MerchantPrevPageButton = nil
    assert(not ns.paused, ns.lastError)
end)

T("no_spellbook_paging", function()
    local f = assert(io.open("addon/TouchPlay/Swipe.lua")); local text = f:read("*a"); f:close()
    local code = text:gsub("%-%-[^\n]*", "")
    assert(not code:find("SpellBook") and not code:find("PlayerSpells"), "the spellbook is never paged by add-on code")
end)

Stub.done("swipe")
