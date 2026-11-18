-- World taps: accuracy and soft targeting (phase-1 close-out, 18 Nov). On the iPad (16 Nov): "I could click an enemy NPC but
-- it was a bit challenging to get the click to be on target". Targeting.lua turns on the game's own soft targeting
-- and bigger enemy name plates while Touch is on, keeps the player's own values and gives them back exactly on Off,
-- pause and Edit Mode, never fights a change the player makes, and never changes a CVar in a fight.
dofile("tests/stub.lua")

local function setup(opts)
    Stub.reset(); Stub.loadAll()
    Stub.targetingCVars()
    if opts and opts.before then opts.before() end
    Stub.login()
    assert(not ns.paused, tostring(ns.lastError))
    return ns.Targeting
end

-- The game's own values before Touch changed anything (Stub.targetingCVars).
local GAME = {
    SoftTargetEnemy = "1", SoftTargetIconEnemy = "0", SoftTargetIconInteract = "1", SoftTargetIconGameObject = "0",
    nameplateShowEnemies = "1", nameplateShowAll = "0", nameplateSize = "1", nameplateStackingTypes = "000",
}

local function isGame(name) return Stub.cvars[name] == GAME[name] end
local function allGame()
    for name in pairs(GAME) do assert(isGame(name), name .. " is " .. tostring(Stub.cvars[name])) end
end
-- /reload: the game keeps its CVars (the stub's reload starts a fresh game, so they are carried over here).
local function reload()
    local cvars = Stub.cvars
    Stub.reload()
    Stub.cvars = cvars
end
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function touchValues()
    assert(Stub.cvars.SoftTargetEnemy == "3", "enemies in front are soft targeted for keys too (Any = 3)")
    assert(Stub.cvars.SoftTargetIconEnemy == "1", "a mark over the enemy a spell will hit")
    assert(Stub.cvars.SoftTargetIconGameObject == "1", "a mark over the object Interact will use")
    assert(Stub.cvars.nameplateShowAll == "1", "enemy plates out of a fight too")
    assert(Stub.cvars.nameplateSize == "3", "Large plates: a bigger tap")
    assert(GetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Enemy), "enemy plates do not overlap")
end

-- ---------------------------------------------------------------------------------------
-- On: the touch defaults; the player's values kept

T("targeting_on_applies_the_touch_defaults_and_keeps_the_originals", function()
    local Targeting = setup()
    touchValues()
    assert(Stub.cvars.SoftTargetIconInteract == "1" and Stub.cvars.nameplateShowEnemies == "1", "already right: left alone")
    local held = TouchPlayDB.targetHeld
    assert(held.SoftTargetEnemy.was == "1" and held.SoftTargetEnemy.ours == "3")
    assert(held.nameplateSize.was == "1" and held.nameplateStackingTypes.was == "000")
    assert(held.SoftTargetIconInteract == nil and held.nameplateShowEnemies == nil, "nothing saved for what was not changed")
    assert(Targeting.Held("nameplateSize"))
    assert(#Stub.cvarInCombat == 0)
end)

T("targeting_skips_a_cvar_this_client_does_not_know", function()
    setup({ before = function() Stub.cvars.SoftTargetIconEnemy = nil; Stub.cvars.nameplateStackingTypes = nil end })
    assert(Stub.cvars.SoftTargetIconEnemy == nil and Stub.cvars.nameplateStackingTypes == nil, "never created")
    assert(TouchPlayDB.targetHeld.SoftTargetIconEnemy == nil and TouchPlayDB.targetHeld.nameplateStackingTypes == nil)
    assert(Stub.cvars.SoftTargetEnemy == "3", "the rest still applies")
    assert(not ns.paused, ns.lastError)
end)

T("targeting_leaves_a_value_that_already_does_the_job", function()
    setup({ before = function()
        Stub.cvars.SoftTargetEnemy = "2"          -- keyboard and mouse: the app's keys are keys
        Stub.cvars.nameplateSize = "5"            -- Huge: never made smaller
        Stub.cvars.nameplateStackingTypes = "011"
    end })
    assert(Stub.cvars.SoftTargetEnemy == "2" and Stub.cvars.nameplateSize == "5" and Stub.cvars.nameplateStackingTypes == "011")
    local held = TouchPlayDB.targetHeld
    assert(held.SoftTargetEnemy == nil and held.nameplateSize == nil and held.nameplateStackingTypes == nil)
end)

T("targeting_never_touches_self_cast_friend_or_mouseover_cvars", function()
    setup()
    assert(Stub.cvars.autoSelfCast == "1" and Stub.cvars.SoftTargetFriend == "0")
    assert(Stub.cvars.SoftTargetForce == "0" and Stub.cvars.enableMouseoverCast == "0")
    for _, def in ipairs(ns.Targeting.DEFS) do
        local n = def.name:lower()
        assert(n ~= "autoselfcast" and n ~= "softtargetfriend" and n ~= "enablemouseovercast" and n ~= "softtargetforce", def.name)
        assert(n ~= "softtargetinteract", "SoftTargetInteract stays Interact.lua's (it works through a pause)")
    end
end)

-- ---------------------------------------------------------------------------------------
-- Given back exactly: Off, pause, Edit Mode

T("targeting_off_gives_every_value_back_and_on_applies_again", function()
    setup()
    ns.SetEnabled(false)
    allGame()
    assert(count(TouchPlayDB.targetHeld) == 0, "nothing held while off")
    ns.SetEnabled(true)
    touchValues()
    assert(TouchPlayDB.targetHeld.SoftTargetEnemy.was == "1", "the player's value, not ours")
end)

T("targeting_pause_gives_back_and_resume_applies", function()
    setup()
    ns.Pause("test")
    allGame()
    ns.SetEnabled(true)                     -- the pause card's "turn touch back on"
    touchValues()
end)

T("targeting_edit_mode_gives_back_and_closing_it_applies", function()
    setup()
    EventRegistry:TriggerEvent("EditMode.Enter")
    allGame()
    EventRegistry:TriggerEvent("EditMode.Exit")
    touchValues()
end)

T("targeting_reload_keeps_the_originals_not_ours", function()
    setup()
    reload(); Stub.fire("PLAYER_LOGIN")
    assert(not ns.paused, ns.lastError)
    touchValues()
    assert(TouchPlayDB.targetHeld.nameplateSize.was == "1", "a reload never saves our own value as the player's")
    ns.SetEnabled(false)
    allGame()
end)

T("targeting_leftovers_go_back_when_logging_in_off", function()
    setup()
    local db = TouchPlayDB
    db.enabled = false                      -- e.g. switched off in a session the game never saved the CVars of
    reload(); Stub.fire("PLAYER_LOGIN"); Stub.fire("PLAYER_ENTERING_WORLD")
    allGame()
    assert(count(TouchPlayDB.targetHeld) == 0)
end)

-- ---------------------------------------------------------------------------------------
-- Never fight the player

T("targeting_a_change_the_player_makes_while_on_stands", function()
    local Targeting = setup()
    Stub.cvars.nameplateSize = "2"          -- the player picks Medium in the game's settings
    Targeting.Apply()
    assert(Stub.cvars.nameplateSize == "2", "not raised again")
    ns.SetEnabled(false)
    assert(Stub.cvars.nameplateSize == "2", "Off does not undo the player's own choice")
    assert(Stub.cvars.SoftTargetEnemy == "1", "the rest goes back")
    ns.SetEnabled(true)
    assert(Stub.cvars.nameplateSize == "2", "and On does not apply it again for this character")
    assert(Stub.cvars.SoftTargetEnemy == "3")
    assert(TouchPlayCharDB.targetDeclined.nameplateSize == true)
end)

T("targeting_a_change_the_player_makes_while_off_stands", function()
    setup()
    ns.SetEnabled(false)
    Stub.cvars.SoftTargetIconEnemy = "0"; Stub.cvars.nameplateShowAll = "0"     -- what we put back: untouched
    Stub.cvars.nameplateSize = "4"                                             -- the player's own
    ns.SetEnabled(true)
    assert(Stub.cvars.nameplateSize == "4")
    assert(Stub.cvars.nameplateShowAll == "1" and Stub.cvars.SoftTargetIconEnemy == "1", "the untouched ones come back")
end)

T("targeting_defaults_in_touch_settings_apply_again", function()
    local Targeting = setup()
    Stub.cvars.nameplateSize = "2"; Targeting.Apply()
    assert(Stub.cvars.nameplateSize == "2")
    Stub.click(ns.Feel.defaultsButton); Stub.advance(1)
    assert(Stub.cvars.nameplateSize == "3", "Defaults is the player's yes to the touch values again")
    assert(TouchPlayCharDB.targetDeclined == nil or TouchPlayCharDB.targetDeclined.nameplateSize == nil)
    ns.SetEnabled(false)
    assert(Stub.cvars.nameplateSize == "2", "and Off gives back the player's last own value")
end)

-- ---------------------------------------------------------------------------------------
-- The two switches (Touch settings, Targeting)

T("targeting_switches_default_on_and_each_owns_its_cvars", function()
    setup()
    local Feel = ns.Feel
    assert(Feel.Get("autoTarget") == true and Feel.Get("bigPlates") == true)
    Feel.Set("autoTarget", false)
    assert(Stub.cvars.SoftTargetEnemy == "1" and Stub.cvars.SoftTargetIconEnemy == "0", "auto-target off: given back")
    assert(Stub.cvars.nameplateSize == "3", "the plates stay")
    Feel.Set("bigPlates", false)
    assert(Stub.cvars.nameplateSize == "1" and Stub.cvars.nameplateShowAll == "0" and Stub.cvars.nameplateStackingTypes == "000")
    assert(Stub.cvars.SoftTargetIconGameObject == "1", "the Interact marks are not a switch")
    Feel.Set("autoTarget", true); Feel.Set("bigPlates", true)
    touchValues()
    ns.SetEnabled(false); ns.SetEnabled(true)
    touchValues()
end)

T("targeting_switch_on_is_a_yes_even_after_the_player_changed_it", function()
    local Targeting = setup()
    Stub.cvars.SoftTargetEnemy = "1"; Targeting.Apply()       -- the player unticked the game's Action Targeting
    assert(Stub.cvars.SoftTargetEnemy == "1")
    ns.Feel.Set("autoTarget", false); ns.Feel.Set("autoTarget", true)
    assert(Stub.cvars.SoftTargetEnemy == "3", "ticking the switch asks for it again")
end)

T("targeting_switch_off_while_off_changes_nothing_now", function()
    setup()
    ns.SetEnabled(false)
    local calls = Stub.calls.SetCVar or 0
    ns.Feel.Set("bigPlates", false); ns.Feel.Set("autoTarget", false)
    assert((Stub.calls.SetCVar or 0) == calls, "Touch is off: the game's values are the player's")
    ns.SetEnabled(true)
    for name in pairs(GAME) do
        if name ~= "SoftTargetIconGameObject" then assert(isGame(name), name .. " follows its switch") end
    end
    assert(Stub.cvars.SoftTargetIconGameObject == "1", "the Interact marks are not a switch")
end)

-- ---------------------------------------------------------------------------------------
-- Fights: no CVar changes under the lockdown

T("targeting_never_sets_a_cvar_in_a_fight", function()
    setup()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    ns.SetEnabled(false)
    ns.Feel.Set("bigPlates", false)
    ns.Targeting.Apply()
    assert(#Stub.cvarInCombat == 0, "changed in a fight: " .. table.concat(Stub.cvarInCombat, ","))
    assert(Stub.cvars.SoftTargetEnemy == "3", "it waits for the end of the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    allGame()
end)

T("targeting_login_in_a_fight_waits", function()
    Stub.reset(); Stub.loadAll(); Stub.targetingCVars()
    Stub.combat(true)
    Stub.login()
    assert(#Stub.cvarInCombat == 0 and isGame("SoftTargetEnemy"))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    touchValues()
end)

T("targeting_switch_in_a_fight_waits", function()
    setup()
    Stub.combat(true)
    ns.Feel.Set("autoTarget", false)
    assert(#Stub.cvarInCombat == 0 and Stub.cvars.SoftTargetEnemy == "3")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.cvars.SoftTargetEnemy == "1")
end)

-- ---------------------------------------------------------------------------------------
-- Our spell buttons with soft targeting on (R40: *type1, no self, focus or mouseover cast)

T("targeting_spell_taps_never_send_the_spell_to_another_unit", function()
    setup()
    Stub.cvars.enableMouseoverCast = "1"
    Stub.setUnit("mouseover", { name = "Friendly Guard" })      -- where the last plain tap left the pointer
    local Contract = ns.Contract
    for i = 1, 7 do
        local key = (select(1, Contract.KeysFor("spell" .. i)))
        assert(key and key:find("^ALT%-CTRL%-SHIFT%-"), "the app holds Alt (the game's self-cast key) with every key")
        Stub.lastActionUnit = "unset"
        Stub.pressKey(key)
        assert(Stub.lastActionUnit == nil, "spell" .. i .. " went to " .. tostring(Stub.lastActionUnit))
    end
end)

-- ---------------------------------------------------------------------------------------
-- /touch targeting: what the client has, for the device check

T("targeting_status_names_every_cvar_and_the_unknown_ones", function()
    setup({ before = function() Stub.cvars.SoftTargetIconEnemy = nil end })
    SlashCmdList.TOUCHPLAY("targeting")
    assert(Stub.printed("SoftTargetEnemy") >= 1)
    assert(Stub.printed("not in this client") >= 1, "SoftTargetIconEnemy is named as unknown")
    assert(Stub.printed("SoftTargetEnemyArc") >= 1, "the arc is shown too (read only)")
    assert(type(TouchPlayDB.targetLog) == "table" and #TouchPlayDB.targetLog >= 1, "kept for the Mac")
    assert(ns.db.enabled, "/touch targeting is not /touch")
end)

Stub.done("targeting")
