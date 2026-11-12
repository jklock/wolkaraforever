-- Interface mobile : l'habillage des panneaux. Fond sombre et bordure bronze arrondie, celle
-- des bulles d'aide du jeu, plutôt qu'un aplat noir : le menu et les réglages se détachent
-- mieux du jeu et se lisent plus vite (idée de scarrdi94, jklock/wolkaraforever#26).

local _, ns = ...

local BRONZE = { 0.54, 0.43, 0.23, 0.95 }
local EDGE = { 0.36, 0.29, 0.20, 0.9 }

-- kind : "panel" (menu, réglages, menu rapide) ou "card" (cadres plus légers).
function ns.Surface(frame, kind, pad)
    if not frame or frame.wmSurface then return frame and frame.wmSurface end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local skin = CreateFrame("Frame", nil, frame, template)
    pad = pad or 0
    skin:SetPoint("TOPLEFT", -pad, pad)
    skin:SetPoint("BOTTOMRIGHT", pad, -pad)
    skin:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    if skin.SetBackdrop then
        skin:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
            edgeSize = kind == "panel" and 16 or 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        skin:SetBackdropColor(0.07, 0.06, 0.05, kind == "panel" and 0.94 or 0.82)
        local edge = kind == "panel" and BRONZE or EDGE
        skin:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
        -- L'ancien aplat du cadre, dessous, n'a plus lieu d'être.
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND" then region:SetAlpha(0) end
            end
        end
    end
    frame.wmSurface = skin
    return skin
end
