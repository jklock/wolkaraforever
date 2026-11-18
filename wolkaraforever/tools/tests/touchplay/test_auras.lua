-- iPad run 5: the game's buffs ran under the Bags orb. Auras moves the game's BuffFrame and DebuffFrame clear of the
-- touch screen with the frames' own widget methods (never Edit Mode's SetPoint / ClearAllPoints / SetScale overrides)
-- and gives them back on Off, a pause and in Edit Mode.
dofile("tests/stub.lua")

-- The game's two aura frames as Edit Mode leaves them: the widget methods kept as *Base, the overrides counting calls.
local function auraFrames()
    local made = {}
    for _, spec in ipairs({ { "BuffFrame", -255, -10 }, { "DebuffFrame", -270, -155 } }) do
        local f = CreateFrame("Frame", spec[1], UIParent)
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", spec[2], spec[3])
        f:SetScale(1)
        f.system = true
        f.overrides = 0
        f.SetPointBase, f.ClearAllPointsBase, f.SetScaleBase = f.SetPoint, f.ClearAllPoints, f.SetScale
        f.SetPoint = function(self, ...) self.overrides = self.overrides + 1; return self:SetPointBase(...) end
        f.ClearAllPoints = function(self) self.overrides = self.overrides + 1; return self:ClearAllPointsBase() end
        f.SetScale = function(self, s) self.overrides = self.overrides + 1; return self:SetScaleBase(s) end
        made[#made + 1] = f
    end
    return made[1], made[2]
end

local function setup()
    Stub.reset()
    local buffs, debuffs = auraFrames()
    Stub.loadAll(); Stub.login()
    return buffs, debuffs
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

T("buffs_move_into_the_band_with_the_widget_methods", function()
    local buffs, debuffs = setup()
    assert(ns.Auras.IsMoved(buffs) and ns.Auras.IsMoved(debuffs))
    local point, rel, relPoint, x, y = buffs:GetPoint(1)
    assert(buffs:GetNumPoints() == 1 and point == "TOPRIGHT" and rel == ns.root and relPoint == "TOPRIGHT", tostring(rel))
    local right, top, scale = ns.Auras.Place()
    assert(near(buffs:GetScale(), scale) and scale < 1, "drawn at the scale that fits a full row: " .. buffs:GetScale())
    -- offsets in the frame's own units: layout units * root scale / the frame's effective scale
    local k = ns.root:GetEffectiveScale() / buffs:GetEffectiveScale()
    assert(near(x, -(1366 - right) * k) and near(y, -top * k), x .. " " .. y)
    local dp, drel, drelPoint = debuffs:GetPoint(1)
    assert(dp == "TOPRIGHT" and drel == buffs and drelPoint == "BOTTOMRIGHT", "debuffs under the buffs")
    assert(buffs.overrides == 0 and debuffs.overrides == 0, "never through Edit Mode's overrides")
    assert(not ns.paused, ns.lastError)
end)

T("buffs_given_back_on_off_pause_and_edit_mode", function()
    local buffs, debuffs = setup()
    ns.SetEnabled(false)
    local p, rel, rp, x, y = buffs:GetPoint(1)
    assert(rel == UIParent and x == -255 and y == -10 and buffs:GetScale() == 1, "Off: the game's place and size")
    assert(select(2, debuffs:GetPoint(1)) == UIParent and select(5, debuffs:GetPoint(1)) == -155)
    ns.SetEnabled(true)
    assert(select(2, buffs:GetPoint(1)) == ns.root)
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(select(2, buffs:GetPoint(1)) == UIParent and buffs:GetScale() == 1, "Edit Mode: the game's")
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(select(2, buffs:GetPoint(1)) == ns.root, "moved again after Edit Mode")
    ns.Pause("test")
    assert(select(2, buffs:GetPoint(1)) == UIParent, "a pause gives it back")
    assert(buffs.overrides == 0 and debuffs.overrides == 0)
end)

-- iPad run 7: one readable place for either hand (0.85, under the target card); a change waits for the end of a fight.
T("buffs_same_place_either_hand_readable_and_wait_for_the_end_of_a_fight", function()
    local buffs = setup()
    local _, _, _, rightX, rightY = buffs:GetPoint(1)
    assert(buffs:GetScale() >= 0.85, "readable: " .. buffs:GetScale())
    ns.Feel.Set("leftHanded", true); Stub.advance(1)
    local _, _, _, leftX, leftY = buffs:GetPoint(1)
    assert(leftX == rightX and leftY == rightY and buffs:GetScale() >= 0.85, "left-handed: the same band")
    Stub.combat(true); Stub.fire("PLAYER_REGEN_DISABLED")
    ns.SetEnabled(false); Stub.advance(1)
    assert(select(2, buffs:GetPoint(1)) == ns.root, "nothing moves in a fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED"); Stub.advance(1)
    assert(select(2, buffs:GetPoint(1)) == UIParent, "given back after it")
end)

T("a_layout_the_game_applies_again_is_kept_as_the_games", function()
    local buffs = setup()
    -- the player saves a layout in Edit Mode: the game anchors the frame anew (through its override)
    buffs:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -20)
    buffs:ClearAllPoints(); buffs:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -20)
    Stub.fire("EDIT_MODE_LAYOUTS_UPDATED")
    assert(select(2, buffs:GetPoint(1)) == ns.root, "moved again")
    ns.SetEnabled(false)
    assert(select(4, buffs:GetPoint(1)) == -300, "and the game's new place is what Off gives back")
end)

T("no_aura_frames_no_error", function()
    Stub.reset(); Stub.loadAll(); Stub.login()
    ns.Each("Layout"); ns.SetEnabled(false); ns.SetEnabled(true)
    assert(not ns.paused, ns.lastError)
end)

Stub.done("auras")
