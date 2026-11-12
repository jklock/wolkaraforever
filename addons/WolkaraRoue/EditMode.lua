-- Slot edit mode: tap a slot, then a spell.
local _, ns = ...

local Edit = ns.Register("Edit mode", {})
local bar, ring

local function Dock()
    local picker = _G.WolkaraMobilePicker
    if not picker then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    picker:SetScale(1)
    local scale = math.min(1, (W * 0.54) / picker:GetWidth(), (H * 0.80) / picker:GetHeight())
    picker:SetScale(scale)
    picker:ClearAllPoints()
    picker:SetPoint("LEFT", UIParent, "LEFT", (W * 0.10) / scale, -(H * 0.03) / scale)
end

local function Mark(slot)
    if not (slot and slot.GetCenter) then ring:Hide(); return end
    ring:ClearAllPoints()
    ring:SetSize(slot:GetWidth() + 14, slot:GetHeight() + 14)
    ring:SetPoint("CENTER", slot, "CENTER")
    ring:Show()
end

function ns.EnterEditMode(slot)
    if InCombatLockdown() then ns.Print(ns.T("customize out of combat.")); return end
    ns.editMode = true
    ns.slotEditing = true
    local quick = ns.db and ns.db.quick
    if type(quick) == "table" and quick.enabled ~= false and not quick.open then
        quick.open = true
        ns.editOpenedQuick = true
    end
    ns.Layout(); ns.Refresh()
    slot = slot or (ns.FanFirstSlot and ns.FanFirstSlot())
    if slot and ns.Picker then ns.Picker:Open(slot) end
end

function ns.ExitEditMode()
    ns.editMode = false
    ring:Hide(); bar:Hide()
    if ns.Picker then ns.Picker:Close() end
    ns.slotEditing = false
    if ns.editOpenedQuick then
        ns.editOpenedQuick = nil
        if ns.db and type(ns.db.quick) == "table" then ns.db.quick.open = false end
    end
    if InCombatLockdown() then return end
    ns.Layout(); ns.Refresh()
    if ns.SavePending and ns.SavePending() and ns.db and ReloadUI then
        ns.db.justSaved = true
        ns.Print(ns.T("saving your settings: the interface is reloading."))
        ReloadUI()
    end
end

function Edit:Init()
    bar = CreateFrame("Frame", "WolkaraMobileEditBar", UIParent)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetSize(520, 46)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -44)
    bar:EnableMouse(true)
    ns.Box(bar, "BACKGROUND", 0.05, 0.05, 0.08, 0.92)
    local hint = ns.Label(bar, "GameFontHighlight", ns.T("Edit mode: tap a slot, then a spell."))
    hint:SetPoint("LEFT", 14, 0)
    local done = ns.UIButton(bar, ns.T("Save & Exit"), 150, 36, function() ns.ExitEditMode() end)
    done:SetPoint("RIGHT", -6, 0)
    done.back:SetVertexColor(0.2, 0.45, 0.25, 0.95)
    bar:Hide()

    ring = CreateFrame("Frame", nil, UIParent)
    ring:SetFrameStrata("MEDIUM")
    ring:EnableMouse(false)
    local glow = ns.Disc(ring, "OVERLAY", 1, 0.82, 0.25, 0.55, 0)
    glow:SetBlendMode("ADD")
    ring:Hide()

    if ns.Picker then
        hooksecurefunc(ns.Picker, "Open", function(_, slot)
            if not ns.editMode then return end
            Dock(); Mark(slot)
        end)
        hooksecurefunc(ns.Picker, "Close", function() ring:Hide() end)
    end
    local picker = _G.WolkaraMobilePicker
    if picker then
        picker:HookScript("OnHide", function()
            if ns.editMode and not InCombatLockdown() then ns.ExitEditMode() end
        end)
    end
end

function Edit:SetEditing(on)
    if on or not bar then return end
    ns.editMode = false
    ring:Hide(); bar:Hide()
    if ns.FanLockIcon then ns.FanLockIcon() end
end

function Edit:CombatStarts()
    if bar then ns.editMode = false; ring:Hide(); bar:Hide() end
end
