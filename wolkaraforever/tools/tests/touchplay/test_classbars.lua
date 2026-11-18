-- Task 9: class bars: stance and form buttons, the pet bar, Leave for vehicles, the form caption
-- (rules 3 and 5); mockups 21, 22, 73.
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

local BATTLE, DEFENSIVE, BERSERKER = 2457, 71, 2458
local BEAR, AQUATIC, CAT, TRAVEL = 5487, 1066, 768, 783

-- A game session with the add-on loaded and laid out; `forms` is the class's list.
local function setup(forms, class)
    Stub.reset(); Stub.loadAll()
    Stub.spellNames[BATTLE], Stub.spellNames[DEFENSIVE], Stub.spellNames[BERSERKER] = "Battle Stance", "Defensive Stance", "Berserker Stance"
    Stub.spellNames[BEAR], Stub.spellNames[AQUATIC], Stub.spellNames[CAT], Stub.spellNames[TRAVEL] =
        "Bear Form", "Aquatic Form", "Cat Form", "Travel Form"
    Stub.playerClass = class or "WARRIOR"
    Stub.forms = forms or {}
    Stub.login()
    return ns.ClassBars
end

local function warrior() return setup({ { spell = BATTLE }, { spell = DEFENSIVE }, { spell = BERSERKER } }) end
local function druid()
    return setup({ { spell = BEAR }, { spell = AQUATIC, castable = false }, { spell = CAT }, { spell = TRAVEL } }, "DRUID")
end

local function gold(c) return c and c[1] == 1 and near(c[2], 0.82) and c[3] == 0 end

-- ---------------------------------------------------------------------------------------
-- Stance and form buttons

T("stance_buttons_match_forms", function()
    local C = warrior()
    assert(#C.stance == 10)
    for i = 1, 10 do
        local b = C.stance[i]
        assert(b:GetName() == "TouchPlayStance" .. i and Stub.inherits(b, "SecureActionButtonTemplate"))
        assert(b:IsShown() == (i <= 3), "button " .. i)
    end
    assert(C.stance[1]:GetAttribute("*type1") == "spell" and C.stance[1]:GetAttribute("spell") == BATTLE)
    assert(C.stance[3]:GetAttribute("spell") == BERSERKER)
    Stub.setActiveForm(1)
    assert(C.stance[1].active and gold(C.stance[1].art.backdropBorderColor), "the stance you are in is bordered in gold")
    assert(not C.stance[2].active and not gold(C.stance[2].art.backdropBorderColor))
    Stub.setActiveForm(3)
    assert(C.stance[3].active and not C.stance[1].active and not gold(C.stance[1].art.backdropBorderColor))
end)

T("stance_row_sits_left_of_the_page_boxes_growing_leftward", function()
    local C = warrior()
    -- right edge fixed at x 1140 (page box 1 starts at 1156), centred on the boxes' height (566 + 21)
    -- three buttons span 3 * 52 + 2 * 10 = 176: x from 964, button 1 leftmost
    for i = 1, 3 do
        local x, y = Stub.centre(C.stance[i])
        assert(near(x, 964 + 26 + (i - 1) * 62), "x " .. i .. " " .. x)
        assert(near(y, 566 + 21), "y " .. y)
        assert(C.stance[i]:GetWidth() == 52 and C.stance[i]:GetHeight() == 52)
        assert(C.stance[i].touchAnchor.corner == "BR")
    end
    local x3 = Stub.centre(C.stance[3]); assert(near(x3 + 26, 1140), "the right edge stays at 1140")
    C = druid()
    local x1, x4 = Stub.centre(C.stance[1]), Stub.centre(C.stance[4])
    assert(near(x4 + 26, 1140) and near(x4 - x1, 3 * 62), "four buttons: still right-edged at 1140")
    assert(x1 < Stub.centre(setup({ { spell = BATTLE } }).stance[1]) , "more forms reach further left")
end)

T("stance_row_stays_clear_of_the_caption_and_the_page_boxes", function()
    local C = druid()
    local cap = C.caption.touchAnchor
    for i = 1, 4 do
        local a = C.stance[i].touchAnchor
        assert(a.x + a.w <= 1140 and a.x + a.w < 1156, "left of the page boxes")
        assert(a.y >= cap.y + cap.h, "below the caption")
    end
    C = setup({ {spell=1},{spell=2},{spell=3},{spell=4},{spell=5},{spell=6},{spell=7},{spell=8},{spell=9},{spell=10} })
    local a = C.stance[1].touchAnchor
    assert(a.x == 1140 - (10 * 52 + 9 * 10) and a.x > 0, "ten forms still fit on the screen")
end)

T("stance_unusable_form_is_grey_and_the_picture_comes_from_the_game", function()
    local C = druid()
    assert(C.stance[2].icon.texture == "formicon2")
    local grey, white = C.stance[2].icon.vertex, C.stance[1].icon.vertex
    assert(grey and grey[1] < 0.5 and grey[2] < 0.5, "Aquatic cannot be used here")
    assert(white and white[1] == 1, "the others stay in full colour")
    Stub.forms[2].castable = true; Stub.fire("UPDATE_SHAPESHIFT_USABLE")
    assert(C.stance[2].icon.vertex[1] == 1, "it lights up when it can be used")
end)

T("stance_tap_casts_the_form_and_a_hold_never_does", function()
    local C = warrior()
    for _, b in ipairs(C.stance) do assert(b:GetAttribute("type") == nil and b:GetAttribute("type2") == nil) end
    Stub.click(C.stance[2], "LeftButton")
    assert(Stub.lastSpell == DEFENSIVE and Stub.calls.CastSpell == 1)
    Stub.click(C.stance[2], "RightButton")
    assert(Stub.calls.CastSpell == 1, "a hold casts nothing")
    assert(Stub.calls.UseAction == 0)
end)

T("stance_hold_asks_the_card_for_the_spell_and_never_casts", function()
    local C = warrior(); local asked = {}
    ns.InfoCard = { Show = function(subject, button) asked[#asked + 1] = { subject = subject, button = button } end }
    Stub.click(C.stance[2], "RightButton")
    assert(#asked == 1 and asked[1].subject.kind == "spell" and asked[1].subject.spellID == DEFENSIVE)
    assert(asked[1].button == C.stance[2], "the card is told which frame was held")
    assert(Stub.calls.CastSpell == 0 and Stub.calls.UseAction == 0, "a hold casts nothing")
    Stub.click(C.stance[2], "LeftButton"); assert(#asked == 1, "a tap does not open the card")
end)

T("stance_hold_opens_the_real_card_with_the_spells_tooltip", function()
    local C = warrior(); Stub.click(C.stance[1], "RightButton")
    assert(ns.InfoCard.IsShown() and ns.InfoCard.Title() == "Battle Stance")
    assert(ns.InfoCard.Button("Close") and not ns.InfoCard.Button("Autocast: on"))
    assert(Stub.calls.CastSpell == 0)
    Stub.combat(true); Stub.click(C.stance[2], "RightButton")
    assert(ns.InfoCard.Title() == "Defensive Stance" and not ns.paused, ns.lastError)
end)

T("stance_bar_hidden_in_vehicle_override_and_possess_by_driver", function()
    local C = warrior()
    local driver = Stub.stateDrivers[C.stanceBar].visibility
    assert(driver == "[vehicleui][overridebar][possessbar] hide; show", driver)
    Stub.applyDrivers(); assert(C.stanceBar:IsShown())
    Stub.setVehicle(true); Stub.applyDrivers(); assert(not C.stanceBar:IsShown())
    Stub.setVehicle(false); Stub.setPossess(true); Stub.applyDrivers(); assert(not C.stanceBar:IsShown())
    Stub.setPossess(false); Stub.applyDrivers(); assert(C.stanceBar:IsShown())
end)

T("stance_state_changes_in_a_fight_need_no_layout", function()
    local C = warrior(); Stub.combat(true)
    Stub.setActiveForm(2)
    assert(C.stance[2].active and not ns.paused, ns.lastError)
    Stub.click(C.stance[3], "LeftButton"); assert(Stub.lastSpell == BERSERKER, "a tap works in a fight")
end)

T("layout_changes_wait_for_fight_end", function()
    local C = warrior(); Stub.combat(true)
    Stub.forms[4] = { spell = 9999 }
    Stub.fire("UPDATE_SHAPESHIFT_FORMS")
    assert(not ns.paused, ns.lastError)
    assert(not C.stance[4]:IsShown() and C.stance[4]:GetAttribute("spell") == nil, "nothing changes in a fight")
    local x1 = Stub.centre(C.stance[1]); assert(near(x1, 964 + 26), "nor does anything move")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused, ns.lastError)
    assert(C.stance[4]:IsShown() and C.stance[4]:GetAttribute("spell") == 9999)
    local x = Stub.centre(C.stance[1]); assert(near(x, 1140 - 238 + 26), "the row has grown leftward to four")
    local x4 = Stub.centre(C.stance[4]); assert(near(x4 + 26, 1140))
end)

T("a_class_with_no_forms_shows_no_stance_button", function()
    local C = setup({})
    for _, b in ipairs(C.stance) do assert(not b:IsShown()) end
end)

-- ---------------------------------------------------------------------------------------
-- The pet bar

-- iPad run 1: the game's small pet button is made for 30 units; its icon had no anchors.
T("pet_buttons_icon_and_frame_fill_the_box", function()
    local C = warrior()
    for i, b in ipairs(C.pet) do
        assert(#b.icon.points == 1 and b.icon.points[1][1] == "ALL" and b.icon.points[1][2] == b, "icon " .. i .. " fills its button")
        assert(b.icon.removedMask == b.IconMask)
        assert(b:GetNormalTexture().texture == "Interface\\Buttons\\UI-Quickslot2")
        assert(b.AutoCastOverlay.width == 52 and b.AutoCastOverlay.height == 52, "the autocast shine fits the box")
        assert(#b:GetHighlightTexture().points == 1 and b:GetHighlightTexture().points[1][2] == b)
    end
    assert(not ns.paused, ns.lastError)
end)

T("pet_bar_only_with_pet", function()
    local C = setup()
    assert(#C.pet == 10)
    local driver = Stub.stateDrivers[C.petBar].visibility
    assert(driver and driver:find("@pet", 1, true) and driver:find("exists", 1, true) and driver:find("nodead", 1, true), driver)
    Stub.applyDrivers(); assert(not C.petBar:IsShown(), "no pet: no bar")
    Stub.setPet(true); Stub.applyDrivers(); assert(C.petBar:IsShown())
    Stub.setPet(false); Stub.applyDrivers(); assert(not C.petBar:IsShown())
end)

T("pet_bar_hides_in_vehicle_override_and_possess_so_leave_has_the_row", function()
    local C = setup(); Stub.setPet(true); Stub.applyDrivers(); assert(C.petBar:IsShown())
    Stub.setVehicle(true); Stub.applyDrivers(); assert(not C.petBar:IsShown() and C.leave:IsShown())
    Stub.setVehicle(false); Stub.setOverride(true); Stub.applyDrivers(); assert(not C.petBar:IsShown())
    Stub.setOverride(false); Stub.setPossess(true); Stub.applyDrivers(); assert(not C.petBar:IsShown())
    Stub.setPossess(false); Stub.applyDrivers(); assert(C.petBar:IsShown(), "the pet bar comes back")
end)

T("pet_dead_hides_the_bar_by_driver_not_by_clear_buttons", function()
    local C = setup(); Stub.setPetAction(1, { name = "Attack", texture = "x" })
    Stub.setPet(true); Stub.applyDrivers(); assert(C.petBar:IsShown())
    Stub.combat(true)
    Stub.units.pet.dead = true; Stub.fire("PET_BAR_UPDATE"); Stub.applyDrivers()
    assert(not ns.paused, ns.lastError)
    assert(not C.petBar:IsShown() and C.petBar:GetAlpha() == 1, "hidden, not left invisible and tappable")
    Stub.units.pet.dead = false; Stub.applyDrivers()
    assert(C.petBar:IsShown(), "a revived pet brings it back")
end)

T("pet_buttons_are_the_games_pet_buttons_on_slots_1_to_10", function()
    local C = setup()
    for i, b in ipairs(C.pet) do
        assert(b:GetName() == "TouchPlayPet" .. i and Stub.inherits(b, "PetActionButtonTemplate"))
        assert(b:GetID() == i and b:GetWidth() == 52 and b:GetHeight() == 52)
        assert(b.clicks and b.clicks[1] == "AnyUp")
        local w, h = b:GetHitRectSize(); assert(w >= 44 and h >= 44)
        local x, y = Stub.centre(b)
        assert(near(x, 275 + 26 + (i - 1) * 62) and near(y, 820 + 26), "slot " .. i)
    end
    -- a row of ten: 10 * 52 + 9 * 10 = 610 wide, centred on the chat strip (580)
    local first, last = Stub.centre(C.pet[1]), Stub.centre(C.pet[10])
    assert(near((first + last) / 2, 580))
end)

T("pet_buttons_show_the_pet_actions_and_which_is_on", function()
    local C = setup()
    PET_ATTACK_TEXTURE = "Interface\\Icons\\Ability_GhoulFrenzy"
    PET_DEFENSIVE_TEXTURE = "Interface\\Icons\\Ability_Defend"
    Stub.setPetAction(1, { name = "PET_ACTION_ATTACK", texture = "PET_ATTACK_TEXTURE", isToken = true })
    Stub.setPetAction(4, { name = "Bite", texture = "biteicon", active = true, autoCastAllowed = true, autoCastEnabled = true })
    Stub.setPetAction(9, { name = "Defensive", texture = "PET_DEFENSIVE_TEXTURE", isToken = true, active = true })
    assert(C.pet[9].icon.texture == "Interface\\Icons\\Ability_Defend" and C.pet[9]:GetChecked() == true, "the stance in use is marked")
    Stub.setPetAction(5, { name = "Claw", texture = "clawicon", usable = false })
    assert(C.pet[4].icon.texture == "biteicon" and C.pet[4]:GetChecked() == true, "the active one is marked")
    assert(C.pet[4].AutoCastOverlay.shown == true and C.pet[4].AutoCastOverlay.autoCastEnabled == true)
    assert(C.pet[1].icon.texture == "Interface\\Icons\\Ability_GhoulFrenzy", "a token names a global")
    assert(not C.pet[1]:GetChecked())
    assert(C.pet[5].icon.vertex[1] < 0.5, "cannot use it now: grey")
    assert(C.pet[4].icon.vertex[1] == 1)
    assert(C.pet[7].alpha < 1, "an empty slot stays as a quiet frame")
    Stub.petActions[4].active = false; Stub.fire("PET_BAR_UPDATE")
    assert(C.pet[4]:GetChecked() == false)
end)

T("pet_tap_commands_the_pet", function()
    local C = setup()
    Stub.setPetAction(4, { name = "Bite", texture = "biteicon" })
    Stub.click(C.pet[4], "LeftButton")
    assert(Stub.lastPetAction == 4 and Stub.calls.CastPetAction == 1)
    assert(Stub.calls.UseAction == 0 and Stub.calls.CastSpell == 0)
end)

T("pet_hold_does_not_toggle_autocast_by_itself_and_asks_the_card", function()
    local C = setup(); local asked = {}
    Stub.setPetAction(4, { name = "Bite", texture = "biteicon", autoCastAllowed = true })
    ns.InfoCard = { Show = function(subject, button) asked[#asked + 1] = { subject = subject, button = button } end }
    local wrap = C.pet[4].wraps and C.pet[4].wraps.OnClick and C.pet[4].wraps.OnClick[1]
    assert(wrap and wrap.pre:find("RightButton", 1, true) and wrap.pre:find("return false", 1, true), "the game's right click is held back")
    Stub.click(C.pet[4], "RightButton")
    assert(Stub.calls.TogglePetAutocast == 0 and Stub.calls.CastPetAction == 0, "a hold neither toggles nor commands")
    assert(#asked == 1 and asked[1].subject.kind == "petAction" and asked[1].subject.index == 4 and asked[1].button == C.pet[4])
    Stub.click(C.pet[4], "LeftButton"); assert(#asked == 1 and Stub.calls.CastPetAction == 1)
    Stub.click(C.pet[7], "RightButton"); assert(#asked == 1, "an empty slot has nothing to show")
end)

T("pet_hold_card_offers_autocast_as_a_secure_macro_set_out_of_combat", function()
    local C = setup()
    Stub.setPetAction(4, { name = "Bite", texture = "biteicon", autoCastAllowed = true, autoCastEnabled = true })
    Stub.setPetAction(1, { name = "Attack", texture = "atticon" })
    Stub.click(C.pet[4], "RightButton")
    assert(ns.InfoCard.IsShown() and ns.InfoCard.Title() == "Bite")
    assert(ns.InfoCard.Button("Autocast: on") and ns.InfoCard.Button("Close"))
    local secure = ns.InfoCard.secureButton
    assert(Stub.inherits(secure, "SecureActionButtonTemplate") and secure:GetAttribute("type") == "macro")
    assert(secure:GetAttribute("macrotext") == "/petautocasttoggle Bite" and secure:IsVisible())
    Stub.click(secure)
    assert(Stub.lastMacro == "/petautocasttoggle Bite" and Stub.calls.TogglePetAutocast == 0)
    assert(not ns.InfoCard.IsShown(), "the card closes after the toggle")
    -- off reads "Autocast: off"; an action that cannot autocast has no such button
    Stub.petActions[4].autoCastEnabled = false; Stub.click(C.pet[4], "RightButton")
    assert(ns.InfoCard.Button("Autocast: off") and not ns.InfoCard.Button("Autocast: on"))
    Stub.click(C.pet[1], "RightButton")
    assert(ns.InfoCard.Title() == "Attack" and not ns.InfoCard.Button("Autocast: on") and not ns.InfoCard.Button("Autocast: off"))
    assert(not secure:IsVisible(), "no secure button when there is nothing to toggle")
end)

T("pet_hold_in_a_fight_shows_the_card_with_autocast_greyed", function()
    local C = setup()
    Stub.setPetAction(4, { name = "Bite", texture = "biteicon", autoCastAllowed = true })
    Stub.combat(true); Stub.click(C.pet[4], "RightButton")
    assert(not ns.paused, ns.lastError)
    assert(ns.InfoCard.IsShown() and ns.InfoCard.Button("Autocast: off"))
    assert(ns.InfoCard.Button("Autocast: off"):IsEnabled() == false, "greyed in a fight")
    assert(not ns.InfoCard.secureButton:IsVisible(), "its secure macro cannot be set in a fight")
    assert(Stub.calls.TogglePetAutocast == 0 and Stub.calls.CastPetAction == 0)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ns.InfoCard.secureButton:IsVisible() and ns.InfoCard.secureButton:GetAttribute("macrotext") == "/petautocasttoggle Bite")
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(not ns.InfoCard.secureButton:IsVisible(), "taken away again when a fight starts")
end)

T("pet_bar_updates_in_a_fight_without_pausing", function()
    local C = setup(); Stub.combat(true)
    Stub.setPetAction(2, { name = "Follow", texture = "followicon", active = true })
    assert(C.pet[2]:GetChecked() == true and not ns.paused, ns.lastError)
    Stub.click(C.pet[2]); assert(Stub.lastPetAction == 2, "a tap works in a fight")
end)

T("pet_unhappy_shows_the_hunters_mood_only_when_mad", function()
    local C = setup(); Stub.setPet(true); Stub.applyDrivers()
    assert(not C.mood:IsShown(), "no mood known: nothing shown")
    Stub.setPetHappiness(1); assert(C.mood:IsShown() and C.mood.text:GetText() == ns.L["classbars.unhappy"])
    assert(ns.L["classbars.unhappy"] == "Unhappy \194\183 deals less damage")
    Stub.setPetHappiness(3); assert(not C.mood:IsShown())
    Stub.setPetHappiness(1); Stub.hunterPet = false; Stub.fire("UNIT_HAPPINESS", "pet")
    assert(not C.mood:IsShown(), "only a hunter's pet has a mood")
end)

T("pet_mood_guarded_when_the_game_has_no_happiness", function()
    local C = setup(); C_PetInfo = nil; GetPetHappiness = nil
    Stub.setPet(true); Stub.fire("UNIT_HAPPINESS", "pet")
    assert(not ns.paused and not C.mood:IsShown(), ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Leave

T("leave_vehicle_shown_in_vehicle", function()
    local C = setup()
    local leave = C.leave
    assert(leave:GetName() == "TouchPlayLeaveVehicle" and Stub.inherits(leave, "SecureActionButtonTemplate"))
    assert(leave:GetAttribute("type") == "macro" and leave:GetAttribute("macrotext") == "/leavevehicle")
    assert(Stub.stateDrivers[leave].visibility == "[vehicleui][overridebar] show; hide")
    Stub.applyDrivers(); assert(not leave:IsShown())
    Stub.setVehicle(true); Stub.applyDrivers(); assert(leave:IsShown())
    Stub.setVehicle(false); Stub.applyDrivers(); assert(not leave:IsShown())
    Stub.setOverride(true); Stub.applyDrivers(); assert(leave:IsShown(), "an override bar has it too")
end)

T("leave_vehicle_taps_in_a_fight_and_is_a_44_unit_target", function()
    local C = setup(); Stub.setVehicle(true); Stub.applyDrivers(); Stub.combat(true)
    Stub.click(C.leave); assert(Stub.lastMacro == "/leavevehicle" and not ns.paused)
    local w, h = C.leave:GetHitRectSize(); assert(w >= 44 and h >= 44)
    assert(C.leave:GetWidth() == 170 and C.leave:GetHeight() == 52)
    local x, y = Stub.centre(C.leave); assert(near(x, 580) and near(y, 820 + 26))
end)

-- ---------------------------------------------------------------------------------------
-- The form caption (mockup 73)

T("caption_names_the_form_and_prowling_for_a_druid", function()
    local C = druid()
    assert(not C.caption:IsShown())
    Stub.setActiveForm(3); assert(C.caption:IsShown() and C.caption.text:GetText() == "Cat Form")
    Stub.setStealth(true); assert(C.caption.text:GetText() == "Cat Form \194\183 Prowling")
    Stub.setStealth(false); assert(C.caption.text:GetText() == "Cat Form")
    Stub.setActiveForm(0); assert(not C.caption:IsShown(), "no form, no stealth: nothing")
end)

T("caption_for_a_rogue_in_stealth_and_for_stealth_without_a_form", function()
    local C = setup({ { spell = 1784 } }, "ROGUE")
    Stub.spellNames[1784] = "Stealth"
    Stub.setActiveForm(1); Stub.setStealth(true)
    assert(C.caption.text:GetText() == "Stealth", "the form already says it")
    Stub.setActiveForm(0)
    assert(C.caption:IsShown() and C.caption.text:GetText() == "Stealthed")
    Stub.setStealth(false); assert(not C.caption:IsShown())
end)

T("caption_sits_above_the_page_boxes_in_gold_and_changes_in_a_fight", function()
    local C = druid()
    local a = C.caption.touchAnchor
    assert(a.corner == "BR" and a.x == 1100 and a.y == 532 and a.w == 220)
    local c = C.caption.text.textColor; assert(gold(c))
    assert(C.caption.text.font == "Fonts\\FRIZQT__.TTF" and C.caption.text.fontSize == 15)
    Stub.combat(true); Stub.setActiveForm(3); Stub.setStealth(true)
    assert(not ns.paused and C.caption.text:GetText() == "Cat Form \194\183 Prowling", ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- The rules

T("secret_values_never_touched", function()
    local C = druid(); Stub.setActiveForm(3)
    Stub.setPetAction(1, { name = "Attack", texture = "x" }); Stub.setPet(true); Stub.applyDrivers()
    Stub.secretCooldowns(true)
    Stub.fire("UPDATE_SHAPESHIFT_COOLDOWN"); Stub.fire("PET_BAR_UPDATE_COOLDOWN"); Stub.fire("PET_BAR_UPDATE")
    Stub.fire("UPDATE_SHAPESHIFT_FORM")
    assert(not ns.paused, ns.lastError)
    Stub.secretUnits(true); Stub.fire("PET_BAR_UPDATE"); assert(not ns.paused, ns.lastError)
end)

-- 16 Nov (pet classes): the stance row, the pet row and Leave are in the contract now (were "plain taps" in v1);
-- the full cases are in test_petclasses.
T("contract_areas_for_the_class_bars", function()
    local C = druid()
    local text = ns.Contract.Write()
    for i = 1, 4 do assert(text:find("|stance" .. i .. ",", 1, true), "stance" .. i) end
    assert(not text:find("stance5,", 1, true) and not text:find("|pet", 1, true), "four forms, no pet row")
    assert(text:find("|leave,", 1, true))
end)

T("loads_before_the_contract", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") then order[#order + 1] = line end
    end
    local classbars, contract
    for i, name in ipairs(order) do
        if name == "ClassBars.lua" then classbars = i elseif name == "Contract.lua" then contract = i end
    end
    assert(classbars and contract and classbars < contract, "R10: ClassBars.lua before Contract.lua")
end)

T("every_word_comes_from_the_text_table", function()
    local C = setup()
    assert(C.leave.face.label:GetText() == ns.L["classbars.leave"] and ns.L["classbars.leave"] == "Leave")
    assert(ns.L["classbars.prowling"] == "Prowling" and ns.L["classbars.stealthed"] == "Stealthed")
    assert(not (TouchPlayDB.missingText and #TouchPlayDB.missingText > 0))
end)

-- The pet's flags come through a unit event for "pet" only, not the global UNIT_FLAGS for every unit.
T("pet_flags_are_a_unit_event_for_the_pet", function()
    setup()
    for _, f in ipairs(Stub.eventFrames("UNIT_FLAGS")) do
        assert(f.unitFilter and f.unitFilter.UNIT_FLAGS, "a frame takes UNIT_FLAGS for every unit")
    end
    local pet
    for _, f in ipairs(Stub.eventFrames("UNIT_FLAGS")) do if f.unitFilter.UNIT_FLAGS.pet then pet = f end end
    assert(pet, "one frame listens for the pet")
end)

Stub.done("classbars")
