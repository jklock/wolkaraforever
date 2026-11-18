-- Task 12: loot toasts that fly to Bags and the loot card (mockup 78). Taking loot is only ever
-- a tap: no event makes a LootSlot call.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    return ns.Loot
end

local LINK = "|cff0070dd|Hitem:%d::::::::|h[%s]|h|r"
local function link(id, name) return LINK:format(id, name) end

local function lootLine(id, name, count)
    local l = link(id, name)
    if count then return ("You receive loot: %sx%d."):format(l, count) end
    return ("You receive loot: %s."):format(l)
end

local function shownToasts(Loot)
    local n = 0
    for _, t in ipairs(Loot.toasts) do if t:IsShown() then n = n + 1 end end
    return n
end

local function shownRows(Loot)
    local list = {}
    for _, r in ipairs(Loot.rows) do if r:IsShown() then list[#list + 1] = r end end
    return list
end

local function open(list, autoLoot)
    Stub.setLoot(list)
    Stub.fire("LOOT_OPENED", autoLoot == true, false)
end

local function noSource(file, word)
    local f = assert(io.open("addon/TouchPlay/" .. file)); local code = f:read("*a"); f:close()
    return not code:find(word, 1, true)
end

local MONEY = { kind = "money", copper = 2340 }
local QUEST = { kind = "item", name = "Mountain Lion Blood", quality = 1, quest = true, questID = 77 }
local FANG = { kind = "item", name = "Broken Fang", quality = 0, count = 2 }
local CLOAK = { kind = "item", name = "Hillborne Cloak", quality = 2 }
local CLOTH = { kind = "item", name = "Wool Cloth", quality = 1, count = 3 }

-- ---------------------------------------------------------------------------------------
-- Toasts

T("toast_per_loot_line_max_four", function()
    local Loot = setup()
    Stub.itemQuality[2589] = 1
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth", 3))
    assert(shownToasts(Loot) == 1)
    Stub.fire("CHAT_MSG_LOOT", lootLine(2592, "Wool Cloth"))
    Stub.fire("CHAT_MSG_LOOT", lootLine(2593, "Silk Cloth"))
    assert(shownToasts(Loot) == 3, "one toast per loot line")
    for i = 1, 5 do Stub.fire("CHAT_MSG_LOOT", lootLine(3000 + i, "Thing " .. i)) end
    assert(shownToasts(Loot) == 4, "four at most, got " .. shownToasts(Loot))
    assert(#Loot.toasts == 4, "from a pool of four")
    assert(not ns.paused, ns.lastError)
end)

T("toast_shows_icon_name_in_quality_colour_and_count", function()
    local Loot = setup()
    Stub.itemQuality[2589] = 2
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth", 3))
    local t
    for _, x in ipairs(Loot.toasts) do if x:IsShown() then t = x end end
    assert(t.name:GetText() == "Linen Cloth", t.name:GetText())
    local r, g, b = t.name:GetTextColor()
    assert(r == 0.12 and g == 1 and b == 0, "uncommon green")
    assert(t.count:GetText() == "x3" and t.count:IsShown())
    assert(t.icon:GetTexture() == "icon2589", tostring(t.icon:GetTexture()))
    Stub.fire("CHAT_MSG_LOOT", lootLine(2592, "Wool Cloth"))
    local u
    for _, x in ipairs(Loot.toasts) do if x:IsShown() and x ~= t then u = x end end
    assert(not u.count:IsShown(), "no count for one item")
    -- a quality the game does not report is read from the link's colour
    Stub.fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:9999::::::::|h[Blue Thing]|h|r.")
    local blue
    for _, x in ipairs(Loot.toasts) do if x:IsShown() and x.name:GetText() == "Blue Thing" then blue = x end end
    local br, bg, bb = blue.name:GetTextColor()
    assert(br == 0 and bg == 0.44 and bb == 0.87, "rare blue from the link colour")
end)

T("toast_flies_to_the_bags_ring", function()
    local Loot = setup()
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth"))
    local t
    for _, x in ipairs(Loot.toasts) do if x:IsShown() then t = x end end
    local cx, cy = Stub.centre(ns.Hud.bags)
    local a = t.touchAnchor
    assert(math.abs(t.flyX - (cx - (a.x + a.w / 2))) < 0.01, "x offset to the ring's centre")
    assert(math.abs(t.flyY - (-(cy - (a.y + a.h / 2)))) < 0.01, "y offset to the ring's centre")
    assert(t.group.playing == true, "it is flying")
    assert(not noSource("Loot.lua", "Hud.bags"), "the ring position is read from Hud, not copied")
end)

T("toast_goes_away_when_it_lands", function()
    local Loot = setup()
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth"))
    local t
    for _, x in ipairs(Loot.toasts) do if x:IsShown() then t = x end end
    t.group:_Fire("OnFinished")
    assert(shownToasts(Loot) == 0)
    -- the slot is free again
    for i = 1, 4 do Stub.fire("CHAT_MSG_LOOT", lootLine(2600 + i, "Thing " .. i)) end
    assert(shownToasts(Loot) == 4)
end)

T("toast_ignores_other_players_and_other_text", function()
    local Loot = setup()
    Stub.fire("CHAT_MSG_LOOT", ("Mira receives loot: %s."):format(link(2589, "Linen Cloth")))
    Stub.fire("CHAT_MSG_LOOT", "Someone rolled 54 for something.")
    Stub.fire("CHAT_MSG_LOOT", nil)
    Stub.fire("CHAT_MSG_LOOT", Stub.secret())
    assert(shownToasts(Loot) == 0 and not ns.paused, ns.lastError)
    -- pushed and created items are the player's too
    Stub.fire("CHAT_MSG_LOOT", ("You receive item: %s."):format(link(2589, "Linen Cloth")))
    Stub.fire("CHAT_MSG_LOOT", ("You create: %sx2."):format(link(2590, "Linen Bandage")))
    assert(shownToasts(Loot) == 2)
end)

T("toasts_stop_while_off", function()
    local Loot = setup()
    ns.SetEnabled(false)
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth"))
    assert(shownToasts(Loot) == 0)
end)

-- ---------------------------------------------------------------------------------------
-- The card

T("loot_card_rows_money_item_quest", function()
    local Loot = setup()
    Stub.quests[77] = { id = 77, title = "Elixir of Pain" }
    open({ MONEY, QUEST, FANG })
    assert(Loot.card:IsShown())
    local rows = shownRows(Loot)
    assert(#rows == 3, "three rows, got " .. #rows)
    assert(rows[1].name:GetText() == "23 silver 40 copper" and rows[1].sub:GetText() == "money", rows[1].name:GetText())
    assert(rows[2].name:GetText() == "Mountain Lion Blood")
    assert(rows[2].sub:GetText() == "quest item · Elixir of Pain", rows[2].sub:GetText())
    assert(rows[2].quest == true and rows[2].backdropBorderColor[4] == 1, "gold outline")
    assert(rows[1].quest ~= true and rows[3].quest ~= true)
    assert(rows[3].name:GetText() == "Broken Fang" and rows[3].count:GetText() == "2" and rows[3].count:IsShown())
    assert(rows[3].sub:GetText():find("^junk"), rows[3].sub:GetText())
    assert(not rows[2].count:IsShown(), "no count for one")
    local r, g, b = rows[3].name:GetTextColor()
    assert(r == 0.62, "junk is grey")
    assert(Loot.button1.label:GetText() == "Take all" and Loot.button2.label:GetText() == "Close")
    assert(not Loot.redLine:IsShown())
    -- a quest item with no quest name reads plain
    open({ { kind = "item", name = "Odd Thing", quality = 1, quest = true } })
    assert(shownRows(Loot)[1].sub:GetText() == "quest item")
end)

T("money_only_card", function()
    local Loot = setup()
    open({ { kind = "money", copper = 112 } })
    local rows = shownRows(Loot)
    assert(#rows == 1 and rows[1].name:GetText() == "1 silver 12 copper", rows[1].name:GetText())
    assert(Loot.button1.label:GetText() == "Take" and Loot.button2.label:GetText() == "Close")
    open({ { kind = "money", copper = 80000 } })
    assert(shownRows(Loot)[1].name:GetText() == "8 gold")
    open({ { kind = "money", copper = 123456 } })
    assert(shownRows(Loot)[1].name:GetText() == "12 gold 34 silver 56 copper")
    Stub.click(Loot.button1)
    assert(#Stub.lootTaken == 1 and Stub.lootTaken[1] == 1, "Take takes the money slot")
end)

T("take_all_only_from_click", function()
    local Loot = setup()
    open({ MONEY, QUEST, FANG })
    Stub.fire("LOOT_SLOT_CHANGED", 2)
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
    Stub.fire("BAG_UPDATE_DELAYED")
    Stub.fire("CHAT_MSG_LOOT", lootLine(2589, "Linen Cloth"))
    assert(Stub.calls.LootSlot == 0, "LOOT_OPENED and the rest make no LootSlot call")
    Stub.click(Loot.button1)
    assert(Stub.calls.LootSlot == 3, "a click makes one per slot, got " .. Stub.calls.LootSlot)
    assert(table.concat(Stub.lootTaken, ",") == "1,2,3")
    assert(not ns.paused, ns.lastError)
end)

T("only_the_click_handlers_call_lootslot", function()
    local f = assert(io.open("addon/TouchPlay/Loot.lua")); local code = f:read("*a"); f:close()
    local n = 0
    for _ in code:gmatch("LootSlot%(") do n = n + 1 end
    assert(n == 2, "LootSlot( appears in TakeAll and TakeMoney only, found " .. n)
    for _, bad in ipairs({ "CastSpell", "UseAction", "TargetUnit", "InteractUnit", "NewTicker", "C_Timer.NewTimer" }) do
        assert(noSource("Loot.lua", bad), bad)
    end
    -- the one timer is a 0 second look again at our own alpha, never an action
    local timers = 0
    for _ in code:gmatch("C_Timer") do timers = timers + 1 end
    assert(timers == 1 and code:find("C_Timer.After(0, ReapplyLate)", 1, true), "one timer: " .. timers)
end)

T("close_button_closes_the_loot", function()
    local Loot = setup()
    open({ MONEY, FANG })
    Stub.click(Loot.button2)
    assert(Stub.calls.CloseLoot == 1 and not Loot.card:IsShown())
    assert(Stub.calls.LootSlot == 0)
end)

T("loot_closed_and_cleared_slots_update_the_card", function()
    local Loot = setup()
    open({ MONEY, CLOAK, CLOTH })
    assert(#shownRows(Loot) == 3)
    -- a cleared slot: the money is gone
    Stub.setLoot({ { kind = "none" }, CLOAK, CLOTH })
    Stub.fire("LOOT_SLOT_CLEARED", 1)
    assert(#shownRows(Loot) == 2, "two rows left, got " .. #shownRows(Loot))
    Stub.fire("LOOT_CLOSED")
    assert(not Loot.card:IsShown())
    -- all slots gone: the card goes with them
    open({ MONEY })
    Stub.setLoot({ { kind = "none" } })
    Stub.fire("LOOT_SLOT_CLEARED", 1)
    assert(not Loot.card:IsShown())
end)

T("bags_full_dims_items", function()
    local Loot = setup()
    Stub.setBagsFull(true)
    open({ MONEY, CLOAK, CLOTH })
    local rows = shownRows(Loot)
    assert(#rows == 3)
    assert(rows[1].dim == false and rows[1]:GetAlpha() == 1, "the money row stays bright")
    assert(rows[2].dim == true and rows[3].dim == true and rows[2]:GetAlpha() < 1, "items dimmed")
    assert(Loot.redLine:IsShown())
    assert(Loot.redLine:GetText() == "Your bags are full. Take the money; the items stay here until you make room.",
        Loot.redLine:GetText())
    local r, g, b = Loot.redLine:GetTextColor()
    assert(r > 0.9 and g < 0.6 and b < 0.6, "red")
    assert(Loot.button1.label:GetText() == "Take money" and Loot.button2.label:GetText() == "Open bags")
    -- Take money takes only the money slot
    Stub.click(Loot.button1)
    assert(Stub.calls.LootSlot == 1 and Stub.lootTaken[1] == 1)
    -- Open bags opens the bags and takes nothing
    Stub.click(Loot.button2)
    assert(Stub.calls.OpenAllBags == 1 and Stub.calls.LootSlot == 1)
    -- room again: the rows are bright again on the next look
    Stub.setBagsFull(false)
    Stub.fire("LOOT_SLOT_CHANGED", 2)
    assert(shownRows(Loot)[2].dim == false and not Loot.redLine:IsShown())
    assert(Loot.button1.label:GetText() == "Take all")
end)

T("bags_fill_up_while_taking", function()
    local Loot = setup()
    open({ MONEY, CLOAK })
    assert(Loot.button1.label:GetText() == "Take all")
    Stub.setBagsFull(true)
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
    assert(Loot.redLine:IsShown() and Loot.button1.label:GetText() == "Take money")
    Stub.fire("UI_ERROR_MESSAGE", 1, Stub.secret())
    assert(not ns.paused, ns.lastError)
end)

T("auto_loot_on_shows_no_card", function()
    local Loot = setup()
    open({ MONEY, CLOAK }, true)
    assert(not Loot.card:IsShown() and Stub.calls.LootSlot == 0)
end)

T("auto_loot_on_with_full_bags_shows_what_stays", function()
    local Loot = setup()
    Stub.setBagsFull(true)
    -- the game took the money already; the items are left
    open({ { kind = "none" }, CLOAK }, true)
    assert(Loot.card:IsShown())
    local rows = shownRows(Loot)
    assert(#rows == 1 and rows[1].name:GetText() == "Hillborne Cloak" and rows[1].dim == true)
    assert(Loot.redLine:GetText() == "Your bags are full. The money is taken; the items stay here until you make room.",
        Loot.redLine:GetText())
    assert(Loot.button1.label:GetText() == "Open bags" and Loot.button2.label:GetText() == "Close")
    assert(Stub.calls.LootSlot == 0)
end)

T("many_slots_show_the_first_eight_and_more", function()
    local Loot = setup()
    local list = {}
    for i = 1, 11 do list[i] = { kind = "item", name = "Thing " .. i, quality = 1 } end
    open(list)
    assert(#shownRows(Loot) == 8)
    assert(Loot.moreLine:IsShown() and Loot.moreLine:GetText() == "+ 3 more")
    Stub.click(Loot.button1)
    assert(Stub.calls.LootSlot == 11, "Take all takes every slot, not only the ones shown")
end)

T("card_buttons_are_touch_sized", function()
    local Loot = setup()
    open({ MONEY, QUEST })
    for _, b in ipairs({ Loot.button1, Loot.button2 }) do
        local w, h = b:GetHitRectSize()
        assert(w >= 44 and h >= 44)
    end
end)

T("loot_card_stays_off_while_the_screen_is_off", function()
    local Loot = setup()
    ns.SetEnabled(false)
    open({ MONEY, QUEST })
    assert(not Loot.card:IsShown())
    -- and a card that was open goes with the screen
    ns.SetEnabled(true)
    open({ MONEY, QUEST }); assert(Loot.card:IsShown())
    ns.SetEnabled(false)
    assert(not Loot.card:IsVisible())
    ns.SetEnabled(true)
    assert(not Loot.card:IsShown(), "a card from before does not come back by itself")
end)

T("secret_loot_slot_text_does_not_raise", function()
    local Loot = setup()
    Stub.setLoot({ { kind = "item", name = Stub.secret(), quality = 1, count = 1 } })
    Stub.fire("LOOT_OPENED", false, false)
    assert(not ns.paused, ns.lastError)
    assert(Loot.card:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- The game's own loot window

-- An open game loot window with one interactive child, as the game builds it.
local function gameWindow(open)
    local frame = _G.LootFrame
    frame.shown = open ~= false
    local child = CreateFrame("Button", nil, frame)
    local grand = CreateFrame("Button", nil, child)
    return frame, child, grand
end

T("loot_card_hides_the_game_window_by_alpha", function()
    local Loot = setup()
    local frame, child, grand = gameWindow()
    open({ MONEY, CLOAK })
    assert(Loot.card:IsShown())
    assert(frame:GetAlpha() == 0 and not frame:IsMouseEnabled(), "invisible and untouchable")
    assert(not child:IsMouseEnabled() and not grand:IsMouseEnabled(), "and so are its children")
    assert(frame:GetParent() == _G.UIParent and frame.calls.SetParent == 0, "never reparented")
    assert(frame:IsShown(), "the game keeps its own window open")
    assert(Stub.calls.CloseLoot == 0, "the game's own open/close logic is not disturbed")
    assert(not ns.Bars.IsHidden("LootFrame"), "not in Bars' hidden list")
    for _, name in ipairs(ns.Bars.HIDDEN) do assert(name ~= "LootFrame") end
end)

T("game_window_untouched_when_no_card_shows", function()
    local Loot = setup()
    local frame, child = gameWindow()
    open({ MONEY, CLOAK }, true)
    assert(not Loot.card:IsShown())
    assert(frame:GetAlpha() == 1 and frame:IsMouseEnabled() and child:IsMouseEnabled())
end)

T("game_window_given_back_when_the_card_hides", function()
    local Loot = setup()
    local frame, child, grand = gameWindow(false)
    frame:SetAlpha(0.7)
    open({ MONEY, CLOAK })
    assert(frame:GetAlpha() == 0)
    Stub.fire("LOOT_CLOSED")
    assert(not Loot.card:IsShown())
    assert(frame:GetAlpha() == 0.7, "exactly what it was")
    assert(frame:IsMouseEnabled() and child:IsMouseEnabled() and grand:IsMouseEnabled())
    -- Close does the same
    open({ MONEY, CLOAK }); assert(frame:GetAlpha() == 0)
    Stub.click(Loot.button2)
    assert(frame:GetAlpha() == 0.7 and child:IsMouseEnabled())
end)

T("game_window_still_closing_is_given_back_when_it_has_hidden", function()
    local Loot = setup()
    local frame, child = gameWindow(true)
    open({ MONEY, CLOAK })
    Stub.fire("LOOT_CLOSED")
    assert(frame:GetAlpha() == 0 and not child:IsMouseEnabled(), "still playing its own hide: stays invisible")
    frame:Hide()                          -- the game finishes closing (its OnHide runs)
    assert(frame:GetAlpha() == 1 and child:IsMouseEnabled() and frame:IsMouseEnabled())
    -- a second loot while one is pending
    frame.shown = true
    open({ MONEY, CLOAK }); Stub.fire("LOOT_CLOSED")
    open({ MONEY }); assert(frame:GetAlpha() == 0)
    frame:Hide(); assert(frame:GetAlpha() == 0, "the card is up again: a late hide does not give it back")
end)

T("game_window_given_back_on_pause_and_off", function()
    local Loot = setup()
    local frame, child = gameWindow()
    frame:SetAlpha(0.9)
    open({ MONEY, CLOAK }); assert(frame:GetAlpha() == 0)
    ns.Pause("test")
    assert(frame:GetAlpha() == 0.9 and child:IsMouseEnabled() and frame:IsMouseEnabled(), "back on a pause")
    ns.paused = false; ns.SetEnabled(true)
    open({ MONEY, CLOAK }); assert(frame:GetAlpha() == 0)
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 0.9 and child:IsMouseEnabled(), "back when off")
    assert(frame.calls.SetParent == 0 and Stub.calls.CloseLoot == 0)
end)

T("switching_on_mid_loot_never_closes_the_loot", function()
    local Loot = setup()
    local frame = gameWindow(true)
    ns.SetEnabled(false); ns.SetEnabled(true)
    ns.Pause("test"); ns.paused = false; ns.SetEnabled(true)
    ns.Each("Layout"); ns.Each("Refresh")
    assert(Stub.calls.CloseLoot == 0, "no CloseLoot, got " .. Stub.calls.CloseLoot)
    assert(frame:GetParent() == _G.UIParent and frame.calls.SetParent == 0)
    assert(frame:IsShown() and frame:GetAlpha() == 1, "the game's window is as it was")
end)

T("game_window_changes_in_a_fight", function()
    local Loot = setup()
    local frame, child = gameWindow()
    Stub.combat(true)
    open({ MONEY, CLOAK })
    assert(not ns.paused, ns.lastError)
    assert(frame:GetAlpha() == 0, "not protected: works in a fight")
end)

-- ---------------------------------------------------------------------------------------
-- The game's open animation and the rows it builds

T("open_animation_does_not_undo_our_alpha", function()
    local Loot = setup()
    local frame = gameWindow(true)
    local anim = frame.ShowAnim
    anim:Play(true)                         -- the game's own LOOT_OPENED handler runs first
    open({ MONEY, CLOAK })
    assert(Loot.card:IsShown() and frame:GetAlpha() == 0)
    Stub.finishAnim(anim)                   -- 0.1 s later the game sets the final alpha, 1
    assert(frame:GetAlpha() == 0, "our card is up: the window stays invisible")
    anim:Play(true); assert(frame:GetAlpha() == 0, "also when it plays again")
    Stub.finishAnim(anim, true)             -- an engine that sets the alpha after the scripts
    Stub.advance(0.01)
    assert(frame:GetAlpha() == 0, "and when the final alpha comes late")
    assert(not frame:IsMouseEnabled())
end)

T("open_animation_not_forced_when_the_card_is_down", function()
    local Loot = setup()
    local frame = gameWindow(true)
    -- no card (auto-loot with room): the game's animation does what it likes
    frame.ShowAnim:Play(true); frame:SetAlpha(0.3)
    open({ MONEY, CLOAK }, true)
    Stub.finishAnim(frame.ShowAnim); Stub.advance(1)
    assert(frame:GetAlpha() == 1 and frame:IsMouseEnabled(), "nothing forced")
    -- a card that came and went
    open({ MONEY, CLOAK }); assert(frame:GetAlpha() == 0)
    frame.shown = false
    Stub.fire("LOOT_CLOSED")
    assert(frame:GetAlpha() == 1)
    frame.ShowAnim:Play(true); Stub.finishAnim(frame.ShowAnim, true); Stub.advance(1)
    assert(frame:GetAlpha() == 1, "the hooks do nothing once the card is hidden")
end)

T("alpha_the_game_left_is_not_given_back_as_invisible", function()
    local Loot = setup()
    local frame = gameWindow(true)
    frame:SetAlpha(0)                       -- a hide animation left it at its final alpha, 0
    frame.ShowAnim:Play(true)
    open({ MONEY, CLOAK })
    Stub.finishAnim(frame.ShowAnim)         -- the open animation says 1: that is what the game wants
    assert(frame:GetAlpha() == 0)
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 1, "given back as the game last set it")
    -- Off before the animation ends: a shown window is never given back at 0
    ns.SetEnabled(true)
    frame:SetAlpha(0); frame.ShowAnim:Play(true)
    open({ MONEY, CLOAK })
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 1, "a shown window comes back visible")
end)

T("rows_built_after_the_card_are_quieted", function()
    local Loot = setup()
    local frame, child = gameWindow(true)
    local early = Stub.addLootRow()
    open({ MONEY, CLOAK })
    assert(not early:IsMouseEnabled(), "a row built before the card is caught by the sweep")
    local late = Stub.addLootRow()          -- the game builds more as it scrolls or refills
    assert(not late:IsMouseEnabled(), "a row built after the card is switched off when it appears")
    frame.shown = false
    Stub.fire("LOOT_CLOSED")
    assert(early:IsMouseEnabled() and late:IsMouseEnabled() and child:IsMouseEnabled(), "all given back")
    local plain = Stub.addLootRow()
    assert(plain:IsMouseEnabled(), "no card: rows are the game's")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Auto-loot that only half fits

T("auto_loot_partial_fill_shows_the_leftovers", function()
    local Loot = setup()
    Stub.freeBagSlots = 1
    local frame = gameWindow()
    open({ MONEY, CLOAK, CLOTH, FANG }, true)
    assert(not Loot.card:IsShown(), "room for one: no card yet")
    -- the game fills the bags and says so
    Stub.setBagsFull(true)
    Stub.setLoot({ { kind = "none" }, CLOAK, { kind = "none" }, { kind = "none" } })
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
    assert(Loot.card:IsShown(), "what stays is shown")
    assert(#shownRows(Loot) == 1 and shownRows(Loot)[1].dim == true)
    assert(Loot.button1.label:GetText() == "Open bags")
    assert(frame:GetAlpha() == 0, "the game's own window steps aside for it")
    assert(Stub.calls.LootSlot == 0, "showing takes nothing")
end)

T("auto_loot_partial_fill_each_event_path", function()
    for _, fire in ipairs({
        function() Stub.fire("LOOT_SLOT_CLEARED", 1) end,
        function() Stub.fire("BAG_UPDATE_DELAYED") end,
        function() Stub.fire("LOOT_SLOT_CHANGED", 2) end,
    }) do
        local Loot = setup()
        Stub.freeBagSlots = 1
        open({ CLOAK, CLOTH }, true)
        assert(not Loot.card:IsShown())
        Stub.setBagsFull(true); Stub.setLoot({ { kind = "none" }, CLOTH })
        fire()
        assert(Loot.card:IsShown() and #shownRows(Loot) == 1)
    end
end)

T("auto_loot_with_room_left_stays_hidden_and_empty_window_never_shows", function()
    local Loot = setup()
    open({ CLOAK, CLOTH }, true)
    Stub.setLoot({ { kind = "none" }, CLOTH })
    Stub.fire("LOOT_SLOT_CLEARED", 1); Stub.fire("BAG_UPDATE_DELAYED")
    assert(not Loot.card:IsShown(), "bags have room: the game is still taking it")
    Stub.setBagsFull(true); Stub.setLoot({ { kind = "none" }, { kind = "none" } })
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
    assert(not Loot.card:IsShown(), "nothing left: nothing to show")
end)

T("loot_events_after_close_do_not_open_a_card", function()
    local Loot = setup()
    Stub.freeBagSlots = 1
    open({ CLOAK, CLOTH }, true)
    Stub.fire("LOOT_CLOSED")
    Stub.setBagsFull(true)
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL); Stub.fire("BAG_UPDATE_DELAYED")
    assert(not Loot.card:IsShown(), "the window is closed")
    -- and a card the player closed stays closed
    Stub.setBagsFull(true)
    open({ CLOAK }, true); assert(Loot.card:IsShown())
    Stub.click(Loot.button2)
    Stub.fire("BAG_UPDATE_DELAYED"); Stub.fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
    assert(not Loot.card:IsShown(), "Close was a decision")
end)

T("loot_needs_no_polling", function()
    local Loot = setup()
    assert(Loot.card.scripts.OnUpdate == nil)
    assert(noSource("Loot.lua", "OnUpdate"), "no OnUpdate in Loot.lua")
end)

T("loot_strings_come_from_the_table", function()
    setup()
    local want = { ["loot.takeAll"] = "Take all", ["loot.take"] = "Take", ["loot.takeMoney"] = "Take money",
        ["loot.openBags"] = "Open bags", ["loot.money"] = "money", ["loot.questItem"] = "quest item",
        ["loot.quest"] = "quest item · %s" }
    for key, text in pairs(want) do assert(ns.L[key] == text, key .. " = " .. tostring(ns.L[key])) end
    for key, text in pairs(ns.L) do
        if key:match("^loot%.") then assert(not text:find("\226\128\148"), "no em dash: " .. key) end
    end
end)

-- I7 (R32): opening the bags is refused to add-on code in a fight, so Open bags is greyed then with "After the fight"
-- and does nothing; out of a fight it opens them (inside pcall). No secure child goes on the loot card (I1).
T("open_bags_is_greyed_in_a_fight_and_works_after_it", function()
    local Loot = setup()
    Stub.setBagsFull(true)
    open({ MONEY, CLOAK })
    local b = Loot.button2
    assert(b.label:GetText() == "Open bags" and b:IsEnabled())
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    assert(not b:IsEnabled() and b.reasonText:IsShown() and b.reasonText:GetText() == "After the fight",
        "greyed with the reason")
    Stub.click(b)
    assert(Stub.calls.OpenAllBags == 0 and #Stub.blocked == 0 and not ns.paused, tostring(ns.lastError))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(b:IsEnabled() and not b.reasonText:IsShown())
    Stub.click(b)
    assert(Stub.calls.OpenAllBags == 1 and #Stub.blocked == 0)
    assert(not Loot.card:IsProtected(), "the loot card holds nothing secure")
    -- a fight starting with the card already up, bags full and no money: Open bags is the first button
    Stub.setLoot({ CLOAK }); Stub.fire("LOOT_SLOT_CHANGED", 1)
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    assert(Loot.button1.label:GetText() == "Open bags" and not Loot.button1:IsEnabled())
    assert(Loot.button2:IsEnabled(), "Close still works")
    -- a missing or changed Blizzard function never pauses us
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    OpenAllBags, ToggleAllBags = function() error("the game changed") end, nil
    Stub.click(Loot.button1)
    assert(not ns.paused, tostring(ns.lastError))
end)

Stub.done("loot")
