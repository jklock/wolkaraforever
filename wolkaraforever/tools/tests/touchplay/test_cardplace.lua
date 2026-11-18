-- iPad run 5: a spell was held, the card opened over the bottom-centre chat strip and the app's toolbar, and a tap
-- on Change spell opened the keyboard. The card keeps off the chat strip, the walk stick's side and the app's toolbar
-- bands, wherever it opens from (the spell buttons, the item column, the stance and pet rows, the player and target
-- cards), at every Button size, either hand, on a stand or not.
dofile("tests/stub.lua")

local function meet(a, b)
    return a.x < b.x + b.w - 0.01 and b.x < a.x + a.w - 0.01 and a.y < b.y + b.h - 0.01 and b.y < a.y + a.h - 0.01
end

local function cardRect()
    local card = ns.InfoCard.frame
    local w, h = card:GetSize()
    return { x = card.placeX, y = card.placeY, w = w, h = h }
end

local function anchorRect(f)
    local a = f.touchAnchor                         -- where it was laid out, in layout units
    return { x = a.x, y = a.y, w = a.w, h = a.h }
end

local function setup(size, left, stand)
    Stub.reset(); Stub.loadAll(); Stub.login()
    Stub.playerClass = "HUNTER"; Stub.setPet(true)
    for i = 1, 10 do Stub.setPetAction(i, { name = "Pet" .. i, texture = "t", usable = true }) end
    Stub.fire("PET_BAR_UPDATE"); Stub.fire("UNIT_PET", "player")
    Stub.setForms({ { name = "Bear Form", spell = 5487 }, { name = "Aquatic Form", spell = 1066 },
        { name = "Cat Form", spell = 768 }, { name = "Travel Form", spell = 783 } })
    for i = 1, 12 do Stub.actions[i] = 116 end
    Stub.spellNames[116] = "Frostbolt"
    ns.Feel.Set("buttonSize", size); ns.Feel.Set("leftHanded", left); ns.Feel.Set("stand", stand); Stub.advance(1)
    Stub.applyDrivers(); Stub.applyUnitWatch()
end

-- Every place a card opens from: { label, subject, frame }.
local function anchors()
    local list = {}
    for i, b in ipairs(ns.Cluster.buttons) do
        list[#list + 1] = { "spell" .. i, { kind = "action", slot = b:GetAttribute("action") or 3 }, b }
    end
    for i, b in ipairs(ns.ItemRail.buttons) do
        list[#list + 1] = { "item" .. i, { kind = "railSlot", rail = i }, b }
    end
    for i, b in ipairs(ns.ClassBars.stance) do
        if b:IsVisible() then list[#list + 1] = { "stance" .. i, { kind = "spell", spellID = 5487 }, b } end
    end
    for i, b in ipairs(ns.ClassBars.pet) do
        if b:IsVisible() then list[#list + 1] = { "pet" .. i, { kind = "petAction", index = i }, b } end
    end
    list[#list + 1] = { "player", { kind = "unit", unit = "player" }, ns.Units.player }
    if ns.Units.target:IsVisible() then
        list[#list + 1] = { "target", { kind = "unit", unit = "target" }, ns.Units.target }
    end
    return list
end

T("card_keeps_off_the_chat_strip_the_stick_and_the_app_toolbar_from_every_anchor", function()
    local problems, cards = {}, 0
    for _, size in ipairs({ 0.8, 1.0, 1.2, 1.4 }) do
        for _, left in ipairs({ false, true }) do
            for _, stand in ipairs({ false, true }) do
                setup(size, left, stand)
                local label = ("size %.1f %s%s"):format(size, left and "left" or "right", stand and " stand" or "")
                for _, withTarget in ipairs({ false, true }) do
                    Stub.setTarget(withTarget and "enemy" or nil); Stub.applyUnitWatch()
                    for _, a in ipairs(anchors()) do
                        ns.InfoCard.Show(a[2], a[3])
                        if ns.InfoCard.IsShown() then
                            cards = cards + 1
                            local c = cardRect()
                            for _, r in ipairs(ns.InfoCard.KeepOff({}, 1366)) do
                                if meet(c, r) then
                                    problems[#problems + 1] = ("%s: card from %s over %s"):format(label, a[1], r.name)
                                end
                            end
                            if c.x < 7.99 or c.y < 7.99 or c.x + c.w > 1366 - 7.99 or c.y + c.h > 1024 - 7.99 then
                                problems[#problems + 1] = ("%s: card from %s off the screen"):format(label, a[1])
                            end
                            if meet(c, anchorRect(a[3])) then
                                problems[#problems + 1] = ("%s: card over %s itself"):format(label, a[1])
                            end
                            ns.InfoCard.Hide()
                        end
                    end
                end
                assert(not ns.paused, ns.lastError)
            end
        end
    end
    assert(cards > 300, "cards opened: " .. cards)
    assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
end)

T("card_place_moves_up_off_what_is_in_the_way", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    local avoid = { { x = 296, y = 948, w = 568, h = 52 } }       -- the chat strip
    -- held at the bottom right of the strip: the card would sit on the strip; it moves up
    local x, y = ns.InfoCard.Place(420, 290, 900, 900, 64, 64, 1366, avoid)
    assert(y + 290 <= 948 - 12 + 1e-6, "above the strip: " .. y)
    -- nothing in the way: unchanged
    local _, y2 = ns.InfoCard.Place(420, 290, 900, 300, 64, 64, 1366, avoid)
    local _, y3 = ns.InfoCard.Place(420, 290, 900, 300, 64, 64, 1366)
    assert(y2 == y3)
    -- the top band: the card moves down below it
    local _, y4 = ns.InfoCard.Place(300, 200, 400, 0, 64, 40, 1366, { { x = 608, y = 0, w = 150, h = 60 } })
    assert(y4 >= 60 + 12 - 1e-6, "below the toolbar: " .. y4)
    -- no way fits: stays where it was put
    local _, y5 = ns.InfoCard.Place(420, 1000, 900, 300, 64, 64, 1366, avoid)
    assert(y5 == 8)
end)

Stub.done("cardplace")
