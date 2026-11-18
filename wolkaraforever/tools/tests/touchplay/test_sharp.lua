-- Ruling A39 (18 Nov): "Sharp screen". The app lets the game draw at the panel's own pixels (backing scale
-- 2.0: 2420 x 1668 on the iPad Pro 11 M5) and TouchPlay lowers the game's RenderScale so the 3D world keeps today's
-- ~908 px width, upscaled with FidelityFX: buttons and text sharp, the world as light as now. The app never writes
-- Config.wtf; this file owns the three CVars, keeps the player's originals, gives them back exactly on Off, pause and
-- Edit Mode, never fights a change the player makes and never sets a CVar in a fight.
dofile("tests/stub.lua")

local function setup(opts)
    Stub.reset(); Stub.loadAll()
    Stub.sharpScreen(opts)
    if opts and opts.before then opts.before() end
    Stub.login()
    Stub.fire("PLAYER_ENTERING_WORLD")
    assert(not ns.paused, tostring(ns.lastError))
    return ns.Sharp
end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function near(a, b) return math.abs((tonumber(a) or -1) - b) < 1e-6 end
-- /reload: the game keeps its CVars (the stub's reload starts a fresh game, so they are carried over here).
local function reload(width)
    local cvars, w, h = Stub.cvars, Stub.physicalW, Stub.physicalH
    local min, max, fsr = GetMinRenderScale, GetMaxRenderScale, RESAMPLE_QUALITY_FSR
    Stub.reload()
    Stub.cvars = cvars
    Stub.physicalW, Stub.physicalH = width or w, h
    GetPhysicalScreenSize = function() return Stub.physicalW, Stub.physicalH end
    GetMinRenderScale, GetMaxRenderScale, RESAMPLE_QUALITY_FSR = min, max, fsr
end
local function game()
    assert(Stub.cvars.RenderScale == "1", "RenderScale " .. tostring(Stub.cvars.RenderScale))
    assert(Stub.cvars.ResampleQuality == "1", "ResampleQuality " .. tostring(Stub.cvars.ResampleQuality))
    assert(Stub.cvars.ResampleSharpness == "0.5", "ResampleSharpness " .. tostring(Stub.cvars.ResampleSharpness))
end
local function sharp(scale)
    assert(near(Stub.cvars.RenderScale, scale or 0.375), "RenderScale " .. tostring(Stub.cvars.RenderScale))
    assert(Stub.cvars.ResampleQuality == "3", "FidelityFX upscales the world")
    assert(Stub.cvars.ResampleSharpness == ns.Sharp.SHARPNESS, "the touch sharpness")
end

-- ---------------------------------------------------------------------------------------
-- The scale: the 3D world stays ~908 px wide

T("sharp_scale_keeps_the_world_908_wide_per_physical_width", function()
    setup()
    local Scale = ns.Sharp.Scale
    assert(Scale(908) == nil, "the app still at 0.75: nothing changes")
    assert(Scale(907) == nil and Scale(1000) == nil, "at or under ~1000 px: RenderScale stays the game's")
    assert(near(Scale(1815), 0.5), "backing 1.5: " .. tostring(Scale(1815)))
    assert(near(Scale(2420), 0.375), "backing 2.0 on the 11-inch: " .. tostring(Scale(2420)))
    assert(near(Scale(2732), 0.332), "a 2732 px panel: " .. tostring(Scale(2732)))
    assert(near(Scale(1210), 0.75), "backing 1.0")
    assert(Scale(nil) == nil and Scale(0) == nil, "no size read: nothing")
end)

T("sharp_scale_clamps_to_the_game_min_and_rounds_to_its_step", function()
    setup()
    local Scale = ns.Sharp.Scale
    assert(near(Scale(2420, 0.5, 2.0), 0.5), "a floor above 0.375 holds (risk R1): " .. tostring(Scale(2420, 0.5, 2.0)))
    assert(near(Scale(2732, 0.5, 2.0), 0.5))
    -- the game's slider has 100 steps from min to max (Settings.CreateSliderOptions with no rate): 0.0175 for 0.25..2
    local s = Scale(2420, 0.25, 2.0)
    assert(near(s, 0.25 + 7 * 0.0175), "on the game's step: " .. tostring(s))
    assert(near(Scale(1815, 0.25, 2.0), 0.25 + 14 * 0.0175))
    assert(Scale(1000, 0.25, 2.0) == nil)
    assert(Scale(950, 0.5, 2.0) == nil, "never raised above the game's own 1")
end)

-- ---------------------------------------------------------------------------------------
-- On: the sharp values; the player's kept

T("sharp_on_at_native_sets_render_scale_fsr_and_sharpness_and_keeps_the_originals", function()
    setup()
    sharp(0.375)
    local held = TouchPlayDB.sharpHeld
    assert(held.RenderScale.was == "1" and near(held.RenderScale.ours, 0.375))
    assert(held.ResampleQuality.was == "1" and held.ResampleQuality.ours == "3")
    assert(held.ResampleSharpness.was == "0.5")
    assert(ns.Sharp.Held("RenderScale"))
    assert(ns.Feel.Get("sharpScreen") == true, "on by default")
end)

T("sharp_at_todays_size_changes_nothing", function()
    setup({ width = 908, height = 626 })
    game()
    assert(count(TouchPlayDB.sharpHeld) == 0, "nothing held")
end)

T("sharp_with_no_physical_size_changes_nothing", function()
    setup({ before = function() GetPhysicalScreenSize = nil end })
    game()
    assert(count(TouchPlayDB.sharpHeld) == 0)
end)

T("sharp_clamps_to_the_game_min", function()
    setup({ min = 0.5, max = 2.0 })
    sharp(0.5)
end)

T("sharp_a_floor_the_game_keeps_quietly_is_not_asked_again_and_again", function()
    setup({ before = function()
        local set = SetCVar
        SetCVar = function(name, value)          -- the game keeps 0.5 at least and does not say so in Lua (risk R1)
            if name == "RenderScale" then
                Stub.renderScaleSets = (Stub.renderScaleSets or 0) + 1
                if tonumber(value) < 0.5 then value = "0.5" end
            end
            return set(name, value)
        end
    end })
    assert(Stub.cvars.RenderScale == "0.5" and Stub.renderScaleSets == 1)
    assert(TouchPlayDB.sharpHeld.RenderScale.was == "1" and TouchPlayDB.sharpHeld.RenderScale.ours == "0.5")
    for _ = 1, 3 do Stub.fire("DISPLAY_SIZE_CHANGED"); ns.Each("Layout") end
    assert(Stub.renderScaleSets == 1, "asked " .. Stub.renderScaleSets .. " times")
    ns.SetEnabled(false)
    assert(Stub.cvars.RenderScale == "1", "given back")
    Stub.renderScaleSets = 0
    ns.SetEnabled(true)
    assert(Stub.cvars.RenderScale == "0.5" and Stub.renderScaleSets == 1, "asked again after a give-back")
    Stub.renderScaleSets = nil
end)

T("sharp_uses_bilinear_when_the_client_has_no_fsr", function()
    setup({ fsr = false })
    assert(near(Stub.cvars.RenderScale, 0.375))
    assert(Stub.cvars.ResampleQuality == "1", "Bilinear (already the game's: nothing held)")
    assert(Stub.cvars.ResampleSharpness == "0.5", "sharpening is FSR's: left alone")
    assert(TouchPlayDB.sharpHeld.ResampleSharpness == nil)
end)

T("sharp_skips_a_cvar_this_client_does_not_know", function()
    setup({ ResampleSharpness = false })
    assert(Stub.cvars.ResampleSharpness == nil, "never created")
    assert(near(Stub.cvars.RenderScale, 0.375) and Stub.cvars.ResampleQuality == "3")
end)

T("sharp_leaves_a_value_that_already_does_the_job", function()
    setup({ ResampleQuality = "3" })
    assert(Stub.cvars.ResampleQuality == "3" and TouchPlayDB.sharpHeld.ResampleQuality == nil)
end)

-- ---------------------------------------------------------------------------------------
-- Given back exactly: Off, the switch, pause, Edit Mode

T("sharp_off_gives_every_value_back_and_on_applies_again", function()
    setup()
    ns.SetEnabled(false)
    game()
    assert(count(TouchPlayDB.sharpHeld) == 0, "nothing held while off")
    ns.SetEnabled(true)
    sharp()
    assert(TouchPlayDB.sharpHeld.RenderScale.was == "1", "the player's value, not ours")
end)

T("sharp_switch_off_gives_back_and_on_applies", function()
    setup()
    ns.Feel.Set("sharpScreen", false)
    game()
    ns.Feel.Set("sharpScreen", true)
    sharp()
end)

T("sharp_pause_and_edit_mode_give_back", function()
    setup()
    ns.Pause("test")
    game()
    ns.SetEnabled(true)
    sharp()
    EventRegistry:TriggerEvent("EditMode.Enter")
    game()
    EventRegistry:TriggerEvent("EditMode.Exit")
    sharp()
end)

T("sharp_reload_keeps_the_originals_not_ours", function()
    setup()
    reload(); Stub.fire("PLAYER_LOGIN"); Stub.fire("PLAYER_ENTERING_WORLD")
    assert(not ns.paused, ns.lastError)
    sharp()
    assert(TouchPlayDB.sharpHeld.RenderScale.was == "1", "a reload never saves our own value as the player's")
    ns.SetEnabled(false)
    game()
end)

T("sharp_leftovers_go_back_when_logging_in_off", function()
    setup()
    TouchPlayDB.enabled = false
    reload(); Stub.fire("PLAYER_LOGIN"); Stub.fire("PLAYER_ENTERING_WORLD")
    game()
    assert(count(TouchPlayDB.sharpHeld) == 0)
end)

T("sharp_next_launch_back_at_today_size_gives_back", function()
    setup()
    reload(908); Stub.fire("PLAYER_LOGIN"); Stub.fire("PLAYER_ENTERING_WORLD")
    game()                                  -- else the world would draw at 340 x 235
    assert(count(TouchPlayDB.sharpHeld) == 0)
end)

T("sharp_next_launch_at_another_size_follows_it_keeping_the_original", function()
    setup()
    reload(1815); Stub.fire("PLAYER_LOGIN"); Stub.fire("PLAYER_ENTERING_WORLD")
    assert(near(Stub.cvars.RenderScale, 0.5), tostring(Stub.cvars.RenderScale))
    assert(TouchPlayDB.sharpHeld.RenderScale.was == "1" and near(TouchPlayDB.sharpHeld.RenderScale.ours, 0.5))
    ns.SetEnabled(false)
    game()
end)

T("sharp_display_size_change_re_evaluates", function()
    setup()
    Stub.physicalW = 1815
    Stub.fire("DISPLAY_SIZE_CHANGED")
    assert(near(Stub.cvars.RenderScale, 0.5))
    Stub.physicalW = 2420
    Stub.fire("UI_SCALE_CHANGED")
    assert(near(Stub.cvars.RenderScale, 0.375))
end)

-- ---------------------------------------------------------------------------------------
-- Never fight the player

T("sharp_a_change_the_player_makes_while_on_stands", function()
    setup()
    Stub.cvars.RenderScale = "0.5"          -- the player moves the game's Render Scale slider
    Stub.fire("DISPLAY_SIZE_CHANGED")
    assert(Stub.cvars.RenderScale == "0.5", "not lowered again")
    assert(TouchPlayCharDB.sharpDeclined.RenderScale == true)
    ns.SetEnabled(false)
    assert(Stub.cvars.RenderScale == "0.5", "Off does not undo the player's own choice")
    assert(Stub.cvars.ResampleQuality == "1", "the rest goes back")
    ns.SetEnabled(true)
    assert(Stub.cvars.RenderScale == "0.5", "and On does not apply it again for this character")
    assert(Stub.cvars.ResampleQuality == "3")
end)

T("sharp_a_change_the_player_makes_while_off_stands", function()
    setup()
    ns.SetEnabled(false)
    Stub.cvars.ResampleQuality = "2"        -- Bicubic, the player's own
    ns.SetEnabled(true)
    assert(Stub.cvars.ResampleQuality == "2")
    assert(near(Stub.cvars.RenderScale, 0.375), "the untouched ones come back")
end)

T("sharp_defaults_and_ticking_the_switch_apply_again", function()
    setup()
    Stub.cvars.RenderScale = "0.6"; ns.Sharp.Sync()
    assert(Stub.cvars.RenderScale == "0.6")
    Stub.click(ns.Feel.defaultsButton); Stub.advance(1)
    assert(near(Stub.cvars.RenderScale, 0.375), "Defaults is the player's yes to the sharp values again")
    ns.SetEnabled(false)
    assert(Stub.cvars.RenderScale == "0.6", "and Off gives back the player's last own value")
    ns.SetEnabled(true)
    Stub.cvars.ResampleQuality = "0"; ns.Sharp.Sync()
    assert(Stub.cvars.ResampleQuality == "0")
    ns.Feel.Set("sharpScreen", false); ns.Feel.Set("sharpScreen", true)
    assert(Stub.cvars.ResampleQuality == "3", "ticking the switch asks for it again")
end)

-- ---------------------------------------------------------------------------------------
-- Fights: no CVar changes under the lockdown

T("sharp_never_sets_a_cvar_in_a_fight", function()
    setup()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    ns.SetEnabled(false)
    ns.Feel.Set("sharpScreen", false)
    Stub.fire("DISPLAY_SIZE_CHANGED")
    assert(#Stub.cvarInCombat == 0, "changed in a fight: " .. table.concat(Stub.cvarInCombat, ","))
    sharp()
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    game()
end)

T("sharp_login_in_a_fight_waits", function()
    Stub.reset(); Stub.loadAll(); Stub.sharpScreen()
    Stub.combat(true)
    Stub.login(); Stub.fire("PLAYER_ENTERING_WORLD")
    assert(#Stub.cvarInCombat == 0)
    game()
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    sharp()
end)

-- ---------------------------------------------------------------------------------------
-- /touch sharp

T("sharp_status_prints_size_scale_quality_min_and_native", function()
    setup({ min = 0.25, max = 2.0 })
    SlashCmdList.TOUCHPLAY("sharp")
    assert(Stub.printed("2420x1668") >= 1, "the physical size")
    assert(Stub.printed("RenderScale") >= 1 and Stub.printed("ResampleQuality 3") >= 1)
    assert(Stub.printed("min 0.25") >= 1, "the game's floor")
    assert(Stub.printed("native") >= 1)
    assert(type(TouchPlayDB.sharpLog) == "table" and #TouchPlayDB.sharpLog >= 1, "kept for the Mac")
    assert(ns.db.enabled, "/touch sharp is not /touch")
    Stub.chat = {}
    setup({ width = 908, height = 626 })
    SlashCmdList.TOUCHPLAY("sharp")
    assert(Stub.printed("908x626") >= 1)
    assert(Stub.printed("not native") >= 1, "the app still draws at 0.75")
    assert(Stub.printed("unknown") >= 1, "no GetMinRenderScale in this client")
end)

-- ---------------------------------------------------------------------------------------
-- The game's windows keep their size (ruling A39b, 18 Nov: at Quality bags, map, character "appear smaller").
-- With "Use UI Scale" off the game sizes UIParent pixel for pixel (768 / the physical height): at 626 px tall a game
-- window covered 2.67 times the share of the screen it covers at 1668. While Sharp screen is on at a native size,
-- Touch turns Use UI Scale on at 768 / 626 (today's), within the game's slider (0.65 .. 1.15, Graphics.lua:931).

local function ui(opts)
    opts = opts or {}
    opts.ui = true
    return setup(opts)
end
-- A game window 500 units tall (Bagnon's bag, the map): its share of the screen height at 908 x 626 with the game's
-- own scale is 500 x (768 / 626) / 768 = 0.799.
local OLD_SHARE = 500 / 626
local function windowShare() return Stub.screenShare(500) end
local function uiGame(was)
    assert(Stub.cvars.useUiScale == "0", "useUiScale " .. tostring(Stub.cvars.useUiScale))
    assert(Stub.cvars.uiscale == (was or "1"), "uiscale " .. tostring(Stub.cvars.uiscale))
end
local function uiSharp()
    assert(Stub.cvars.useUiScale == "1", "Use UI Scale on: " .. tostring(Stub.cvars.useUiScale))
    assert(near(Stub.cvars.uiscale, 1.15), "the game's max: " .. tostring(Stub.cvars.uiscale))
end

T("sharp_ui_scale_per_physical_size", function()
    setup()
    local UiScale = ns.Sharp.UiScale
    assert(UiScale(908, 626) == nil, "the app still at 0.75: the game's windows are as they always were")
    assert(UiScale(1000, 690) == nil, "at or under ~1000 px wide: nothing")
    assert(UiScale(nil, nil) == nil and UiScale(2420, nil) == nil, "no size read: nothing")
    for _, size in ipairs({ { 1815, 1251 }, { 2420, 1668 }, { 2732, 2048 } }) do
        local s, wanted = UiScale(size[1], size[2])
        assert(near(s, 1.15), size[2] .. " px tall: the game's max " .. tostring(s))
        assert(math.abs(wanted - 768 / 626) < 1e-6, "today's scale is what is wanted: " .. tostring(wanted))
    end
    -- the game's max is what holds it back: a client allowing more gets today's scale on its 0.01 step
    assert(near(UiScale(2420, 1668, 0.65, 2.0), 1.23), tostring(UiScale(2420, 1668, 0.65, 2.0)))
    assert(near(UiScale(1815, 1251, 0.65, 1.2), 1.2))
end)

T("sharp_ui_scale_on_at_native_keeps_game_windows_their_old_size", function()
    ui()
    local before = 0.30                                    -- the game's own scale at 1668 would give 0.300
    uiSharp()
    local held = TouchPlayDB.sharpHeld
    assert(held.useUiScale.was == "0" and held.useUiScale.ours == "1")
    assert(held.uiscale.was == "1" and near(held.uiscale.ours, 1.15))
    local share = windowShare()
    assert(share > before * 2.4, "bigger than the shrunk 0.30: " .. share)
    assert(share / OLD_SHARE > 0.93 and share / OLD_SHARE <= 1.0, "within the game's max of the old size: "
        .. share / OLD_SHARE)
    Stub.fire("UI_SCALE_CHANGED"); Stub.fire("DISPLAY_SIZE_CHANGED")
    uiSharp()
    assert(TouchPlayDB.sharpHeld.uiscale.was == "1", "never takes its own value for the player's")
end)

T("sharp_ui_scale_at_todays_size_changes_nothing", function()
    ui({ width = 908, height = 626 })
    uiGame()
    assert(math.abs(windowShare() - OLD_SHARE) < 1e-6)
    assert(TouchPlayDB.sharpHeld.uiscale == nil and TouchPlayDB.sharpHeld.useUiScale == nil)
end)

T("sharp_ui_scale_given_back_exactly_on_off_switch_pause_edit_mode", function()
    ui({ uiscale = "0.9" })                           -- an old slider value the player left with Use UI Scale off
    uiSharp()
    ns.SetEnabled(false); uiGame("0.9")
    assert(math.abs(windowShare() - 500 / 1668) < 1e-6, "the game's own size again")
    ns.SetEnabled(true); uiSharp()
    ns.Feel.Set("sharpScreen", false); uiGame("0.9")
    ns.Feel.Set("sharpScreen", true); uiSharp()
    ns.Pause("test"); uiGame("0.9")
    ns.SetEnabled(true); uiSharp()
    EventRegistry:TriggerEvent("EditMode.Enter"); uiGame("0.9")
    EventRegistry:TriggerEvent("EditMode.Exit"); uiSharp()
    assert(TouchPlayDB.sharpHeld.uiscale.was == "0.9")
end)

T("sharp_ui_scale_leaves_a_player_who_uses_their_own", function()
    ui({ useUiScale = "1", uiscale = "0.8" })
    assert(Stub.cvars.useUiScale == "1" and Stub.cvars.uiscale == "0.8", "their own scale never followed the pixels")
    assert(TouchPlayDB.sharpHeld.uiscale == nil and TouchPlayDB.sharpHeld.useUiScale == nil)
    assert(near(Stub.cvars.RenderScale, 0.375), "the rest of Sharp screen still works")
    ns.SetEnabled(false)
    assert(Stub.cvars.useUiScale == "1" and Stub.cvars.uiscale == "0.8")
end)

T("sharp_ui_scale_the_players_slider_stands_with_use_ui_scale", function()
    ui()
    Stub.cvars.uiscale = "1"; Stub.uiScaleNow()   -- the player moves the game's UI Scale slider
    Stub.fire("UI_SCALE_CHANGED")
    assert(Stub.cvars.uiscale == "1" and Stub.cvars.useUiScale == "1", "theirs, with Use UI Scale on")
    assert(TouchPlayCharDB.sharpDeclined.uiscale == true)
    ns.SetEnabled(false)
    assert(Stub.cvars.uiscale == "1" and Stub.cvars.useUiScale == "1", "Off keeps the size they chose")
    assert(Stub.cvars.RenderScale == "1", "the rest goes back")
    ns.SetEnabled(true)
    assert(Stub.cvars.uiscale == "1" and Stub.cvars.useUiScale == "1")
    Stub.click(ns.Feel.defaultsButton); Stub.advance(1)
    uiSharp()
end)

T("sharp_ui_scale_use_ui_scale_turned_off_by_the_player_stands", function()
    ui()
    Stub.cvars.useUiScale = "0"; Stub.uiScaleNow()   -- the player unticks Use UI Scale
    ns.Sharp.Sync()
    assert(Stub.cvars.useUiScale == "0", "not ticked again")
    assert(Stub.cvars.uiscale == "1", "their slider value back in the same pass")
    assert(TouchPlayDB.sharpHeld.uiscale == nil and TouchPlayCharDB.sharpDeclined.useUiScale == true)
    ns.SetEnabled(false); ns.SetEnabled(true)
    assert(Stub.cvars.useUiScale == "0" and Stub.cvars.uiscale == "1", "stands for this character")
end)

T("sharp_ui_scale_waits_for_the_end_of_a_fight", function()
    ui()
    Stub.fire("PLAYER_REGEN_DISABLED"); Stub.combat(true)
    ns.SetEnabled(false)
    assert(#Stub.cvarInCombat == 0, "changed in a fight: " .. table.concat(Stub.cvarInCombat, ","))
    uiSharp()
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    uiGame()
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    ns.SetEnabled(true)
    assert(#Stub.cvarInCombat == 0)
    uiGame()
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    uiSharp()
end)

T("sharp_ui_scale_leaves_touchs_layout_contract_and_fonts_as_they_are", function()
    ui()
    ns.Feel.Set("sharpScreen", false); Stub.fire("UI_SCALE_CHANGED")
    uiGame()
    local contract = ns.Contract.Write()
    local rootScale = ns.root:GetEffectiveScale()
    local label = ns.Feel.rows.sharpScreen.label
    local _, size = label:GetFont()
    local fontPx = size * label:GetEffectiveScale()
    local rootW, rootH = ns.root:GetSize()
    ns.Feel.Set("sharpScreen", true); Stub.fire("UI_SCALE_CHANGED")
    uiSharp()
    assert(ns.Contract.Write() == contract, "the contract does not change")
    assert(math.abs(ns.root:GetEffectiveScale() - rootScale) < 1e-9, "Touch's layout is where it was")
    assert(math.abs(rootScale - 0.75) < 1e-9, "1024 layout units = the screen's 768 at any UI scale")
    local w, h = ns.root:GetSize()
    assert(math.abs(w - rootW) < 1e-6 and h == rootH, "the same 1024-tall layout space")
    local _, size2 = label:GetFont()
    assert(size2 == size and math.abs(size2 * label:GetEffectiveScale() - fontPx) < 1e-9, "Touch's text the same size")
end)

T("sharp_ui_scale_status_says_the_scale_and_the_max", function()
    ui()
    SlashCmdList.TOUCHPLAY("sharp")
    assert(Stub.printed("UI scale 1.15") >= 1, "the UI scale chosen")
    assert(Stub.printed("1.23") >= 1 and Stub.printed("max 1.15") >= 1, "today's would be 1.23: the game's max holds it")
    assert(Stub.printed("useUiScale 1") >= 1 and Stub.printed("uiscale 1.15") >= 1, "the two CVars, Touch's")
    Stub.chat = {}
    ui({ useUiScale = "1", uiscale = "0.8" })
    SlashCmdList.TOUCHPLAY("sharp")
    assert(Stub.printed("your own UI scale") >= 1)
end)

-- ---------------------------------------------------------------------------------------
-- Touch settings: the switch

T("sharp_settings_row_says_what_it_does_and_ticks", function()
    setup()
    local Feel = ns.Feel
    Feel.Open()
    local r = Feel.rows.sharpScreen
    assert(r and r.box, "a Sharp screen row")
    assert(r.label:GetText() == "Sharp screen")
    assert(r.note:GetText() == "Sharp buttons and text; the 3D world stays as light as now")
    assert(r.check:IsShown(), "ticked by default")
    Stub.click(r.box)
    assert(ns.db.feel.sharpScreen == false and not r.check:IsShown())
    game()
    Stub.click(r.box)
    sharp()
end)

Stub.done("sharp")
