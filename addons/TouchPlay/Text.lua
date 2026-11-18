-- TouchPlay: every word the player reads.
--
-- Every user-facing string lives in ns.L (English only for now, sentence case, no em dashes)
-- and is read with ns.T(key, ...). A key nobody wrote down shows as the key itself, so a gap
-- is easy to see on screen, and is kept once in TouchPlayDB.missingText for the Mac to read.

local ADDON_NAME, ns = ...

ns.L = {
    ["common.close"] = "Close",
    ["common.cancel"] = "Cancel",
    ["common.more"] = "More",
    ["common.afterFight"] = "After the fight",
}

-- Returns the text for key. Extra arguments go through string.format; without any, the text
-- is returned as written, so a literal "%" in it is safe.
function ns.T(key, ...)
    local text = ns.L[key]
    if text == nil then
        local db = TouchPlayDB
        if type(db) == "table" then
            if type(db.missingText) ~= "table" then db.missingText = {} end
            local list = db.missingText
            local known = false
            for i = 1, #list do
                if list[i] == key then known = true; break end
            end
            if not known then list[#list + 1] = key end
        end
        return key
    end
    if select("#", ...) == 0 then return text end
    local ok, formatted = pcall(string.format, text, ...)
    if ok then return formatted end
    return text
end
