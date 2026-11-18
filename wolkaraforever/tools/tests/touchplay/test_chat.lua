-- Task 12: the chat strip: the last three lines, the fade, the whisper badge, the typing strip and
-- the bare F12 binding the keyboard's Send key needs (mockups 01, 81, 82).
dofile("tests/stub.lua")

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    ns.Chat.Clear()         -- the add-on's own first-run lines are not what these tests look at
    return ns.Chat
end

local function say(text, r, g, b) DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b) end

local function texts(Chat)
    local out = {}
    for i, row in ipairs(Chat.Visible()) do out[i] = row.text end
    return out
end

local function noSource(file, word)
    local f = assert(io.open("addon/TouchPlay/" .. file)); local code = f:read("*a"); f:close()
    return not code:find(word, 1, true)
end

-- ---------------------------------------------------------------------------------------
-- The lines

T("three_lines_then_fade", function()
    local Chat = setup()
    for i = 1, 5 do say("line " .. i, 1, 1, 0) end
    local v = texts(Chat)
    assert(#v == 3 and v[1] == "line 3" and v[2] == "line 4" and v[3] == "line 5", table.concat(v, "|"))
    assert(Chat.lines:GetAlpha() == 1)
    Stub.advance(19); assert(Chat.lines:GetAlpha() == 1, "not yet")
    -- a new line starts the 20 seconds again
    say("line 6"); Stub.advance(19); assert(Chat.lines:GetAlpha() == 1, "the timer was reset")
    Stub.advance(2); assert(Chat.lines:GetAlpha() == 0.25, "faded after 20 s of nothing new")
    assert(Chat.strip:GetAlpha() == 1, "the strip stays")
    say("line 7"); assert(Chat.lines:GetAlpha() == 1, "a new line brings them back")
    Stub.advance(21); assert(Chat.lines:GetAlpha() == 0.25)
end)

T("line_colours_kept", function()
    local Chat = setup()
    say("Rollya Dice has gone offline.", 1, 0.82, 0)
    local row = Chat.Visible()[1]
    assert(row.text == "Rollya Dice has gone offline.")
    assert(row.r == 1 and row.g == 0.82 and row.b == 0)
    say("|cff1eff00[Guild] [Rhonda]: hi|r")
    assert(texts(Chat)[2] == "|cff1eff00[Guild] [Rhonda]: hi|r", "colour codes stay in the text")
    say("no colour given")
    local v = Chat.Visible()[3]
    assert(v.r == 1 and v.g == 1 and v.b == 1, "white when the game gives none")
end)

T("long_line_wraps_with_indent", function()
    local Chat = setup()
    local words = {}
    for i = 1, 25 do words[i] = "word" .. i end
    local long = "|cff1eff00" .. table.concat(words, " ") .. "|r"
    say("short"); say(long)
    local v = Chat.Visible()
    assert(#v == 3, "the last three rows, got " .. #v)
    -- the long line took two or more rows; every row after its first is indented 22
    assert(v[3].indent == 22 and v[1].indent == 0, v[1].indent .. "/" .. v[3].indent)
    for _, row in ipairs(v) do assert(#row.text * 6 <= 560 - row.indent, "fits its width") end
    assert(v[3].text:sub(1, 10) == "|cff1eff00", "the colour carries onto the wrapped row: " .. v[3].text)
    -- the rows together hold every word once
    local joined = {}
    for _, row in ipairs(v) do joined[#joined + 1] = row.text end
    local all = table.concat(joined, " ")
    assert(all:find("word25", 1, true) and all:find("word10", 1, true))
end)

T("wrap_keeps_a_link_in_one_piece", function()
    local Chat = setup()
    local pad = string.rep("x", 85)
    say(pad .. " |Hitem:1|h[Big Red Sword]|h tail")
    local v = Chat.Visible()
    for _, row in ipairs(v) do
        local open = select(2, row.text:gsub("|H", ""))
        local close = select(2, row.text:gsub("|h%[", ""))
        assert(open == close, "link not split: " .. row.text)
    end
    assert(v[#v].text:find("[Big Red Sword]", 1, true) or v[1].text:find("[Big Red Sword]", 1, true))
end)

T("whisper_line_is_marked", function()
    local Chat = setup()
    say("[Mira] whispers: want to do the lions together?")
    Stub.fire("CHAT_MSG_WHISPER", "want to do the lions together?", "Mira-Tarren Mill")
    local v = Chat.Visible()
    assert(v[#v].whisper == true, "pink bar behind the new whisper")
    say("later line")
    assert(Chat.Visible()[#Chat.Visible()].whisper == false)
end)

T("secret_line_does_not_raise", function()
    local Chat = setup()
    say("plain")
    say(Stub.secret(), Stub.secret(), Stub.secret(), Stub.secret())
    assert(not ns.paused, ns.lastError)
    assert(#Chat.Visible() == 2)
    Stub.fire("CHAT_MSG_WHISPER", Stub.secret(), Stub.secret())
    assert(not ns.paused, ns.lastError)
    assert(Chat.badge:IsShown(), "a whisper from a hidden name still gets a badge")
    Stub.click(Chat.badge)
    assert(Stub.calls.ReplyTell == 1 and not ns.paused, "reply goes through the game's own last-whisper")
end)

T("a_message_that_is_not_text_is_ignored", function()
    local Chat = setup()
    say(nil); say(42)
    assert(#Chat.Visible() == 0 and not ns.paused, ns.lastError)
end)

T("whisper_line_marked_when_the_event_comes_first", function()
    local Chat = setup()
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill")
    say("[Mira] whispers: hi")
    local v = Chat.Visible()
    assert(v[#v].whisper == true, "the next line after the event is the whisper")
    say("another line")
    v = Chat.Visible()
    assert(v[#v].whisper == false and v[#v - 1].whisper == true, "only the one line")
    -- an event with no line in the same frame does not mark a later, unrelated line
    Stub.fire("CHAT_MSG_WHISPER", "psst", "Bob")
    Stub.advance(1)
    say("something else entirely")
    v = Chat.Visible()
    assert(v[#v].whisper == false, "a stale event marks nothing")
end)

T("whisper_line_not_marked_when_the_line_was_old", function()
    local Chat = setup()
    say("an old line"); Stub.advance(5)
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill")
    local v = Chat.Visible()
    assert(v[#v].whisper == false, "the newest line is from long ago: not the whisper")
end)

T("hidden_sender_label_and_no_compare_with_nil", function()
    local Chat = setup()
    Stub.fire("CHAT_MSG_WHISPER", "hi", Stub.secret())
    assert(Chat.badge:IsShown() and Chat.badge.label:GetText() == "Reply to %s", "label formatted from the hidden name")
    assert(not ns.paused, ns.lastError)
    -- a plain name after a hidden one replaces it
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill")
    assert(Chat.badge.label:GetText() == "Reply to Mira")
    -- a whisper event with no sender at all still gives a badge
    Stub.click(Chat.badge)
    Stub.fire("CHAT_MSG_WHISPER", "hi")
    assert(Chat.badge:IsShown() and Chat.badge.label:GetText() == "Reply" and not ns.paused, ns.lastError)
end)

-- ---------------------------------------------------------------------------------------
-- The whisper badge

T("whisper_badge_and_name", function()
    local Chat = setup()
    assert(not Chat.badge:IsShown())
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill")
    assert(Chat.badge:IsShown())
    assert(Chat.badge.label:GetText() == "Reply to Mira", "realm stripped: " .. tostring(Chat.badge.label:GetText()))
    assert(Chat.badge.count:GetText() == "1")
    Stub.fire("CHAT_MSG_WHISPER", "hello?", "Mira-Tarren Mill")
    assert(Chat.badge.count:GetText() == "2")
    Stub.fire("CHAT_MSG_WHISPER", "psst", "Bob")
    assert(Chat.badge.label:GetText() == "Reply to Bob" and Chat.badge.count:GetText() == "3")
    -- tapping the badge answers the newest whisperer and clears the badge and the Menu dot
    ns.Hud.unreadWhisper = true
    Stub.click(Chat.badge)
    assert(Stub.lastTell == "Bob" and Stub.calls.SendTell == 1)
    assert(not Chat.badge:IsShown() and not ns.Hud.unreadWhisper)
    -- the full name (with realm) is what the game is given
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill"); Stub.click(Chat.badge)
    assert(Stub.lastTell == "Mira-Tarren Mill")
end)

T("answering_a_whisper_clears_the_badge", function()
    local Chat = setup()
    Stub.fire("CHAT_MSG_WHISPER", "hi", "Mira-Tarren Mill")
    Stub.fire("CHAT_MSG_WHISPER_INFORM", "yes!", "Mira-Tarren Mill")
    assert(not Chat.badge:IsShown())
end)

T("battle_net_whisper_replies_through_the_game", function()
    local Chat = setup()
    Stub.fire("CHAT_MSG_BN_WHISPER", "hi", "Mira")
    assert(Chat.badge:IsShown() and Chat.badge.label:GetText() == "Reply to Mira")
    Stub.click(Chat.badge)
    assert(Stub.calls.ReplyTell == 1 and Stub.calls.SendTell == 0)
end)

-- ---------------------------------------------------------------------------------------
-- The strip

T("strip_prefix_follows_channel", function()
    local Chat = setup()
    local box = _G.ChatFrame1EditBox
    assert(Chat.strip.text:GetText():find("Say:", 1, true) and Chat.strip.text:GetText():find("tap to type", 1, true))
    box:SetAttribute("stickyType", "PARTY"); box:_Fire("OnHide")
    assert(Chat.strip.text:GetText():find("Party:", 1, true), Chat.strip.text:GetText())
    box:SetAttribute("stickyType", "GUILD"); say("echo")
    assert(Chat.strip.text:GetText():find("Guild:", 1, true), "a new line also looks again")
    box:SetAttribute("stickyType", "WHISPER"); box:SetAttribute("tellTarget", "Mira-Tarren Mill"); box:_Fire("OnHide")
    assert(Chat.strip.text:GetText():find("Whisper Mira:", 1, true), Chat.strip.text:GetText())
    box:SetAttribute("stickyType", "YELL"); box:_Fire("OnHide")
    assert(Chat.strip.text:GetText():find("Yell:", 1, true))
    box:SetAttribute("stickyType", nil); box:SetAttribute("chatType", "RAID"); box:_Fire("OnHide")
    assert(Chat.strip.text:GetText():find("Raid:", 1, true), "chatType when nothing is sticky")
    box:SetAttribute("chatType", "NOSUCHTYPE"); box:_Fire("OnHide")
    assert(Chat.strip.text:GetText():find("Say:", 1, true), "an unknown channel reads Say")
end)

T("tap_opens_chat_input", function()
    local Chat = setup()
    Stub.click(Chat.strip)
    assert(Stub.calls.OpenChat == 1 and Stub.lastChatOpened == "", "the game's chat input opens once")
    -- the older name still works when the game has no ChatFrameUtil
    ChatFrameUtil = nil
    Stub.click(Chat.strip)
    assert(Stub.calls.ChatFrame_OpenChat == 1, "falls back to ChatFrame_OpenChat")
    assert(not ns.paused, ns.lastError)
end)

T("tap_works_in_a_fight", function()
    local Chat = setup()
    Stub.combat(true)
    Stub.click(Chat.strip)
    assert(Stub.calls.OpenChat == 1 and not ns.paused, ns.lastError)
end)

T("hold_says_later_version", function()
    local Chat = setup()
    assert(not Chat.later:IsShown())
    -- a long press
    Stub.mouseDown(Chat.strip); Stub.advance(0.6); Stub.click(Chat.strip)
    assert(Stub.calls.OpenChat == 0, "a hold does not type")
    assert(Chat.later:IsShown() and Chat.later:GetText() == "Coming in a later version")
    Stub.advance(3); assert(not Chat.later:IsShown(), "the note goes away")
    -- the right click the hold key sends
    Stub.click(Chat.strip, "RightButton")
    assert(Chat.later:IsShown() and Stub.calls.OpenChat == 0)
    -- a quick tap after a press still types
    Stub.advance(3)
    Stub.mouseDown(Chat.strip); Stub.advance(0.1); Stub.click(Chat.strip)
    assert(Stub.calls.OpenChat == 1)
end)

T("strip_and_lines_positions", function()
    local Chat = setup()
    local s, l = Chat.strip.touchAnchor, Chat.lines.touchAnchor
    assert(s.x == 296 and s.y == 948 and s.w == 568 and s.h == 52, "strip 568 x 52 at (296, 948)")
    assert(l.x == 300 and l.w == 560, "lines left 300, width 560")
    assert(l.corner == "BL" and (1024 - (l.y + l.h)) == 84, "lines bottom 84")
    assert(Chat.strip:GetHitRectSize() >= 44 and select(2, Chat.strip:GetHitRectSize()) >= 44)
    local bw, bh = Chat.badge:GetHitRectSize()
    assert(bw >= 44 and bh >= 44, "badge is a touch area too")
end)

-- ---------------------------------------------------------------------------------------
-- The contract area and the F12 key

T("chat_area_in_the_contract", function()
    local Chat = setup()
    local s = ns.db.contract
    assert(s:find("chat,BL,296,24,568,52,ALT%-CTRL%-SHIFT%-%w+,,"), s)
    local tap = ns.Contract.KeysFor("chat")
    assert(Stub.bindings[tap] and Stub.bindings[tap].command == "OPENCHAT", "the app's chat key opens the box")
end)

T("f12_bound_after_apply_pause_and_off", function()
    setup()
    local b = Stub.bindings["F12"]
    assert(b and b.command == "OPENCHAT", "bare F12 opens the chat input after Apply")
    ns.Contract.Apply()
    assert(Stub.bindings["F12"] and Stub.bindings["F12"].command == "OPENCHAT", "still after a second Apply")
    ns.Pause("test")
    assert(Stub.bindings["F12"] and Stub.bindings["F12"].command == "OPENCHAT", "kept while paused")
    assert(Stub.bindings[ns.Contract.WORLD_KEY] == nil and Stub.bindings[(ns.Contract.KeysFor("spell1"))] == nil)
    ns.paused = false
    ns.SetEnabled(true)
    assert(Stub.bindings["F12"] and Stub.bindings[ns.Contract.WORLD_KEY], "on again binds everything")
    ns.SetEnabled(false)
    assert(Stub.bindings["F12"] and Stub.bindings["F12"].command == "OPENCHAT", "kept when switched off")
    assert(Stub.bindings[(ns.Contract.KeysFor("spell1"))] == nil, "the other touch keys are gone")
end)

T("f12_changes_wait_for_the_end_of_a_fight", function()
    setup()
    Stub.combat(true)
    ns.SetEnabled(false)
    assert(Stub.bindings["F12"], "still bound during the fight")
    assert(not ns.paused, ns.lastError)
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(Stub.bindings["F12"] and Stub.bindings["F12"].command == "OPENCHAT")
    assert(Stub.bindings[(ns.Contract.KeysFor("spell1"))] == nil)
end)

T("f12_is_a_bare_key", function()
    setup()
    for key in pairs(Stub.bindings) do
        if key:find("F12", 1, true) and key ~= "F12" then assert(key == "ALT-CTRL-SHIFT-F12", key) end
    end
    assert(Stub.bindings["F12"] and not Stub.bindings["F12"].click)
end)

-- ---------------------------------------------------------------------------------------
-- The game's own chat window (R27: by alpha, never reparented)

local function gameChat()
    return _G.ChatFrame1, _G.ChatFrame1Tab, _G.ChatFrame2, _G.ChatFrame1EditBox
end

T("game_chat_hidden_by_alpha_after_layout", function()
    setup()
    local frame, tab, other, box = gameChat()
    assert(frame:GetAlpha() == 0 and not frame:IsMouseEnabled(), "message area invisible and untouchable")
    assert(tab:GetAlpha() == 0 and not tab:IsMouseEnabled(), "its tab too")
    assert(other:GetAlpha() == 0, "other chat windows too")
    assert(frame:GetParent() == _G.UIParent and frame.calls.SetParent == 0, "never reparented")
    assert(frame:IsShown(), "still shown: the game keeps working")
    -- the edit box goes dark with its window while nobody types: it does not ignore the parent's alpha (the
    -- iPad run showed it as an empty bar), and it takes no touches
    assert(box:GetAlpha() == 0 and not box:IsIgnoringParentAlpha(), "edit box dark on its own and with its window")
    assert(not box:IsMouseEnabled(), "no touches on the dark box")
    assert(box.shown ~= false)
    -- our own lines still reach the game's chat frame (the hook sees them)
    say("hello"); assert(texts(ns.Chat)[#texts(ns.Chat)] == "hello")
end)

T("game_chat_given_back_on_pause_and_off", function()
    Stub.reset(); Stub.loadAll()
    _G.ChatFrame1:SetAlpha(0.6)
    Stub.login()
    local frame, tab, other, box = gameChat()
    assert(frame:GetAlpha() == 0)
    ns.Pause("test")
    assert(frame:GetAlpha() == 0.6 and frame:IsMouseEnabled(), "exactly what it was, on a pause")
    assert(tab:GetAlpha() == 1 and tab:IsMouseEnabled() and other:GetAlpha() == 1)
    assert(not box:IsIgnoringParentAlpha() and box:IsMouseEnabled() and box:GetAlpha() == 1, "edit box as it was")
    ns.paused = false; ns.SetEnabled(true)
    assert(frame:GetAlpha() == 0 and not box:IsIgnoringParentAlpha() and not box:IsMouseEnabled(), "hidden again when on")
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 0.6 and frame:IsMouseEnabled() and tab:GetAlpha() == 1 and not box:IsIgnoringParentAlpha()
        and box:IsMouseEnabled(), "given back when off")
    assert(frame.calls.SetParent == 0)
end)

T("game_chat_changes_wait_for_the_end_of_a_fight", function()
    setup()
    local frame = _G.ChatFrame1
    Stub.combat(true)
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 0 and not ns.paused, "still hidden during the fight")
    Stub.combat(false); Stub.fire("PLAYER_REGEN_ENABLED")
    assert(frame:GetAlpha() == 1)
end)

T("game_chat_stays_hidden_when_the_game_shows_it_again", function()
    setup()
    local frame = _G.ChatFrame1
    frame:SetAlpha(1)                                 -- the game (a fade, a new window) undoes it
    Stub.fire("UPDATE_CHAT_WINDOWS")
    assert(frame:GetAlpha() == 0, "put back")
    -- a chat window made later (a whisper tab) is hidden too
    local later = CreateFrame("ScrollingMessageFrame", "ChatFrame3", _G.UIParent)
    Stub.fire("UPDATE_FLOATING_CHAT_WINDOWS")
    assert(later:GetAlpha() == 0)
    -- and giving it back restores each to what it was before we touched it
    ns.SetEnabled(false)
    assert(frame:GetAlpha() == 1 and later:GetAlpha() == 1)
end)

T("game_chat_children_lose_their_mouse_too", function()
    Stub.reset(); Stub.loadAll()
    local chat = _G.ChatFrame1
    local click = CreateFrame("Button", "ChatFrame1ClickAnywhereButton", chat)
    local resize = CreateFrame("Button", nil, chat)
    local deep = CreateFrame("Button", nil, resize)
    local off = CreateFrame("Button", nil, chat); off:EnableMouse(false)    -- already off: must stay off
    local secure = CreateFrame("Button", nil, chat, "SecureActionButtonTemplate")
    local inBox = CreateFrame("Button", nil, _G.ChatFrame1EditBox)
    local buttonFrame = CreateFrame("Frame", "ChatFrame1ButtonFrame", chat)   -- a child that is also listed by name
    buttonFrame:SetAlpha(0.8)
    Stub.login()
    assert(buttonFrame:GetAlpha() == 0)
    assert(not click:IsMouseEnabled() and not resize:IsMouseEnabled() and not deep:IsMouseEnabled(),
        "children and grandchildren of the hidden chat do not catch touches")
    assert(secure:IsMouseEnabled(), "a protected child is left alone")
    assert(inBox:IsMouseEnabled(), "what is in the edit box stays")
    -- one made later
    local later = CreateFrame("Button", nil, chat)
    Stub.fire("UPDATE_CHAT_WINDOWS")
    assert(not later:IsMouseEnabled(), "a child made later is caught too")
    ns.SetEnabled(false)
    assert(click:IsMouseEnabled() and resize:IsMouseEnabled() and deep:IsMouseEnabled() and later:IsMouseEnabled(),
        "each child's mouse comes back")
    assert(not off:IsMouseEnabled(), "a child that had no mouse still has none")
    assert(buttonFrame:GetAlpha() == 0.8, "a listed child gets its own alpha back too")
    assert(secure:IsMouseEnabled() and inBox:IsMouseEnabled() and _G.ChatFrame1EditBox:IsMouseEnabled())
    assert(not ns.paused, ns.lastError)
end)

T("edit_box_lifts_only_while_typing_and_sits_on_the_strip", function()
    local Chat = setup()
    local box = _G.ChatFrame1EditBox
    local before = box:GetNumPoints()
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", _G.ChatFrame1, "BOTTOMLEFT", 0, -8)
    box:SetPoint("TOPRIGHT", _G.ChatFrame1, "BOTTOMRIGHT", 0, -8)
    Stub.fire("UPDATE_CHAT_WINDOWS")
    assert(not box:IsIgnoringParentAlpha(), "dark while nobody types")
    box:SetFocus()
    assert(box:IsIgnoringParentAlpha() and box:IsMouseEnabled(), "typing: visible and tappable")
    assert(box:GetNumPoints() == 2 and select(2, box:GetPoint(1)) == Chat.strip and select(2, box:GetPoint(2)) == Chat.strip,
        "typing: on the strip")
    -- the game redoing the window while typing keeps it lifted
    Stub.fire("UPDATE_CHAT_WINDOWS")
    assert(box:IsIgnoringParentAlpha() and select(2, box:GetPoint(1)) == Chat.strip)
    box:ClearFocus()
    assert(not box:IsIgnoringParentAlpha() and not box:IsMouseEnabled(), "dark again")
    assert(box:GetNumPoints() == 2 and select(2, box:GetPoint(1)) == _G.ChatFrame1 and select(5, box:GetPoint(1)) == -8
        and select(3, box:GetPoint(2)) == "BOTTOMRIGHT", "back where the game put it")
    -- typing, then Off: everything as the game had it, in the middle of typing
    box:SetFocus()
    ns.SetEnabled(false)
    assert(not box:IsIgnoringParentAlpha() and box:IsMouseEnabled(), "Off gives the box back")
    assert(select(2, box:GetPoint(1)) == _G.ChatFrame1, "and its place")
    ns.SetEnabled(true)
    assert(box:IsIgnoringParentAlpha() and select(2, box:GetPoint(1)) == Chat.strip, "typing still lifted when on again")
    box:ClearFocus()
    -- Edit Mode: the game's own, focus changes do nothing
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(not box:IsIgnoringParentAlpha() and select(2, box:GetPoint(1)) == _G.ChatFrame1)
    box:SetFocus()
    assert(not box:IsIgnoringParentAlpha() and select(2, box:GetPoint(1)) == _G.ChatFrame1, "Edit Mode: left alone")
    box:ClearFocus()
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(not box:IsIgnoringParentAlpha() and not box:IsMouseEnabled())
    assert(not ns.paused, ns.lastError)
end)

-- iPad run 5: a thin bar holding a "/" stayed drawn left of centre above the strip: a live chat edit box. Its own
-- alpha hides it whoever its parent is, and whatever alpha the game gives it while nobody types.
T("edit_box_dark_on_its_own_whatever_its_parent_and_the_game_set", function()
    setup()
    local box = _G.ChatFrame1EditBox
    box:SetParent(UIParent)                       -- not under the hidden window: its alpha does not reach it
    box:SetText("/")
    ns.Each("Layout")
    assert(box:GetAlpha() == 0 and not box:IsMouseEnabled(), "dark with text in it and no focus")
    box:SetAlpha(0.8)                             -- the game fades it in (a chat style, an activate)
    assert(box:GetAlpha() == 0, "dark again at once")
    box:SetFocus()
    assert(box:GetAlpha() == 0.8 and box:IsIgnoringParentAlpha(), "typing: the game's own alpha")
    box:ClearFocus()
    assert(box:GetAlpha() == 0)
    for i = 2, 4 do
        local other = _G["ChatFrame" .. i .. "EditBox"]
        if other then assert(other:GetAlpha() == 0, "every chat window's box: " .. i) end
    end
    ns.SetEnabled(false)
    assert(box:GetAlpha() == 0.8, "Off gives the game's alpha back")
    box:SetAlpha(0.5)
    assert(box:GetAlpha() == 0.5, "Off: the game's to set")
    box:SetParent(_G.ChatFrame1)
    assert(not ns.paused, ns.lastError)
end)

T("edit_box_focus_hooks_are_made_once", function()
    setup()
    local box = _G.ChatFrame1EditBox
    for _ = 1, 3 do Stub.fire("UPDATE_CHAT_WINDOWS") end
    assert(#box.hooks.OnEditFocusGained == 1 and #box.hooks.OnEditFocusLost == 1)
end)

T("layout_in_edit_mode_does_not_hide_the_game_chat_again", function()
    setup()
    local frame = _G.ChatFrame1
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(frame:GetAlpha() == 1)
    ns.Each("Layout")
    assert(frame:GetAlpha() == 1, "a Layout while Edit Mode is open leaves the game's chat alone")
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(frame:GetAlpha() == 0, "and it steps aside when Edit Mode closes")
    ns.Each("Layout")
    assert(frame:GetAlpha() == 0)
end)

T("game_chat_comes_back_in_edit_mode", function()
    setup()
    local frame = _G.ChatFrame1
    EventRegistry:TriggerEvent("EditMode.Enter")
    assert(frame:GetAlpha() == 1, "Edit Mode shows it")
    EventRegistry:TriggerEvent("EditMode.Exit")
    assert(frame:GetAlpha() == 0, "and it steps aside again")
end)

-- ---------------------------------------------------------------------------------------
-- Pause, off and the rules

T("fade_timer_cancelled_on_pause_and_off", function()
    local Chat = setup()
    say("hello")
    assert(Chat.HasFade())
    ns.Pause("test")
    assert(not Chat.HasFade(), "paused: no timer left")
    Stub.advance(30)
    ns.paused = false; ns.SetEnabled(true)
    say("again"); assert(Chat.HasFade())
    ns.SetEnabled(false)
    assert(not Chat.HasFade(), "off: no timer left")
    Stub.advance(30)
    assert(not ns.paused, ns.lastError)
end)

T("lines_kept_while_the_screen_is_off", function()
    local Chat = setup()
    ns.SetEnabled(false)
    say("while off 1"); say("while off 2")
    assert(not Chat.HasFade(), "no timer while off")
    ns.SetEnabled(true)
    local seen = table.concat(texts(Chat), "|")      -- (the "Touch screen on" line is the newest)
    assert(seen:find("while off 2", 1, true), "the lines are there when the screen comes back: " .. seen)
end)

T("chat_needs_no_polling", function()
    local Chat = setup()
    assert(Chat.lines.scripts.OnUpdate == nil and Chat.strip.scripts.OnUpdate == nil)
    assert(noSource("Chat.lua", "OnUpdate"), "no OnUpdate anywhere in Chat.lua")
    assert(noSource("Chat.lua", "NewTicker"), "no ticker either")
end)

T("chat_strings_come_from_the_table", function()
    setup()
    for _, key in ipairs({ "chat.tapToType", "chat.say", "chat.party", "chat.guild", "chat.whisper", "chat.yell",
        "chat.reply", "chat.later" }) do
        assert(ns.L[key], key)
    end
    assert(ns.L["chat.later"] == "Coming in a later version")
    assert(ns.L["chat.reply"] == "Reply to %s")
    for key, text in pairs(ns.L) do
        if key:match("^chat%.") then assert(not text:find("\226\128\148"), "no em dash: " .. key) end
    end
end)

Stub.done("chat")
