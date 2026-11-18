-- iPad run 6 (17 Nov): the Next target ring and its words drew on top of Bagnon's bag window. Game windows and other
-- add-ons' windows must sit above the play screen's buttons; TouchPlay's own sheets and cards (picker, Menu, settings,
-- info card, loot card, guide, reload notice, pause card) stay above everything.
--
-- The game's window strata (Camelot UI source, /tmp/wowui/Interface/AddOns):
--   UIParent and the UI panels on it (character, spellbook, vendor, quest, mail, bank ...)  MEDIUM (UIParent's own)
--   ContainerFrameTemplate, ContainerFrameCombinedBags   MEDIUM   Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:229, 313
--   SpellBookFrame                                       MEDIUM   Blizzard_UIPanels_Game/Cata|Vanilla/SpellBookFrame.xml
--   WorldMapFrame's border                               HIGH     Blizzard_WorldMap/Blizzard_WorldMap.xml:85
--   LootFrame                                            HIGH     Blizzard_UIPanels_Game/Mainline/LootFrame.xml:116
--   SettingsPanel                                        HIGH     Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml:4
--   the game's own unit frames and quest tracker         LOW      PlayerFrame.xml:13, TargetFrame.xml:52, ObjectiveTracker.xml:3
-- Bagnon (Forever-iPad-2-Essentials): its windows take the profile's strata, HIGH by default (Bagnon/src/defaults.lua:15;
-- BagBrother/core/classes/frameBase.lua:51), and its options offer LOW, MEDIUM or HIGH.
-- So the play screen is LOW, as the game's own unit frames are: under every MEDIUM or HIGH window, over the world's
-- BACKGROUND layers. Sheets are DIALOG or higher.
dofile("tests/stub.lua")

local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8 }
local LOWEST_WINDOW = "MEDIUM"   -- the lowest strata a game window has (above)

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
end

local function under(frame, root)
    local f, guard = frame, 0
    while f and guard < 60 do
        if f == root then return true end
        f, guard = f:GetParent(), guard + 1
    end
    return false
end

-- TouchPlay's sheets and cards: each, and everything in it, sits above every window.
local SHEETS = {
    { "Picker", "dim" }, { "Picker", "sheet" }, { "Picker", "ring" }, { "Picker", "flash" },
    { "Menu", "dim" }, { "Menu", "panel" },
    { "Feel", "dim" }, { "Feel", "panel" },
    { "Guide", "dim" }, { "Guide", "glow" },
    { "Loot", "card" },
    { "Contract", "notice" },
    { "Perf", "panel" }, { "Perf", "card" },
}

local function Sheets()
    local list = {}
    for _, path in ipairs(SHEETS) do
        local frame = ns[path[1]] and ns[path[1]][path[2]]
        assert(type(frame) == "table", path[1] .. "." .. path[2] .. " exists")
        list[#list + 1] = frame
    end
    -- the info card and the layer that closes it are made the first time a card shows
    for _, key in ipairs({ "frame", "catcher" }) do
        if ns.InfoCard[key] then list[#list + 1] = ns.InfoCard[key] end
    end
    return list
end

local function inSheet(frame, sheets)
    for _, sheet in ipairs(sheets) do if under(frame, sheet) then return true end end
    return false
end

-- What the game's AFK saver dims on purpose: it covers the screen while away (Hud.afk), so it is no play-screen button.
local function Exempt(frame)
    return frame == ns.Hud.afk or under(frame, ns.Hud.afk)
end

T("play_screen_frames_sit_under_the_games_windows", function()
    setup()
    local sheets = Sheets()
    local checked = 0
    for _, frame in ipairs(Stub.allFrames()) do
        local mine = under(frame, ns.root) or under(frame, ns.moveRoot)
        if mine and not inSheet(frame, sheets) and not Exempt(frame) then
            local strata = frame:GetFrameStrata()
            assert(RANK[strata] < RANK[LOWEST_WINDOW], tostring(frame:GetName() or frame.kind) .. " is " .. strata
                .. ": a play-screen frame must be under the game's windows (" .. LOWEST_WINDOW .. ")")
            checked = checked + 1
        end
    end
    assert(checked > 50, "the play screen was walked (" .. checked .. " frames)")
    -- the ones from the screenshot
    for _, frame in ipairs({ ns.Cluster.nextTarget, ns.Cluster.nextTarget.face, TouchPlaySpell1, TouchPlayPage1,
        TouchPlayItem1, TouchPlayBags, TouchPlayMenu, TouchPlayQuest, TouchPlayMinimap, ns.Units.player, ns.Units.target,
        ns.Interact.interact, ns.Interact.jump }) do
        assert(frame:GetFrameStrata() == "LOW", tostring(frame:GetName()) .. " is LOW, not " .. frame:GetFrameStrata())
    end
    assert(ns.root:GetFrameStrata() == "LOW" and ns.moveRoot:GetFrameStrata() == "LOW")
end)

T("sheets_and_cards_stay_above_every_window", function()
    setup()
    local sheets = Sheets()
    for _, sheet in ipairs(sheets) do
        for _, frame in ipairs(Stub.allFrames()) do
            if under(frame, sheet) then
                local strata = frame:GetFrameStrata()
                assert(RANK[strata] >= RANK.DIALOG, tostring(frame:GetName() or frame.kind) .. " in a sheet is " .. strata)
            end
        end
    end
    -- the info card is made the first time it shows
    ns.InfoCard.Show({ kind = "action", slot = 3 })
    local card = ns.InfoCard.frame
    assert(card and RANK[card:GetFrameStrata()] >= RANK.DIALOG, "the info card is above every window")
    assert(RANK[ns.InfoCard.secureButton:GetFrameStrata()] >= RANK.DIALOG, "and so is its secure button")
end)

-- The minimap sits in our ring: it goes with the ring's strata and gets its own back with its parent.
T("the_minimap_takes_the_rings_strata_and_gets_its_own_back", function()
    Stub.reset()
    local map = Stub.frames.Minimap
    map:SetFrameStrata("MEDIUM")         -- as if the game had set it
    Stub.loadAll(); Stub.login()
    assert(ns.Hud.IsMinimapInRing(), "the minimap is in the ring")
    assert(map:GetFrameStrata() == "LOW", "in the ring the minimap is LOW, not " .. map:GetFrameStrata())
    ns.SetEnabled(false)
    assert(map:GetFrameStrata() == "MEDIUM", "given back with its own strata")
end)

-- Every strata is set when the frame is made (the files load out of a fight, or while the game is still loading):
-- nothing changes a strata in a fight, where the game refuses it for a secure frame.
T("no_strata_changes_in_a_fight", function()
    setup()
    Stub.combat(true)
    Stub.fire("PLAYER_REGEN_DISABLED")
    ns.InfoCard.Show({ kind = "action", slot = 3 })
    ns.Picker.Open(1)
    Stub.fire("LOOT_OPENED")
    Stub.combat(false)
    Stub.fire("PLAYER_REGEN_ENABLED")
    assert(not ns.paused, ns.lastError)
end)
Stub.done("strata")
