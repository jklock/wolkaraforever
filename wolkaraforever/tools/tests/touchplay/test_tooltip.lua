-- iPad run 7: "tooltips cover the buttons being touched". While the touch screen is on, the game's default tooltip
-- place and the tooltips TouchPlay's own buttons open go to one spot away from both thumbs (top centre, under the
-- app's toolbar band); no game tooltip while the info card is open; Off gives the game its own place back.
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
    return GameTooltip
end

local function atSpot(tip)
    local point, rel, relPoint, x, y = tip:GetPoint(1)
    return tip:GetNumPoints() == 1 and point == "TOP" and rel == ns.root and relPoint == "TOPLEFT"
        and math.abs(x - 683 * ns.root:GetEffectiveScale() / tip:GetEffectiveScale()) < 1e-6
        and math.abs(y + 64 * ns.root:GetEffectiveScale() / tip:GetEffectiveScale()) < 1e-6
end

T("the_default_place_is_the_top_centre_spot", function()
    local tip = setup()
    GameTooltip_SetDefaultAnchor(tip, UIParent)          -- the world under the finger, a unit frame
    assert(atSpot(tip), "at the spot: " .. tostring(select(1, tip:GetPoint(1))))
    ns.SetEnabled(false)
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    assert(select(1, tip:GetPoint(1)) == "BOTTOMRIGHT", "Off: the game's own place")
    ns.SetEnabled(true)
    GameTooltip_SetDefaultAnchor(tip, UIParent); assert(atSpot(tip))
end)

T("our_buttons_tooltips_go_to_the_spot_others_keep_theirs", function()
    local tip = setup()
    local spell = ns.Cluster.buttons[1]
    tip:SetOwner(spell, "ANCHOR_RIGHT")                  -- ActionButton.lua:1114 with UberTooltips off
    assert(tip:GetOwner() == spell and tip.ownerAnchor == "ANCHOR_NONE" and atSpot(tip), tostring(tip.ownerAnchor))
    local pet = ns.ClassBars.pet[1]
    tip:SetOwner(pet, "ANCHOR_LEFT"); assert(tip.ownerAnchor == "ANCHOR_NONE" and atSpot(tip))
    local bag = CreateFrame("Button", "ContainerFrame1Item1", UIParent)
    tip:SetOwner(bag, "ANCHOR_RIGHT")
    assert(tip.ownerAnchor == "ANCHOR_RIGHT", "a game window's button keeps its own place")
    assert(not ns.paused, ns.lastError)
end)

T("no_game_tooltip_while_the_info_card_is_open", function()
    local tip = setup()
    tip:Show(); assert(tip:IsShown())
    ns.InfoCard.Show({ kind = "action", slot = 3 })
    assert(ns.InfoCard.IsShown() and not tip:IsShown(), "opening the card hides it")
    tip:Show(); assert(not tip:IsShown(), "and it cannot show while the card is open")
    ns.InfoCard.Hide()
    tip:Show(); assert(tip:IsShown(), "back after the card closes")
end)

-- The spot holds a tooltip 360 wide and 300 tall clear of both thumbs' buttons (the cluster, page boxes, Next target,
-- Interact, Jump, Dive), the item column, the stance and pet rows and the walk stick's box, at every Button size, either
-- hand, on a stand or not.
T("the_spot_is_clear_of_both_thumbs_at_every_setting", function()
    local problems = {}
    local function hits(a, b)
        return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
    end
    for _, size in ipairs({ 0.8, 1.0, 1.2, 1.4 }) do
        for _, left in ipairs({ false, true }) do
            for _, stand in ipairs({ false, true }) do
                setup()
                Stub.playerClass = "HUNTER"; ns.Each("Layout")
                Stub.setForms({ { name = "Bear Form", spell = 5487 }, { name = "Cat Form", spell = 768 },
                    { name = "Aquatic Form", spell = 1066 }, { name = "Travel Form", spell = 783 } })
                ns.Feel.Set("buttonSize", size); ns.Feel.Set("leftHanded", left); ns.Feel.Set("stand", stand)
                Stub.advance(1)
                local x, y, w, h = ns.Tooltip.Area(360, 300)
                local tipRect = { x = x, y = y, w = w, h = h }
                local list = ns.ThumbAreas({})
                local function add(f)
                    local fx, fy, fw, fh = ns.Final(f)
                    if fx then list[#list + 1] = { x = fx, y = fy, w = fw, h = fh, name = f:GetName() } end
                end
                for _, b in ipairs(ns.ItemRail.buttons) do add(b) end
                for _, b in ipairs(ns.ClassBars.pet) do add(b) end
                for _, b in ipairs(ns.ClassBars.stance) do if b:IsShown() then add(b) end end
                for _, k in ipairs(ns.InfoCard.KeepOff({})) do
                    if k.name == "walk stick" then list[#list + 1] = k end
                end
                for _, t in ipairs(list) do
                    if hits(tipRect, t) then
                        problems[#problems + 1] = ("size %.1f %s%s: %s"):format(size, left and "left" or "right",
                            stand and " stand" or "", tostring(t.name or "thumb side"))
                    end
                end
            end
        end
    end
    assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
end)

Stub.done("tooltip")
