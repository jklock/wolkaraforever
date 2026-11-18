-- Task 8: the item column (rule 6); mockups 01, 32, 72.
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

-- A game session with the add-on loaded and laid out.
local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    ItemRail = ns.ItemRail
    return ItemRail
end

-- Bag items that are in the bags before login (the column fills itself at login).
-- one of each kind in the bags, so every slot has something to glow for
local FULL = { { id = 4599, cat = "food", req = 1, count = 3 }, { id = 1179, cat = "drink", req = 1, count = 3 },
    { id = 118, cat = "health", req = 1, count = 2 }, { id = 119, cat = "mana", req = 1, count = 1 } }
local setupFull

local function setupWith(items)
    Stub.reset(); Stub.loadAll()
    for _, item in ipairs(items) do Stub.addBagItem(item) end
    Stub.login()
    ItemRail = ns.ItemRail
    return ItemRail
end

function setupFull() return setupWith(FULL) end

T("rule6_choose_best", function()
    setup()
    local r = ItemRail.Choose({{id = 1, cat = "food", req = 25, count = 4}, {id = 2, cat = "food", req = 35, count = 1}}, 34, {})
    assert(r.food == 1) -- level 35 food is not usable at 34
end)
T("rule6_pinned_keeps_slot_at_zero", function() setup(); local r = ItemRail.Choose({}, 34, {mana = 5513}); assert(r.mana == 5513) end)
T("rule6_updates_after_fight_not_during", function()
    setup(); Stub.combat(true); Stub.addBagItem({id = 3, cat = "drink", req = 30, count = 20}); Stub.fire("BAG_UPDATE_DELAYED")
    assert(ItemRail.buttons[2]:GetAttribute("item") ~= "item:3")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); assert(ItemRail.buttons[2]:GetAttribute("item") == "item:3")
end)
T("rule6_missing_category_empty", function() setup(); assert(ItemRail.buttons[3].empty:IsShown() and ItemRail.buttons[3].plus:IsShown()) end)
T("secret_values_never_touched", function()
    setup(); Stub.secretUnits(true); Stub.fire("PLAYER_REGEN_ENABLED"); assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Choosing

T("choose_highest_level_then_highest_stack_then_lowest_id", function()
    setup()
    local items = {
        { id = 10, cat = "drink", req = 20, count = 5 },
        { id = 11, cat = "drink", req = 30, count = 2 },
        { id = 12, cat = "drink", req = 30, count = 9 },
        { id = 13, cat = "drink", req = 30, count = 9 },
        { id = 20, cat = "health", req = 10, count = 3 },
    }
    local r = ItemRail.Choose(items, 34, {})
    assert(r.drink == 12, "same level: the bigger stack, then the lower id")
    assert(r.health == 20 and r.food == nil and r.mana == nil)
end)
T("choose_skips_empty_stacks_and_unknown_categories", function()
    setup()
    local r = ItemRail.Choose({ { id = 1, cat = "food", req = 1, count = 0 }, { id = 2, cat = "scroll", req = 1, count = 5 } }, 34, {})
    assert(r.food == nil and r.scroll == nil)
end)
T("choose_level_equal_is_usable", function()
    setup()
    assert(ItemRail.Choose({ { id = 1, cat = "mana", req = 34, count = 1 } }, 34, {}).mana == 1)
end)
T("choose_pin_wins_over_a_better_item", function()
    setup()
    local r = ItemRail.Choose({ { id = 2, cat = "food", req = 30, count = 9 } }, 34, { food = 1 })
    assert(r.food == 1)
end)
T("choose_does_not_change_its_input_and_reuses_out", function()
    setup()
    local items = { { id = 2, cat = "food", req = 30, count = 9 } }
    local out = {}
    assert(ItemRail.Choose(items, 34, nil, out) == out and out.food == 2)
    ItemRail.Choose({}, 34, nil, out); assert(out.food == nil, "an earlier answer does not linger")
    assert(items[1].count == 9 and #items == 1)
end)

-- ---------------------------------------------------------------------------------------
-- The buttons

T("four_secure_buttons_at_the_mockup_places", function()
    setup()
    assert(#ItemRail.buttons == 4)
    for i, b in ipairs(ItemRail.buttons) do
        assert(b:GetName() == "TouchPlayItem" .. i and Stub.inherits(b, "SecureActionButtonTemplate"))
        assert(b:GetWidth() == 48 and b:GetHeight() == 48)
        local a = b.touchAnchor
        -- placed from the bottom-right corner (it scales with the cluster, I5); at Button size 1 that is the mockup place
        assert(a.corner == "BR" and a.x == 1300 and a.y == 300 + 66 * (i - 1), "item " .. i)
        assert(select(2, b:GetHitRectSize()) >= 44)
    end
end)
T("quickslot_frame_is_1_68_times_the_icon", function()
    setup()
    local off = (math.floor(48 * 1.68 + 0.5) - 48) / 2
    local tl, br = ItemRail.buttons[1]:GetNormalTexture().points[1], ItemRail.buttons[1]:GetNormalTexture().points[2]
    assert(tl[1] == "TOPLEFT" and near(tl[4], -off) and near(tl[5], off))
    assert(br[1] == "BOTTOMRIGHT" and near(br[4], off) and near(br[5], -off))
end)
T("column_fills_itself_at_login", function()
    setupWith({
        { id = 100, cat = "food", req = 5, count = 12 },
        { id = 101, cat = "drink", req = 5, count = 20 },
        { id = 5513, cat = "gem", req = 0, count = 1 },
        { id = 102, cat = "health", req = 5, count = 4 },
        { id = 103, cat = "mana", req = 5, count = 7 },
    })
    local want = { "item:100", "item:101", "item:102", "item:103" }   -- the gem (req 0) loses to the mana potion
    for i, b in ipairs(ItemRail.buttons) do
        assert(b:GetAttribute("item") == want[i], i .. " " .. tostring(b:GetAttribute("item")))
        assert(b:GetAttribute("*type1") == "item")
        assert(not b.empty:IsShown() and b.icon:IsShown())
    end
    assert(ItemRail.buttons[2].count:GetText() == "20" and ItemRail.buttons[4].count:GetText() == "7"
        and ItemRail.buttons[3].count:GetText() == "4")
end)
T("a_tap_uses_the_item_and_a_hold_never_does", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    local b = ItemRail.buttons[2]
    Stub.click(b, "LeftButton"); assert(Stub.lastItemUsed == "item:101")
    Stub.lastItemUsed = nil
    assert(b:GetAttribute("type2") == nil and b:GetAttribute("type") == nil)
    Stub.click(b, "RightButton"); assert(Stub.lastItemUsed == nil, "a right click does not use the item")
end)
T("hold_opens_the_item_card", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    Stub.click(ItemRail.buttons[2], "RightButton")
    assert(ns.InfoCard.IsShown() and ns.InfoCard.Title() ~= nil)
end)
T("hold_on_an_empty_slot_never_uses_anything", function()
    setup(); Stub.click(ItemRail.buttons[3], "RightButton"); assert(Stub.lastItemUsed == nil and not ns.paused)
end)
T("same_item_in_two_bags_counts_together", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 }, { id = 101, cat = "drink", req = 5, count = 5 } })
    assert(ItemRail.buttons[2].count:GetText() == "25")
end)
T("only_the_four_kinds_are_picked_up", function()
    setupWith({ { id = 900, cat = "armor", req = 1, count = 1 } })
    for _, b in ipairs(ItemRail.buttons) do assert(b:GetAttribute("item") == nil and b.empty:IsShown()) end
end)
T("level_gate_follows_the_player", function()
    setupWith({ { id = 1, cat = "food", req = 25, count = 4 }, { id = 2, cat = "food", req = 35, count = 1 } })
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:1")
    Stub.setUnit("player", { level = 35 }); Stub.fire("PLAYER_LEVEL_UP")
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:2")
end)
T("an_item_the_game_has_not_told_us_about_is_asked_again", function()
    Stub.reset(); Stub.loadAll(); Stub.addBagItem({ id = 7, cat = "food", req = 5, count = 3 }); Stub.itemUnloaded[7] = true
    Stub.login(); ItemRail = ns.ItemRail
    assert(ItemRail.buttons[1]:GetAttribute("item") == nil)
    Stub.itemUnloaded[7] = nil; Stub.fire("GET_ITEM_INFO_RECEIVED", 7)
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:7")
end)

-- ---------------------------------------------------------------------------------------
-- The fight

T("nothing_secure_is_touched_in_a_fight", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    Stub.combat(true)
    Stub.addBagItem({ id = 150, cat = "food", req = 5, count = 3 }); Stub.fire("BAG_UPDATE_DELAYED")
    Stub.fire("PLAYER_LEVEL_UP"); Stub.fire("BAG_UPDATE_COOLDOWN")
    assert(not ns.paused, ns.lastError)
    assert(ItemRail.buttons[1]:GetAttribute("item") == nil)
end)
T("counts_and_grey_follow_the_bags_in_a_fight", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    Stub.combat(true)
    Stub.removeBagItem(101); Stub.addBagItem({ id = 101, cat = "drink", req = 5, count = 19 }); Stub.fire("BAG_UPDATE_DELAYED")
    assert(ItemRail.buttons[2].count:GetText() == "19")
    Stub.removeBagItem(101); Stub.fire("BAG_UPDATE_DELAYED")
    assert(ItemRail.buttons[2].count:GetText() == "0" and ItemRail.buttons[2].icon.desaturated == true,
        "the last one used in a fight: grey 0 until the fight ends")
    assert(ItemRail.buttons[2]:GetAttribute("item") == "item:101")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[2]:GetAttribute("item") == nil and ItemRail.buttons[2].empty:IsShown(), "then the slot empties")
end)
T("an_item_that_runs_out_leaves_its_slot_empty", function()
    setupWith({ { id = 5513, cat = "gem", req = 0, count = 1 } })
    assert(ItemRail.buttons[4]:GetAttribute("item") == "item:5513", "a mana gem fills the mana slot")
    Stub.removeBagItem(5513); Stub.fire("BAG_UPDATE_DELAYED")
    local b = ItemRail.buttons[4]
    assert(b:GetAttribute("item") == nil and b:GetAttribute("*type1") == nil and b.empty:IsShown())
    assert(b.count:GetText() == "" and not b.pin:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- Pins

T("pin_stores_in_the_character_data_and_keeps_the_slot", function()
    setupWith({ { id = 5513, cat = "gem", req = 0, count = 1 } })
    ItemRail.Pin(4, 5513)
    assert(ns.char.pins.mana == 5513 and TouchPlayCharDB.pins.mana == 5513)
    assert(ItemRail.buttons[4].pin:IsShown())
    Stub.removeBagItem(5513); Stub.fire("BAG_UPDATE_DELAYED")
    local b = ItemRail.buttons[4]
    assert(b:GetAttribute("item") == "item:5513", "pinned: the slot stays")
    assert(b.count:GetText() == "0" and b.icon.desaturated == true and b.pin:IsShown() and not b.empty:IsShown(), "grey 0, badge")
    -- buy more: it fills again, no longer grey
    Stub.addBagItem({ id = 5513, cat = "gem", req = 0, count = 3 }); Stub.fire("BAG_UPDATE_DELAYED")
    assert(b.count:GetText() == "3" and b.icon.desaturated == false)
end)
T("a_pin_beats_a_better_item", function()
    setupWith({ { id = 1, cat = "food", req = 5, count = 4 }, { id = 2, cat = "food", req = 30, count = 9 } })
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:2")
    ItemRail.Pin(1, 1); assert(ItemRail.buttons[1]:GetAttribute("item") == "item:1")
    ItemRail.Unpin(1); assert(ItemRail.buttons[1]:GetAttribute("item") == "item:2" and not ItemRail.buttons[1].pin:IsShown())
end)
T("pin_in_a_fight_waits_for_the_fight", function()
    setupWith({ { id = 1, cat = "food", req = 5, count = 4 }, { id = 2, cat = "food", req = 30, count = 9 } })
    Stub.combat(true); ItemRail.Pin(1, 1)
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:2")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:1")
end)
-- The labels on the open item card, in order.
local function cardLabels()
    local out = {}
    for i = 1, ns.InfoCard.frame.buttonCount do out[i] = ns.InfoCard.frame.buttons[i].label:GetText() end
    return table.concat(out, "|")
end
local function press(label)
    for i = 1, ns.InfoCard.frame.buttonCount do
        local b = ns.InfoCard.frame.buttons[i]
        if b.label:GetText() == label then Stub.click(b); return true end
    end
end

T("pin_and_unpin_on_the_item_card", function()
    setupWith({ { id = 1, cat = "food", req = 5, count = 4 }, { id = 2, cat = "food", req = 30, count = 9 } })
    local card = ns.InfoCard
    -- the card of the lower food (held in the bags): Pin pins it, Unpin is not offered yet
    card.Show({ kind = "item", bag = 0, slot = 1 })
    assert(cardLabels() == "Use|Link|Pin", cardLabels())
    assert(press("Pin"))
    assert(ns.char.pins.food == 1 and ItemRail.buttons[1]:GetAttribute("item") == "item:1")
    -- the pinned one offers Unpin only; the other food of that kind offers Pin again
    card.Show({ kind = "item", bag = 0, slot = 1 }); assert(cardLabels() == "Use|Link|Unpin", cardLabels())
    card.Show({ kind = "item", bag = 0, slot = 2 }); assert(cardLabels() == "Use|Link|Pin", cardLabels())
    card.Show({ kind = "item", bag = 0, slot = 1 }); assert(press("Unpin")); assert(ns.char.pins.food == nil)
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:2")
    -- an item card from a link (a pinned item with none left) works too
    card.Show({ kind = "item", link = "item:1" }); assert(cardLabels() == "Link|Close|Pin", cardLabels())
    assert(press("Pin")); assert(ns.char.pins.food == 1)
    card.Show({ kind = "item", link = "item:1" }); assert(cardLabels() == "Link|Close|Unpin", cardLabels())
end)
T("pin_and_unpin_with_a_merchant_open_show_the_right_one", function()
    setupWith({ { id = 1, cat = "food", req = 5, count = 4 } })
    Stub.setMerchant(true)
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(cardLabels() == "Use|Link|Sell|Pin", cardLabels())
    assert(press("Pin")); assert(ns.char.pins.food == 1)
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(cardLabels() == "Use|Link|Sell|Unpin", cardLabels())
    assert(press("Unpin")); assert(ns.char.pins.food == nil)
end)
T("neither_pin_nor_unpin_for_other_kinds_of_item", function()
    setupWith({ { id = 900, cat = "armor", req = 1, count = 1 } })
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(not cardLabels():find("Pin") and not cardLabels():find("Unpin"), cardLabels())
    assert(next(ns.char.pins) == nil and not ns.paused)
end)
T("pin_card_buttons_never_use_the_item", function()
    setupWith({ { id = 1, cat = "food", req = 5, count = 4 } })
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 }); press("Pin")
    assert(Stub.lastUsedItem == nil and Stub.lastItemUsed == nil)
end)
T("a_pinned_item_keeps_full_colour_after_a_tap_or_hold", function()
    setupWith({ { id = 5513, cat = "gem", req = 0, count = 2 } })
    ItemRail.Pin(4, 5513)
    local b = ItemRail.buttons[4]
    assert(b.icon.alpha == 1 and b.icon.desaturated == false)
    Stub.mouseDown(b); assert(b.icon.alpha == 0.7, "pressed")
    Stub.mouseUp(b); assert(b.icon.alpha == 1 and b.icon.desaturated == false, "back to full colour")
    Stub.click(b, "RightButton"); Stub.mouseUp(b)
    assert(b.icon.alpha == 1, "after a hold too")
    -- none left: stays grey after a press too
    Stub.removeBagItem(5513); Stub.fire("BAG_UPDATE_DELAYED")
    Stub.mouseDown(b); Stub.mouseUp(b)
    assert(b.icon.alpha == 0.6 and b.icon.desaturated == true and b.count:GetText() == "0")
end)

-- ---------------------------------------------------------------------------------------
-- Cooldown, glow, hidden values

T("cooldown_goes_straight_to_the_sweep", function()
    setupWith({ { id = 102, cat = "health", req = 5, count = 7 } })
    Stub.itemCooldowns[102] = { 100, 30 }; Stub.fire("BAG_UPDATE_COOLDOWN")
    local cd = ItemRail.buttons[3].cooldown
    assert(cd.cooldownStart == 100 and cd.cooldownDuration == 30)
end)
-- SetCooldown refuses a hidden value from add-on code (SecretArguments = AllowedWhenUntainted): it is skipped.
T("hidden_cooldown_numbers_are_skipped", function()
    setupWith({ { id = 102, cat = "health", req = 5, count = 7 } })
    Stub.secretCooldowns(true); Stub.fire("BAG_UPDATE_COOLDOWN"); Stub.fire("BAG_UPDATE_DELAYED")
    assert(not ns.paused, ns.lastError)
    assert(not Stub.isSecret(ItemRail.buttons[3].cooldown.cooldownStart), "never handed to SetCooldown")
end)

-- R43: the game evaluates the step curves (0..1 input): food and drink at 50 %, the healing and mana potions at 25 %.
T("glow_thresholds_are_fractions_the_game_evaluates", function()
    setupWith({ { id = 101, cat = "food", req = 1, count = 3 }, { id = 102, cat = "health", req = 5, count = 7 } })
    local food, potion = ItemRail.buttons[1], ItemRail.buttons[3]
    Stub.setUnit("player", { health = 730, healthMax = 1460, power = 100, powerMax = 100 }); Stub.fire("UNIT_HEALTH", "player")
    assert(food.healthGlow:GetAlpha() == 0, "exactly half: not under 50 %")
    Stub.setUnit("player", { health = 700 }); Stub.fire("UNIT_HEALTH", "player")
    assert(food.healthGlow:GetAlpha() == 1, "under half")
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    Stub.setUnit("player", { health = 400 }); Stub.fire("UNIT_HEALTH", "player")
    assert(potion.healthGlow:GetAlpha() == 0, "27 %: not under 25 %")
    Stub.setUnit("player", { health = 300 }); Stub.fire("UNIT_HEALTH", "player")
    assert(potion.healthGlow:GetAlpha() == 1, "20 %")
    assert(not ns.paused, ns.lastError)
end)
T("food_and_drink_glow_after_a_fight_when_low", function()
    setupFull()
    Stub.setUnit("player", { health = 400, healthMax = 1460, power = 90, powerMax = 100 })
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(ItemRail.buttons[1].healthGlow.alpha == 0, "no glow in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    for i = 1, 2 do
        assert(ItemRail.buttons[i].healthGlow.alpha == 1 and ItemRail.buttons[i].manaGlow.alpha == 0, "health low only")
    end
    assert(ItemRail.buttons[4].manaGlow.alpha == 0 and ItemRail.buttons[3].healthGlow.alpha == 0, "gem and potion rings are for a fight")
    Stub.setUnit("player", { health = 1400, power = 20 }); Stub.fire("UNIT_HEALTH", "player")
    assert(ItemRail.buttons[2].healthGlow.alpha == 0 and ItemRail.buttons[2].manaGlow.alpha == 1, "mana low only")
    Stub.setUnit("player", { power = 50 }); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(ItemRail.buttons[2].manaGlow.alpha == 0, "50% is not under 50%")
end)
T("in_a_fight_the_potion_glows_at_low_health_only", function()
    setupFull()
    Stub.setUnit("player", { health = 200, healthMax = 1460, power = 90, powerMax = 100 })   -- 13%
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(ItemRail.buttons[3].healthGlow.alpha == 1, "potion ring (mockup 19)")
    assert(ItemRail.buttons[4].manaGlow.alpha == 0, "mana is fine")
    for i = 1, 2 do
        assert(ItemRail.buttons[i].healthGlow.alpha == 0 and ItemRail.buttons[i].manaGlow.alpha == 0, "food and drink wait for the fight to end")
    end
    Stub.setUnit("player", { health = 400 }); Stub.fire("UNIT_HEALTH", "player")        -- 27%: under 50 but not under 25
    assert(ItemRail.buttons[3].healthGlow.alpha == 0, "25% is the line in a fight")
    Stub.setUnit("player", { health = 365 }); Stub.fire("UNIT_HEALTH", "player")        -- 25.0%
    assert(ItemRail.buttons[3].healthGlow.alpha == 0, "25% is not under 25%")
    Stub.setUnit("player", { health = 360 }); Stub.fire("UNIT_HEALTH", "player")
    assert(ItemRail.buttons[3].healthGlow.alpha == 1)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[3].healthGlow.alpha == 0 and ItemRail.buttons[1].healthGlow.alpha == 1, "after the fight: food and drink instead")
end)
T("in_a_fight_the_mana_gem_glows_at_low_mana_only", function()
    setupFull()
    Stub.setUnit("player", { health = 1400, healthMax = 1460, power = 7, powerMax = 100 })
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(ItemRail.buttons[4].manaGlow.alpha == 1, "mana gem ring (mockup 75)")
    assert(ItemRail.buttons[3].healthGlow.alpha == 0)
    for i = 1, 2 do
        assert(ItemRail.buttons[i].manaGlow.alpha == 0 and ItemRail.buttons[i].healthGlow.alpha == 0, "not food or drink")
    end
    Stub.setUnit("player", { power = 40 }); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(ItemRail.buttons[4].manaGlow.alpha == 0)
    Stub.combat(false); Stub.setUnit("player", { power = 7 }); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[4].manaGlow.alpha == 0 and ItemRail.buttons[2].manaGlow.alpha == 1)
end)
T("rage_users_have_no_mana_gem_ring", function()
    setup()
    Stub.setUnit("player", { health = 1400, powerType = 1, powerToken = "RAGE", power = 0, powerMax = 100 })
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(ItemRail.buttons[4].manaGlow.alpha == 0)
end)
T("hidden_values_go_into_the_curves_in_a_fight_too", function()
    setupFull(); Stub.secretUnits(true); Stub.combat(true)
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.fire("UNIT_HEALTH", "player"); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(not ns.paused, ns.lastError)
    assert(Stub.isSecret(ItemRail.buttons[3].healthGlow.alpha) and Stub.isSecret(ItemRail.buttons[4].manaGlow.alpha))
end)
T("rage_users_have_no_mana_glow", function()
    setup()
    Stub.setUnit("player", { health = 1400, powerType = 1, powerToken = "RAGE", power = 0, powerMax = 100 })
    Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[2].manaGlow.alpha == 0)
end)
T("no_glow_when_dead", function()
    setup()
    Stub.setUnit("player", { health = 0, dead = true }); Stub.fire("PLAYER_DEAD")
    assert(ItemRail.buttons[1].healthGlow.alpha == 0)
end)
T("hidden_health_and_power_go_into_the_curve_only", function()
    setupFull(); Stub.secretUnits(true)
    Stub.fire("PLAYER_REGEN_ENABLED"); Stub.fire("UNIT_HEALTH", "player"); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(not ns.paused, ns.lastError)
    assert(Stub.isSecret(ItemRail.buttons[1].healthGlow.alpha) and Stub.isSecret(ItemRail.buttons[1].manaGlow.alpha))
    assert(Stub.calls.UnitHealthPercent > 0 and Stub.calls.UnitPowerPercent > 0)
end)
T("hidden_item_ids_are_skipped", function()
    setup()
    Stub.bags[0] = { { itemID = Stub.secret(), count = 3, link = "x", name = "Hidden" } }
    Stub.fire("BAG_UPDATE_DELAYED")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Contract, pause, load order

T("areas_item1_to_item4_register_with_tap_and_hold", function()
    setup()
    local string = TouchPlayDB.contract:match("areas=(.*)$")   -- past the outline= field, which names the items too
    for i = 1, 4 do
        local area = string:match("item" .. i .. ",[^|]*")
        assert(area, "item" .. i .. " is in the contract")
        local name, anchor, dx, dy, w, h, tap, hold = area:match("^(%w+),(%u+),(%-?%d+),(%-?%d+),(%d+),(%d+),([^,]*),([^,]*)")
        assert(anchor == "TR" and tonumber(w) == 48 and tonumber(h) == 48, area)
        assert(tonumber(dx) == 1366 - (1300 + 48) and tonumber(dy) == 300 + 66 * (i - 1), area)
        assert(tap ~= "" and hold ~= "", "tap and hold keys: " .. area)
    end
end)
T("item_column_loads_before_the_contract", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do
        line = line:gsub("\r", ""); if line:match("%.lua$") then order[#order + 1] = line end
    end
    local rail, contract, card
    for i, f in ipairs(order) do
        if f == "ItemRail.lua" then rail = i elseif f == "Contract.lua" then contract = i elseif f == "InfoCard.lua" then card = i end
    end
    assert(rail and contract and card and card < rail and rail < contract)
end)
T("the_column_stays_through_a_reload", function()
    setupWith({ { id = 5513, cat = "gem", req = 0, count = 1 } })
    ItemRail.Pin(4, 5513)
    Stub.reload(); Stub.fire("PLAYER_LOGIN")
    assert(ns.char.pins.mana == 5513 and ns.ItemRail.buttons[4]:GetAttribute("item") == "item:5513")
end)

-- I5: large buttons would take the column into the minimap: the four sit in a row over the page boxes instead.
T("large_buttons_put_the_items_in_a_row_over_the_page_boxes", function()
    setup()
    ns.Feel.Set("buttonSize", 1.4); Stub.advance(1)
    local page4 = ns.Cluster.pageBoxes[4].touchAnchor
    local last = ItemRail.buttons[4].touchAnchor
    for i = 2, 4 do
        local a, b = ItemRail.buttons[i - 1].touchAnchor, ItemRail.buttons[i].touchAnchor
        assert(a.y == b.y and b.x > a.x + a.w, "a row, left to right")
    end
    assert(math.abs((last.x + last.w) - (page4.x + page4.w)) < 0.01, "right-aligned with the page boxes")
    assert(last.y + last.h < page4.y and ItemRail.buttons[1].touchAnchor.y > 220, "between the minimap and the page boxes")
    local contract = ns.Contract.Write()
    assert(contract:find("item1,TR,", 1, true), "the contract still counts them from the top-right corner")
    ns.Feel.Set("buttonSize", 1.0); Stub.advance(1)
    assert(ItemRail.buttons[1].touchAnchor.x == 1300 and ItemRail.buttons[2].touchAnchor.y == 366, "a column again")
end)

-- An empty slot has nothing to use: it never glows.
T("an_empty_slot_never_glows", function()
    setupWith({ { id = 102, cat = "health", req = 5, count = 7 } })
    Stub.setUnit("player", { health = 100, healthMax = 1460, power = 5, powerMax = 100 })
    Stub.fire("UNIT_HEALTH", "player")
    assert(ItemRail.buttons[1].itemID == nil and ItemRail.buttons[1].healthGlow:GetAlpha() == 0, "food: empty")
    assert(ItemRail.buttons[2].manaGlow:GetAlpha() == 0, "drink: empty")
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true); Stub.fire("UNIT_HEALTH", "player")
    assert(ItemRail.buttons[3].healthGlow:GetAlpha() == 1, "the healing potion is there and glows")
    assert(ItemRail.buttons[4].manaGlow:GetAlpha() == 0, "no mana potion: no glow")
end)

-- ---------------------------------------------------------------------------------------
-- iPad run 4: what fills the column, and how the player fills it by hand

T("healing_and_mana_potions_fill_their_own_slots_and_other_potions_are_ignored", function()
    setupWith({
        { id = 10, cat = "health", req = 1, count = 2 }, { id = 11, cat = "health", req = 12, count = 1 },
        { id = 12, cat = "mana", req = 5, count = 3 }, { id = 13, cat = "other", req = 1, count = 9 },
    })
    assert(ItemRail.buttons[3]:GetAttribute("item") == "item:11", "the best healing potion")
    assert(ItemRail.buttons[4]:GetAttribute("item") == "item:12", "the mana potion")
    for i = 1, 4 do assert(ItemRail.buttons[i]:GetAttribute("item") ~= "item:13", "a resistance potion is not ours") end
    assert(ItemRail.buttons[1].empty:IsShown() and ItemRail.buttons[2].empty:IsShown())
end)
T("food_and_drink_are_told_apart_by_the_use_spell_even_when_it_has_another_name", function()
    setupWith({
        { id = 20, cat = "food", req = 1, count = 2 },                              -- the game's Food spell
        { id = 21, cat = "food", req = 1, count = 4, spell = "Refreshment" },        -- a drink with another spell name
        { id = 22, cat = "food", req = 9, count = 1, spell = "Well Fed Feast" },     -- other food
    })
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:22", "the best food (level 9)")
    assert(ItemRail.buttons[2]:GetAttribute("item") == "item:21", "Refreshment is a drink")
end)
T("an_old_save_keeps_its_pinned_gem_as_the_mana_pin", function()
    setupWith({ { id = 5513, cat = "gem", req = 0, count = 1 } })
    ns.char.pins = { gem = 5513, potion = 118, food = 7 }
    Stub.fire("BAG_UPDATE_DELAYED")
    assert(ns.char.pins.mana == 5513 and ns.char.pins.gem == nil and ns.char.pins.potion == nil and ns.char.pins.food == 7)
end)

local function slotCard(index, mouse)
    Stub.click(ItemRail.buttons[index], mouse or "LeftButton")
    local c = ns.InfoCard
    local lines = {}
    for _, row in ipairs(c.frame.rows) do if row.left:IsShown() and row.left.text then lines[#lines + 1] = row.left.text end end
    return c.Title(), table.concat(lines, " / ")
end

T("a_tap_or_a_hold_on_an_empty_slot_says_plainly_how_to_fill_it", function()
    setup()
    for i, want in ipairs({ "Food slot", "Drink slot", "Healing potion slot", "Mana potion slot" }) do
        for _, mouse in ipairs({ "LeftButton", "RightButton" }) do
            local title, lines = slotCard(i, mouse)
            assert(title == want, tostring(title))
            assert(lines:find("Nothing in your bags for this slot.", 1, true) and lines:find("Change item", 1, true), lines)
            assert(cardLabels() == "Change item|Close", cardLabels())
            ns.InfoCard.Hide()
        end
    end
    local _, lines = slotCard(3)
    assert(lines:find("Carry healing potions", 1, true), lines)
    assert(Stub.lastItemUsed == nil and not ns.paused, ns.lastError)
end)
T("a_filled_slot_card_offers_change_item_and_pin", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    slotCard(2, "RightButton")
    assert(cardLabels() == "Use|Link|Change item|Pin", cardLabels())
    assert(Stub.lastItemUsed == nil, "a hold never uses it")
    assert(press("Pin")); assert(ns.char.pins.drink == 101)
    slotCard(2, "RightButton"); assert(cardLabels() == "Use|Link|Change item|Unpin", cardLabels())
    assert(press("Unpin")); assert(ns.char.pins.drink == nil)
end)
T("the_card_still_has_a_title_when_the_game_gives_no_tooltip_lines", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    Stub.tooltipOverride = 0
    local title = slotCard(2, "RightButton")
    Stub.tooltipOverride = nil
    assert(title == "Item 101", "the item's own name, not Nothing here: " .. tostring(title))
end)
T("change_item_opens_the_pickers_items_tab_for_that_slot_and_pin_to_slot_pins_there", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 }, { id = 102, cat = "health", req = 5, count = 3 },
        { id = 900, cat = "armor", req = 1, count = 1 } })
    Stub.itemSpells[900] = true                        -- a bandage-like item with a use of its own
    local Picker = ns.Picker
    slotCard(1)                                       -- the food slot is empty
    assert(press("Change item"))
    assert(Picker.sheet:IsShown() and Picker.tab == "Items" and Picker.rail == 1)
    assert(not Picker.tabs:IsShown(), "no school tabs for a slot of the column")
    assert(Picker.title.label:GetText() == "Choose an item for this slot" and Picker.putButton.label:GetText() == "Pin to slot")
    assert(Picker.ring:IsShown(), "the slot being filled is ringed")
    local names = {}
    for _, cell in ipairs(Picker.cells) do if cell:IsShown() then names[#names + 1] = cell.entry.id end end
    assert(#names == 3, "every item with a use: " .. #names)
    assert(not Picker.putButton:IsEnabled(), "nothing chosen yet")
    for _, cell in ipairs(Picker.cells) do if cell:IsShown() and cell.entry.id == 900 then Stub.click(cell) end end
    assert(Picker.putButton:IsEnabled())
    Stub.click(Picker.putButton)
    assert(not Picker.sheet:IsShown() and Picker.rail == nil)
    assert(ns.char.pins.food == 900 and ItemRail.buttons[1]:GetAttribute("item") == "item:900", "pinned to the food slot")
    assert(ItemRail.buttons[1].pin:IsShown())
    -- the next time the sheet opens for a spell button it is the spell sheet again
    Picker.Open(5)
    assert(Picker.tabs:IsShown() and Picker.putButton.label:GetText() == "Put on button" and Picker.rail == nil)
end)
T("the_slots_own_kind_comes_first_in_the_picker_and_pinned_items_have_the_green_dot", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 }, { id = 102, cat = "health", req = 5, count = 3 },
        { id = 103, cat = "health", req = 9, count = 1 } })
    ItemRail.Pin(3, 103)
    ns.Picker.OpenItem(3)
    local first, second = ns.Picker.cells[1].entry, ns.Picker.cells[2].entry
    assert(first.id == 102 and second.id == 103, "healing potions first")
    assert(not first.onButton and second.onButton, "103 is pinned in the column")
    assert(ns.Picker.cells[3].entry.id == 101)
    Stub.click(ns.Picker.cancelButton); assert(not ns.Picker.sheet:IsShown())
end)
T("pinning_from_the_picker_works_in_a_fight_and_lands_after_it", function()
    setupWith({ { id = 102, cat = "health", req = 5, count = 3 }, { id = 103, cat = "health", req = 9, count = 1 } })
    ns.Picker.OpenItem(3)
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    for _, cell in ipairs(ns.Picker.cells) do if cell:IsShown() and cell.entry.id == 102 then Stub.click(cell) end end
    assert(ns.Picker.putButton:IsEnabled(), "a pin is only a saved choice")
    Stub.click(ns.Picker.putButton)
    assert(ns.char.pins.health == 102 and ItemRail.buttons[3]:GetAttribute("item") == "item:103", "the button waits for the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[3]:GetAttribute("item") == "item:102" and not ns.paused, ns.lastError)
end)
T("an_empty_slot_shows_a_plus_and_a_filled_one_does_not", function()
    setupWith({ { id = 101, cat = "drink", req = 5, count = 20 } })
    assert(ItemRail.buttons[1].plus:IsShown() and not ItemRail.buttons[2].plus:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- iPad run 5: drag an item from the bags onto a slot (ruling A33: while a window is open a drag is a real mouse drag,
-- the bags pick the item up and letting go on the slot is its OnReceiveDrag)

local function drop(index, id)
    Stub.cursor = { kind = "item", id = id }
    ItemRail.buttons[index]:_Fire("OnReceiveDrag")
end

T("drop_a_food_on_a_slot_pins_it_there_clears_the_cursor_and_flashes", function()
    setupWith({ { id = 4599, cat = "food", req = 1, count = 3 }, { id = 4600, cat = "food", req = 1, count = 1 } })
    local before = ItemRail.buttons[1]:GetAttribute("item")
    drop(1, 4600)
    assert(ns.char.pins.food == 4600 and Stub.cursorEmpty(), "pinned, cursor empty")
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:4600" and before ~= "item:4600")
    assert(ns.Picker.flash:IsShown(), "the slot flashes")
    assert(not ItemRail.note:IsShown())
    assert(not ns.paused, ns.lastError)
end)

T("drop_any_usable_item_on_any_slot", function()
    setupWith({ { id = 118, cat = "health", req = 1, count = 2 }, { id = 7000, cat = "other", req = 1, count = 1 } })
    drop(2, 7000)                                         -- a resistance potion on the drink slot
    assert(ns.char.pins.drink == 7000 and Stub.cursorEmpty())
    drop(3, 118)
    assert(ns.char.pins.health == 118)
end)

T("drop_in_a_fight_pins_and_the_slot_follows_after_it", function()
    setupWith({ { id = 4599, cat = "food", req = 1, count = 3 }, { id = 4600, cat = "food", req = 1, count = 1 } })
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    drop(1, 4600)
    assert(ns.char.pins.food == 4600 and Stub.cursorEmpty())
    assert(ItemRail.buttons[1]:GetAttribute("item") ~= "item:4600", "nothing secure changes in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:4600")
end)

T("drop_armour_shakes_and_says_why", function()
    setupWith({ { id = 4599, cat = "food", req = 1, count = 3 } })
    Stub.bags[1] = { [1] = { name = "Cloth Gloves", itemID = 2000, icon = "gloves" } }   -- no use: not for the column
    local pinsBefore = ns.char.pins.food
    drop(1, 2000)
    assert(ns.char.pins.food == pinsBefore, "not pinned")
    assert(Stub.cursorEmpty(), "the item goes back to its bag place")
    assert(ItemRail.note:IsShown() and ItemRail.note:GetText() == ns.T("items.dropNo"), "a short line says why")
    assert(ItemRail.buttons[1].icon.shake ~= nil, "the slot shakes")
    Stub.advance(3)
    assert(not ItemRail.note:IsShown(), "the line goes by itself")
    -- Reduce motion: no shake, the line still says why
    ns.Feel.Set("reduceMotion", true)
    ItemRail.buttons[2].icon.shake = nil
    drop(2, 2000)
    assert(ItemRail.buttons[2].icon.shake == nil and ItemRail.note:IsShown())
    assert(not ns.paused, ns.lastError)
end)

T("drop_of_something_else_is_left_alone", function()
    setup()
    Stub.cursor = { kind = "spell", id = 116 }
    ItemRail.buttons[1]:_Fire("OnReceiveDrag")
    assert(not Stub.cursorEmpty() and not ItemRail.note:IsShown(), "a spell on the cursor: not ours")
    Stub.cursor = nil
    assert(ItemRail.buttons[1].scripts.OnReceiveDrag == nil, "hooked, never set: the secure button keeps its own")
end)

-- iPad run 7: dragging from the bags onto a slot did nothing. The slots take drags as a drop target the way the game's
-- own slots do (RegisterForDrag), and a tap with an item still on the cursor (a drag let go somewhere else leaves it
-- there; the game's own slots place it on a click too) drops it: pinned, and the secure click uses nothing then.
-- /touch keys logs each drop on our slots, so the iPad can prove which path ran.
T("slots_take_drags", function()
    setup()
    for _, b in ipairs(ItemRail.buttons) do
        assert(b.dragButtons and b.dragButtons[1] == "LeftButton", b:GetName() .. " is registered for drag")
    end
end)

T("a_tap_with_an_item_on_the_cursor_pins_it_and_uses_nothing", function()
    setupWith({ { id = 4599, cat = "food", req = 1, count = 3 }, { id = 4600, cat = "food", req = 1, count = 1 } })
    Stub.lastItemUsed = nil
    Stub.cursor = { kind = "item", id = 4600 }
    Stub.click(ItemRail.buttons[1], "LeftButton")
    assert(ns.char.pins.food == 4600 and Stub.cursorEmpty(), "pinned, cursor empty")
    assert(Stub.lastItemUsed == nil, "the click used nothing: " .. tostring(Stub.lastItemUsed))
    assert(not ns.InfoCard.IsShown(), "no card")
    assert(ItemRail.buttons[1]:GetAttribute("item") == "item:4600", "the slot's item follows")
    Stub.click(ItemRail.buttons[1], "LeftButton")
    assert(Stub.lastItemUsed == "item:4600", "the next tap uses it: " .. tostring(Stub.lastItemUsed))
    -- an empty slot with an item on the cursor: pinned there, no "empty slot" card
    Stub.cursor = { kind = "item", id = 4599 }
    Stub.click(ItemRail.buttons[3], "LeftButton")
    assert(ns.char.pins.health == 4599 and not ns.InfoCard.IsShown() and Stub.cursorEmpty())
    assert(not ns.paused, ns.lastError)
end)

T("the_key_log_shows_each_drop_on_a_slot", function()
    setupWith({ { id = 4599, cat = "food", req = 1, count = 3 }, { id = 4600, cat = "food", req = 1, count = 1 } })
    SlashCmdList.TOUCHPLAY("keys on")
    ItemRail.buttons[2]:_Fire("OnReceiveDrag")                    -- nothing on the cursor: still logged
    drop(1, 4600)
    Stub.cursor = { kind = "item", id = 4599 }
    Stub.click(ItemRail.buttons[1], "LeftButton")
    local text = table.concat(TouchPlayDB.keylog, "\n")
    assert(text:find("DROP | TouchPlayItem2 | OnReceiveDrag | cursor=- | none", 1, true), text)
    assert(text:find("DROP | TouchPlayItem1 | OnReceiveDrag | cursor=item:4600 | pinned", 1, true), text)
    assert(text:find("DROP | TouchPlayItem1 | click | cursor=item:4599 | pinned", 1, true), text)
    SlashCmdList.TOUCHPLAY("keys off")
    drop(1, 4600)
    assert(select(2, table.concat(TouchPlayDB.keylog, "\n"):gsub("DROP", "")) == 3, "off: no more lines")
end)

Stub.done("itemrail")
