-- TouchPlay: where the game's tooltip shows (iPad run 7).
--
-- On the iPad: "tooltips cover the buttons being touched". The game puts its tooltip at its default place, the bottom right
-- corner (GameTooltip_SetDefaultAnchor, SharedTooltipTemplates.lua:87: the world under the finger, the unit frames, and
-- our spell buttons with "UberTooltips" on), or beside the button that owns it (ActionButton.lua:1114 SetTooltip:
-- ANCHOR_RIGHT / ANCHOR_LEFT). On the touch screen the bottom right is the spell cluster (or, left-handed, the walk
-- stick's box) and beside a button is under the thumb. So, while the touch screen is on:
--   * every tooltip the game places at its default spot, and every tooltip one of TouchPlay's own buttons opens, goes
--     to one fixed spot away from both thumbs: hanging from the top centre, under the app's toolbar band (y 64), where
--     neither hand's buttons, the item column or the walk stick's box are;
--   * while TouchPlay's info card is open no game tooltip shows (the card says it all, bigger).
-- Only post-hooks (hooksecurefunc, HookScript); the tooltip is not a protected frame, so placing or hiding it is
-- allowed in a fight. Windows that place their own tooltips (bags, the character pane) keep theirs.

local _, ns = ...

local Tooltip = ns.Register("Tooltip", {})

Tooltip.TOP = 64            -- layout units from the top: under the app's top band (ns.APP_TOP_H 60)

local REF_W = 1366

local function Active()
    return ns.IsActive() and not ns.inEditMode
end

-- TouchPlay's own frames: under its roots, or named TouchPlay*.
local function Ours(frame)
    local f, guard = frame, 0
    while type(f) == "table" and guard < 30 do
        if f == ns.root or f == ns.moveRoot then return true end
        local ok, name = pcall(f.GetName, f)
        if ok and type(name) == "string" and name:find("^TouchPlay") then return true end
        local okParent, parent = pcall(f.GetParent, f)
        f, guard = okParent and parent or nil, guard + 1
    end
    return false
end
Tooltip.Ours = Ours

-- Offsets in `frame`'s own units for `units` layout units.
local function Own(frame, units)
    local rootScale = ns.root:GetEffectiveScale() or 1
    local own = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not own or own <= 0 then own = 1 end
    return units * rootScale / own
end

-- The fixed spot: the tooltip's top centre at the screen's top centre, Tooltip.TOP down.
function Tooltip.Place(tip)
    tip:ClearAllPoints()
    tip:SetPoint("TOP", ns.root, "TOPLEFT", Own(tip, REF_W / 2), -Own(tip, Tooltip.TOP))
end

-- The rectangle a tooltip `w` x `h` (layout units) takes at the spot: x, y, w, h from the top left.
function Tooltip.Area(w, h)
    local width = (ns.root and ns.root:GetWidth()) or REF_W
    if not width or width <= 0 then width = REF_W end
    return width / 2 - w / 2, Tooltip.TOP, w, h
end

local placing = false

local function AfterDefaultAnchor(tip)
    if not Active() or tip ~= _G.GameTooltip then return end
    ns.Guard("tooltip place", Tooltip.Place, tip)
end

-- One of our buttons opened the tooltip beside itself (ANCHOR_RIGHT / ANCHOR_LEFT): take it to the spot instead.
local function AfterSetOwner(tip, owner, anchor)
    if placing or not Active() or anchor == "ANCHOR_NONE" or not Ours(owner) then return end
    placing = true
    ns.Guard("tooltip owner", function()
        tip:SetOwner(owner, "ANCHOR_NONE")
        Tooltip.Place(tip)
    end)
    placing = false
end

local function OnTooltipShow(tip)
    if Active() and ns.InfoCard and ns.InfoCard.IsShown() then tip:Hide() end
end

-- The info card opened: a game tooltip still up goes (the card copied what it needed first, InfoCard.lua).
function Tooltip.CardOpened()
    local tip = _G.GameTooltip
    if Active() and tip and tip:IsShown() then tip:Hide() end
end

local hooked = false
function Tooltip:Init()
    if hooked then return end
    hooked = true
    if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", AfterDefaultAnchor)
    end
    local tip = _G.GameTooltip
    if tip then
        if tip.SetOwner then hooksecurefunc(tip, "SetOwner", AfterSetOwner) end
        if tip.HookScript then tip:HookScript("OnShow", OnTooltipShow) end
    end
end
