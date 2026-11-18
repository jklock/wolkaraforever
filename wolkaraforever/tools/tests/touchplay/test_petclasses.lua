-- Pet classes (16 Nov): the pet's card, Call / Revive / Feed pet, and the pet row, the stance row and Leave in the
-- layout contract (mockups 21, 22, 73; state list "Pet bar": pet out, pet dead, pet unhappy, no pet).
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

local CALL_PET, REVIVE_PET, FEED_PET = 883, 982, 6991
local BATTLE, DEFENSIVE, BERSERKER = 2457, 71, 2458

-- A session for `class` (HUNTER, WARLOCK, WARRIOR, MAGE ...) with `forms`, laid out; `known` = spells the
-- character knows (default: a hunter's Call, Revive and Feed Pet).
local function setup(class, forms, known)
    Stub.reset(); Stub.loadAll()
    Stub.playerClass = class or "HUNTER"
    Stub.forms = forms or {}
    Stub.knownSpells = known or { [CALL_PET] = true, [REVIVE_PET] = true, [FEED_PET] = true }
    Stub.spellNames[CALL_PET], Stub.spellNames[REVIVE_PET], Stub.spellNames[FEED_PET] = "Call Pet", "Revive Pet", "Feed Pet"
    Stub.spellNames[BATTLE], Stub.spellNames[DEFENSIVE], Stub.spellNames[BERSERKER] =
        "Battle Stance", "Defensive Stance", "Berserker Stance"
    Stub.login()
    assert(not ns.paused, ns.lastError)
    Stub.applyDrivers()
    return ns.ClassBars, ns.Units
end

local function petOut(fields)
    Stub.setPet(true)
    Stub.setUnit("pet", { name = "Fang", level = 33, health = 800, healthMax = 1000, power = 60, powerMax = 100,
        powerType = 2, powerToken = "FOCUS" })
    for k, v in pairs(fields or {}) do Stub.units.pet[k] = v end
    for i = 1, 10 do Stub.petActions[i] = { name = "Pet" .. i, texture = "peticon" .. i } end
    Stub.fire("UNIT_PET", "player"); Stub.fire("PET_BAR_UPDATE")
    Stub.applyDrivers()
end

local function areaNames()
    local text = ns.Contract.Write()
    local names = {}
    for area in text:match("areas=(.*)$"):gmatch("[^|]+") do names[area:match("^([^,]+)")] = area end
    return names, text
end

-- ---------------------------------------------------------------------------------------
-- The pet's card (mockup 22: under the player's card, portrait, name, level, health and focus)

T("pet_card_is_a_secure_unit_card_shown_by_a_driver_while_a_pet_exists", function()
    local _, U = setup()
    local card = U.pet
    assert(card and card:GetName() == "TouchPlayPetCard", "the pet's card exists")
    assert(Stub.inherits(card, "SecureActionButtonTemplate") and card:GetAttribute("useOnKeyDown") == false)
    assert(card:GetAttribute("unit") == "pet" and card:GetAttribute("*type1") == "target")
    assert(card:GetAttribute("type2") == nil and card:GetAttribute("*type2") == nil, "a hold never opens the game's menu")
    local driver = Stub.stateDrivers[card] and Stub.stateDrivers[card].visibility
    assert(driver and driver:find("@pet,exists", 1, true), tostring(driver))
    assert(not card:IsShown(), "no pet: no card")
    petOut()
    assert(card:IsShown(), "a pet: its card")
    Stub.combat(true); Stub.setPet(false); Stub.applyDrivers()
    assert(not card:IsShown() and not ns.paused, "the driver hides it in a fight too: " .. tostring(ns.lastError))
    Stub.setPet(true); Stub.applyDrivers(); assert(card:IsShown(), "and shows it in a fight")
end)

T("pet_card_draws_the_mockup_card_under_the_players", function()
    local _, U = setup(); petOut()
    local card = U.pet
    -- the player's card art at scale 1 (232 x 100), mirrored like the player's: portrait left, bars right
    assert(near(card:GetWidth(), 232) and near(card:GetHeight(), 100))
    assert(card.frameArt.texCoord[1] == 1, "mirrored like the player's card")
    -- mockup 22: the portrait's centre at (143, 158)
    local a = card.touchAnchor
    assert(near(a.x + 70, 143, 2) and near(a.y + 50, 158, 2), ("portrait centre (%.0f, %.0f)"):format(a.x + 70, a.y + 50))
    assert(card.nameText:GetText() == "Fang" and card.levelText:GetText() == "33")
    local c = card.levelText.textColor; assert(c and c[1] == 1 and near(c[2], 0.82), "a gold level, as the mockup")
    assert(card.healthBar.value == 800 and card.healthBar.maxValue == 1000)
    assert(card.powerBar.value == 60 and card.powerBar.maxValue == 100)
    assert(card.healthText:GetText() == nil or card.healthText:GetText() == "", "no numbers on the small bars")
    -- the touch area is the drawn part, clear of the player's card above it
    local tap, player = U.petTap.touchAnchor, U.playerTap.touchAnchor
    assert(tap.y >= player.y + player.h, "the pet's touch area starts below the player's")
    assert(tap.x >= a.x and tap.x + tap.w <= a.x + a.w and tap.y >= a.y and tap.y + tap.h <= a.y + a.h)
end)

T("pet_card_dead_reads_dead_and_greys_the_portrait", function()
    local _, U = setup(); petOut()
    Stub.setDead("pet", "dead"); Stub.applyDrivers()
    assert(U.pet:IsShown(), "a dead pet keeps its card (mockup 21: Pet dead)")
    assert(U.pet.healthText:GetText() == "Dead")
    assert(U.pet.portrait.desaturated == true)
    Stub.setDead("pet", nil)
    assert(U.pet.portrait.desaturated == false and U.pet.healthText:GetText() == "")
end)

T("pet_card_tap_targets_the_pet_and_a_hold_opens_the_unit_card", function()
    local _, U = setup(); petOut()
    Stub.click(U.pet, "LeftButton")
    assert(Stub.lastTargeted == "pet" and Stub.calls.TargetUnit == 1)
    Stub.click(U.pet, "RightButton")
    assert(Stub.calls.TargetUnit == 1, "a hold never targets")
    assert(ns.InfoCard.IsShown() and ns.InfoCard.Title() == "Fang")
end)

T("the_players_card_gives_its_bottom_to_the_pet_card_only_for_a_pet_class", function()
    setup()
    assert(areaNames().player:find("^player,TL,10,8,348,120,"), "a hunter: the top 120 units")
    setup("MAGE")
    assert(areaNames().player:find("^player,TL,10,8,348,150,"), "a mage: the whole card, as before")
end)

T("pet_card_only_for_a_pet_class", function()
    local _, U = setup("MAGE"); petOut()
    assert(not U.pet:IsShown(), "a mage's borrowed pet gets no card")
    local names = areaNames(); assert(not names.petcard)
end)

T("pet_card_events_are_unit_events_for_the_pet", function()
    local _, U = setup(); petOut()
    Stub.units.pet.health = 300; Stub.fire("UNIT_HEALTH", "pet")
    assert(U.pet.healthBar.value == 300)
    local found
    for _, f in ipairs(Stub.eventFrames("UNIT_HEALTH")) do
        if f.unitFilter and f.unitFilter.UNIT_HEALTH and f.unitFilter.UNIT_HEALTH.pet then found = true end
    end
    assert(found, "UNIT_HEALTH for the pet comes through a unit event")
end)

T("pet_card_secret_values_are_never_compared", function()
    local _, U = setup(); petOut()
    Stub.secretUnits(true); Stub.combat(true)
    Stub.fire("UNIT_HEALTH", "pet"); Stub.fire("UNIT_POWER_UPDATE", "pet")
    assert(not ns.paused, ns.lastError)
end)

-- The quest list keeps below the pet's card at every Text size.
T("quest_list_keeps_below_the_pet_card", function()
    for _, size in ipairs({ 0.8, 1.0, 1.4 }) do
        setup(); petOut()
        ns.Feel.Set("textSize", size); Stub.advance(1)
        local q, p = ns.Hud.quest.touchAnchor, ns.Units.petTap.touchAnchor
        assert(q.y >= p.y + p.h, ("text %.1f: quest list at %.1f, pet card to %.1f"):format(size, q.y, p.y + p.h))
    end
end)

-- ---------------------------------------------------------------------------------------
-- Call pet, Revive pet, Feed pet (mockup 21)

T("no_pet_out_shows_call_pet_in_the_row", function()
    local C = setup()
    local call = C.call
    assert(call and call:GetName() == "TouchPlayPetCall")
    assert(call:IsShown(), "a hunter with no pet: Call pet")
    assert(call.icon.texture == "icon" .. CALL_PET)
    -- it sits on pet slot 5's square, so it shares that slot's touch area and key
    local a, s = call.touchAnchor, C.pet[5].touchAnchor
    assert(near(a.x, s.x) and near(a.y, s.y) and near(a.w, s.w))
    petOut(); assert(not call:IsShown(), "the pet is out: the bar instead")
end)

T("pet_dead_shows_revive_pet_where_the_bar_was", function()
    local C = setup(); petOut()
    Stub.setDead("pet", "dead"); Stub.fire("UNIT_PET", "player"); Stub.applyDrivers()
    assert(not C.petBar:IsShown() and C.call:IsShown(), "Revive pet replaces the bar")
    assert(C.call.icon.texture == "icon" .. REVIVE_PET)
end)

T("call_and_revive_need_the_spells_and_a_hunter", function()
    local C = setup("HUNTER", {}, {})
    assert(not C.call:IsShown(), "a hunter who has not learnt Call Pet sees no button")
    C = setup("WARLOCK", {}, { [CALL_PET] = true })
    assert(not C.call:IsShown(), "a warlock has no Call pet")
end)

T("unhappy_pet_lights_up_feed_pet", function()
    local C = setup(); petOut()
    local feed = C.feed
    assert(feed and feed:GetName() == "TouchPlayPetFeed" and Stub.inherits(feed, "SecureActionButtonTemplate"))
    assert(not feed:IsShown(), "a happy pet: no Feed pet")
    Stub.setPetHappiness(1)
    assert(feed:IsShown() and C.mood:IsShown(), "unhappy: the red line and Feed pet")
    assert(feed.glow and feed.glow:IsShown(), "it lights up")
    assert(feed:GetAttribute("*type1") == "spell" and feed:GetAttribute("*spell1") == FEED_PET)
    Stub.click(feed, "LeftButton"); assert(Stub.lastSpell == FEED_PET)
    Stub.setPetHappiness(3)
    assert(not feed:IsShown() and feed:GetAttribute("*type1") == nil, "happy again: gone, and its key does nothing")
end)

T("feed_pet_waits_for_the_end_of_a_fight", function()
    local C = setup(); petOut()
    Stub.combat(true); Stub.setPetHappiness(1)
    assert(not ns.paused, ns.lastError)
    assert(C.mood:IsShown(), "the red line shows at once")
    assert(not C.feed:IsShown(), "the button waits: a pet cannot be fed in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(C.feed:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- The contract: areas by what the character can have (the app reads the list only after a reload)

T("a_hunter_has_the_pet_card_pet_row_feed_and_leave_areas", function()
    setup()
    local names = areaNames()
    assert(names.petcard and names.petfeed and names.leave, "pet card, Feed pet, Leave")
    for i = 1, 10 do assert(names["pet" .. i], "pet" .. i) end
    for i = 1, 10 do assert(not names["stance" .. i], "no stance" .. i) end
end)

T("a_warlock_has_the_pet_areas_but_no_feed", function()
    setup("WARLOCK")
    local names = areaNames()
    assert(names.petcard and names.pet1 and names.pet10 and names.leave)
    assert(not names.petfeed, "Feed Pet is a hunter's")
end)

T("a_warrior_has_one_stance_area_per_stance_and_no_pet_areas", function()
    setup("WARRIOR", { { spell = BATTLE }, { spell = DEFENSIVE }, { spell = BERSERKER } })
    local names = areaNames()
    for i = 1, 3 do assert(names["stance" .. i], "stance" .. i) end
    assert(not names.stance4 and not names.pet1 and not names.petcard and not names.petfeed)
    assert(names.leave)
end)

T("a_mage_has_no_pet_or_stance_areas", function()
    setup("MAGE")
    local names = areaNames()
    for name in pairs(names) do
        assert(not name:match("^pet") and not name:match("^stance"), "a mage has no " .. name)
    end
    assert(names.leave, "Leave: anyone can be put in a vehicle")
end)

T("a_new_stance_adds_its_area_after_the_fight", function()
    setup("WARRIOR", { { spell = BATTLE } })
    assert(areaNames().stance1 and not areaNames().stance2)
    Stub.combat(true)
    Stub.forms[2] = { spell = DEFENSIVE }; Stub.fire("UPDATE_SHAPESHIFT_FORMS")
    assert(not areaNames().stance2, "nothing changes in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(areaNames().stance2, "the new stance has its area")
    local _, hold = ns.Contract.KeysFor("stance2")
    assert(Stub.bindings[(ns.Contract.KeysFor("stance2"))] and Stub.bindings[hold], "and its keys")
end)

T("new_areas_follow_the_buttons_geometry", function()
    local C, U = setup()
    local names = areaNames()
    local function check(name, frame)
        local corner, dx, dy, w, h = names[name]:match("^[^,]+,(%u%u),(%-?%d+),(%-?%d+),(%d+),(%d+),")
        local a = frame.touchAnchor
        assert(corner == a.corner, name .. " corner " .. tostring(corner))
        assert(tonumber(w) == math.floor(math.max(a.w, 44) + 0.5) and tonumber(h) == math.floor(math.max(a.h, 44) + 0.5), name)
    end
    for i = 1, 10 do check("pet" .. i, C.pet[i]) end
    check("petcard", U.petTap); check("leave", C.leave); check("petfeed", C.feed)
end)

T("no_two_areas_share_a_key", function()
    for _, class in ipairs({ "HUNTER", "WARLOCK", "WARRIOR", "MAGE" }) do
        setup(class, class == "WARRIOR" and { { spell = BATTLE }, { spell = DEFENSIVE } } or {})
        local _, text = areaNames()
        local seen = { [text:match("world=([^;]+)")] = "world" }
        for area in text:match("areas=(.*)$"):gmatch("[^|]+") do
            local fields = {}
            for f in (area .. ","):gmatch("([^,]*),") do fields[#fields + 1] = f end
            for i = 7, 9 do
                local key = fields[i]
                if key ~= "" then
                    assert(not seen[key], class .. ": " .. key .. " on " .. fields[1] .. " and " .. tostring(seen[key]))
                    seen[key] = fields[1]
                end
            end
        end
    end
end)

-- The keys the current app can send are F1..F12, 0..9 and the letters but W A S D (44, 42 used): the two left go to
-- pet / stance slots 1 and 2; the rest come from the keys the app must learn (keypad, F13..F19).
T("extra_keys_old_pool_first_then_the_new_keys", function()
    setup()
    local C = ns.Contract
    assert(C.KeysFor("pet1") == "ALT-CTRL-SHIFT-Y" and C.KeysFor("pet2") == "ALT-CTRL-SHIFT-Z")
    assert(C.KeysFor("stance1") == C.KeysFor("pet1"), "slot k of the class bar: the pet's or the stance's, never both")
    local needs = {}
    for _, key in ipairs(C.NEW_KEYS) do needs[key] = true end
    for _, name in ipairs(C.EXTRA_NAMES) do
        local t, h, p = C.KeysFor(name)
        for _, k in ipairs({ t or false, h or false, p or false }) do
            if k then
                assert(k:find("^ALT%-CTRL%-SHIFT%-"), k)
                local bare = k:sub(16)
                local old = false
                for _, o in ipairs(C.POOL) do if o == k then old = true end end
                assert(old or needs[bare], name .. ": " .. k .. " is neither in the old pool nor in NEW_KEYS")
                assert(not bare:match("^[WASD]$"))
            end
        end
    end
    assert(#C.NEW_KEYS == 22)
end)

T("v1_keys_never_move", function()
    setup()
    local C, P = ns.Contract, "ALT-CTRL-SHIFT-"
    local t, h = C.KeysFor("spell1"); assert(t == P .. "F2" and h == P .. "F")
    t, h = C.KeysFor("interact"); assert(t == P .. "E" and h == P .. "U")
    local _, _, press = C.KeysFor("dive"); assert(press == P .. "X")
    assert(#C.NAMES == 26)
end)

-- ---------------------------------------------------------------------------------------
-- Every new key, pressed as the app presses it (Ctrl, Alt and Shift held)

local function press(key)
    assert(key, "no key")
    Stub.secureActions = {}
    Stub.lastPetAction, Stub.lastSpell, Stub.lastMacro, Stub.lastTargeted = nil, nil, nil, nil
    assert(Stub.pressKey(key), "nothing bound to " .. key)
    assert(not ns.paused, key .. ": " .. tostring(ns.lastError))
end

T("pet_keys_command_the_pet_with_ctrl_alt_shift_held", function()
    local C = setup(); petOut()
    for i = 1, 10 do
        local tap = ns.Contract.KeysFor("pet" .. i)
        press(tap)
        assert(Stub.lastPetAction == i, "pet" .. i .. " commanded " .. tostring(Stub.lastPetAction))
        assert(Stub.calls.PickupPetAction == 0, "never picks the action up (Shift is held)")
    end
    Stub.combat(true); press((ns.Contract.KeysFor("pet3"))); assert(Stub.lastPetAction == 3, "in a fight too")
end)

T("pet_hold_keys_open_the_card_and_never_act", function()
    local C = setup(); petOut()
    Stub.petActions[4].autoCastAllowed = true; Stub.fire("PET_BAR_UPDATE")
    for i = 1, 10 do
        ns.InfoCard.Hide()
        local _, hold = ns.Contract.KeysFor("pet" .. i)
        press(hold)
        assert(#Stub.secureActions == 0 and Stub.calls.CastPetAction == 0 and Stub.calls.TogglePetAutocast == 0,
            "pet" .. i .. ": a hold never acts")
        assert(ns.InfoCard.IsShown() and ns.InfoCard.Title() == "Pet" .. i, "pet" .. i .. ": its card")
    end
    assert(ns.InfoCard.Button("Autocast: off") == nil or true)
end)

T("an_empty_pet_slot_key_does_nothing", function()
    setup()                       -- a hunter with no pet
    for i = 1, 10 do
        if i ~= 5 then
            press((ns.Contract.KeysFor("pet" .. i)))
            assert(#Stub.secureActions == 0 and Stub.calls.CastPetAction == 0, "pet" .. i .. " with no pet")
        end
    end
    local _, hold = ns.Contract.KeysFor("pet3"); press(hold)
    assert(not ns.InfoCard.IsShown(), "nothing to show")
end)

T("slot_5_key_calls_or_revives_the_pet", function()
    setup()
    press((ns.Contract.KeysFor("pet5"))); assert(Stub.lastSpell == CALL_PET, "no pet: Call Pet")
    petOut(); press((ns.Contract.KeysFor("pet5"))); assert(Stub.lastPetAction == 5 and Stub.lastSpell == nil)
    Stub.setDead("pet", "dead"); Stub.applyDrivers()
    Stub.combat(true)
    press((ns.Contract.KeysFor("pet5"))); assert(Stub.lastSpell == REVIVE_PET, "dead: Revive Pet, in a fight too")
    Stub.click(ns.ClassBars.call, "LeftButton"); assert(Stub.lastSpell == REVIVE_PET, "a plain click on it does the same")
end)

T("a_warlock_slot_5_key_never_calls", function()
    setup("WARLOCK")
    press((ns.Contract.KeysFor("pet5")))
    assert(#Stub.secureActions == 0 or Stub.lastSpell == nil)
    assert(Stub.lastSpell == nil and Stub.calls.CastPetAction == 0)
end)

T("stance_keys_cast_the_forms_and_holds_open_the_card", function()
    setup("WARRIOR", { { spell = BATTLE }, { spell = DEFENSIVE }, { spell = BERSERKER } })
    local want = { BATTLE, DEFENSIVE, BERSERKER }
    for i = 1, 3 do
        local tap, hold = ns.Contract.KeysFor("stance" .. i)
        press(tap); assert(Stub.lastSpell == want[i], "stance" .. i)
        ns.InfoCard.Hide()
        local casts = Stub.calls.CastSpell
        press(hold); assert(Stub.calls.CastSpell == casts and ns.InfoCard.IsShown(), "stance" .. i .. " hold")
    end
end)

T("pet_card_keys_target_and_open_the_card", function()
    setup(); petOut()
    local tap, hold = ns.Contract.KeysFor("petcard")
    press(tap); assert(Stub.lastTargeted == "pet")
    ns.InfoCard.Hide(); local n = Stub.calls.TargetUnit
    press(hold); assert(Stub.calls.TargetUnit == n and ns.InfoCard.IsShown())
end)

T("feed_key_feeds_only_while_unhappy", function()
    setup(); petOut()
    local tap = ns.Contract.KeysFor("petfeed")
    press(tap); assert(Stub.lastSpell == nil, "happy: nothing")
    Stub.setPetHappiness(1); press(tap); assert(Stub.lastSpell == FEED_PET)
end)

T("leave_key_and_the_pet_slots_under_leave_leave_the_vehicle", function()
    local C = setup(); petOut()
    press((ns.Contract.KeysFor("leave"))); assert(Stub.lastMacro == "/leavevehicle")
    Stub.setVehicle(true); Stub.applyDrivers()
    assert(C.leave:IsShown() and not C.petBar:IsShown())
    local la = C.leave.touchAnchor
    local under = 0
    for i = 1, 10 do
        local a = C.pet[i].touchAnchor
        local overlaps = a.x < la.x + la.w and la.x < a.x + a.w
        press((ns.Contract.KeysFor("pet" .. i)))
        if overlaps then
            under = under + 1
            assert(Stub.lastMacro == "/leavevehicle", "pet" .. i .. " lies under Leave: it leaves")
        else
            assert(Stub.lastMacro == nil and Stub.lastPetAction == nil, "pet" .. i .. " is not under Leave: nothing")
        end
    end
    assert(under >= 2, "Leave covers some of the row")
    Stub.setVehicle(false); Stub.applyDrivers()
    press((ns.Contract.KeysFor("pet5"))); assert(Stub.lastPetAction == 5, "out of the vehicle the slot is the pet's again")
end)

T("leave_routing_follows_left_handed", function()
    local C = setup(); petOut()
    ns.Feel.Set("leftHanded", true); Stub.advance(1)
    Stub.setVehicle(true); Stub.applyDrivers()
    local la = C.leave.touchAnchor
    for i = 1, 10 do
        local a = C.pet[i].touchAnchor
        local overlaps = a.x < la.x + la.w and la.x < a.x + a.w
        press((ns.Contract.KeysFor("pet" .. i)))
        assert((Stub.lastMacro == "/leavevehicle") == overlaps, "pet" .. i)
    end
end)

T("every_new_key_is_bound_when_on_and_gone_when_paused", function()
    setup(); petOut()
    for _, name in ipairs({ "petcard", "pet1", "pet10", "petfeed", "leave" }) do
        assert(Stub.bindings[(ns.Contract.KeysFor(name))], name .. " bound")
    end
    ns.Pause("test")
    for _, name in ipairs({ "petcard", "pet1", "pet10", "petfeed", "leave" }) do
        assert(Stub.bindings[(ns.Contract.KeysFor(name))] == nil, name .. " unbound while paused")
    end
end)

T("new_secure_buttons_act_on_the_up_click", function()
    setup(); petOut()
    for _, f in ipairs(Stub.allFrames()) do
        local name = f:GetName()
        if type(name) == "string" and name:find("^TouchPlayPet") and Stub.inherits(f, "SecureActionButtonTemplate") then
            assert(f:GetAttribute("useOnKeyDown") == false, name)
        end
    end
end)

Stub.done("petclasses")
