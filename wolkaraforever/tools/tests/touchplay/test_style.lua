-- Task 2: the text table, the layout root and the shared kit.
dofile("tests/stub.lua")

local function setup(w, h)
    Stub.reset(); Stub.screen(w or 1366, h or 1024)
    Stub.load("Core.lua", "Text.lua", "Style.lua"); Stub.login()
end

T("root_is_1024_units_tall", function()
    setup(1194, 834)
    assert(math.abs(ns.root:GetHeight() * ns.root:GetScale() - 834) < 0.5)
end)

T("root_follows_a_screen_change", function()
    setup(1194, 834)
    Stub.screen(1366, 1024); Stub.fire("DISPLAY_SIZE_CHANGED")
    assert(math.abs(ns.root:GetScale() - 1) < 1e-6)
    Stub.screen(2388, 1668); Stub.fire("UI_SCALE_CHANGED")
    assert(math.abs(ns.root:GetHeight() * ns.root:GetScale() - 1668) < 0.5)
    assert(math.abs(ns.root:GetWidth() * ns.root:GetScale() - 2388) < 0.5)
end)

T("move_root_matches_root_and_survives_pause", function()
    setup(1194, 834)
    assert(ns.moveRoot and ns.moveRoot ~= ns.root)
    assert(ns.moveRoot:GetHeight() == ns.root:GetHeight() and ns.moveRoot:GetScale() == ns.root:GetScale())
    assert(ns.moveRoot:GetWidth() == ns.root:GetWidth())
    ns.Pause("test")
    assert(not ns.root:IsShown() and ns.moveRoot:IsShown(), "Pause hides only ns.root")
end)

T("anchor_right_bottom_offsets", function()
    setup()
    -- the primary spell button: top-left (1224, 868) size 88 -> right offset 54, bottom offset 68
    local f = CreateFrame("Frame", nil, ns.root); f:SetSize(88, 88); ns.Anchor(f, "BR", 1224, 868)
    local point, _, _, x, y = f:GetPoint(1); assert(point == "BOTTOMRIGHT" and x == -54 and y == 68)
end)

T("anchor_other_corners", function()
    setup()
    local f = CreateFrame("Frame", nil, ns.root); f:SetSize(100, 40)
    ns.Anchor(f, "TL", 24, 200)
    local p, rel, rp, x, y = f:GetPoint(1)
    assert(p == "TOPLEFT" and rp == "TOPLEFT" and rel == ns.root and x == 24 and y == -200)
    ns.Anchor(f, "TR", 1000, 10)
    p, _, _, x, y = f:GetPoint(1); assert(p == "TOPRIGHT" and x == -(1366 - 1100) and y == -10)
    ns.Anchor(f, "BL", 300, 900)
    p, _, _, x, y = f:GetPoint(1); assert(p == "BOTTOMLEFT" and x == 300 and y == 1024 - 940)
    assert(f:GetNumPoints() == 1, "an anchor replaces the old point")
    local ok = pcall(ns.Anchor, f, "MIDDLE", 0, 0); assert(not ok, "unknown corner is an error")
end)

T("anchor_in_move_root_uses_move_root", function()
    setup()
    local f = CreateFrame("Frame", nil, ns.moveRoot); f:SetSize(84, 84)
    ns.Anchor(f, "BL", 864, 750)
    local _, rel = f:GetPoint(1); assert(rel == ns.moveRoot)
end)

T("anchor_remembers_the_mockup_position", function()
    setup()
    local f = CreateFrame("Frame", nil, ns.root); f:SetSize(88, 88)
    ns.Anchor(f, "BR", 1224, 868)
    local a = f.touchAnchor
    assert(a.corner == "BR" and a.x == 1224 and a.y == 868 and a.w == 88 and a.h == 88)
    f:SetSize(64, 50); ns.Anchor(f, "TL", 10, 20)
    a = f.touchAnchor
    assert(a.corner == "TL" and a.x == 10 and a.y == 20 and a.w == 64 and a.h == 50)
end)

T("gold_header_fits_text", function()
    setup()
    local short, long = ns.Kit.GoldHeader(ns.root, "Bags"), ns.Kit.GoldHeader(ns.root, "Christoph Jeffcoat · Trade goods")
    assert(long:GetWidth() > short:GetWidth() and short:GetWidth() >= 200)
end)

T("gold_header_is_three_parts_from_the_game_art", function()
    setup()
    local h = ns.Kit.GoldHeader(ns.root, "Bags")
    assert(math.abs(h:GetHeight() - 47.5) < 0.6, "38 art pixels at scale 1.25")
    local parts = h.parts
    assert(parts.left.texture == "Interface\\DialogFrame\\UI-DialogBox-Gold-Header")
    assert(parts.left:GetWidth() == 20 and parts.right:GetWidth() == 20, "caps are 16 art pixels at 1.25")
    assert(math.abs(parts.middle:GetWidth() - (h:GetWidth() - 40)) < 1e-6)
    assert(h.label:GetText() == "Bags")
    h:SetLabel("Backpack"); assert(h.label:GetText() == "Backpack")
end)

T("backdrop_uses_the_game_art", function()
    setup()
    local g = ns.Kit.Backdrop(ns.root, "gold", "dark").backdrop
    assert(g.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Gold-Border" and g.edgeSize == 32)
    assert(g.bgFile == "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" and g.insets.left == 11)
    local s = ns.Kit.Backdrop(ns.root, "silver", "dark").backdrop
    assert(s.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border")
    local t = ns.Kit.Backdrop(ns.root, "tooltip", "tooltip").backdrop
    assert(t.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and t.edgeSize == 16 and t.insets.left == 4)
    assert(t.bgFile == "Interface\\Tooltips\\UI-Tooltip-Background")
    local p = ns.Kit.Backdrop(ns.root, "tooltip", "parchment").backdrop
    assert(p.bgFile == "Interface\\FontStyles\\FontStyleParchment")
    assert(not pcall(ns.Kit.Backdrop, ns.root, "wooden", "dark"))
end)

T("bar_passes_secret_values", function()
    setup()
    for _, kind in ipairs({ "health", "power", "cast", "xp", "timer" }) do
        local bar = ns.Kit.Bar(ns.root, kind); bar:Set(0, Stub.secret(), Stub.secret())
        assert(Stub.isSecret(bar.maxValue) and Stub.isSecret(bar.value), kind)
    end
    assert(not pcall(ns.Kit.Bar, ns.root, "nonsense"))
end)

T("bar_values_pass_straight_through", function()
    setup()
    local bar = ns.Kit.Bar(ns.root, "health"); bar:Set(0, 100, 37)
    assert(bar.minValue == 0 and bar.maxValue == 100 and bar.value == 37)
end)

T("missing_text_returns_key_once", function()
    setup()
    assert(ns.T("no.such.key") == "no.such.key"); ns.T("no.such.key")
    assert(#TouchPlayDB.missingText == 1)
    ns.T("another.key"); assert(#TouchPlayDB.missingText == 2)
end)

T("text_formats_with_arguments", function()
    setup()
    ns.L["test.count"] = "%d of %d"; ns.L["test.percent"] = "100% sure"
    assert(ns.T("test.count", 3, 10) == "3 of 10")
    assert(ns.T("test.percent") == "100% sure", "no arguments, no formatting")
    assert(ns.T("common.close") == "Close")
    assert(ns.T("test.count", "x") == "%d of %d", "a bad format falls back to the text")
end)

T("missing_text_before_saved_variables_does_not_fail", function()
    Stub.reset(); Stub.load("Core.lua", "Text.lua")
    assert(ns.T("early.key") == "early.key")
end)

T("touch_areas_never_below_44", function()
    setup()
    local b = ns.Kit.RedButton(ns.root, 30, 20, "x"); local w, h = b:GetHitRectSize()
    assert(w >= 44 and h >= 44)
    local big = ns.Kit.RedButton(ns.root, 200, 60, "x"); w, h = big:GetHitRectSize()
    assert(w == 200 and h == 60, "a big button keeps its own area")
    local ring = ns.Kit.RingButton(ns.root, 30, "Interface\\Icons\\INV_Misc_Bag_08", "Bags")
    w, h = ring:GetHitRectSize(); assert(w >= 44 and h >= 44)
    local chip = ns.Kit.Chip(ns.root, "Quests"); w, h = chip:GetHitRectSize(); assert(w >= 44 and h >= 44)
    local tabs = ns.Kit.Tabs(ns.root, { "Zone", "World" })
    for _, tab in ipairs(tabs.buttons) do w, h = tab:GetHitRectSize(); assert(w >= 44 and h >= 44) end
end)

T("fit_hit_recomputes_after_a_resize", function()
    setup()
    local b = ns.Kit.RedButton(ns.root, 30, 20, "x")
    b:SetSize(100, 20); ns.Kit.FitHit(b)
    local w, h = b:GetHitRectSize(); assert(w == 100 and h >= 44)
end)

T("red_button_art_and_states", function()
    setup()
    local b = ns.Kit.RedButton(ns.root, 200, 44, "Accept")
    assert(b:GetNormalTexture().texture == "Interface\\Buttons\\UI-Panel-Button-Up")
    assert(b:GetPushedTexture().texture == "Interface\\Buttons\\UI-Panel-Button-Down")
    local c = b:GetNormalTexture().texCoord
    assert(c[1] == 0 and c[2] == 0.625 and c[3] == 0 and c[4] == 0.6875)
    assert(b.label:GetText() == "Accept" and b:IsEnabled())
    local clicks = 0; b:SetScript("OnClick", function() clicks = clicks + 1 end)
    b:SetEnabledWithReason(false, "Not enough gold")
    assert(not b:IsEnabled() and b.reasonText:GetText() == "Not enough gold" and b.reasonText:IsShown())
    b:SetEnabledWithReason(true)
    assert(b:IsEnabled() and not b.reasonText:IsShown())
    b:SetBusy(true); assert(not b:IsEnabled())
    b:SetEnabledWithReason(true); assert(not b:IsEnabled(), "busy wins over enabled")
    b:SetBusy(false); assert(b:IsEnabled())
end)

T("red_button_tap_plays_the_tap_sound", function()
    setup()
    local b = ns.Kit.RedButton(ns.root, 200, 44, "Accept")
    Stub.click(b); assert(Stub.sounds[#Stub.sounds] == SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end)

T("sounds_use_soundkit_ids", function()
    setup()
    ns.Kit.Sound("tap"); ns.Kit.Sound("open"); ns.Kit.Sound("close"); ns.Kit.Sound("error")
    assert(Stub.sounds[1] == SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON and Stub.sounds[2] == SOUNDKIT.IG_MAINMENU_OPEN)
    assert(Stub.sounds[3] == SOUNDKIT.IG_MAINMENU_CLOSE and Stub.sounds[4] == SOUNDKIT.IG_QUEST_FAILED)
    ns.Kit.Sound("nonsense"); assert(#Stub.sounds == 4)
end)

T("ring_button_has_icon_and_label", function()
    setup()
    local r = ns.Kit.RingButton(ns.root, 60, "bag", "Bags")
    assert(r:GetWidth() == 60 and r:GetHeight() == 60)
    assert(r.icon.touchGlyph == "bag" and r.icon.texture == ns.Kit.ART_GLYPHS and r.label:GetText() == "Bags")
    -- a game texture (the tracked ability's icon) still shows, cropped as the game's icons are
    local t = ns.Kit.RingButton(ns.root, 46, "Interface\\Icons\\INV_Misc_Bag_08")
    assert(t.icon.texture == "Interface\\Icons\\INV_Misc_Bag_08" and t.icon.touchGlyph == nil)
    assert(t.icon.texCoord[1] == 0.08 and t.icon.texCoord[2] == 0.92)
end)

T("chip_shows_on_and_off", function()
    setup()
    local c = ns.Kit.Chip(ns.root, "Quests")
    assert(c:GetHeight() == 44 and c.on == false and not c.check:IsShown())
    c:SetOn(true); assert(c.on == true and c.check:IsShown())
    local gold = c.backdropBorderColor
    assert(gold[1] == 1 and math.abs(gold[2] - 0.82) < 1e-6)
    c:SetOn(false); assert(c.on == false and not c.check:IsShown())
end)

T("tabs_select_one_at_a_time", function()
    setup()
    local tabs = ns.Kit.Tabs(ns.root, { "Zone", "Continent", "World" })
    local seen = {}
    tabs:SetOnSelect(function(i) seen[#seen + 1] = i end)
    assert(#tabs.buttons == 3 and tabs:GetSelected() == 1)
    Stub.click(tabs.buttons[3]); assert(tabs:GetSelected() == 3 and seen[1] == 3)
    assert(tabs.buttons[3].selected and not tabs.buttons[1].selected)
    tabs:SetSelected(2); assert(tabs:GetSelected() == 2 and #seen == 1, "setting by code does not call back")
end)

T("card_lines_come_from_a_pool", function()
    setup()
    local card = ns.Kit.Card(ns.root)
    assert(card.backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border")
    card:SetTitle("Hillborne Cloak", 0.12, 1, 0)
    card:SetLines({ "Binds when equipped", "Back", "24 Armor" })
    assert(card.lineCount == 3 and card.lines[3]:IsShown() and card.lines[3]:GetText() == "24 Armor")
    local first = card.lines[1]
    card:SetLines({ "One" })
    assert(card.lines[1] == first and card.lineCount == 1 and not card.lines[2]:IsShown())
    assert(card.title:GetText() == "Hillborne Cloak")
    local before = #card.lines
    card:SetLines({ "a", "b", "c" }); assert(#card.lines == before, "no new font string for lines seen before")
end)

T("card_buttons_up_to_four_in_a_row", function()
    setup()
    local card = ns.Kit.Card(ns.root)
    local chosen
    card:SetLines({ "x" })
    card:SetButtons({ { label = "Equip", onClick = function() chosen = "equip" end },
        { label = "Link in chat" }, { label = "More" } })
    assert(card.buttonCount == 3 and card.buttons[3]:IsShown() and not card.buttons[4])
    Stub.click(card.buttons[1]); assert(chosen == "equip")
    local w = card:GetWidth()
    local bw = (w - 40 - 2 * 10) / 3
    assert(math.abs(card.buttons[1]:GetWidth() - bw) < 1e-6)
    assert(card.buttons[1]:GetHeight() == 44)
    card:SetButtons({ { label = "Close" } }); assert(card.buttonCount == 1 and not card.buttons[2]:IsShown())
    assert(not pcall(card.SetButtons, card, { {}, {}, {}, {}, {} }), "at most four buttons")
    local h1 = card:GetHeight(); card:SetButtons({}); assert(card:GetHeight() < h1, "no buttons, shorter card")
end)

T("card_grows_with_its_lines", function()
    setup()
    local card = ns.Kit.Card(ns.root); card:SetTitle("T"); card:SetLines({ "a" })
    local h1 = card:GetHeight(); card:SetLines({ "a", "b", "c", "d" })
    assert(card:GetHeight() > h1)
end)

T("frame_pool_hands_out_and_takes_back", function()
    setup()
    local pool = CreateFramePool("Frame", ns.root)
    local a, isNew = pool:Acquire(); assert(isNew)
    pool:Release(a); assert(not a:IsShown())
    local b, again = pool:Acquire(); assert(b == a and not again)
end)

-- A card's title may be a hidden value (the game's tooltip text in a fight): fitting never compares it.
T("card_fit_with_a_hidden_title", function()
    setup()
    local card = ns.Kit.Card(ns.root)
    card:SetTitle(Stub.secret())
    card:SetLines({ "Line one" })
    assert(card:GetHeight() >= 60)
end)

-- iPad run 5: other players' Cyrillic chat came out as boxes. Every TouchPlay text is drawn with a font family that
-- has the game's own file for each other alphabet; no font file is set on a string directly.
T("every_text_has_a_font_family_with_every_alphabet", function()
    Stub.reset()
    local made = {}
    local meta = Stub.Frame
    local create = meta.CreateFontString
    meta.CreateFontString = function(self, ...)
        local fs = create(self, ...)
        made[#made + 1] = fs
        return fs
    end
    Stub.loadAll(); Stub.login()
    Stub.fire("PLAYER_ENTERING_WORLD")
    meta.CreateFontString = create
    local checked = 0
    for _, fs in ipairs(made) do
        if fs.font ~= nil then              -- a string TouchPlay gave a font (the stub's own templates give none)
            checked = checked + 1
            local family = fs.fontObject
            assert(family and family.members, "a font family, not a bare file: " .. tostring(fs.font))
            local by = {}
            for _, m in ipairs(family.members) do by[m.alphabet] = m end
            assert(by.roman and by.roman.file == fs.font, "Latin uses TouchPlay's own face")
            for _, alphabet in ipairs({ "russian", "korean", "simplifiedchinese", "traditionalchinese" }) do
                assert(by[alphabet] and by[alphabet].file:find("^Fonts\\"), alphabet .. " has a game font file")
                assert(by[alphabet].height == by.roman.height and by[alphabet].flags == by.roman.flags)
            end
        end
    end
    assert(checked > 50, "the add-on's texts were seen: " .. checked)
    assert(ns.Kit.ALPHABETS[ns.Kit.FONT_TITLE].russian == "Fonts\\FRIZQT___CYR.TTF")
    -- no bare file anywhere in the add-on's code (the popup skin's give-back of the game's own fonts excepted)
    for _, file in ipairs({ "Chat", "Units", "Hud", "Loot", "InfoCard", "Interact", "Picker", "Menu", "Feel",
        "Guide", "Corpse", "Perf", "ItemRail", "Hold", "Cluster", "ClassBars" }) do
        local f = assert(io.open("addon/TouchPlay/" .. file .. ".lua")); local text = f:read("*a"); f:close()
        assert(not text:find(":SetFont%("), file .. ".lua sets a bare font file")
    end
    assert(not ns.paused, ns.lastError)
end)

T("font_falls_back_to_the_file_without_CreateFontFamily", function()
    Stub.reset()
    local saved = CreateFontFamily
    CreateFontFamily = nil
    Stub.load("Core.lua", "Text.lua", "Style.lua"); Stub.login()
    local fs = UIParent:CreateFontString()
    ns.Kit.SetFont(fs, ns.Kit.FONT_TITLE, 14, "")
    CreateFontFamily = saved
    assert(fs.font == ns.Kit.FONT_TITLE and fs.fontSize == 14 and fs.fontObject == nil)
end)

T("font_family_keeps_colour_and_justify", function()
    setup()
    local fs = UIParent:CreateFontString()
    fs:SetTextColor(1, 0.5, 0); fs:SetJustifyH("LEFT")
    ns.Kit.SetFont(fs, ns.Kit.FONT_NUMBER, 16, "OUTLINE")
    local r, g, b = fs:GetTextColor()
    assert(r == 1 and g == 0.5 and b == 0 and fs:GetJustifyH() == "LEFT")
    assert(fs.fontObject and fs.fontFlags == "OUTLINE" and fs.fontSize == 16)
    assert(ns.Kit.FontFamily(ns.Kit.FONT_NUMBER, 16, "OUTLINE") == fs.fontObject, "made once per face, size, flags")
end)

Stub.done("style")
