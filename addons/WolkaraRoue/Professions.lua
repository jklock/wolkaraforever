-- Profession spells offered in the slot picker.
local _, ns = ...

local IDS = {
    7620, 7731, 7732, 18248,
    2550, 3102, 3413, 18260, 818,
    3273, 3274, 7924, 10846,
    2383, 2580, 2656,
    2259, 3101, 3464, 11611,
    2018, 3100, 3538, 9785,
    7411, 7412, 7413, 13920, 13262,
    4036, 4037, 4038, 12656,
    2108, 3104, 3811, 10662,
    3908, 3909, 3910, 12180,
    25229, 31252, 45357, 51005,
    1804,
}

local function Info(id)
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then name, icon = info.name, info.iconID end
    elseif GetSpellInfo then
        local n, _, i = GetSpellInfo(id)
        name, icon = n, i
    end
    return name, icon
end

local function Known(id)
    if IsPlayerSpell then return IsPlayerSpell(id) end
    if IsSpellKnown then return IsSpellKnown(id) end
    return false
end

function ns.ProfessionSpells()
    local list, seen = {}, {}
    local function add(id, name, icon)
        if not id or not name or seen[name] then return end
        if IsPassiveSpell and IsPassiveSpell(id) then return end
        seen[name] = true
        list[#list + 1] = { kind = "spell", id = id, name = name, icon = icon }
    end
    if GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for _, index in ipairs({ GetProfessions() }) do
            if index then
                local _, _, _, _, count, offset = GetProfessionInfo(index)
                for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive then add(item.spellID, item.name, item.iconID) end
                end
            end
        end
    end
    for i = #IDS, 1, -1 do
        local id = IDS[i]
        if Known(id) then
            local name, icon = Info(id)
            add(id, name, icon)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
