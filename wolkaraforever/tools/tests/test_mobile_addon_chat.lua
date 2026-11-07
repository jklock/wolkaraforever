-- The Interface mobile add-on's chat (addons/WolkaraRoue/Chat.lua), run outside the game with
-- stand-ins for its frames. Its layout is measured on two screen widths: no tab runs into the
-- close button, no conversation chip runs off the panel (the 0.5 panel had both), the panel
-- stays between the sticks and the strip sits at the bottom, clear of the app's toolbar. The
-- quick tabs switch the strip between the players' talk and the system's messages; a whisper
-- counts as unread and becomes the Reply chip; F12 opens the game's input on the chosen
-- conversation; the game's input is invisible and takes no touch until it is typed in.
--
-- usage: luajit test_mobile_addon_chat.lua <path to Chat.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_chat.lua <Chat.lua>")

local W, H = 1000, 703
local frames = {}
local Mock = {}
Mock.__index = function(_, key) return Mock[key] or function() end end
local function New(kind, name, parent)
    local frame = setmetatable({ ftype = kind, name = name, parent = parent, shown = true, alpha = 1,
        width = 0, height = 0, points = {}, lines = {}, scripts = {}, hooks = {}, mouse = true }, Mock)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function Mock:SetSize(w, h) self.width, self.height = w, h end
function Mock:SetWidth(w) self.width = w end
function Mock:GetWidth() return self.width end
function Mock:ClearAllPoints() self.points = {} end
function Mock:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Mock:Show() self.shown = true end
function Mock:Hide() self.shown = false end
function Mock:SetShown(on) self.shown = on and true or false end
function Mock:IsShown() return self.shown end
function Mock:AddMessage(line) self.lines[#self.lines + 1] = line end
function Mock:Clear() self.lines = {} end
function Mock:SetText(text) self.text = text end
function Mock:GetText() return self.text end
function Mock:GetStringWidth() return #(self.text or "") * 7 end
function Mock:SetAlpha(a) self.alpha = a end
function Mock:SetScript(script, fn) self.scripts[script] = fn end
function Mock:GetScript(script) return self.scripts[script] end
function Mock:HookScript(script, fn) self.hooks[script] = fn end
function Mock:GetParent() return self.parent end
function Mock:SetParent(parent) self.parent = parent end
function Mock:EnableMouse(on) self.mouse = on end
function Mock:SetFrameStrata(strata) self.strata = strata end
function Mock:HasFocus() return rawget(self, "focus") end
function Mock:GetFont() return "font", 12, "" end
function Mock:CreateTexture() return New("Texture", nil, self) end

CreateFrame = function(kind, name, parent) return New(kind, name, parent) end
UIParent = New("Frame", "UIParent")
function UIParent:GetWidth() return W end
function UIParent:GetHeight() return H end
InCombatLockdown = function() return false end
ChatFontNormal = New("Font")
Ambiguate = function(name) return (name:match("^([^-]+)")) end
date = function() return "12:00 " end
ChatTypeInfo = {}
NUM_CHAT_WINDOWS = 2
ChatFrame1, ChatFrame2 = New("Frame", nil, UIParent), New("Frame", nil, UIParent)
local box = New("EditBox", "ChatFrame1EditBox", ChatFrame1)
ChatFrame1.editBox = box
DEFAULT_CHAT_FRAME = ChatFrame1
local opened
ChatFrame_OpenChat = function(text) opened = text end
local binding
ClearOverrideBindings = function() end
SetOverrideBindingClick = function(_, _, key, button) binding = { key, button } end

local handlers = {}
local ns = { STICK_X = 0.12, STICK_Y = 0.222, editing = false }
function ns.Register(_, module) return module end
function ns.On(event, fn) handlers[event] = fn end
function ns.Guard(_, fn, ...) return fn(...) end
function ns.Clamp(v, low, high) return math.max(low, math.min(high, v)) end
function ns.Box(frame) return New("Texture", nil, frame) end
function ns.EditFrame(frame) return New("Texture", nil, frame) end
function ns.Label(frame, _, text) local label = New("FontString", nil, frame); label.text = text; return label end
function ns.UIButton(parent, text, width, height, onClick)
    local button = New("Button", nil, parent)
    button:SetSize(width, height)
    button.back = New("Texture", nil, button)
    button.text = ns.Label(button, nil, text)
    button:SetScript("OnClick", onClick)
    return button
end
function ns.Movable(frame, store, key, default)
    function frame:PlaceSaved()
        local saved = store()[key]
        local d = saved and { saved.point, saved.relativePoint, saved.x, saved.y } or default()
        self:ClearAllPoints()
        self:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end
ns.db = { chat = { custom = true, fontSize = 16, tab = "talk" } }

assert(loadfile(path))("WolkaraRoue", ns)
local Chat = ns.Chat
Chat:Init()
local ticker, panel = WolkaraMobileChatTicker, WolkaraMobileChat
assert(ticker and panel)

-- Every button laid by Row: its left edge and width, from the anchor it was given.
local function Edge(button) local p = button.points[1]; return p[4], button.width, p[1] end
local function Buttons(parent, height)
    local list = {}
    for _, frame in ipairs(frames) do
        if frame.ftype == "Button" and frame.parent == parent and rawget(frame, "text") and frame.height == height then list[#list + 1] = frame end
    end
    return list
end
local function Check(label)
    Chat:Layout()
    local side = W * ns.STICK_X + H * 0.10
    assert(panel.width <= W - 2 * side + 1e-6 or panel.width <= W * 0.5 + 1e-6, label .. ": the panel runs under a stick")
    -- The close button, top right; the four tabs end before it.
    local close, tabs, chips = nil, {}, {}
    for _, button in ipairs(Buttons(panel, 36)) do
        local text = button.text.text
        if text == "X" then close = button
        elseif text == "Discussion" or text == "Privé" or text == "Système" or text == "Tout" then tabs[#tabs + 1] = button
        else chips[#chips + 1] = button end
    end
    assert(close and #tabs == 4 and #chips == 5, label .. ": the panel's buttons")
    local closeLeft = panel.width + close.points[1][4] - close.width
    for _, tab in ipairs(tabs) do
        local x, width, anchor = Edge(tab)
        assert(anchor == "TOPLEFT" and x + width <= closeLeft - 1e-6, label .. ": the tab " .. tab.text.text .. " runs into the close button")
        assert(tab.text.width <= width, label .. ": a tab's text is wider than the tab")
    end
    for _, chip in ipairs(chips) do
        local x, width, anchor = Edge(chip)
        assert(anchor == "BOTTOMLEFT" and x >= 8 and x + width <= panel.width - 8 + 1e-6, label .. ": the chip " .. chip.text.text .. " runs off the panel")
        assert(chip.text.width <= width)
    end
    -- The strip: at the bottom, above the app's toolbar, between the wheels' lowest spells.
    local p = ticker.points[1]
    assert(p[1] == "BOTTOM" and p[3] == "BOTTOM" and p[5] >= H * 0.10 and ticker.width <= W * 0.4, label .. ": the strip")
    local quick, hide = {}, nil
    for _, button in ipairs(Buttons(ticker, 28)) do
        if button.text.text == "Masquer" then hide = button else quick[#quick + 1] = button end
    end
    assert(#quick == 2 and hide, label .. ": the quick tabs and Masquer")
    local quickEnd = 0
    for _, button in ipairs(quick) do
        local x, width = Edge(button)
        assert(x >= 0 and x + width <= ticker.width and button.points[1][5] > 0, label .. ": a quick tab is off the strip")
        quickEnd = math.max(quickEnd, x + width)
    end
    -- Masquer, on the same row at the right, clear of the quick tabs; the unread count above it.
    local h = hide.points[1]
    assert(h[1] == "TOPRIGHT" and h[3] == "TOPRIGHT" and h[4] == 0 and h[5] == quick[1].points[1][5], label .. ": Masquer's row")
    assert(ticker.width - hide.width >= quickEnd + 1, label .. ": Masquer runs into the quick tabs")
    assert(hide.text.width <= hide.width, label .. ": Masquer's text is wider than its button")
end
Check("wide screen")
W = 760
Check("narrow screen")
W = 1000
Chat:Layout()
assert(binding[1] == "F12" and binding[2] == "WolkaraMobileChatOpener")

-- The game's input: kept, invisible and touch-free until typed in, laid on the strip.
local holder = box.parent
assert(holder ~= ChatFrame1 and holder.alpha == 0 and box.mouse == false and box.points[1][2] == ticker)
box.hooks.OnEditFocusGained(box)
assert(holder.alpha == 1, "the input does not show while typing")
box.hooks.OnEditFocusLost(box)
assert(holder.alpha == 0)
assert(ChatFrame2.parent ~= UIParent and ChatFrame2.parent.shown == false, "the game's chat is still on screen")

-- The quick tabs: talk and system, one touch apart.
local function Tap(label, parent)
    for _, frame in ipairs(frames) do
        if frame.ftype == "Button" and rawget(frame, "text") and frame.text.text == label and (not parent or frame.parent == parent) then
            return frame.scripts.OnClick(frame)
        end
    end
    error("no button " .. label)
end
handlers.CHAT_MSG_SAY("bonjour", "Ana-Realm")
handlers.CHAT_MSG_LOOT("Vous recevez le butin : [Étoffe de lin].")
assert(#ticker.lines == 1 and ticker.lines[1]:find("bonjour"), "the talk strip shows the loot")
Tap("Système", ticker)
assert(ns.db.chat.tab == "system" and #ticker.lines == 1 and ticker.lines[1]:find("butin"), "the system strip")
Tap("Discussion", ticker)
assert(#ticker.lines == 1 and ticker.lines[1]:find("bonjour"))
-- The add-on's own messages show on both.
ns.ChatAdd("Mobile : réglages enregistrés.")
assert(ticker.lines[#ticker.lines]:find("réglages"))

-- A whisper: counted, and the Reply chip names who to answer.
handlers.CHAT_MSG_WHISPER("tu viens ?", "Bob-Realm")
local badgeText
for _, frame in ipairs(frames) do
    if frame.ftype == "FontString" and frame.parent == ticker and rawget(frame, "text") and frame.text:find("privé") then badgeText = frame.text end
end
assert(badgeText == "1 nouveau privé", tostring(badgeText))
local reply
for _, button in ipairs(Buttons(panel, 36)) do if button.text.text == "À Bob" then reply = button end end
assert(reply, "the Reply chip does not name Bob")

-- F12, sent by the app before a line: the input opens on the chosen conversation.
WolkaraMobileChatOpener.scripts.OnClick()
assert(opened == "/s ", "Say is not the default")
Tap("Groupe", panel)
WolkaraMobileChatOpener.scripts.OnClick()
assert(opened == "/p ")
reply.scripts.OnClick(reply)
WolkaraMobileChatOpener.scripts.OnClick()
assert(opened == "/w Bob-Realm ")

-- Touching the strip opens the panel on the same tab; the cross closes it.
ticker.scripts.OnMouseUp(ticker)
assert(panel.shown and not ticker.shown and #WolkaraMobileChatList.lines >= 2)
Tap("X", panel)
assert(not panel.shown and ticker.shown)

-- Masquer: the strip goes, and a chat button waits just left of the app's keyboard - the folded
-- toolbar is 96 x 34 pt, centred, 42 pt up a 669 pt screen, its keyboard on the left - level
-- with it. It counts what the players say meanwhile, not the loot.
local mini = Chat.mini
assert(mini and not mini.shown, "the chat button shows while the chat is on screen")
Tap("Masquer", ticker)
assert(ns.db.chat.hidden == true and not ticker.shown and not panel.shown and mini.shown, "Masquer did not hide the chat")
local spot = mini.points[1]
assert(spot[1] == "BOTTOMRIGHT" and spot[2] == UIParent and spot[3] == "BOTTOM", "the chat button's anchor")
local keyboardLeft = W / 2 - 48 / 669 * H
local right = W / 2 + spot[4]
assert(right <= keyboardLeft - 1 and right >= keyboardLeft - 20, "the chat button is not just left of the keyboard")
assert(math.abs(spot[5] - 42 / 669 * H) < 0.5 and math.abs(mini.height - 34 / 669 * H) < 0.5, "the chat button is not level with the toolbar")
local count
for _, frame in ipairs(frames) do
    if frame.ftype == "FontString" and frame.parent == mini and frame ~= mini.text then count = frame end
end
handlers.CHAT_MSG_SAY("encore là ?", "Ana-Realm")
handlers.CHAT_MSG_LOOT("Vous recevez le butin : [Étoffe de laine].")
handlers.CHAT_MSG_WHISPER("ohé", "Bob-Realm")
assert(count and count.text == "2", "the chat button counts " .. tostring(count and count.text))
-- It stays hidden through a layout; Customise shows the strip to move it, then hides it again.
Chat:Layout()
assert(not ticker.shown and mini.shown)
ns.editing = true; Chat:SetEditing(true)
assert(ticker.shown and not mini.shown, "Customise cannot reach the hidden strip")
ns.editing = false; Chat:SetEditing(false)
assert(not ticker.shown and mini.shown)
-- Writing still works, and touching the bubble brings the strip back, up to date, count cleared.
WolkaraMobileChatOpener.scripts.OnClick()
assert(opened == "/w Bob-Realm ")
mini.scripts.OnClick(mini)
assert(ns.db.chat.hidden == false and ticker.shown and not mini.shown and count.text == "")
assert(ticker.lines[#ticker.lines]:find("ohé"), "the strip missed what was said while hidden")

print("mobile add-on chat: no tab or chip overflows on two widths, panel between the sticks, strip at the bottom, talk/system one touch apart, whisper counted and answered, F12 on the chosen conversation, input hidden until typed in, Masquer leaves a counting button left of the keyboard: PASS")
