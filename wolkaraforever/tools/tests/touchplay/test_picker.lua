-- Task 7: change a button, the spell picker (rule 4); mockups 93, 94.
dofile("tests/stub.lua")

local Picker

-- A game session with the add-on loaded and laid out. Spell 116 (Frostbolt) sits on button 1.
local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Picker = ns.Picker
    Stub.actions[1] = 116; Stub.fire("ACTIONBAR_SLOT_CHANGED", 1)
    return Picker
end

-- Opens the picker on the Frost school: the button holds Frost Nova (spell 122).
local function openFrost(slot) Stub.actions[slot] = 122; Picker.Open(slot) end

local function cellOf(name)
    for _, cell in ipairs(Picker.cells) do
        if cell:IsShown() and cell.label:GetText() == name then return cell end
    end
end

-- ---------------------------------------------------------------------------------------
-- The plan's tests

T("rule4_put_places_into_slot", function()
    setup(); Picker.Put(3, { kind = "spell", id = 120 })
    assert(Stub.actions[3].id == 120 and Stub.actions[3].kind == "spell" and Stub.cursorEmpty())
    assert(Stub.lastPickupSpell == 120 and Stub.calls.PlaceAction == 1 and Stub.calls.ClearCursor == 1)
end)

T("rule4_put_replaces_what_was_there", function()
    setup(); Stub.actions[3] = 133
    Picker.Put(3, { kind = "spell", id = 120 })
    assert(Stub.actions[3].id == 120 and Stub.cursorEmpty())
end)

T("rule4_put_an_item", function()
    setup(); Picker.Put(4, { kind = "item", id = 4540 })
    assert(Stub.lastPickupItem == 4540 and Stub.actions[4].kind == "item" and Stub.actions[4].id == 4540)
    assert(Stub.cursorEmpty())
end)

T("rule4_remove_clears_slot", function()
    setup(); Stub.actions[3] = 133; Picker.Remove(3)
    assert(Stub.actions[3] == nil and Stub.cursorEmpty() and Stub.calls.PickupAction == 1)
end)

T("rule4_never_in_combat", function()
    setup(); Stub.combat(true)
    Picker.Put(3, { kind = "spell", id = 120 })
    Stub.actions[2] = 133; Picker.Remove(2)
    assert(Stub.calls.PlaceAction == 0 and Stub.calls.PickupAction == 0 and Stub.calls.ClearCursor == 0)
    assert(Stub.calls.PickupSpell == 0 and Stub.actions[3] == nil and Stub.actions[2] == 133)
end)

T("opens_on_school_of_replaced_spell", function()
    setup(); Stub.actions[2] = { kind = "spell", id = 116, school = "Frost" }
    Picker.Open(2); assert(Picker.tab == "Frost")
end)

T("opens_on_the_first_tab_for_an_empty_button", function()
    setup(); Picker.Open(5); assert(Picker.tab == "General")
end)

T("opens_on_items_for_an_item_button", function()
    setup(); Stub.actions[5] = { kind = "item", id = 4540 }
    Picker.Open(5); assert(Picker.tab == "Items")
end)

T("on_button_dot", function()
    setup(); local e = Picker.Entries("Frost"); assert(e[1].onButton == true)
end)

-- ---------------------------------------------------------------------------------------
-- Entries

T("entries_one_tab_per_school_and_items", function()
    setup(); Picker.Open(5)
    local labels = {}
    for i, tab in ipairs(Picker.tabs.buttons) do labels[i] = tab.label:GetText() end
    assert(table.concat(labels, "|") == "General|Arcane|Fire|Frost|Mounts|Items", table.concat(labels, "|"))
end)

T("entries_spells_only_no_passives_no_future_spells", function()
    setup()
    local e = Picker.Entries("Frost")
    assert(#e == 3 and e[1].id == 116 and e[2].id == 120 and e[3].id == 122)
    for _, entry in ipairs(e) do assert(entry.kind == "spell" and entry.icon and entry.name) end
    assert(#Picker.Entries("General") == 1)       -- the passive is left out
end)

T("entries_on_button_only_for_spells_on_a_button", function()
    setup(); Stub.actions[14] = 122                   -- page 2, button 2
    local e = Picker.Entries("Frost")
    assert(e[1].onButton == true and e[2].onButton == false and e[3].onButton == true)
end)

T("entries_items_are_usable_bag_items_once_each", function()
    setup()
    Stub.bags[0] = { [1] = { name = "Elixir", itemID = 4540, count = 5, icon = "elixir" },
        [2] = { name = "Linen Cloth", itemID = 2589, count = 20 },
        [3] = { name = "Elixir", itemID = 4540, count = 3, icon = "elixir" } }
    Stub.bags[2] = { [1] = { name = "Water", itemID = 8766, count = 10, icon = "water" } }
    Stub.itemSpells[4540], Stub.itemSpells[8766] = true, true
    Stub.actions[6] = { kind = "item", id = 8766 }
    local e = Picker.Entries("Items")
    assert(#e == 2 and e[1].kind == "item" and e[1].id == 4540 and e[1].name == "Elixir" and e[1].icon == "elixir")
    assert(e[1].onButton == false and e[2].id == 8766 and e[2].onButton == true)
end)

T("entries_for_an_unknown_tab_is_empty", function()
    setup(); assert(#Picker.Entries("Holy") == 0)
end)

T("entries_skip_hidden_and_off_spec_schools", function()
    setup(); Stub.spellbook.lines[2].hidden = true; Stub.spellbook.lines[3].offSpec = true
    Picker.Open(5)
    local labels = {}
    for i, tab in ipairs(Picker.tabs.buttons) do labels[i] = tab.label:GetText() end
    assert(table.concat(labels, "|") == "General|Frost|Mounts|Items")
end)

-- ---------------------------------------------------------------------------------------
-- The sheet

T("sheet_is_960_by_580_at_40_420", function()
    setup()
    local s = Picker.sheet
    assert(s:GetWidth() == 960 and s:GetHeight() == 580)
    assert(s.touchAnchor.corner == "BL" and s.touchAnchor.x == 40 and s.touchAnchor.y == 420)
    assert(not s:IsShown())
end)

T("open_shows_the_sheet_title_grid_and_buttons", function()
    setup(); openFrost(2)
    assert(Picker.sheet:IsShown() and Picker.title.label:GetText() == "Choose a spell for this button")
    assert(Picker.putButton.label:GetText() == "Put on button" and Picker.cancelButton.label:GetText() == "Cancel")
    assert(#Picker.cells == 12)
    local c = cellOf("Frostbolt")
    assert(c and c.icon.texture == "icon116" and c.dot:IsShown())
    assert(cellOf("Cone of Cold") and not cellOf("Cone of Cold").dot:IsShown())
    assert(not cellOf("Fireball"))
end)

T("grid_is_six_columns_of_64_icons", function()
    setup(); openFrost(2)
    local a, b = Picker.cells[1], Picker.cells[7]
    assert(a.icon:GetWidth() == 64 and a.icon:GetHeight() == 64)
    assert(a.col == 1 and Picker.cells[6].col == 6 and Picker.cells[7].col == 1 and b.row == 2)
end)

T("tap_a_spell_then_put", function()
    setup(); openFrost(2)
    assert(not Picker.putButton:IsEnabled())
    Stub.click(cellOf("Cone of Cold"))
    assert(Picker.selected.id == 120 and cellOf("Cone of Cold").selectBox:IsShown())
    assert(Picker.putButton:IsEnabled())
    Stub.click(Picker.putButton)
    assert(Stub.actions[2].id == 120 and Stub.cursorEmpty() and not Picker.sheet:IsShown())
end)

T("tapping_another_spell_moves_the_choice", function()
    setup(); openFrost(2)
    Stub.click(cellOf("Cone of Cold")); Stub.click(cellOf("Frost Nova"))
    assert(Picker.selected.id == 122 and not cellOf("Cone of Cold").selectBox:IsShown())
end)

T("cancel_closes_and_changes_nothing", function()
    setup(); openFrost(2)
    Stub.click(cellOf("Cone of Cold")); Stub.click(Picker.cancelButton)
    assert(not Picker.sheet:IsShown() and Stub.actions[2] == 122 and Stub.calls.PlaceAction == 0)
end)

T("tabs_switch_the_grid", function()
    setup(); openFrost(2)
    Stub.click(Picker.tabs.buttons[3])
    assert(Picker.tab == "Fire" and cellOf("Fireball") and not cellOf("Frostbolt"))
    Stub.click(Picker.tabs.buttons[6]); assert(Picker.tab == "Items")
    assert(Picker.noneText:IsShown())
end)

T("items_tab_lists_items_and_puts_one", function()
    setup()
    Stub.bags[0] = { [1] = { name = "Elixir", itemID = 4540, icon = "elixir" } }
    Stub.itemSpells[4540] = true
    openFrost(2); Stub.click(Picker.tabs.buttons[6])
    assert(cellOf("Elixir") and not Picker.noneText:IsShown())
    Stub.click(cellOf("Elixir")); Stub.click(Picker.putButton)
    assert(Stub.actions[2].kind == "item" and Stub.actions[2].id == 4540)
end)

T("paging_through_a_long_school", function()
    setup()
    local many = {}
    for i = 1, 14 do many[i] = { id = 1000 + i, name = "Spell " .. i } end
    Stub.spellbook.lines[4].spells = many
    openFrost(2); Stub.click(Picker.tabs.buttons[4])
    assert(Picker.pageCount == 2 and cellOf("Spell 1") and not cellOf("Spell 13"))
    assert(Picker.pageText:GetText() == "1/2")
    Stub.click(Picker.nextButton)
    assert(cellOf("Spell 13") and cellOf("Spell 14") and not cellOf("Spell 1") and Picker.pageText:GetText() == "2/2")
    assert(not cellOf("Spell 13").dot:IsShown())
    Stub.click(Picker.prevButton); assert(cellOf("Spell 1"))
end)

T("a_choice_survives_a_page_turn", function()
    setup()
    local many = {}
    for i = 1, 14 do many[i] = { id = 1000 + i, name = "Spell " .. i } end
    Stub.spellbook.lines[4].spells = many
    openFrost(2); Stub.click(Picker.tabs.buttons[4])
    Stub.click(cellOf("Spell 2")); Stub.click(Picker.nextButton); Stub.click(Picker.prevButton)
    assert(Picker.selected.id == 1002 and cellOf("Spell 2").selectBox:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- The button being changed, and the flash

T("the_button_being_changed_pulses", function()
    setup(); openFrost(2)
    local ring = Picker.ring
    assert(ring:IsShown() and ring.pulse:IsPlaying())
    local p = ring.points[1]
    assert(p[1] == "CENTER" and p[2] == ns.Cluster.buttons[2])
    Picker.Cancel()
    assert(not ring:IsShown() and not ring.pulse:IsPlaying())
end)

T("no_ring_when_the_slot_is_on_another_page", function()
    setup(); Picker.Open(14)
    assert(Picker.sheet:IsShown() and not Picker.ring:IsShown())
end)

T("the_ring_uses_no_onupdate_and_the_flash_is_a_one_shot", function()
    setup(); openFrost(2)
    assert(Picker.ring.scripts.OnUpdate == nil and Picker.flash.scripts.OnUpdate == nil)
    assert(Picker.flash.group.scripts.OnUpdate == nil)
end)

T("put_flashes_the_button_with_the_spell_name", function()
    setup(); openFrost(2)
    Stub.click(cellOf("Cone of Cold")); Stub.click(Picker.putButton)
    local f = Picker.flash
    assert(f:IsShown() and f.group:IsPlaying() and f.label:GetText() == "Cone of Cold")
    assert(f.points[1][2] == ns.Cluster.buttons[2])
    f.group:_Fire("OnFinished"); assert(not f:IsShown())
end)

T("put_names_the_spell_even_without_a_name_in_the_entry", function()
    setup(); Stub.spellNames[120] = "Cone of Cold"
    Picker.Put(2, { kind = "spell", id = 120 })
    assert(Picker.flash.label:GetText() == "Cone of Cold")
end)

T("a_failed_pickup_places_nothing", function()
    setup(); Stub.actions[2] = 133
    local pick = C_Spell.PickupSpell
    C_Spell.PickupSpell = function() end          -- the game picked nothing up
    Picker.Put(2, { kind = "spell", id = 120 })
    C_Spell.PickupSpell = pick
    assert(Stub.actions[2] == 133 and Stub.calls.PlaceAction == 0 and Stub.cursorEmpty())
end)

-- ---------------------------------------------------------------------------------------
-- Empty buttons, and the fight

T("empty_buttons_show_a_plus_and_a_tap_opens_the_picker", function()
    setup()
    local b1, b2 = ns.Cluster.buttons[1], ns.Cluster.buttons[2]
    assert(not b1.plus:IsShown() and b2.plus:IsShown() and b2.plus:GetText() == "+")
    Stub.click(b2)
    assert(Picker.sheet:IsShown() and Picker.slot == 2)
end)

T("tapping_a_full_button_does_not_open_the_picker", function()
    setup(); Stub.click(ns.Cluster.buttons[1])
    assert(not Picker.sheet:IsShown())
end)

T("a_right_click_on_an_empty_button_does_not_open_the_picker", function()
    setup(); Stub.click(ns.Cluster.buttons[2], "RightButton")
    assert(not Picker.sheet:IsShown())
end)

T("no_picker_from_an_empty_button_in_a_fight", function()
    setup(); Stub.combat(true); Stub.click(ns.Cluster.buttons[2])
    assert(not Picker.sheet:IsShown())
end)

T("remove_leaves_a_plus_that_opens_the_picker", function()
    setup(); Picker.Remove(1)
    local b1 = ns.Cluster.buttons[1]
    assert(b1.plus:IsShown())
    Stub.click(b1); assert(Picker.slot == 1 and Picker.sheet:IsShown())
end)

T("put_hides_the_plus", function()
    setup(); Picker.Put(2, { kind = "spell", id = 120 })
    assert(not ns.Cluster.buttons[2].plus:IsShown())
end)

T("a_page_change_moves_the_plus", function()
    setup(); Stub.actions[13] = 133
    ns.Cluster.buttons[1]:SetAttribute("action", 13)
    assert(not ns.Cluster.buttons[1].plus:IsShown())
    ns.Cluster.buttons[1]:SetAttribute("action", 25)
    assert(ns.Cluster.buttons[1].plus:IsShown())
end)

T("a_fight_greys_put_with_the_reason_and_the_end_of_it_gives_it_back", function()
    setup(); openFrost(2); Stub.click(cellOf("Cone of Cold"))
    assert(Picker.putButton:IsEnabled())
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(not Picker.putButton:IsEnabled())
    assert(Picker.putButton.reasonText:IsShown() and Picker.putButton.reasonText:GetText() == ns.L["card.afterFight"])
    Stub.click(Picker.putButton)
    assert(Stub.calls.PlaceAction == 0 and Picker.sheet:IsShown())
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Picker.putButton:IsEnabled() and not Picker.putButton.reasonText:IsShown())
end)

T("open_in_a_fight_shows_the_reason_and_never_places", function()
    setup(); Stub.combat(true); openFrost(2)
    assert(Picker.sheet:IsShown() and not Picker.putButton:IsEnabled())
    Stub.click(cellOf("Cone of Cold"))
    assert(not Picker.putButton:IsEnabled() and Picker.putButton.reasonText:GetText() == ns.L["card.afterFight"])
    Stub.click(Picker.putButton)
    assert(Stub.calls.PlaceAction == 0 and Stub.calls.PickupSpell == 0)
end)

-- ---------------------------------------------------------------------------------------
-- The info card's buttons, the pause, hidden values

T("the_info_card_buttons_reach_the_picker", function()
    setup()
    ns.InfoCard.Show({ kind = "action", slot = 1 }, ns.Cluster.buttons[1])
    Stub.click(ns.InfoCard.Button("Change spell"))
    assert(Picker.sheet:IsShown() and Picker.slot == 1 and Picker.tab == "Frost")
    Picker.Cancel()
    ns.InfoCard.Show({ kind = "action", slot = 1 }, ns.Cluster.buttons[1])
    Stub.click(ns.InfoCard.Button("Remove"))
    assert(Stub.actions[1] == nil and Stub.cursorEmpty())
end)

T("a_pause_closes_the_picker", function()
    setup(); openFrost(2)
    ns.Each("Restore")
    assert(not Picker.sheet:IsShown() and not Picker.ring:IsShown())
end)

T("hidden_spellbook_names_and_icons_only_reach_the_text_and_the_picture", function()
    setup()
    for _, line in ipairs(Stub.spellbook.lines) do
        for _, sp in ipairs(line.spells) do sp.name = Stub.secret() end
    end
    local info = C_SpellBook.GetSpellBookItemInfo
    C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
        local i = info(slot, bank)
        if i then i.iconID = Stub.secret() end
        return i
    end
    Stub.actions[2] = 116
    Picker.Open(2)
    assert(Picker.tab == "Frost" and Picker.sheet:IsShown())
    local c = Picker.cells[1]
    assert(c:IsShown() and Stub.isSecret(c.label:GetText()) and Stub.isSecret(c.icon.texture) and c.dot:IsShown())
    Stub.click(c); Stub.click(Picker.putButton)
    assert(Stub.actions[2].id == 116 and Stub.isSecret(Picker.flash.label:GetText()))
end)

T("hidden_names_never_break_the_text_keyed_lookup", function()
    setup()
    for _, line in ipairs(Stub.spellbook.lines) do line.name = Stub.secret() end
    assert(#Picker.Entries("Frost") == 0)
    openFrost(2); assert(Picker.sheet:IsShown())
end)

T("every_string_comes_from_the_text_table", function()
    setup()
    for _, key in ipairs({ "picker.title", "picker.put", "picker.legend", "picker.items", "picker.mounts", "picker.randomMount", "picker.showAllRanks", "picker.none", "picker.plus" }) do
        assert(ns.L[key], key)
    end
    assert(not TouchPlayDB.missingText or #TouchPlayDB.missingText == 0)
    openFrost(2)
    assert(not TouchPlayDB.missingText or #TouchPlayDB.missingText == 0)
end)

-- ---------------------------------------------------------------------------------------
-- Mounts: the journal's own pickup, from a tap, out of a fight

local function names(entries)
    local out = {}
    for i, e in ipairs(entries) do out[i] = e.name end
    return table.concat(out, "|")
end

T("mounts_tab_lists_collected_mounts_random_first_favourites_then_alphabetical", function()
    setup()
    local e = Picker.Entries("Mounts")
    assert(names(e) == "Random favourite mount|Frostwolf Howler|Swift Palomino|Brown Horse", names(e))
    assert(e[1].kind == "mount" and e[1].random == true and e[1].id == 0)
    assert(e[2].kind == "mount" and e[2].id == 17 and e[2].icon == "mount17")
    assert(Stub.calls.MountPickup == 0)           -- listing never picks anything up
end)

T("mounts_tab_has_no_random_entry_without_a_favourite", function()
    setup()
    for _, m in ipairs(Stub.mounts) do m.favorite = nil end
    assert(names(Picker.Entries("Mounts")) == "Brown Horse|Frostwolf Howler|Swift Palomino")
end)

T("mounts_tab_shows_in_the_grid_and_marks_mounts_already_on_a_button", function()
    setup(); Stub.actions[3] = { kind = "summonmount", id = 35 }
    Picker.Open(5)
    Stub.click(Picker.tabs.buttons[5])
    assert(Picker.tab == "Mounts")
    local c = cellOf("Swift Palomino")
    assert(c and c.icon.texture == "mount35" and c.dot:IsShown())
    assert(not cellOf("Brown Horse").dot:IsShown())
    assert(cellOf("Random favourite mount"))
end)

T("opens_on_mounts_for_a_mount_button", function()
    setup(); Stub.actions[5] = { kind = "summonmount", id = 35 }
    Picker.Open(5); assert(Picker.tab == "Mounts")
end)

T("tapping_a_mount_puts_it_on_the_button_with_the_journals_pickup", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Swift Palomino")); Stub.click(Picker.putButton)
    assert(Stub.calls.MountPickup == 1 and Stub.calls.PlaceAction == 1 and Stub.lastPlaceAction == 5)
    assert(Stub.actions[5].kind == "summonmount" and Stub.actions[5].id == 35 and Stub.cursorEmpty())
    assert(not Picker.sheet:IsShown())
end)

T("the_random_favourite_is_placed_with_pickup_zero", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Random favourite mount")); Stub.click(Picker.putButton)
    assert(Stub.calls.MountPickup == 1 and Stub.calls.PlaceAction == 1)
    assert(Stub.actions[5].kind == "summonmount" and Stub.actions[5].id == 0 and Stub.cursorEmpty())
end)

T("a_mount_is_found_by_id_if_the_journal_order_moved_since_the_list", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Swift Palomino"))
    table.insert(Stub.mounts, 1, { id = 77, name = "Aardvark", icon = "mount77", collected = true })
    Stub.click(Picker.putButton)
    assert(Stub.actions[5].id == 35, "the mount picked is the one chosen")
end)

T("a_mount_that_left_the_journal_is_not_placed", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Swift Palomino"))
    table.remove(Stub.mounts, 4)
    Stub.click(Picker.putButton)
    assert(Stub.calls.PlaceAction == 0 and Stub.actions[5] == nil and Stub.cursorEmpty())
end)

T("mounts_in_a_fight_are_greyed_and_nothing_is_called", function()
    setup(); Stub.combat(true); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Swift Palomino"))
    assert(not Picker.putButton:IsEnabled() and Picker.putButton.reasonText:GetText() == ns.L["card.afterFight"])
    Stub.click(Picker.putButton)
    assert(Picker.Put(5, { kind = "mount", id = 35 }) == false)
    assert(Stub.calls.MountPickup == 0 and Stub.calls.PlaceAction == 0 and Stub.calls.ClearCursor == 0)
    assert(Stub.actions[5] == nil)
end)

T("mounts_tab_pins_a_mount_to_the_mount_ring", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    assert(Picker.tab == "Mounts" and Picker.pinButton:IsShown() and not Picker.rankChip:IsShown())
    assert(not Picker.pinButton:IsEnabled(), "nothing chosen yet")
    Stub.click(cellOf("Swift Palomino"))
    assert(Picker.pinButton:IsEnabled())
    Stub.click(Picker.pinButton)
    assert(TouchPlayCharDB.mount == 35 and not Picker.sheet:IsShown(), "pinned, and the sheet closes")
    assert(_G.TouchPlayMount:GetAttribute("macrotext"):find("SummonByID(35)", 1, true))
    assert(Stub.actions[5] == nil and Stub.calls.MountPickup == 0, "the spell button is left alone")
    -- the random favourite again
    Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Random favourite mount")); Stub.click(Picker.pinButton)
    assert(TouchPlayCharDB.mount == nil and _G.TouchPlayMount:GetAttribute("macrotext"):find("SummonByID(0)", 1, true))
end)

T("pin_button_only_on_the_mounts_tab_and_greyed_in_a_fight", function()
    setup(); openFrost(2)
    assert(not Picker.pinButton:IsShown())
    Picker.Close(); Stub.combat(true); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.click(cellOf("Swift Palomino"))
    assert(Picker.pinButton:IsShown() and not Picker.pinButton:IsEnabled())
    assert(Picker.PinMount({ kind = "mount", id = 35 }) == false and TouchPlayCharDB.mount == nil)
    assert(ns.L["picker.pinMount"] == "Put on Mount button")
end)

T("no_mount_call_comes_from_an_event_or_a_timer", function()
    setup(); Picker.Open(5); Stub.click(Picker.tabs.buttons[5])
    Stub.actions[8] = { kind = "summonmount", id = 17 }
    Stub.fire("ACTIONBAR_SLOT_CHANGED", 8); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.fire("PLAYER_REGEN_ENABLED")
    Stub.fire("PLAYER_ENTERING_WORLD"); Stub.advance(10)
    assert(Stub.calls.MountPickup == 0 and Stub.calls.PlaceAction == 0 and Stub.calls.PickupAction == 0)
end)

T("a_client_without_the_mount_journal_has_no_mounts_tab", function()
    setup(); C_MountJournal = nil
    Picker.Open(5)
    local labels = {}
    for i, tab in ipairs(Picker.tabs.buttons) do labels[i] = tab.label:GetText() end
    assert(table.concat(labels, "|") == "General|Arcane|Fire|Frost|Items")
    assert(#Picker.Entries("Mounts") == 0)
end)

-- ---------------------------------------------------------------------------------------
-- Spell ranks: the highest known by default, a lower one on the row, every rank with "Show all ranks"

-- Fire holds Fireball and Fire Blast (no ranks) and Scorch known at ranks 1 to 3.
local SCORCH1, SCORCH2, SCORCH3 = 2948, 8444, 8445
local function withScorch()
    setup(); Stub.addRanks("Fire", "Scorch", { SCORCH1, SCORCH2, SCORCH3 })
end

local function rowNamed(entries, name)
    for _, e in ipairs(entries) do if e.name == name then return e end end
end

local function openFire(slot) Picker.Open(slot); Stub.click(Picker.tabs.buttons[3]); assert(Picker.tab == "Fire") end

T("ranks_a_spell_with_three_ranks_lists_rank_three_by_default", function()
    withScorch()
    local e = Picker.Entries("Fire")
    local n = 0
    for _, row in ipairs(e) do if row.name == "Scorch" then n = n + 1 end end
    assert(n == 1 and #e == 3, "one row per spell, got " .. #e)
    local row = rowNamed(e, "Scorch")
    assert(row.id == SCORCH3 and row.rank == "Rank 3" and #row.ranks == 3)
    assert(row.ranks[1].id == SCORCH3 and row.ranks[2].id == SCORCH2 and row.ranks[3].id == SCORCH1)
end)

T("ranks_the_row_shows_the_rank_and_a_rank_control", function()
    withScorch(); openFire(5)
    local c = cellOf("Scorch")
    assert(c.rankButton:IsShown() and c.rankButton.label:GetText() == "Rank 3")
    assert(c.rankButton:IsEnabled() and c.rankButton.arrow:IsShown())
    assert(c.rankButton:GetHeight() >= 24)
end)

T("ranks_a_rankless_spell_shows_no_rank", function()
    withScorch(); openFire(5)
    local c = cellOf("Fireball")
    assert(not c.rankButton:IsShown())
    assert(rowNamed(Picker.Entries("Fire"), "Fireball").rank == "")
    assert(rowNamed(Picker.Entries("Fire"), "Fireball").ranks == nil)
end)

T("ranks_a_spell_with_one_known_rank_shows_it_without_a_choice", function()
    setup(); Stub.addRanks("Fire", "Pyroblast", { 11366 })
    Stub.spellbook.lines[3].spells[#Stub.spellbook.lines[3].spells].low = false
    openFire(5)
    local c = cellOf("Pyroblast")
    assert(c.rankButton:IsShown() and c.rankButton.label:GetText() == "Rank 1")
    assert(not c.rankButton.arrow:IsShown() and not c.rankButton:IsMouseEnabled())
end)

T("ranks_the_default_places_the_highest_rank", function()
    withScorch(); openFire(5)
    Stub.click(cellOf("Scorch")); Stub.click(Picker.putButton)
    assert(Stub.lastPickupSpell == SCORCH3 and Stub.actions[5].id == SCORCH3)
end)

T("ranks_choosing_rank_one_places_rank_ones_id", function()
    withScorch(); openFire(5)
    local c = cellOf("Scorch")
    Stub.click(c.rankButton)
    assert(Picker.rankMenu:IsShown())
    local labels = {}
    for i = 1, 3 do labels[i] = Picker.rankMenu.buttons[i].label:GetText() end
    assert(table.concat(labels, "|") == "Rank 3|Rank 2|Rank 1", table.concat(labels, "|"))
    assert(not Picker.rankMenu.buttons[4] or not Picker.rankMenu.buttons[4]:IsShown())
    Stub.click(Picker.rankMenu.buttons[3])
    assert(not Picker.rankMenu:IsShown() and c.rankButton.label:GetText() == "Rank 1")
    assert(Picker.selected and Picker.selected.id == SCORCH1)
    assert(Stub.calls.PickupSpell == 0 and Stub.calls.PlaceAction == 0, "choosing a rank places nothing")
    Stub.click(Picker.putButton)
    assert(Stub.lastPickupSpell == SCORCH1 and Stub.actions[5].id == SCORCH1 and Stub.cursorEmpty())
end)

T("ranks_the_green_dot_follows_the_rank_shown", function()
    withScorch(); Stub.actions[2] = SCORCH1; openFire(5)
    local c = cellOf("Scorch")
    assert(not c.dot:IsShown())
    Stub.click(c.rankButton); Stub.click(Picker.rankMenu.buttons[3])
    assert(c.dot:IsShown())
end)

T("ranks_a_fight_greys_put_for_a_chosen_rank_and_nothing_is_called", function()
    withScorch(); openFire(5)
    Stub.click(cellOf("Scorch").rankButton); Stub.click(Picker.rankMenu.buttons[2])
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(not Picker.putButton:IsEnabled() and Picker.putButton.reasonText:GetText() == ns.L["card.afterFight"])
    Stub.click(Picker.putButton)
    assert(Picker.Put(5, Picker.selected) == false)
    assert(Stub.calls.PickupSpell == 0 and Stub.calls.PlaceAction == 0 and Stub.actions[5] == nil)
end)

T("ranks_the_menu_closes_on_a_tab_page_or_cancel", function()
    withScorch(); openFire(5)
    Stub.click(cellOf("Scorch").rankButton); assert(Picker.rankMenu:IsShown())
    Stub.click(Picker.tabs.buttons[2]); assert(not Picker.rankMenu:IsShown())
    Stub.click(Picker.tabs.buttons[3]); Stub.click(cellOf("Scorch").rankButton)
    Stub.click(Picker.cancelButton); assert(not Picker.rankMenu:IsShown())
end)

T("ranks_show_all_ranks_off_is_the_start", function()
    withScorch()
    assert(Picker.ShowAllRanks() == false)
    openFire(5)
    assert(Picker.rankChip:IsShown() and Picker.rankChip.on == false)
    assert(Picker.rankChip.label:GetText() == "Show all ranks")
end)

T("ranks_show_all_ranks_lists_every_rank_as_its_own_row", function()
    withScorch(); openFire(5)
    Stub.click(Picker.rankChip)
    assert(Picker.ShowAllRanks() == true and TouchPlayDB.showAllRanks == true and Picker.rankChip.on == true)
    local e = Picker.Entries("Fire")
    local got = {}
    for _, row in ipairs(e) do got[#got + 1] = row.name .. ":" .. row.rank .. ":" .. row.id end
    assert(table.concat(got, ",") == "Fireball::133,Fire Blast::2136,Scorch:Rank 3:8445,Scorch:Rank 2:8444,Scorch:Rank 1:2948",
        table.concat(got, ","))
    for _, row in ipairs(e) do assert(row.ranks == nil) end
    assert(Picker.tab == "Fire" and #Picker.entries == 5)
    local rankCells = 0
    for _, cell in ipairs(Picker.cells) do
        if cell:IsShown() and cell.label:GetText() == "Scorch" then
            rankCells = rankCells + 1
            assert(cell.rankButton:IsShown() and not cell.rankButton.arrow:IsShown())
        end
    end
    assert(rankCells == 3)
end)

T("ranks_show_all_ranks_places_the_exact_row", function()
    withScorch(); openFire(5); Stub.click(Picker.rankChip)
    local picked
    for _, cell in ipairs(Picker.cells) do
        if cell:IsShown() and cell.label:GetText() == "Scorch" and cell.rankButton.label:GetText() == "Rank 2" then picked = cell end
    end
    Stub.click(picked); Stub.click(Picker.putButton)
    assert(Stub.lastPickupSpell == SCORCH2 and Stub.actions[5].id == SCORCH2)
end)

T("ranks_show_all_ranks_off_again_goes_back_to_one_row", function()
    withScorch(); openFire(5); Stub.click(Picker.rankChip); Stub.click(Picker.rankChip)
    assert(TouchPlayDB.showAllRanks == false and #Picker.entries == 3)
end)

T("ranks_the_setting_starts_from_the_games_own_checkbox", function()
    setup(); Stub.cvars.ShowAllSpellRanks = "1"
    assert(Picker.ShowAllRanks() == true)
    Stub.cvars.ShowAllSpellRanks = "0"
    assert(Picker.ShowAllRanks() == false)
    TouchPlayDB.showAllRanks = true
    assert(Picker.ShowAllRanks() == true, "the player's own choice here wins over the game's setting")
    TouchPlayDB.showAllRanks = false; Stub.cvars.ShowAllSpellRanks = "1"
    assert(Picker.ShowAllRanks() == false)
end)

T("ranks_the_chip_is_only_on_spell_tabs", function()
    withScorch(); openFire(5)
    assert(Picker.rankChip:IsShown())
    Stub.click(Picker.tabs.buttons[5]); assert(Picker.tab == "Mounts" and not Picker.rankChip:IsShown())
    Stub.click(Picker.tabs.buttons[6]); assert(Picker.tab == "Items" and not Picker.rankChip:IsShown())
    Stub.click(Picker.tabs.buttons[3]); assert(Picker.rankChip:IsShown())
end)

T("ranks_the_flash_names_the_rank", function()
    withScorch(); openFire(5)
    Stub.click(cellOf("Scorch")); Stub.click(Picker.putButton)
    assert(Picker.flash.label:GetText() == "Scorch, Rank 3", Picker.flash.label:GetText())
end)

T("ranks_hidden_rank_text_only_reaches_the_text", function()
    withScorch()
    for _, sp in ipairs(Stub.spellbook.lines[3].spells) do if sp.rank then sp.rank = Stub.secret() end end
    openFire(5)
    assert(#Picker.entries == 3 and #rowNamed(Picker.entries, "Scorch").ranks == 3)
    local c = cellOf("Scorch")
    assert(c.rankButton:IsShown() and Stub.isSecret(c.rankButton.label:GetText()))
    Stub.click(c.rankButton); Stub.click(Picker.rankMenu.buttons[2]); Stub.click(Picker.putButton)
    -- hidden rank text cannot be sorted: the highest first, then the spellbook's own order
    assert(Stub.actions[5].id == SCORCH1 and Picker.flash.label:GetText() == "Scorch")
end)

Stub.done("picker")
