-- Task 4: the spell cluster: seven secure buttons, four pages, forms and vehicles page themselves
-- (rules 3 and 5).
dofile("tests/stub.lua")

local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

-- A game session with the add-on loaded and laid out.
local function setup()
    Stub.reset(); Stub.load("Core.lua", "Text.lua", "Style.lua", "Cluster.lua", "Contract.lua")
    Stub.login()
    return ns.Cluster
end

T("rule3_seven_buttons_four_pages", function()
    local C = setup(); assert(#C.buttons == 7)
    assert(C.Slot(1, 1) == 1 and C.Slot(2, 1) == 13 and C.Slot(3, 7) == 31 and C.Slot(4, 7) == 43)
    for i, b in ipairs(C.buttons) do
        assert(b:GetName() == "TouchPlaySpell" .. i and Stub.inherits(b, "ActionBarButtonTemplate"))
        assert(b:GetAttribute("action") == C.Slot(1, i))
        assert(b.clicks and b.clicks[1] == "AnyUp")
    end
end)

T("rule3_ring_geometry", function()
    local C = setup(); local x, y = Stub.centre(C.buttons[2]); assert(near(x, 1032) and near(y, 912))
    x, y = Stub.centre(C.buttons[7]); assert(near(x, 1293, 1) and near(y, 677, 1))
    x, y = Stub.centre(C.buttons[1]); assert(near(x, 1268) and near(y, 912))
    assert(C.buttons[1]:GetWidth() == 88 and C.buttons[2]:GetWidth() == 64)
    -- 79 units between neighbouring ring centres (19.2 degrees at radius 236)
    local x3, y3 = Stub.centre(C.buttons[3]); local x2, y2 = Stub.centre(C.buttons[2])
    assert(near(math.sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2), 79, 1.5))
end)

T("rule3_quickslot_frame_is_1_68_times_the_icon", function()
    local C = setup()
    for _, b in ipairs(C.buttons) do
        local nt = b:GetNormalTexture()
        local d = b:GetWidth(); local off = (math.floor(d * 1.68 + 0.5) - d) / 2
        local tl, br = nt.points[1], nt.points[2]
        assert(tl[1] == "TOPLEFT" and near(tl[4], -off) and near(tl[5], off))
        assert(br[1] == "BOTTOMRIGHT" and near(br[4], off) and near(br[5], -off))
    end
end)

-- iPad run 1: the template's icon had no anchors and came out about half the box.
T("rule3_icon_fills_the_box_inside_the_quickslot_frame", function()
    local C = setup()
    for i, b in ipairs(C.buttons) do
        local icon = b.icon
        assert(#icon.points == 1 and icon.points[1][1] == "ALL" and icon.points[1][2] == b, "icon " .. i .. " fills its button")
        assert(icon.texCoord[1] == 0.07 and icon.texCoord[2] == 0.93, "a thin crop, not the whole texture")
        assert(icon.removedMask == b.IconMask, "the round mask is off: the carved frame has square corners")
        assert(b:GetNormalTexture().texture == "Interface\\Buttons\\UI-Quickslot2", "the game's Quickslot frame")
        for _, part in ipairs({ b:GetPushedTexture(), b:GetHighlightTexture(), b:GetCheckedTexture(), b.Border, b.Flash,
            b.NewActionTexture, b.SpellHighlightTexture }) do
            assert(#part.points == 1 and part.points[1][1] == "ALL" and part.points[1][2] == b, "glow and push art follow the box")
        end
    end
    -- the primary 88 and the ring 64: the icon is the button's own size
    assert(C.buttons[1]:GetWidth() == 88 and C.buttons[2]:GetWidth() == 64)
    assert(not ns.paused, ns.lastError)
end)

T("rule3_form_page_switches_itself", function()
    local C = setup(); Stub.setBonusBar(1); Stub.applyDrivers()
    assert(C.buttons[1]:GetAttribute("action") == 73)
    assert(C.buttons[7]:GetAttribute("action") == 79)
    Stub.setBonusBar(0); Stub.applyDrivers()
    assert(C.buttons[1]:GetAttribute("action") == 1)
end)

T("rule3_each_bonus_bar_has_its_slots", function()
    local C = setup()
    for bar = 1, 4 do
        Stub.setBonusBar(bar); Stub.applyDrivers()
        assert(C.buttons[3]:GetAttribute("action") == (6 + bar - 1) * 12 + 3, bar)
    end
end)

T("rule3_page_box_reads_c_in_a_form", function()
    local C = setup()
    assert(C.pageBoxes[1].label:GetText() == "1")
    Stub.setBonusBar(1); Stub.applyDrivers()
    assert(C.pageBoxes[1].label:GetText() == "C" and C.pageBoxes[2].label:GetText() == "2")
    Stub.setBonusBar(0); Stub.applyDrivers()
    assert(C.pageBoxes[1].label:GetText() == "1")
end)

T("vehicle_page", function()
    local C = setup(); Stub.setVehicle(true); Stub.applyDrivers()
    assert(C.buttons[1]:GetAttribute("action") == (12 - 1) * 12 + 1)
end)

T("override_possess_and_temp_shapeshift_pages", function()
    local C = setup()
    Stub.setTempShapeshift(true); Stub.applyDrivers()
    assert(C.buttons[2]:GetAttribute("action") == (13 - 1) * 12 + 2)
    Stub.setTempShapeshift(false); Stub.setPossess(true); Stub.applyDrivers()
    assert(C.buttons[2]:GetAttribute("action") == (11 - 1) * 12 + 2)
    Stub.setPossess(false); Stub.setOverride(true); Stub.setVehicle(true); Stub.applyDrivers()
    assert(C.buttons[2]:GetAttribute("action") == (14 - 1) * 12 + 2, "override comes before vehicle")
end)

T("paging_state_driver_is_the_documented_one", function()
    local C = setup()
    assert(Stub.stateDrivers[C.pager].page == "[overridebar] override; [vehicleui] vehicle; [possessbar] possess; "
        .. "[shapeshift] tempshapeshift; [bonusbar:1] bonus1; [bonusbar:2] bonus2; [bonusbar:3] bonus3; "
        .. "[bonusbar:4] bonus4; page")
end)

T("page_boxes_choose_the_page_and_a_form_wins_then_gives_it_back", function()
    local C = setup()
    Stub.click("TouchPlayPage3")
    assert(C.buttons[1]:GetAttribute("action") == 25 and C.buttons[7]:GetAttribute("action") == 31)
    local gold, grey = C.pageBoxes[3].label.textColor, C.pageBoxes[1].label.textColor
    assert(gold[1] == 1 and near(gold[2], 0.82) and grey[1] < 0.7, "the chosen box reads gold")
    Stub.setBonusBar(2); Stub.applyDrivers(); assert(C.buttons[1]:GetAttribute("action") == 85)
    Stub.setBonusBar(0); Stub.applyDrivers(); assert(C.buttons[1]:GetAttribute("action") == 25, "the chosen page comes back")
end)

T("page_switch_in_combat_secure_only", function()
    local C = setup(); Stub.combat(true); Stub.click("TouchPlayPage2")
    assert(C.buttons[1]:GetAttribute("action") == 13 and not ns.paused)
    Stub.click("TouchPlayPage4"); assert(C.buttons[7]:GetAttribute("action") == 43 and not ns.paused)
    assert(Stub.calls.UseAction == 0, "a page box never casts")
end)

T("page_boxes_are_secure_attribute_clicks_44_units_to_tap", function()
    local C = setup()
    for p, box in ipairs(C.pageBoxes) do
        assert(box:GetName() == "TouchPlayPage" .. p and Stub.inherits(box, "SecureActionButtonTemplate"))
        assert(box:GetAttribute("type") == "attribute")
        assert(box:GetWidth() == 42 and box:GetHeight() == 42)
        local w, h = box:GetHitRectSize(); assert(w >= 44 and h >= 44)
        local x, y = Stub.centre(box); assert(near(x, 1156 + (p - 1) * 48 + 21) and near(y, 566 + 21))
    end
end)

T("rule5_positions_shared_spells_per_character", function()
    local C = setup(); assert(TouchPlayDB.layout and TouchPlayCharDB.layout == nil)
    assert(TouchPlayDB.layout.scale == 1)
end)

T("hold_never_casts", function()
    local C = setup(); Stub.click("TouchPlaySpell1", "RightButton")
    assert(Stub.calls.UseAction == 0)
    for _, b in ipairs(C.buttons) do assert(b:GetAttribute("type2") == nil and b:GetAttribute("type") == nil) end
    Stub.click("TouchPlaySpell1", "LeftButton")
    assert(Stub.calls.UseAction == 1 and Stub.lastUsedAction == 1, "a tap casts")
end)

T("hold_asks_the_info_card_for_the_current_slot", function()
    local C = setup(); local asked
    ns.InfoCard = { Show = function(what, button) asked = { what = what, button = button } end }
    Stub.setBonusBar(1); Stub.applyDrivers()
    Stub.click("TouchPlaySpell2", "RightButton")
    assert(asked and asked.what.kind == "action" and asked.what.slot == 74 and asked.button == C.buttons[2], "the card is told which frame was held")
    asked = nil; Stub.click("TouchPlaySpell2", "LeftButton"); assert(asked == nil, "a tap does not open the card")
end)

T("next_target_is_a_secure_macro_ring", function()
    local C = setup(); local nt = TouchPlayNextTarget
    assert(nt and Stub.inherits(nt, "SecureActionButtonTemplate"))
    assert(nt:GetAttribute("type") == "macro" and nt:GetAttribute("macrotext") == "/targetenemy")
    local x, y = Stub.centre(nt); assert(near(x, 1150 + 28) and near(y, 794 + 28))
    Stub.combat(true); Stub.click(nt); assert(Stub.lastMacro == "/targetenemy" and not ns.paused)
end)

T("areas_registered_with_the_contract", function()
    local C = setup()
    local text = ns.Contract.Write()
    for i = 1, 7 do assert(text:find("spell" .. i .. ",BR,", 1, true), "spell" .. i) end
    for p = 1, 4 do assert(text:find("page" .. p .. ",BR,", 1, true), "page" .. p) end
    assert(text:find("nexttarget,BR,", 1, true))
    -- spell1: BR, 54 from the right, 68 from the bottom, 88 square, tap F2-key, hold key present
    local tap, hold = ns.Contract.KeysFor("spell1")
    local want = ("spell1,BR,54,68,88,88,%s,%s,"):format(tap, hold)
    assert(text:find(want, 1, true), want)
    ns.Contract.Apply()
    local t = Stub.bindings[tap]; assert(t and t.click == "TouchPlaySpell1" and t.button == "LeftButton")
    local h = Stub.bindings[hold]; assert(h and h.click == "TouchPlaySpell1" and h.button == "RightButton")
end)

T("secret_values_never_touched", function()
    local C = setup(); Stub.secretCooldowns(true); Stub.fire("ACTIONBAR_UPDATE_COOLDOWN")
    assert(not ns.paused)
end)

T("a_page_change_never_writes_saved_positions", function()
    local C = setup(); Stub.click("TouchPlayPage2")
    assert(TouchPlayCharDB.layout == nil and TouchPlayDB.layout.scale == 1)
end)

-- Hot paths make no closure per hold or per page change (performance rule): the guarded work is a named function.
T("no_closure_per_hold_or_page", function()
    local f = assert(io.open("addon/TouchPlay/Cluster.lua")); local text = f:read("*a"); f:close()
    assert(not text:find('ns.Guard("cluster hold", function', 1, true), "the hold makes a closure")
    assert(not text:find('ns.Guard("cluster pages", function', 1, true), "each page change makes a closure")
end)

Stub.done("cluster")
