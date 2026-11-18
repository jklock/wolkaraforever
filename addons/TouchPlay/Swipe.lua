-- TouchPlay: swipe between pages (iPad run 5).
--
-- While a window is open the app hands the game plain mouse input (ruling A33): a tap is a left down and up on lift; a
-- finger that moves past 10 points is a left down at the START point, mouse moves following the finger, and a left up
-- where it lifts. So a swipe reaches the game as GLOBAL_MOUSE_DOWN at the start and GLOBAL_MOUSE_UP at the lift (the
-- game's own events, Blizzard_Menu/Menu.lua:54 listens to the same). Reading them changes nothing in the game.
--
-- A swipe is a left down and up at least MIN layout units apart, mostly sideways (|dx| at least RATIO times |dy|),
-- that started on a page holder, with nothing on the cursor (a dragged item is not a swipe). Finger right to left is
-- the next page, left to right the previous one. Page holders, topmost first:
--   TouchPlay's own: the picker sheet (pages, then tabs: Picker.Turn), the guide (steps: Guide.Turn), a unit's info
--     card (its second page: InfoCard.Turn). Their own page labels, counters and dots update as their buttons do; no
--     slide is drawn, so Reduce motion has nothing to stop.
--   The game's: windows with page buttons whose paging is plain Lua with no protected action behind it, turned by
--     clicking their own page button (Button:Click, out of a fight only): the merchant (MerchantNextPageButton /
--     MerchantPrevPageButton, Blizzard_UIPanels_Game/Mainline/MerchantFrame.xml:555, MerchantFrame.lua:605-630) and a
--     book or letter (ItemTextNextPageButton / ItemTextPrevPageButton, Mainline/ItemTextFrame.xml:119-145).
-- Left out on purpose: the spellbook (PlayerSpellsFrame, whose source this client does not ship; its pages lay out
-- the spell buttons the player casts from, so a page turned by add-on code would taint them and the game would block
-- those casts), and pet stable / other add-ons' windows (no page buttons here, or unknown).

local _, ns = ...

local Swipe = ns.Register("Swipe", {})

Swipe.MIN = 60              -- layout units the finger must travel sideways
Swipe.RATIO = 2             -- sideways at least twice as far as up or down

-- The game's windows: { window, next button, previous button } by global name.
Swipe.GAME = {
    { "MerchantFrame", "MerchantNextPageButton", "MerchantPrevPageButton" },
    { "ItemTextFrame", "ItemTextNextPageButton", "ItemTextPrevPageButton" },
}

local start                 -- { x, y, holder } of the left button's down, in screen units

-- Whether the screen point (sx, sy) is on `frame` (shown and visible).
local function Under(frame, sx, sy)
    if type(frame) ~= "table" or not frame.IsVisible or not frame:IsVisible() or not frame.GetRect then return false end
    local l, b, w, h = frame:GetRect()
    if not l or not w then return false end
    local s = frame:GetEffectiveScale() or 1
    return sx >= l * s and sx <= (l + w) * s and sy >= b * s and sy <= (b + h) * s
end

local function Click(name)
    local button = _G[name]
    if type(button) ~= "table" or not button.Click or not button:IsVisible() then return false end
    if button.IsEnabled and not button:IsEnabled() then return false end
    button:Click()
    return true
end

-- The page holders, topmost first: { frame, turn(dir) }.
local function Holders()
    local list = {}
    local guide, picker, card = ns.Guide, ns.Picker, ns.InfoCard
    if guide and guide.dim then list[#list + 1] = { guide.dim, guide.Turn } end
    if card and card.frame then list[#list + 1] = { card.frame, card.Turn } end
    if picker and picker.sheet then list[#list + 1] = { picker.sheet, picker.Turn } end
    for _, g in ipairs(Swipe.GAME) do
        local window = _G[g[1]]
        if type(window) == "table" then
            list[#list + 1] = { window, function(dir)
                if ns.InFight and ns.InFight() or InCombatLockdown() then return false end
                return Click(dir > 0 and g[2] or g[3])
            end }
        end
    end
    return list
end

local function HolderAt(sx, sy)
    for _, h in ipairs(Holders()) do
        if Under(h[1], sx, sy) then return h end
    end
    return nil
end

local function OnDown(_, button)
    start = nil
    if button ~= "LeftButton" or not ns.IsActive() then return end
    if GetCursorInfo and GetCursorInfo() then return end
    local sx, sy = GetCursorPosition()
    local holder = HolderAt(sx, sy)
    if holder then start = { x = sx, y = sy, holder = holder } end
end

local function OnUp(_, button)
    local s = start
    start = nil
    if not s or button ~= "LeftButton" or not ns.IsActive() then return end
    if GetCursorInfo and GetCursorInfo() then return end
    local sx, sy = GetCursorPosition()
    local k = ns.root:GetEffectiveScale() or 1
    local dx, dy = (sx - s.x) / k, (sy - s.y) / k
    if math.abs(dx) < Swipe.MIN or math.abs(dx) < Swipe.RATIO * math.abs(dy) then return end
    if not s.holder[1]:IsVisible() then return end
    local turned = s.holder[2](dx < 0 and 1 or -1)
    if turned and ns.Kit and ns.Kit.Sound then ns.Kit.Sound("tap") end
end

ns.On("GLOBAL_MOUSE_DOWN", function(button) OnDown(nil, button) end)      -- ns.On guards each handler
ns.On("GLOBAL_MOUSE_UP", function(button) OnUp(nil, button) end)

function Swipe:Restore() start = nil end
