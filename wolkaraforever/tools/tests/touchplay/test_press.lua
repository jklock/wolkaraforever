-- Polish pass (18 Nov): every control shows a press (pale gold, then a short fade), greyed controls say why, a game
-- error flashes the pressed spell red, out of range turns the icon red, and no hover look stays lit.
dofile("tests/stub.lua")

local Kit, Contract

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Kit, Contract = ns.Kit, ns.Contract
    assert(not ns.paused, ns.lastError)
end

local function tapKey(name) return (select(1, Contract.KeysFor(name))) end
local function holdKey(name) return (select(2, Contract.KeysFor(name))) end
local function pressKey(name) return (select(3, Contract.KeysFor(name))) end

local function lit(frame) return frame.touchPress and frame.touchPress:GetAlpha() == 1 and frame.touchPress.down end
local function fading(frame) return frame.touchPress and frame.touchPress.group:IsPlaying() end
local function tint(frame) return frame.touchPress.tint end

-- ---------------------------------------------------------------------------------------
-- The look itself

T("a_red_button_lights_while_pressed_and_fades_when_let_go", function()
    setup()
    local b = Kit.RedButton(ns.root, 180, 44, "Accept")
    assert(b.touchPress and b.touchPress:GetAlpha() == 0, "not lit before a press")
    Stub.mouseDown(b)
    assert(lit(b) and not fading(b), "lit at once, held while the finger is down")
    assert(tint(b) == Kit.PRESS_COLOR, "pale gold")
    Stub.mouseUp(b)
    assert(not b.touchPress.down and fading(b), "let go: the fade runs")
    assert(b.touchPress.hold.duration == Kit.PRESS_HOLD and b.touchPress.fade.duration == Kit.PRESS_FADE)
    assert(b.touchPress.fade.toAlpha == 0 and b.touchPress.fade.fromAlpha == 1, "fades out")
    assert(Kit.PRESS_HOLD + Kit.PRESS_FADE <= 0.2, "short: about 100-150 ms of motion")
end)

T("reduce_motion_holds_the_look_then_drops_it_with_no_fade", function()
    setup()
    ns.db.feel = { reduceMotion = true }
    local b = Kit.RedButton(ns.root, 180, 44, "Accept")
    Stub.mouseDown(b); Stub.mouseUp(b)
    local layer = b.touchPress
    assert(fading(b), "still shown for a moment")
    assert(layer.fade.fromAlpha == 1 and layer.fade.toAlpha == 1, "no alpha change while it plays: no animation")
    -- and back with motion on
    ns.db.feel = { reduceMotion = false }
    Stub.mouseDown(b); Stub.mouseUp(b)
    assert(layer.fade.toAlpha == 0)
end)

T("a_tap_with_no_down_before_it_still_flashes", function()
    setup()
    local b = Kit.RedButton(ns.root, 180, 44, "Accept")
    Kit.PressUp(b)
    assert(fading(b) and tint(b) == Kit.PRESS_COLOR)
end)

T("a_disabled_red_button_presses_grey_and_says_why", function()
    setup()
    local b = Kit.RedButton(ns.root, 180, 44, "Accept")
    b:SetEnabledWithReason(false, "Your quest log is full")
    Stub.mouseDown(b)
    assert(tint(b) == Kit.PRESS_GREY, "grey, not gold")
    assert(Kit.reasonFrame and Kit.reasonFrame:IsShown() and Kit.reasonFrame.text:GetText() == "Your quest log is full")
    Stub.mouseUp(b)
    Stub.advance(Kit.REASON_SECONDS + 0.1)
    assert(not Kit.reasonFrame:IsShown(), "the reason goes after a moment")
end)

T("a_busy_red_button_presses_grey_with_no_words", function()
    setup()
    local b = Kit.RedButton(ns.root, 180, 44, "Accept")
    b:SetBusy(true)
    Stub.mouseDown(b)
    assert(tint(b) == Kit.PRESS_GREY)
    assert(not (Kit.reasonFrame and Kit.reasonFrame:IsShown()))
end)

T("an_unknown_shape_is_an_error", function()
    setup()
    local ok = pcall(Kit.AddPress, CreateFrame("Button", nil, ns.root), "star")
    assert(not ok)
end)

-- ---------------------------------------------------------------------------------------
-- The keys the app sends

T("the_press_key_watcher_listens_and_passes_every_key_on", function()
    setup()
    local f = Contract.pressKeys
    assert(f:IsKeyboardEnabled() and f:GetPropagateKeyboardInput(), "keys still reach the bindings and the game")
end)

T("a_spell_key_lights_its_button_at_the_down_and_lets_go_at_the_up", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1"))
    assert(lit(b), "lit at the key's down")
    Stub.keyUp(tapKey("spell1"))
    assert(fading(b) and not b.touchPress.down, "let go at its up")
end)

T("jump_is_lit_for_as_long_as_the_finger_is_down", function()
    setup()
    local jump = ns.Interact.jump
    Stub.keyDown(pressKey("jump"))
    assert(lit(jump) and not fading(jump), "the app sends Jump's key down when the finger lands")
    Stub.keyUp(pressKey("jump"))
    assert(fading(jump))
end)

T("command_areas_light_too", function()
    setup()
    for _, name in ipairs({ "bags", "menu", "minimap", "interact" }) do
        local key = tapKey(name)
        local frame = Contract.pressByKey[key]
        assert(frame and frame.touchPress, name .. " has a press look")
        Stub.keyDown(key)
        assert(lit(frame), name .. " lit")
        Stub.keyUp(key)
        assert(fading(frame), name .. " lets go")
    end
end)

T("a_hold_key_does_not_light_the_press", function()
    setup()
    local b = ns.Cluster.buttons[2]
    Stub.keyDown(holdKey("spell2"))
    assert(not lit(b), "the hold opens the info card; the app draws its ring")
    Stub.keyUp(holdKey("spell2"))
end)

T("a_bare_key_from_a_keyboard_lights_nothing", function()
    setup()
    local b = ns.Cluster.buttons[1]
    local bare = tapKey("spell1"):gsub("^ALT%-CTRL%-SHIFT%-", "")
    Stub.hold(false, false, false)
    Contract.pressKeys:_Fire("OnKeyDown", bare)
    assert(not lit(b))
    Contract.pressKeys:_Fire("OnKeyUp", bare)
end)

T("the_key_up_lets_go_even_with_the_modifiers_gone", function()
    setup()
    local b = ns.Cluster.buttons[3]
    local bare = tapKey("spell3"):gsub("^ALT%-CTRL%-SHIFT%-", "")
    Stub.hold(true, true, true)
    Contract.pressKeys:_Fire("OnKeyDown", bare)
    assert(lit(b))
    Stub.hold(false, false, false)
    Contract.pressKeys:_Fire("OnKeyUp", bare)
    assert(not b.touchPress.down and fading(b), "nothing stays lit")
end)

T("every_tap_and_press_area_has_a_press_look", function()
    setup()
    local n = 0
    for key, frame in pairs(Contract.pressByKey) do
        n = n + 1
        assert(frame.touchPress, "the area on " .. key .. " has no press look")
    end
    assert(n >= 20, "the play screen's tap and press keys are watched (" .. n .. ")")
end)

T("a_pause_lets_every_look_go", function()
    setup()
    local jump = ns.Interact.jump
    Stub.keyDown(pressKey("jump"))
    assert(lit(jump))
    ns.Pause("test")
    assert(jump.touchPress:GetAlpha() == 0 and not jump.touchPress.down, "a key up that never comes leaves nothing lit")
end)

-- ---------------------------------------------------------------------------------------
-- Greyed controls say why

T("mount_greyed_in_a_fight_says_why_when_pressed", function()
    setup()
    Contract.Apply()
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    local dive = ns.Interact.dive
    assert(ns.Interact.diveLabel() == "Mount")
    Stub.keyDown(pressKey("dive"))
    assert(tint(dive) == Kit.PRESS_GREY, "grey press")
    assert(Kit.reasonFrame:IsShown() and Kit.reasonFrame.text:GetText() == ns.L["dive.afterFight"])
    Stub.keyUp(pressKey("dive"))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    Stub.keyDown(pressKey("dive"))
    assert(tint(dive) == Kit.PRESS_COLOR, "gold again after the fight")
    Stub.keyUp(pressKey("dive"))
end)

T("nothing_near_presses_grey_with_no_words", function()
    setup()
    local interact = ns.Interact.interact
    assert(ns.Interact.label() == ns.L["interact.none"])
    Stub.keyDown(tapKey("interact"))
    assert(tint(interact) == Kit.PRESS_GREY)
    assert(not (Kit.reasonFrame and Kit.reasonFrame:IsShown()), "its label already says it")
    Stub.keyUp(tapKey("interact"))
end)

-- ---------------------------------------------------------------------------------------
-- Plain taps (a window or sheet open): the secure button over a picture lights the picture

T("a_plain_tap_on_a_ring_lights_the_ring_under_the_secure_button", function()
    setup()
    local bags = ns.Hud.bags
    assert(bags.touchPress == bags.face.touchPressLayer, "one look, shared with the picture")
    Stub.mouseDown(bags)
    assert(lit(bags))
    Stub.mouseUp(bags)
    assert(fading(bags))
end)

T("a_menu_tile_lights_its_edge", function()
    setup()
    local tile = ns.Menu.tiles.bags or select(2, next(ns.Menu.tiles))
    Stub.mouseDown(tile); assert(lit(tile)); Stub.mouseUp(tile); assert(fading(tile))
end)

T("a_unit_card_glows_at_its_portrait_never_a_box_round_it", function()
    setup()
    for _, card in ipairs({ ns.Units.player, ns.Units.target }) do
        assert(card.touchPress and card.touchPress.shape == "round", "a glow, not a box (iPad run 7)")
    end
    assert(ns.Units.playerTap.touchPress == ns.Units.player.touchPress, "the player's key lights the same glow")
end)

-- ---------------------------------------------------------------------------------------
-- Spell button states the template did not show

T("no_hover_highlight_stays_lit_on_a_spell_button", function()
    setup()
    for _, b in ipairs(ns.Cluster.buttons) do
        assert(b:GetHighlightTexture():GetAlpha() == 0, "the pointer stays where the last plain tap left it")
    end
end)

T("a_game_error_flashes_the_pressed_spell_red", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.click(b, "LeftButton")          -- the press is noted (PreClick)
    assert(ns.Hud.ShowError("Not enough mana"))
    assert(tint(b) == Kit.PRESS_ERROR and fading(b))
    Stub.mouseDown(b)
    assert(tint(b) == Kit.PRESS_COLOR, "the next press is gold again")
end)

T("out_of_range_turns_the_icon_red", function()
    setup()
    local b = ns.Cluster.buttons[1]
    local r = b.touchRange
    assert(r, "a range veil")
    ActionButton_UpdateRangeIndicator(b, true, false)
    assert(r.frame:GetAlpha() == 1 and r.veil:GetAlpha() == 1, "checks range, out of it: red")
    ActionButton_UpdateRangeIndicator(b, true, true)
    assert(r.veil:GetAlpha() == 0, "in range: clear")
    ActionButton_UpdateRangeIndicator(b, false, false)
    assert(r.frame:GetAlpha() == 0, "no range to check: clear")
end)

T("out_of_range_takes_hidden_values_without_comparing_them", function()
    setup()
    local b = ns.Cluster.buttons[1]
    ActionButton_UpdateRangeIndicator(b, Stub.secret(), Stub.secret())
    assert(b.touchRange.frame.alphaFromBoolean and b.touchRange.veil.alphaFromBoolean, "straight to SetAlphaFromBoolean")
    assert(ns.lastError == nil, tostring(ns.lastError))
end)

T("a_game_button_that_is_not_ours_is_left_alone_by_the_range_hook", function()
    setup()
    local other = CreateFrame("CheckButton", "SomeOtherButton", UIParent, "ActionBarButtonTemplate")
    ActionButton_UpdateRangeIndicator(other, true, false)
    assert(other.touchRange == nil)
end)

T("the_casting_and_aiming_animations_grow_with_the_button", function()
    setup()
    -- the template's cast and aim animations are 128 units for its 45-unit button; ours are 88 and 64
    for i, b in ipairs(ns.Cluster.buttons) do
        b.SpellCastAnimFrame = rawget(b, "SpellCastAnimFrame") or CreateFrame("Frame", nil, b)
        b.TargetReticleAnimFrame = rawget(b, "TargetReticleAnimFrame") or CreateFrame("Frame", nil, b)
        Kit.FitActionButton(b, b:GetWidth())
        local want = b:GetWidth() / 45
        assert(math.abs(b.SpellCastAnimFrame:GetScale() - want) < 1e-6, "button " .. i .. " cast animation")
        assert(math.abs(b.TargetReticleAnimFrame:GetScale() - want) < 1e-6, "button " .. i .. " aim animation")
    end
end)

T("put_on_button_pressed_with_nothing_chosen_says_what_to_do", function()
    setup()
    local Picker = ns.Picker
    Picker.Open(1)
    assert(Picker.selected == nil and not Picker.putButton:IsEnabled())
    Stub.mouseDown(Picker.putButton)
    assert(tint(Picker.putButton) == Kit.PRESS_GREY)
    assert(Kit.reasonFrame:IsShown() and Kit.reasonFrame.text:GetText() == ns.L["picker.chooseFirst"])
    Stub.mouseUp(Picker.putButton)
end)

T("a_game_error_after_an_item_tap_flashes_that_slot_red", function()
    setup()
    local b = ns.ItemRail.buttons[1]
    Stub.click(b, "LeftButton")
    assert(ns.Hud.ShowError("Can't do that while moving"))
    assert(tint(b) == Kit.PRESS_ERROR and fading(b))
end)

-- ---------------------------------------------------------------------------------------
-- A look that stays lit (iPad, 18 Nov): the Bags button stayed lit after the bags closed, and the quest box kept an
-- outline after the map was opened by tapping the quest list and closed by tapping the minimap. The key down lit the
-- area, a window opened, and the matching key up never reached the watcher.

local function lone(frame) return not frame.touchPress.down and frame.touchPress:GetAlpha() == 0 end
local function gone(frame) Stub.advance(0.5); return lone(frame) end
local function nothingLit()
    for key, frame in pairs(Contract.pressByKey) do
        if frame.touchPress and frame.touchPress:GetAlpha() > 0 then return false, key end
    end
    return true
end

T("bags_button_is_not_left_lit_when_the_key_up_is_lost_and_the_bags_close", function()
    setup()
    local bags = ns.Hud.bags
    Stub.keyDown(tapKey("bags"))
    assert(lit(bags), "lit at the key's down")
    ContainerFrame1:Show(); Stub.advance(0.3)          -- the bags open; the key up never comes
    assert(not bags.touchPress.down, "a window opening lets the look go")
    ContainerFrame1:Hide(); Stub.advance(0.3)          -- the bags close
    assert(gone(bags) and nothingLit(), "nothing lit after the bags closed")
    Stub.keyUp(tapKey("bags"))                         -- a late key up changes nothing
    assert(gone(bags), "a late key up does not flash it again")
end)

T("quest_outline_is_not_left_when_the_map_opens_and_closes_by_the_minimap", function()
    setup()
    local quest, minimap = ns.Hud.quest, ns.Hud.minimap
    Stub.keyDown(tapKey("quest"))                      -- tap the quest list
    assert(lit(quest))
    CharacterFrame:Show(); Stub.advance(0.3)           -- the map opens; the key up is lost
    assert(not quest.touchPress.down, "the window opening lets the quest box go")
    Stub.keyDown(tapKey("minimap"))                    -- tap the minimap to close it
    assert(lit(minimap) and gone(quest), "the quest box is dark when the minimap lights")
    CharacterFrame:Hide(); Stub.advance(0.3)           -- the map closes; the minimap's key up is lost too
    assert(gone(minimap) and nothingLit(), "nothing lit after the map closed")
end)

T("only_one_tap_area_is_lit_at_a_time", function()
    setup()
    local a, b = ns.Cluster.buttons[1], ns.Cluster.buttons[2]
    Stub.keyDown(tapKey("spell1")); assert(lit(a))
    Stub.keyDown(tapKey("spell2"))
    assert(lit(b) and not a.touchPress.down, "a new key down lets the earlier tap area go")
    Stub.keyUp(tapKey("spell2")); Stub.keyUp(tapKey("spell1"))
    assert(gone(a) and gone(b) and nothingLit())
end)

T("a_tap_area_with_no_key_up_goes_dark_after_a_second_and_a_half", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    Stub.advance(1.4); assert(lit(b), "still down inside the limit")
    Stub.advance(0.2); assert(not b.touchPress.down, "the limit let it go")
    assert(gone(b))
end)

T("a_late_timer_does_not_cut_a_newer_press_short", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); Stub.keyUp(tapKey("spell1"))
    Stub.advance(1.0)
    Stub.keyDown(tapKey("spell1"))                     -- a second tap, 1 s later
    Stub.advance(0.7)                                  -- the first one's timer is due now
    assert(lit(b), "the second press keeps its own 1.5 s")
    Stub.keyUp(tapKey("spell1"))
end)

T("jump_stays_lit_while_held_past_the_limit_but_a_window_change_lets_it_go", function()
    setup()
    local jump = ns.Interact.jump
    Stub.keyDown(pressKey("jump"))
    Stub.advance(5); assert(lit(jump), "a held Jump has no time limit")
    ContainerFrame1:Show(); Stub.advance(0.3)
    assert(not jump.touchPress.down, "a window opening lets it go")
    ContainerFrame1:Hide(); Stub.advance(0.3)
    assert(gone(jump))
end)

T("a_fight_starting_or_ending_lets_every_look_go", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    Stub.fire("PLAYER_REGEN_DISABLED")
    assert(not b.touchPress.down, "fight starts")
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not b.touchPress.down, "fight ends")
    assert(gone(b))
end)

T("one_of_our_sheets_showing_lets_the_look_go", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    ns.Menu.panel:Show()
    assert(not b.touchPress.down)
    ns.Menu.panel:Hide()
    assert(gone(b))
end)

T("the_area_hiding_lets_its_look_go_at_once", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    b:Hide()
    assert(lone(b), "no fade on a frame that is gone")
    b:Show()
    assert(lone(b), "and it is dark when it comes back")
end)

T("the_pulse_box_taking_focus_lets_the_look_go", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    Stub.keyboardFocus = nil
    local box = _G.TouchPlayWorldSignal
    assert(box, "the pulse box")
    box:SetFocus()                                       -- an edit box takes the keyboard: key ups stop arriving
    assert(not b.touchPress.down)
    box:ClearFocus()
end)

T("the_key_watcher_hiding_lets_every_look_go", function()
    setup()
    local b = ns.Cluster.buttons[1]
    Stub.keyDown(tapKey("spell1")); assert(lit(b))
    Contract.pressKeys:Hide()
    assert(not b.touchPress.down)
    Contract.pressKeys:Show()
end)

Stub.done("press")
