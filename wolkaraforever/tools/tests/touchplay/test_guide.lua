-- Task 14: the touch guide (rule 8; mockups 101-103): four steps with a spotlight and a finger, shown once.
dofile("tests/stub.lua")

-- The very first run shows the reload notice (the saved list is new to the app), and the guide waits for it; the
-- player reloads, and the guide opens then. These tests start after that reload.
local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    Stub.reload(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return ns.Guide
end

T("guide_waits_for_the_reload_notice_then_opens_after_the_reload", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local Guide = ns.Guide
    assert(ns.Contract.notice:IsShown(), "the first run offers the reload")
    assert(not Guide.IsShown() and TouchPlayDB.guideDone ~= true, "the guide waits: the two never share the screen")
    -- a later layout with the notice still up does not start it either
    ns.Each("Layout"); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.Guide.IsShown() and ns.Contract.notice:IsShown())
    -- the player reloads: nothing to reload now, so the guide opens
    Stub.reload(); Stub.login()
    assert(not ns.Contract.notice:IsShown() and ns.Guide.IsShown() and ns.Guide.step == 1)
    assert(TouchPlayDB.guideDone == true)
    assert(not ns.paused, ns.lastError)
end)

T("guide_and_notice_never_share_the_screen_in_a_fight_either", function()
    Stub.reset(); Stub.loadAll(); Stub.fire("ADDON_LOADED", "TouchPlay")
    Stub.combat(true); Stub.fire("PLAYER_LOGIN")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(ns.Contract.notice:IsShown() and not ns.Guide.IsShown(), "the fight ends with the notice up: no guide")
end)

T("rule8_guide_once", function()
    local Guide = setup()
    assert(Guide.IsShown(), "the first login shows the guide")
    assert(Guide.step == 1)
    assert(TouchPlayDB.guideDone == true, "it never starts by itself again")
    -- a second login (the same saved variables)
    Stub.reload(); Stub.login()
    assert(not ns.Guide.IsShown(), "the second login does not show it")
    Stub.fire("PLAYER_LOGIN")
    assert(not ns.Guide.IsShown())
    assert(not ns.paused, ns.lastError)
end)

T("guide_waits_for_the_fight_to_end", function()
    Stub.reset(); Stub.loadAll(); Stub.login(); Stub.reload()      -- (after the first run's reload)
    Stub.combat(true); Stub.fire("PLAYER_LOGIN")      -- the add-on loads out of a fight; the login lands in one
    local Guide = ns.Guide
    assert(not Guide.IsShown(), "not in a fight")
    assert(TouchPlayDB.guideDone ~= true)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Guide.IsShown())
end)

T("guide_not_shown_while_touch_is_off", function()
    Stub.reset(); Stub.loadAll()
    TouchPlayDB = { enabled = false }
    Stub.login()
    assert(not ns.Guide.IsShown())
end)

T("rule8_guide_from_menu", function()
    local Guide = setup()
    Guide.Hide(); assert(not Guide.IsShown())
    ns.Menu.Open()
    Stub.click(ns.Menu.guideButton)
    assert(Guide.IsShown() and Guide.step == 1 and not ns.Menu.IsOpen())
    assert(TouchPlayDB.guideDone == true)
end)

local function card(Guide) return Guide.card end

T("guide_step_texts_come_from_the_mockups", function()
    local Guide = setup()
    local want = {
        { "1 of 4", "Walk", "Put your thumb anywhere on the left and slide. The stick appears under it. Push to the edge and let go to keep running." },
        { "2 of 4", "Look and target", "Drag the world with one finger to look around; your character turns with you. Tap an enemy to target it. Pinch to zoom." },
        { "3 of 4", "Cast, and hold to read", "Tap a spell to cast it. Hold any button or person for its card: what it does, and what you can do with it." },
        { "4 of 4", "Interact and Jump", "Interact does whatever is nearest: Talk, Loot, Open, Reel in. Jump is beside it." },
    }
    for i, w in ipairs(want) do
        assert(Guide.step == i)
        assert(Guide.counter:GetText() == w[1], Guide.counter:GetText())
        assert(Guide.title:GetText() == w[2], Guide.title:GetText())
        assert(Guide.body:GetText() == w[3], Guide.body:GetText())
        assert(ns.L["guide." .. i] == w[3], "the text lives in ns.L guide." .. i)
        assert(Guide.skipButton.label:GetText() == "Skip")
        assert(Guide.nextButton.label:GetText() == (i == 4 and "Done" or "Next"))
        if i < 4 then Stub.click(Guide.nextButton) end
    end
end)

T("guide_next_walks_the_steps_and_the_final_card", function()
    local Guide = setup()
    Stub.click(Guide.nextButton); assert(Guide.step == 2)
    Stub.click(Guide.nextButton); assert(Guide.step == 3)
    Stub.click(Guide.nextButton); assert(Guide.step == 4)
    Stub.click(Guide.nextButton)
    assert(Guide.final:IsShown() and not Guide.card:IsShown(), "the closing card")
    assert(Guide.finalTitle:GetText() == "You're ready")
    assert(Guide.finalBody:GetText() == "You can open this guide again from Menu › Touch guide.", Guide.finalBody:GetText())
    assert(Guide.playButton.label:GetText() == "Play")
    Stub.click(Guide.playButton)
    assert(not Guide.IsShown())
    assert(not ns.paused, ns.lastError)
end)

T("guide_skip_goes_to_the_final_card", function()
    local Guide = setup()
    Stub.click(Guide.nextButton)
    Stub.click(Guide.skipButton)
    assert(Guide.final:IsShown(), "skipping also ends on the closing card")
    Stub.click(Guide.playButton)
    assert(not Guide.IsShown())
end)

T("guide_spotlight_dims_everything_but_the_part", function()
    local Guide = setup()
    -- step 1: the walk side (left) as in mockup 101
    local hole = Guide.hole
    assert(hole.x == 19 and hole.y == 477 and hole.w == 563 and hole.h == 523, hole.x .. "," .. hole.y .. "," .. hole.w .. "," .. hole.h)
    assert(Guide.dim:IsShown() and Guide.dim:IsMouseEnabled(), "the dim takes the touches")
    for _, side in ipairs(Guide.dim.sides) do assert(side:IsShown()) end
    -- step 3 lights up the spell cluster; step 4 Interact and Jump
    Stub.click(Guide.nextButton); Stub.click(Guide.nextButton)
    local h3 = Guide.hole
    local primary = ns.Cluster.buttons[1].touchAnchor
    assert(h3.x < primary.x and h3.x + h3.w > primary.x + primary.w, "the spotlight holds the primary button")
    assert(h3.y < primary.y and h3.y + h3.h >= primary.y + primary.h)
    Stub.click(Guide.nextButton)
    local h4, jump, interact = Guide.hole, ns.Interact.jump.touchAnchor, ns.Interact.interact.touchAnchor
    assert(h4.x < interact.x and h4.x + h4.w > jump.x + jump.w, "Interact and Jump are both lit")
end)

T("guide_follows_the_left_handed_layout", function()
    local Guide = setup(); Guide.Hide()
    ns.Feel.Set("leftHanded", true); Stub.advance(1)
    Guide.Show(true)
    assert(Guide.hole.x > 683, "the walk side is on the right now: " .. Guide.hole.x)
    assert(Guide.body:GetText():find("on the right", 1, true), Guide.body:GetText())
    Stub.click(Guide.nextButton); Stub.click(Guide.nextButton)
    assert(Guide.hole.x + Guide.hole.w / 2 < 683, "the spells are lit on the left")
end)

T("guide_card_buttons_are_big_and_in_the_same_place", function()
    local Guide = setup()
    local sx, nx
    for step = 1, 4 do
        local w, h = Guide.nextButton:GetHitRectSize(); assert(w >= 44 and h >= 44)
        w, h = Guide.skipButton:GetHitRectSize(); assert(w >= 44 and h >= 44)
        local cx = Guide.card.touchAnchor
        local nextOffset = Guide.nextButton.points[1]
        assert(nextOffset[1] == "BOTTOMRIGHT", "Next sits in the card's corner every time")
        if step < 4 then Stub.click(Guide.nextButton) end
    end
end)

T("guide_finger_moves_unless_reduce_motion", function()
    local Guide = setup()
    assert(Guide.finger.group:IsPlaying(), "the finger shows the gesture")
    Guide.Hide()
    ns.Feel.Set("reduceMotion", true)
    Guide.Show(true)
    assert(not Guide.finger.group:IsPlaying(), "reduce motion keeps the finger still")
    assert(Guide.finger:IsShown())
    assert(Guide.finger.scripts.OnUpdate == nil, "no OnUpdate")
end)

T("guide_menu_glows_once_after_it", function()
    local Guide = setup()
    Stub.click(Guide.skipButton); Stub.click(Guide.playButton)
    assert(Guide.glow:IsShown(), "Menu glows once so you know where the guide lives")
    Stub.advance(10)
    assert(not Guide.glow:IsShown())
    -- from the Menu it does not glow again
    Guide.Show(true); Stub.click(Guide.skipButton); Stub.click(Guide.playButton)
    assert(not Guide.glow:IsShown(), "only the first time")
end)

T("guide_in_a_fight_is_safe", function()
    local Guide = setup(); Guide.Hide()
    Stub.combat(true)
    Guide.Show(true)
    Stub.click(Guide.nextButton); Stub.click(Guide.skipButton); Stub.click(Guide.playButton)
    assert(not ns.paused, ns.lastError)
end)

T("guide_pause_closes_it", function()
    local Guide = setup()
    ns.Pause("test")
    assert(not Guide.IsShown())
end)

Stub.done("guide")
