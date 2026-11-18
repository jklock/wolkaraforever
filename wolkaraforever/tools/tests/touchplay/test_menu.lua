-- Task 14: the Menu (mockup 30): 12 tiles with live sub-lines and a gold dot, game windows opened by
-- secure /click macros, Log out by a hold that only unlocks, the footer.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return ns.Menu
end

local function quest(id, title, extra)
    local q = { id = id, title = title, objectives = {} }
    for k, v in pairs(extra or {}) do q[k] = v end
    return q
end

local KEYS = { "character", "spellbook", "talents", "quests", "map", "bags", "professions", "social",
    "chat", "editLayout", "settings", "logout" }

T("menu_has_the_twelve_tiles_and_the_footer", function()
    local Menu = setup()
    assert(#Menu.KEYS == 12)
    for i, k in ipairs(KEYS) do assert(Menu.KEYS[i] == k, "tile " .. i .. " is " .. k) end
    Menu.Open()
    assert(Menu.panel:IsShown() and Menu.IsOpen())
    local a = Menu.panel.touchAnchor
    assert(a.x == 233 and a.y == 130 and a.w == 900 and a.h == 640, "gold panel 900 x 640 at (233, 130)")
    local names = { "Character", "Spellbook", "Talents", "Quests", "Map", "Bags", "Professions", "Social", "Chat",
        "Edit layout", "Settings", "Log out" }
    for i, k in ipairs(KEYS) do
        local t = Menu.tiles[k]
        assert(t and t.title:GetText() == names[i], k .. " " .. tostring(t and t.title:GetText()))
        local w, h = t:GetHitRectSize()
        assert(w >= 44 and h >= 44)
    end
    assert(Menu.guideButton.label:GetText() == "Touch guide")
    assert(Menu.saveButton.label:GetText() == "Save settings")
    assert(Menu.closeButton.label:GetText() == "Close")
end)

T("menu_title_has_name_level_and_class", function()
    local Menu = setup()
    Menu.Open()
    assert(Menu.title.label:GetText() == "Keepsy · Level 34 Mage", Menu.title.label:GetText())
    Stub.setUnit("player", { level = 35 }); Menu.Open()
    assert(Menu.title.label:GetText() == "Keepsy · Level 35 Mage", Menu.title.label:GetText())
end)

T("menu_tiles_secure_clicks", function()
    local Menu = setup()
    -- the windows open through the game's own micro buttons, by a secure /click macro. This client's micro
    -- buttons (ActionButtonUtilOverrides.lua): Spellbook and Talents are two tabs of PlayerSpellsMicroButton's
    -- window, Social is the Guild button (QuickJoinToastButton could not be confirmed to open Friends).
    local want = { character = "CharacterMicroButton", spellbook = "PlayerSpellsMicroButton",
        talents = "PlayerSpellsMicroButton", quests = "QuestLogMicroButton", professions = "ProfessionMicroButton",
        social = "GuildMicroButton", bags = "MainMenuBarBackpackButton" }
    for key, button in pairs(want) do
        local t = Menu.tiles[key]
        assert(Stub.inherits(t, "SecureActionButtonTemplate"), key .. " is a secure button")
        assert(t:GetAttribute("type") == "macro" and t:GetAttribute("macrotext") == "/click " .. button, key)
    end
    -- Map: the same secure click the Hud's minimap uses (the zone button's own ToggleWorldMap)
    local map = Menu.tiles.map
    assert(Stub.inherits(map, "SecureActionButtonTemplate") and map:GetAttribute("type") == "click")
    assert(map:GetAttribute("clickbutton") == MinimapCluster.ZoneTextButton)
    Menu.Open(); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    for key, button in pairs(want) do
        if not Menu.IsOpen() then Stub.click("TouchPlayMenu") end       -- in a fight only the secure ring opens it
        local before = Stub.gameClicks[button] or 0
        Stub.click(Menu.tiles[key])
        assert(Stub.gameClicks[button] == before + 1, key .. " clicked " .. button .. " in a fight")
        assert(not Menu.IsOpen(), "the Menu closes behind the window it opened")
    end
    Stub.click("TouchPlayMenu"); Stub.click(map)
    assert(Stub.calls.ToggleWorldMap == 1, "the map opens in a fight")
    assert(not Menu.IsOpen(), "and the Menu closes behind it")
    assert(#Stub.blocked == 0, "no insecure panel call was refused: " .. table.concat(Stub.blocked, ","))
    assert(Stub.calls.ShowUIPanel == 0, "no ShowUIPanel call")
    assert(not ns.paused, ns.lastError)
    -- not one protected attribute changes while a fight is on
    Menu.Open(); Menu.Refresh(); Menu.Close()
    assert(not ns.paused, ns.lastError)
end)

T("menu_every_tile_with_a_secure_path_is_never_greyed", function()
    local Menu = setup(); Menu.Open(); Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    for _, k in ipairs(KEYS) do
        assert(Menu.tiles[k].sub:GetText() ~= "After the fight", k .. " has a secure path")
        assert(Menu.tiles[k].face:GetAlpha() == 1, k)
    end
end)

-- A tile whose named button this game lacks falls back on the game's own Toggle, but a Toggle that shows a
-- panel is refused to add-on code in a fight (R32): the tile is greyed then and does nothing.
T("menu_fallback_tiles_are_greyed_in_a_fight_and_do_nothing", function()
    local Menu = setup()
    _G.GuildMicroButton = nil                       -- this game's button is gone: Social falls back
    Menu:Layout()                                   -- (the tiles read what the game has when laid out)
    Menu.Open()
    assert(Menu.tiles.social.sub:GetText() == "Friends, guild, who" and Menu.tiles.social.face:GetAlpha() == 1)
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    assert(Menu.tiles.social.sub:GetText() == "After the fight", Menu.tiles.social.sub:GetText())
    assert(Menu.tiles.social.face:GetAlpha() < 1, "greyed")
    assert(Menu.tiles.character.face:GetAlpha() == 1, "the others are not")
    Stub.click(Menu.tiles.social)
    assert(Stub.calls.ToggleFriendsFrame == 0 and #Stub.blocked == 0, "nothing was called")
    assert(Menu.IsOpen(), "and the Menu stays")
    assert(not ns.paused, ns.lastError)
    -- the fight ends: the tile wakes up and works
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Menu.tiles.social.sub:GetText() == "Friends, guild, who" and Menu.tiles.social.face:GetAlpha() == 1)
    Stub.click(Menu.tiles.social)
    assert(Stub.calls.ToggleFriendsFrame == 1 and not Menu.IsOpen())
end)

T("menu_every_fallback_works_out_of_a_fight", function()
    local Menu = setup()
    _G.CharacterMicroButton, _G.PlayerSpellsMicroButton, _G.QuestLogMicroButton = nil, nil, nil
    _G.ProfessionMicroButton, _G.GuildMicroButton, _G.MainMenuBarBackpackButton = nil, nil, nil
    MinimapCluster.ZoneTextButton = false        -- (a missing field would answer the stub's catch-all)
    local want = { character = "ToggleCharacter", spellbook = "ToggleSpellBook", talents = "ToggleTalents",
        quests = "ToggleQuestLog", map = "ToggleWorldMapFn", bags = "ToggleAllBags", social = "ToggleFriendsFrame" }
    for key, call in pairs(want) do
        Menu.Open(); Stub.click(Menu.tiles[key])
        assert(Stub.calls[call] == 1, key .. " -> " .. call .. " " .. tostring(Stub.calls[call]))
    end
    assert(not ns.paused, ns.lastError)
end)

T("menu_a_missing_blizzard_function_never_pauses_touchplay", function()
    local Menu = setup()
    _G.GuildMicroButton = nil; _G.QuestLogMicroButton = nil
    _G.ToggleFriendsFrame = nil                           -- the game has no such function
    Menu.Open(); Stub.click(Menu.tiles.social)
    assert(not ns.paused, ns.lastError)
    _G.ToggleQuestLog = function() error("the game changed") end     -- and one that raises
    Menu.Open(); Stub.click(Menu.tiles.quests)
    assert(not ns.paused and ns.lastError == nil, tostring(ns.lastError))
    assert(not Menu.IsOpen(), "the Menu still closes")
end)

-- ---------------------------------------------------------------------------------------
-- The live sub-lines and the dots

T("menu_sublines", function()
    local Menu = setup()
    Stub.zone = "Hillsbrad Foothills"
    Stub.professions = { { name = "Fishing", rank = 112 } }
    Stub.talentPoints, Stub.talentCount = true, 2
    Stub.freeBagSlots = 18
    Stub.setQuests({ quest(1, "A"), quest(2, "B", { complete = true }), quest(3, "C"), quest(4, "D"),
        quest(5, "E"), quest(6, "F") })
    Menu.Open()
    local sub = function(k) return Menu.tiles[k].sub:GetText() end
    assert(sub("character") == "Gear and stats")
    assert(sub("spellbook") == "All your spells")
    assert(sub("talents") == "2 points to spend", sub("talents"))
    assert(sub("quests") == "6 active · 1 ready", sub("quests"))
    assert(sub("map") == "Hillsbrad Foothills")
    assert(sub("bags") == "18 slots free", sub("bags"))
    assert(sub("professions") == "Fishing 112", sub("professions"))
    assert(sub("social") == "Friends, guild, who")
    assert(sub("editLayout") == "Move and resize")
    assert(sub("settings") == "Game and touch")
    assert(sub("logout") == "Hold to confirm")
    -- green for what waits, white for the rest
    local function green(k) local r, g, b = Menu.tiles[k].sub:GetTextColor(); return g > r and g > b end
    assert(green("talents") and green("quests") and not green("character") and not green("map"))
end)

T("menu_sublines_when_nothing_waits", function()
    local Menu = setup()
    Stub.setQuests({})
    Menu.Open()
    local sub = function(k) return Menu.tiles[k].sub:GetText() end
    assert(sub("talents") == "No points to spend", sub("talents"))
    assert(sub("quests") == "No active quests", sub("quests"))
    assert(sub("professions") == "None learned yet", sub("professions"))
    assert(sub("chat") == "Tap to talk", sub("chat"))
    Stub.setQuests({ quest(1, "A") }); Menu.Refresh()
    assert(sub("quests") == "1 active", sub("quests"))
    Stub.talentPoints, Stub.talentCount = true, 1; Menu.Refresh()
    assert(sub("talents") == "1 point to spend", sub("talents"))
    Stub.talentCount = 0; Menu.Refresh()
    assert(sub("talents") == "Points to spend", "points known to wait, count unknown")
end)

T("menu_dots", function()
    local Menu = setup()
    Stub.setQuests({}); Menu.Open()
    for _, k in ipairs(KEYS) do assert(not Menu.tiles[k].dot:IsShown(), k .. " has no dot") end
    -- a talent point: a dot on Talents
    Stub.talentPoints, Stub.talentCount = true, 2; Stub.fire("PLAYER_TALENT_UPDATE")
    assert(Menu.tiles.talents.dot:IsShown() and not Menu.tiles.quests.dot:IsShown())
    -- a quest ready to hand in: a dot on Quests
    Stub.setQuests({ quest(1, "Done", { complete = true }) })
    assert(Menu.tiles.quests.dot:IsShown())
    -- an unread whisper: a dot on Chat and the green line
    Stub.fire("CHAT_MSG_WHISPER", "thanks for the water", "Mira-Tarren Mill")
    assert(Menu.tiles.chat.dot:IsShown())
    assert(Menu.tiles.chat.sub:GetText() == "1 unread whisper", Menu.tiles.chat.sub:GetText())
    Stub.fire("CHAT_MSG_WHISPER", "hello?", "Mira-Tarren Mill")
    assert(Menu.tiles.chat.sub:GetText() == "2 unread whispers", Menu.tiles.chat.sub:GetText())
    assert(not Menu.tiles.map.dot:IsShown() and not Menu.tiles.bags.dot:IsShown())
    -- a reply takes the dot away
    Stub.fire("CHAT_MSG_WHISPER_INFORM", "ok", "Mira-Tarren Mill")
    assert(not Menu.tiles.chat.dot:IsShown())
    assert(Menu.tiles.chat.sub:GetText() == "Tap to talk")
    assert(not ns.paused, ns.lastError)
end)

T("menu_dots_never_compare_hidden_values", function()
    local Menu = setup()
    Menu.Open()
    Stub.fire("QUEST_LOG_UPDATE"); Stub.fire("BAG_UPDATE_DELAYED")
    Stub.combat(true); Stub.fire("ZONE_CHANGED"); Stub.fire("CHAT_MSG_WHISPER", Stub.secret(), Stub.secret())
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- Edit layout, Settings, the Chat tile, the footer

T("menu_edit_layout_says_later", function()
    local Menu = setup(); Menu.Open()
    Stub.click(Menu.tiles.editLayout)
    assert(Menu.tiles.editLayout.sub:GetText() == "Coming in a later version")
    assert(Menu.IsOpen(), "the Menu stays")
    Stub.advance(4)
    assert(Menu.tiles.editLayout.sub:GetText() == "Move and resize", "back to its own line")
end)

T("menu_settings_opens_touch_settings", function()
    local Menu = setup(); Menu.Open()
    Stub.click(Menu.tiles.settings)
    assert(not Menu.IsOpen() and ns.Feel.panel:IsShown())
    assert(ns.Feel.rows.gameSettings, "Touch settings has the Game settings row")
end)

T("menu_chat_tile_opens_the_chat", function()
    local Menu = setup(); Menu.Open()
    Stub.click(Menu.tiles.chat)
    assert(Stub.calls.OpenChat == 1 and not Menu.IsOpen())
end)

T("menu_footer", function()
    local Menu = setup(); Menu.Open()
    -- Save settings: a secure /reload
    assert(Stub.inherits(Menu.saveButton.secure, "SecureActionButtonTemplate"))
    assert(Menu.saveButton.secure:GetAttribute("macrotext") == "/reload")
    Stub.click(Menu.saveButton.secure); assert(Stub.calls.ReloadUI == 1)
    -- Close
    Stub.click(Menu.closeButton); assert(not Menu.IsOpen())
    -- Touch guide: closes the Menu and shows the guide again
    Menu.Open(); TouchPlayDB.guideDone = true
    Stub.click(Menu.guideButton)
    assert(not Menu.IsOpen() and ns.Guide.IsShown())
end)

T("menu_dim_behind_closes_it", function()
    local Menu = setup(); Menu.Open()
    assert(Menu.dim:IsShown())
    Stub.click(Menu.dim)
    assert(not Menu.IsOpen() and not Menu.dim:IsShown())
end)

-- The panel holds secure tiles, so the game protects it: in a fight it opens and closes only through the secure
-- ring, Close, Touch guide and the dim (R42). Ordinary code can neither open nor close it then, and never errors.
T("menu_opens_and_closes_in_a_fight", function()
    local Menu = setup(); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    assert(Menu.panel:IsProtected(), "the game protects the panel (it holds secure tiles)")
    Stub.click("TouchPlayMenu"); assert(Menu.IsOpen() and Menu.dim:IsShown() and not ns.paused, ns.lastError)
    assert(ns.Hold.For(Menu.tiles.logout).active, "the Log out hold is put back on the way in")
    Stub.tap(Menu.closeButton); assert(not Menu.IsOpen() and not Menu.dim:IsShown(), "Close closes it")
    Stub.click("TouchPlayMenu"); Stub.click("TouchPlayMenu"); assert(Menu.IsOpen(), "opening twice leaves it open")
    Stub.click(Menu.dim); assert(not Menu.IsOpen(), "the dim closes it")
    Stub.click("TouchPlayMenu")
    local shown = 0
    ns.Guide = { Show = function() shown = shown + 1 end }
    Stub.tap(Menu.guideButton); assert(not Menu.IsOpen() and shown == 1, "Touch guide closes it and shows the guide")
    Stub.click("TouchPlayMenu"); Menu.Close(); Menu.Open()
    assert(Menu.IsOpen() and not ns.paused, "ordinary code changes nothing in a fight, and never errors: " .. tostring(ns.lastError))
    Stub.click(Menu.tiles.settings)
    assert(not Menu.IsOpen() and ns.Feel.IsOpen(), "Settings closes the Menu and opens Touch settings in a fight")
    assert(not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- The Hud's Menu ring opens it (Ruling R18 ends: no ToggleGameMenu fallback)

T("hud_menu_ring_opens_our_menu", function()
    local Menu = setup()
    Stub.click("TouchPlayMenu", "LeftButton")
    assert(Menu.IsOpen() and Stub.calls.ToggleGameMenu == 0, "our Menu, never the game's")
    Menu.Close()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true); Stub.click("TouchPlayMenu", "LeftButton")
    assert(Menu.IsOpen() and Stub.calls.ToggleGameMenu == 0, "in a fight too")
    Stub.click(Menu.dim)
    Stub.click("TouchPlayMenu", "RightButton"); assert(not Menu.IsOpen())
    local f = assert(io.open("addon/TouchPlay/Hud.lua")); local text = f:read("*a"); f:close()
    assert(not text:find("elseif ToggleGameMenu", 1, true), "the temporary fallback is gone")
end)

-- ---------------------------------------------------------------------------------------
-- Log out: a hold that only unlocks (R28, R29)

local function logout(Menu) return Menu.tiles.logout end

T("logout_is_a_secure_logout_macro", function()
    local Menu = setup()
    local t = logout(Menu)
    assert(Stub.inherits(t, "SecureActionButtonTemplate") and t:GetAttribute("type") == "macro")
    assert(t:GetAttribute("macrotext") == "/logout")
end)

T("logout_needs_a_hold_then_one_more_tap", function()
    local Menu = setup(); Menu.Open()
    local t = logout(Menu)
    assert(Stub.coveredBy(t), "a hold frame covers the tile")
    -- a tap does nothing
    Stub.tap(t, 0.1)
    assert(Stub.calls.Logout == 0, "a quick tap never logs out")
    -- a hold of 0.8 s completes on release: it only unlocks
    Stub.tap(t, 0.9)
    assert(Stub.calls.Logout == 0, "the hold itself never logs out (R28)")
    local hold = ns.Hold.For(t)
    assert(hold.face:IsShown() and hold.face.label:GetText() == "Tap to confirm", "the face says so")
    assert(Stub.coveredBy(t) == nil, "the hold frame lets the next real tap through")
    Stub.tap(t)
    assert(Stub.calls.Logout == 1, "the next tap runs the secure /logout")
    assert(not ns.paused, ns.lastError)
end)

T("logout_unlock_expires_after_three_seconds", function()
    local Menu = setup(); Menu.Open()
    local t = logout(Menu)
    Stub.tap(t, 0.9)
    Stub.advance(3.1)
    assert(Stub.coveredBy(t), "locked again")
    Stub.tap(t); assert(Stub.calls.Logout == 0)
end)

T("logout_hold_timer_never_logs_out", function()
    local Menu = setup(); Menu.Open()
    local t = logout(Menu)
    local hit = Stub.coveredBy(t)
    hit:_Fire("OnMouseDown", "LeftButton")
    Stub.advance(5)      -- a finger that stays down forever
    assert(Stub.calls.Logout == 0, "the timer only marks it ready")
end)

T("logout_with_the_hold_off_is_a_plain_tap", function()
    local Menu = setup()
    ns.db.feel = { holdRisky = false }
    Menu.Open()
    local t = logout(Menu)
    assert(Stub.coveredBy(t) == nil, "no hold frame")
    Stub.tap(t)
    assert(Stub.calls.Logout == 1)
end)

T("logout_in_a_fight_unlocks_and_logs_out_from_the_secure_button", function()
    local Menu = setup(); Menu.Open(); Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    local t = logout(Menu)
    Stub.tap(t, 0.9); assert(Stub.calls.Logout == 0)
    Stub.tap(t); assert(Stub.calls.Logout == 1 and not ns.paused, ns.lastError)
end)

T("logout_locks_again_when_the_menu_opens", function()
    local Menu = setup(); Menu.Open()
    local t = logout(Menu)
    Stub.tap(t, 0.9)
    Menu.Close(); Menu.Open()
    assert(Stub.coveredBy(t), "a new visit starts locked")
end)

T("menu_restore_and_pause_close_it", function()
    local Menu = setup(); Menu.Open()
    ns.Pause("test")
    assert(not Menu.IsOpen(), "a pause closes the Menu")
end)

Stub.done("menu")
