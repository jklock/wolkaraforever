-- Task 3: the contract: touch areas, their keys and the saved button list (rule 10).
dofile("tests/stub.lua")

local Contract

-- A game session with the add-on loaded (saved variables read) but no layout yet.
local function setup()
    Stub.reset(); Stub.load("Core.lua", "Text.lua", "Style.lua", "Contract.lua")
    Stub.fire("ADDON_LOADED", "TouchPlay")
    Contract = ns.Contract
end

local function Box(w, h, corner, x, y)
    local f = CreateFrame("Frame", nil, ns.root)
    f:SetSize(w, h); ns.Anchor(f, corner, x, y)
    return f
end

-- spell1 (88 x 88, BR) and jump (BR)
local function setupWithDemoAreas()
    setup()
    Contract.Area("spell1", Box(88, 88, "BR", 1224, 868), { anchor = "BR",
        tap = { click = "TouchPlaySpell1" }, hold = { click = "TouchPlaySpell1", button = "RightButton" } })
    Contract.Area("jump", Box(58, 58, "BR", 1089, 886), { anchor = "BR", press = { command = "JUMP" } })
    return Contract.Write()
end

-- All 26 areas, each with every action its name has a key for.
local function registerFullAreas()
    for _, name in ipairs(Contract.NAMES) do
        local tap, hold, press = Contract.KeysFor(name)
        local opts = { anchor = "TL" }
        if tap then opts.tap = { click = "TouchPlay" .. name } end
        if hold then opts.hold = { click = "TouchPlay" .. name, button = "RightButton" } end
        if press then opts.press = { command = name == "jump" and "JUMP" or "DISMOUNT" } end
        if name == "interact" then opts.tap = { command = "INTERACTTARGET" } end
        Contract.Area(name, Box(60, 60, "TL", 100, 100), opts)
    end
    return Contract.Write()
end

local function setupFullAreas()
    setup()
    return registerFullAreas()
end

T("rule10_pool_order_and_size", function()
    setup()
    assert(#Contract.POOL == 44 and Contract.POOL[1] == "ALT-CTRL-SHIFT-F1" and Contract.POOL[44] == "ALT-CTRL-SHIFT-Z")
end)

-- Ruling A22: the walk stick holds the plain W, A, S, D keys and the app sends keys by key code, so no
-- chord may end in one of those letters.
T("a22_pool_skips_walk_letters", function()
    setup()
    for i, key in ipairs(Contract.POOL) do assert(not key:match("%-[WASD]$"), "walk letter in the pool: " .. key) end
    local need = 1                                    -- the world key
    for _, name in ipairs(Contract.NAMES) do
        local t, h, p = Contract.KeysFor(name)
        if t then need = need + 1 end
        if h then need = need + 1 end
        if p then need = need + 1 end
    end
    assert(need == 42 and #Contract.POOL >= need, "the pool covers every key the areas need")
end)

T("rule10_pool_sequence", function()
    setup()
    local want = { "F1", "F2", "F12", "1", "9", "0", "B", "C", "E", "Z" }
    local at = { 1, 2, 12, 13, 21, 22, 23, 24, 25, 44 }
    for i, key in ipairs(want) do assert(Contract.POOL[at[i]] == "ALT-CTRL-SHIFT-" .. key, key) end
end)

T("rule10_contract_string_format", function()
    local s = setupWithDemoAreas()
    assert(s:match("^TPC1;hold=0%.45;hand=R;turn=1;world=ALT%-CTRL%-SHIFT%-F1;outline=spell1,jump;areas="), s)
    assert(s:find("spell1,BR,54,68,88,88,ALT%-CTRL%-SHIFT%-F2,ALT%-CTRL%-SHIFT%-F,|", 1, false))
    assert(s:find("jump,BR,%d+,%d+,%d+,%d+,,,ALT%-CTRL%-SHIFT%-V"))
    assert(not s:find('["\\\n]'))
    assert(TouchPlayDB.contract == s, "stored in the saved variables")
end)

T("rule10_fixed_keys_from_the_name_list", function()
    setup()
    local P = "ALT-CTRL-SHIFT-"
    local function keys(name) local t, h, p = Contract.KeysFor(name); return t, h, p end
    local t, h, p = keys("spell1"); assert(t == P .. "F2" and h == P .. "F" and p == nil)
    t, h, p = keys("spell7"); assert(t == P .. "F8" and h == P .. "L")
    t, h = keys("nexttarget"); assert(t == P .. "1" and h == nil)
    t, h = keys("item1"); assert(t == P .. "2" and h == P .. "M")   -- page1..4 and nexttarget sit between
    t, h = keys("quest"); assert(t == P .. "0" and h == P .. "T")
    t, h, p = keys("interact"); assert(t == P .. "E" and h == P .. "U" and p == nil)   -- A19: the aim-cancel hold
    t, h, p = keys("jump"); assert(t == nil and h == nil and p == P .. "V")
    t, h, p = keys("dive"); assert(t == nil and h == nil and p == P .. "X")
    t, h, p = keys("minimap"); assert(t == P .. "B" and h == nil)
    assert(keys("nosuch") == nil)
    -- 1 world + 24 tap + 15 hold + 2 press = 42 of the 44 keys, none twice
    local seen, n = { [Contract.POOL[1]] = true }, 1
    for _, name in ipairs(Contract.NAMES) do
        local all = { keys(name) }
        for i = 1, 3 do
            local k = all[i]
            if k then
                assert(not seen[k], k); seen[k] = true; n = n + 1
                assert(not k:match("%-[WASD]$"), "walk letter assigned: " .. k)
            end
        end
    end
    assert(#Contract.NAMES == 26 and n == 42)
end)

T("rule10_registration_order_never_moves_keys", function()
    setup()
    Contract.Area("item2", Box(48, 48, "TR", 1300, 366), { anchor = "TR", tap = { click = "TouchPlayItem2" } })
    local t = Contract.KeysFor("item2")
    local s = Contract.Write()
    assert(s:find("item2,TR,18,366,48,48," .. t .. ",,", 1, true), s)
    setup()
    Contract.Area("item1", Box(48, 48, "TR", 1300, 300), { anchor = "TR", tap = { click = "TouchPlayItem1" } })
    Contract.Area("item2", Box(48, 48, "TR", 1300, 366), { anchor = "TR", tap = { click = "TouchPlayItem2" } })
    assert(Contract.KeysFor("item2") == t)
end)

T("rule10_areas_written_in_name_list_order", function()
    setup()
    Contract.Area("jump", Box(58, 58, "BR", 1089, 886), { press = { command = "JUMP" } })
    Contract.Area("spell1", Box(88, 88, "BR", 1224, 868), { tap = { click = "A" } })
    local s = Contract.Write()
    assert(s:find("areas=spell1,[^|]*|jump,"))
end)

T("rule10_corner_geometry", function()
    setup()
    Contract.Area("bags", Box(60, 60, "TL", 24, 200), { anchor = "TL", tap = { click = "B" } })
    Contract.Area("menu", Box(60, 60, "TR", 1000, 10), { anchor = "TR", tap = { click = "M" } })
    Contract.Area("quest", Box(100, 50, "BL", 300, 900), { anchor = "BL", tap = { click = "Q" } })
    Contract.Area("chat", Box(80, 70, "BR", 1200, 800), { anchor = "BR", tap = { click = "C" } })
    local s = Contract.Write()
    assert(s:find("bags,TL,24,200,60,60,", 1, true))
    assert(s:find("menu,TR,306,10,60,60,", 1, true))
    assert(s:find("quest,BL,300,74,100,50,", 1, true))
    assert(s:find("chat,BR,86,154,80,70,", 1, true))
end)

T("rule10_small_areas_grow_to_44", function()
    setup()
    -- a 42 x 42 page box at (1156, 566) grows by one unit on every side
    Contract.Area("page1", Box(42, 42, "BR", 1156, 566), { anchor = "BR", tap = { click = "P" } })
    local s = Contract.Write()
    assert(s:find("page1,BR,167,415,44,44,", 1, true), s)
end)

T("rule10_numbers_are_integers", function()
    setup()
    Contract.Area("bags", Box(59.6, 60.4, "TL", 24.4, 200.5), { anchor = "TL", tap = { click = "B" } })
    local s = Contract.Write()
    assert(s:find("bags,TL,24,201,60,60,", 1, true), s)
    assert(not s:match("areas=(.*)$"):find("%."), "no decimals in the areas")
end)

T("rule10_feel_settings_in_header", function()
    setup()
    assert(Contract.FEEL_DEFAULTS.hold == 0.45 and Contract.FEEL_DEFAULTS.leftHanded == false
        and Contract.FEEL_DEFAULTS.turnWithView == true)
    TouchPlayDB.feel = { hold = 0.6, leftHanded = true, turnWithView = false }
    assert(Contract.Write():match("^TPC1;hold=0%.6;hand=L;turn=0;world="))
    TouchPlayDB.feel = { hold = 1 }
    assert(Contract.Write():match("^TPC1;hold=0%.8;hand=R;turn=1;"), "kept inside its range, as Touch settings does")
    TouchPlayDB.feel = { hold = 0.455 }
    assert(Contract.Write():match("^TPC1;hold=0%.46;") or Contract.Write():match("^TPC1;hold=0%.45;"))
    TouchPlayDB.feel = { hold = "slow", leftHanded = "yes", turnWithView = 3 }
    assert(Contract.Write():match("^TPC1;hold=0%.45;hand=R;turn=1;"), "wrong types fall back")
    TouchPlayDB.feel = nil
    assert(Contract.Write():match("^TPC1;hold=0%.45;hand=R;turn=1;"))
end)

T("rule10_area_checks_its_arguments", function()
    setup()
    local f = Box(60, 60, "TL", 0, 0)
    assert(not pcall(Contract.Area, "nosuch", f, { tap = { click = "X" } }))
    assert(not pcall(Contract.Area, "page1", f, { hold = { click = "X" } }), "page1 has no hold key")
    assert(not pcall(Contract.Area, "spell1", f, { press = { command = "JUMP" } }), "spell1 has no press key")
    assert(not pcall(Contract.Area, "jump", f, { tap = { command = "JUMP" } }), "jump has no tap key")
    -- an area whose frame was never placed cannot be written
    local bare = CreateFrame("Frame", nil, ns.root); bare:SetSize(60, 60)
    Contract.Area("bags", bare, { tap = { click = "B" } })
    assert(not pcall(Contract.Write))
end)

T("rule10_bindings_set", function()
    setupWithDemoAreas(); Contract.Apply()
    assert(Stub.bindings["ALT-CTRL-SHIFT-F2"].click == "TouchPlaySpell1")
    assert(Stub.bindings["ALT-CTRL-SHIFT-F"].button == "RightButton")
    assert(Stub.bindings["ALT-CTRL-SHIFT-F"].click == "TouchPlaySpell1")
    assert(Stub.bindings["ALT-CTRL-SHIFT-V"].command == "JUMP")
    assert(Stub.bindings["ALT-CTRL-SHIFT-F1"].click == "TouchPlayWorldHold", "world key")
end)

-- The game builds key chords in the fixed order ALT, CTRL, SHIFT, META (Blizzard_SharedXML KeyCommand.lua) and finds a
-- binding by that exact string, so a chord written in any other order is never found and falls back to the bare key.
local MODIFIER_RANK = { ALT = 1, CTRL = 2, SHIFT = 3, META = 4 }
local function canonical(key)
    local mods, rest = {}, key
    while true do
        local m, tail = rest:match("^(%a+)%-(.+)$")
        if not m or not MODIFIER_RANK[m] then break end
        mods[#mods + 1] = m
        rest = tail
    end
    table.sort(mods, function(a, b) return MODIFIER_RANK[a] < MODIFIER_RANK[b] end)
    mods[#mods + 1] = rest
    return table.concat(mods, "-")
end

T("keys_are_in_the_games_modifier_order", function()
    assert(canonical("CTRL-ALT-SHIFT-F2") == "ALT-CTRL-SHIFT-F2", "the canonicaliser reorders")
    assert(canonical("SHIFT-CTRL-ALT-META-F2") == "ALT-CTRL-SHIFT-META-F2")
    assert(canonical("F12") == "F12" and canonical("ALT-CTRL-SHIFT-F2") == "ALT-CTRL-SHIFT-F2")
    setupFullAreas(); Contract.Apply()
    for _, key in ipairs(Contract.POOL) do assert(key == canonical(key), "pool key out of order: " .. key) end
    assert(Contract.WORLD_KEY == canonical(Contract.WORLD_KEY))
    local bound = 0
    for key in pairs(Stub.bindings) do
        bound = bound + 1
        assert(key == canonical(key), "bound chord out of order: " .. key)
    end
    assert(bound > 20, "the full layout binds its keys")
    local text = ns.db.contract
    local world = text:match("world=([^;]+)")
    assert(world == canonical(world), world)
    local n = 0
    for key in text:gmatch("[%u%-]*SHIFT%-%w+") do
        n = n + 1
        assert(key == canonical(key), "contract key out of order: " .. key)
        assert(key:find("^ALT%-CTRL%-SHIFT%-"), key)
    end
    assert(n > 40, "the contract string carries its keys: " .. n)
    assert(not text:find("CTRL%-ALT"), "the old order is gone from the contract string")
end)

T("rule10_apply_replaces_old_bindings", function()
    setupWithDemoAreas(); Contract.Apply()
    Contract.Area("spell1", Box(88, 88, "BR", 1224, 868), { anchor = "BR", hold = { click = "TouchPlaySpell1" } })
    Contract.Apply()
    assert(Stub.bindings["ALT-CTRL-SHIFT-F2"] == nil, "tap binding gone")
    assert(Stub.bindings["ALT-CTRL-SHIFT-F"])
end)

T("world_hold_button_is_secure_and_hidden", function()
    setup()
    local b = Contract.WorldHold
    assert(b and b == _G.TouchPlayWorldHold and b:GetName() == "TouchPlayWorldHold")
    assert(Stub.inherits(b, "SecureActionButtonTemplate") and not b:IsShown())
    assert(b:GetAttribute("type") == nil, "no action until Task 6")
    assert(Contract.WORLD_KEY == "ALT-CTRL-SHIFT-F1")
end)

T("apply_in_combat_waits", function()
    setupWithDemoAreas(); Stub.combat(true); Contract.Apply()
    assert(next(Stub.bindings) == nil and not ns.paused)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); assert(Stub.bindings["ALT-CTRL-SHIFT-F2"])
    assert(not ns.paused)
end)

T("pause_clears_bindings_keeps_movement", function()
    setupFullAreas(); Contract.Apply(); ns.Pause("test")
    assert(Stub.bindings[Contract.KeysFor("spell1")] == nil)
    local _, _, jump = Contract.KeysFor("jump"); assert(Stub.bindings[jump].command == "JUMP")
    assert(Stub.bindings[(Contract.KeysFor("interact"))].command == "INTERACTTARGET")
    local _, _, dive = Contract.KeysFor("dive"); assert(Stub.bindings[dive].command == "DISMOUNT")
    assert(Stub.bindings[Contract.WORLD_KEY] == nil)
    local n = 0; for _ in pairs(Stub.bindings) do n = n + 1 end
    assert(n == 3, "only jump, dive and interact stay, got " .. n)
end)

T("pause_in_combat_clears_after_the_fight", function()
    setupFullAreas(); Contract.Apply(); Stub.combat(true); ns.Pause("test")
    assert(Stub.bindings[(Contract.KeysFor("spell1"))], "still bound during the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.bindings[(Contract.KeysFor("spell1"))] == nil)
    assert(Stub.bindings[(Contract.KeysFor("interact"))])
end)

T("switching_back_on_binds_again", function()
    setupFullAreas(); Contract.Apply(); ns.Pause("test")
    ns.paused = false; ns.Each("Layout")
    assert(Stub.bindings[(Contract.KeysFor("spell1"))], "layout binds every area again")
    assert(Stub.bindings[Contract.WORLD_KEY])
end)

T("off_clears_bindings_keeps_movement", function()
    setupFullAreas(); Contract.Apply(); ns.SetEnabled(false)
    assert(Stub.bindings[(Contract.KeysFor("spell1"))] == nil)
    assert(Stub.bindings[Contract.WORLD_KEY] == nil)
    local _, _, jump = Contract.KeysFor("jump"); assert(Stub.bindings[jump].command == "JUMP")
    assert(Stub.bindings[(Contract.KeysFor("interact"))].command == "INTERACTTARGET")
    local n = 0; for _ in pairs(Stub.bindings) do n = n + 1 end
    assert(n == 3, "got " .. n)
end)

T("off_in_combat_clears_after_the_fight", function()
    setupFullAreas(); Contract.Apply(); Stub.combat(true); ns.SetEnabled(false)
    assert(Stub.bindings[(Contract.KeysFor("spell1"))], "still bound during the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.bindings[(Contract.KeysFor("spell1"))] == nil)
    assert(Stub.bindings[(Contract.KeysFor("interact"))])
    assert(not ns.paused)
end)

T("on_again_rebinds", function()
    setupFullAreas(); Contract.Apply(); ns.SetEnabled(false); ns.SetEnabled(true)
    assert(Stub.bindings[(Contract.KeysFor("spell1"))], "layout binds every area again")
    assert(Stub.bindings[Contract.WORLD_KEY])
end)

T("keep_key_stays_bound_through_pause_and_off", function()
    setupFullAreas(); Contract.KeepKey("F12", { command = "OPENCHAT" }); Contract.Apply()
    assert(Stub.bindings["F12"].command == "OPENCHAT", "bound by Apply")
    assert(not Stub.bindings["F12"].click)
    ns.Pause("test")
    assert(Stub.bindings["F12"].command == "OPENCHAT", "kept in a pause")
    local n = 0; for _ in pairs(Stub.bindings) do n = n + 1 end
    assert(n == 4, "the three movement keys and F12, got " .. n)
    ns.paused = false; ns.Each("Layout")
    assert(Stub.bindings["F12"] and Stub.bindings[Contract.WORLD_KEY], "layout binds it with the rest")
    ns.SetEnabled(false)
    assert(Stub.bindings["F12"].command == "OPENCHAT", "kept when off")
end)

T("keep_key_waits_for_the_end_of_a_fight", function()
    setupFullAreas(); Contract.KeepKey("F12", { command = "OPENCHAT" })
    Stub.combat(true); Contract.Apply()
    assert(Stub.bindings["F12"] == nil and not ns.paused)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.bindings["F12"].command == "OPENCHAT")
end)

T("keep_key_checks_its_arguments", function()
    setup()
    assert(not pcall(Contract.KeepKey, nil, { command = "X" }))
    assert(not pcall(Contract.KeepKey, "F12", {}))
    assert(not pcall(Contract.KeepKey, "F12", "OPENCHAT"))
    assert(pcall(Contract.KeepKey, "F11", { click = "SomeButton" }))
    Contract.Apply(); assert(Stub.bindings["F11"].click == "SomeButton")
end)

T("changed_contract_offers_reload", function()
    setupWithDemoAreas(); TouchPlayDB.contract = "TPC1;old"; Contract.loadedAtLogin = "TPC1;old"
    Contract.Write(); assert(Contract.notice:IsShown())
end)

T("same_contract_needs_no_reload", function()
    setupWithDemoAreas()
    Contract.loadedAtLogin = Contract.Write()
    Contract.Write(); assert(not Contract.notice:IsShown())
end)

T("notice_hides_when_the_change_is_undone", function()
    setupWithDemoAreas()
    Contract.loadedAtLogin = Contract.Write()
    TouchPlayDB.feel = { leftHanded = true }
    Contract.Write(); assert(Contract.notice:IsShown())
    TouchPlayDB.feel = nil
    Contract.Write(); assert(not Contract.notice:IsShown())
end)

T("loaded_contract_is_remembered_at_load", function()
    setup()
    assert(Contract.loadedAtLogin == nil)
    Stub.reset(); TouchPlayDB = { contract = "TPC1;saved" }
    Stub.load("Core.lua", "Text.lua", "Style.lua", "Contract.lua"); Stub.fire("ADDON_LOADED", "TouchPlay")
    assert(ns.Contract.loadedAtLogin == "TPC1;saved")
end)

T("notice_text_and_reload_button", function()
    setupWithDemoAreas()
    assert(ns.L["contract.reload"] == "Touch buttons changed. Reload to give them to the app.")
    local found = false
    for _, line in ipairs(Contract.notice.lines) do
        if line.text == ns.L["contract.reload"] then found = true end
    end
    assert(found, "notice shows the sentence")
    local reload = Contract.reloadButton
    assert(Stub.inherits(reload, "SecureActionButtonTemplate"))
    assert(reload:GetAttribute("type") == "macro" and reload:GetAttribute("macrotext") == "/reload")
    assert(Stub.calls.ReloadUI == 0)
    Stub.click(reload); assert(Stub.calls.ReloadUI == 1)
end)

T("keys_stable_between_reloads", function()
    local a = setupFullAreas(); Stub.reload(); Contract = ns.Contract
    local b = registerFullAreas()
    assert(a == b)
    assert(Contract.loadedAtLogin == a and not Contract.notice:IsShown(), "same list: nothing to reload")
end)

T("touch_keys_list_prints_the_area_list", function()
    setupWithDemoAreas()
    SlashCmdList.TOUCHPLAY("keys list")
    assert(Stub.printed("spell1") == 1 and Stub.printed("jump") == 1 and Stub.printed("F2") >= 1)
end)

T("core_pause_does_not_need_contract", function()
    Stub.reset(); Stub.load("Core.lua"); Stub.fire("ADDON_LOADED", "TouchPlay")
    ns.Pause("test"); assert(ns.paused)
end)

-- ---------------------------------------------------------------------------------------
-- The app holds Ctrl, Option and Shift with every key (C1): the game then reads alt-ctrl-shift-type1, so every
-- left-click attribute is the "*" wildcard form, and the right click (a hold) has no action at all.

local function fullScreen()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, tostring(ns.lastError))
    Stub.addBagItem({ id = 4599, cat = "food", req = 1, count = 5 })
    Stub.addBagItem({ id = 1179, cat = "drink", req = 1, count = 5 })
    Stub.addBagItem({ id = 118, cat = "health", req = 1, count = 3 })
    Stub.addBagItem({ id = 5513, cat = "gem", req = 1, count = 1 })
    Stub.fire("BAG_UPDATE_DELAYED")
    Stub.setQuests({ { id = 11, title = "Wanted: Hogger", objectives = { { text = "Hogger slain: 0/1" } } } })
    Stub.setTarget("enemy")
    Stub.actions[1] = 133
    Stub.cvars.enableMouseoverCast = "1"
    Stub.setMouseover("Kobold Miner")
    return ns.Contract
end

local function taps(name)
    local tap = ns.Contract.KeysFor(name)
    return tap
end

T("every_key_works_with_ctrl_alt_shift_held", function()
    local C = fullScreen()
    local function press(key)
        assert(key and key:find("^ALT%-CTRL%-SHIFT%-"), tostring(key))
        Stub.secureActions = {}
        Stub.lastMacro, Stub.lastTargeted, Stub.lastItemUsed, Stub.lastUsedAction = nil, nil, nil, nil
        assert(Stub.pressKey(key), "nothing bound to " .. key)
        assert(not ns.paused, key .. ": " .. tostring(ns.lastError))
    end
    for i = 1, 7 do
        press(taps("spell" .. i))
        assert(Stub.lastUsedAction == ns.Cluster.Slot(1, i), "spell" .. i .. " used " .. tostring(Stub.lastUsedAction))
        assert(Stub.lastActionUnit ~= "player" and Stub.lastActionUnit ~= "focus" and Stub.lastActionUnit ~= "mouseover",
            "spell" .. i .. " went to " .. tostring(Stub.lastActionUnit))
    end
    for p = 1, 4 do
        press(taps("page" .. p))
        assert(tonumber(ns.Cluster.pager:GetAttribute("state-chosen")) == p, "page" .. p)
    end
    press(taps("page1"))
    press(taps("nexttarget")); assert(Stub.lastMacro == "/targetenemy", tostring(Stub.lastMacro))
    press(taps("item1")); assert(Stub.lastItemUsed == "item:4599", "item1: " .. tostring(Stub.lastItemUsed))
    press(taps("bags")); assert(Stub.commandsRun[#Stub.commandsRun] == "OPENALLBAGS", "bags: a binding command")
    press(taps("player")); assert(Stub.lastTargeted == "player", "player: " .. tostring(Stub.lastTargeted))
    press(taps("target")); assert(Stub.lastTargeted == "target", "target: " .. tostring(Stub.lastTargeted))
    Stub.setTarget(nil)
    press(taps("quest")); assert(Stub.commandsRun[#Stub.commandsRun] == "TOGGLEQUESTLOG", "quest: a binding command")
    press(taps("minimap")); assert(Stub.commandsRun[#Stub.commandsRun] == "TOGGLEWORLDMAP", "minimap: a binding command")
    press(taps("menu")); assert(ns.Menu.IsOpen(), "menu opens")
    ns.Menu.Close()
    press(taps("chat")); assert(Stub.commandsRun[#Stub.commandsRun] == "OPENCHAT")
    press(taps("interact")); assert(Stub.commandsRun[#Stub.commandsRun] == "INTERACTTARGET")
    local _, _, jump = C.KeysFor("jump")
    press(jump); assert(Stub.commandsRun[#Stub.commandsRun] == "JUMP")
    local _, _, dive = C.KeysFor("dive")
    -- on land with a mount the dive key is the Mount button (R50); in water it swims down
    press(dive); assert(Stub.lastMacro == ns.Interact.MountMacro(nil), "mount: " .. tostring(Stub.lastMacro))
    Stub.setSwimming(true); Stub.fire("MIRROR_TIMER_START")
    press(dive); assert(Stub.commandsRun[#Stub.commandsRun] == "SITORSTAND")
    press(C.WORLD_KEY)
    assert(#Stub.secureActions == 0, "the world key acts on nothing")
end)

T("every_hold_key_opens_a_card_and_never_acts", function()
    local C = fullScreen()
    for _, name in ipairs(C.NAMES) do
        local _, hold = C.KeysFor(name)
        -- Interact's hold is the hidden stop button (A19), not a card: its own test is in test_interact
        if hold and Stub.bindings[hold] and name ~= "interact" then
            ns.InfoCard.Hide()
            Stub.secureActions, Stub.lastMacro, Stub.lastTargeted, Stub.lastItemUsed = {}, nil, nil, nil
            local used = Stub.calls.UseAction
            Stub.pressKey(hold)
            assert(not ns.paused, name .. ": " .. tostring(ns.lastError))
            assert(#Stub.secureActions == 0 and Stub.calls.UseAction == used, name .. ": a hold never acts")
            assert(ns.InfoCard.IsShown(), name .. ": a hold opens the card")
        end
    end
end)

T("no_cluster_spell_is_self_or_focus_cast", function()
    fullScreen()
    for i, b in ipairs(ns.Cluster.buttons) do
        assert(Stub.modifiedAttribute(b, "checkselfcast", "LeftButton") == nil, "spell" .. i .. " self cast")
        assert(Stub.modifiedAttribute(b, "checkfocuscast", "LeftButton") == nil, "spell" .. i .. " focus cast")
        assert(Stub.modifiedAttribute(b, "checkmouseovercast", "LeftButton") == nil, "spell" .. i .. " mouseover cast")
        assert(b:GetAttribute("type2") == nil and b:GetAttribute("*type2") == nil and b:GetAttribute("type") == nil)
    end
end)

-- The contract's hold is the one Touch settings uses: kept inside its range (Contract.GetFeel).
T("contract_hold_is_the_clamped_setting", function()
    setup()
    ns.db.feel = { hold = 5 }
    assert(Contract.Write():find(";hold=0.8;", 1, true), "held inside 0.3 to 0.8")
    ns.db.feel = { hold = 0.1 }
    assert(Contract.Write():find(";hold=0.3;", 1, true))
end)

-- The reload notice sits clear of the target card (360..708 x 8..158), the quest list and every touch area, either hand.
T("reload_notice_is_clear_of_the_cards_and_the_quest_list", function()
    for _, left in ipairs({ false, true }) do
        Stub.reset(); Stub.loadAll(); Stub.login()
        if left then ns.Feel.Set("leftHanded", true); Stub.advance(1) end
        local n = ns.Contract.notice
        n:Show()
        local a = n.touchAnchor
        assert(a.y >= 160, "below the cards: " .. a.y)
        local function clear(name, f)
            local b = f.touchAnchor
            local x, y, w, h = ns.TapRect(b.x, b.y, b.w, b.h)
            assert(not (a.x < x + w and x < a.x + a.w and a.y < y + h and y < a.y + a.h),
                (left and "left-handed " or "") .. "the notice covers " .. name)
        end
        clear("the target card", ns.Units.target); clear("the player card", ns.Units.player)
        clear("the quest list", ns.Hud.quest); clear("Bags", ns.Hud.bags); clear("Menu", ns.Hud.menu)
        clear("the minimap", ns.Hud.minimap)
        for i, b in ipairs(ns.ItemRail.buttons) do clear("item" .. i, b) end
    end
end)

-- R47: SecureActionButton_OnClick from an add-on's button acts on the down click while ActionButtonUseKeyDown is on
-- (the default), and our buttons hear up clicks only: every one says useOnKeyDown = false, so a tap acts on lift.
T("every_secure_action_button_acts_on_the_up_click", function()
    fullScreen()
    assert(Stub.cvars.ActionButtonUseKeyDown == nil or Stub.cvars.ActionButtonUseKeyDown ~= "0", "the default: on")
    local n = 0
    for _, f in ipairs(Stub.allFrames()) do
        local name = f:GetName()
        if Stub.inherits(f, "SecureActionButtonTemplate") and name and name:find("^TouchPlay") then
            n = n + 1
            assert(f:GetAttribute("useOnKeyDown") == false, name .. " acts on the down click it never hears")
        end
    end
    assert(n >= 25, "the add-on's secure buttons: " .. n)
    -- the cluster is the game's own action button: it passes isSecureAction and acts on the up click by itself
    local used = Stub.calls.UseAction
    Stub.click(ns.Cluster.buttons[1], "LeftButton", false)
    assert(Stub.calls.UseAction == used + 1, "the cluster acts on the up click")
end)

-- R47: the cards are secure action buttons (a unit button's click goes through the click bindings, which do not bind
-- a Ctrl+Alt+Shift click, so it would do nothing).
T("the_cards_target_with_ctrl_alt_shift_held", function()
    fullScreen()
    for _, card in ipairs({ ns.Units.player, ns.Units.target }) do
        assert(Stub.inherits(card, "SecureActionButtonTemplate") and not Stub.inherits(card, "SecureUnitButtonTemplate"))
        assert(card:GetAttribute("*type1") == "target" and card:GetAttribute("useOnKeyDown") == false)
    end
end)

-- The press outline (app 7f94abf): the header field `outline=<area>,...` lists the areas that always draw something;
-- the app outlines only those. The list comes from a flag every area name must carry (Contract.DRAWN), not a typed string.
local ALWAYS_DRAWN = {
    "spell1", "spell2", "spell3", "spell4", "spell5", "spell6", "spell7", "page1", "page2", "page3", "page4",
    "nexttarget", "item1", "item2", "item3", "item4", "bags", "menu", "player", "minimap", "chat", "interact",
    "jump", "dive",
}
local SOMETIMES_EMPTY = { "target", "quest", "petcard", "leave", "petfeed" }
for i = 1, 10 do SOMETIMES_EMPTY[#SOMETIMES_EMPTY + 1] = "pet" .. i; SOMETIMES_EMPTY[#SOMETIMES_EMPTY + 1] = "stance" .. i end

-- every real area, each with every action its name has a key for (the 26 v1 names and the 24 class-bar names)
local function registerEveryArea()
    for _, name in ipairs(Contract.ALL_NAMES) do
        local tap, hold, press = Contract.KeysFor(name)
        local opts = { anchor = "TL" }
        if tap then opts.tap = { click = "TouchPlay" .. name } end
        if hold then opts.hold = { click = "TouchPlay" .. name, button = "RightButton" } end
        if press then opts.press = { command = "JUMP" } end
        if name:match("^stance") then Contract.Drop(name) else Contract.Area(name, Box(60, 60, "TL", 100, 100), opts) end
    end
end

local function outlineList(text)
    local field = text:match("^TPC1;[^|]-;outline=([^;]*);")
    assert(field, "no outline field: " .. text)
    local list = {}
    for name in field:gmatch("[^,]+") do list[#list + 1] = name end
    return list, field
end

T("outline_field_sits_after_world_and_before_areas", function()
    local s = setupWithDemoAreas()
    assert(s:match("world=[^;]+;outline=[^;]*;areas="), s)
    assert(select(2, s:gsub(";", ";")) == 6, "one more header field, areas still last: " .. s)
end)

T("outline_lists_exactly_the_always_drawn_areas", function()
    setup()
    registerEveryArea()
    local list = outlineList(Contract.Write())
    local want = {}
    for _, name in ipairs(ALWAYS_DRAWN) do want[name] = true end
    local got = {}
    for _, name in ipairs(list) do assert(not got[name], "listed twice: " .. name); got[name] = true end
    for name in pairs(want) do assert(got[name], "missing from outline: " .. name) end
    for name in pairs(got) do assert(want[name], "must not be outlined: " .. name) end
    assert(#list == 24)
end)

T("outline_names_are_real_areas_in_contract_order", function()
    setup()
    registerEveryArea()
    local list = outlineList(Contract.Write())
    local index = {}
    for i, name in ipairs(Contract.ALL_NAMES) do index[name] = i end
    local last = 0
    for _, name in ipairs(list) do
        assert(index[name], "not an area: " .. name)
        assert(index[name] > last, "out of contract order: " .. name); last = index[name]
    end
end)

T("outline_leaves_out_the_conditional_areas", function()
    setup()
    registerEveryArea()
    local text = Contract.Write()
    local _, field = outlineList(text)
    local listed = {}
    for name in field:gmatch("[^,]+") do listed[name] = true end
    for _, name in ipairs(SOMETIMES_EMPTY) do
        assert(not listed[name], "conditional area outlined: " .. name)
        assert(Contract.DRAWN[name] == false, name .. " must be flagged not-always-drawn")
    end
    assert(not field:find("quest") and not field:find("^target") and not field:find(",target") and not field:find("pet")
        and not field:find("stance"))
    -- the unlisted areas are still in the contract: they take the finger and send keys
    assert(text:find("|quest,", 1, true) and text:find("|target,", 1, true) and text:find("|leave,", 1, true))
end)

T("outline_only_names_areas_the_contract_has", function()
    local s = setupWithDemoAreas()
    local list = outlineList(s)
    assert(#list == 2 and list[1] == "spell1" and list[2] == "jump", s)
    setup()
    Contract.Area("quest", Box(100, 50, "BL", 300, 900), { anchor = "BL", tap = { click = "Q" } })
    local _, field = outlineList(Contract.Write())
    assert(field == "", "an empty list means no area is outlined: [" .. field .. "]")
    assert(Contract.Write():find("outline=;areas=quest,", 1, true))
end)

T("every_area_name_chooses_whether_it_is_always_drawn", function()
    setup()
    for _, name in ipairs(Contract.ALL_NAMES) do
        assert(type(Contract.DRAWN[name]) == "boolean", "area " .. name .. " has no always-drawn flag")
    end
    for name in pairs(Contract.DRAWN) do
        local real = false
        for _, n in ipairs(Contract.ALL_NAMES) do if n == name then real = true end end
        assert(real, "a flag for a name that is not an area: " .. name)
    end
end)

T("outline_does_not_break_the_parser_view_of_the_areas", function()
    setup()
    registerEveryArea()
    local text = Contract.Write()
    -- an older app splits on ';' and reads the fields it knows (hold, hand, turn, world, areas): the new one is ignored
    local fields = {}
    for part in text:gmatch("[^;]+") do
        local k, v = part:match("^(%w+)=(.*)$")
        if k then fields[k] = v end
    end
    assert(fields.hold == "0.45" and fields.hand == "R" and fields.turn == "1" and fields.world == Contract.WORLD_KEY)
    assert(fields.areas and fields.areas:match("^spell1,TL,") and not fields.areas:find("outline"))
    assert(text:match("^TPC1;"))
end)

Stub.done("contract")
