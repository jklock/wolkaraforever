-- Task 15: the rules the add-on keeps, checked on the source itself (rule 7: nothing acts from an event;
-- performance: no OnUpdate except the animation clock and the popups' time bar).
-- This file's own folder, so neither the stub nor the add-on is looked for relative to where the test was started.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
dofile(HERE .. "/stub.lua")

-- The add-on's folder, found from the same place.
local DIR = HERE .. "/../addon/TouchPlay/"

local function files()
    local list = {}
    local p = io.popen('ls "' .. DIR .. '"')
    for name in p:lines() do
        if name:match("%.lua$") then list[#list + 1] = name end
    end
    p:close()
    table.sort(list)
    assert(#list > 20, "the add-on files were found in " .. DIR)
    return list
end

-- The file's code with the comments taken out and every line kept (so line numbers stay true). Strings stay:
-- a banned name inside a string ("CastSpell", _G["TargetUnit"], Func("C_Container", "UseContainerItem")) is as
-- good as the call itself.
local function Code(text)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", function(s) return (s:gsub("[^\n]", "")) end)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        -- a "--" outside a string starts a comment
        local result, inString, i = {}, nil, 1
        while i <= #line do
            local c = line:sub(i, i)
            if inString then
                result[#result + 1] = c
                if c == "\\" then result[#result + 1] = line:sub(i + 1, i + 1); i = i + 1
                elseif c == inString then inString = nil end
            elseif c == '"' or c == "'" then
                inString = c; result[#result + 1] = c
            elseif c == "-" and line:sub(i + 1, i + 1) == "-" then
                break
            else
                result[#result + 1] = c
            end
            i = i + 1
        end
        out[#out + 1] = table.concat(result)
    end
    return out
end

local function read(name)
    local f = assert(io.open(DIR .. name))
    local text = f:read("*a")
    f:close()
    return text
end

-- Where each top-level function starts and ends: a `function Name` or `local function Name` at column 0 runs to the
-- first line that starts with `end` at column 0 (or to its own line when it is closed there). Returns a list of
-- { name =, first =, last = }. A line in none of them is "file level".
local function Functions(lines)
    local list, open = {}, nil
    for n, line in ipairs(lines) do
        if not open then
            local name = line:match("^local function ([%w_%.:]+)") or line:match("^function ([%w_%.:]+)")
            if name then
                open = { name = name, first = n }
                if line:match("%f[%w]end%s*$") and line:find("%(.-%)") and line:match("%)%s.*end%s*$") then
                    open.last = n
                    list[#list + 1] = open; open = nil
                end
            end
        elseif line:match("^end%f[%W]") then
            open.last = n
            list[#list + 1] = open; open = nil
        end
    end
    if open then open.last = #lines; list[#list + 1] = open end
    return list
end

local function Enclosing(functions, n)
    for _, f in ipairs(functions) do
        if n >= f.first and n <= f.last then return f end
    end
    return nil
end

-- Actions the game only allows from a click or a key (TargetUnit, UseContainerItem and the like are restricted even
-- from a tap when our own code calls them: those run on secure buttons). They may be written only where a tap runs them.
local BANNED = {
    "TargetUnit", "FocusUnit", "AssistUnit", "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction",
    "UseContainerItem", "UseItemByName", "RunMacroText", "InteractUnit", "LootSlot", "JumpOrAscendStart",
    "PickupAction", "PlaceAction", "CancelUnitBuff",
}

-- file -> name -> the functions that may hold it. Each is a tap handler: it runs from a click on a button, and its
-- body must not register an event, a timer or a hook (checked below), so nothing in it can run from one.
local ALLOWED = {
    ["Loot.lua"] = { LootSlot = { ["Loot.TakeAll"] = true, ["Loot.TakeMoney"] = true } },
    -- the picker's put and remove taps
    ["Picker.lua"] = { PlaceAction = { ["Picker.Put"] = true }, PickupAction = { ["Picker.Remove"] = true } },
    -- the card's Sell (a merchant is open) and Cancel buff buttons
    ["InfoCard.lua"] = { UseContainerItem = { ItemButtons = true }, CancelUnitBuff = { AuraButtons = true } },
}

-- Nothing in an allowed function's body may arrange for code to run later or on an event.
local FORBIDDEN_IN_BODY = { "ns%.On%(", "RegisterEvent", "RegisterUnitEvent", "RegisterAllEvents", "C_Timer", "HookScript",
    'SetScript%("OnEvent"' }

-- JumpOrAscendStart is only ever hooked (the game's own jump calls our hook afterwards), never called: a line may name
-- it only as hooksecurefunc's target or in an existence check.
local function ExemptLine(name, line)
    if name ~= "JumpOrAscendStart" then return false end
    local rest = line:gsub('hooksecurefunc%(%s*["\']JumpOrAscendStart["\']', ""):gsub("if JumpOrAscendStart then", "")
    return not rest:find("%f[%w_]JumpOrAscendStart%f[^%w_]")
end

-- The problems in one file's source (a list of strings; empty when the file is clean). `seen` collects the allowances used.
local function Check(file, text, seen)
    local problems = {}
    local lines = Code(text)
    local functions = Functions(lines)
    for n, line in ipairs(lines) do
        for _, name in ipairs(BANNED) do
            if line:find("%f[%w_]" .. name .. "%f[^%w_]") and not ExemptLine(name, line) then
                local f = Enclosing(functions, n)
                local where = f and f.name or "(file level)"
                local allowed = f and ALLOWED[file] and ALLOWED[file][name] and ALLOWED[file][name][f.name]
                if not allowed then
                    problems[#problems + 1] = ("%s:%d uses %s in %s: actions come only from a tap on a button or a key"):format(file, n, name, where)
                else
                    if seen then seen[file .. ":" .. name .. ":" .. f.name] = true end
                    for i = f.first, f.last do
                        for _, pattern in ipairs(FORBIDDEN_IN_BODY) do
                            if lines[i]:find(pattern) then
                                problems[#problems + 1] = ("%s:%d: %s holds %s, so its body must not arrange code to run later (%s)")
                                    :format(file, i, f.name, name, (pattern:gsub("%%", "")))
                            end
                        end
                    end
                end
            end
        end
    end
    return problems
end

T("rule7_no_action_from_events", function()
    local seen, all = {}, {}
    for _, file in ipairs(files()) do
        for _, problem in ipairs(Check(file, read(file), seen)) do all[#all + 1] = problem end
    end
    assert(#all == 0, table.concat(all, "\n"))
    -- the allowances are not left standing for code that is gone
    for file, names in pairs(ALLOWED) do
        for name, functions in pairs(names) do
            for fn in pairs(functions) do
                assert(seen[file .. ":" .. name .. ":" .. fn], ("the allowance %s %s in %s is no longer used: remove it"):format(file, name, fn))
            end
        end
    end
    assert(not ALLOWED["InfoCard.lua"].TargetUnit, "TargetUnit runs on a secure button (R35): no allowance")
end)

T("rule7_the_check_catches_an_action_run_from_an_event", function()
    local source = table.concat({
        "function Loot.TakeAll()",
        "    for slot = 1, 3 do LootSlot(slot) end",
        "end",
        "",
        'ns.On("LOOT_OPENED", function()',
        "    LootSlot(1)",
        "end)",
    }, "\n")
    local problems = Check("Loot.lua", source)
    assert(#problems == 1 and problems[1]:find("Loot.lua:6 uses LootSlot in (file level)", 1, true), table.concat(problems, "|"))
    -- the same call is fine in the tap handler alone
    assert(#Check("Loot.lua", "function Loot.TakeAll()\n    LootSlot(1)\nend\n") == 0)
    -- a closure that registers an event inside the allowed handler is refused by its body
    local inside = table.concat({
        "function Loot.TakeAll()",
        '    ns.On("LOOT_OPENED", function() LootSlot(1) end)',
        "end",
    }, "\n")
    local bad = Check("Loot.lua", inside)
    assert(#bad >= 1 and bad[1]:find("must not arrange code", 1, true), table.concat(bad, "|"))
    -- a timer, a hook or an OnEvent script inside it is refused as well
    for _, line in ipairs({ "C_Timer.After(1, function() LootSlot(1) end)", 'frame:HookScript("OnShow", function() LootSlot(1) end)',
        'frame:SetScript("OnEvent", function() LootSlot(1) end)', 'frame:RegisterEvent("X"); LootSlot(1)',
        'frame:RegisterUnitEvent("UNIT_HEALTH", "player"); LootSlot(1)', "frame:RegisterAllEvents(); LootSlot(1)" }) do
        assert(#Check("Loot.lua", "function Loot.TakeAll()\n    " .. line .. "\nend\n") >= 1, line)
    end
    -- another function in the same file does not get the allowance
    assert(#Check("Loot.lua", "function Loot.Other()\n    LootSlot(1)\nend\n") == 1)
    -- another file does not either
    assert(#Check("Hud.lua", "function Loot.TakeAll()\n    LootSlot(1)\nend\n") == 1)
end)

T("rule7_names_in_strings_count_and_comments_do_not", function()
    local quoted = Code('local x = "InteractUnit" -- note')
    assert(quoted[1]:find("InteractUnit") and not quoted[1]:find("note"))
    assert(#Check("Hud.lua", 'local f = _G["TargetUnit"]\n') == 1, "_G[...] is caught")
    assert(#Check("Hud.lua", 'local f = Func("C_Container", "UseContainerItem")\n') == 1, "Func(...) is caught")
    assert(#Check("Hud.lua", "-- CastSpell is not allowed here\nlocal x = 1\n") == 0, "a comment is not code")
    assert(#Check("Hud.lua", "--[[ TargetUnit\n FocusUnit ]]\nlocal x = 1\n") == 0, "a block comment either")
    assert(#Check("Hud.lua", "local x = CastSpellByName2\n") == 0, "a longer name is its own name")
    for _, name in ipairs({ "TargetUnit", "FocusUnit", "AssistUnit", "CastSpell", "CastSpellByName", "CastSpellByID",
        "UseAction", "UseContainerItem", "UseItemByName", "RunMacroText", "InteractUnit", "LootSlot", "PickupAction",
        "PlaceAction", "CancelUnitBuff" }) do
        assert(#Check("Hud.lua", "local function OnEvent()\n    " .. name .. "(1)\nend\n") == 1, name)
    end
end)

T("rule7_jump_is_only_hooked_never_called", function()
    assert(#Check("Interact.lua", 'if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", OnJumpPressed) end\n') == 0)
    assert(#Check("Interact.lua", "local function Go()\n    JumpOrAscendStart()\nend\n") == 1)
    assert(#Check("Interact.lua", 'hooksecurefunc("JumpOrAscendStart", f); JumpOrAscendStart()\n') == 1)
end)

T("no_reload_from_insecure_code", function()
    for _, file in ipairs(files()) do
        for n, line in ipairs(Code(read(file))) do
            if line:find("%f[%w_]ReloadUI%f[^%w_]") then
                error(("%s:%d calls ReloadUI: reload through a secure /reload macro button"):format(file, n))
            end
        end
    end
end)

T("onupdate_only_in_the_clock_and_the_time_bar", function()
    local allowed = { ["Perf.lua"] = true, ["Popups.lua"] = true }
    for _, file in ipairs(files()) do
        for n, line in ipairs(Code(read(file))) do
            if line:find("OnUpdate") and not allowed[file] then
                error(("%s:%d uses OnUpdate: only the animation clock (Perf.lua) and the popups' time bar may"):format(file, n))
            end
        end
    end
end)

T("toc_order_perf_before_contract_contract_last", function()
    local order = {}
    for line in io.lines(DIR .. "TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then order[#order + 1] = line end
    end
    assert(order[#order] == "Contract.lua", "Contract.lua stays last: " .. order[#order])
    local perf
    for i, name in ipairs(order) do if name == "Perf.lua" then perf = i end end
    assert(perf and perf < #order, "Perf.lua is listed before Contract.lua")
end)

Stub.done("rules")
