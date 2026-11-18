-- TouchPlay: the game's buffs and debuffs, moved clear of the touch screen (iPad run 5, run 7).
--
-- The game's own BuffFrame and DebuffFrame (Edit Mode aura systems; this client's preset puts BuffFrame's top right
-- 255 x 10 from the screen's top right, icons growing left and wrapping down, 11 to a row, and DebuffFrame 155 lower:
-- Blizzard_EditMode/Mainline/EditModePresetLayouts.lua:433-468) ran under the Bags orb, next to the app's top-centre
-- toolbar. TouchPlay draws no buffs of its own: it moves the game's two frames clear of every touch area and the app's
-- toolbar, left of the Bags and Menu orbs (right edge 958), buffs from the top down and debuffs under the buffs, in the
-- band under the target card and its cast bar (the cast bar ends at y 198, x 636): top 200, x 547..958, either hand.
-- iPad run 7: run 5's 0.64 (right-handed) and 0.5 (left-handed) were too small to read. They are now drawn at 0.85: a
-- full row of 11 is 411 units wide, a row 42.5 tall; two rows of buffs and two of debuffs end at y 374, above the
-- right-handed stance row at its largest (y 375) and the item row (x 988 on). Left-handed, the quest list starts under
-- them (Hud.lua). Every count from none to two rows of each, at every Touch setting, is checked in test_feel.lua.
--
-- Edit Mode owns these frames and overrides SetScale, SetPoint and ClearAllPoints on them (EditModeSystemTemplates.lua:
-- 10-17, :117-155: the overrides tell the Edit Mode manager an anchor changed). So the move uses the frames' own widget
-- methods the overrides keep (SetScaleBase, SetPointBase, ClearAllPointsBase): no Lua field of the frame is written, nothing the
-- manager reads changes. The game's points are kept and put back on Restore (Off, pause) and while Edit Mode is open;
-- a layout the game applies again (EDIT_MODE_LAYOUTS_UPDATED) is followed by the move again. Out of a fight only.

local _, ns = ...

local Auras = ns.Register("Auras", {})

local REF_W = 1366          -- the layout's width (Style.lua)

Auras.GAP = 4               -- between the buffs and the debuffs
-- The model the layout checks use (the game's own sizes are read when the frames exist): the iPad shots show a buff
-- 37 units wide with its time under it, 44 apart and 49 tall; 11 buffs and 8 debuffs to a row (the preset above).
Auras.PITCH_W, Auras.PITCH_H = 44, 50
Auras.BUFFS_PER_ROW, Auras.DEBUFFS_PER_ROW = 11, 8
Auras.SCALE = 0.85          -- iPad run 7: readable (run 5 had 0.64 / 0.5)
Auras.BAND = { right = 958, top = 200 }   -- Hud: ORB_X 968; Units: the target's cast bar ends at y 198
Auras.MAX_ROWS = 4          -- two of buffs, two of debuffs: what the layout keeps room for

-- Where the buffs go: right edge, top and scale (layout units). The same for either hand.
function Auras.Place()
    return Auras.BAND.right, Auras.BAND.top, Auras.SCALE
end

-- The lowest y the buffs and debuffs reach with two rows of each (the left-handed quest list starts under it).
function Auras.Bottom()
    local _, top, scale = Auras.Place()
    return top + Auras.MAX_ROWS * Auras.PITCH_H * scale + Auras.GAP
end

-- The area the buffs and debuffs take in layout units (x, y, w, h from the top left of the 1366 x 1024 layout),
-- for `buffs` buffs and `debuffs` debuffs; nil when there are none.
function Auras.Area(buffs, debuffs)
    local rowsB = math.ceil((buffs or 0) / Auras.BUFFS_PER_ROW)
    local rowsD = math.ceil((debuffs or 0) / Auras.DEBUFFS_PER_ROW)
    if rowsB + rowsD == 0 then return nil end
    local right, top, scale = Auras.Place()
    local perRow = math.max(math.min(buffs or 0, Auras.BUFFS_PER_ROW), math.min(debuffs or 0, Auras.DEBUFFS_PER_ROW))
    local w = perRow * Auras.PITCH_W * scale
    local h = (rowsB + rowsD) * Auras.PITCH_H * scale + ((rowsB > 0 and rowsD > 0) and Auras.GAP or 0)
    return right - w, top, w, h
end

local saved = {}            -- frame -> { points = its points, scale = its scale } as the game had them
local want = false

local function Raw(frame, name) return frame[name .. "Base"] or frame[name] end

local function Save(frame)
    if saved[frame] then return end
    local points = {}
    for i = 1, (frame.GetNumPoints and frame:GetNumPoints() or 0) do points[i] = { frame:GetPoint(i) } end
    saved[frame] = { points = points, scale = frame.GetScale and frame:GetScale() or 1 }
end

-- Offsets in `frame`'s own units for a distance of `units` layout units.
local function Own(frame, units)
    local rootScale = ns.root:GetEffectiveScale() or 1
    local own = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not own or own <= 0 then own = 1 end
    return units * rootScale / own
end

-- The frame at the game's own scale times `scale` (its widget SetScale: Edit Mode's SetScale override would move it
-- and lay out the managed frames again, EditModeSystemTemplates.lua:117).
local function Scale(frame, scale)
    local game = saved[frame] and saved[frame].scale or 1
    if frame.SetScale then Raw(frame, "SetScale")(frame, game * scale) end
end

local function Move()
    if not want or ns.inEditMode then return end
    local right, top, scale = Auras.Place()
    local buffs, debuffs = _G.BuffFrame, _G.DebuffFrame
    if type(buffs) == "table" and buffs.SetPoint then
        Save(buffs)
        Scale(buffs, scale)
        Raw(buffs, "ClearAllPoints")(buffs)
        Raw(buffs, "SetPoint")(buffs, "TOPRIGHT", ns.root, "TOPRIGHT", -Own(buffs, REF_W - right), -Own(buffs, top))
    end
    if type(debuffs) == "table" and debuffs.SetPoint then
        Save(debuffs)
        Scale(debuffs, scale)
        Raw(debuffs, "ClearAllPoints")(debuffs)
        if type(buffs) == "table" and buffs.SetPoint then
            Raw(debuffs, "SetPoint")(debuffs, "TOPRIGHT", buffs, "BOTTOMRIGHT", 0, -Own(debuffs, Auras.GAP))
        else
            Raw(debuffs, "SetPoint")(debuffs, "TOPRIGHT", ns.root, "TOPRIGHT", -Own(debuffs, REF_W - right),
                -Own(debuffs, top))
        end
    end
end

local function GiveBack()
    for frame, was in pairs(saved) do
        if frame.SetScale then Raw(frame, "SetScale")(frame, was.scale) end
        Raw(frame, "ClearAllPoints")(frame)
        for _, p in ipairs(was.points) do Raw(frame, "SetPoint")(frame, p[1], p[2], p[3], p[4], p[5]) end
        saved[frame] = nil
    end
end

function Auras.IsMoved(frame) return saved[frame] ~= nil end

function Auras:Layout()
    if ns.inEditMode then return end
    want = true
    ns.Queue("auras", Move)
end

function Auras:Restore()
    want = false
    ns.Queue("auras", GiveBack)
end

function Auras:Init()
    if not EventRegistry then return end
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        ns.Guard("Auras EditMode.Enter", function() ns.Queue("auras", GiveBack) end)
    end, Auras)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        ns.Guard("Auras EditMode.Exit", function() if want then ns.Queue("auras", Move) end end)
    end, Auras)
end

-- The game applied a layout again (switching or saving one): its points are the game's now; keep those and move again.
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function()
    if not want or ns.inEditMode then return end
    for frame in pairs(saved) do
        local _, relativeTo = frame:GetPoint(1)
        if relativeTo ~= ns.root and relativeTo ~= _G.BuffFrame then saved[frame] = nil end   -- the game's again
    end
    ns.Queue("auras", Move)
end)
