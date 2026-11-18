-- iPad run 5 (IMG_0012): the Mount button's macro printed "Type '/help' for a listing of a few commands." as the
-- raptor came: this client's chat had no /stopmacro. Every macro line TouchPlay writes must start with a command
-- the client knows.
--
-- This client's UI source (/tmp/wowui) ships Blizzard_ChatFrameBase with only its .toc (Shared\SlashCommands.lua
-- and Shared\SlashCommandsRegistry.lua are listed there, not present), so the command list cannot be read from it.
-- KNOWN holds the commands TouchPlay uses, each with what is known; a new command means adding it here with its
-- evidence (and an in-game check in docs/checks/2026-11-13-addon-screens.md).
dofile("tests/stub.lua")

local KNOWN = {
    run = "seen working on the iPad: the Mount button's /run summoned the raptor (run 5)",
    click = "the game's own secure /click (SecureTemplates use it); TouchPlay's Menu tiles",
    targetexact = "standard secure command; in-game check",
    targetenemy = "standard secure command (Next target); in-game check",
    dismount = "standard secure command; in-game check",
    leavevehicle = "standard secure command; in-game check",
    reload = "standard command (also /console reloadui); in-game check",
    logout = "standard command; in-game check",
    petautocasttoggle = "standard secure command; in-game check",
}
local MISSING = { stopmacro = "IMG_0012: unknown to this client's chat" }

-- The command at the start of each line of `macro` (nil for a blank line).
local function Commands(macro)
    local out = {}
    for line in (macro .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("%S") then out[#out + 1] = line:match("^%s*/(%a+)") or ("<not a command: " .. line .. ">") end
    end
    return out
end

local function Check(macro, where)
    for _, command in ipairs(Commands(macro)) do
        local lower = command:lower()
        assert(not MISSING[lower], where .. ": /" .. command .. " is not in this client (" .. tostring(MISSING[lower]) .. ")")
        assert(KNOWN[lower], where .. ": /" .. command .. " is not a known command: " .. macro)
    end
end

T("every_macro_line_starts_with_a_known_command", function()
    -- every macrotext any frame is given, while the add-on runs through its states
    local seen = {}
    local set = Stub.Frame.SetAttribute
    Stub.Frame.SetAttribute = function(self, key, value)
        if type(key) == "string" and key:lower():find("macrotext") and type(value) == "string" then
            seen[#seen + 1] = { value, tostring(self.GetName and self:GetName() or "?") .. "." .. key }
        end
        return set(self, key, value)
    end
    Stub.reset(); Stub.loadAll(); Stub.login()
    Stub.fire("PLAYER_ENTERING_WORLD")
    ns.Each("Layout")
    if ns.Interact.PinMount then pcall(ns.Interact.PinMount, 35) end
    Stub.Frame.SetAttribute = set
    assert(#seen >= 5, "macros were seen: " .. #seen)
    for _, s in ipairs(seen) do Check(s[1], s[2]) end
    -- the Mount button's, pinned or not
    Check(ns.Interact.MountMacro(nil), "MountMacro(nil)")
    Check(ns.Interact.MountMacro(35), "MountMacro(35)")
    assert(#Commands(ns.Interact.MountMacro(35)) == 1, "one line")
    assert(ns.Interact.MountMacro(35):find("InCombatLockdown", 1, true), "does nothing in a fight")
end)

-- The macros made only on a tap (the info card's secure actions, the Menu's tiles) are in the source as strings:
-- every string that starts a macro is checked too.
T("every_macro_string_in_the_source_starts_with_a_known_command", function()
    local found = 0
    for _, file in ipairs({ "Cluster", "ClassBars", "Contract", "Hud", "InfoCard", "Interact", "Menu", "Perf",
        "Loot", "Picker", "ItemRail", "Units", "Corpse", "Popups", "Feel", "Guide", "Chat", "Hold", "Signal" }) do
        local f = assert(io.open("addon/TouchPlay/" .. file .. ".lua")); local text = f:read("*a"); f:close()
        for line in text:gmatch("[^\n]+") do
            local code = line:gsub("%-%-.*$", "")
            if code:find("macrotext") or code:find("macro%s*=") or code:find("secure%s*=") then
                for command in code:gmatch("\"/(%a+)") do
                    found = found + 1
                    Check("/" .. command, file .. ".lua: " .. line)
                end
            end
        end
    end
    assert(found >= 8, "macro strings were found: " .. found)
end)

Stub.done("macros")
