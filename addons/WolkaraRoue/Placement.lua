-- Sizes and places game windows clear of the screen corners.
local _, ns = ...

local Placement = ns.Register("Window placement", {})

local MARGIN = 10
local EDGE = 28
local TOOLBAR = 40
local HANDLE = 36
local LEFT_ZONE_X, LEFT_ZONE_Y = 0.42, 0.42
local RIGHT_ZONE_X, RIGHT_ZONE_Y = 0.64, 0.25
local WHOLE_SCREEN = { WorldMapFrame = true }

local original
local natural, pending = {}, {}
local busy = false

local function Large()
    local db = ns.db
    if type(db.windows) ~= "table" then db.windows = {} end
    if db.windows.size == nil then db.windows.size = "large" end
    return db.windows.size == "large"
end
Placement.Settings = function() Large(); return ns.db.windows end

local function Areas(W, H)
    if Large() then
        return { { left = EDGE, right = EDGE, top = HANDLE, bottom = TOOLBAR } }
    end
    return {
        { left = W * LEFT_ZONE_X + MARGIN, right = W * (1 - RIGHT_ZONE_X) + MARGIN, top = HANDLE, bottom = TOOLBAR },
        { left = MARGIN, right = W * (1 - RIGHT_ZONE_X) + MARGIN, top = MARGIN, bottom = H * (1 - LEFT_ZONE_Y) + MARGIN },
        { left = MARGIN, right = MARGIN, top = MARGIN, bottom = H * (1 - RIGHT_ZONE_Y) + MARGIN },
    }
end

function Placement.Best(W, H, width, height, largest)
    local best, chosen = -1, nil
    for _, area in ipairs(Areas(W, H)) do
        local scale = math.min(largest, (W - area.left - area.right) / width, (H - area.top - area.bottom) / height)
        if scale > best then best, chosen = scale, area end
    end
    return best, chosen
end

local function Overhang(frame)
    local close = frame.CloseButton or (type(frame.BorderFrame) == "table" and frame.BorderFrame.CloseButton)
        or _G[(frame:GetName() or "") .. "CloseButton"]
    if type(close) ~= "table" or not close.GetRight or not close:IsShown() then return 0, 0 end
    local frameRight, frameTop, closeRight, closeTop = frame:GetRight(), frame:GetTop(), close:GetRight(), close:GetTop()
    if not (frameRight and frameTop and closeRight and closeTop) then return 0, 0 end
    local f, c = frame:GetEffectiveScale(), close:GetEffectiveScale()
    return math.max(0, (closeRight * c - frameRight * f) / f), math.max(0, (closeTop * c - frameTop * f) / f)
end

local function Fit(frame)
    if not (ns.Fan and ns.Fan:Enabled()) then
        if original then return original(frame) end
        return
    end
    if busy or type(frame) ~= "table" or not frame.IsShown or not frame:IsShown() then return end
    if InCombatLockdown() and frame:IsProtected() then pending[frame] = true; return end
    if frame:GetNumPoints() > 1 then return end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width < 1 or height < 1 then return end
    if natural[frame] == nil then natural[frame] = frame:GetScale() or 1 end
    local ui = UIParent:GetEffectiveScale()
    local parent = frame:GetParent()
    local parentScale = parent and parent:GetEffectiveScale() / ui or 1
    local right, top = Overhang(frame)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local scale, area
    if WHOLE_SCREEN[frame:GetName() or ""] then
        scale = math.min(natural[frame] * parentScale, (W - 2 * EDGE) / (width + right), (H - 2 * EDGE) / (height + top))
        area = { left = EDGE, right = EDGE, top = EDGE, bottom = EDGE }
    else
        scale, area = Placement.Best(W, H, width + right, height + top, natural[frame] * parentScale)
    end
    busy = true
    if math.abs(frame:GetScale() - scale / parentScale) > 0.001 then frame:SetScale(scale / parentScale) end
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(-area.left / scale, area.right / scale + right, area.top / scale + top, -area.bottom / scale)
    busy = false
end

function Placement:Init()
    if ns.Windows and ns.Windows.Fit then
        original = ns.Windows.Fit
        ns.Windows.Fit = Fit
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    for frame in pairs(pending) do
        pending[frame] = nil
        Fit(frame)
    end
end)

ns.Placement = Placement
