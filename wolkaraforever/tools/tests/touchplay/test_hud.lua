-- Task 10: the rest of the HUD: quest list, minimap ring, Bags and Menu, XP line, level-up, screen
-- edges, errors near the button, mirror timers, away (mockups 01, 13-19, 25, 32, 33, 72, 76).
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

-- A game session with the whole add-on loaded and laid out.
local function setup()
    Questie = nil                           -- a test that failed half way may have left one
    Stub.reset(); Stub.loadAll(); Stub.login()
    return ns.Hud
end

local function quest(id, title, extra)
    local q = { id = id, title = title, objectives = { { text = "Mountain Lion Blood: 7/10", finished = false } } }
    for k, v in pairs(extra or {}) do q[k] = v end
    return q
end

-- ---------------------------------------------------------------------------------------
-- The quest list

T("quest_lines_limit_and_more", function()
    local Hud = setup()
    local watched = {}
    for i = 1, 6 do watched[i] = { id = i, title = "Quest " .. i, objectives = {} } end
    local lines, more = Hud.QuestLines(watched, 4)
    assert(#lines == 4 and more == 2, "6 watched: 4 lines, 2 more")
    lines, more = Hud.QuestLines(watched, 8)
    assert(#lines == 6 and more == 0)
    lines, more = Hud.QuestLines({}, 4)
    assert(#lines == 0 and more == 0)
    -- the screen shows the "+ 2 more" line, one tap from the log
    local list = {}
    for i = 1, 6 do list[i] = quest(i, "Quest " .. i) end
    Stub.setQuests(list)
    assert(Hud.more:IsShown() and Hud.more:GetText() == "+ 2 more · tap to open the quest log", Hud.more:GetText())
    for i = 1, 4 do assert(Hud.entries[i]:IsShown()) end
    Stub.setQuests({ quest(1, "Quest 1") })
    assert(not Hud.more:IsShown() and Hud.entries[1]:IsShown() and not Hud.entries[2]:IsShown())
end)

T("quest_card_hidden_when_none", function()
    local Hud = setup()
    Stub.setQuests({})
    assert(not Hud.quest.content:IsShown() and not Hud.quest:IsMouseEnabled(), "nothing shown, nothing to tap")
    Stub.setQuests({ quest(1, "Elixir of Pain") })
    assert(Hud.quest.content:IsShown() and Hud.quest:IsMouseEnabled())
    assert(Hud.entries[1].title:GetText():find("Elixir of Pain", 1, true))
    assert(Hud.entries[1].lines[1]:GetText() == "- Mountain Lion Blood: 7/10")
    -- in a fight the empty list cannot change the secure button; it waits
    Stub.setQuests({}); Stub.combat(true)
    Stub.setQuests({ quest(1, "Elixir of Pain") })
    assert(not ns.paused, ns.lastError)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Hud.quest:IsMouseEnabled())
end)

T("quest_list_steps_aside_for_a_target", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Elixir of Pain") })
    Stub.applyDrivers(); assert(Hud.quest:IsShown())
    Stub.setTarget("enemy"); Stub.applyDrivers(); assert(not Hud.quest:IsShown())
    Stub.setTarget(nil); Stub.applyDrivers(); assert(Hud.quest:IsShown())
end)

T("ready_quest_green", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Elixir of Pain", { complete = true }) })
    local lines = Hud.QuestLines(Hud.ReadQuests(), 4)
    assert(lines[1].state == "ready" and lines[1].suffix == "(Complete)")
    local c = lines[1].suffixColour
    assert(c[2] > 0.9 and c[1] < 0.3, "green")
    local text = Hud.entries[1].title:GetText()
    assert(text:find("(Complete)", 1, true) and text:find("|cff1eff00", 1, true), text)
    assert(Hud.entries[1].lines[1]:GetText() == "- Ready to turn in")
end)

T("failed_quest_red", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Escorting Erland", { failed = true }) })
    local text = Hud.entries[1].title:GetText()
    assert(text:find("(Failed)", 1, true) and text:find("|cffff2121", 1, true), text)
    local r, g, b = Hud.entries[1].lines[1]:GetTextColor()
    assert(r == 1 and g < 0.6 and b < 0.6, "the objective line reads red")
end)

T("new_quest_until_first_progress", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "A Recipe for Death") })
    Stub.fire("QUEST_ACCEPTED", 1)
    assert(Hud.entries[1].title:GetText():find("(new)", 1, true))
    Stub.quests[1].objectives[1].numFulfilled = 1
    Stub.fire("QUEST_WATCH_UPDATE", 1)
    assert(not Hud.entries[1].title:GetText():find("(new)", 1, true))
end)

T("objective_just_done_flashes_gold_with_the_games_sound", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Elixir of Pain", { objectives = {
        { text = "Stanley's Elixir delivered", finished = true },
        { text = "Mountain Lion Blood: 9/10", finished = false } } }) })
    local before = #Stub.sounds
    Stub.quests[1].objectives[2].finished = true
    Stub.fire("QUEST_WATCH_UPDATE", 1)
    assert(#Stub.sounds == before + 1 and Stub.sounds[#Stub.sounds] == 43936, "the game's objective sound")
    local r, g, b = Hud.entries[1].lines[2]:GetTextColor()
    assert(r == 1 and near(g, 0.82) and b == 0, "gold")
    r, g, b = Hud.entries[1].lines[1]:GetTextColor()
    assert(r == 1 and g == 1 and b == 1, "the other line is untouched")
    Stub.advance(2.2)
    r, g, b = Hud.entries[1].lines[2]:GetTextColor()
    assert(r == 1 and g == 1 and b == 1, "back to white after 2 seconds")
    Stub.fire("QUEST_LOG_UPDATE"); assert(#Stub.sounds == before + 1, "the sound plays once")
end)

T("objective_just_done_band_check_and_plus_one_then_settles", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Elixir of Pain", { objectives = {
        { text = "Stanley's Elixir delivered", finished = true },
        { text = "Mountain Lion Blood: 9/10", finished = false } } }) })
    local entry = Hud.entries[1]
    assert(not entry.band:IsShown() and not entry.check:IsShown() and not entry.plus:IsShown(), "nothing before the flash")
    Stub.quests[1].objectives[2].finished = true
    Stub.fire("QUEST_WATCH_UPDATE", 1)
    assert(entry.band:IsShown() and entry.band.color[1] == 1 and entry.band.color[4] > 0.2, "a gold band")
    assert(entry.band.points[#entry.band.points][5] < entry.band.points[1][5] or #entry.band.points == 1)
    assert(entry.check:IsShown() and entry.check.texture == "Interface\\Buttons\\UI-CheckBox-Check", "the game's check")
    assert(entry.plus:IsShown() and entry.plus:GetText() == "+1")
    local r, g, b = entry.plus:GetTextColor(); assert(g == 1 and r < 0.3 and b == 0, "green")
    assert(entry.lines[2]:GetText() == "- Mountain Lion Blood: 9/10", "no (Done) while it flashes")
    Stub.advance(2.2)
    assert(not entry.band:IsShown() and not entry.check:IsShown() and not entry.plus:IsShown(), "all gone after 2 seconds")
    assert(entry.lines[2]:GetText():find("(Done)", 1, true), "it settles to the plain done line")
end)

T("timed_quest_uses_timer_duration", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Escorting Erland", { timeTotal = 900, timeElapsed = 288 }) })
    local entry = Hud.entries[1]
    assert(entry.bar and entry.bar:IsShown(), "a timer bar")
    assert(entry.bar.timerDuration and entry.bar.timerDuration.total == 900, "SetTimerDuration got a duration object")
    assert(near(entry.bar.timerDuration.start, Stub.now - 288))
    local binding = Stub.bindingsMade[#Stub.bindingsMade]
    assert(binding.enabled and binding.duration == entry.bar.timerDuration and binding.format == "{} left")
    local c = entry.bar.barColor
    assert(c[1] == 1 and c[2] > 0.7, "gold while there is time")
    -- the last minute turns it red, at once and when the minute starts
    Stub.quests[1].timeElapsed = 850; Stub.fire("QUEST_WATCH_UPDATE", 1)
    c = entry.bar.barColor; assert(c[1] == 1 and c[2] < 0.3, "red in the last 60 seconds")
    Stub.quests[1].timeElapsed = 400; Stub.fire("QUEST_WATCH_UPDATE", 1)
    c = entry.bar.barColor; assert(c[2] > 0.7)
    Stub.quests[1].timeElapsed = 800; Stub.fire("QUEST_WATCH_UPDATE", 1)
    c = entry.bar.barColor; assert(c[2] > 0.7, "100 seconds left: still gold")
    Stub.quests[1].timeElapsed = 842     -- 58 seconds left by the time the timer fires
    Stub.advance(41)
    c = entry.bar.barColor; assert(c[2] < 0.3, "the timer turned it red when the last minute began")
    -- a quest that is no longer timed gives the bar back
    Stub.setQuests({ quest(1, "Escorting Erland") })
    assert(not entry.bar:IsShown())
end)

T("quest_tap_opens_the_log_hold_asks_the_card", function()
    local Hud = setup()
    Stub.setQuests({ quest(7, "Elixir of Pain"), quest(8, "Farren's Proof") })
    assert(Stub.inherits(Hud.quest, "SecureActionButtonTemplate"))
    Stub.combat(true)
    Stub.click("TouchPlayQuest", "LeftButton")
    assert(Stub.macroClicks[1] == "QuestLogMicroButton" and Stub.gameClicks.QuestLogMicroButton == 1, "a secure click, in a fight too")
    local actions = #Stub.secureActions
    local asked
    ns.InfoCard = { Show = function(what, frame) asked = { what = what, frame = frame } end }
    Stub.click("TouchPlayQuest", "RightButton")
    assert(#Stub.secureActions == actions and Stub.gameClicks.QuestLogMicroButton == 1, "a hold never opens the log")
    assert(asked and asked.what.kind == "questObjective" and asked.what.questID == 7 and asked.frame == Hud.entries[1])
    asked = nil; Stub.click("TouchPlayQuest", "LeftButton"); assert(asked == nil, "a tap asks no card")
    assert(not ns.paused, ns.lastError)
end)

-- Questie with its own "auto track" off: only the quests it was told to track (Questie.db.char.TrackedQuests).
T("quest_list_prefers_questie_when_loaded", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Game's quest"), quest(2, "Questie's quest", { watched = false }) })
    Questie = { db = { profile = { trackerEnabled = true, autoTrackQuests = false },
        char = { TrackedQuests = { [2] = true }, AutoUntrackedQuests = {} } } }
    Stub.fire("QUEST_LOG_UPDATE")
    Questie = nil
    assert(Hud.entries[1].title:GetText():find("Questie's quest", 1, true) and not Hud.entries[2]:IsShown())
end)

-- iPad run 8 (17 Nov, Deathknell, "Rude Awakening" accepted and complete): the list under the player card was empty.
-- Questie (v12.9.0) tracks every quest in the log by default ("auto track"): its TrackedQuests table stays empty and
-- only AutoUntrackedQuests is written (QuestieQuest:IsQuestTracked). TouchPlay read TrackedQuests alone, so it showed
-- nothing. The list follows Questie's own rule; and when nothing is watched it shows the quests in the log.
local function questie(autoTrack, tracked, untracked, trackerOn)
    return { db = { profile = { trackerEnabled = trackerOn ~= false, autoTrackQuests = autoTrack },
        char = { TrackedQuests = tracked or {}, AutoUntrackedQuests = untracked or {} } } }
end

local function titles(Hud)
    local list = {}
    for i = 1, #Hud.entries do
        if Hud.entries[i]:IsShown() then list[#list + 1] = (Hud.entries[i].title:GetText():gsub(" |c.*$", "")) end
    end
    return table.concat(list, "|")
end

T("questie_auto_tracking_shows_the_quests_in_the_log", function()
    local Hud = setup()
    Questie = questie(true)
    -- Questie leaves the game's watch list empty (a stub that empties watches like Questie does)
    Stub.setQuests({ quest(1, "Rude Awakening", { complete = true, watched = false }) })
    local shown = titles(Hud)
    assert(shown:find("Rude Awakening", 1, true), "the player's one quest is listed: " .. shown)
    local lines = Hud.QuestLines(Hud.ReadQuests(), 4)
    assert(lines[1].state == "ready" and lines[1].suffix == "(Complete)", "Quest complete!")
    assert(Hud.quest.content:IsShown() and Hud.quest:IsMouseEnabled())
    -- a quest the player untracked in Questie leaves the list
    Questie = questie(true, nil, { [1] = true })
    Stub.setQuests({ quest(1, "Rude Awakening", { watched = false }), quest(2, "The Mindless Ones", { watched = false }) })
    shown = titles(Hud)
    Questie = nil
    assert(shown == "The Mindless Ones", shown)
    assert(not ns.paused, ns.lastError)
end)

T("questie_tracker_off_uses_the_games_watches", function()
    local Hud = setup()
    Questie = questie(true, nil, nil, false)  -- Questie's tables go stale with its tracker off
    Stub.setQuests({ quest(1, "Rude Awakening", { watched = false }), quest(2, "The Mindless Ones") })
    local shown = titles(Hud)
    Questie = nil
    assert(shown == "The Mindless Ones", shown)
end)

T("nothing_watched_shows_the_quests_in_the_log", function()
    local Hud = setup()
    -- no Questie, the game's watch list empty: the log, in its order
    Stub.setQuests({ quest(3, "Rude Awakening", { complete = true, watched = false }),
        quest(1, "The Mindless Ones", { watched = false }) })
    assert(titles(Hud) == "Rude Awakening|The Mindless Ones", titles(Hud))
    -- watched quests first: only they show while there are any
    Stub.setQuests({ quest(3, "Rude Awakening", { watched = false }), quest(1, "The Mindless Ones") })
    assert(titles(Hud) == "The Mindless Ones", titles(Hud))
    -- Questie in manual mode with nothing tracked: the log too
    Questie = questie(false)
    Stub.setQuests({ quest(3, "Rude Awakening", { watched = false }) })
    local shown = titles(Hud)
    Questie = nil
    assert(shown == "Rude Awakening", shown)
end)

T("the_quest_key_works_for_a_quest_listed_from_the_log", function()
    local Hud = setup()
    local key = ns.Contract.KeysFor("quest")
    local function press()
        local before = #Stub.commandsRun
        Stub.pressKey(key)
        return Stub.commandsRun[#Stub.commandsRun] == "TOGGLEQUESTLOG" and #Stub.commandsRun > before
    end
    Questie = questie(true)
    Stub.setQuests({ quest(1, "Rude Awakening", { complete = true, watched = false }) }); Stub.applyDrivers()
    assert(press(), "the list has a quest: the key opens the quest log")
    Stub.setQuests({}); Stub.applyDrivers()
    Questie = nil
    assert(not press(), "empty log: nothing")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- The minimap ring

T("minimap_ring_in_the_mockup_places", function()
    local Hud = setup()
    local x, y = Stub.centre(Hud.disc); assert(near(x, 1250, 1) and near(y, 134, 1), x .. "," .. y)
    assert(near(Hud.disc:GetWidth(), 172))
    local a = Hud.border.touchAnchor
    assert(a.x == 1035 and a.y == 0 and a.w == 330 and a.h == 330 and a.corner == "TR")
    x, y = Stub.centre(Hud.bags); assert(near(x, 968 + 30) and near(y, 34 + 30) and near(Hud.bags:GetWidth(), 60))
    x, y = Stub.centre(Hud.menu); assert(near(x, 968 + 30) and near(y, 128 + 30))
    x, y = Stub.centre(Hud.quest)
    assert(Hud.quest.touchAnchor.x == 24 and Hud.quest.touchAnchor.y == 200 and Hud.quest:GetWidth() == 340)
    x, y = Stub.centre(Hud.minimap); assert(near(x, 1250, 1) and near(y, 134, 1))
end)

T("game_minimap_moves_into_the_ring_and_back", function()
    local Hud = setup()
    local map = Stub.frames.Minimap
    local container = Stub.frames.MinimapCluster.children[3]
    assert(Hud.IsMinimapInRing() == true and map:GetParent() == Hud.disc)
    assert(map:GetWidth() == 172 and Stub.frames.MinimapBackdrop:GetAlpha() == 0, "the game's own ring art is off")
    ns.Hud:Restore()
    assert(map:GetParent() == container and map:GetWidth() == 198 and map:GetNumPoints() == 1)
    assert(map:GetPoint(1) == "CENTER" and Stub.frames.MinimapBackdrop:GetAlpha() == 1)
    ns.Hud:Layout(); assert(map:GetParent() == Hud.disc)
    -- in a fight the game's minimap is left alone, then moved when it ends
    Stub.combat(true); ns.Hud:Restore()
    assert(map:GetParent() == Hud.disc and not ns.paused, "waits for the end of the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(map:GetParent() == container)
    -- a Restore that comes before the layout is not undone by it
    Stub.combat(true); ns.Hud:Layout(); ns.Hud:Restore(); Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(map:GetParent() == container)
end)

T("minimap_tap_opens_the_world_map_through_a_secure_click", function()
    local Hud = setup()
    assert(Stub.inherits(Hud.minimap, "SecureActionButtonTemplate"))
    Stub.combat(true)
    Stub.click("TouchPlayMinimap", "LeftButton")
    assert(Stub.calls.ToggleWorldMap == 1, "the game's own world map toggle was clicked")
    assert(Hud.minimap:GetAttribute("clickbutton") == Stub.frames.MinimapCluster.ZoneTextButton)
    assert(not ns.paused, ns.lastError)
end)

T("zone_coordinates_and_clock", function()
    local Hud = setup()
    assert(Hud.zoneText:GetText() == "Tarren Mill")
    assert(Hud.coordText:GetText() == "62.3, 20.2 · 3:10", Hud.coordText:GetText())
    Stub.mapPos, Stub.minute, Stub.zone = { 0.5, 0.25 }, 5, "Hillsbrad Foothills"
    Stub.fire("ZONE_CHANGED")
    assert(Hud.zoneText:GetText() == "Hillsbrad Foothills" and Hud.coordText:GetText() == "50.0, 25.0 · 3:05")
    Stub.mapPos, Stub.minute = nil, 6
    Stub.advance(1.1)
    assert(Hud.coordText:GetText() == "3:06", "no position: the clock only")
end)

T("mail_dot_on_pending_mail", function()
    local Hud = setup()
    assert(not Hud.mail:IsShown())
    Stub.mail = true; Stub.fire("UPDATE_PENDING_MAIL")
    assert(Hud.mail:IsShown() and Hud.mail.dot:IsShown(), "the letter with a gold dot")
    assert(Hud.mail.icon.touchGlyph == "mail", "the envelope glyph")
    assert(Hud.mail:GetWidth() >= 44 or select(1, Hud.mail:GetHitRectSize()) >= 44, "a finger can hit it")
    Stub.mail = false; Stub.fire("UPDATE_PENDING_MAIL")
    assert(not Hud.mail:IsShown())
end)

T("tracking_icon_shows_the_active_one_and_a_tap_opens_the_choice", function()
    local Hud = setup()
    assert(not Hud.tracking:IsShown())
    Stub.tracking = { { name = "Find Minerals", texture = "mineicon", active = false },
        { name = "Find Herbs", texture = "herbicon", active = true } }
    Stub.fire("MINIMAP_UPDATE_TRACKING")
    assert(Hud.tracking:IsShown() and Hud.tracking.icon.texture == "herbicon")
    Stub.click(Hud.tracking); assert(Stub.calls.TrackingMenu == 1)
    Stub.tracking[2].active = false; Stub.fire("MINIMAP_UPDATE_TRACKING")
    assert(not Hud.tracking:IsShown())
end)

T("instance_minimap_says_no_map", function()
    local Hud = setup()
    assert(not Hud.noMap:IsShown() and not Hud.arrow:IsShown())
    Stub.instanceKind, Stub.zone = "party", "Scarlet Monastery"
    Stub.fire("ZONE_CHANGED_NEW_AREA")
    assert(Hud.noMap:IsShown() and Hud.noMap:GetText() == "No map inside. Open the map.", "one line of text, as the plan writes it")
    assert(not Hud.noMap:GetText():find("\n", 1, true))
    assert(Hud.noMap:GetText():find("No map inside.", 1, true))
    assert(Hud.noMap:GetText():find("Open the map.", 1, true) and Hud.arrow:IsShown(), "the words and the arrow")
    assert(Stub.frames.Minimap:GetAlpha() == 0 and Hud.zoneText:GetText() == "Scarlet Monastery")
    assert(Hud.coordText:GetText() == "3:10", "no coordinates inside")
    Stub.instanceKind = "none"; Stub.fire("ZONE_CHANGED_NEW_AREA")
    assert(not Hud.noMap:IsShown() and Stub.frames.Minimap:GetAlpha() == 1)
end)

T("zoom_rings_follow_the_pinch", function()
    local Hud = setup()
    assert(not Hud.zoomIn:IsShown() and not Hud.zoomOut:IsShown())
    Hud.minimap.scripts.OnMouseWheel(Hud.minimap, 1)
    assert(Stub.zoom == 1 and Hud.zoomIn:IsShown() and Hud.zoomOut:IsShown())
    Stub.click(Hud.zoomIn); assert(Stub.zoom == 2)
    Stub.click(Hud.zoomOut); Stub.click(Hud.zoomOut); assert(Stub.zoom == 0 and not Hud.zoomIn:IsShown())
    Stub.click(Hud.zoomOut); assert(Stub.zoom == 0, "no zooming out past the start")
    for _, r in ipairs({ Hud.zoomIn, Hud.zoomOut }) do
        local a = r.touchAnchor
        assert(a.x + a.w <= 1366 and a.x >= 0, "kept on the screen")
    end
end)

-- ---------------------------------------------------------------------------------------
-- Bags and Menu

T("bags_tap_clicks_the_games_backpack", function()
    local Hud = setup()
    assert(Stub.inherits(Hud.bags, "SecureActionButtonTemplate") and Hud.bags:GetAttribute("*type1") == "macro")
    Stub.combat(true)
    Stub.click("TouchPlayBags", "LeftButton")
    assert(Stub.macroClicks[1] == "MainMenuBarBackpackButton" and Stub.gameClicks.MainMenuBarBackpackButton == 1)
    assert(not ns.paused, ns.lastError)
end)

T("menu_tap_opens_our_menu_never_the_games", function()
    local Hud = setup()
    assert(Hud.menu:GetAttribute("*type1") == nil, "no secure action: the game's menu button only acts under the pointer")
    Stub.click("TouchPlayMenu", "LeftButton")
    assert(ns.Menu.IsOpen() and Stub.calls.ToggleGameMenu == 0 and #Stub.macroClicks == 0, "our Menu, not the game's")
    ns.Menu.Close()
    Stub.combat(true); Stub.click("TouchPlayMenu", "LeftButton")
    assert(ns.Menu.IsOpen() and not ns.paused, "in a fight too")
    Stub.click(ns.Menu.dim); Stub.combat(false)
    Stub.click("TouchPlayMenu", "RightButton"); assert(not ns.Menu.IsOpen())
    -- Ruling R18 is over: with no Menu there is no fallback to the game's menu
    local menu = ns.Menu
    ns.Menu = nil
    Stub.click("TouchPlayMenu", "LeftButton")
    assert(Stub.calls.ToggleGameMenu == 0 and not ns.paused, ns.lastError)
    ns.Menu = menu
end)

T("menu_dot_when_talent_points", function()
    local Hud = setup()
    assert(not Hud.menu.dot:IsShown())
    Stub.talentPoints = true; Stub.fire("PLAYER_TALENT_UPDATE")
    assert(Hud.menu.dot:IsShown(), "a talent point waits")
    Stub.talentPoints = false; Stub.fire("PLAYER_TALENT_UPDATE")
    assert(not Hud.menu.dot:IsShown())
    -- a quest ready to hand in
    Stub.setQuests({ quest(1, "Elixir of Pain", { complete = true }) })
    assert(Hud.menu.dot:IsShown(), "a ready quest waits")
    Stub.setQuests({ quest(1, "Elixir of Pain") })
    assert(not Hud.menu.dot:IsShown())
    -- an unread whisper, until it is read
    Stub.fire("CHAT_MSG_WHISPER", "thanks for the water", "Mira")
    assert(Hud.menu.dot:IsShown(), "an unread whisper waits")
    Hud.ClearWhisper(); assert(not Hud.menu.dot:IsShown())
end)

-- ---------------------------------------------------------------------------------------
-- Experience, level up, edges, away

T("xp_line_with_the_rested_stretch", function()
    local Hud = setup()
    assert(Hud.xp:GetValue() == 4700 and select(2, Hud.xp:GetMinMaxValues()) == 10000)
    assert(Hud.restedBar:GetValue() == 0 and not Hud.restedText:IsShown())
    Stub.xp.rested = 900; Stub.setResting(true); Stub.fire("UPDATE_EXHAUSTION")
    assert(Hud.restedBar:GetValue() == 5600, "the blue stretch runs on from the purple")
    assert(Hud.restedText:IsShown() and Hud.restedText:GetText() == "Rested: double experience for the next 900")
    Stub.xp.rested = 9000; Stub.fire("UPDATE_EXHAUSTION")
    assert(Hud.restedBar:GetValue() == 10000, "never past the end of the line")
    Stub.setResting(false); assert(not Hud.restedText:IsShown())
    Stub.xp.have = 6000; Stub.fire("PLAYER_XP_UPDATE"); assert(Hud.xp:GetValue() == 6000)
    Stub.xp.max = 0; Stub.fire("PLAYER_XP_UPDATE"); assert(not Hud.xp:GetParent():IsShown(), "no line at the top level")
end)

T("level_up_banner", function()
    local Hud = setup()
    assert(not Hud.banner:IsShown())
    Stub.fire("PLAYER_LEVEL_UP", 35, 53, 61, 1)
    assert(Hud.banner:IsShown())
    assert(Hud.banner.title:GetText() == "You have reached level 35!")
    assert(Hud.banner.gains:GetText() == "+ 53 health · + 61 mana · + 1 talent point", Hud.banner.gains:GetText())
    Stub.advance(4.2); assert(not Hud.banner:IsShown())
    Stub.fire("PLAYER_LEVEL_UP", 36, 40, 0, 2)
    assert(Hud.banner.gains:GetText() == "+ 40 health · + 2 talent points")
    -- a second level-up inside the time keeps its own full time
    Stub.advance(3); Stub.fire("PLAYER_LEVEL_UP", 37, 10, 10, 0); Stub.advance(2)
    assert(Hud.banner:IsShown() and Hud.banner.title:GetText():find("37"))
end)

T("red_edge_under_a_quarter_blue_tint_as_a_ghost", function()
    local Hud = setup()
    assert(Hud.edge.low.alpha == 0 and not Hud.edge.ghost:IsShown())
    Stub.setUnit("player", { health = 300, healthMax = 1460 }); Stub.fire("UNIT_HEALTH", "player")
    assert(Hud.edge.low.alpha == 1, "red under 25%")
    Stub.setUnit("player", { health = 400, healthMax = 1460 }); Stub.fire("UNIT_HEALTH", "player")
    assert(Hud.edge.low.alpha == 0, "27% is not low")
    Stub.setUnit("player", { health = 200 }); Stub.fire("UNIT_HEALTH", "player")
    assert(Hud.edge.low.alpha == 1)
    Stub.setDead("player", "dead"); assert(Hud.edge.low.alpha == 0 and not Hud.edge.ghost:IsShown(), "no glow once dead")
    Stub.setDead("player", "ghost")
    assert(Hud.edge.ghost:IsShown() and Hud.edge.ghost.color[3] == 1 and Hud.edge.ghost.color[4] < 0.2, "blue tint")
    Stub.setDead("player", nil); Stub.fire("PLAYER_UNGHOST"); assert(not Hud.edge.ghost:IsShown())
    assert(Hud.edge.low.texture:find("LowHealth") and Hud.edge.low.blendMode == "ADD")
end)

T("away_card_dims_and_the_first_tap_only_wakes", function()
    local Hud = setup()
    assert(not Hud.afk:IsShown())
    Stub.setAfk(true)
    assert(Hud.afk:IsShown() and Hud.afk.title:GetText() == "You are away")
    assert(Hud.afk.tap:GetText() == "Tap anywhere to come back.")
    assert(Hud.afk.minutes:GetText() == "Away for 1 minute · the game logs you out after 30")
    assert(Hud.afk.dim.color[4] > 0.4, "the screen dims")
    Stub.advance(130)
    assert(Hud.afk.minutes:GetText() == "Away for 2 minutes · the game logs you out after 30", Hud.afk.minutes:GetText())
    local spells = Stub.calls.UseAction
    Stub.click(Hud.afk)
    assert(not Hud.afk:IsShown() and #Stub.chatSent == 1 and Stub.chatSent[1].kind == "AFK" and Stub.chatSent[1].text == "")
    assert(Stub.calls.UseAction == spells and Stub.calls.CastSpell == 0 and Stub.calls.TargetUnit == 0, "the tap never casts")
    assert(not UnitIsAFK("player"), "the game's flag is cleared")
    -- already back (the game cleared it first): the tap sends nothing
    Stub.setAfk(true); Stub.setAfk(false)
    assert(not Hud.afk:IsShown() and #Stub.chatSent == 1)
end)

-- ---------------------------------------------------------------------------------------
-- Errors near the button, mirror timers

T("error_near_last_pressed_button", function()
    local Hud = setup()
    local button = Stub.frames.TouchPlaySpell3
    Stub.click(button)
    Stub.fire("UI_ERROR_MESSAGE", 1, "Target needs to be in front of you.")
    assert(Hud.errorFrame:IsShown() and Hud.errorFrame.text:GetText() == "Target needs to be in front of you.")
    local p = Hud.errorFrame.points[#Hud.errorFrame.points]
    assert(p[2] == button and p[5] == 40 and p[1] == "BOTTOMRIGHT" and p[3] == "TOPRIGHT", "40 units above that button")
    Stub.advance(1.9); assert(Hud.errorFrame:IsShown())
    Stub.advance(0.2); assert(not Hud.errorFrame:IsShown(), "gone after 2 seconds")
    -- another button, another place
    Stub.click(Stub.frames.TouchPlaySpell1)
    Stub.fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    assert(Hud.errorFrame.points[#Hud.errorFrame.points][2] == Stub.frames.TouchPlaySpell1)
    -- an error that comes later than half a second after a press belongs to something else
    Stub.advance(2.5)
    Stub.advance(0.6); Stub.fire("UI_ERROR_MESSAGE", 1, "You can't do that yet.")
    assert(not Hud.errorFrame:IsShown())
    -- the first error's timer does not hide the second one early
    Stub.click(button); Stub.fire("UI_ERROR_MESSAGE", 1, "One"); Stub.advance(1.5)
    Stub.click(button); Stub.fire("UI_ERROR_MESSAGE", 1, "Two"); Stub.advance(1)
    assert(Hud.errorFrame:IsShown() and Hud.errorFrame.text:GetText() == "Two")
    Stub.advance(1.1); assert(not Hud.errorFrame:IsShown())
end)

T("error_with_no_press_shows_nothing", function()
    local Hud = setup()
    Stub.fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
    assert(not Hud.errorFrame:IsShown() and not ns.paused)
end)

T("error_during_the_click_is_still_near_the_button", function()
    local Hud = setup()
    local button = Stub.frames.TouchPlaySpell2
    -- the game answers a failed cast while the click runs, before PostClick
    button:_Fire("PreClick", "LeftButton")
    Stub.fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
    assert(Hud.errorFrame:IsShown() and Hud.errorFrame.points[#Hud.errorFrame.points][2] == button)
end)

T("mirror_timers_move_to_the_top_middle_and_back", function()
    local Hud = setup()
    local box = Stub.frames.MirrorTimerContainer
    local p = box.points[#box.points]
    assert(p[1] == "TOP" and p[2] == Stub.frames.TouchPlayRoot and p[3] == "TOPLEFT" and p[4] == 533 + 150 and p[5] == -150,
        "(533, 150) in layout units, 300 wide, centred on its middle")
    for _, timer in ipairs(box.mirrorTimers) do
        assert(timer:GetWidth() == 300 and timer.StatusBar:GetWidth() == 289)
    end
    -- Edit Mode puts it back where the layout says: it is moved again
    box:SetPoint("TOP", Stub.frames.UIParent, "TOP", 0, -100)
    p = box.points[#box.points]; assert(p[2] == Stub.frames.TouchPlayRoot and p[5] == -150)
    ns.Hud:Restore()
    p = box.points[#box.points]
    assert(#box.points == 1 and p[2] == Stub.frames.UIParent and p[5] == -100)
    assert(box.mirrorTimers[1]:GetWidth() == 206 and box.mirrorTimers[1].StatusBar:GetWidth() == 195)
    box:SetPoint("TOP", Stub.frames.UIParent, "TOP", 0, -100)
    assert(box.points[#box.points][2] == Stub.frames.UIParent, "left alone after Restore")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Secret values, the contract, fights

T("secret_values_never_touched", function()
    local Hud = setup(); Stub.secretUnits(true)
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do Stub.fire(event, "player") end
    Stub.fire("PLAYER_ENTERING_WORLD"); Stub.fire("PLAYER_DEAD"); Stub.fire("PLAYER_ALIVE")
    Stub.fire("PLAYER_FLAGS_CHANGED", "player"); Stub.fire("PLAYER_XP_UPDATE"); Stub.fire("QUEST_LOG_UPDATE")
    assert(not ns.paused, ns.lastError)
    assert(Stub.isSecret(Hud.edge.low.alpha), "the hidden answer went straight into the alpha")
    ns.Each("Refresh"); assert(not ns.paused, ns.lastError)
    -- hidden values in a fight, the screen still works
    Stub.combat(true)
    Stub.fire("UNIT_HEALTH", "player"); Stub.fire("UPDATE_PENDING_MAIL"); Stub.fire("ZONE_CHANGED")
    Stub.fire("UI_ERROR_MESSAGE", 1, "Out of range."); Stub.fire("PLAYER_LEVEL_UP", 35, 1, 1, 0)
    assert(not ns.paused, ns.lastError)
    -- a hidden error text and hidden map numbers are skipped, not compared
    Stub.fire("UI_ERROR_MESSAGE", 1, Stub.secret())
    assert(not ns.paused, ns.lastError)
    Stub.mapPos = { Stub.secret(), Stub.secret() }
    Stub.advance(1.1); Stub.fire("ZONE_CHANGED")
    assert(not ns.paused, ns.lastError)
    assert(Hud.coordText:GetText() == "3:10")
end)

T("a_fight_never_blocks_the_hud", function()
    local Hud = setup(); Stub.combat(true)
    Stub.setQuests({ quest(1, "Elixir of Pain", { timeTotal = 900, timeElapsed = 100 }), quest(2, "Farren's Proof", { complete = true }) })
    Stub.fire("QUEST_WATCH_UPDATE", 1); Stub.mail = true; Stub.fire("UPDATE_PENDING_MAIL")
    Stub.talentPoints = true; Stub.fire("PLAYER_TALENT_UPDATE"); Stub.instanceKind = "raid"; Stub.fire("ZONE_CHANGED_NEW_AREA")
    Stub.setAfk(true); Stub.setAfk(false)
    ns.Each("Refresh")
    assert(not ns.paused, ns.lastError)
    ns.Hud:Layout()
    assert(not ns.paused, ns.lastError)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused, ns.lastError)
end)

T("areas_registered_with_the_contract", function()
    setup()
    local text = ns.Contract.Write()
    assert(text:find("quest,TL,24,200,340,260,", 1, true), text)
    assert(text:find("minimap,TR,30,48,172,172,", 1, true), text)
    assert(text:find("bags,TR,338,34,60,60,", 1, true), text)
    assert(text:find("menu,TR,338,128,60,60,", 1, true), text)
    ns.Contract.Apply()
    local qt, qh = ns.Contract.KeysFor("quest")
    -- iPad run 4: the app's key runs the game's own binding command, which needs no game button to exist (iPad run 7:
    -- bound by the quest gate, only while the list shows quests)
    Stub.setQuests({ quest(1, "Elixir of Pain") }); Stub.applyDrivers()
    assert(Stub.bindings[qt] and Stub.bindings[qt].command == "TOGGLEQUESTLOG" and not Stub.bindings[qt].click)
    assert(Stub.bindings[qh].click == "TouchPlayQuest" and Stub.bindings[qh].button == "RightButton")
    local mt = ns.Contract.KeysFor("minimap"); assert(Stub.bindings[mt].command == "TOGGLEWORLDMAP")
    local bt = ns.Contract.KeysFor("bags"); assert(Stub.bindings[bt].command == "OPENALLBAGS")
    local nt = ns.Contract.KeysFor("menu"); assert(Stub.bindings[nt].click == "TouchPlayMenu")
end)

T("the_keys_of_bags_quest_and_map_work_with_no_game_button_at_all", function()
    local Hud = setup()
    -- this client (Camelot, the controller's bar) has none of the micro or bag buttons
    _G.MainMenuBarBackpackButton, _G.QuestLogMicroButton = nil, nil
    Stub.setQuests({ quest(1, "Elixir of Pain") })
    ns.Contract.Apply()
    local function press(name)
        local key = ns.Contract.KeysFor(name)
        assert(Stub.pressKey(key), name)
        assert(not ns.paused, ns.lastError)
        return Stub.commandsRun[#Stub.commandsRun]
    end
    assert(press("bags") == "OPENALLBAGS")
    assert(press("quest") == "TOGGLEQUESTLOG")
    assert(press("minimap") == "TOGGLEWORLDMAP")
    assert(#Stub.macroClicks == 0)
end)

-- iPad run 7 (questlist-box.png): a tap under the player card, where an empty quest list draws nothing, opened the map.
-- The yellow rounded box is the app's press glow round the "quest" area (TouchAreas.m AKTouchPressView); the key ran
-- TOGGLEQUESTLOG, which in this client opens the world map (Camelot has no separate quest log frame: its quest log is
-- the map's quest panel, Blizzard_WorldMap.lua:1397). Rule: an area whose content is empty or hidden does nothing.
-- The quest key is bound by a secure gate: only while the list has quests and no target hides it, in a fight too.
T("the_quest_key_does_nothing_while_the_list_is_empty_or_hidden", function()
    local Hud = setup()
    local key = ns.Contract.KeysFor("quest")
    local function press()
        local before = #Stub.commandsRun
        Stub.pressKey(key)
        assert(not ns.paused, ns.lastError)
        return Stub.commandsRun[#Stub.commandsRun] == "TOGGLEQUESTLOG" and #Stub.commandsRun > before
    end
    Stub.setQuests({}); Stub.applyDrivers()
    assert(not press(), "empty: nothing")
    Stub.setQuests({ quest(1, "Elixir of Pain") }); Stub.applyDrivers()
    assert(press(), "a quest: the quest log (in this client, the map's quest panel)")
    Stub.setTarget("enemy"); Stub.applyDrivers()
    assert(not press(), "hidden by a target: nothing")
    local _, holdKey = ns.Contract.KeysFor("quest")
    Stub.pressKey(holdKey)
    assert(not ns.InfoCard.IsShown(), "and a hold asks no card about a hidden list")
    -- in a fight the target comes and goes through the secure state driver
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    Stub.setTarget(nil); Stub.applyDrivers()
    assert(press(), "the target gone in a fight: the key works again")
    Stub.setTarget("enemy"); Stub.applyDrivers()
    assert(not press())
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); Stub.setTarget(nil); Stub.applyDrivers()
    -- Off: no key at all
    ns.SetEnabled(false); Stub.advance(1)
    assert(not press(), "Off: nothing")
    ns.SetEnabled(true); Stub.advance(1)
    assert(press())
end)

T("a_plain_tap_on_bags_opens_the_bags_even_with_no_game_backpack_button", function()
    local Hud = setup()
    _G.MainMenuBarBackpackButton = nil
    local before = Stub.calls.ToggleAllBags or 0
    Stub.click("TouchPlayBags", "LeftButton")
    assert((Stub.calls.ToggleAllBags or 0) == before + 1, "out of a fight the add-on calls the game's own toggle")
    assert(not ns.paused, ns.lastError)
    Stub.click("TouchPlayBags", "RightButton")
    assert((Stub.calls.ToggleAllBags or 0) == before + 1, "a right click does nothing")
end)

T("a_plain_tap_on_bags_opens_them_once_when_the_game_has_a_backpack_button", function()
    local Hud = setup()
    local before = Stub.calls.ToggleAllBags or 0
    Stub.click("TouchPlayBags", "LeftButton")
    assert((Stub.calls.ToggleAllBags or 0) == before + 1 and (Stub.gameClicks.MainMenuBarBackpackButton or 0) == 0,
        "out of a fight one toggle, no second click on the game's button")
end)

T("a_plain_tap_on_the_quest_list_opens_the_quest_log_once", function()
    local Hud = setup()
    Stub.setQuests({ quest(1, "Elixir of Pain", {}) }); Stub.fire("QUEST_WATCH_UPDATE", 1)
    local before = Stub.calls.ToggleQuestLog or 0
    Stub.click("TouchPlayQuest", "LeftButton")
    assert((Stub.calls.ToggleQuestLog or 0) == before + 1 and (Stub.gameClicks.QuestLogMicroButton or 0) == 0)
    Stub.combat(true)
    Stub.click("TouchPlayQuest", "LeftButton")
    assert((Stub.calls.ToggleQuestLog or 0) == before + 1 and Stub.gameClicks.QuestLogMicroButton == 1,
        "in a fight the secure click on the game's button does it")
end)

T("a_plain_tap_on_the_minimap_opens_the_map_once_or_falls_back", function()
    local Hud = setup()
    local before = Stub.calls.ToggleWorldMap or 0
    Stub.click("TouchPlayMinimap", "LeftButton")
    assert((Stub.calls.ToggleWorldMap or 0) == before + 1 and (Stub.calls.ToggleWorldMapFn or 0) == 0, "the zone text button")
    _G.MinimapCluster = {}   -- no zone text button in this client
    ns.Hud:Layout(); Stub.fire("PLAYER_REGEN_ENABLED")
    Stub.click("TouchPlayMinimap", "LeftButton")
    assert((Stub.calls.ToggleWorldMapFn or 0) == 1, "no zone text button: the add-on calls ToggleWorldMap itself")
end)

T("layout_waits_for_the_end_of_a_fight", function()
    local Hud = setup(); local before = Hud.bags.calls.SetPoint
    Stub.combat(true); ns.Hud:Layout()
    assert(Hud.bags.calls.SetPoint == before and not ns.paused)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Hud.bags.calls.SetPoint > before)
end)

T("every_touch_area_is_at_least_44", function()
    local Hud = setup()
    for _, f in ipairs({ Hud.quest, Hud.minimap, Hud.bags, Hud.menu, Hud.zoomIn, Hud.zoomOut, Hud.tracking }) do
        local w, h = f:GetHitRectSize()
        assert(w >= 44 and h >= 44, tostring(f.name) .. " " .. w .. "x" .. h)
    end
end)

T("restore_gives_the_game_its_frames_back", function()
    setup()
    local map = Stub.frames.Minimap
    ns.Pause("test")
    assert(map:GetParent() ~= ns.Hud.disc and not ns.Hud.IsMinimapInRing(), "a pause gives the minimap back")
    assert(Stub.frames.MirrorTimerContainer.mirrorTimers[1]:GetWidth() == 206)
end)

-- ---------------------------------------------------------------------------------------
-- Timers: one ticker, cancelled with the screen; callbacks run guarded and only while on

local function setupCounting()
    Stub.reset()
    local made = {}
    local NewTicker = C_Timer.NewTicker
    C_Timer.NewTicker = function(seconds, fn)
        local t = NewTicker(seconds, fn); made[#made + 1] = t; return t
    end
    Stub.loadAll(); Stub.login()
    local calls = { coords = 0 }
    local refresh = ns.Hud.RefreshCoords
    ns.Hud.RefreshCoords = function() calls.coords = calls.coords + 1; return refresh() end
    return ns.Hud, made, calls
end

T("one_ticker_runs_while_the_screen_is_on", function()
    local Hud, made, calls = setupCounting()
    assert(#made == 1 and Hud.HasTicker(), "the coordinate ticker, started by the layout")
    Stub.advance(1.1); Stub.advance(1.1); assert(calls.coords == 2)
    Stub.setAfk(true); Stub.advance(1.1)
    assert(#made == 1, "the away minutes ride the same ticker")
    Stub.advance(130); assert(Hud.afk.minutes:GetText():find("2 minutes", 1, true))
    ns.Each("Layout"); ns.Each("Layout"); assert(#made == 1, "a second layout starts no second ticker")
end)

T("ticker_stops_with_pause_off_and_restore", function()
    local Hud, made, calls = setupCounting()
    Stub.advance(1.1); local n = calls.coords; assert(n == 1)
    ns.Pause("test")
    assert(made[1].cancelled and not Hud.HasTicker(), "a pause cancels it")
    Stub.advance(5); Stub.advance(5); assert(calls.coords == n, "no tick after a pause")
    -- off, then on again: one new ticker, the old one stays dead
    Stub.reset(); local H2, made2, calls2 = setupCounting()
    ns.SetEnabled(false)
    assert(made2[1].cancelled and not H2.HasTicker())
    Stub.advance(5); Stub.advance(5); assert(calls2.coords == 0)
    ns.SetEnabled(true)
    assert(#made2 == 2 and H2.HasTicker() and not made2[2].cancelled)
    local before = calls2.coords
    Stub.advance(1.1); assert(calls2.coords == before + 1, "one tick")
    -- a plain Restore (Edit Mode)
    ns.Hud:Restore(); assert(made2[2].cancelled and not H2.HasTicker())
    -- in a fight the Restore waits; the ticker finds the add-on paused and stops itself
    local H3, made3, calls3 = setupCounting()
    Stub.combat(true); ns.Pause("fight")
    assert(not made3[1].cancelled)
    Stub.advance(1.1); assert(made3[1].cancelled and calls3.coords == 0)
end)

T("quest_timer_callbacks_are_guarded_and_only_run_while_on", function()
    local Hud = setup()
    local drawn = 0
    local refresh = Hud.RefreshQuests
    Hud.RefreshQuests = function() drawn = drawn + 1; return refresh() end
    -- a flash and a last-minute timer are pending
    Stub.setQuests({ quest(1, "Elixir of Pain", { timeTotal = 900, timeElapsed = 100,
        objectives = { { text = "a", finished = false } } }) })
    Stub.quests[1].objectives[1].finished = true; Stub.fire("QUEST_WATCH_UPDATE", 1)
    drawn = 0
    -- the add-on is paused before they fire: they draw nothing
    ns.Pause("test")
    Stub.advance(2.2); Stub.advance(900)
    assert(drawn == 0, "no redraw after a pause")
    -- while on, an error inside the redraw goes through the guard and pauses; it is not raised
    Stub.reset(); Stub.loadAll(); Stub.login(); Hud = ns.Hud
    Stub.setQuests({ quest(1, "Elixir of Pain", { objectives = { { text = "a", finished = false } } }) })
    Stub.quests[1].objectives[1].finished = true; Stub.fire("QUEST_WATCH_UPDATE", 1)
    Hud.RefreshQuests = function() error("boom") end
    local ok = pcall(Stub.advance, 2.2)
    assert(ok, "the timer does not raise")
    assert(ns.paused and tostring(ns.lastError):find("boom", 1, true), "the pause machinery saw it")
end)

-- The tracking choice is the game's own menu button: from our code, only out of a fight.
T("tracking_icon_does_nothing_in_a_fight", function()
    local Hud = setup()
    Stub.tracking = { { name = "Find Herbs", texture = "herbicon", active = true } }
    Stub.fire("MINIMAP_UPDATE_TRACKING")
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    Stub.click(Hud.tracking)
    assert(Stub.calls.TrackingMenu == 0 and not ns.paused, tostring(ns.lastError))
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    Stub.click(Hud.tracking); assert(Stub.calls.TrackingMenu == 1)
end)

Stub.done("hud")
