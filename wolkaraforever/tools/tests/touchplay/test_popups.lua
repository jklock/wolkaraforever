-- Task 13: touch-sized popups, the 0.4 s guard, the 0.8 s hold for what cannot be undone (mockups 12,
-- 13, 15, 80, 104). The game's static popups are the stub's StaticPopup1..4.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return ns.Popups
end

-- dialogs as the game defines them (GameDialogDefs.lua)
local function define()
    StaticPopupDialogs.PARTY_INVITE = { text = "%s invites you to a group.", button1 = "Accept", button2 = "Decline",
        OnAccept = function() AcceptGroup() end }
    StaticPopupDialogs.TRADE = { text = "%s wants to trade.", button1 = "Yes", button2 = "No", OnAccept = function() end }
    StaticPopupDialogs.DUEL = { text = "%s duel.", button1 = "Accept", button2 = "Decline", OnAccept = function() end }
    StaticPopupDialogs.DEATH = { text = "You have died.", button1 = "Release Spirit", button2 = "Use Soulstone",
        OnButton1 = function() RepopMe() end }
    StaticPopupDialogs.DELETE_ITEM = { text = "Destroy %s?", button1 = "Yes", button2 = "No",
        OnAccept = function() DeleteCursorItem() end }
    StaticPopupDialogs.DELETE_GOOD_ITEM = { text = "Destroy %s? Type DELETE.", button1 = "Okay", button2 = "Cancel",
        OnAccept = function() DeleteCursorItem() end }
    StaticPopupDialogs.TIMED = { text = "%s wants to resurrect you.", button1 = "Accept", button2 = "Decline",
        timeout = 60, OnAccept = function() AcceptGroup() end }
    StaticPopupDialogs.ABANDON_QUEST = { text = "Abandon %s?", button1 = "Yes", button2 = "No",
        OnAccept = function() RepopMe() end }
    StaticPopupDialogs.XP_LOSS = { text = "Resurrecting costs 25 percent durability.", button1 = "Accept", button2 = "Cancel",
        OnAccept = function() RetrieveCorpse() end }
    StaticPopupDialogs.RECOVER_CORPSE = { text = "Resurrect now?", button1 = "Accept",
        OnAccept = function() RetrieveCorpse(); return true end }
end

local function show(which, arg)
    local d = StaticPopup_Show(which, arg or "Tarek")
    assert(d, "no free popup")
    return d
end

local function afterGuard() Stub.advance(0.5) end

local function button(d, i) return d:GetButton(i) end

-- ---------------------------------------------------------------------------------------
-- Skin

T("skinned_buttons_keep_their_actions", function()
    local P = setup(); define()
    local d = StaticPopup1
    local clicks, scripts = {}, {}
    for i = 1, 4 do clicks[i] = button(d, i).scripts.OnClick end
    for k, v in pairs(d.scripts) do scripts[k] = v end
    show("PARTY_INVITE")
    for i = 1, 4 do
        local b = button(d, i)
        assert(b.scripts.OnClick == clicks[i], "button " .. i .. " keeps its own click handler")
        assert(next(b.attributes) == nil, "no attribute written on a popup button")
        assert(b.calls.SetParent == 0, "no reparenting")
    end
    for k, v in pairs(d.scripts) do assert(scripts[k] == v, "the popup's own script " .. k .. " is untouched") end
    assert(d.calls.SetParent == 0)
    assert(button(d, 1):GetHeight() == 52 and button(d, 2):GetHeight() == 52, button(d, 1):GetHeight())
    local _, size = d.Text:GetFont()
    assert(size == 18, tostring(size))
    -- the accept still accepts
    afterGuard(); Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 1)
end)

T("skin_follows_the_screen_scale", function()
    local P = setup(); define()
    Stub.screen(2048, 1536); Stub.fire("DISPLAY_SIZE_CHANGED")
    local d = show("PARTY_INVITE")
    assert(button(d, 1):GetHeight() == 78, "52 layout units are 78 here: " .. button(d, 1):GetHeight())
    local _, size = d.Text:GetFont(); assert(size == 27, tostring(size))
end)

T("several_queued_each_skinned", function()
    local P = setup(); define()
    local list = { show("PARTY_INVITE"), show("TRADE"), show("DUEL"), show("DEATH") }
    assert(#list == 4 and list[1] ~= list[4])
    for i, d in ipairs(list) do
        assert(d:IsShown())
        assert(button(d, 1):GetHeight() == 52, "popup " .. i)
        assert(select(2, d.Text:GetFont()) == 18, "popup " .. i)
    end
end)

T("skin_in_a_fight_is_immediate_and_never_blocks", function()
    local P = setup(); define()
    Stub.combat(true)
    local d = show("PARTY_INVITE")
    assert(button(d, 1):GetHeight() == 52, "a plain popup is restyled at once, fight or not")
    afterGuard(); Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 1, "the popup works in the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused, ns.lastError)
end)

T("a_protected_popup_is_styled_only_when_the_game_allows", function()
    local P = setup(); define()
    StaticPopup1:Show(); StaticPopup1:Hide()
    local d = StaticPopup2
    d.protectedFlag = true
    d.which, d.dialogInfo = "PARTY_INVITE", StaticPopupDialogs.PARTY_INVITE
    d.Buttons[1].shown = true
    d:Show()
    assert(not ns.paused, ns.lastError)
    assert(button(d, 1):GetHeight() == 52, "out of a fight the queue runs at once")
    button(d, 1):SetHeight(21)
    Stub.combat(true)
    P.Skin(d)
    afterGuard()
    assert(not ns.paused and button(d, 1):GetHeight() == 21, "in a fight a protected popup waits")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused and button(d, 1):GetHeight() == 52, "and gets its look when the fight ends: " .. tostring(ns.lastError))
    Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 1, "and still answers")
end)

-- ---------------------------------------------------------------------------------------
-- The guard

T("ignores_taps_for_0_4s", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE")
    Stub.advance(0.2)
    Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 0, "a tap at 0.2 s is swallowed")
    Stub.advance(0.3)
    Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 1, "a tap at 0.5 s answers")
end)

T("guard_is_a_separate_frame_and_covers_the_whole_popup", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE")
    local cover = Stub.coveredBy(button(d, 2))
    assert(cover and cover ~= d and cover:GetParent() == UIParent, "a frame of ours, not a child of the popup")
    assert(cover.level > d.level)
    afterGuard()
    assert(Stub.coveredBy(button(d, 2)) == nil)
end)

T("guard_restarts_when_a_popup_is_reused", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE"); afterGuard()
    StaticPopup_Hide("PARTY_INVITE")
    d = show("PARTY_INVITE")
    Stub.advance(0.2)
    assert(Stub.coveredBy(button(d, 1)), "a new popup in the same frame guards again")
end)

-- ---------------------------------------------------------------------------------------
-- The hold

T("risky_list_is_exact", function()
    local P = setup()
    -- R31: DELETE_GOOD_ITEM is out (typing DELETE is already its confirmation)
    local want = { "DEATH", "RECOVER_CORPSE_INSTANCE", "CONFIRM_LEAVE_BATTLEFIELD", "DELETE_ITEM",
        "ABANDON_QUEST", "CAMP", "CONFIRM_BINDER" }
    assert(#P.RISKY == #want)
    for i, name in ipairs(want) do assert(P.RISKY[i] == name and P.NeedsHold(name), name) end
    assert(not P.NeedsHold("PARTY_INVITE") and not P.NeedsHold("TRADE"))
    assert(not P.NeedsHold("DELETE_GOOD_ITEM") and not P.PROTECTED_ACCEPT.DELETE_GOOD_ITEM)
    assert(P.NeedsHold("XP_LOSS"), "the spirit healer's question needs a hold too")
end)

T("risky_needs_hold", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    Stub.tap(button(d, 1), 0.1)
    assert(Stub.calls.RepopMe == 0, "a tap releases nothing")
    local hold = Stub.coveredBy(button(d, 1))
    assert(hold and hold.face:IsShown() and hold.face.label:GetText() == "Hold to confirm", "a quick tap says how")
    Stub.advance(1.5)
    assert(hold.face.label:GetText() == "Hold to release spirit", "then the button reads its own words again")
    Stub.tap(button(d, 1), 0.5)
    assert(Stub.calls.RepopMe == 0, "half a second is not enough")
    Stub.tap(button(d, 1), 0.8)
    assert(Stub.calls.RepopMe == 1, "0.8 s releases once")
    assert(not d:IsShown(), "the game closed its popup")
    Stub.advance(2)
    assert(Stub.calls.RepopMe == 1)
end)

T("hold_shows_a_fill_and_cancels_on_release", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    hold:_Fire("OnMouseDown", "LeftButton")
    assert(hold.bar:IsShown())
    Stub.advance(0.4)
    assert(hold.progress > 0.4 and hold.progress < 0.6, hold.progress)
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(not hold.bar:IsShown() and Stub.calls.RepopMe == 0)
    Stub.advance(2)
    assert(Stub.calls.RepopMe == 0, "a released hold never completes")
end)

T("hold_off_is_a_plain_tap", function()
    local P = setup(); define()
    ns.db.feel = { holdRisky = false }
    local d = show("DEATH"); afterGuard()
    assert(Stub.coveredBy(button(d, 1)) == nil)
    Stub.tap(button(d, 1))
    assert(Stub.calls.RepopMe == 1)
end)

T("contract_default_for_hold_is_on", function()
    local P = setup()
    assert(ns.Contract.FEEL_DEFAULTS.holdRisky == true)
    assert(P.HoldEnabled())
    ns.db.feel = { holdRisky = false }; assert(not P.HoldEnabled())
    ns.db.feel = { holdRisky = "yes" }; assert(P.HoldEnabled(), "an odd value falls back to the default")
end)

T("not_risky_is_a_tap", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE"); afterGuard()
    assert(Stub.coveredBy(button(d, 1)) == nil)
    Stub.tap(button(d, 1))
    assert(Stub.calls.AcceptGroup == 1)
end)

T("cancel_buttons_never_need_a_hold", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    assert(Stub.coveredBy(button(d, 2)) == nil, "Use Soulstone and the others are plain taps")
end)

T("a_button_the_game_disabled_is_left_to_the_game", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    button(d, 1):Disable()
    assert(not hold.face:IsShown(), "the game's own disabled face (a countdown) shows through")
    Stub.tap(button(d, 1), 1)
    assert(Stub.calls.RepopMe == 0)
    button(d, 1):Enable()
    assert(hold.face:IsShown())
end)

T("unprotected_accept_runs_through_the_games_button", function()
    local P = setup(); define()
    local d = show("ABANDON_QUEST", "Elixir of Pain"); afterGuard()
    local clicks = 0
    local real = button(d, 1).Click
    button(d, 1).Click = function(self, ...) clicks = clicks + 1; return real(self, ...) end
    Stub.tap(button(d, 1), 0.8)
    assert(clicks == 1 and Stub.calls.RepopMe == 1, "one click on the game's own button")
end)

T("protected_accept_never_runs_from_our_code", function()
    local P = setup(); define()
    assert(P.PROTECTED_ACCEPT.DELETE_ITEM)
    local d = show("DELETE_ITEM", "Hillborne Cloak"); afterGuard()
    local clicks, accepts = 0, 0
    local real = button(d, 1).Click
    button(d, 1).Click = function(self, ...) clicks = clicks + 1; return real(self, ...) end
    local oldDelete = DeleteCursorItem
    DeleteCursorItem = function() accepts = accepts + 1 end
    local hold = Stub.coveredBy(button(d, 1))
    Stub.tap(button(d, 1), 0.8)
    assert(clicks == 0 and accepts == 0, "the finished hold calls nothing from our code")
    assert(d:IsShown(), "the popup waits for the player")
    assert(Stub.coveredBy(button(d, 1)) == nil, "our frame no longer takes the touch")
    assert(hold.face:IsShown() and hold.face.label:GetText() == "Tap to confirm")
    Stub.tap(button(d, 1))
    assert(accepts == 1 and clicks == 0, "the player's own tap confirms, through the game's button")
    DeleteCursorItem = oldDelete
end)

T("protected_accept_locks_again_after_3s", function()
    local P = setup(); define()
    local d = show("DELETE_ITEM", "Hillborne Cloak"); afterGuard()
    local accepts = 0
    DeleteCursorItem = function() accepts = accepts + 1 end
    Stub.tap(button(d, 1), 0.8)
    Stub.advance(2.9)
    assert(Stub.coveredBy(button(d, 1)) == nil, "still unlocked at 2.9 s")
    Stub.advance(0.2)
    assert(Stub.coveredBy(button(d, 1)), "locked again at 3.1 s")
    Stub.tap(button(d, 1))
    assert(accepts == 0, "a tap now needs a hold again")
end)

T("spirit_healer_costs_and_distance", function()
    local P = setup(); define()
    Stub.mapPos = { 0.4, 0.5 }
    Stub.corpse = { 0.4 + 0.24, 0.5 }
    Stub.mapSize = { 1000, 700 }
    Stub.setDead("player", "ghost")
    local d = show("XP_LOSS"); afterGuard()
    local shownText = d.Text:GetText()
    local qAt = shownText:find("Return to life now?", 1, true)
    local costAt = shownText:find("Resurrecting costs 25 percent durability.", 1, true)
    assert(qAt and costAt and qAt < costAt, "the question first, then the game's own cost line: " .. shownText)
    assert(shownText:find("|cffffffffReturn to life now?|r", 1, true), "the question is white")
    assert(shownText:find("|cffff8070Resurrecting costs 25 percent durability.|r", 1, true), "the cost line has its own colour")
    local hold = Stub.coveredBy(button(d, 1))
    assert(hold.face.label:GetText() == "Hold to return")
    assert(button(d, 2):GetText() == "Not now")
    local g = Stub.coveredBy(button(d, 1)) -- the hold, not the guard
    local note
    for _, child in ipairs(UIParent.children) do
        if child.note and child.note:IsShown() then note = child.note end
    end
    assert(note and note:GetText() == "Your corpse is 240 yards away, free to reach.", note and note:GetText())
    Stub.tap(button(d, 1), 0.1); assert(Stub.calls.RetrieveCorpse == 0)
    Stub.tap(button(d, 1), 0.8); assert(Stub.calls.RetrieveCorpse == 1)
end)

T("resurrect_at_your_corpse_is_the_games_one_button", function()
    local P = setup(); define()
    local d = show("RECOVER_CORPSE"); afterGuard()
    assert(button(d, 1):GetHeight() == 52 and Stub.coveredBy(button(d, 1)) == nil)
    Stub.tap(button(d, 1)); assert(Stub.calls.RetrieveCorpse == 1)
end)

T("camp_and_instance_corpse_have_nothing_to_hold", function()
    local P = setup()
    StaticPopupDialogs.CAMP = { text = "Logging out", button2 = "Cancel", OnCancel = function() end }
    StaticPopupDialogs.RECOVER_CORPSE_INSTANCE = { text = "Your corpse is inside." }
    local a = show("CAMP"); local b = show("RECOVER_CORPSE_INSTANCE")
    assert(not button(a, 1):IsShown() and not button(b, 1):IsShown())
    afterGuard()
    assert(not ns.paused, ns.lastError)
    assert(Stub.coveredBy(button(a, 1)) == nil, "no hold over a button that is not there")
end)

T("hidden_text_is_never_read", function()
    local P = setup(); define()
    StaticPopupDialogs.DEATH.OnShow = function(d) d.Text.text = Stub.secret() end
    local d = show("DEATH"); afterGuard()
    StaticPopupDialogs.XP_LOSS.OnShow = function(d) d.Text.text = Stub.secret() end
    local e = show("XP_LOSS"); afterGuard()
    assert(not ns.paused, ns.lastError)
    Stub.tap(button(d, 1), 0.8); assert(Stub.calls.RepopMe == 1)
end)

T("spirit_text_secret_checked_before_the_type", function()
    local P = setup(); define()
    local realType = type
    -- a hidden string answers type() "string", as the game's does: only Plain() keeps the compare away
    type = function(v) if Stub.isSecret(v) then return "string" end return realType(v) end
    StaticPopupDialogs.XP_LOSS.OnShow = function(d) d.Text.text = Stub.secret() end
    local ok, problem = pcall(function() show("XP_LOSS"); afterGuard() end)
    type = realType
    assert(ok, problem)
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- The helper, the hearth item and the lifecycle

T("hold_button_helper_for_any_button", function()
    local P = setup()
    local b = ns.Kit.RedButton(ns.root, 120, 52, "Log out")
    local done = 0
    P.HoldButton(b, 0.8, function() done = done + 1 end)
    Stub.tap(b, 0.3); assert(done == 0)
    Stub.tap(b, 0.8); assert(done == 1)
    assert(P.HoldButton(b, 0.8, function() end, { arm = true }), "a hold can be put on again")
    P.ReleaseHold(b)
    assert(Stub.coveredBy(b) == nil)
    ns.db.feel = { holdRisky = false }
    assert(P.HoldButton(b, 0.8, function() end) == nil and Stub.coveredBy(b) == nil, "off: a plain button")
end)

local function hearth()
    Stub.bags[0] = { [1] = { name = "Hearth item", count = 1, quality = 1, itemID = 6948, link = "item:6948" } }
end

T("hearthstone_card_needs_a_hold_then_a_tap", function()
    local P = setup()
    hearth()
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    local use = ns.InfoCard.Button("Use")
    local secure = ns.InfoCard.secureButton
    assert(secure:GetAttribute("type") == "item" and secure:GetAttribute("item") == "0 1", "the secure Use is under the hold")
    Stub.tap(use)
    assert(Stub.lastItemUsed == nil, "a tap does not use it")
    Stub.tap(use, 0.8)
    assert(Stub.lastItemUsed == nil, "the hold unlocks, it does not use it (R28)")
    local face = Stub.coveredBy(use)
    assert(face == nil)
    Stub.tap(use)
    assert(Stub.lastItemUsed == "0 1", "the player's own tap lands on the secure Use button and uses it")
    assert(Stub.lastUsedItem == nil and Stub.calls.UseContainerItem == 0, "never from our own code (R37)")
end)

T("other_items_are_a_tap", function()
    local P = setup()
    Stub.bags[0] = { [1] = { name = "Healing Potion", count = 1, quality = 1, itemID = 118, link = "item:118" } }
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    local use = ns.InfoCard.Button("Use")
    Stub.tap(use)
    assert(Stub.lastItemUsed == "0 1")
    -- and the hold does not follow the Use button to another card
    hearth()
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    Stub.lastItemUsed = nil
    Stub.tap(ns.InfoCard.Button("Use")); assert(Stub.lastItemUsed == nil)
    Stub.bags[0] = { [1] = { name = "Healing Potion", count = 1, quality = 1, itemID = 118, link = "item:118" } }
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    Stub.tap(ns.InfoCard.Button("Use")); assert(Stub.lastItemUsed, "the next card is a plain tap again")
end)

T("off_and_pause_cancel_a_hold", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    hold:_Fire("OnMouseDown", "LeftButton")
    ns.SetEnabled(false)
    Stub.advance(2)
    assert(Stub.calls.RepopMe == 0, "a hold in progress never completes after Off")
    assert(Stub.coveredBy(button(d, 1)) == nil and not hold:IsShown())
    assert(button(d, 1):GetHeight() == 21, "Off gives the game's size back")
    ns.SetEnabled(true)
    local e = show("PARTY_INVITE"); afterGuard()
    assert(button(e, 1):GetHeight() == 52, "back on: skinned again")
end)

T("a_closed_popup_takes_everything_away", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    assert(Stub.coveredBy(button(d, 1)))
    StaticPopup_Hide("DEATH")
    assert(Stub.coveredBy(button(d, 1)) == nil)
    local e = show("DEATH")
    assert(e == d and Stub.coveredBy(button(e, 1)), "the same frame guards and holds again")
end)

T("idle_popups_leave_no_timer", function()
    local P = setup(); define()
    local base = #Stub.timers
    local d = show("DEATH"); afterGuard()
    Stub.tap(button(d, 1), 0.8)
    Stub.advance(5)
    assert(#Stub.timers == base, "no timer or ticker of ours runs once the touch and the guard are over: " .. #Stub.timers - base)
end)

T("a_failing_hold_pauses_and_gives_the_game_its_popup", function()
    local P = setup(); define()
    local d = show("ABANDON_QUEST", "x"); afterGuard()
    StaticPopupDialogs.ABANDON_QUEST.OnAccept = function() error("boom") end
    pcall(Stub.tap, button(d, 1), 0.8)
    assert(ns.paused, "an error pauses the add-on as everywhere")
    assert(Stub.coveredBy(button(d, 1)) == nil, "and the popup is the game's again")
end)

-- ---------------------------------------------------------------------------------------
-- Fix round 1: a hold never completes from a timer (R29)

local function pressFor(hold, seconds)
    hold:_Fire("OnMouseDown", "LeftButton")
    Stub.advance(seconds)
end

T("r29_no_accept_fires_without_a_release", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    pressFor(hold, 0.8)
    Stub.advance(5)
    assert(Stub.calls.RepopMe == 0, "the finger is still down: nothing runs from the timer")
    assert(d:IsShown() and hold.face.label:GetText() == "Let go to confirm", hold.face.label:GetText())
    assert(hold.progress == 1)
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.calls.RepopMe == 1, "the release runs it, once")
    assert(not d:IsShown())
end)

T("r29_release_before_ready_fires_none", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    pressFor(hold, 0.7)
    hold:_Fire("OnMouseUp", "LeftButton")
    Stub.advance(2)
    assert(Stub.calls.RepopMe == 0 and d:IsShown())
end)

T("r29_sliding_off_cancels", function()
    local P = setup(); define()
    local d = show("DEATH"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    pressFor(hold, 0.9)
    assert(hold.face.label:GetText() == "Let go to confirm")
    hold:_Fire("OnLeave")
    assert(not hold.bar:IsShown() and hold.face.label:GetText() == "Hold to release spirit", "back to idle")
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.calls.RepopMe == 0, "leave, then release: nothing")
    -- a fresh press still works
    pressFor(hold, 0.8); hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.calls.RepopMe == 1)
end)

T("r29_the_unlock_also_waits_for_the_release", function()
    local P = setup(); define()
    local d = show("DELETE_ITEM", "Cloak"); afterGuard()
    local hold = Stub.coveredBy(button(d, 1))
    pressFor(hold, 0.8); Stub.advance(1)
    assert(Stub.coveredBy(button(d, 1)) == hold, "still locked while the finger is down")
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.coveredBy(button(d, 1)) == nil and hold.face.label:GetText() == "Tap to confirm")
end)

T("r29_helper_and_no_timer_while_the_finger_rests", function()
    local P = setup()
    local b = ns.Kit.RedButton(ns.root, 120, 52, "Log out")
    local done = 0
    local hold = P.HoldButton(b, 0.8, function() done = done + 1 end)
    local base = #Stub.timers
    pressFor(hold, 0.8)
    assert(done == 0)
    Stub.advance(3)
    assert(#Stub.timers <= base, "nothing of ours keeps ticking once it is ready")
    hold:_Fire("OnMouseUp", "LeftButton"); assert(done == 1)
end)

-- Fix round 1: the guard dims the buttons and says why (mockup 12)

T("guard_dims_the_buttons_and_says_why", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE")
    local g = P.GuardFor(d)
    assert(g.wake:IsShown() and g.wake:GetText() == "Buttons wake up after a moment, so a tap already on its way cannot answer.",
        g.wake:GetText())
    local dims = 0
    for _, t in ipairs(g.dims) do
        if t:IsShown() then
            dims = dims + 1
            assert(t.points[1][1] == "ALL" and (t.points[1][2] == button(d, 1) or t.points[1][2] == button(d, 2)))
        end
    end
    assert(dims == 2, "one dimming texture over each of the popup's two buttons")
    Stub.advance(0.5)
    assert(not g.wake:IsShown(), "the line goes with the guard")
    for _, t in ipairs(g.dims) do assert(not t:IsShown()) end
end)

-- Fix round 1: mockup 104, the hearth item's own words

T("hearthstone_use_reads_hold_to_go_home", function()
    local P = setup()
    hearth()
    ns.InfoCard.Show({ kind = "item", bag = 0, slot = 1 })
    local hold = Stub.coveredBy(ns.InfoCard.Button("Use"))
    assert(hold and hold.face:IsShown() and hold.face.label:GetText() == "Hold to go home", "idle label")
    pressFor(hold, 0.8)
    assert(hold.face.label:GetText() == "Let go to confirm")
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.lastItemUsed == nil and hold.face.label:GetText() == "Tap to confirm", "R28 and R29: the hold only unlocks")
    Stub.tap(ns.InfoCard.Button("Use"))
    assert(Stub.lastItemUsed == "0 1")
end)

T("a_card_render_keeps_an_unlock_and_a_press", function()
    local P = setup()
    hearth()
    local subject = { kind = "item", bag = 0, slot = 1 }
    ns.InfoCard.Show(subject)
    local use = ns.InfoCard.Button("Use")
    local hold = Stub.coveredBy(use)
    pressFor(hold, 0.4)
    ns.InfoCard.Show(subject)                 -- the card is drawn again mid-press
    assert(hold.pressAt, "the press goes on")
    Stub.advance(0.4)
    assert(hold.ready, "and gets ready on time")
    hold:_Fire("OnMouseUp", "LeftButton")
    assert(Stub.coveredBy(use) == nil)
    ns.InfoCard.Show(subject)                 -- and again after the unlock
    assert(Stub.coveredBy(ns.InfoCard.Button("Use")) == nil, "an unlock survives a redraw")
    ns.InfoCard.Hide(); ns.InfoCard.Show(subject)
    assert(Stub.coveredBy(ns.InfoCard.Button("Use")), "a closed card starts locked again")
end)

-- Fix round 1: the queue and the timer (R30)

T("r30_one_of_n_badge_on_the_top_popup", function()
    local P = setup(); define()
    local a = show("PARTY_INVITE"); afterGuard()
    assert(not P.GuardFor(a).badge:IsShown(), "one popup: no badge")
    local b = show("TRADE"); local c = show("DUEL")
    assert(P.GuardFor(a).badge:IsShown() and P.GuardFor(a).badge:GetText() == "1 of 3", P.GuardFor(a).badge:GetText())
    assert(not P.GuardFor(b).badge:IsShown() and not P.GuardFor(c).badge:IsShown())
    assert(a:IsShown() and b:IsShown() and c:IsShown(), "nothing is hidden or moved")
    a:Hide()
    assert(P.GuardFor(b).badge:IsShown() and P.GuardFor(b).badge:GetText() == "1 of 2")
    b:Hide()
    assert(not P.GuardFor(c).badge:IsShown(), "the last one has no badge")
end)

T("r30_timed_popup_bar_turns_red_and_ticks", function()
    local P = setup(); define()
    local d = show("TIMED"); afterGuard()
    local g = P.GuardFor(d)
    local bar = g.timerBar
    assert(bar:IsShown() and bar.scripts.OnUpdate, "a timed popup gets the bar and its one OnUpdate")
    local function step(left) d.timeleft = left; bar:_Fire("OnUpdate", 0.2) end
    local ticks = #Stub.sounds
    step(45)
    assert(math.abs(g.frac - 0.75) < 0.01 and not g.red, "gold and three quarters full")
    assert(#Stub.sounds == ticks, "no tick before the last 10 seconds")
    step(10)
    assert(g.red and #Stub.sounds == ticks + 1, "red and one tick at 10")
    step(9.9); step(9.8)
    assert(#Stub.sounds == ticks + 1, "one tick per second, not per frame")
    step(8.9)
    assert(#Stub.sounds == ticks + 2)
    ns.db.feel = { tapSounds = false }
    step(7.9); step(6.9)
    assert(#Stub.sounds == ticks + 2, "silent when tap sounds are off")
    StaticPopup_Hide("TIMED")
    assert(not bar:IsShown() and bar.scripts.OnUpdate == nil, "no OnUpdate once the popup is gone")
end)

T("r30_untimed_popups_have_no_bar_and_no_update", function()
    local P = setup(); define()
    local d = show("PARTY_INVITE"); afterGuard()
    local bar = P.GuardFor(d).timerBar
    assert(not bar:IsShown() and bar.scripts.OnUpdate == nil)
end)

T("r31_delete_good_item_is_a_plain_tap", function()
    local P = setup(); define()
    local d = show("DELETE_GOOD_ITEM", "Epic"); afterGuard()
    assert(Stub.coveredBy(button(d, 1)) == nil, "typing DELETE is its confirmation: no hold on top")
    Stub.tap(button(d, 1))
    assert(Stub.calls.DeleteCursorItem == 1)
    local e = show("DELETE_ITEM", "Cloak"); afterGuard()
    assert(Stub.coveredBy(button(e, 1)), "DELETE_ITEM keeps its hold, then tap")
end)

Stub.done("popups")
