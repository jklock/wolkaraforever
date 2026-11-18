-- Task 5: the player card, the target card and the cast bars (mockups 01, 02, 19, 20, 70, 74, 77).
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

-- A game session with the add-on loaded and laid out.
local function setup()
    Stub.reset()
    Stub.load("Core.lua", "Text.lua", "Style.lua", "Cluster.lua", "Units.lua", "Contract.lua")
    Stub.login()
    return ns.Units
end

T("level_colours", function()
    setup()
    local Units = ns.Units
    assert(select(2, Units.LevelText(37, 34)) == 1 and select(3, Units.LevelText(37, 34)) < 0.6) -- orange
    assert(Units.LevelText(44, 34) == "skull" and Units.LevelText(-1, 34) == "skull")
    assert(Units.LevelText(43, 34) == "43", "nine above is still a number")
    local text, r, g, b = Units.LevelText(34, 34); assert(text == "34" and r == 1 and near(g, 0.82) and b == 0, "yellow")
    text, r, g, b = Units.LevelText(40, 34); assert(r == 1 and g < 0.2, "red, five or more above")
    text, r, g, b = Units.LevelText(30, 34); assert(g > 0.7 and r < 0.5, "green, a little below")
    text, r, g, b = Units.LevelText(21, 34); assert(near(r, 0.5) and near(g, 0.5) and near(b, 0.5), "grey, far below")
end)

T("frame_art_by_classification", function()
    local U = setup()
    assert(U.FrameArt("rareelite"):find("Rare%-Elite"))
    assert(U.FrameArt("normal") == "Interface\\TargetingFrame\\UI-TargetingFrame")
    assert(U.FrameArt("elite"):find("Elite") and not U.FrameArt("elite"):find("Rare"))
    assert(U.FrameArt("rare"):find("Rare") and not U.FrameArt("rare"):find("Elite"))
    assert(U.KindOf("worldboss") == "elite" and U.KindOf("trivial") == "normal" and U.KindOf("rareelite") == "rareelite")
end)

T("cards_use_the_art_at_scale_1_5_in_the_mockup_places", function()
    local U = setup()
    assert(U.player:GetName() == "TouchPlayPlayer" and U.target:GetName() == "TouchPlayTarget")
    for _, card in ipairs({ U.player, U.target }) do
        assert(near(card:GetWidth(), 232 * 1.5) and near(card:GetHeight(), 100 * 1.5))
        assert(card.frameArt.texture:find("TargetingFrame"))
    end
    local x, y = Stub.centre(U.player); assert(near(x, 10 + 174) and near(y, 8 + 75))
    x, y = Stub.centre(U.target); assert(near(x, 360 + 174) and near(y, 8 + 75))
    -- the player's art is mirrored, the target's is not
    assert(U.player.frameArt.texCoord[1] == 1 and U.target.frameArt.texCoord[1] < 0.1)
end)

T("cards_are_secure_action_buttons", function()
    local U = setup()
    for unit, card in pairs({ player = U.player, target = U.target }) do
        assert(Stub.inherits(card, "SecureActionButtonTemplate"), "an action button: the app's keys hold modifiers (R47)")
        assert(card:GetAttribute("unit") == unit and card:GetAttribute("*type1") == "target")
        assert(card:GetAttribute("type2") == nil and card:GetAttribute("type") == nil)
        assert(card.clicks and card.clicks[1] == "AnyUp")
    end
end)

T("tap_targets_self_hold_never_acts", function()
    local U = setup()
    Stub.click("TouchPlayPlayer", "LeftButton")
    assert(Stub.lastTargeted == "player" and Stub.calls.TargetUnit == 1, "a tap targets yourself")
    Stub.click("TouchPlayPlayer", "RightButton")
    assert(Stub.calls.TargetUnit == 1 and #Stub.secureActions == 1, "a hold does nothing else, no menu")
    Stub.click("TouchPlayTarget", "RightButton")
    assert(#Stub.secureActions == 1)
end)

T("hold_asks_the_info_card_with_the_frame", function()
    local U = setup(); local asked
    ns.InfoCard = { Show = function(what, frame) asked = { what = what, frame = frame } end }
    Stub.click("TouchPlayPlayer", "RightButton")
    assert(asked and asked.what.kind == "unit" and asked.what.unit == "player" and asked.frame == U.player)
    asked = nil; Stub.click("TouchPlayTarget", "RightButton")
    assert(asked and asked.what.unit == "target" and asked.frame == U.target)
    asked = nil; Stub.click("TouchPlayTarget", "LeftButton"); Stub.click("TouchPlayPlayer", "LeftButton")
    assert(asked == nil, "a tap does not open the card")
end)

T("hold_before_the_info_card_exists_does_nothing", function()
    setup(); Stub.click("TouchPlayPlayer", "RightButton"); assert(not ns.paused)
end)

T("no_target_hides_card", function()
    local U = setup()
    Stub.setTarget(nil); assert(not U.target:IsShown())
    assert(Stub.unitWatched(U.target), "the game hides and shows it from secure code")
    Stub.setTarget("enemy"); assert(U.target:IsShown())
    Stub.setTarget(nil); assert(not U.target:IsShown())
    assert(U.player:IsShown())
end)

T("out_of_range_fades", function()
    local U = setup()
    Stub.setTarget("enemy", { range = false }); assert(U.target:GetAlpha() < 0.6)
    Stub.setTarget("enemy", { range = true }); assert(U.target:GetAlpha() == 1)
    Stub.setTarget("enemy", { range = false }); assert(U.target:GetAlpha() < 0.6)
    Stub.setTarget("friendly", {}); assert(U.target:GetAlpha() == 1, "a friendly NPC is not judged by an attack spell")
    Stub.setTarget("player", { inParty = true, range = false }); assert(U.target:GetAlpha() < 0.6, "party member by UnitInRange")
    Stub.setUnit("target", { range = true }); Stub.fire("UNIT_IN_RANGE_UPDATE", "target")
    assert(U.target:GetAlpha() == 1)
end)

T("name_bar_colours", function()
    local U = setup()
    local function colour(kind, opts) Stub.setTarget(kind, opts); return U.NameBarColour("target") end
    local r, g, b = colour("enemy"); assert(r > 0.5 and g == 0 and b == 0, "red")
    r, g, b = colour("neutral"); assert(r > 0.5 and g > 0.5 and b == 0, "yellow")
    r, g, b = colour("friendly"); assert(r == 0 and g > 0.4 and b == 0, "green")
    r, g, b = colour("player"); assert(r == 0 and b > 0.5, "blue")
    r, g, b = colour("enemy", { tapDenied = true }); assert(near(r, g) and near(g, b), "grey: tagged by someone else")
    r, g, b = colour("enemy", { dead = true }); assert(near(r, g) and near(g, b), "grey: dead")
    -- a hostile player is red; an unflagged player who cannot attack us is blue; a flagged friend is green
    r, g, b = colour("player", { canAttackUs = true, canAttack = true }); assert(r > 0.5 and g == 0)
    r, g, b = colour("player", { pvp = true }); assert(g > 0.4 and r == 0 and b == 0)
    -- the name bar on the card carries it
    Stub.setTarget("friendly"); assert(U.target.nameBg.vertex[2] > 0.4 and U.target.nameBg.vertex[1] == 0)
    Stub.setTarget("enemy"); assert(U.target.nameBg.vertex[1] > 0.5 and U.target.nameBg.vertex[2] == 0)
    assert(U.player.nameBg == nil, "the player card has no name bar")
end)

T("target_card_follows_the_target", function()
    local U = setup()
    Stub.setTarget("elite", { health = 620, healthMax = 1000 })
    assert(U.target.nameText:GetText() == "Deathguard Elite")
    assert(U.target.frameArt.texture == U.FrameArt("elite"))
    assert(U.target.levelText:GetText() == "35" and near(U.target.levelText.textColor[2], 0.82), "one above is yellow")
end)

T("level_colour_on_the_card", function()
    local U = setup()
    Stub.setTarget("enemy", { level = 38 })
    local c = U.target.levelText.textColor; assert(c[1] == 1 and c[2] < 0.6, "four above is orange")
    Stub.setTarget("neutral"); c = U.target.levelText.textColor; assert(near(c[1], 0.5), "grey: far below")
    assert(U.target.levelText:GetText() == "21")
    c = U.player.levelText.textColor; assert(U.player.levelText:GetText() == "34" and c[1] == 1 and near(c[2], 0.82))
end)

T("rare_and_rare_elite_art_and_skull", function()
    local U = setup()
    Stub.setTarget("rare"); assert(U.target.frameArt.texture:find("Rare") and not U.target.frameArt.texture:find("Elite"))
    Stub.setTarget("rareelite"); assert(U.target.frameArt.texture:find("Rare%-Elite"))
    Stub.setTarget("boss")
    assert(U.target.skull:IsShown() and U.target.levelText:GetText() == "")
    assert(U.target.frameArt.texture == U.FrameArt("elite"))
    Stub.setTarget("enemy"); assert(not U.target.skull:IsShown() and U.target.levelText:GetText() == "32")
end)

T("health_and_power_go_straight_to_the_bars", function()
    local U = setup()
    local bar = U.player.healthBar
    assert(bar.minValue == 0 and bar.maxValue == 1460 and bar.value == 1284)
    assert(U.player.healthText.formatArgs[1] == 1284 and U.player.healthText.formatArgs[2] == 1460)
    assert(U.player.powerBar.maxValue == 100 and U.player.powerBar.value == 64)
    Stub.setUnit("player", { health = 1000 }); Stub.fire("UNIT_HEALTH", "player")
    assert(bar.value == 1000 and U.player.healthText.formatArgs[1] == 1000)
    Stub.setUnit("player", { power = 20 }); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(U.player.powerBar.value == 20)
    Stub.setTarget("elite", { health = 620, healthMax = 1000, powerType = 3, powerToken = "ENERGY" })
    assert(U.target.healthText.text == "%d%%" and near(U.target.healthText.formatArgs[1], 62), "the target reads a percent")
    assert(U.target.powerBar.barColor[1] == 1 and U.target.powerBar.barColor[2] == 1, "energy is yellow")
end)

T("dead_and_ghost_words", function()
    local U = setup()
    Stub.setDead("player", "ghost"); assert(U.player.healthText:GetText() == ns.L["unit.ghost"])
    assert(U.player.portrait.desaturated and U.player.portrait.vertex[3] > U.player.portrait.vertex[1], "pale blue")
    Stub.setDead("player", "dead"); assert(U.player.healthText:GetText() == ns.L["unit.dead"])
    assert(U.player.portrait.desaturated and U.player.portrait.vertex[1] < 0.6, "grey")
    Stub.setDead("player", nil); assert(not U.player.portrait.desaturated and U.player.healthText.text == "%d / %d")
    assert(ns.L["unit.ghost"] == "Ghost" and ns.L["unit.dead"] == "Dead")
    Stub.setTarget("enemy"); Stub.setDead("target", "dead")
    assert(U.target.healthText:GetText() == "Dead" and U.target.portrait.desaturated)
    local v = U.target.nameBg.vertex; assert(near(v[1], v[2], 0.001) and near(v[2], v[3], 0.001), "grey name bar")
end)

T("tapped_target_goes_grey", function()
    local U = setup()
    Stub.setTarget("enemy", { tapDenied = true })
    local c = U.target.healthBar.barColor; assert(near(c[1], c[2], 0.05) and near(c[2], c[3], 0.05), "grey health bar")
    Stub.setTarget("enemy"); c = U.target.healthBar.barColor; assert(c[2] > 0.8 and c[1] == 0, "green again")
end)

T("fight_resting_leader_and_pvp_states", function()
    local U = setup(); local p = U.player
    assert(not p.swords:IsShown() and not p.rest:IsShown()
        and not p.crown:IsShown() and not p.pvp:IsShown() and p.levelText:IsShown())
    Stub.setUnit("player", { combat = true }); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(p.swords:IsShown() and not p.levelText:IsShown(), "swords where the level was")
    Stub.setUnit("player", { combat = false }); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not p.swords:IsShown() and p.levelText:IsShown())
    Stub.setResting(true); assert(p.rest:IsShown() and p.rest:GetText() == "zzz")
    Stub.setResting(false); assert(not p.rest:IsShown())
    Stub.setUnit("player", { leader = true }); Stub.fire("PARTY_LEADER_CHANGED"); assert(p.crown:IsShown())
    Stub.setUnit("player", { leader = false }); Stub.fire("PARTY_LEADER_CHANGED"); assert(not p.crown:IsShown())
    Stub.setUnit("player", { pvp = true }); Stub.fire("UNIT_FACTION", "player")
    assert(p.pvp:IsShown() and p.pvp.texture:find("Alliance"))
    Stub.setUnit("player", { pvp = false }); Stub.fire("UNIT_FACTION", "player"); assert(not p.pvp:IsShown())
end)

-- iPad run 7 (17 Nov): "that is not a combat glow, it's just a red box around the frame - remove it altogether."
-- The card draws no glow box at all, in a fight or at low health; the crossed swords on the level badge are the
-- in-fight sign and the screen's red edge (Hud.lua) the low-health one. The art is gone too.
local function readFile(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

T("the_card_draws_no_glow_box_in_a_fight_or_at_low_health", function()
    local U = setup(); local p = U.player
    for _, key in ipairs({ "combatGlow", "combatFill", "lowGlow", "pulse", "pulseGroup" }) do
        assert(p[key] == nil, "no " .. key .. " on the card")
    end
    assert(U.CARD_GLOW == nil and ns.Kit.ART_CARD_GLOW == nil, "no glow box numbers or art path")
    local src = readFile("addon/TouchPlay/Units.lua")
    assert(not src:find("UI-Player-Status", 1, true) and not src:find("CardGlow", 1, true))
    assert(not readFile("tools/make-art.py"):find("CARD_GLOW", 1, true), "make-art.py draws no card glow")
    assert(io.open("addon/TouchPlay/Art/CardGlow.tga", "rb") == nil, "Art/CardGlow.tga is deleted")
    Stub.setUnit("player", { combat = true }); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(p.swords:IsShown() and not p.levelText:IsShown(), "the swords are the in-fight sign")
    Stub.setUnit("player", { combat = false }); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not p.swords:IsShown() and p.levelText:IsShown())
end)

-- R43: the step curve goes to UnitHealthPercent (the game evaluates it); its input runs 0 to 1, so the step is 0.25.
-- Low health shows on the screen's red edge only (run 7: no box on the card).
T("low_health_shows_on_the_screen_edge_at_a_quarter", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local curve = ns.Units.LowCurve()
    assert(curve.kind == Enum.LuaCurveType.Step and curve.points[2].x == 0.25, "the step at a quarter")
    Stub.setUnit("player", { health = 400, healthMax = 1460 }); Stub.fire("UNIT_HEALTH", "player")
    assert(ns.Hud.edge.low:GetAlpha() == 0, "27 %: no red edge")
    Stub.setUnit("player", { health = 300 }); Stub.fire("UNIT_HEALTH", "player")
    assert(ns.Hud.edge.low:GetAlpha() == 1, "20 %: the screen edge")
end)

T("low_health_without_maths", function()
    local U = setup(); Stub.secretUnits(true)
    Stub.fire("UNIT_HEALTH", "player"); Stub.fire("UNIT_MAXHEALTH", "player"); Stub.fire("UNIT_POWER_UPDATE", "player")
    assert(not ns.paused, ns.lastError)
    assert(Stub.isSecret(U.player.healthBar.value))
    assert(Stub.isSecret(U.player.healthText.formatArgs[1]), "the text got the hidden value as it was")
end)

T("cast_bars_sit_where_the_mockups_put_them", function()
    local U = setup()
    local a = U.playerCast.touchAnchor
    assert(a.x == 483 and a.y == 700 and a.w == 400, "under the centre, 400 wide")
    assert(near(a.x + a.w / 2, 683), "centred on the 1366 screen")
    local t, card = U.targetCast.touchAnchor, U.target.touchAnchor
    assert(t.y >= card.y + card.h and t.x >= card.x and t.x + t.w <= card.x + card.w, "under the target card")
end)

T("player_cast_gold_interruptible", function()
    local U = setup(); local holder, bar = U.playerCast, U.playerCast.bar
    assert(not holder:IsShown())
    Stub.setUnit("player", { cast = { name = "Fireball", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_START", "player")
    assert(holder:IsShown() and bar.text:GetText() == "Fireball")
    assert(bar.timerDuration and bar.timerDuration.duration == "cast")
    assert(bar.timerDirection == Enum.StatusBarTimerDirection.ElapsedTime, "it fills")
    assert(near(bar.barColor[1], 1) and near(bar.barColor[2], 0.76), "gold")
    assert(bar.shield.alpha == 0)
    Stub.setUnit("player", { cast = false }); Stub.fire("UNIT_SPELLCAST_STOP", "player")
    assert(not holder:IsShown())
end)

T("target_cast_grey_with_a_shield_when_it_cannot_be_interrupted", function()
    local U = setup(); Stub.setTarget("elite")
    local bar = U.targetCast.bar
    Stub.setUnit("target", { cast = { name = "Shadow Bolt", notInterruptible = true } })
    Stub.fire("UNIT_SPELLCAST_START", "target")
    assert(U.targetCast:IsShown() and bar.text:GetText() == "Shadow Bolt")
    assert(bar.barColor[1] == bar.barColor[2] and bar.barColor[2] == bar.barColor[3], "grey")
    assert(bar.shield.alpha == 1 and bar.shield.alphaFromBoolean[1] == true)
    Stub.setUnit("target", { cast = { name = "Shield Bash", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    assert(bar.barColor[1] == 1 and bar.shield.alpha == 0, "interruptible again")
    Stub.setUnit("target", { cast = false }); Stub.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
    assert(not U.targetCast:IsShown())
end)

T("channelling_is_green_and_drains", function()
    local U = setup(); local bar = U.playerCast.bar
    Stub.setUnit("player", { cast = { name = "Arcane Missiles", channel = true, notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player")
    assert(U.playerCast:IsShown() and bar.text:GetText() == "Arcane Missiles")
    assert(bar.timerDuration.duration == "channel" and bar.timerDirection == Enum.StatusBarTimerDirection.RemainingTime)
    assert(bar.barColor[2] > 0.8 and bar.barColor[1] < 0.3 and bar.barColor[3] < 0.3, "green")
    Stub.setUnit("player", { cast = false }); Stub.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    assert(not U.playerCast:IsShown())
end)

T("target_change_clears_the_old_cast", function()
    local U = setup(); Stub.setTarget("elite", { cast = { name = "Shadow Bolt", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_START", "target"); assert(U.targetCast:IsShown())
    Stub.setTarget("friendly"); assert(not U.targetCast:IsShown())
    Stub.setTarget("elite", { cast = { name = "Shadow Bolt", notInterruptible = false } })
    assert(U.targetCast:IsShown(), "a target that is already casting shows its bar")
    Stub.setTarget(nil); assert(not U.targetCast:IsShown())
end)

T("secret_values_never_touched", function()
    local U = setup(); Stub.secretUnits(true)
    Stub.setTarget("elite", { cast = { name = "Shadow Bolt", notInterruptible = true } })
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_LEVEL", "UNIT_FLAGS" }) do
        Stub.fire(event, "target"); Stub.fire(event, "player")
    end
    Stub.setUnit("target", { cast = { name = "Arcane Missiles", channel = true, notInterruptible = true } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "target")
    assert(not ns.paused, ns.lastError)
    assert(U.targetCast:IsShown() and Stub.isSecret(U.targetCast.bar.text:GetText()), "straight to the text")
    assert(Stub.isSecret(U.targetCast.bar.shield.alphaFromBoolean[1]), "straight to the shield")
    assert(Stub.isSecret(U.target.healthBar.value))
    Stub.fire("PLAYER_TARGET_CHANGED"); Stub.fire("PLAYER_ENTERING_WORLD"); assert(not ns.paused, ns.lastError)
end)

T("a_fight_never_blocks_the_cards", function()
    local U = setup(); Stub.combat(true)
    Stub.setTarget("elite", { range = false, cast = { name = "Shadow Bolt", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_START", "target"); Stub.fire("UNIT_HEALTH", "target"); Stub.fire("UNIT_HEALTH", "player")
    Stub.setUnit("player", { combat = true }); Stub.fire("PLAYER_REGEN_DISABLED")
    ns.Each("Refresh")
    assert(not ns.paused, ns.lastError)
    assert(U.target:IsShown() and U.target:GetAlpha() < 0.6 and U.targetCast:IsShown())
    Stub.setTarget(nil); assert(not U.target:IsShown(), "the unit watch hides it in a fight")
end)

T("layout_waits_for_the_end_of_a_fight", function()
    local U = setup(); local before = U.player.calls.SetPoint
    Stub.combat(true); ns.Units:Layout()
    assert(U.player.calls.SetPoint == before and not ns.paused)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(U.player.calls.SetPoint > before)
end)

T("areas_registered_with_the_contract", function()
    local U = setup()
    local text = ns.Contract.Write()
    assert(text:find("player,TL,10,8,348,150,", 1, true), text)
    assert(text:find("target,TL,360,8,348,150,", 1, true), text)
    ns.Contract.Apply()
    local tap, hold = ns.Contract.KeysFor("player")
    local t = Stub.bindings[tap]; assert(t and t.click == "TouchPlayPlayer" and t.button == "LeftButton")
    local h = Stub.bindings[hold]; assert(h and h.click == "TouchPlayPlayer" and h.button == "RightButton")
    tap, hold = ns.Contract.KeysFor("target")
    t = Stub.bindings[tap]; assert(t and t.click == "TouchPlayTarget" and t.button == "LeftButton")
    h = Stub.bindings[hold]; assert(h and h.click == "TouchPlayTarget" and h.button == "RightButton")
end)

T("units_load_before_the_contract_in_the_toc", function()
    local order = {}
    for line in io.lines("addon/TouchPlay/TouchPlay.toc") do order[#order + 1] = line:gsub("\r", "") end
    local units, contract
    for i, line in ipairs(order) do
        if line == "Units.lua" then units = i end
        if line == "Contract.lua" then contract = i end
    end
    assert(units and contract and units < contract and contract == #order)
end)

T("unit_events_are_asked_for_by_unit", function()
    local U = setup()
    -- one frame takes the unit events; no frame of ours listens to UNIT_HEALTH any other way
    local count = 0
    for _, f in ipairs({ U.player, U.target, U.playerCast, U.targetCast }) do
        if f.events.UNIT_HEALTH then count = count + 1 end
    end
    assert(count == 0)
    Stub.setUnit("player", { health = 500 }); Stub.fire("UNIT_HEALTH", "player")
    assert(U.player.healthBar.value == 500)
    Stub.fire("UNIT_HEALTH", "party1"); assert(not ns.paused, "other units are ignored")
end)

T("paused_addon_ignores_unit_events", function()
    local U = setup(); ns.Pause("test")
    Stub.setUnit("player", { health = 77 }); Stub.fire("UNIT_HEALTH", "player")
    assert(U.player.healthBar.value ~= 77)
end)

T("hidden_unit_in_range_answer_is_never_tested", function()
    local U = setup()
    Stub.setTarget("player", { inParty = true, range = false }); assert(U.target:GetAlpha() < 0.6)
    Stub.secretRange(true)
    Stub.fire("UNIT_IN_RANGE_UPDATE", "target"); Stub.fire("PLAYER_TARGET_CHANGED")
    assert(not ns.paused, ns.lastError)
    assert(U.target:GetAlpha() == 1, "a hidden answer counts as in range")
    Stub.setTarget("enemy", { range = false }); assert(not ns.paused, ns.lastError)
end)

-- SetTimerDuration refuses a hidden duration from add-on code: the call sits in a pcall, the cast still shows.
T("hidden_cast_duration_is_never_tested_and_never_pauses", function()
    local U = setup(); Stub.secretDurations(true)
    Stub.setTarget("elite", { cast = { name = "Shadow Bolt", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_START", "target")
    assert(not ns.paused, ns.lastError)
    local bar = U.targetCast.bar
    assert(U.targetCast:IsShown() and bar.text:GetText() == "Shadow Bolt", "the cast shows")
    assert(Stub.isSecret(bar.timeBinding.duration), "the time binding has it")
    Stub.setUnit("target", { cast = { name = "Arcane Missiles", channel = true, notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "target")
    assert(not ns.paused, ns.lastError)
    Stub.secretDurations(false); Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "target")
    assert(bar.timerDirection == Enum.StatusBarTimerDirection.RemainingTime and not Stub.isSecret(bar.timerDuration))
    assert(bar.timerInterpolation == Enum.StatusBarInterpolation.Immediate, "Immediate, as the Hud's timer bars")
    Stub.setUnit("target", { cast = false }); Stub.fire("UNIT_SPELLCAST_STOP", "target")
    assert(not U.targetCast:IsShown() and not bar.timeBinding.enabled, "no cast: no duration, bar hides")
end)

T("time_left_comes_from_a_duration_text_binding", function()
    local U = setup()
    local bar = U.playerCast.bar
    local binding = bar.timeBinding
    assert(binding and binding.fontString == bar.timeText, "the binding writes the time font string")
    assert(binding.components[1].property == Enum.DurationTextBindingProperty.RemainingDuration
        and binding.components[1].formatter.kind == "seconds" and binding.format == "{}")
    assert(not binding.enabled)
    Stub.setUnit("player", { cast = { name = "Fireball", notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_START", "player")
    assert(binding.enabled and binding.duration and binding.duration.duration == "cast")
    Stub.setUnit("player", { cast = false }); Stub.fire("UNIT_SPELLCAST_STOP", "player")
    assert(not binding.enabled)
    Stub.setUnit("player", { cast = { name = "Arcane Missiles", channel = true, notInterruptible = false } })
    Stub.fire("UNIT_SPELLCAST_CHANNEL_START", "player")
    assert(binding.enabled and binding.duration.duration == "channel")
    assert(bar.timeText.scripts.OnUpdate == nil and bar.scripts.OnUpdate == nil and U.playerCast.scripts.OnUpdate == nil)
    assert(#Stub.bindingsMade == 2, "one binding per cast bar, made once")
end)

-- Units' own yes/no helper is named for what it answers, so it is never mistaken for ns.Plain.
T("units_has_no_second_plain", function()
    local f = assert(io.open("addon/TouchPlay/Units.lua")); local text = f:read("*a"); f:close()
    assert(not text:find("local function Plain(", 1, true), "a local Plain that answers truthiness")
end)

Stub.done("units")
