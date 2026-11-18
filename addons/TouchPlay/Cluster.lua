-- TouchPlay: the spell cluster (rules 3 and 5): seven of the game's own action buttons under
-- the right thumb, four pages, and the game's form, stealth and vehicle pages.
--
-- The buttons are ActionBarButtonTemplate on the game's action slots, so cooldown sweeps, range,
-- mana, procs and the combat-hidden numbers all come from the template: nothing here reads or
-- compares a cooldown, a power or an aura value.
--
-- Paging is done by the game's secure code, so it works in a fight: a state header (the pager)
-- watches the game's bar conditions and sets each button's `action` attribute from a secure
-- snippet. A page box is a secure click that sets `state-chosen` on the pager.
--
-- A right click (a hold) never casts: the buttons carry *type1 only, so only a left click acts (with any keys
-- held, as the app sends them).
-- The hold asks the info card (Task 6) about the slot the button shows now.
--
-- Positions are fixed in v1: the layout lives in TouchPlayDB.layout (shared by every character),
-- never in TouchPlayCharDB.

local ADDON_NAME, ns = ...

local Cluster = ns.Register("Cluster", {})

-- Mockup numbers (layout units, 1366 x 1024): primary 88 centred (1268, 912); six 64 buttons on
-- a circle of radius 236 around it, from 180 degrees in steps of 19.2.
local PRIMARY, RING = 88, 64
local CENTRE_X, CENTRE_Y, RADIUS, STEP = 1268, 912, 236, 19.2
local PAGE_BOX, PAGE_X, PAGE_STEP, PAGE_Y = 42, 1156, 48, 566
local NEXT_D, NEXT_X, NEXT_Y = 56, 1150, 794
local CORNER = "BR"                   -- nearest screen corner for the whole cluster
local SLOTS_PER_PAGE, PAGES, BUTTONS = 12, 4, 7

local NEXT_ICON = "cross"                 -- the mockup's red crosshair, our own art (R48)

ns.L["cluster.pageForm"] = "C"
ns.L["cluster.pageVehicle"] = "V"
ns.L["cluster.nextTarget"] = "Next target"

-- Action slot of button i on page p: pages 1-4 are slots 1-7, 13-19, 25-31, 37-43.
function Cluster.Slot(page, i) return (page - 1) * SLOTS_PER_PAGE + i end

-- ---------------------------------------------------------------------------------------
-- The pager: a state header that pages the buttons from secure code

-- Runs for every change of the game's bar state (state-page) and of the chosen page box
-- (state-chosen). A bar state ("bonus1", "vehicle", ...) uses that bar's slots; "page" uses the
-- chosen page. bar-<state> attributes hold each bar's index: slot = (bar - 1) * 12 + button.
local PAGE_SNIPPET = [[
    local state = self:GetAttribute("state-page") or "page"
    local bar
    if state == "page" then
        bar = tonumber(self:GetAttribute("state-chosen")) or 1
    else
        bar = tonumber(self:GetAttribute("bar-" .. state)) or 1
    end
    for i = 1, 7 do
        self:GetFrameRef("spell" .. i):SetAttribute("action", (bar - 1) * 12 + i)
    end
]]

local PAGING = "[overridebar] override; [vehicleui] vehicle; [possessbar] possess; "
    .. "[shapeshift] tempshapeshift; [bonusbar:1] bonus1; [bonusbar:2] bonus2; "
    .. "[bonusbar:3] bonus3; [bonusbar:4] bonus4; page"

local pager = CreateFrame("Frame", "TouchPlayPager", ns.root, "SecureHandlerStateTemplate")
Cluster.pager = pager

-- ---------------------------------------------------------------------------------------
-- Placement

-- Top-left of each element in the mockup.
local function RingTopLeft(i)       -- i = 1..6, the ring button after the primary
    local a = math.rad(180 - (i - 1) * STEP)
    local cx, cy = CENTRE_X + RADIUS * math.cos(a), CENTRE_Y - RADIUS * math.sin(a)
    return math.floor(cx - RING / 2 + 0.5), math.floor(cy - RING / 2 + 0.5)
end

-- The page boxes' step in mockup units: 48, or more when small buttons would bring two boxes' touch areas (44 at
-- least) closer than 44 apart. The row keeps its right end (box 4 where the mockup has it) and grows leftward.
local function PageStep()
    local size = ns.FeelValue and ns.FeelValue("buttonSize") or 1
    if type(size) ~= "number" or size <= 0 then size = 1 end
    return math.max(PAGE_STEP, ns.Kit.MIN_TAP / size + 0.01)
end

-- The mockup x of page box p under the current Button size (the stance row keeps 16 units left of box 1).
function Cluster.PageX(p)
    return PAGE_X + (PAGES - 1) * PAGE_STEP - (PAGES - p) * PageStep()
end

local function Place()
    ns.Anchor(Cluster.buttons[1], CORNER, CENTRE_X - PRIMARY / 2, CENTRE_Y - PRIMARY / 2, true)
    for i = 2, BUTTONS do
        local x, y = RingTopLeft(i - 1)
        ns.Anchor(Cluster.buttons[i], CORNER, x, y, true)
    end
    for p, box in ipairs(Cluster.pageBoxes) do
        ns.Anchor(box, CORNER, Cluster.PageX(p), PAGE_Y, true)
    end
    ns.Anchor(Cluster.nextTarget, CORNER, NEXT_X, NEXT_Y, true)
end

-- ---------------------------------------------------------------------------------------
-- Spell buttons

-- A hold (the right click the hold key sends) asks the info card; it never casts.
local function ShowActionCard(button)
    ns.InfoCard.Show({ kind = "action", slot = button:GetAttribute("action") }, button)
end

local function OnSpellPostClick(self, button)
    if button ~= "RightButton" then return end
    if ns.InfoCard then ns.Guard("cluster hold", ShowActionCard, self) end
end

local function NewSpellButton(i)
    local d = i == 1 and PRIMARY or RING
    local b = CreateFrame("CheckButton", "TouchPlaySpell" .. i, ns.root, "ActionBarButtonTemplate")
    b:SetSize(d, d)
    b:RegisterForClicks("AnyUp")
    -- Only a left click acts: "*type1" is a left click with any keys held (the app holds Ctrl, Option and
    -- Shift with every key, which plain "type1" would not match). With no generic `type`, a right click has
    -- nothing to do; the template's press-and-hold release is kept for the left click only.
    b:SetAttribute("type", nil)
    b:SetAttribute("*type1", "action")
    b:SetAttribute("type2", nil)
    b:SetAttribute("typerelease", nil)
    b:SetAttribute("*typerelease1", "actionrelease")
    -- held keys never send the spell somewhere else: no self, focus or mouseover cast (the template turns
    -- them on; Alt is the game's self-cast key and the app always holds it)
    b:SetAttribute("checkselfcast", nil)
    b:SetAttribute("checkfocuscast", nil)
    b:SetAttribute("checkmouseovercast", nil)
    b:SetAttribute("action", Cluster.Slot(1, i))
    b:SetAttribute("showgrid", 1)       -- an empty slot stays on screen: tap it to choose a spell
    -- the icon fills the box and the game's Quickslot frame sits round it (Kit.FitActionButton)
    ns.Kit.FitActionButton(b, d)
    if b.HotKey then b.HotKey:SetAlpha(0) end     -- no key labels: the keys belong to the app
    ns.Kit.AddPress(b, "square")                  -- pressed: the pale-gold edge (mockup 10)
    ns.Kit.AddRange(b)                            -- out of range: the icon goes red (the hidden key label did that)
    b:HookScript("PostClick", OnSpellPostClick)
    pager:SetFrameRef("spell" .. i, b)
    return b
end

Cluster.buttons = {}
for i = 1, BUTTONS do Cluster.buttons[i] = NewSpellButton(i) end

-- ---------------------------------------------------------------------------------------
-- Page boxes

local BOX_GOLD, BOX_GREY = { 1, 0.82, 0 }, { 0.53, 0.53, 0.53 }
local FRAME_GOLD, FRAME_GREY = { 1, 0.82, 0 }, { 0.75, 0.75, 0.75 }   -- the page box frame: lit, not lit

local function NewPageBox(p)
    local box = CreateFrame("Button", "TouchPlayPage" .. p, ns.root, "SecureActionButtonTemplate")
    box:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    box:SetSize(PAGE_BOX, PAGE_BOX)
    box:RegisterForClicks("AnyUp")
    box:SetAttribute("type", "attribute")
    box:SetAttribute("attribute-frame", pager)
    box:SetAttribute("attribute-name", "state-chosen")
    box:SetAttribute("attribute-value", p)
    -- the picture: a dark box in a frame (our own art, R48: the tooltip's 16 px edge came out soft) with the page
    -- number (or the form letter) in it; the frame is tinted gold when lit
    local art = box:CreateTexture(nil, "BACKGROUND")
    ns.Kit.SetGlyph(art, "box")
    art:SetAllPoints(box)
    box.art = art
    box.label = box:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(box.label, ns.Kit.FONT_NUMBER, 18, "")
    box.label:SetPoint("CENTER", box, "CENTER", 0, 0)
    box.label:SetText(tostring(p))
    ns.Kit.FitHit(box)
    ns.Kit.AddPress(box, "square", box, 1)
    box:HookScript("PostClick", function() ns.Kit.Sound("tap") end)
    return box
end

Cluster.pageBoxes = {}
for p = 1, PAGES do Cluster.pageBoxes[p] = NewPageBox(p) end

-- Which box is lit and what box 1 reads. In a form, stealth or a vehicle the game's page wins:
-- box 1 reads "C" (or "V") and is lit; otherwise the chosen page is lit. Text colours and
-- backdrop colours only: nothing here moves or shows a protected frame, so it is safe in a fight.
local function ShowPages()
    local state = pager:GetAttribute("state-page") or "page"
    local chosen = tonumber(pager:GetAttribute("state-chosen")) or 1
    local lit = state == "page" and chosen or 1
    for p, box in ipairs(Cluster.pageBoxes) do
        local text = tostring(p)
        if p == 1 and state ~= "page" then
            text = ns.T(state == "vehicle" and "cluster.pageVehicle" or "cluster.pageForm")
        end
        box.label:SetText(text)
        local c = p == lit and BOX_GOLD or BOX_GREY
        box.label:SetTextColor(c[1], c[2], c[3])
        local frame = p == lit and FRAME_GOLD or FRAME_GREY
        box.art:SetVertexColor(frame[1], frame[2], frame[3])
    end
end

pager:HookScript("OnAttributeChanged", function(_, name)
    if name ~= "state-page" and name ~= "state-chosen" then return end
    ns.Guard("cluster pages", ShowPages)
end)

-- ---------------------------------------------------------------------------------------
-- Next target

do
    local nt = CreateFrame("Button", "TouchPlayNextTarget", ns.root, "SecureActionButtonTemplate")
    nt:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    nt:SetSize(NEXT_D, NEXT_D)
    nt:RegisterForClicks("AnyUp")
    nt:SetAttribute("type", "macro")
    nt:SetAttribute("macrotext", "/targetenemy")
    -- the picture: the kit's ring button; the secure button over it takes the tap
    local face = ns.Kit.RingButton(nt, NEXT_D, NEXT_ICON, ns.T("cluster.nextTarget"))
    face:SetAllPoints(nt)
    face:EnableMouse(false)
    nt.face = face
    ns.Kit.FitHit(nt)
    ns.Kit.AddPress(nt, "round", face)            -- the ring's own press glow, lit by the secure button over it
    nt:HookScript("PostClick", function() ns.Kit.Sound("tap") end)
    Cluster.nextTarget = nt
end

Place()

-- The pager works from the moment it exists: its snippets, the bars it pages onto, the driver.
pager:SetAttribute("_onstate-page", PAGE_SNIPPET)
pager:SetAttribute("_onstate-chosen", PAGE_SNIPPET)
pager:SetAttribute("bar-override", GetOverrideBarIndex and GetOverrideBarIndex() or 14)
pager:SetAttribute("bar-vehicle", GetVehicleBarIndex and GetVehicleBarIndex() or 12)
pager:SetAttribute("bar-tempshapeshift", GetTempShapeshiftBarIndex and GetTempShapeshiftBarIndex() or 13)
pager:SetAttribute("bar-possess", 11)                 -- bonus bar 5
for n = 1, 4 do pager:SetAttribute("bar-bonus" .. n, 6 + n) end
RegisterStateDriver(pager, "page", PAGING)

-- ---------------------------------------------------------------------------------------
-- Module steps

function Cluster:Init()
    -- Positions are fixed in v1 and shared by every character; nothing goes in TouchPlayCharDB.
    local layout = ns.db.layout
    if type(layout) ~= "table" then layout = {}; ns.db.layout = layout end
    if type(layout.scale) ~= "number" then layout.scale = 1 end

    local Contract = ns.Contract
    if not Contract then return end
    for i, b in ipairs(Cluster.buttons) do
        local name = b:GetName()
        Contract.Area("spell" .. i, b, { anchor = CORNER,
            tap = { click = name, button = "LeftButton" },
            hold = { click = name, button = "RightButton" } })
    end
    for p, box in ipairs(Cluster.pageBoxes) do
        Contract.Area("page" .. p, box, { anchor = CORNER,
            tap = { click = box:GetName(), button = "LeftButton" } })
    end
    Contract.Area("nexttarget", Cluster.nextTarget, { anchor = CORNER,
        tap = { click = "TouchPlayNextTarget", button = "LeftButton" } })
end

function Cluster:Layout()
    ns.Queue("cluster layout", Place)
end

function Cluster:Refresh()
    ShowPages()
end
