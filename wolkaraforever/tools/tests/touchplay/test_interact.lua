-- Task 11: the Interact, Jump and Dive faces, aiming, the facing message and the flight card
-- (rule 9; mockups 01, 10, 16-18, 23-25, 77, 91).
dofile("tests/stub.lua")

local Interact, Contract

-- A game session with the whole add-on loaded and laid out.
local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Interact, Contract = ns.Interact, ns.Contract
    assert(not ns.paused, ns.lastError)
    return Interact
end

local function parentChainHas(frame, root)
    local f = frame
    while f do
        if f == root then return true end
        f = f:GetParent()
    end
    return false
end

local function bound(key) return Stub.bindings[key] end
local function keyOf(name) return (select(1, Contract.KeysFor(name))) end
local function pressKeyOf(name) return (select(3, Contract.KeysFor(name))) end

local function boundCount()
    local n = 0
    for _ in pairs(Stub.bindings) do n = n + 1 end
    return n
end

-- A pause or Off leaves the three movement keys and bare F12 (the chat strip's, Task 12): 4 in all.
local KEPT = 4

-- ---------------------------------------------------------------------------------------
-- What Interact says

T("rule9_labels", function()
    setup()
    assert(Interact.Label({ fishing = true, exists = false }) == "reelin")
    assert(Interact.Label({}) == "none")
    assert(Interact.Label({ exists = true, dead = true, lootable = true }) == "loot")
    assert(Interact.Label({ exists = true, dead = true, skinnable = true }) == "skin")
    assert(Interact.Label({ exists = true, attackable = true }) == "attack")
    assert(Interact.Label({ exists = true, isObject = true }) == "open")
    assert(Interact.Label({ exists = true }) == "talk")
end)

T("rule9_label_priority", function()
    setup()
    -- fishing beats everything; a lootable body beats skinning and attacking; skin beats attack
    assert(Interact.Label({ fishing = true, exists = true, attackable = true }) == "reelin")
    assert(Interact.Label({ exists = true, dead = true, lootable = true, skinnable = true, attackable = true }) == "loot")
    assert(Interact.Label({ exists = true, dead = true, skinnable = true, attackable = true }) == "skin")
    assert(Interact.Label({ exists = true, attackable = true, isObject = true }) == "attack")
    -- a dead body that is neither lootable nor skinnable (looted already) has nothing to do: "Nothing near"
    assert(Interact.Label({ exists = true, dead = true }) == "none")
    assert(Interact.Label({ exists = true, dead = true, isObject = true }) == "none")
end)

T("rule9_the_face_follows_the_soft_interact_unit", function()
    setup()
    assert(Interact.label() == ns.L["interact.none"] and Interact.interact.label.textColor[1] < 0.6, "nothing near is grey")
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    assert(Interact.label() == "Talk", Interact.label())
    Stub.setSoftInteract({ name = "Starving Mountain Lion", canAttack = true })
    assert(Interact.label() == "Attack")
    Stub.setSoftInteract({ name = "Starving Mountain Lion", dead = true, canAttack = true, lootable = true })
    assert(Interact.label() == "Loot", "a body with loot: loot before attack")
    Stub.setSoftInteract({ name = "Starving Mountain Lion", dead = true, canAttack = true, creatureTypeID = 1 })
    assert(Interact.label() == "Skin", "a beast body with nothing to loot: skin")
    Stub.setSoftInteract({ name = "Mailbox", object = true })
    assert(Interact.label() == "Open")
    Stub.setSoftInteract(nil)
    assert(Interact.label() == "Nothing near")
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    Stub.setTarget("friendly")          -- PLAYER_TARGET_CHANGED reads again
    assert(Interact.label() == "Talk")
end)

-- World taps (18 Nov): the face also names what Interact will use, under its word, so a tap is never a guess (the
-- game's own mark sits over it in the world: SoftTargetIconInteract / SoftTargetIconGameObject, Targeting.lua).
T("interact_face_names_what_it_will_use", function()
    setup()
    assert(Interact.unitName() == "", "nothing near: no name")
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    assert(Interact.label() == "Talk" and Interact.unitName() == "Apothecary Lydon", Interact.unitName())
    assert(Interact.interact.nameLine:IsShown())
    Stub.setSoftInteract({ name = "Mailbox", object = true })
    assert(Interact.unitName() == "Mailbox", "a game object by its name too")
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    Stub.setSoftInteract({ name = "Apothecary Lydon the Second" })
    assert(Interact.unitName() == "Apothecary Lydon the Second", "the same word, a new name: painted again")
    Stub.setSoftInteract({ name = Stub.secret(), guid = "guid:hidden" })
    assert(Interact.unitName() == "", "a name the game hides is never shown or compared")
    assert(not ns.paused, ns.lastError)
    Stub.setSoftInteract(nil)
    assert(Interact.unitName() == "" and not Interact.interact.nameLine:IsShown())
    -- the name stays inside its column: it never reaches the spell ring's second button
    local line = Interact.interact.nameLine
    assert(line:GetWidth() <= 104 and line.wordWrap == false, "one line, cut short")
end)

T("rule9_game_object_fallback_without_UnitIsGameObject", function()
    setup()
    local saved = _G.UnitIsGameObject
    _G.UnitIsGameObject = nil
    Stub.setSoftInteract({ name = "Chest", creatureType = nil })
    -- an object has no creature type; the stub answers one for every unit, so it is a person
    assert(Interact.label() == "Talk")
    _G.UnitIsGameObject = saved
end)

T("rule9_fishing_shows_reel_in", function()
    setup()
    Stub.spellNames[131474] = "Fishing"
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast1", 131474)
    assert(Interact.label() == "Reel in", Interact.label())
    Stub.setSoftInteract({ name = "Fishing Bobber", object = true })
    assert(Interact.label() == "Reel in", "the bobber is an object: still Reel in")
    Stub.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 131474)
    assert(Interact.label() == "Open", Interact.label())
    -- another channel is not fishing
    Stub.setSoftInteract(nil)
    Stub.setUnit("player", { cast = { name = "Drink", channel = true } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast2", 430)
    assert(Interact.label() == "Nothing near")
    -- fishing found by name when the spell id is not the retail one
    Stub.setUnit("player", { cast = { name = "Fishing", channel = true } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast3", 7620)
    assert(Interact.label() == "Reel in", "matched by the spell's name")
end)

T("rule9_no_fish_button", function() setup(); assert(_G.TouchPlayFish == nil) end)

T("rule9_interact_bound_to_command", function()
    setup()
    Contract.Apply()
    local b = bound(keyOf("interact"))
    assert(b and b.command == "INTERACTTARGET", "interact key runs INTERACTTARGET")
    local hold = select(2, Contract.KeysFor("interact"))
    assert(hold == "ALT-CTRL-SHIFT-U", "interact has a hold key from the pool: " .. tostring(hold))
    local text = ns.db.contract
    local line = text:match("areas=.*|(interact,[^|]*)")   -- the area line, not the outline= field's name
    assert(line == "interact,BR,376,148,84,84,ALT-CTRL-SHIFT-E,ALT-CTRL-SHIFT-U,", line)
end)

-- Ruling A22: the walk stick holds plain W, A, S, D, so the contract the whole add-on writes never
-- carries a chord on one of those letters.
T("a22_default_contract_has_no_walk_letters", function()
    setup()
    local text = ns.db.contract
    assert(text and text:find("^TPC1;"), "the contract is written")
    local n = 0
    for key in text:gmatch("ALT%-CTRL%-SHIFT%-(%w+)") do
        n = n + 1
        assert(key ~= "W" and key ~= "A" and key ~= "S" and key ~= "D", "walk letter in the contract: " .. key)
    end
    assert(n > 0)
    for key in pairs(Stub.bindings) do
        assert(not key:match("^ALT%-CTRL%-SHIFT%-[WASD]$"), "walk letter bound: " .. key)
    end
end)

-- Ruling A19: lifting a ground-spell aim over Interact sends Interact's hold key; it runs the hidden "stop"
-- button, never Escape (which would open the game menu with nothing aimed).
T("a19_interact_hold_key_is_the_hidden_stop_button", function()
    setup()
    Contract.Apply()
    local hold = select(2, Contract.KeysFor("interact"))
    local b = bound(hold)
    assert(b and b.click == "TouchPlayStopAim" and b.button == "LeftButton" and not b.command, "the hold key clicks the stop button")
    local button = _G.TouchPlayStopAim
    assert(button and Stub.inherits(button, "SecureActionButtonTemplate"))
    assert(button:GetAttribute("type") == "stop", "the game's stop action")
    assert(button:GetAttribute("useOnKeyDown") == false, "acts on the up click (R47)")
    assert(not button:IsShown(), "hidden")
    -- the tap is still INTERACTTARGET, and the hold key is not the tap key
    assert(bound(keyOf("interact")).command == "INTERACTTARGET" and hold ~= keyOf("interact"))
    -- nothing aimed: the key does nothing at all
    Stub.setTargeting(false); Stub.secureActions = {}
    local before = Stub.calls.SpellStopTargeting
    Stub.pressKey(hold)
    assert(Stub.calls.SpellStopTargeting == before, "nothing is stopped when nothing is aimed")
    -- aiming: the key stops the aim
    Stub.setTargeting(true)
    Stub.pressKey(hold)
    assert(Stub.calls.SpellStopTargeting == before + 1 and not SpellIsTargeting(), "the aim is cancelled")
    for _, key in ipairs(Stub.commandsRun) do assert(key ~= "TOGGLEGAMEMENU", "never Escape") end
end)

-- A pause keeps only Interact's tap (with Jump and Dive): the hold key goes with the rest.
T("a19_pause_keeps_only_the_interact_tap", function()
    setup()
    Contract.Apply()
    ns.Pause("test")
    assert(bound(keyOf("interact")), "tap stays")
    assert(not bound((select(2, Contract.KeysFor("interact")))), "hold key goes in a pause")
end)

T("rule9_hidden_values_never_tested", function()
    setup()
    local savedDead, savedGuid, savedAttack, savedObject, savedType =
        UnitIsDead, UnitGUID, UnitCanAttack, UnitIsGameObject, UnitCreatureType
    Stub.setUnit("softinteract", { name = "Secret thing" })
    UnitIsDead = function() return Stub.secret() end
    UnitGUID = function() return Stub.secret() end
    UnitCanAttack = function() return Stub.secret() end
    UnitIsGameObject = function() return Stub.secret() end
    UnitCreatureType = function() return Stub.secret(), Stub.secret() end
    Stub.fire("PLAYER_SOFT_INTERACT_CHANGED")
    Stub.fire("PLAYER_TARGET_CHANGED")
    assert(not ns.paused, ns.lastError)
    assert(Interact.label() == "Talk", "hidden facts count as false")
    UnitIsDead, UnitGUID, UnitCanAttack, UnitIsGameObject, UnitCreatureType =
        savedDead, savedGuid, savedAttack, savedObject, savedType
    -- the channel started with a hidden spell id and a hidden name
    local savedChannel = UnitChannelInfo
    UnitChannelInfo = function() return Stub.secret() end
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "x", Stub.secret())
    assert(not ns.paused, ns.lastError)
    UnitChannelInfo = savedChannel
end)

T("interact_never_calls_interact_api", function()
    setup()
    for e in pairs(Stub.allEvents) do Stub.fire(e) end
    assert(Stub.calls.InteractUnit == 0)
    assert(Stub.calls.TaxiRequestEarlyLanding == 0, "Request stop waits for a tap")
    assert(Stub.calls.JumpOrAscendStart == 0)
end)

T("faces_have_no_onupdate_and_take_no_taps", function()
    setup()
    for _, f in ipairs({ Interact.interact, Interact.jump, Interact.dive, Interact.facing, Interact.card }) do
        assert(f.scripts.OnUpdate == nil, "no OnUpdate")
    end
    for _, f in ipairs({ Interact.interact, Interact.jump, Interact.dive }) do
        assert(not f:IsMouseEnabled(), "a picture: the app's key does the work")
    end
end)

-- ---------------------------------------------------------------------------------------
-- Jump and Dive

T("jump_is_a_press_on_JUMP", function()
    setup()
    Contract.Apply()
    local b = bound(pressKeyOf("jump"))
    assert(b and b.command == "JUMP")
    assert(Interact.jumpLabel() == ns.L["jump.jump"] and ns.L["jump.jump"] == "Jump")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount", "dry land with a mount: Mount (R50)")
end)

T("swim_shows_dive", function()
    setup()
    Stub.setSwimming(true); Stub.fire("MIRROR_TIMER_START")
    assert(Interact.dive:IsShown() and Interact.jumpLabel() == ns.L["jump.swimUp"])
    assert(Interact.diveLabel() == "Dive" and ns.L["jump.swimUp"] == "Swim up")
    Stub.setSwimming(false); Stub.fire("MIRROR_TIMER_STOP")
    assert(Interact.diveLabel() == "Mount" and Interact.jumpLabel() == "Jump", "back on land: Mount")
end)

T("swim_is_found_on_the_next_move_or_jump", function()
    setup()
    Stub.setSwimming(true)
    Stub.fire("PLAYER_STOPPED_MOVING")
    assert(Interact.dive:IsShown(), "stopping to tread water")
    Stub.setSwimming(false); Stub.fire("PLAYER_STARTED_MOVING")
    assert(Interact.diveLabel() == "Mount")
    Stub.setSwimming(true)
    _G.JumpOrAscendStart()              -- the game's jump command, as the Jump key runs it
    assert(Interact.dive:IsShown(), "pressing Jump looks again")
end)

T("dive_press_is_the_swim_down_command", function()
    setup()
    Stub.setSwimming(true); Stub.fire("MIRROR_TIMER_START")
    Contract.Apply()
    local b = bound(pressKeyOf("dive"))
    assert(b and b.command == "SITORSTAND", "swim down is SITORSTAND (Bindings_Camelot.xml)")
end)

T("mounted_dive_ring_is_dismount_through_a_hidden_macro", function()
    setup()
    Contract.Apply()
    Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Dismount")
    local b = bound(pressKeyOf("dive"))
    assert(b and b.click == "TouchPlayDismount" and b.button == "LeftButton" and not b.command, "the key clicks the dismount button")
    local button = _G.TouchPlayDismount
    assert(button and Stub.inherits(button, "SecureActionButtonTemplate"))
    assert(button:GetAttribute("type") == "macro" and button:GetAttribute("macrotext") == "/dismount")
    assert(not button:IsShown(), "hidden")
    -- the jump key still jumps, interact still interacts
    assert(bound(pressKeyOf("jump")).command == "JUMP" and bound(keyOf("interact")).command == "INTERACTTARGET")
    Stub.setMounted(false); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayMount", "back on foot: the Mount button")
end)

T("mounted_and_swimming_shows_dismount", function()
    setup()
    Stub.setSwimming(true); Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(Interact.diveLabel() == "Dismount" and Interact.jumpLabel() == "Swim up")
end)

T("logging_in_mounted_binds_dismount_from_the_start", function()
    Stub.reset(); Stub.loadAll()
    Stub.setMounted(true)
    Stub.login()
    assert(bound(pressKeyOf("dive")).click == "TouchPlayDismount")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Dismount")
end)

T("mounting_in_a_fight_binds_after_the_fight", function()
    setup()
    Contract.Apply()
    Stub.combat(true)
    Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(not ns.paused, ns.lastError)
    assert(Interact.diveLabel() == "Dismount", "the picture changes at once")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayMount", "the game refuses binding changes in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayDismount")
end)

-- ---------------------------------------------------------------------------------------
-- R50: the Mount ring on land

local RANDOM_MACRO = "/run if not InCombatLockdown() then C_MountJournal.SummonByID(0) end"

T("mount_ring_on_land_clicks_a_hidden_summon_macro", function()
    setup()
    Contract.Apply()
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount" and ns.L["dive.mount"] == "Mount")
    assert(Interact.dive.icon.touchGlyph == "mount", "the gold horse head")
    assert(Interact.dive.label.textColor[1] == 1, "gold, not grey")
    local b = bound(pressKeyOf("dive"))
    assert(b and b.click == "TouchPlayMount" and b.button == "LeftButton" and not b.command)
    local button = _G.TouchPlayMount
    assert(button and Stub.inherits(button, "SecureActionButtonTemplate") and not button:IsShown())
    assert(button:GetAttribute("type") == "macro" and button:GetAttribute("macrotext") == RANDOM_MACRO,
        tostring(button:GetAttribute("macrotext")))
    assert(button:GetAttribute("useOnKeyDown") == false, "acts on the up click (R47)")
    assert(button.clicks and button.clicks[1] == "AnyUp")
    -- the contract is unchanged: the dive area keeps its press key
    assert(ns.db.contract:find("dive,BR,478,232,56,56,,,", 1, true), ns.db.contract)
end)

T("mount_dive_dismount_follow_the_player_and_the_key_follows", function()
    setup()
    Contract.Apply()
    Stub.setSwimming(true); Stub.fire("MIRROR_TIMER_START")
    assert(Interact.diveLabel() == "Dive" and Interact.dive.icon.touchGlyph == "dive")
    assert(bound(pressKeyOf("dive")).command == "SITORSTAND")
    Stub.setSwimming(false); Stub.fire("MIRROR_TIMER_STOP")
    assert(Interact.diveLabel() == "Mount" and bound(pressKeyOf("dive")).click == "TouchPlayMount")
    Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(Interact.diveLabel() == "Dismount" and bound(pressKeyOf("dive")).click == "TouchPlayDismount")
    Stub.setTaxi(true)
    assert(not Interact.dive:IsShown(), "no ring on a flight path")
end)

T("no_mount_ring_without_a_mount", function()
    Stub.reset(); Stub.loadAll()
    for _, m in ipairs(Stub.mounts) do m.collected = false end
    Stub.login()
    Interact, Contract = ns.Interact, ns.Contract
    Stub.fire("PLAYER_ENTERING_WORLD")
    assert(not Interact.dive:IsShown(), "nothing to summon: no ring")
    assert(bound(pressKeyOf("dive")).command == "SITORSTAND", "the key stays swim down")
    -- the first mount
    Stub.mounts[1].collected = true
    Stub.fire("NEW_MOUNT_ADDED", 241)
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayMount")
end)

T("a_mount_hidden_for_this_character_does_not_count", function()
    Stub.reset(); Stub.loadAll()
    Stub.mounts = { { id = 90, name = "Nightsaber (other faction)", icon = "mount90", collected = true, hidden = true } }
    Stub.login()
    assert(not ns.Interact.dive:IsShown())
end)

T("mount_ring_greys_in_a_fight_and_lights_after", function()
    setup()
    Contract.Apply()
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount")
    assert(Interact.dive.label.textColor[1] < 0.6 and Interact.dive.icon.desaturated == true, "greyed")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayMount", "the macro stops itself in a fight ([combat])")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Interact.dive.label.textColor[1] == 1 and not Interact.dive.icon.desaturated)
    assert(not ns.paused, ns.lastError)
end)

T("a_pinned_mount_is_summoned_instead_and_kept_for_the_character", function()
    setup()
    Interact.PinMount(35)
    assert(TouchPlayCharDB.mount == 35)
    assert(_G.TouchPlayMount:GetAttribute("macrotext") == "/run if not InCombatLockdown() then C_MountJournal.SummonByID(35) end")
    Stub.reload(); Stub.fire("PLAYER_LOGIN")
    assert(_G.TouchPlayMount:GetAttribute("macrotext") == "/run if not InCombatLockdown() then C_MountJournal.SummonByID(35) end",
        "kept after a reload")
    ns.Interact.PinMount(nil)
    assert(TouchPlayCharDB.mount == nil and _G.TouchPlayMount:GetAttribute("macrotext") == RANDOM_MACRO)
end)

T("pinning_in_a_fight_waits_for_its_end", function()
    setup()
    Stub.combat(true)
    Interact.PinMount(17)
    assert(not ns.paused, ns.lastError)
    assert(_G.TouchPlayMount:GetAttribute("macrotext") == RANDOM_MACRO, "the game protects the button in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(_G.TouchPlayMount:GetAttribute("macrotext"):find("SummonByID(17)", 1, true))
end)

T("a_ghost_gets_no_mount_ring", function()
    setup()
    Stub.setDead("player", "ghost"); Stub.fire("PLAYER_DEAD")
    assert(not Interact.dive:IsShown(), "a ghost cannot mount")
    Stub.setDead("player", nil); Stub.fire("PLAYER_UNGHOST")
    assert(Interact.dive:IsShown() and Interact.diveLabel() == "Mount")
end)

T("nothing_summons_from_an_event_or_a_timer", function()
    setup()
    -- the stub's SummonByID raises: any call from add-on code would pause the add-on
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED",
        "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do Stub.fire(e) end
    Stub.advance(10)
    assert(not ns.paused, ns.lastError)
end)

T("dive_ring_clears_the_pet_row_and_the_interact_ring", function()
    setup()
    Stub.setPet(true)
    local dive = Interact.dive.touchAnchor
    local function overlap(a, b)
        return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
    end
    for i, b in ipairs(ns.ClassBars.pet) do
        assert(b.touchAnchor and not overlap(dive, b.touchAnchor), "pet button " .. i)
    end
    assert(not overlap(dive, Interact.interact.touchAnchor), "interact")
    -- the dive label sits under its ring: it must not reach the pet row either
    local labelBottom = dive.y + dive.h + 24
    for _, b in ipairs(ns.ClassBars.pet) do
        assert(labelBottom <= b.touchAnchor.y, "the Dive label stays above the pet row")
    end
end)

-- ---------------------------------------------------------------------------------------
-- Where the faces sit

T("faces_sit_where_the_mockups_put_them_and_belong_to_the_move_root", function()
    setup()
    local want = {
        interact = { Interact.interact, 906, 792, 84 },
        jump = { Interact.jump, 1118, 915, 58 },
        dive = { Interact.dive, 832, 736, 56 },
    }
    for name, w in pairs(want) do
        local f, x, y, d = w[1], w[2], w[3], w[4]
        local a = f.touchAnchor
        assert(a and a.x == x and a.y == y and a.w == d and a.h == d, name)
        assert(parentChainHas(f, ns.moveRoot) and not parentChainHas(f, ns.root), name .. " stays with the move root")
        assert(a.w >= 44 and a.h >= 44, name .. " tap size")
    end
    -- the contract carries them with their corner and offsets
    local text = ns.db.contract
    assert(text:find("interact,BR,376,148,84,84,", 1, true), text)
    assert(text:find("jump,BR,190,51,58,58,", 1, true), text)
    assert(text:find("dive,BR,478,232,56,56,", 1, true), text)
    local aim = Interact.aimLine
    assert(not aim:IsShown())
end)

T("pause_keeps_the_faces_and_their_keys", function()
    setup()
    ns.Pause("test")
    assert(ns.root:IsShown() == false)
    assert(Interact.interact:IsShown() and Interact.jump:IsShown(), "mockup 91: Talk and Jump stay")
    -- the faces keep following the game
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    assert(Interact.label() == "Talk")
    Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(Interact.diveLabel() == "Dismount")
    -- only the three movement keys and F12 are bound, and the dive key follows the mount
    assert(bound("F12").command == "OPENCHAT", "F12 stays")
    assert(boundCount() == KEPT, "bound " .. boundCount())
    assert(bound(keyOf("interact")).command == "INTERACTTARGET" and bound(pressKeyOf("jump")).command == "JUMP")
    assert(bound(pressKeyOf("dive")).click == "TouchPlayDismount")
    Stub.setMounted(false); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(boundCount() == KEPT and bound(pressKeyOf("dive")).click == "TouchPlayMount")
end)

T("off_keeps_the_movement_keys_and_gives_the_cvar_back", function()
    Stub.reset(); Stub.loadAll(); Stub.cvars.SoftTargetInteract = "1"
    Stub.login()
    Interact = ns.Interact; Contract = ns.Contract
    assert(Stub.cvars.SoftTargetInteract == "3")
    ns.SetEnabled(false)
    assert(Stub.cvars.SoftTargetInteract == "1", "Off puts the old value back")
    assert(boundCount() == KEPT)
    Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    assert(boundCount() == KEPT and bound(pressKeyOf("dive")).click == "TouchPlayDismount", "still only the kept keys")
    ns.SetEnabled(true)
    assert(Stub.cvars.SoftTargetInteract == "3", "On raises it again")
    assert(Stub.printed("soft interact") == 1, "told once, not on every switch")
end)

T("starting_off_registers_the_areas_and_places_the_faces", function()
    Stub.reset(); Stub.loadAll()
    TouchPlayDB = { enabled = false }
    Stub.login()
    assert(not ns.paused, ns.lastError)
    local I = ns.Interact
    assert(I.interact.touchAnchor and I.jump.touchAnchor and I.dive.touchAnchor)
    Stub.setSoftInteract({ name = "Apothecary Lydon" })
    assert(I.label() == "Talk", "the faces follow the game while off")
    assert(Stub.cvars.SoftTargetInteract == "1", "off at login leaves the cvar alone")
end)

-- ---------------------------------------------------------------------------------------
-- Soft interact setting

T("login_raises_soft_interact_once_and_never_in_a_fight", function()
    Stub.reset(); Stub.loadAll(); Stub.cvars.SoftTargetInteract = "1"
    Stub.login()
    assert(Stub.cvars.SoftTargetInteract == "3", "raised at login")
    assert(Stub.printed("soft interact") == 1)
    assert(ns.db.softInteractOld == 1)
    -- the game put it back (or the player did): a layout in a fight waits for the end of the fight
    Stub.cvars.SoftTargetInteract = "1"
    Stub.combat(true)
    ns.Interact:Layout()
    assert(Stub.cvars.SoftTargetInteract == "1", "not in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.cvars.SoftTargetInteract == "3")
    assert(Stub.printed("soft interact") == 1, "told once")
    assert(ns.db.softInteractOld == 1, "the first old value is the one kept")
end)

T("soft_interact_left_alone_when_already_three", function()
    Stub.reset(); Stub.loadAll(); Stub.cvars.SoftTargetInteract = "3"
    Stub.login()
    assert(Stub.calls.SetCVar == 0 and ns.db.softInteractOld == nil)
    ns.SetEnabled(false)
    assert(Stub.calls.SetCVar == 0 and Stub.cvars.SoftTargetInteract == "3", "nothing of ours to give back")
end)

T("a_pause_keeps_soft_interact_up", function()
    Stub.reset(); Stub.loadAll(); Stub.cvars.SoftTargetInteract = "0"
    Stub.login()
    ns.Pause("test")
    assert(Stub.cvars.SoftTargetInteract == "3", "Interact still works through a pause")
end)

-- ---------------------------------------------------------------------------------------
-- Aiming

T("aiming_shows_cancel", function()
    setup()
    Stub.setTargeting(true); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    assert(Interact.label() == ns.L["interact.cancel"] and ns.L["interact.cancel"] == "Cancel")
    assert(Interact.interact.icon.touchGlyph == "cancel", "a red X")
    Stub.setTargeting(false); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    assert(Interact.label() == ns.L["interact.none"])
end)

T("aiming_names_the_spell_that_was_pressed", function()
    setup()
    Stub.spellNames[10] = "Flamestrike"
    Stub.actions[1] = 10
    local b = ns.Cluster.buttons[1]
    -- the key presses the button, then the game starts aiming
    b:_Fire("PreClick", "LeftButton", false)
    Stub.setTargeting(true); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    assert(Interact.aimLine:IsShown() and Interact.aimLine:GetText() == "Let go to cast Flamestrike", Interact.aimLine:GetText())
    local c = Interact.aimLine.textColor
    assert(c and c[2] == 1 and c[1] < 0.5, "green")
    Stub.setTargeting(false); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    assert(not Interact.aimLine:IsShown())
end)

T("aiming_without_a_recent_press_says_it_plainly", function()
    setup()
    Stub.spellNames[10] = "Flamestrike"
    Stub.actions[1] = 10
    ns.Cluster.buttons[1]:_Fire("PreClick", "LeftButton", false)
    Stub.advance(5)                      -- an old press must not name a spell started some other way
    Stub.setTargeting(true); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    assert(Interact.aimLine:GetText() == "Let go to cast")
end)

-- R24: mockup 23 puts the line under the aiming circle, centred at about (645, 640).
T("aiming_line_is_centred_under_the_circle", function()
    setup()
    local line = Interact.aimLine
    local x, y = Stub.centre(line)
    assert(x == 645 and y == 640, x .. "," .. y)
    assert(line.justifyH == "CENTER", tostring(line.justifyH))
end)

T("aiming_sits_clear_of_the_cluster", function()
    setup()
    -- the line's box (centred at (645, 640), 320 x 28) must not touch a spell button or page box
    local box = { x = 485, y = 626, w = 320, h = 28 }
    local function overlap(a, b)
        return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
    end
    for i, b in ipairs(ns.Cluster.buttons) do assert(not overlap(box, b.touchAnchor), "spell " .. i) end
    for i, b in ipairs(ns.Cluster.pageBoxes) do assert(not overlap(box, b.touchAnchor), "page " .. i) end
    assert(not overlap(box, ns.Cluster.nextTarget.touchAnchor))
end)

-- ---------------------------------------------------------------------------------------
-- The facing message

T("facing_message_shows_for_two_seconds_with_a_hint_three_times", function()
    setup()
    for i = 1, 3 do
        Stub.fire("UI_ERROR_MESSAGE", 1, ERR_BADATTACKFACING)
        assert(Interact.facing:IsShown() and Interact.facing.text:GetText() == "Target needs to be in front of you.")
        assert(Interact.facing.hint:GetText() == ns.L["facing.hint"], "hint " .. i)
        Stub.advance(1)
        assert(Interact.facing:IsShown(), "still up after 1 s")
        Stub.advance(1.1)
        assert(not Interact.facing:IsShown(), "gone after 2 s")
    end
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_BADATTACKFACING)
    assert(Interact.facing.hint:GetText() == "", "the fourth time: no hint")
    assert(ns.db.facingHints == 3)
    local a = Interact.facing.touchAnchor
    assert(a.y == 200 and a.x + a.w / 2 == 683, "centred, at y 200")
end)

T("a_second_facing_error_keeps_the_message_up_for_its_own_two_seconds", function()
    setup()
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_BADATTACKFACING)
    Stub.advance(1.5)
    Stub.fire("UI_ERROR_MESSAGE", 1, ERR_BADATTACKFACING)
    Stub.advance(1)                      -- the first timer fires here and must not hide the second
    assert(Interact.facing:IsShown())
    Stub.advance(1.1)
    assert(not Interact.facing:IsShown())
end)

T("other_errors_and_hidden_text_do_not_show_the_facing_message", function()
    setup()
    Stub.fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    assert(not Interact.facing:IsShown())
    Stub.fire("UI_ERROR_MESSAGE", 1, Stub.secret())
    Stub.fire("UI_ERROR_MESSAGE")
    assert(not ns.paused, ns.lastError and ns.lastError:sub(1, 200))
    assert(not Interact.facing:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- The flight card

T("flight_card_names_the_stop_and_requests_it_on_a_tap", function()
    setup()
    Stub.taxiNodes[3] = "Undercity, Tirisfal Glades"
    TakeTaxiNode(3)                      -- the flight master's map, as the game calls it
    Stub.setTaxi(true)
    local card = Interact.card
    assert(card:IsShown() and card.title:GetText() == "Flying to Undercity", card.title:GetText())
    assert(card.buttons[1].label:GetText() == "Request stop")
    local a = card.touchAnchor
    assert(a.x == 486 and a.y == 134 and a.w == 394, "mockup 17")
    assert(Stub.calls.TaxiRequestEarlyLanding == 0, "nothing runs until a tap")
    Stub.click(card.buttons[1])
    assert(Stub.calls.TaxiRequestEarlyLanding == 1)
    assert(card.buttons[1].busy and card.buttons[1].label:GetText() == "Stop requested")
    Stub.click(card.buttons[1])
    assert(Stub.calls.TaxiRequestEarlyLanding == 1, "a second tap does nothing while it waits")
    Stub.setTaxi(false)
    assert(not card:IsShown())
end)

T("flight_card_without_a_known_stop", function()
    setup()
    Stub.setTaxi(true)
    assert(Interact.card:IsShown() and Interact.card.title:GetText() == "On a flight path")
    Stub.setTaxi(false)
    -- a new flight starts with a fresh button
    Stub.taxiNodes[1] = "Orgrimmar, Durotar"
    TakeTaxiNode(1)
    Stub.setTaxi(true)
    assert(Interact.card.title:GetText() == "Flying to Orgrimmar")
    assert(not Interact.card.buttons[1].busy and Interact.card.buttons[1].label:GetText() == "Request stop")
end)

T("flight_greys_jump_and_takes_interact_away", function()
    setup()
    Stub.setTaxi(true)
    assert(not Interact.interact:IsShown(), "mockup 17 has no Interact")
    assert(Interact.jump:IsShown() and Interact.jump.label.textColor[1] < 0.6, "Jump greyed")
    assert(not Interact.dive:IsShown())
    Stub.setTaxi(false)
    assert(Interact.interact:IsShown() and Interact.jump.label.textColor[1] == 1)
end)

T("flight_card_follows_the_game_events_and_no_polling", function()
    setup()
    local timers = #Stub.timers
    Stub.taxi = true
    Stub.fire("PLAYER_ENTERING_WORLD")   -- logging in or reloading mid-flight
    assert(Interact.card:IsShown())
    Stub.taxi = false
    Stub.fire("UPDATE_BONUS_ACTIONBAR")
    assert(not Interact.card:IsShown())
    Stub.advance(1.0); Stub.advance(0.2) -- the in-world signal's one pulse (Signal.lua, sent 1 s after entering) has run and left no timer
    assert(#Stub.timers == timers, "no timers started for polling")
end)

T("flight_card_hides_with_the_add_on_but_the_game_keeps_its_own_leave_button", function()
    setup()
    Stub.setTaxi(true)
    ns.SetEnabled(false)
    assert(not ns.root:IsShown(), "the card is on the root, which off hides")
    assert(Interact.jump:IsShown(), "the faces stay")
end)

-- The aim line names the spell only from a plain answer: a hidden action kind is never compared.
T("aiming_with_a_hidden_action_kind_says_it_plainly", function()
    setup()
    Stub.actions[1] = 10
    local real = GetActionInfo
    GetActionInfo = function() return Stub.secret(), 10 end
    ns.Cluster.buttons[1]:_Fire("PreClick", "LeftButton", false)
    Stub.setTargeting(true); Stub.fire("CURRENT_SPELL_CAST_CHANGED")
    GetActionInfo = real
    assert(not ns.paused, tostring(ns.lastError))
    assert(Interact.aimLine:GetText() == "Let go to cast")
end)

Stub.done("interact")
