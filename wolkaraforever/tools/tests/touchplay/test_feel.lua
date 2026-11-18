-- Task 14: Touch settings (the feel), left-handed mirroring, reduce motion (mockups 31, 87, 88).
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return ns.Feel
end

local function centreX(frame)
    local a = frame.touchAnchor
    return a.x + a.w / 2
end

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

-- ---------------------------------------------------------------------------------------
-- Defaults: one table, the contract's

T("feel_defaults", function()
    local Feel = setup()
    local d = ns.Contract.FEEL_DEFAULTS
    local want = { leftHanded = false, stand = false, buttonSize = 1.0, textSize = 1.0, hold = 0.45,
        turnWithView = true, edgeRun = true, holdRisky = true, tapSounds = true, floatingNumbers = true,
        reduceMotion = "auto", autoTarget = true, bigPlates = true,      -- Targeting (18 Nov, Claude's default)
        sharpScreen = true }                                             -- ruling A39 (18 Nov)
    for k, v in pairs(want) do assert(d[k] == v, "default " .. k .. " is " .. tostring(d[k])) end
    for k in pairs(d) do assert(want[k] ~= nil, "no key outside the plan: " .. k) end
    for k, v in pairs(want) do assert(Feel.Get(k) == v, "Get(" .. k .. ")") end
    assert(ns.db.feel == nil or next(ns.db.feel) == nil, "nothing is saved until something changes")
end)

T("feel_get_falls_back_on_odd_values", function()
    local Feel = setup()
    ns.db.feel = { hold = "slow", leftHanded = 3, buttonSize = 9, textSize = 0, holdRisky = "yes", reduceMotion = 5 }
    assert(Feel.Get("hold") == 0.45 and Feel.Get("leftHanded") == false)
    assert(Feel.Get("buttonSize") == 1.4, "clamped to the top of its range")
    assert(Feel.Get("textSize") == 0.8, "clamped to the bottom of its range")
    assert(Feel.Get("holdRisky") == true and Feel.Get("reduceMotion") == "auto")
end)

T("feel_set_validates_and_saves", function()
    local Feel = setup()
    Feel.Set("hold", 0.6); assert(ns.db.feel.hold == 0.6)
    Feel.Set("hold", 5); assert(ns.db.feel.hold == 0.8, "hold stops at 0.8")
    Feel.Set("hold", 0.01); assert(ns.db.feel.hold == 0.3, "hold starts at 0.3")
    Feel.Set("turnWithView", false); assert(ns.db.feel.turnWithView == false)
    Feel.Set("hold", "fast"); assert(ns.db.feel.hold == 0.3, "a word changes nothing")
    Feel.Set("nonsense", true); assert(ns.db.feel.nonsense == nil, "an unknown key is not saved")
end)

-- ---------------------------------------------------------------------------------------
-- A change rewrites the contract

T("feel_change_rewrites_contract", function()
    local Feel = setup()
    assert(TouchPlayDB.contract:find("hold=0.45;", 1, true))
    Feel.Set("hold", 0.6)
    assert(TouchPlayDB.contract:find(";hold=0.6;", 1, true), TouchPlayDB.contract)
    Feel.Set("turnWithView", false)
    assert(TouchPlayDB.contract:find(";turn=0;", 1, true), TouchPlayDB.contract)
    assert(not ns.paused, ns.lastError)
end)

T("feel_layout_change_in_a_fight_waits", function()
    local Feel = setup()
    local before = TouchPlayDB.contract
    Stub.combat(true)
    Feel.Set("leftHanded", true)
    Stub.advance(1)
    assert(TouchPlayDB.contract == before, "the layout waits for the end of the fight")
    assert(not ns.paused, ns.lastError)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(TouchPlayDB.contract:find(";hand=L;", 1, true), TouchPlayDB.contract)
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Left-handed

T("left_handed_mirrors_cluster", function()
    local Feel = setup()
    local primary = ns.Cluster.buttons[1]
    assert(near(centreX(primary), 1268), "right-handed: centre x 1268")
    Feel.Set("leftHanded", true); Stub.advance(1)
    assert(near(centreX(primary), 98), "mirrored: centre x " .. centreX(primary))
    assert(primary.touchAnchor.corner == "BL" and primary.touchAnchor.mirrored)
    -- the whole thumb side moves: ring buttons, page boxes, Next target, item column, Interact, Jump, Dive
    for _, f in ipairs({ ns.Cluster.buttons[4], ns.Cluster.pageBoxes[1], ns.Cluster.nextTarget,
        ns.ItemRail.buttons[1], ns.Interact.interact, ns.Interact.jump, ns.Interact.dive }) do
        assert(f.touchAnchor.mirrored and centreX(f) < 683, "on the left now: " .. tostring(f.name or f.kind))
    end
    -- x -> 1366 - x - w
    local jump = ns.Interact.jump.touchAnchor
    assert(near(jump.x, 1366 - 1118 - 58), jump.x)
    -- the card, the minimap, Bags and Menu stay
    for _, f in ipairs({ ns.Units.player, ns.Hud.bags, ns.Hud.menu, ns.Hud.minimap }) do
        assert(not f.touchAnchor.mirrored, "stays where it is")
    end
    assert(near(centreX(ns.Hud.bags), 968 + 30), "Bags stays")
    -- the quest list moves to x 380 (mockup 87), under the game's buffs (iPad run 7: y 380, not 200)
    local q = ns.Hud.quest.touchAnchor
    assert(q.x == 380 and q.y >= ns.Auras.Bottom() and q.y <= ns.Auras.Bottom() + 12, q.x .. "," .. q.y)
    -- the chat moves too (mockup 87: strip at x 502)
    assert(near(ns.Chat.strip.touchAnchor.x, 1366 - 296 - 568), ns.Chat.strip.touchAnchor.x)
    assert(not ns.paused, ns.lastError)
end)

T("left_handed_mirrors_the_contract_too", function()
    local Feel = setup()
    local right = TouchPlayDB.contract
    assert(right:find("spell1,BR,", 1, true) and right:find("hand=R", 1, true))
    Feel.Set("leftHanded", true); Stub.advance(1)
    local c = TouchPlayDB.contract
    assert(c:find(";hand=L;", 1, true), c)
    -- spell1 was 88 wide at BR dx 54 (1366-1224-88); now it counts from BL with the same distance
    assert(c:find("spell1,BL,54,", 1, true), c:match("spell1[^|]*"))
    assert(c:find("jump,BL,190,", 1, true), c:match("jump[^|]*"))        -- 1366 - 1118 - 58 = 190
    assert(c:find("chat,BR,", 1, true), "the chat counts from the right corner now")
    assert(c:find("bags,TR,", 1, true) and c:find("menu,TR,", 1, true), "Bags and Menu did not move")
    Feel.Set("leftHanded", false); Stub.advance(1)
    assert(TouchPlayDB.contract == right, "back to the first list")
end)

T("left_handed_off_restores_the_cluster", function()
    local Feel = setup()
    Feel.Set("leftHanded", true); Stub.advance(1)
    Feel.Set("leftHanded", false); Stub.advance(1)
    local primary = ns.Cluster.buttons[1]
    assert(near(centreX(primary), 1268) and primary.touchAnchor.corner == "BR" and not primary.touchAnchor.mirrored)
    assert(ns.Hud.quest.touchAnchor.x == 24)
end)

T("stand_moves_buttons_down", function()
    local Feel = setup()
    local y0 = ns.Cluster.buttons[1].touchAnchor.y
    Feel.Set("stand", true); Stub.advance(1)
    local y1 = ns.Cluster.buttons[1].touchAnchor.y
    assert(y1 > y0, "lower on the screen: " .. y0 .. " -> " .. y1)
    for _, b in ipairs(ns.Cluster.buttons) do
        assert(b.touchAnchor.y + b.touchAnchor.h <= 1024, "never off the screen")
    end
    assert(ns.Hud.bags.touchAnchor.y == 34, "the minimap column stays")
end)

T("button_size_scales_the_thumb_side", function()
    local Feel = setup()
    local b = ns.Cluster.buttons[1]
    assert(b.touchAnchor.w == 88)
    Feel.Set("buttonSize", 1.25); Stub.advance(1)
    assert(near(b.touchAnchor.w, 110) and near(b.touchAnchor.h, 110), b.touchAnchor.w)
    assert(near(b:GetScale(), 1.25))
    -- the nearest corner keeps its distance times the size
    assert(near(1366 - (b.touchAnchor.x + b.touchAnchor.w), (1366 - 1224 - 88) * 1.25, 0.6),
        1366 - (b.touchAnchor.x + b.touchAnchor.w))
    assert(TouchPlayDB.contract:find("spell1,BR,%d+,%d+,110,110"), TouchPlayDB.contract:match("spell1[^|]*"))
    Feel.Set("buttonSize", 1.0); Stub.advance(1)
    assert(b.touchAnchor.w == 88 and b:GetScale() == 1)
end)

T("text_size_scales_the_reading_text", function()
    local Feel = setup()
    assert(ns.Hud.quest:GetScale() == 1 and ns.Chat.lines:GetScale() == 1)
    Feel.Set("textSize", 1.2); Stub.advance(1)
    assert(near(ns.Hud.quest:GetScale(), 1.2) and near(ns.Chat.lines:GetScale(), 1.2))
    assert(near(ns.Hud.quest.touchAnchor.w, 340 * 1.2), "the quest list is wider by the same amount")
    assert(near(ns.Hud.quest.touchAnchor.x, 24 * 1.2), "and keeps its distance times the size from its corner")
    assert(ns.Cluster.buttons[1]:GetScale() == 1, "the buttons follow Button size, not Text size")
    assert(ns.Units.player:GetScale() == 1 and not ns.Units.player.touchAnchor.mirrored, "the cards are not touched")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Reduce motion

T("reduce_motion_follows_the_game_unless_set", function()
    local Feel = setup()
    assert(ns.ReduceMotion() == false)
    Stub.cvars.CameraReduceUnexpectedMovement = "1"
    assert(ns.ReduceMotion() == true, "follows the game's own setting")
    Feel.Set("reduceMotion", false)
    assert(ns.ReduceMotion() == false, "what the player chose wins")
    Feel.Set("reduceMotion", true); Stub.cvars.CameraReduceUnexpectedMovement = "0"
    assert(ns.ReduceMotion() == true)
end)

T("reduce_motion_stops_pulses", function()
    local Feel = setup()
    -- (the player card's low-health pulse is gone since iPad run 7) the spell picker's ring
    Feel.Set("reduceMotion", true)
    Stub.actions[2] = 122
    ns.Picker.Open(2)
    assert(ns.Picker.ring:IsShown() and not ns.Picker.ring.pulse:IsPlaying(), "no pulse on the picker ring")
    Feel.Set("reduceMotion", false)
    ns.Picker.Open(2)
    assert(ns.Picker.ring.pulse:IsPlaying(), "the ring pulses again")
    Feel.Set("reduceMotion", true)
    assert(not ns.Picker.ring.pulse:IsPlaying(), "a pulse already running stops when the setting turns on")
    assert(not ns.paused, ns.lastError)
end)

T("reduce_motion_off_starts_the_pulses_again", function()
    local Feel = setup()
    -- the picker's ring, open while it changes
    Stub.actions[2] = 122; ns.Picker.Open(2)
    Feel.Set("reduceMotion", true); assert(not ns.Picker.ring.pulse:IsPlaying() and ns.Picker.ring:IsShown())
    Feel.Set("reduceMotion", false); assert(ns.Picker.ring.pulse:IsPlaying(), "the ring pulses again")
    Feel.Set("reduceMotion", "auto")
    assert(not ns.paused, ns.lastError)
end)

T("reduce_motion_picker_put_flash_is_still", function()
    local Feel = setup()
    Stub.actions[2] = 122; ns.Picker.Open(2)
    Feel.Set("reduceMotion", true)
    Stub.spellNames[120] = "Cone of Cold"
    ns.Picker.Put(2, { kind = "spell", id = 120 })
    local f = ns.Picker.flash
    assert(f:IsShown() and f.label:GetText() == "Cone of Cold", "the name still shows")
    assert(not f.group:IsPlaying() and not f.glow:IsShown(), "no animation, no glow")
    Stub.advance(2)
    assert(not f:IsShown(), "it goes away by itself")
    Feel.Set("reduceMotion", false)
    ns.Picker.Put(2, { kind = "spell", id = 120 })
    assert(f.group:IsPlaying() and f.glow:IsShown(), "with motion on it flashes as before")
end)

T("picker_ring_follows_the_buttons_size", function()
    local Feel = setup()
    Feel.Set("buttonSize", 1.25); Stub.advance(1)
    Stub.actions[2] = 122; ns.Picker.Open(2)
    local b = ns.Cluster.buttons[2]
    assert(near(ns.Picker.ring:GetWidth(), b:GetWidth() * 1.25 + 10), ns.Picker.ring:GetWidth())
end)

T("reduce_motion_loot_fades_in_place", function()
    local Feel = setup()
    Feel.Set("reduceMotion", true)
    Stub.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:1234::::::::|h[Wool Cloth]|h|r.")
    local toast
    for _, t in ipairs(ns.Loot.toasts) do if t:IsShown() then toast = t end end
    assert(toast, "a toast shows")
    assert(toast.flyX == 0 and toast.flyY == 0, "it does not fly to Bags")
end)

-- ---------------------------------------------------------------------------------------
-- R33: left-handed mirrors everything laid out around the thumb cluster

-- Every touch target on screen now, as { name, x, y, w, h } in layout units (a target under 44 grows to 44 around its
-- centre, as the contract does it). Only what is shown counts: the game's drivers decide that (the pet row or Leave,
-- the quest list or the target card, Dive while swimming or mounted).
local function targets()
    local list = {}
    local function add(name, f)
        local a = f and f.touchAnchor
        if a and f:IsVisible() then
            local w, h = math.max(a.w, 44), math.max(a.h, 44)
            list[#list + 1] = { name = name, x = a.x - (w - a.w) / 2, y = a.y - (h - a.h) / 2, w = w, h = h }
        end
    end
    for i, b in ipairs(ns.Cluster.buttons) do add("spell" .. i, b) end
    for i, b in ipairs(ns.Cluster.pageBoxes) do add("page" .. i, b) end
    add("nexttarget", ns.Cluster.nextTarget)
    for i, b in ipairs(ns.ItemRail.buttons) do add("item" .. i, b) end
    add("interact", ns.Interact.interact); add("jump", ns.Interact.jump); add("dive", ns.Interact.dive)
    add("bags", ns.Hud.bags); add("menu", ns.Hud.menu); add("chat", ns.Chat.strip); add("quest", ns.Hud.quest)
    -- the cards' touch areas are their drawn parts (16 Nov: the pet's card sits under the player's)
    add("player", ns.Units.playerTap); add("target", ns.Units.target); add("minimap", ns.Hud.minimap)
    add("petcard", ns.Units.petTap)
    for i, b in ipairs(ns.ClassBars.pet) do add("pet" .. i, b) end
    add("leave", ns.ClassBars.leave)
    for i, b in ipairs(ns.ClassBars.stance) do add("stance" .. i, b) end
    add("petcall", ns.ClassBars.call); add("petfeed", ns.ClassBars.feed)
    return list
end

local function overlaps()
    local list, found = targets(), {}
    for i = 1, #list do
        local a = list[i]
        if a.x < -0.01 or a.y < -0.01 or a.x + a.w > 1366.01 or a.y + a.h > 1024.01 then
            found[#found + 1] = a.name .. "(off the screen)"
        end
        for j = i + 1, #list do
            local b = list[j]
            -- the ring's own buttons sit on a circle: their boxes touch at the corners by design
            local ring = a.name:match("^spell") and b.name:match("^spell")
            if not ring and a.x < b.x + b.w - 0.01 and b.x < a.x + a.w - 0.01 and a.y < b.y + b.h - 0.01
                and b.y < a.y + a.h - 0.01 then
                found[#found + 1] = a.name .. "/" .. b.name
            end
        end
    end
    return found, #list
end

local function petClass()
    Stub.playerClass = "HUNTER"
    ns.Each("Layout")                       -- the class decides the pet card and the pet row's areas
    Stub.setPet(true)
    for i = 1, 10 do Stub.setPetAction(i, { name = "Pet" .. i, texture = "t", usable = true }) end
    Stub.fire("PET_BAR_UPDATE"); Stub.fire("UNIT_PET", "player")
end

T("left_handed_no_two_touch_targets_overlap_for_a_pet_class", function()
    local Feel = setup(); petClass(); Stub.applyDrivers()
    local found, n = overlaps()
    assert(#found == 0 and n > 30, "right-handed: " .. table.concat(found, " "))
    Feel.Set("leftHanded", true); Stub.advance(1)
    found, n = overlaps()
    assert(#found == 0, "left-handed: " .. table.concat(found, " "))
    assert(n > 30, "the pet row is among them: " .. n)
    Feel.Set("stand", true); Stub.advance(1)
    found = overlaps()
    assert(#found == 0, "on a stand too: " .. table.concat(found, " "))
end)

-- I5: every Button size the slider offers, on a stand or not, either hand, for a pet class with four forms, in each
-- state that shows other buttons (swimming or mounted shows Dive; a vehicle shows Leave; a target hides the quest list).
T("no_two_touch_targets_overlap_at_any_selectable_setting", function()
    local problems = {}
    for _, size in ipairs({ 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4 }) do
        for _, left in ipairs({ false, true }) do
            for _, stand in ipairs({ false, true }) do
                local Feel = setup(); petClass()
                Stub.setForms({ { name = "Bear Form", spell = 5487 }, { name = "Aquatic Form", spell = 1066 },
                    { name = "Cat Form", spell = 768 }, { name = "Travel Form", spell = 783 } })
                Feel.Set("buttonSize", size); Feel.Set("leftHanded", left); Feel.Set("stand", stand); Stub.advance(1)
                local label = ("size %.1f %s%s"):format(size, left and "left" or "right", stand and " stand" or "")
                local function check(state)
                    Stub.applyDrivers(); Stub.applyUnitWatch()
                    local found = overlaps()
                    if #found > 0 then problems[#problems + 1] = label .. " " .. state .. ": " .. table.concat(found, " ") end
                end
                check("idle")
                Stub.setSwimming(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
                assert(ns.Interact.dive:IsShown(), "dive shows")
                check("swimming")
                Stub.setSwimming(false); Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
                check("mounted")
                Stub.setMounted(false); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
                Stub.setTarget("enemy")
                check("target")
                Stub.setTarget(nil); Stub.setVehicle(true)
                check("vehicle")
                Stub.setVehicle(false)
                -- the pet's states (mockup 21): unhappy shows Feed pet; dead and none show Revive / Call pet
                Stub.setPetHappiness(1)
                check("unhappy")
                Stub.setPetHappiness(3); Stub.setDead("pet", "dead"); Stub.fire("UNIT_PET", "player")
                check("pet dead")
                Stub.setPet(false)
                check("no pet")
                assert(not ns.paused, ns.lastError)
            end
        end
    end
    assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
end)

-- iPad run 5: the game's buffs ran under the Bags orb, next to the app's top-centre toolbar. Auras moves them to the
-- band under the target card (iPad run 7: at 0.85 scale or more, so they can be read). The area they take with none,
-- one, a row and two rows of buffs (11 to a row) and of debuffs (8 to a row) never meets a touch target or the app's
-- toolbar bands, at every Button size, either hand, on a stand or not, in each state that shows other buttons.
local function hits(a, b)
    return a.x < b.x + b.w - 0.01 and b.x < a.x + a.w - 0.01 and a.y < b.y + b.h - 0.01 and b.y < a.y + a.h - 0.01
end

T("buffs_and_debuffs_clear_of_every_touch_target_and_the_app_toolbar", function()
    local problems = {}
    for _, size in ipairs({ 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4 }) do
        for _, left in ipairs({ false, true }) do
            for _, stand in ipairs({ false, true }) do
                local Feel = setup(); petClass()
                Stub.setForms({ { name = "Bear Form", spell = 5487 }, { name = "Aquatic Form", spell = 1066 },
                    { name = "Cat Form", spell = 768 }, { name = "Travel Form", spell = 783 } })
                Feel.Set("buttonSize", size); Feel.Set("leftHanded", left); Feel.Set("stand", stand); Stub.advance(1)
                local label = ("size %.1f %s%s"):format(size, left and "left" or "right", stand and " stand" or "")
                local function check(state)
                    Stub.applyDrivers(); Stub.applyUnitWatch()
                    local list = targets()
                    for _, band in ipairs(ns.AppBands()) do list[#list + 1] = band end
                    -- none, one, a row and two rows of buffs, each with none, one, a row and two rows of debuffs
                    for _, b in ipairs({ 0, 1, 11, 22 }) do for _, d in ipairs({ 0, 1, 8, 16 }) do
                        local counts = { b, d }
                        local x, y, w, h = ns.Auras.Area(counts[1], counts[2])
                        if x then
                        local area = { x = x, y = y, w = w, h = h }
                        if area.x < 0 or area.y < 0 or area.x + area.w > 1366 then
                            problems[#problems + 1] = label .. " " .. state .. ": buffs off the screen"
                        end
                        for _, t in ipairs(list) do
                            if hits(area, t) then
                                problems[#problems + 1] = ("%s %s: %d buffs %d debuffs meet %s"):format(label, state,
                                    counts[1], counts[2], t.name)
                            end
                        end
                        end
                    end end
                    -- iPad run 7: at 0.64 / 0.5 they were too small to read; 0.85 or more at every setting
                    local _, _, scale = ns.Auras.Place()
                    if scale < 0.85 then problems[#problems + 1] = label .. " " .. state .. ": scale " .. scale end
                end
                assert(ns.Auras.Area(0, 0) == nil, "no buffs: no area")
                check("idle")
                Stub.setSwimming(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED"); check("swimming")
                Stub.setSwimming(false); Stub.setMounted(true); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED"); check("mounted")
                Stub.setMounted(false); Stub.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
                Stub.setTarget("enemy"); check("target")
                Stub.setTarget(nil); Stub.setVehicle(true); check("vehicle")
                Stub.setVehicle(false)
            end
        end
    end
    assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
end)

-- iPad run 7: the quest list (a "text" frame) grows with Text size; at every Text size, either hand, small and large
-- buttons, the buffs (two rows of each) and the quest list still meet nothing.
T("buffs_and_quest_list_clear_at_every_text_size", function()
    local problems = {}
    for _, text in ipairs({ 0.8, 1.0, 1.2, 1.4 }) do
        for _, size in ipairs({ 0.8, 1.0, 1.4 }) do
            for _, left in ipairs({ false, true }) do
                local Feel = setup(); petClass()
                Stub.setForms({ { name = "Bear Form", spell = 5487 }, { name = "Cat Form", spell = 768 } })
                Feel.Set("textSize", text); Feel.Set("buttonSize", size); Feel.Set("leftHanded", left); Stub.advance(1)
                Stub.applyDrivers(); Stub.applyUnitWatch()
                local label = ("text %.1f size %.1f %s"):format(text, size, left and "left" or "right")
                local list = targets()
                for _, band in ipairs(ns.AppBands()) do list[#list + 1] = band end
                local x, y, w, h = ns.Auras.Area(22, 16)
                local area = { x = x, y = y, w = w, h = h }
                for _, t in ipairs(list) do
                    if hits(area, t) then problems[#problems + 1] = label .. ": buffs meet " .. t.name end
                end
                local found = overlaps()
                for _, f in ipairs(found) do
                    if f:find("quest") then problems[#problems + 1] = label .. ": " .. f end
                end
            end
        end
    end
    assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
end)

-- The page boxes' own touch areas never overlap: their step stays at 44 or more at any size.
T("page_boxes_keep_a_44_step_at_any_size", function()
    for _, size in ipairs({ 0.8, 1.0, 1.4 }) do
        local Feel = setup(); Feel.Set("buttonSize", size); Stub.advance(1)
        local boxes = ns.Cluster.pageBoxes
        for p = 2, #boxes do
            local a, b = boxes[p - 1].touchAnchor, boxes[p].touchAnchor
            local step = (b.x + b.w / 2) - (a.x + a.w / 2)
            assert(step >= 44 - 0.001, ("size %.1f: step %.2f"):format(size, step))
        end
        assert(near(boxes[4].touchAnchor.x + boxes[4].touchAnchor.w, 1366 - 24 * size), "the row keeps its right end")
    end
end)

-- Left-handed, the loot toasts start clear of the mirrored quest list (380..720): at x 730.
T("left_handed_loot_toasts_start_clear_of_the_quest_list", function()
    local Feel = setup()
    assert(ns.Loot.toasts[1].touchAnchor.x == 690, "right-handed: as the mockup")
    Feel.Set("leftHanded", true); Stub.advance(1)
    local quest = ns.Hud.quest.touchAnchor
    assert(quest.x == 380 and quest.x + quest.w == 720)
    for _, t in ipairs(ns.Loot.toasts) do assert(t.touchAnchor.x == 730, tostring(t.touchAnchor.x)) end
end)

T("left_handed_pet_row_and_leave_follow_the_mirrored_chat", function()
    local Feel = setup(); petClass()
    local pet1, leave = ns.ClassBars.pet[1].touchAnchor, ns.ClassBars.leave.touchAnchor
    local row = ns.ClassBars.pet[10].touchAnchor.x + 52 - pet1.x
    assert(near(pet1.x + row / 2, 580), "centred on the chat strip: " .. (pet1.x + row / 2))
    assert(near(leave.x + leave.w / 2, 580))
    Feel.Set("leftHanded", true); Stub.advance(1)
    pet1, leave = ns.ClassBars.pet[1].touchAnchor, ns.ClassBars.leave.touchAnchor
    local chat = ns.Chat.strip.touchAnchor
    assert(near(pet1.x + row / 2, 1366 - 580), "the pet row's centre mirrors: " .. (pet1.x + row / 2))
    assert(near(leave.x + leave.w / 2, 1366 - 580))
    assert(near(chat.x + chat.w / 2, 1366 - 580), "same centre as the mirrored chat strip")
end)

T("left_handed_picker_sheet_moves_off_the_cluster", function()
    local Feel = setup()
    local sheet = ns.Picker.sheet.touchAnchor
    assert(sheet.x == 40 and not sheet.mirrored)
    Feel.Set("leftHanded", true); Stub.advance(1)
    sheet = ns.Picker.sheet.touchAnchor
    assert(sheet.mirrored and sheet.corner == "BR" and near(sheet.x, 1366 - 40 - 960), sheet.x)
    local primary = ns.Cluster.buttons[1].touchAnchor
    assert(sheet.x >= primary.x + primary.w, "the sheet no longer covers the spell buttons")
end)

T("left_handed_aim_line_mirrors", function()
    local Feel = setup()
    local line = ns.Interact.aimLine
    local x, y = Stub.centre(line)
    assert(x == 645 and y == 640, "right-handed: centred at (645, 640), mockup 23")
    Feel.Set("leftHanded", true); Stub.advance(1)
    x, y = Stub.centre(line)
    assert(x == 721 and y == 640, "left-handed: mirrored to 721: " .. x)
    assert(line.justifyH == "CENTER")
    Feel.Set("leftHanded", false); Stub.advance(1)
    x = Stub.centre(line); assert(x == 645)
end)

T("one_shared_plain_helper", function()
    setup()
    assert(type(ns.Plain) == "function" and ns.Plain(3) == true and ns.Plain(Stub.secret()) == false)
    for _, file in ipairs({ "Hold.lua", "Menu.lua", "Popups.lua" }) do
        local f = assert(io.open("addon/TouchPlay/" .. file)); local text = f:read("*a"); f:close()
        assert(not text:find("local function Plain", 1, true), file .. " uses ns.Plain")
    end
end)

-- ---------------------------------------------------------------------------------------
-- The other switches

T("tap_sounds_switch_the_tap_sound", function()
    local Feel = setup()
    Stub.sounds = {}
    ns.Kit.Sound("tap"); assert(#Stub.sounds == 1, "on by default")
    Feel.Set("tapSounds", false)
    ns.Kit.Sound("tap"); assert(#Stub.sounds == 1, "off: no tap sound")
    ns.Kit.Sound("open"); assert(#Stub.sounds == 2, "opening a window keeps its sound")
    Feel.Set("tapSounds", true)
    ns.Kit.Sound("tap"); assert(#Stub.sounds == 3)
end)

T("floating_numbers_set_the_games_cvar", function()
    local Feel = setup()
    Feel.Set("floatingNumbers", false)
    assert(Stub.cvars.enableFloatingCombatText == "0")
    Feel.Set("floatingNumbers", true)
    assert(Stub.cvars.enableFloatingCombatText == "1")
end)

-- ---------------------------------------------------------------------------------------
-- The panel (mockups 31, 88)

local function row(Feel, key) return assert(Feel.rows[key], "row " .. key) end

-- iPad run 7 (settings-*.png): "LargeNormal" and "Quick" over "info card": on a slider row the words take their own
-- columns: the label (its note under it), the left word right-aligned before the track, the right word after it, the
-- value right-aligned at the panel's right edge; nothing shares a column.
T("slider_rows_lay_out_in_columns_that_never_meet", function()
    local Feel = setup()
    Feel.Open()
    local function span(fs)
        local point, rel, relPoint, x = fs:GetPoint(1)
        local w = fs:GetWidth()
        assert(w and w > 0, "every word has a width")
        return point, rel, relPoint, x, w           -- x: the anchor's own offset
    end
    for _, key in ipairs({ "buttonSize", "textSize", "hold" }) do
        local r = row(Feel, key)
        local s = r.slider
        local _, sRel, _, sx = s:GetPoint(1)
        assert(sRel == Feel.panel)
        local sLeft, sRight = sx, sx + s:GetWidth()
        local lp, lrel, lrp, lx, lw = span(s.leftLabel)
        assert(lrel == s and lp == "RIGHT" and lrp == "LEFT" and s.leftLabel.justifyH == "RIGHT", key .. " left word")
        local rp, rrel, rrp, rx, rw = span(s.rightLabel)
        assert(rrel == s and rp == "LEFT" and rrp == "RIGHT", key .. " right word")
        local vp, vrel, vrp, vx, vw = span(r.value)
        assert(vrel == Feel.panel and vp == "RIGHT" and r.value.justifyH == "RIGHT", key .. " value right-aligned")
        local valueLeft = Feel.PANEL_W + vx - vw        -- anchored RIGHT to the panel's TOPRIGHT
        assert(sRight + rx + rw + 8 <= valueLeft, key .. ": the right word ends before the value starts")
        assert(sLeft + lx - lw >= 37, key .. ": the left word starts inside the panel")
        -- the label's note goes under the label, never on the line of the left word
        if r.note then
            local np, nrel, nrp = r.note:GetPoint(1)
            assert(nrel == r.label and np == "TOPLEFT" and nrp == "BOTTOMLEFT", key .. ": the note under its label")
            assert(37 + r.note:GetWidth() <= sLeft + lx - lw, key .. ": the note ends before the left word")
        end
    end
end)

-- iPad run 7: the "Reload to give them to the app" notice sat behind the panel. A change that needs a reload says so
-- inside the panel (between Defaults and Done); Done uncovers the notice with its Reload button. Auto-run counts: the
-- app reads it from the saved file, written at a reload.
T("the_reload_line_shows_inside_the_panel", function()
    local Feel = setup()
    ns.Contract.loadedAtLogin = TouchPlayDB.contract     -- as after a reload: the app has this list
    ns.Contract.Write(); Stub.advance(0.1)
    Feel.Open()
    assert(not Feel.reloadLine:IsShown(), "nothing changed yet")
    Feel.Set("leftHanded", true); Stub.advance(1)
    assert(Feel.reloadLine:IsShown() and Feel.reloadLine:GetText():find("Reload", 1, true), "inside the panel")
    assert(ns.Contract.notice:IsShown())
    Feel.Close()
    assert(ns.Contract.notice:IsShown(), "Done: the notice and its Reload button are in view")
    Feel.Set("leftHanded", false); Stub.advance(1)
    Feel.Open(); assert(not Feel.reloadLine:IsShown(), "back as loaded: no reload")
    Feel.Set("edgeRun", false); Stub.advance(1)
    assert(Feel.reloadLine:IsShown() and ns.Contract.notice:IsShown(), "auto-run reaches the app at a reload too")
end)

T("panel_has_every_row_of_the_mockup", function()
    local Feel = setup()
    Feel.Open()
    assert(Feel.panel:IsShown())
    assert(Feel.title.label:GetText() == "Touch settings")
    local keys = { "leftHanded", "stand", "buttonSize", "textSize", "sharpScreen", "hold", "turnWithView", "edgeRun",
        "holdRisky", "autoTarget", "bigPlates", "tapSounds", "floatingNumbers", "reduceMotion", "vibration",
        "gameSettings" }
    for _, k in ipairs(keys) do row(Feel, k) end
    assert(row(Feel, "leftHanded").label:GetText() == "Left-handed layout")
    assert(row(Feel, "leftHanded").note:GetText() == "swaps the walk side and the spell side")
    assert(row(Feel, "stand").label:GetText() == "iPad on a stand")
    assert(row(Feel, "buttonSize").label:GetText() == "Button size")
    assert(row(Feel, "textSize").label:GetText() == "Text size")
    assert(row(Feel, "hold").label:GetText() == "Hold time")
    assert(row(Feel, "hold").note:GetText() == "how long before a hold opens the info card")
    assert(row(Feel, "turnWithView").label:GetText() == "Character turns with the view")
    assert(row(Feel, "turnWithView").note:GetText() == "recommended")
    -- ruling A34: auto-run locks by sliding up onto the lock above the stick (iPad run 7: the old words described A28)
    assert(row(Feel, "edgeRun").label:GetText() == "Auto-run lock above the walk stick", row(Feel, "edgeRun").label:GetText())
    assert(row(Feel, "edgeRun").note:GetText() == "slide up onto it and let go to keep running")
    assert(row(Feel, "holdRisky").label:GetText() == "Risky actions need a hold")
    assert(row(Feel, "holdRisky").note:GetText() == "release spirit, hearth, log out, delete")
    assert(row(Feel, "tapSounds").label:GetText() == "Tap sounds")
    assert(row(Feel, "floatingNumbers").label:GetText() == "Floating damage numbers")
    assert(row(Feel, "reduceMotion").label:GetText() == "Reduce motion")
    assert(row(Feel, "reduceMotion").note:GetText() == "follows the iPad setting unless you change it here")
    assert(row(Feel, "gameSettings").label:GetText() == "Game settings ›")
    -- Targeting (18 Nov, no mockup: defaults pending the tester's approval)
    assert(row(Feel, "autoTarget").label:GetText() == "Auto-target the enemy in front")
    assert(row(Feel, "autoTarget").note:GetText() == "a spell with no target hits the enemy you face")
    assert(row(Feel, "bigPlates").label:GetText() == "Bigger name plates to tap")
    assert(row(Feel, "bigPlates").note:GetText() == "enemy plates always shown, larger, not stacked")
    assert(Feel.headers and Feel.headers["feel.targeting"] and Feel.headers["feel.targeting"]:GetText() == "Targeting")
    -- ruling A39 (18 Nov): Sharp screen, in Layout under Text size
    assert(row(Feel, "sharpScreen").label:GetText() == "Sharp screen")
    assert(row(Feel, "sharpScreen").note:GetText() == "Sharp buttons and text; the 3D world stays as light as now")
    assert(Feel.defaultsButton.label:GetText() == "Defaults" and Feel.doneButton.label:GetText() == "Done")
end)

T("panel_vibration_row_is_greyed", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "vibration")
    assert(r.label:GetText() == "Vibration")
    assert(r.note:GetText() == "iPhone only: iPads cannot vibrate")
    assert(r.box:IsEnabled() == false, "it cannot be ticked")
    local cr = r.label:GetTextColor()
    assert(cr < 0.6, "greyed")
    assert(ns.db.feel == nil or ns.db.feel.vibration == nil)
end)

T("panel_checkbox_changes_the_setting", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "turnWithView")
    assert(r.check:IsShown(), "ticked by default")
    Stub.click(r.box)
    assert(ns.db.feel.turnWithView == false and not r.check:IsShown())
    assert(TouchPlayDB.contract:find(";turn=0;", 1, true))
    Stub.click(r.box)
    assert(ns.db.feel.turnWithView == true and r.check:IsShown())
    Stub.click(row(Feel, "leftHanded").box); Stub.advance(1)
    assert(ns.db.feel.leftHanded == true and near(centreX(ns.Cluster.buttons[1]), 98))
    assert(not ns.paused, ns.lastError)
end)

T("panel_checkboxes_are_at_least_44_units", function()
    local Feel = setup(); Feel.Open()
    for key, r in pairs(Feel.rows) do
        if r.box then
            local w, h = r.box:GetHitRectSize()
            assert(w >= 44 and h >= 44, key .. " " .. w .. "x" .. h)
        end
    end
end)

T("panel_slider_changes_the_setting", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "hold")
    assert(r.slider:GetValue() == 0.45 and r.value:GetText() == "0.45 s")
    r.slider:SetValue(0.6)
    assert(ns.db.feel.hold == 0.6 and r.value:GetText() == "0.60 s", r.value:GetText())
    assert(TouchPlayDB.contract:find(";hold=0.6;", 1, true))
    local min, max = r.slider:GetMinMaxValues()
    assert(min == 0.3 and max == 0.8)
    assert(r.slider.leftLabel:GetText() == "Quick" and r.slider.rightLabel:GetText() == "Slow")
    local b = row(Feel, "buttonSize")
    local bmin, bmax = b.slider:GetMinMaxValues(); assert(bmin == 0.8 and bmax == 1.4)
    assert(b.value:GetText() == "Normal" and b.slider.leftLabel:GetText() == "Small" and b.slider.rightLabel:GetText() == "Large")
    b.slider:SetValue(1.2); assert(b.value:GetText() ~= "Normal")
    Stub.advance(1)
    assert(ns.db.feel.buttonSize == 1.2)
end)

T("panel_reduce_motion_shows_the_effective_state", function()
    local Feel = setup()
    Stub.cvars.CameraReduceUnexpectedMovement = "1"
    Feel.Open()
    local r = row(Feel, "reduceMotion")
    assert(r.check:IsShown(), "the game's setting shows ticked (mockup 88)")
    Stub.click(r.box)
    assert(ns.db.feel.reduceMotion == false and not r.check:IsShown())
end)

T("panel_defaults_and_done", function()
    local Feel = setup(); Feel.Open()
    Feel.Set("hold", 0.7); Feel.Set("holdRisky", false); Feel.Set("reduceMotion", true)
    Stub.click(Feel.defaultsButton); Stub.advance(1)
    assert(Feel.Get("hold") == 0.45 and Feel.Get("holdRisky") == true and Feel.Get("reduceMotion") == "auto")
    assert(row(Feel, "holdRisky").check:IsShown() and row(Feel, "hold").value:GetText() == "0.45 s")
    assert(TouchPlayDB.contract:find(";hold=0.45;", 1, true))
    Stub.click(Feel.doneButton)
    assert(not Feel.panel:IsShown())
end)

-- The row is an ordinary button: no secure child, so the panel is not protected and opens and closes in a fight.
T("panel_game_settings_row_is_a_plain_button", function()
    local Feel = setup(); Feel.Open()
    local b = row(Feel, "gameSettings").button
    assert(not b:IsProtected() and not Feel.panel:IsProtected(), "nothing secure in Touch settings")
    assert(b:GetAttribute("type") == nil and b:GetAttribute("macrotext") == nil, "no /click GameMenuButtonOptions")
end)

-- The game's settings panel is refused to add-on code in a fight (R32), so the row is greyed then and does nothing.
T("panel_game_settings_fallback_waits_for_the_end_of_a_fight", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "gameSettings")
    assert(_G.GameMenuButtonOptions == nil)
    assert(r.button:IsEnabled() ~= false and r.face:GetAlpha() == 1)
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(r.note:GetText() == "After the fight", tostring(r.note:GetText()))
    assert(r.face:GetAlpha() < 1, "greyed")
    Stub.click(r.button)
    assert(Stub.calls.OpenSettings == 0 and #Stub.blocked == 0 and not ns.paused, "nothing was called")
    assert(Feel.panel:IsShown(), "and the panel stays")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(r.face:GetAlpha() == 1 and r.note:GetText() ~= "After the fight")
    Stub.click(r.button)
    assert(Stub.calls.OpenSettings == 1, "out of a fight it opens")
    assert(Stub.lastCategory == Settings.INTERFACE_CATEGORY_ID and Stub.lastCategory ~= nil,
        "a category this client defines (not GAMEPLAY_CATEGORY_ID)")
    assert(not Feel.panel:IsShown(), "and Touch settings steps aside")
    assert(not ns.paused, ns.lastError)
end)

T("panel_game_settings_missing_function_never_pauses_touchplay", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "gameSettings")
    Settings.OpenToCategory = function() error("the game changed") end
    Stub.click(r.button)
    assert(not ns.paused and ns.lastError == nil, tostring(ns.lastError))
    Feel.Open()
    Settings = nil
    Stub.click(r.button)
    assert(not ns.paused, ns.lastError)
end)

T("panel_opens_in_a_fight", function()
    local Feel = setup(); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    Feel.Open()
    assert(Feel.panel:IsShown() and not ns.paused, ns.lastError)
    Stub.click(Feel.doneButton)
    assert(not Feel.panel:IsShown())
end)

T("no_ShowUIPanel_anywhere", function()
    for _, file in ipairs({ "Menu.lua", "Feel.lua", "Guide.lua" }) do
        local f = assert(io.open("addon/TouchPlay/" .. file)); local text = f:read("*a"); f:close()
        assert(not text:find("ShowUIPanel", 1, true), file .. " never calls ShowUIPanel")
    end
end)

-- A rebuild that comes due while Touch is paused or off does nothing (a Layout would hide the game's bars again).
T("rebuild_waits_while_paused_or_off", function()
    local Feel = setup()
    Feel.Set("buttonSize", 1.2)
    ns.Pause("test")
    Stub.advance(1)
    assert(not ns.Bars.IsHidden("MainActionBar"), "paused: the bars stay given back")
    Feel = setup()
    Feel.Set("buttonSize", 1.2)
    SlashCmdList.TOUCHPLAY("")                  -- switched off before the rebuild comes due
    Stub.advance(1)
    assert(not ns.Bars.IsHidden("MainActionBar"), "off: the bars stay given back")
    assert(ns.Cluster.buttons[1]:GetScale() == 1, "nothing was laid out")
end)


-- Targeting rows made the panel one group longer: it still fits under the app's top band and above the screen's
-- bottom, every row is at least 44 apart (no two rows' taps meet) and in the order of the mockup with Targeting
-- after Touch.
T("panel_fits_the_screen_with_the_targeting_group", function()
    local Feel = setup(); Feel.Open()
    local _, _, _, _, top = Feel.panel:GetPoint(1)
    local y0 = -top
    assert(y0 >= 60, "under the app's top band")
    assert(y0 + Feel.panel:GetHeight() <= 1024 - 6, "bottom " .. (y0 + Feel.panel:GetHeight()))
    local order = { "leftHanded", "stand", "buttonSize", "textSize", "sharpScreen", "hold", "turnWithView", "edgeRun", "holdRisky",
        "autoTarget", "bigPlates", "tapSounds", "floatingNumbers", "reduceMotion", "vibration", "gameSettings" }
    local last
    for _, key in ipairs(order) do
        local y = Feel.rowY[key]
        assert(y, "row " .. key .. " has a place")
        if last then assert(y - last >= 44, key .. " is " .. (y - last) .. " under the row before") end
        last = y
    end
    assert(last + 22 <= Feel.panel:GetHeight() - 82 - 10, "the Game settings row clears Defaults and Done")
    for key, r in pairs(Feel.rows) do
        if r.box then
            local w, h = r.box:GetHitRectSize()
            assert(w >= 44 and h >= 44, key)
        end
    end
end)

T("panel_targeting_switches_tick_and_untick", function()
    local Feel = setup(); Feel.Open()
    local r = row(Feel, "autoTarget")
    assert(r.check:IsShown(), "on by default")
    Stub.click(r.box)
    assert(ns.db.feel.autoTarget == false and not r.check:IsShown())
    Stub.click(row(Feel, "bigPlates").box)
    assert(ns.db.feel.bigPlates == false and not row(Feel, "bigPlates").check:IsShown())
    Stub.click(Feel.defaultsButton); Stub.advance(1)
    assert(r.check:IsShown() and row(Feel, "bigPlates").check:IsShown())
    assert(not ns.paused, ns.lastError)
end)

Stub.done("feel")
