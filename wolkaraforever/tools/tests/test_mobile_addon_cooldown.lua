-- The Interface mobile add-on's cooldowns (addons/WolkaraRoue/Actions.lua), run outside the
-- game: a spell on cooldown shows the time left and a grey icon until it is ready, the global
-- cooldown keeps only its sweep, and the text goes when the cooldown ends or is reset.
--
-- usage: luajit test_mobile_addon_cooldown.lua <path to Actions.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_cooldown.lua <Actions.lua>")

local now, ticker = 100, nil
GetTime = function() return now end
CreateFrame = function()
    local frame = {}
    function frame:SetScript(name, fn) self[name] = fn end
    ticker = ticker or frame
    return frame
end
InCombatLockdown = function() return false end

local cooldown = { start = 0, duration = 0, enabled = true }
local ns = {}
function ns.SpellCooldown() return cooldown.start, cooldown.duration, cooldown.enabled end
assert(loadfile(path))("WolkaraRoue", ns)

local button = {
    icon = { desaturated = false, SetDesaturated = function(self, on) self.desaturated = on end },
    timer = { text = "", SetText = function(self, text) self.text = text end },
    cooldown = { shown = false, SetCooldown = function(self, s, d) self.s, self.d = s, d end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end },
    GetEntry = function() return { kind = "spell", id = 42 } end,
}
local function Tick(seconds) now = now + seconds; ticker.OnUpdate(ticker, 0.2) end

-- The text: minutes, whole seconds, then tenths in the last three seconds.
assert(ns.CooldownText(75) == "2m" and ns.CooldownText(60) == "1m")
assert(ns.CooldownText(12.2) == "13" and ns.CooldownText(3) == "3")
assert(ns.CooldownText(2.44) == "2.4" and ns.CooldownText(0.05) == "0.1")

-- A ten-second cooldown, three seconds in: sweep, "7", grey icon; then it counts down and clears.
cooldown.start, cooldown.duration = 97, 10
ns.UpdateCooldown(button)
assert(button.cooldown.shown and button.cooldown.s == 97 and button.cooldown.d == 10)
assert(button.timer.text == "7" and button.icon.desaturated == true)
Tick(4.5)
assert(button.timer.text == "3.0" or button.timer.text == "2.5", button.timer.text)
Tick(3)
assert(button.timer.text == "" and button.icon.desaturated == false, "the cooldown did not clear")

-- The global cooldown keeps its sweep, without a number or grey.
cooldown.start, cooldown.duration = now, 1.5
ns.UpdateCooldown(button)
assert(button.cooldown.shown and button.timer.text == "" and button.icon.desaturated == false)

-- A cooldown reset by the game clears at once.
cooldown.start, cooldown.duration = now, 30
ns.UpdateCooldown(button)
assert(button.timer.text == "30" and button.icon.desaturated)
cooldown.start, cooldown.duration = 0, 0
ns.UpdateCooldown(button)
assert(not button.cooldown.shown and button.timer.text == "" and not button.icon.desaturated)
Tick(1)
assert(button.timer.text == "")

print("mobile add-on cooldowns: time left on the spell, grey until ready, global cooldown untouched, reset clears: PASS")
