-- Task 6: info cards (rule 4): hold anything for its card; mockups 03, 11, 71, 92.
dofile("tests/stub.lua")

local picked = {}

-- A game session with the add-on loaded and laid out. The picker (Task 7) is faked.
local function setup(noPicker)
    -- every file the .toc lists except the item column (Task 8): its Pin and Unpin card buttons
    -- have their own tests, and this one is about the card's own buttons
    Stub.reset()
    local files = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and line ~= "ItemRail.lua" then files[#files + 1] = line end
    end
    Stub.load(unpack(files)); Stub.login()
    InfoCard = ns.InfoCard
    picked = {}
    if noPicker then
        ns.Picker = nil                 -- the real picker (Task 7) loads too; this test is about its absence
    else
        ns.Picker = { Open = function(slot) picked.open = slot end, Remove = function(slot) picked.remove = slot end }
    end
    Stub.actions[3] = 116
    Stub.spellNames[116] = "Frostbolt"
    return InfoCard
end

local function labels()
    local out = {}
    for i = 1, InfoCard.frame.buttonCount do out[i] = InfoCard.frame.buttons[i].label:GetText() end
    return table.concat(out, "|")
end

T("place_right_then_flips_left", function()
    setup()
    local x, _, side = InfoCard.Place(420, 290, 300, 600, 64, 64, 1366); assert(side == "right" and x == 300 + 64 + 12)
    x, _, side = InfoCard.Place(420, 290, 1236, 640, 64, 64, 1366); assert(side == "left" and x == 1236 - 12 - 420)
end)
T("place_clamped_vertically", function()
    setup()
    local _, y = InfoCard.Place(420, 290, 300, 1000, 64, 20, 1366); assert(y + 290 <= 1024 - 8)
    _, y = InfoCard.Place(420, 290, 300, 0, 64, 20, 1366); assert(y >= 8)
end)
T("place_never_over_the_anchor_even_when_cramped", function()
    setup()
    -- 500 wide screen, card 420: neither side fits; it still stays inside the screen
    local x = InfoCard.Place(420, 290, 200, 300, 100, 64, 500); assert(x >= 8 and x + 420 <= 500 - 8)
end)

T("rule4_hold_opens_card_not_cast", function()
    setup(); Stub.click("TouchPlaySpell3", "RightButton")
    assert(InfoCard.frame:IsShown() and Stub.calls.UseAction == 0)
    assert(InfoCard.Title() == "Frostbolt")
end)
T("hold_card_buttons_for_a_spell", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 }); assert(labels() == "Change spell|Remove|Close")
    InfoCard.Button("Change spell"):_Fire("OnClick", "LeftButton")
    assert(picked.open == 3 and not InfoCard.IsShown(), "change opens the picker and closes the card")
    InfoCard.Show({ kind = "action", slot = 3 }); InfoCard.Button("Remove"):_Fire("OnClick", "LeftButton")
    assert(picked.remove == 3)
    InfoCard.Show({ kind = "action", slot = 3 }); InfoCard.Button("Close"):_Fire("OnClick", "LeftButton")
    assert(not InfoCard.IsShown())
end)
T("empty_button_offers_change_only", function()
    setup(); InfoCard.Show({ kind = "action", slot = 5 })
    assert(InfoCard.Title() == ns.L["card.emptyButton"] and labels() == "Change spell|Close")
end)
T("without_a_picker_change_and_remove_are_hidden", function()
    setup(true); InfoCard.Show({ kind = "action", slot = 3 }); assert(labels() == "Close")
end)
T("rule4_change_disabled_in_fight", function()
    setup(); Stub.combat(true); InfoCard.Show({ kind = "action", slot = 3 })
    assert(not InfoCard.Button("Change spell"):IsEnabled() and InfoCard.ReasonText() == ns.L["card.afterFight"])
    assert(not InfoCard.Button("Remove"):IsEnabled() and InfoCard.Button("Close"):IsEnabled())
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(InfoCard.Button("Change spell"):IsEnabled() and InfoCard.ReasonText() == nil, "the fight ending frees it")
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(not InfoCard.Button("Change spell"):IsEnabled(), "a fight starting greys it")
end)
T("hold_from_the_spell_button_places_beside_it_never_over_it", function()
    setup()
    for i = 1, 7 do
        Stub.click("TouchPlaySpell" .. i, "RightButton")
        local card, b = InfoCard.frame, Stub.frames["TouchPlaySpell" .. i]
        local bx, bby, bw, bh = b:GetRect()
        local p = card.points[#card.points]
        local cx, cy = p[4], -p[5]            -- card top-left, layout units from the screen's top-left
        local cw, ch = card:GetSize()
        local by = 1024 - (bby + bh)
        local apart = cx + cw <= bx or cx >= bx + bw or cy + ch <= by or cy >= by + bh
        assert(apart, "card over spell button " .. i)
        assert(cx >= 8 and cx + cw <= 1366 - 8 and cy >= 8 and cy + ch <= 1024 - 8, "inside the screen")
        assert(card.side == (cx > bx and "right" or "left"))
    end
end)

T("world_hold_reads_mouseover", function()
    setup(); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    assert(InfoCard.Title() == "Starving Mountain Lion")
    assert(labels() == "Target|Close", "an enemy card: Target and Close")
end)
T("world_hold_one_card_for_a_down_and_an_up", function()
    setup(); Stub.setMouseover("Starving Mountain Lion")
    local shown = 0
    local old = InfoCard.Show
    InfoCard.Show = function(...) shown = shown + 1; return old(...) end
    TouchPlayWorldHold:_Fire("PostClick", "LeftButton", true)
    TouchPlayWorldHold:_Fire("PostClick", "LeftButton", false)
    InfoCard.Show = old
    assert(shown == 1, "only the release opens the card, got " .. shown)
end)
T("world_hold_copies_the_game_tooltip_when_no_unit", function()
    setup(); Stub.setMouseover(nil); Stub.setGameTooltip({ "Briarthorn", { left = "Herbalism", right = "Skill 70" } })
    Stub.click("TouchPlayWorldHold")
    assert(InfoCard.Title() == "Briarthorn" and labels() == "Close")
end)
T("world_hold_with_nothing_says_so", function()
    setup(); Stub.setMouseover(nil); Stub.setGameTooltip(nil); Stub.click("TouchPlayWorldHold")
    assert(InfoCard.Title() == ns.L["card.nothingHere"] and labels() == "Close")
end)
T("world_key_does_not_act", function()
    setup(); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    assert(Stub.calls.TargetUnit == 0 and Stub.calls.UseAction == 0)
    assert(TouchPlayWorldHold:GetAttribute("type") == nil)
end)

T("long_text_scrolls", function()
    setup(); Stub.tooltipLines(30); InfoCard.Show({ kind = "item", link = "x" }); assert(InfoCard.scroll:IsShown())
    assert(InfoCard.frame:GetHeight() < 330 + 160, "the card stops growing at 330 units of text")
end)
T("short_text_does_not_scroll", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 }); assert(not InfoCard.scroll:IsShown())
end)

T("broken_hook_skipped", function()
    setup(); TouchPlay.AddCardLine("item", function() error("x") end); InfoCard.Show({ kind = "item", link = "x" }); assert(not ns.paused)
    assert(#ns.db.errors == 1 and ns.db.errors[1].text:find("card line hook"), "remembered")
end)
T("hook_line_and_action_show_up", function()
    setup()
    TouchPlay.AddCardLine("item", function() return "Vendor price: 5g" end)
    TouchPlay.AddCardLine("item", function() return { text = "Rare find", r = 0, g = 0.5, b = 1 } end)
    local ran
    TouchPlay.AddCardAction("item", "Mine", function(subject) ran = subject.link end)
    InfoCard.Show({ kind = "item", link = "x" })
    assert(labels() == "Link|Close|Mine")
    local rows = InfoCard.frame.rows
    assert(rows[1].left.text == "Vendor price: 5g" and rows[2].left.text == "Rare find")
    InfoCard.Button("Mine"):_Fire("OnClick", "LeftButton"); assert(ran == "x" and not ns.paused)
end)
T("broken_action_hook_is_skipped_and_logged", function()
    setup(); TouchPlay.AddCardAction("item", "Bad", function() error("boom") end)
    InfoCard.Show({ kind = "item", link = "x" })
    InfoCard.Button("Bad"):_Fire("OnClick", "LeftButton")
    assert(not ns.paused and ns.db.errors[1].text:find("card action Bad"))
end)
T("action_hook_isShown_decides_whether_the_button_appears", function()
    setup()
    local seen
    TouchPlay.AddCardAction("item", "Always", function() end)
    TouchPlay.AddCardAction("item", "Yes", function() end, function(subject, model) seen = { subject, model }; return true end)
    TouchPlay.AddCardAction("item", "No", function() end, function() return false end)
    TouchPlay.AddCardAction("item", "Truthy", function() end, function() return "yes" end)
    TouchPlay.AddCardAction("item", "Nothing", function() end, function() end)
    local subject = { kind = "item", link = "x" }
    InfoCard.Show(subject)
    assert(labels() == "Link|Close|Always|Yes", labels())
    assert(seen[1] == subject and type(seen[2]) == "table" and seen[2].buttons, "it gets the subject and the card model")
    assert(not ns.paused and not ns.db.errors, "a hidden button is not an error")
end)
T("a_failing_isShown_hides_the_button_and_never_pauses", function()
    setup()
    TouchPlay.AddCardAction("item", "Broken", function() end, function() error("boom") end)
    TouchPlay.AddCardAction("item", "After", function() end)
    InfoCard.Show({ kind = "item", link = "x" })
    assert(labels() == "Link|Close|After", labels())
    assert(not ns.paused and ns.db.errors[1].text:find("card action visibility Broken"), "remembered")
end)
T("a_hidden_hook_does_not_use_up_a_button_place", function()
    setup()
    TouchPlay.AddCardAction("item", "H1", function() end, function() return false end)
    TouchPlay.AddCardAction("item", "H2", function() end, function() return false end)
    TouchPlay.AddCardAction("item", "S1", function() end, function() return true end)
    TouchPlay.AddCardAction("item", "S2", function() end, function() return true end)
    InfoCard.Show({ kind = "item", link = "x" })
    assert(labels() == "Link|Close|S1|S2", labels())
end)
T("a_hook_with_a_bad_isShown_is_ignored", function()
    setup(); TouchPlay.AddCardAction("item", "Bad", function() end, "nope")
    InfoCard.Show({ kind = "item", link = "x" }); assert(not InfoCard.Button("Bad"))
end)
T("hooks_only_for_their_kind", function()
    setup(); TouchPlay.AddCardAction("unit", "Mine", function() end)
    InfoCard.Show({ kind = "action", slot = 3 }); assert(not InfoCard.Button("Mine"))
end)

-- items
local function bagItem(opts)
    Stub.bags[0] = { [1] = opts }
end

T("item_card_potion_buttons", function()
    setup(); bagItem({ name = "Healing Potion", count = 7, quality = 1 }); ns.Bags = { Split = function() end }
    InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(InfoCard.Title() == "Healing Potion" and labels() == "Use|Link")
    -- Use is the game's own secure "item" action on a button laid over the card's: our code never calls it (R37)
    local secure = InfoCard.secureButton
    assert(secure:IsVisible() and secure:GetAttribute("type") == "item" and secure:GetAttribute("item") == "0 1")
    assert(secure:GetAttribute("unit") == nil and secure:GetAttribute("macrotext") == nil)
    Stub.tap(InfoCard.Button("Use"))
    assert(Stub.lastItemUsed == "0 1", tostring(Stub.lastItemUsed))
    assert(Stub.lastUsedItem == nil and Stub.calls.UseContainerItem == 0, "UseContainerItem is never called from our code")
    assert(not InfoCard.IsShown(), "the card closes after the use")
end)
T("item_card_gear_equips", function()
    setup(); bagItem({ name = "Hillborne Cloak", count = 1, quality = 2 }); Stub.equippable["Hillborne Cloak"] = true
    InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(labels() == "Equip|Link")
    InfoCard.Button("Equip"):_Fire("OnClick", "LeftButton"); assert(Stub.lastEquipped == "Hillborne Cloak")
    assert(InfoCard.frame.iconFrame.backdropBorderColor[2] == 1, "the quality colour frames the picture")
end)
T("item_card_vendor_open_offers_sell", function()
    setup(); bagItem({ name = "Hillborne Cloak", count = 1, quality = 2 }); Stub.equippable["Hillborne Cloak"] = true
    Stub.setMerchant(true); InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(labels() == "Equip|Link|Sell")
    InfoCard.Button("Sell"):_Fire("OnClick", "LeftButton"); assert(Stub.lastUsedItem[2] == 1, "Sell at a merchant stays a direct call")
end)
T("item_card_never_offers_delete", function()
    setup(); ns.Bags = { Split = function() end }
    local cases = {
        { { name = "Healing Potion", count = 7 }, false, false },
        { { name = "Hillborne Cloak", count = 1, quality = 2 }, true, false },
        { { name = "Healing Potion", count = 1 }, false, true },
        { { name = "Hillborne Cloak", count = 1, quality = 3 }, true, true },
    }
    for _, case in ipairs(cases) do
        bagItem(case[1]); Stub.equippable[case[1].name] = case[2]; Stub.setMerchant(case[3])
        InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
        assert(not InfoCard.Button("Delete") and not InfoCard.Button("Split"), labels())
        Stub.combat(true); InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
        assert(not InfoCard.Button("Delete") and not InfoCard.Button("Split"), labels())
        for i = 1, InfoCard.frame.buttonCount do InfoCard.frame.buttons[i]:_Fire("OnClick", "LeftButton") end
        Stub.combat(false)
    end
    assert(Stub.calls.DeleteCursorItem == 0 and Stub.calls.PickupContainerItem == 0)
    InfoCard.Show({ kind = "item", link = "[Sword]" }); assert(not InfoCard.Button("Delete"))
end)
T("item_card_link_goes_to_chat", function()
    setup(); bagItem({ name = "Healing Potion", count = 1 }); InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    InfoCard.Button("Link"):_Fire("OnClick", "LeftButton")
    assert(Stub.lastLinked == "Healing Potion" and Stub.lastChatOpened == "Healing Potion", "opens chat when no box is open")
    Stub.chatLinkOpen = true; Stub.lastChatOpened = nil
    InfoCard.Show({ kind = "item", bag = 0, slot = 1 }); InfoCard.Button("Link"):_Fire("OnClick", "LeftButton")
    assert(Stub.lastChatOpened == nil, "a link goes into an open box")
end)
T("item_card_actions_greyed_in_fight", function()
    setup(); bagItem({ name = "Healing Potion", count = 7 })
    Stub.combat(true); InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(not InfoCard.Button("Use"):IsEnabled())
    assert(InfoCard.Button("Link"):IsEnabled() and InfoCard.ReasonText() == ns.L["card.afterFightDo"])
    assert(not InfoCard.secureButton:IsVisible() and InfoCard.secureButton:GetAttribute("type") == nil,
        "the secure Use cannot be set up in a fight")
    InfoCard.Button("Use"):_Fire("OnClick", "LeftButton")
    assert(Stub.lastUsedItem == nil and Stub.lastItemUsed == nil)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(InfoCard.secureButton:IsVisible() and InfoCard.secureButton:GetAttribute("item") == "0 1", "set up after the fight")
end)
T("item_by_link_only_offers_link_and_close", function()
    setup(); InfoCard.Show({ kind = "item", link = "[Sword]" }); assert(labels() == "Link|Close")
end)

-- units
T("unit_friendly_player", function()
    setup(); Stub.setTarget("player"); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(InfoCard.Title() == "Tarek" and labels() == "Whisper|Invite|More")
    InfoCard.Button("Whisper"):_Fire("OnClick", "LeftButton"); assert(Stub.lastTell == "Tarek")
    InfoCard.Show({ kind = "unit", unit = "target" }); InfoCard.Button("Invite"):_Fire("OnClick", "LeftButton")
    assert(Stub.lastInvite == "Tarek")
end)
T("unit_more_page_and_back", function()
    setup(); Stub.setTarget("player"); InfoCard.Show({ kind = "unit", unit = "target" })
    InfoCard.Button("More"):_Fire("OnClick", "LeftButton")
    assert(InfoCard.IsShown() and labels() == "Inspect|Trade|Follow|Back")
    InfoCard.Button("Back"):_Fire("OnClick", "LeftButton"); assert(labels() == "Whisper|Invite|More")
end)
T("unit_enemy_targets", function()
    setup(); Stub.setTarget("enemy"); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(labels() == "Target|Close")
    local secure = InfoCard.secureButton
    assert(secure:IsVisible() and secure:GetAttribute("type") == "target" and secure:GetAttribute("unit") == "target",
        "the secure target action on the stable token")
    Stub.tap(InfoCard.Button("Target"))
    assert(Stub.lastTargeted == "target" and Stub.calls.TargetUnit == 1, "the secure button targets")
    assert(Stub.lastTargetedUnit == nil, "TargetUnit is never called from our code (R35)")
    assert(not InfoCard.IsShown() and not ns.paused, tostring(ns.lastError))
end)
T("unit_party_member_has_target_not_invite", function()
    setup(); Stub.setTarget("player", { inParty = true }); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(labels() == "Whisper|Target|More")
end)
T("unit_enemy_target_greyed_in_fight", function()
    setup(); Stub.setTarget("enemy"); Stub.combat(true); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(not InfoCard.Button("Target"):IsEnabled() and InfoCard.Button("Close"):IsEnabled())
end)
T("unit_that_is_gone_says_nothing_here", function()
    setup(); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(InfoCard.Title() == ns.L["card.nothingHere"] and labels() == "Close" and not ns.paused)
end)
T("player_card_hold_shows_close_only", function()
    setup(); Stub.click("TouchPlayPlayer", "RightButton")
    assert(InfoCard.IsShown() and InfoCard.Title() == "Keepsy" and labels() == "Close")
end)
T("target_card_hold_asks_for_the_target_card", function()
    setup(); Stub.setTarget("enemy"); Stub.click("TouchPlayTarget", "RightButton")
    assert(InfoCard.IsShown() and InfoCard.Title() == "Starving Mountain Lion")
end)

-- a unit is remembered by name and GUID, not by the token it was held through
local function holdFriendlyAndLoseMouseover()
    setup(); Stub.setMouseover("Tarek", { reaction = 5, isPlayer = true, canAttack = false, canAttackUs = false })
    Stub.click("TouchPlayWorldHold")
    assert(InfoCard.Title() == "Tarek" and labels() == "Whisper|Invite|More")
    Stub.setMouseover(nil); Stub.fire("PLAYER_TARGET_CHANGED")      -- the finger is on the card now
end
T("unit_whisper_and_invite_work_after_mouseover_is_gone", function()
    holdFriendlyAndLoseMouseover()
    InfoCard.Button("Whisper"):_Fire("OnClick", "LeftButton"); assert(Stub.lastTell == "Tarek")
    Stub.click("TouchPlayWorldHold"); -- nothing under the finger now: a fresh card
    assert(InfoCard.Title() == ns.L["card.nothingHere"])
end)
T("unit_invite_after_mouseover_is_gone", function()
    holdFriendlyAndLoseMouseover()
    InfoCard.Button("Invite"):_Fire("OnClick", "LeftButton"); assert(Stub.lastInvite == "Tarek")
end)
T("unit_target_by_name_after_mouseover_is_gone", function()
    setup(); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    Stub.setMouseover(nil); Stub.fire("PLAYER_TARGET_CHANGED")
    assert(InfoCard.Button("Target"):IsEnabled())
    local secure = InfoCard.secureButton
    assert(secure:GetAttribute("type") == "macro" and secure:GetAttribute("unit") == nil)
    assert(secure:GetAttribute("macrotext") == "/targetexact Starving Mountain Lion", "name only: the exact-name macro")
    Stub.tap(InfoCard.Button("Target"))
    assert(Stub.lastMacro == "/targetexact Starving Mountain Lion" and Stub.lastTargetedUnit == nil)
end)
T("unit_target_never_bakes_in_the_mouseover_token", function()
    setup(); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    assert(InfoCard.Title() == "Starving Mountain Lion")
    local secure = InfoCard.secureButton
    -- mouseover still matches while the card draws, but nothing refreshes it when the pointer moves onto the card
    assert(secure:GetAttribute("unit") ~= "mouseover", "mouseover is not kept fresh by any event")
    assert(secure:GetAttribute("type") == "macro" and secure:GetAttribute("macrotext") == "/targetexact Starving Mountain Lion")
    Stub.setMouseover(nil)                    -- the finger is on the card: no mouseover any more, and no event
    Stub.tap(InfoCard.Button("Target"))
    assert(Stub.lastMacro == "/targetexact Starving Mountain Lion" and Stub.lastTargeted == nil,
        "the held creature is targeted by name: " .. tostring(Stub.lastMacro))
end)
T("unit_held_by_mouseover_that_is_also_the_target_uses_the_target_token", function()
    setup(); Stub.setTarget("enemy"); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    local secure = InfoCard.secureButton
    assert(secure:GetAttribute("type") == "target" and secure:GetAttribute("unit") == "target",
        "target is kept fresh by PLAYER_TARGET_CHANGED, so it may be used")
end)
T("unit_target_with_a_hidden_name_and_no_token_is_greyed_with_a_reason", function()
    setup(); Stub.setTarget("enemy")
    local realGuid = UnitGUID
    UnitGUID = function() return Stub.secret() end
    GetUnitName = function() return Stub.secret() end
    InfoCard.Show({ kind = "unit", unit = "target" })
    local secure = InfoCard.secureButton
    assert(not secure:IsVisible(), "nothing to target with: no secure button")
    assert(not InfoCard.Button("Target"):IsEnabled(), "greyed, not a button that just closes the card")
    assert(InfoCard.ReasonText() == ns.L["card.unitGone"], tostring(InfoCard.ReasonText()))
    assert(InfoCard.Button("Close"):IsEnabled() and not ns.paused)
    UnitGUID = realGuid; GetUnitName = nil
end)
T("unit_target_uses_the_token_while_it_is_the_same_unit", function()
    setup(); Stub.setTarget("enemy"); InfoCard.Show({ kind = "unit", unit = "target" })
    Stub.tap(InfoCard.Button("Target")); assert(Stub.lastTargeted == "target" and Stub.lastTargetedUnit == nil)
    Stub.lastTargeted = nil
    Stub.setTarget("enemy"); Stub.setMouseover("Starving Mountain Lion"); Stub.click("TouchPlayWorldHold")
    Stub.setMouseover(nil); Stub.fire("PLAYER_TARGET_CHANGED")
    assert(InfoCard.secureButton:GetAttribute("unit") == "target")
    Stub.tap(InfoCard.Button("Target"))
    assert(Stub.lastTargeted == "target", "the same creature is also the target: the token is safe")
end)
T("unit_target_changed_after_the_hold_acts_on_the_held_unit", function()
    setup(); Stub.setTarget("enemy"); InfoCard.Show({ kind = "unit", unit = "target" })
    Stub.setTarget("elite"); Stub.fire("PLAYER_TARGET_CHANGED")   -- a different creature is the target when the button is tapped
    assert(InfoCard.secureButton:GetAttribute("type") == "macro", "the token no longer vouches for the held creature")
    Stub.tap(InfoCard.Button("Target"))
    assert(Stub.lastMacro == "/targetexact Starving Mountain Lion" and Stub.lastTargeted == nil,
        "acts on the held creature by name, never on the new target: " .. tostring(Stub.lastMacro))
end)
T("unit_second_page_greys_when_no_stable_token", function()
    holdFriendlyAndLoseMouseover()
    InfoCard.Button("More"):_Fire("OnClick", "LeftButton")
    assert(labels() == "Inspect|Trade|Follow|Back")
    assert(not InfoCard.Button("Inspect"):IsEnabled() and InfoCard.ReasonText() == ns.L["card.unitGone"])
    assert(InfoCard.Button("Back"):IsEnabled())
    InfoCard.Button("Inspect"):_Fire("OnClick", "LeftButton"); assert(Stub.lastInspected == nil and InfoCard.IsShown(), "no token: nothing happens, the card stays")
    -- the same person becomes the target: the buttons come back and act on "target"
    Stub.setTarget("player"); assert(InfoCard.Button("Inspect"):IsEnabled() and InfoCard.ReasonText() == nil)
    InfoCard.Button("Inspect"):_Fire("OnClick", "LeftButton"); assert(Stub.lastInspected == "target")
end)
T("unit_actions_missing_from_this_game_are_hidden", function()
    setup(); InspectUnit, InitiateTrade, FollowUnit = nil, nil, nil
    Stub.setTarget("player"); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(labels() == "Whisper|Invite", "no More when it would be empty")
    InspectUnit = function() end
    InfoCard.Show({ kind = "unit", unit = "target" }); InfoCard.Button("More"):_Fire("OnClick", "LeftButton")
    assert(labels() == "Inspect|Back")
end)
T("page_change_keeps_hook_lines_once", function()
    setup(); TouchPlay.AddCardLine("unit", function() return "Hooked" end)
    Stub.setTarget("player"); InfoCard.Show({ kind = "unit", unit = "target" })
    InfoCard.Button("More"):_Fire("OnClick", "LeftButton"); InfoCard.Button("Back"):_Fire("OnClick", "LeftButton")
    local n = 0
    for _, row in ipairs(InfoCard.frame.rows) do if row.left:IsShown() and row.left.text == "Hooked" then n = n + 1 end end
    assert(n == 1, n)
end)

-- what a hook returns is checked
T("malformed_hook_returns_are_ignored_or_whitened", function()
    setup()
    TouchPlay.AddCardLine("item", function() return { text = "bad colours", r = "bad", g = {}, b = 7 } end)
    TouchPlay.AddCardLine("item", function() return { text = 5 } end)
    TouchPlay.AddCardLine("item", function() return 42 end)
    TouchPlay.AddCardLine("item", function() return { text = "secret colour", r = Stub.secret() } end)
    InfoCard.Show({ kind = "item", link = "x" })
    assert(not ns.paused)
    local rows = InfoCard.frame.rows
    assert(rows[1].left.text == "bad colours" and rows[1].left.textColor[1] == 1 and rows[1].left.textColor[2] == 1
        and rows[1].left.textColor[3] == 1)
    assert(rows[2].left.text == "secret colour" and rows[2].left.textColor[1] == 1 and (rows[3] == nil or not rows[3].left:IsShown()))
end)

T("hidden_guid_means_no_stable_token", function()
    setup(); Stub.setTarget("enemy")
    local real = UnitGUID
    UnitGUID = function() return Stub.secret() end
    InfoCard.Show({ kind = "unit", unit = "target" })
    assert(not ns.paused and InfoCard.Button("Target"):IsEnabled())
    Stub.fire("PLAYER_TARGET_CHANGED")
    Stub.tap(InfoCard.Button("Target"))
    assert(not ns.paused and Stub.lastMacro == "/targetexact Starving Mountain Lion" and Stub.lastTargeted == nil,
        "by name: the hidden GUID cannot vouch for a token")
    Stub.setTarget("player"); InfoCard.Show({ kind = "unit", unit = "target" })
    InfoCard.Button("More"):_Fire("OnClick", "LeftButton")
    assert(not ns.paused and not InfoCard.Button("Inspect"):IsEnabled(), "token actions grey out")
    UnitGUID = real
end)

T("hidden_number_from_a_hook_colour_is_ignored", function()
    setup()
    -- type() answers "number" for a real hidden number, so the stub's hidden value must too
    local realType = type
    type = function(v)
        if realType(v) == "table" then
            local mt = getmetatable(v)
            if mt and mt.__unm then return "number" end     -- the stub's hidden value
        end
        return realType(v)
    end
    local ok, problem = pcall(function()
        TouchPlay.AddCardLine("item", function() return { text = "hidden", r = Stub.secret(), g = 0.5, b = Stub.secret() } end)
        InfoCard.Show({ kind = "item", link = "x" })
    end)
    type = realType
    assert(ok, problem)
    local c = InfoCard.frame.rows[1].left.textColor
    assert(not ns.paused and c[1] == 1 and c[2] == 0.5 and c[3] == 1)
end)

-- a hidden picture is never compared
T("hidden_icon_is_never_compared", function()
    setup(); Stub.combat(true)
    GetActionTexture = function() return Stub.secret() end
    InfoCard.Show({ kind = "action", slot = 3 })
    assert(not ns.paused and InfoCard.frame.iconFrame:IsShown() and Stub.isSecret(InfoCard.frame.iconTexture.texture))
    Stub.auras.player = { [1] = { name = "Frost Armor" } }
    C_UnitAuras.GetAuraDataByIndex = function() return { icon = Stub.secret() } end
    InfoCard.Show({ kind = "aura", unit = "player", index = 1 })
    assert(not ns.paused and Stub.isSecret(InfoCard.frame.iconTexture.texture))
end)

-- auras and quests
T("aura_on_the_player_can_be_cancelled", function()
    setup(); Stub.auras.player = { [2] = { name = "Frost Armor", text = "28 minutes remaining" } }
    InfoCard.Show({ kind = "aura", unit = "player", index = 2 })
    assert(InfoCard.Title() == "Frost Armor" and labels() == "Cancel buff|Close")
    InfoCard.Button("Cancel buff"):_Fire("OnClick", "LeftButton")
    assert(Stub.lastCancelledBuff[1] == "player" and Stub.lastCancelledBuff[2] == 2)
    Stub.combat(true); InfoCard.Show({ kind = "aura", unit = "player", index = 2 })
    assert(not InfoCard.Button("Cancel buff"):IsEnabled())
end)
T("aura_on_the_target_and_debuffs_have_no_cancel", function()
    setup(); Stub.auras.target = { [1] = { name = "Rend" } }; Stub.auras.player = { [1] = { name = "Poison" } }
    InfoCard.Show({ kind = "aura", unit = "target", index = 1 }); assert(labels() == "Close")
    InfoCard.Show({ kind = "aura", unit = "player", index = 1, filter = "HARMFUL" }); assert(labels() == "Close")
end)
T("quest_objective_card", function()
    setup(); Stub.quests[77] = { title = "Elixir of Pain", objectives = { { text = "Mountain Lion Blood: 7/10", finished = false } } }
    InfoCard.Show({ kind = "questObjective", questID = 77 })
    assert(InfoCard.Title() == "Elixir of Pain" and labels() == "Show on map|Untrack|Close")
    assert(InfoCard.frame.rows[1].left.text == "Mountain Lion Blood: 7/10")
    InfoCard.Button("Untrack"):_Fire("OnClick", "LeftButton"); assert(Stub.lastUntracked == 77)
end)

-- I6: Show on map is the card's secure entry: a secure click on the zone text button the Hud's minimap uses (its own
-- ToggleWorldMap), with the quest super-tracked first. OpenQuestLog and ToggleWorldMap are never called from our code.
T("quest_show_on_map_is_a_secure_click_on_the_zone_button", function()
    setup(); Stub.quests[77] = { title = "Elixir of Pain", objectives = {} }
    InfoCard.Show({ kind = "questObjective", questID = 77 })
    local secure = InfoCard.secureButton
    assert(secure:IsShown() and secure:GetAttribute("type") == "click", tostring(secure:GetAttribute("type")))
    assert(secure:GetAttribute("clickbutton") == MinimapCluster.ZoneTextButton and secure.over == InfoCard.Button("Show on map"))
    Stub.tap(InfoCard.Button("Show on map"))
    assert(Stub.lastSuperTracked == 77, "the quest is super-tracked first")
    assert(Stub.calls.ToggleWorldMap == 1, "the zone button opened the map")
    assert(Stub.calls.OpenQuestLog == 0 and Stub.calls.ToggleWorldMapFn == 0, "never from our own code")
    assert(not InfoCard.IsShown() and not ns.paused, tostring(ns.lastError))
    -- in a fight the secure entry cannot be set up: greyed, and a tap does nothing
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    InfoCard.Show({ kind = "questObjective", questID = 77 })
    assert(not InfoCard.Button("Show on map"):IsEnabled() and not secure:IsShown())
    InfoCard.Button("Show on map"):_Fire("OnClick", "LeftButton")
    assert(#Stub.blocked == 0 and Stub.calls.OpenQuestLog == 0 and not ns.paused, tostring(ns.lastError))
end)

-- hidden text in a fight
T("hidden_text_goes_only_to_settext", function()
    setup(); Stub.setTarget("enemy"); Stub.tooltipSecret(true); Stub.combat(true)
    InfoCard.Show({ kind = "unit", unit = "target" })
    assert(not ns.paused and Stub.isSecret(InfoCard.Title()), "the title is the hidden value, untouched")
    assert(Stub.isSecret(InfoCard.frame.rows[1].left.text))
    bagItem({ name = "Healing Potion", count = 7 }); InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    assert(not ns.paused)
    Stub.setMouseover("Starving Mountain Lion"); InfoCard.Show({ kind = "world" }); assert(not ns.paused)
end)

-- the card itself
T("card_hides_with_pause_and_off", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 }); assert(InfoCard.IsShown())
    ns.Pause("test"); assert(not InfoCard.IsShown() and not InfoCard.catcher:IsShown())
end)
T("tap_away_closes_the_card", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 }); assert(InfoCard.catcher:IsShown())
    Stub.click(InfoCard.catcher, "LeftButton"); assert(not InfoCard.IsShown())
end)
T("cards_reuse_their_pieces", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 })
    local rows, buttons = #InfoCard.frame.rows, #InfoCard.frame.buttons
    for _ = 1, 5 do InfoCard.Show({ kind = "action", slot = 3 }) end
    assert(#InfoCard.frame.rows == rows and #InfoCard.frame.buttons == buttons)
end)
T("show_ignores_bad_subjects", function()
    setup(); InfoCard.Show(nil); InfoCard.Show({ kind = "nonsense" }); InfoCard.Show("RightButton")
    assert(not InfoCard.IsShown() and not ns.paused)
end)
T("spell_card_shows_the_spells_tooltip_and_closes", function()
    setup(); Stub.spellNames[768] = "Cat Form"
    InfoCard.Show({ kind = "spell", spellID = 768 }, nil)
    assert(InfoCard.IsShown() and InfoCard.Title() == "Cat Form" and InfoCard.Button("Close"))
    InfoCard.Show({ kind = "spell", spellID = "x" }, nil)
    assert(InfoCard.Title() == "Nothing here" and not ns.paused)
end)
T("pet_action_card_shows_the_pet_tooltip_and_nothing_for_an_empty_slot", function()
    setup(); Stub.petActions[2] = { name = "Follow", texture = "followicon" }
    InfoCard.Show({ kind = "petAction", index = 2 }, nil)
    assert(InfoCard.IsShown() and InfoCard.Title() == "Follow" and InfoCard.Button("Close"))
    assert(not InfoCard.Button("Autocast: on") and not InfoCard.Button("Autocast: off"), "Follow cannot autocast")
    InfoCard.Show({ kind = "petAction", index = 9 }, nil)
    assert(InfoCard.Title() == "Nothing here" and not ns.paused)
end)
T("card_in_the_toc_before_the_contract", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do if line:match("%.lua$") then order[#order + 1] = line end end
    local info, contract
    for i, f in ipairs(order) do if f == "InfoCard.lua" then info = i elseif f == "Contract.lua" then contract = i end end
    assert(info and contract and info < contract and contract == #order, "Contract.lua stays last")
end)

-- ---------------------------------------------------------------------------------------
-- R41: the card is an ordinary frame. Its secure button hangs from UIParent, placed over its card button with points
-- of its own, so the game never protects the card: it opens, closes and moves in a fight.

local function anchoredTo(frame, target)
    for _, p in ipairs(frame.points) do if p[2] == target then return true end end
    return false
end

T("card_secure_button_hangs_from_uiparent_over_its_button", function()
    setup(); Stub.bags[0] = { [1] = { name = "Healing Potion", count = 7, quality = 1 } }
    InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    local secure, use, card = InfoCard.secureButton, InfoCard.Button("Use"), InfoCard.frame
    assert(secure:GetParent() == UIParent and secure:IsVisible(), "a child of UIParent, shown out of a fight")
    assert(not anchoredTo(secure, card) and not anchoredTo(secure, use), "never anchored to the card or its buttons")
    assert(secure.over == use, "it lies over Use")
    local w, h = use:GetSize()
    assert(secure:GetWidth() == w and secure:GetHeight() == h, "the button's size")
    local point, rel, relPoint, x, y = secure:GetPoint(1)
    local _, _, _, ox, oy = use:GetPoint(1)
    assert(point == "TOPLEFT" and rel == ns.root and relPoint == "TOPLEFT")
    assert(x == card.placeX + ox and -y == card.placeY + card:GetHeight() - oy - h, "over the Use button: " .. x .. "," .. y)
    local protected = card:IsProtected()
    assert(not protected, "the card is not protected")
    InfoCard.Hide()
    assert(not secure:IsShown() and secure.over == nil, "it goes with the card")
end)

T("in_a_fight_a_hold_opens_the_card_and_close_closes_it", function()
    setup(); Stub.setTarget("enemy")
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    Stub.click(ns.Cluster.buttons[3], "RightButton")
    assert(InfoCard.IsShown() and InfoCard.Title() == "Frostbolt" and not ns.paused, tostring(ns.lastError))
    Stub.tap(InfoCard.Button("Close"))
    assert(not InfoCard.IsShown() and not ns.paused, tostring(ns.lastError))
    -- the unit card's Target is secure: greyed in the fight, its secure button away
    Stub.click(ns.Units.target, "RightButton")
    assert(InfoCard.IsShown() and not InfoCard.Button("Target"):IsEnabled() and not InfoCard.secureButton:IsShown())
    Stub.click(ns.Cluster.buttons[3], "RightButton")         -- another hold moves the open card
    assert(InfoCard.IsShown() and InfoCard.Title() == "Frostbolt" and not ns.paused, tostring(ns.lastError))
    Stub.tap(InfoCard.catcher); assert(not InfoCard.IsShown(), "a tap away closes it")
    assert(not ns.paused, tostring(ns.lastError))
end)

T("a_fight_starting_takes_the_secure_button_away_and_the_end_brings_it_back", function()
    setup(); Stub.setTarget("enemy")
    Stub.click(ns.Units.target, "RightButton")
    assert(InfoCard.secureButton:IsShown() and InfoCard.secureButton:GetAttribute("type") == "target")
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    assert(not InfoCard.secureButton:IsShown(), "put away before the lockdown")
    assert(not InfoCard.Button("Target"):IsEnabled(), "greyed: the fight is on (the lockdown is not yet)")
    InfoCard.Hide(); InfoCard.Show({ kind = "unit", unit = "target" })
    assert(not ns.paused and not InfoCard.secureButton:IsShown(), tostring(ns.lastError))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(InfoCard.secureButton:IsShown() and InfoCard.Button("Target"):IsEnabled())
end)

-- A tooltip fill that raises (a game function that changed) is not a reason to pause: the card shows without it.
T("a_failing_tooltip_fill_never_pauses", function()
    setup()
    local tip = _G.TouchPlayCardTip or CreateFrame("GameTooltip", "TouchPlayCardTip", UIParent)
    InfoCard.Show({ kind = "action", slot = 3 })
    _G.TouchPlayCardTip.SetAction = function() error("the game changed") end
    InfoCard.Show({ kind = "action", slot = 3 })
    assert(not ns.paused and InfoCard.IsShown(), tostring(ns.lastError))
end)

-- Each greyed entry says its own reason: an unusable secure entry other than Target is not "not nearby".
T("each_entry_has_its_own_reason", function()
    setup(); Stub.quests[77] = { title = "Elixir of Pain", objectives = {} }
    MinimapCluster.ZoneTextButton = false
    InfoCard.Show({ kind = "questObjective", questID = 77 })
    assert(not InfoCard.Button("Show on map"):IsEnabled())
    assert(InfoCard.ReasonText() ~= ns.L["card.unitGone"], tostring(InfoCard.ReasonText()))
end)

-- The secure button follows its card button whenever the card's layout changes out of a fight (a reason line coming
-- or going changes the card's height by 22, and the button sits 14 from the card's bottom).
T("refresh_places_the_secure_button_again", function()
    setup(); Stub.setTarget("enemy")
    InfoCard.Show({ kind = "unit", unit = "target" })
    local card, secure = InfoCard.frame, InfoCard.secureButton
    card:SetHeight(card:GetHeight() + 22)          -- as when the reason line appears
    InfoCard.Refresh()
    local button = InfoCard.Button("Target")
    local _, _, _, ox, oy = button:GetPoint(1)
    local _, h = button:GetSize()
    local _, _, _, x, y = secure:GetPoint(1)
    assert(secure:IsShown() and x == card.placeX + ox and -y == card.placeY + card:GetHeight() - oy - h,
        "over its button again: " .. tostring(-y))
end)

-- ---------------------------------------------------------------------------------------
-- Spell ranks: the card says which rank a button casts

local function rightTexts()
    local out = {}
    for _, row in ipairs(InfoCard.frame.rows) do
        if row.right:IsShown() then out[#out + 1] = row.right:GetText() end
    end
    return table.concat(out, "|")
end

T("rank_the_card_of_a_ranked_spell_button_says_its_rank", function()
    setup(); Stub.addRanks("Frost", "Frost Ray", { 9001, 9002 })
    Stub.spellNames[9001], Stub.spellNames[9002] = "Frost Ray", "Frost Ray"
    Stub.actions[4] = 9001
    InfoCard.Show({ kind = "action", slot = 4 })
    assert(InfoCard.Title() == "Frost Ray" and rightTexts():find("Rank 1", 1, true), rightTexts())
    Stub.actions[4] = 9002
    InfoCard.Show({ kind = "action", slot = 4 })
    assert(rightTexts():find("Rank 2", 1, true) and not rightTexts():find("Rank 1", 1, true), rightTexts())
end)

T("rank_a_rankless_spell_adds_no_rank_line", function()
    setup(); InfoCard.Show({ kind = "action", slot = 3 })
    assert(not rightTexts():find("Rank", 1, true), rightTexts())
end)

T("rank_the_games_own_rank_text_is_not_said_twice", function()
    -- the game's tooltip for a button already has "30 yd range" on the right of its second line: say it is the rank
    setup(); Stub.addRanks("Frost", "Frost Ray", { 9001 })
    Stub.spellbook.lines[4].spells[#Stub.spellbook.lines[4].spells].rank = "30 yd range"
    Stub.spellNames[9001] = "Frost Ray"; Stub.actions[4] = 9001
    InfoCard.Show({ kind = "action", slot = 4 })
    local n = 0
    for _, row in ipairs(InfoCard.frame.rows) do
        if row.right:IsShown() and row.right:GetText() == "30 yd range" then n = n + 1 end
    end
    assert(n == 1, "once, got " .. n)
end)

T("rank_a_spell_card_by_id_says_the_rank", function()
    setup(); Stub.addRanks("Frost", "Frost Ray", { 9001, 9002 })
    Stub.spellNames[9001] = "Frost Ray"
    InfoCard.Show({ kind = "spell", spellID = 9001 })
    assert(rightTexts():find("Rank 1", 1, true), rightTexts())
end)

Stub.done("infocard")
