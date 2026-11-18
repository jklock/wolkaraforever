-- TouchPlay: the chat strip (mockups 01, 81, 82).
--
-- The last three rows the game's own chat window got (DEFAULT_CHAT_FRAME's AddMessage is hooked,
-- so colours and links are the game's), a strip under them that says where you are talking
-- ("Say: tap to type"), and a pink "Reply to Mira" badge when a whisper comes in.
--
--   * a long line wraps with a 22 unit indent on its second and later rows;
--   * 20 seconds with nothing new: the lines fade to alpha 0.25 (one timer, started again by
--     every new line, cancelled with the screen); a new line brings them back;
--   * the strip follows the last channel used: the chat edit box's sticky type (the game keeps
--     it there), looked at again when the box closes and when a line arrives;
--   * a tap opens the game's chat input (not protected, so it works in a fight); a hold (a long
--     press, or the right click the hold key would send) says "Coming in a later version";
--   * the app's "Send" key types a bare F12 first: Contract.KeepKey binds F12 to the game's
--     OPENCHAT command (Bindings_*.xml: ChatFrameUtil.OpenChat("")) and keeps it through a
--     pause and when the add-on is Off, so typed chat never goes nowhere.
--
-- The game's own chat window is hidden by alpha with its mouse off (never reparented: R27), so
-- the strip is the only chat on screen. Its edit box goes dark with the window while nobody types
-- (the iPad run showed it as a separate empty bar otherwise); while it has focus it ignores the
-- parent's alpha and sits on the strip, and it goes back to its own place when focus leaves.
-- Everything is given back exactly as it was on a pause, Off and in Edit Mode.
--
-- Chat text and sender names can be hidden in some places: such a line is passed straight to
-- SetText, never measured, compared or joined.

local ADDON_NAME, ns = ...

local Chat = ns.Register("Chat", {})
local Kit = ns.Kit

ns.L["chat.tapToType"] = "tap to type"
ns.L["chat.say"] = "Say"
ns.L["chat.party"] = "Party"
ns.L["chat.guild"] = "Guild"
ns.L["chat.officer"] = "Officer"
ns.L["chat.raid"] = "Raid"
ns.L["chat.raidWarning"] = "Raid warning"
ns.L["chat.instance"] = "Instance"
ns.L["chat.yell"] = "Yell"
ns.L["chat.emote"] = "Emote"
ns.L["chat.channel"] = "Channel"
ns.L["chat.whisperBare"] = "Whisper"
ns.L["chat.whisper"] = "Whisper %s"
ns.L["chat.reply"] = "Reply to %s"
ns.L["chat.replyAny"] = "Reply"
ns.L["chat.later"] = "Coming in a later version"

-- ---------------------------------------------------------------------------------------
-- Numbers from the mockups (layout units, 1366 x 1024)

local LINES_X, LINES_BOTTOM, LINES_W = 300, 84, 560
local ROWS, ROW_H, FONT = 3, 22, 18
local INDENT = 22
local STRIP_X, STRIP_Y, STRIP_W, STRIP_H = 296, 948, 568, 52
local STRIP_GAP = 6
local FADE_SECONDS, FADE_ALPHA = 20, 0.25
local LATER_SECONDS = 2
local DEFAULT_HOLD = 0.45
local REF_W, REF_H = 1366, 1024
local PINK = { 1, 0.5, 0.9 }

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

-- ---------------------------------------------------------------------------------------
-- The lines

local lines = CreateFrame("Frame", nil, ns.root)
lines:SetSize(LINES_W, ROWS * ROW_H)
lines:EnableMouse(false)
Chat.lines = lines

local rows = {}
for i = 1, ROWS do
    local bar = lines:CreateTexture(nil, "BACKGROUND")
    bar:SetColorTexture(PINK[1], PINK[2], PINK[3], 0.2)
    bar:SetSize(LINES_W, ROW_H)
    bar:SetPoint("TOPLEFT", lines, "TOPLEFT", 0, -(i - 1) * ROW_H)
    bar:Hide()
    local fs = lines:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, Kit.FONT_TITLE, FONT, "")
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", lines, "TOPLEFT", 0, -(i - 1) * ROW_H)
    fs:SetSize(LINES_W, ROW_H)
    fs.bar, fs.indent = bar, 0
    rows[i] = fs
end
Chat.rows = rows

-- The ruler measures a piece of text; it is never shown.
local ruler = lines:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(ruler, Kit.FONT_TITLE, FONT, "")
ruler:Hide()

local function Width(text)
    ruler:SetText((text:gsub("\1", " ")))
    return ruler:GetStringWidth()
end

-- The colour code still open at the end of a row ("|cAARRGGBB" not yet closed by "|r").
local function OpenColour(text)
    local open
    for at, kind in text:gmatch("()|([cr])") do
        if kind == "c" then open = text:sub(at, at + 9) else open = nil end
    end
    return open
end

-- A link's spaces are kept together while the text is cut into words.
local function Protect(link) return (link:gsub(" ", "\1")) end

-- Cuts entry.text into rows that fit: the first LINES_W wide, the others indented. A colour that
-- is still open at the end of a row starts the next one.
local function Wrap(entry)
    local text = entry.text:gsub("|H.-|h.-|h", Protect)
    local rowsOut, n, current = entry.rows, 0, nil
    for word in text:gmatch("%S+") do
        local candidate = current and (current .. " " .. word) or word
        local limit = n == 0 and LINES_W or LINES_W - INDENT
        if current and Width(candidate) > limit then
            n = n + 1
            rowsOut[n] = (current:gsub("\1", " "))
            current = (OpenColour(current) or "") .. word
        else
            current = candidate
        end
    end
    n = n + 1
    rowsOut[n] = current and (current:gsub("\1", " ")) or ""
    entry.n = n
end

-- Oldest first; the three newest messages are kept, each as one reused table.
local entries = {
    { rows = {}, n = 0 }, { rows = {}, n = 0 }, { rows = {}, n = 0 },
}
local count = 0
local slotEntry, slotRow = {}, {}       -- what each of the three screen rows shows

local function Paint()
    local need = ROWS
    for i = 1, ROWS do slotEntry[i], slotRow[i] = nil, nil end
    for index = 3, 4 - count, -1 do
        local entry = entries[index]
        for k = entry.n, 1, -1 do
            if need == 0 then break end
            slotEntry[need], slotRow[need] = entry, k
            need = need - 1
        end
        if need == 0 then break end
    end
    for i = 1, ROWS do
        local fs, entry, k = rows[i], slotEntry[i], slotRow[i]
        if entry then
            local indent = k == 1 and 0 or INDENT
            if fs.indent ~= indent then
                fs.indent = indent
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", lines, "TOPLEFT", indent, -(i - 1) * ROW_H)
                fs:SetWidth(LINES_W - indent)
            end
            local text = entry.rows[k]
            if not Plain(text) or fs.shownText ~= text then
                fs.shownText = Plain(text) and text or nil
                fs:SetText(text)
            end
            fs:SetTextColor(entry.r, entry.g, entry.b)
            fs.entry, fs.k = entry, k
            fs.bar:SetShown(entry.whisper)
            fs:Show()
        else
            fs.entry, fs.shownText = nil, nil
            fs:SetText("")
            fs.bar:Hide()
            fs:Hide()
        end
    end
end

-- Forgets the kept lines (a fresh start for the tests).
function Chat.Clear()
    count = 0
    Paint()
end

-- What the three rows show, top to bottom (for the tests and the report).
function Chat.Visible()
    local list = {}
    for i = 1, ROWS do
        local entry, k = slotEntry[i], slotRow[i]
        if entry then
            list[#list + 1] = { text = entry.rows[k], indent = k == 1 and 0 or INDENT,
                r = entry.r, g = entry.g, b = entry.b, whisper = entry.whisper == true }
        end
    end
    return list
end

-- ---------------------------------------------------------------------------------------
-- The fade: one timer, started again by every new line; the dimming itself runs on the shared animation clock
-- (ns.Animate), which is gone again when it ends.

local fadeTimer
local FADE_ANIMATION = 0.4

local function FadeNow()
    fadeTimer = nil
    ns.Animate(lines, "fadeto", FADE_ANIMATION, FADE_ALPHA)
end

local function StartFade()
    if fadeTimer then fadeTimer:Cancel() end
    ns.Animate.Cancel(lines)
    if lines:GetAlpha() ~= 1 then lines:SetAlpha(1) end
    fadeTimer = C_Timer.NewTimer(FADE_SECONDS, FadeNow)
end

local function StopFade()
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
    ns.Animate.Cancel(lines)
    lines:SetAlpha(1)
end

function Chat.HasFade() return fadeTimer ~= nil end

-- ---------------------------------------------------------------------------------------
-- The strip

local strip = Kit.Backdrop(ns.root, "tooltip", "tooltip", "Button")
strip:SetSize(STRIP_W, STRIP_H)
strip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
Kit.FitHit(strip)
Chat.strip = strip

strip.text = strip:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(strip.text, Kit.FONT_TITLE, 20, "")
strip.text:SetJustifyH("LEFT")
strip.text:SetPoint("LEFT", strip, "LEFT", 18, 0)

strip.later = strip:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(strip.later, Kit.FONT_TITLE, 18, "")
strip.later:SetTextColor(1, 0.82, 0)
strip.later:SetPoint("LEFT", strip, "LEFT", 18, 0)
strip.later:Hide()
Chat.later = strip.later

local LABELS = {
    SAY = "chat.say", PARTY = "chat.party", GUILD = "chat.guild", OFFICER = "chat.officer",
    RAID = "chat.raid", RAID_WARNING = "chat.raidWarning", INSTANCE_CHAT = "chat.instance",
    YELL = "chat.yell", EMOTE = "chat.emote", CHANNEL = "chat.channel",
}

-- The channel you are talking in: the edit box's sticky type, else its current type.
local function Prefix()
    local box = _G.ChatFrame1EditBox
    local kind, target
    if box and box.GetAttribute then
        kind = box:GetAttribute("stickyType") or box:GetAttribute("chatType")
        target = box:GetAttribute("tellTarget")
    end
    if type(kind) ~= "string" then kind = "SAY" end
    if kind == "WHISPER" or kind == "BN_WHISPER" then
        if type(target) == "string" and target ~= "" then
            return ns.T("chat.whisper", target:match("^[^%-]+") or target)
        end
        return ns.T("chat.whisperBare")
    end
    return ns.T(LABELS[kind] or "chat.say")
end

local shownPrefix
local function UpdateStrip()
    local prefix = Prefix()
    if prefix == shownPrefix then return end
    shownPrefix = prefix
    strip.text:SetText(("|cffffffff%s:|r |cff808080%s|r"):format(prefix, ns.T("chat.tapToType")))
end

local function Tap()
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then open("") end
end
Chat.Open = Tap                 -- the Menu's Chat tile

local laterTimer
local function HideLater()
    laterTimer = nil
    strip.later:Hide()
    strip.text:Show()
end

local function Hold()
    if laterTimer then laterTimer:Cancel() end
    strip.later:SetText(ns.T("chat.later"))
    strip.later:Show()
    strip.text:Hide()
    laterTimer = C_Timer.NewTimer(LATER_SECONDS, HideLater)
end

local pressedAt
local function HoldSeconds()
    local feel = ns.db and ns.db.feel
    local hold = type(feel) == "table" and feel.hold
    if type(hold) ~= "number" or hold ~= hold or hold <= 0 then return DEFAULT_HOLD end
    return hold
end

strip:SetScript("OnMouseDown", function() pressedAt = GetTime() end)
strip:SetScript("OnClick", function(_, button)
    local held = pressedAt and GetTime() - pressedAt >= HoldSeconds()
    pressedAt = nil
    ns.Guard("chat strip", (button == "RightButton" or held) and Hold or Tap)
end)
strip:HookScript("PostClick", function() Kit.Sound("tap") end)
-- pressed (polish pass): a plain tap lights the strip's edge. In the world the app opens its own keyboard for the
-- strip and sends no key, so there its gold outline is the only press look.
Kit.AddPress(strip, "rect", strip, 2)

-- ---------------------------------------------------------------------------------------
-- The whisper badge

local badge = Kit.Backdrop(strip, "tooltip", "tooltip", "Button")
badge:SetSize(150, 36)
badge:SetPoint("RIGHT", strip, "RIGHT", -8, 0)
badge:SetFrameLevel(strip:GetFrameLevel() + 2)
badge:SetBackdropColor(0.25, 0.08, 0.25, 0.95)
badge:SetBackdropBorderColor(PINK[1], PINK[2], PINK[3], 1)
badge:RegisterForClicks("LeftButtonUp")
Kit.FitHit(badge)
badge:Hide()
Chat.badge = badge

local disc = badge:CreateTexture(nil, "ARTWORK")
disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
disc:SetVertexColor(PINK[1], PINK[2], PINK[3])
disc:SetSize(24, 24)
disc:SetPoint("LEFT", badge, "LEFT", 8, 0)
badge.count = badge:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(badge.count, Kit.FONT_NUMBER, 16, "")
badge.count:SetTextColor(0, 0, 0)
badge.count:SetPoint("CENTER", disc, "CENTER", 0, 0)
badge.label = badge:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(badge.label, Kit.FONT_TITLE, 16, "")
badge.label:SetTextColor(1, 0.8, 0.95)
badge.label:SetPoint("LEFT", badge, "LEFT", 40, 0)

local unread, replyFull, replyName, replyHidden, replyBN = 0, nil, nil, nil, false
local hasHiddenSender = false

-- How many whispers wait for a reply (the Menu's Chat tile and its dot).
function Chat.Unread() return unread end

local function UpdateBadge()
    if unread == 0 then
        badge:Hide()
        return
    end
    badge.count:SetText(unread > 99 and "99+" or tostring(unread))
    if replyName then
        badge.label:SetText(ns.T("chat.reply", replyName))
    elseif hasHiddenSender then
        badge.label:SetFormattedText(ns.L["chat.reply"], replyHidden)
    else
        badge.label:SetText(ns.T("chat.replyAny"))
    end
    badge:SetWidth(math.ceil(badge.label:GetStringWidth()) + 56)
    Kit.FitHit(badge)
    badge:Show()
end

local function ClearUnread()
    unread, replyFull, replyName, replyHidden, replyBN = 0, nil, nil, nil, false
    hasHiddenSender = false
    if ns.Hud and ns.Hud.ClearWhisper then ns.Hud.ClearWhisper() end
    UpdateBadge()
end

local function Reply()
    local full, bn = replyFull, replyBN
    ClearUnread()
    local send = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    local reply = (ChatFrameUtil and ChatFrameUtil.ReplyTell) or ChatFrame_ReplyTell
    if full and not bn and send then send(full) elseif reply then reply() end
end
badge:SetScript("OnClick", function() ns.Guard("chat reply", Reply) end)
Kit.AddPress(badge, "rect", badge, 2)
badge:HookScript("PostClick", function() Kit.Sound("tap") end)

-- A whisper event and its line in the chat window arrive in either order, in the same frame: the
-- event marks the newest line if that arrived this frame, else the next line that arrives.
local pendingWhisperAt

local function NoteWhisper(sender, bn)
    unread = unread + 1
    replyBN = bn
    if Plain(sender) then
        hasHiddenSender = false
        if type(sender) == "string" then
            replyFull, replyHidden = sender, nil
            replyName = sender:match("^[^%-]+") or sender
        else
            replyFull, replyName, replyHidden = nil, nil, nil
        end
    else
        hasHiddenSender = true
        replyFull, replyName, replyHidden = nil, nil, sender
    end
    local now = GetTime()
    if count > 0 and entries[3].at == now then
        entries[3].whisper = true
        pendingWhisperAt = nil
    else
        pendingWhisperAt = now
    end
    Paint()
    UpdateBadge()
end

ns.On("CHAT_MSG_WHISPER", function(_, sender) NoteWhisper(sender, false) end)
ns.On("CHAT_MSG_BN_WHISPER", function(_, sender) NoteWhisper(sender, true) end)
ns.On("CHAT_MSG_WHISPER_INFORM", ClearUnread)
ns.On("CHAT_MSG_BN_WHISPER_INFORM", ClearUnread)

-- ---------------------------------------------------------------------------------------
-- A line arrives

local function Record(_, text, r, g, b)
    local hidden = not Plain(text)
    if not hidden and type(text) ~= "string" then return end
    local entry = entries[1]
    entries[1], entries[2], entries[3] = entries[2], entries[3], entry
    local now = GetTime()
    entry.text, entry.at = text, now
    entry.whisper = pendingWhisperAt == now
    pendingWhisperAt = nil
    if Plain(r) and Plain(g) and Plain(b) and type(r) == "number" and type(g) == "number" and type(b) == "number" then
        entry.r, entry.g, entry.b = r, g, b
    else
        entry.r, entry.g, entry.b = 1, 1, 1
    end
    if hidden then
        entry.rows[1], entry.n = text, 1
    else
        Wrap(entry)
    end
    if count < 3 then count = count + 1 end
    if ns.IsActive() then
        Paint()
        UpdateStrip()
        StartFade()
    end
end

local function OnAddMessage(frame, ...) ns.Guard("chat line", Record, frame, ...) end
local function OnBoxHide() if ns.IsActive() then ns.Guard("chat strip", UpdateStrip) end end

-- ---------------------------------------------------------------------------------------
-- The game's own chat window: alpha 0 and no mouse, never moved

-- Chat windows, their tabs and their scroll buttons by name, and the dock's own buttons. The edit
-- boxes are not in the list: they must stay usable.
local DOCK_PARTS = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }

local savedGame = {}        -- frame -> { alpha =, mouse = } as the game had it
local savedBox = {}         -- edit box -> whether it ignored its parent's alpha
local savedBoxAlpha = {}    -- edit box -> its own alpha as the game last set it
local boxTyping = {}        -- edit box -> it has focus and sits on the strip
local settingAlpha = false  -- TouchPlay is setting a box's alpha (its SetAlpha hook lets that through)
local savedBoxPoints = {}   -- edit box -> its anchors while it sits on the strip
local boxHooked = {}        -- edit box -> true once its focus scripts are hooked
local gameWant = false        -- (while Edit Mode is open, ns.inEditMode, the game chat is the game's)

-- Mouse off on the frames under a chat window too (a click-anywhere or resize button would still
-- catch touches over the hidden chat). Edit boxes (and what is in them) and protected frames are
-- left alone; only a child that had its mouse on is recorded, so only it is given its mouse back.
local function QuietChildren(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        local box = child.GetObjectType and child:GetObjectType() == "EditBox"
        if not box and not (child.IsProtected and child:IsProtected()) then
            if child.IsMouseEnabled and child:IsMouseEnabled() and not savedGame[child] then
                savedGame[child] = { mouse = true }
                child:EnableMouse(false)
            end
            if child.GetChildren then QuietChildren(child:GetChildren()) end
        end
    end
end

local function QuietFrame(frame)
    if type(frame) ~= "table" or not frame.SetAlpha then return end
    local was = savedGame[frame]
    if not was then
        savedGame[frame] = { alpha = frame:GetAlpha(), mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false }
    elseif was.alpha == nil then
        was.alpha = frame:GetAlpha()        -- first met as somebody's child, its alpha is still the game's
    end
    frame:SetAlpha(0)
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.GetChildren then QuietChildren(frame:GetChildren()) end
end

local function EachGameChat(fn)
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        fn(_G["ChatFrame" .. i], _G["ChatFrame" .. i .. "EditBox"], _G["ChatFrame" .. i .. "Tab"],
            _G["ChatFrame" .. i .. "ButtonFrame"])
    end
end

-- A typing box sits on the strip while it has focus, and goes dark with its window the rest of the time.
local function MoveBoxToStrip(box)
    if savedBoxPoints[box] or not box.GetNumPoints or not strip then return end
    local points = {}
    for i = 1, box:GetNumPoints() do points[i] = { box:GetPoint(i) } end
    savedBoxPoints[box] = points
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
end

local function MoveBoxBack(box)
    local points = savedBoxPoints[box]
    if not points then return end
    savedBoxPoints[box] = nil
    box:ClearAllPoints()
    for _, p in ipairs(points) do box:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

-- The box's own alpha: 0 while it is dark, the game's while it types. Its parent's alpha alone does not hide it
-- (iPad run 5: a thin empty bar, holding a "/", stayed drawn left of centre above the strip: a chat edit box the
-- hidden chat window's alpha did not reach, whoever its parent is or whatever alpha the game gave it).
local function SetBoxAlpha(box, typing)
    if savedBoxAlpha[box] == nil then savedBoxAlpha[box] = box.GetAlpha and box:GetAlpha() or 1 end
    settingAlpha = true
    box:SetAlpha(typing and savedBoxAlpha[box] or 0)
    settingAlpha = false
end

-- The game sets the box's alpha (a fade, a chat style): kept as the box's own, and dark again while nobody types.
local function OnBoxSetAlpha(box, alpha)
    if settingAlpha or not gameWant or ns.inEditMode or savedBoxAlpha[box] == nil then return end
    savedBoxAlpha[box] = alpha
    if not boxTyping[box] and (alpha or 0) > 0 then
        settingAlpha = true
        box:SetAlpha(0)
        settingAlpha = false
    end
end

local function SetBoxTyping(box, typing)
    boxTyping[box] = typing or nil
    box:SetIgnoreParentAlpha(typing)
    SetBoxAlpha(box, typing)
    if typing then MoveBoxToStrip(box) else MoveBoxBack(box) end
    -- no mouse while it is dark, so the invisible bar does not catch touches meant for the world
    if box.EnableMouse then
        if not savedGame[box] then savedGame[box] = { mouse = box.IsMouseEnabled and box:IsMouseEnabled() or false } end
        box:EnableMouse(typing)
    end
end

local function OnBoxFocus(box)
    if gameWant and not ns.inEditMode then ns.Guard("chat box focus", SetBoxTyping, box, true) end
end
local function OnBoxUnfocus(box)
    if gameWant and not ns.inEditMode then ns.Guard("chat box focus", SetBoxTyping, box, false) end
end

local function QuietBox(box)
    if not box.SetIgnoreParentAlpha then return end
    if savedBox[box] == nil then savedBox[box] = box.IsIgnoringParentAlpha and box:IsIgnoringParentAlpha() or false end
    if not boxHooked[box] and box.HookScript then
        boxHooked[box] = true
        box:HookScript("OnEditFocusGained", OnBoxFocus)
        box:HookScript("OnEditFocusLost", OnBoxUnfocus)
        if box.SetAlpha then hooksecurefunc(box, "SetAlpha", OnBoxSetAlpha) end
    end
    SetBoxTyping(box, box.HasFocus and box:HasFocus() or false)
end

local function QuietGameChat()
    EachGameChat(function(frame, box, tab, buttons)
        if box then QuietBox(box) end
        QuietFrame(frame); QuietFrame(tab); QuietFrame(buttons)
    end)
    for _, name in ipairs(DOCK_PARTS) do QuietFrame(_G[name]) end
end

local function GiveGameChatBack()
    for box in pairs(savedBoxPoints) do MoveBoxBack(box) end
    for frame, was in pairs(savedGame) do
        if was.alpha then frame:SetAlpha(was.alpha) end
        if frame.EnableMouse then frame:EnableMouse(was.mouse) end
        savedGame[frame] = nil
    end
    for box, ignored in pairs(savedBox) do
        box:SetIgnoreParentAlpha(ignored)
        savedBox[box] = nil
    end
    for box, alpha in pairs(savedBoxAlpha) do
        settingAlpha = true
        box:SetAlpha(alpha)
        settingAlpha = false
        savedBoxAlpha[box] = nil
        boxTyping[box] = nil
    end
end

local function ApplyGameChat()
    if gameWant then QuietGameChat() else GiveGameChatBack() end
end

local function WantGameChat(on)
    gameWant = on
    ns.Queue("chat game", ApplyGameChat)
end

local function ReassertGameChat() if gameWant then ns.Queue("chat game", ApplyGameChat) end end
ns.On("UPDATE_CHAT_WINDOWS", ReassertGameChat)
ns.On("UPDATE_FLOATING_CHAT_WINDOWS", ReassertGameChat)

-- ---------------------------------------------------------------------------------------
-- Module steps

function Chat:Init()
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then hooksecurefunc(frame, "AddMessage", OnAddMessage) end
    local box = _G.ChatFrame1EditBox
    if box and box.HookScript then box:HookScript("OnHide", OnBoxHide) end
    if EventRegistry then
        -- Core sets ns.inEditMode first (its callbacks were registered first)
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            ns.Guard("EditMode.Enter", WantGameChat, false)
        end, Chat)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            if ns.IsActive() and not ns.inEditMode then ns.Guard("EditMode.Exit", WantGameChat, true) end
        end, Chat)
    end
    local Contract = ns.Contract
    if not Contract then return end
    Contract.Area("chat", strip, { anchor = "BL", tap = { command = "OPENCHAT" } })
    -- the keyboard's Send key types a bare F12 before the text
    Contract.KeepKey("F12", { command = "OPENCHAT" })
end

-- The strip's width: the mockup's 568, shortened at the thumb end when a stand and large buttons bring a spell
-- button down over it (I5), so the two touch areas never overlap. Worked out right-handed (a left-handed thumb area
-- is mirrored back first).
local thumbAreas = {}
local function StripWidth()
    local width = STRIP_W
    local left = ns.LeftHanded()
    for _, o in ipairs(ns.ThumbAreas(thumbAreas)) do
        local x = left and (REF_W - o.x - o.w) or o.x
        if o.y < STRIP_Y + STRIP_H and STRIP_Y < o.y + o.h and x < STRIP_X + width and STRIP_X < x + o.w then
            width = math.max(STRIP_H, x - STRIP_GAP - STRIP_X)
        end
    end
    return width
end

function Chat:Layout()
    ns.Anchor(lines, "BL", LINES_X, REF_H - LINES_BOTTOM - ROWS * ROW_H, "sidetext")
    strip:SetWidth(StripWidth())
    ns.Anchor(strip, "BL", STRIP_X, STRIP_Y, "side")
    if not ns.inEditMode then WantGameChat(true) end
end

function Chat:Refresh()
    Paint()
    shownPrefix = nil
    UpdateStrip()
    UpdateBadge()
    if count > 0 then StartFade() end
end

function Chat:Restore()
    WantGameChat(false)
    StopFade()
    if laterTimer then laterTimer:Cancel(); HideLater() end
end
