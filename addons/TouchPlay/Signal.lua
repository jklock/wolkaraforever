-- TouchPlay: the in-world signal (rulings A24, A30, A32).
--
-- The iPad app must know when TouchPlay's buttons are drawn (the player is in the world) and when they are
-- not (login and character select, where add-ons are not drawn), so it never claims touches there. The game
-- gives the host no such signal, but a password edit box that takes focus switches the host's "secure event
-- input" on, and clearing the focus switches it off. This file pulses one hidden password box, 0.15 s on and
-- 0.15 s off, and the number of pulses in a group is what the app hears (ruling A32):
--   1  entered the world (login, /reload, loading in, switching On): sent 1 s after PLAYER_ENTERING_WORLD
--      (ruling A27: right after a loading screen the frame hitch can stretch the pulse past the app's 0.35 s
--      limit); switching On in the world pulses at once; the last window closing pulses at once;
--   2  left the world (loading out, logout, an error pause, switching Off): the app releases every key;
--   3  a window is open, still in the world (ruling A32; was the leaving pulse under A30): the app hands plain
--      taps to the game but keeps an auto-run lock's keys held, so the character keeps running with the map open.
--      Ruling A37 (iPad run 7): TouchPlay's own full-screen sheets (the picker, the Menu panel, Touch settings, the
--      guide) send 2 instead, so the app hides and switches off the walk stick (its ring was drawn over Touch
--      settings, and a thumb "engaged something" over the picker). Game windows and the small cards (info card, loot
--      card, pause card, away card) keep 3. Closing back to the world sends 1, as before (3 if a window stays open).
-- Same trick as WolkaraRoue's KeyboardSignal (a 2x2 password EditBox, SetFocus then ClearFocus).
--
-- Nothing here is an action (no cast, target, use, loot or interact), and nothing is protected: an EditBox is
-- an ordinary frame, so SetFocus and ClearFocus work in a fight (the chat box does the same).
--
-- Groups. The app counts pulses in groups: a group ends 0.6 s after its last pulse; 1, 2 and 3 are the values
-- above and 4 or more reads as 2 ("left", the safe side). So:
--   * 1 and 3 always start a group of their own: never sooner than 0.8 s after the last pulse ended (SPACING), and
--     never while another sequence runs;
--   * 2 goes at once (a loading screen or logout cannot wait). With no group open it is two pulses. When a group
--     may still be open (a pulse ran or ended less than SPACING ago) it is four: joined to what came before or
--     not, and whether or not a pulse cut short there was seen, the app counts 4 or more, "left".
--
-- Neither 1 nor 3 takes the keyboard from the player: while another edit box has focus they wait, asking again
-- every 0.5 s (1 gives up after 10 s, as it always did). 2 goes at once even while typing.
--
-- Logout: PLAYER_LEAVING_WORLD arrives just before PLAYER_LOGOUT and starts the timed leaving pulses. The game's
-- timers may not run once PLAYER_LOGOUT has fired, so when those pulses are still under way PLAYER_LOGOUT cancels
-- them and adds four immediate SetFocus/ClearFocus pairs (no timer) as the last edges.
--
-- Pulses go only while Touch is switched On (TouchPlayDB.enabled) and not paused. An error pause (ruling A26)
-- sends 2, because the game's own bars are back and the app must let plain taps reach them; resuming (switching
-- On again, in the world) sends 1 (or 3 when a window is open). While paused, loading screens send nothing: the
-- app has already been told.
--
-- Overlays (rulings A30, A32): the app claims touches on TouchPlay's areas while the player is in the world, so a
-- sheet, card or game window drawn over them could not be tapped. While any overlay is open (TouchPlay's own
-- sheets, panels and cards, and every game window the game's own registries name: UIPanelWindows and ShowUIPanel,
-- the UISpecialFrames Escape list, the bags; see "Overlays" below) the add-on sends 3, so the app hands plain taps
-- through (TouchPlay's full-screen sheets send 2 instead, ruling A37); when the last one closes, 1 goes at once (no 1 s
-- wait). Leaving the world with a window open sends 2.
-- The count is read from the frames themselves (shown, visible and, for a game window, not at alpha 0) 0.25 s
-- after the last OnShow or OnHide, so going from one window straight to another sends nothing. /touch windows
-- logs what it sees.

local ADDON_NAME, ns = ...

local Signal = ns.Register("Signal", {})

local PULSE = 0.15          -- seconds the box holds focus
local GAP = 0.15            -- seconds between two pulses of a group
local ENTER_DELAY = 1       -- how long after PLAYER_ENTERING_WORLD the entering pulse goes (the frame hitch after
                            -- a loading screen could stretch the pulse past the app's 0.35 s limit)
local POLL = 0.5            -- how often a deferred pulse asks again while the player types
local GIVE_UP = 10          -- how long the entering pulse keeps asking
local SPACING = 0.8         -- a new group starts this long after the last pulse ended, at least (the app closes a
                            -- group 0.6 s after its last one)
local SETTLE = 0.25         -- the overlays are counted this long after the last one opened or closed

-- What the app hears (ruling A32): the number of pulses in a group.
local ENTERED, LEFT, WINDOW = 1, 2, 3
local SURE_LEFT = 4         -- pulses that read as "left" whatever group they join (the app reads 4 or more as 2)
Signal.ENTERED, Signal.LEFT, Signal.WINDOW = ENTERED, LEFT, WINDOW

local box = CreateFrame("EditBox", "TouchPlayWorldSignal", UIParent)
box:SetPassword(true)
box:SetAutoFocus(false)
box:SetSize(2, 2)
box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
box:SetAlpha(0)
box:EnableMouse(false)
-- No key scripts: the box never types, sends or reacts. (Anything a key adds while it holds focus is cleared
-- with the focus.)
Signal.Box = box

local token = 0             -- a newer pulse sequence makes every timer of an older one do nothing
local waitToken = 0         -- a newer wait (for 1 or 3) or a leaving pulse cancels an older wait
local inWorld = nil         -- nil until the first event; false between leaving and entering
local running = false       -- a pulse sequence is under way
local lastOff = -100        -- GetTime() when the box last let go of a pulse's focus
local told = nil            -- what the app was last told: ENTERED, LEFT, WINDOW, or nil nothing yet
local notBefore = 0         -- GetTime() before which 1 or 3 does not go (the 1 s after PLAYER_ENTERING_WORLD)
local covered = false       -- an overlay is open (as last counted)
local sheetOpen = false     -- one of TouchPlay's full-screen sheets is open (as last counted; ruling A37)
local AnyOpen               -- counts the overlays now (below)
local AnySheetOpen          -- whether a full-screen sheet is open now (below)

local function Enabled() return ns.db ~= nil and ns.db.enabled == true and not ns.paused end

-- A window opened or closed, or the keyboard went to the pulse box: a key up that was due may never reach the press-look
-- watcher (iPad, 18 Nov: the Bags button stayed lit after the bags closed), so every look lets go now.
local function ReleaseLooks()
    if ns.Contract and ns.Contract.ReleaseLit then ns.Contract.ReleaseLit() end
end
box:HookScript("OnEditFocusGained", function() ReleaseLooks() end)

-- Gives focus back (only when the box still holds it: never takes focus from another box) and empties it.
local function Release()
    if box:HasFocus() then
        box:ClearFocus()
        lastOff = GetTime()
    end
    box:SetText("")
end

-- Another edit box holds the keyboard: the player is typing.
local function Typing()
    local other = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return other ~= nil and other ~= box
end

-- No group can still be open: nothing runs and the last pulse ended SPACING ago or more.
local function GroupClosed()
    return not running and not box:HasFocus() and GetTime() - lastOff >= SPACING - 1e-6
end

-- `count` pulses, now, telling the app `value`. Cancels any sequence still under way. When the box still has focus
-- from one that was cut short it lets go first and starts after a gap, so the host sees an edge.
local function Pulses(count, value)
    token = token + 1
    local mine = token
    running, told = true, value
    local function Step(i)
        if token ~= mine then return end
        box:SetFocus()
        C_Timer.After(PULSE, function()
            if token ~= mine then return end
            Release()
            if i < count then C_Timer.After(GAP, function() Step(i + 1) end) else running = false end
        end)
    end
    if box:HasFocus() then
        Release()
        C_Timer.After(GAP, function() Step(1) end)
    else
        Step(1)
    end
end

-- 2, at once: two pulses on a closed group, else four (see "Groups" above). Cancels a 1 or 3 still waiting. When
-- the leaving pulses are already under way nothing more is needed.
local function Leave()
    waitToken = waitToken + 1
    if told == LEFT and running then return end
    Pulses(GroupClosed() and LEFT or SURE_LEFT, LEFT)
end

-- What the app should hear now (nil: nothing yet, the world was not entered since loading).
local function Want()
    if inWorld == nil then return nil end
    if inWorld == false or sheetOpen then return LEFT end
    return covered and WINDOW or ENTERED
end

-- Tells the app 1 or 3 (whichever is true when it goes), as soon as it may: not before `notBefore`, not while a
-- sequence runs or a group may still be open, not while the player types in another edit box (1 gives up after
-- GIVE_UP seconds of that). A newer wait or a leaving pulse cancels it; nothing goes when the app already knows.
local function Sync()
    waitToken = waitToken + 1
    local mine = waitToken
    local waited = 0
    local function Try()
        if waitToken ~= mine or not Enabled() then return end
        local want = Want()
        if want == nil then return end
        if want == LEFT then
            if told ~= LEFT then Leave() end
            return
        end
        if want == told then return end
        local now = GetTime()
        if now < notBefore - 1e-6 then C_Timer.After(notBefore - now, Try); return end
        if running then C_Timer.After(GAP, Try); return end
        local early = lastOff + SPACING - now
        if early > 1e-6 then C_Timer.After(early, Try); return end
        if Typing() then
            waited = waited + POLL
            if want == WINDOW or waited <= GIVE_UP then C_Timer.After(POLL, Try) end
            return
        end
        Pulses(want, want)
    end
    Try()
end

ns.On("PLAYER_ENTERING_WORLD", function()
    inWorld = true
    notBefore = GetTime() + ENTER_DELAY
    if Enabled() then Sync() end
end, true)

ns.On("PLAYER_LEAVING_WORLD", function()
    inWorld = false
    if Enabled() then Leave() end
end, true)

ns.On("PLAYER_LOGOUT", function()
    inWorld = false
    if not Enabled() then return end
    if running then
        -- the timed pulses may not get to run: end with four immediate pairs (4 or more reads "left" whatever they
        -- join)
        token, waitToken = token + 1, waitToken + 1
        Release()
        for _ = 1, SURE_LEFT do
            box:SetFocus()
            Release()
        end
        running, told = false, LEFT
    elseif told ~= LEFT then
        Leave()
    end
end, true)

-- Called by ns.SetEnabled after the switch: Off tells the app at once, On (also the way back from a pause) tells it
-- when the player is in the world (a slash command is only typed there, so an unknown state counts as in the world):
-- 1, or 3 when a window is open.
function Signal.OnSwitch(on)
    if on then
        covered = AnyOpen()      -- counted at once: the pause card has just closed, say
        sheetOpen = AnySheetOpen()
        if inWorld ~= false then
            inWorld = true
            told = nil           -- Off or the pause said "left": tell the app again
            Sync()
        end
    elseif not ns.paused then
        Leave()                  -- Off from a pause: the pause already sent it
    end
end

-- Called by ns.Pause (once per pause). Nothing when Touch is switched Off: the app was told then.
function Signal.OnPause()
    if ns.db ~= nil and ns.db.enabled == true then Leave() end
end

-- What the app was last told (ENTERED, LEFT, WINDOW or nil), for the tests and /touch.
function Signal.Told() return told end

-- ---------------------------------------------------------------------------------------
-- Overlays (ruling A30)

-- Which windows count is read from the game's own registries, never from a list of guessed names (this client's UI
-- source is /tmp/wowui; the load-on-demand add-ons there have only their .toc, so their frame names cannot be known
-- in advance, but they register themselves):
--   panel    UIPanelWindows (Blizzard_UIParentPanelManager/Mainline/UIPanelWindows.lua, filled at
--            Shared/UIParentPanelManager.lua:83; load-on-demand add-ons write their own entry, as
--            Blizzard_UIPanels_Game/Shared/TaxiFrame.lua:2 does, or call RegisterUIPanel, :92, as
--            Blizzard_WorldMap.lua:135 does), UIChildWindows (:11, windows shown only with their parent panel), and
--            any frame the game's ShowUIPanel (:871) is asked to show (it shows one with no entry too, :891);
--   special  UISpecialFrames (:21), the Escape list (CloseSpecialWindows, :1106) other add-ons put their windows in
--            (Bagnon does); added to at any time, so it is read again on ADDON_LOADED and after the bag functions;
--   bag      the game's bags: ContainerFrameContainer.ContainerFrames (ContainerFrame1..7, parentArray
--            "ContainerFrames", Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:229 and :298-:304) and
--            ContainerFrameCombinedBags (:313). Every way of opening one ends in frame:Show()
--            (ContainerFrame_GenerateFrame, Mainline/ContainerFrame.lua:1304); this Camelot client loads the Mainline
--            ContainerFrame.lua (Blizzard_UIPanels_Game.toc:118; Camelot/ContainerFrame.lua only overrides two
--            methods), and its bank is BankFrame, a panel (BankFrameRegistration.lua:11);
--   named    the short list EXTRA below: windows no registry covers, each with its evidence;
--   own      TouchPlay's own sheets, panels and cards (Signal.Track).
-- The registries are read again when an add-on loads (ADDON_LOADED), at PLAYER_LOGIN, after RegisterUIPanel,
-- ShowUIPanel and HideUIPanel, after the functions that close windows (CloseWindows, CloseAllWindows,
-- CloseSpecialWindows) and just after the bag functions (bag add-ons make their windows on first use). Every frame
-- found gets an OnShow and an OnHide hook. Nothing is replaced and nothing is written into the game's tables: only
-- hooksecurefunc and HookScript, so the game's own code stays untainted.
--
-- Left out on purpose: the game's loot window (in UIPanelWindows, but TouchPlay keeps it at alpha 0 and its loot card,
-- which counts, stands in for it), static popups (a popup is not a window, whoever lists it), TouchPlay's reload notice
-- (placed clear of every touch area) and any game window that is shown but not drawn: at alpha 0 (as TouchPlay keeps
-- one hidden on purpose) or at a tiny effective scale (as Bagnon keeps the game's bag and bank windows; NotDrawn).
--
-- Windows that neither registry covers (shown with a plain Show(), in no list), each named with its evidence:
local EXTRA = {
    -- ModelPreviewFrame: Blizzard_SharedXML/ModelPreviewFrame.xml:3 (ButtonFrameTemplate, FULLSCREEN_DIALOG);
    -- shown by ModelPreviewFrame_ShowModelInternal with ModelPreviewFrame:Show(), ModelPreviewFrame.lua:152
    "ModelPreviewFrame",
    -- GroupLootHistoryFrame: Blizzard_FrameXML/Mainline/LootHistory.xml:193 (DefaultPanelFlatTemplate, 261 x 590);
    -- shown by ToggleLootHistoryFrame (SetShown, LootHistory.lua:667) and a loot link (Show, LootHistory.lua:686)
    "GroupLootHistoryFrame",
}
Signal.EXTRA = EXTRA

local overlays = {}         -- every frame counted, in the order it was found
local isOverlay = {}        -- frame -> the source that found it ("panel", "special", "bag", "named", "own")
local isSheet = {}          -- frame -> true for TouchPlay's full-screen sheets (ruling A37: they send 2)
local settleAt = 0          -- GetTime() when the count is due; a later open or close moves it on
local pending = false       -- a count is waiting

local TINY = 0.01           -- a game window drawn at a smaller effective scale is not there for the player

-- Why a shown game window is not drawn: "alpha 0" (TouchPlay keeps the game's loot window so, Loot.lua), "tiny scale"
-- (Bagnon keeps the game's combined bag and bank windows shown inside a parent at scale 0.001 while its own window
-- stands in: BagBrother/core/features/uiOverrides.lua:25, :56, :95), or nil when it is drawn.
local function NotDrawn(frame)
    if isOverlay[frame] == "own" then return nil end
    if frame.GetAlpha and (frame:GetAlpha() or 1) <= 0 then return "alpha 0" end
    if frame.GetEffectiveScale and (frame:GetEffectiveScale() or 1) < TINY then return "tiny scale" end
    return nil
end

-- Whether `frame` is open, as the app should hear it: shown and visible, and for a game window also drawn.
local function IsOpen(frame)
    return frame:IsVisible() and NotDrawn(frame) == nil
end

function AnyOpen()
    for i = 1, #overlays do
        if IsOpen(overlays[i]) then return true end
    end
    return false
end

function AnySheetOpen()
    for frame in pairs(isSheet) do
        if frame:IsVisible() then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------------------
-- /touch windows: every window the detector sees open or close, printed and kept in TouchPlayDB.windowlog (the last
-- KEEP_LOG lines). Line: T | OPEN or CLOSE | <global name, or "<unnamed> in <parent> > ... > UIParent"> | <source>
-- (panel, special, bag, named or own),
-- with "| alpha 0, not counted" or "| tiny scale, not counted" on a window that is shown but not drawn; T | START and
-- T | STOP mark the switch.

local KEEP_LOG = 200
local logging = false
local logged = {}           -- frame -> what the log last said: true open, false closed, or why it is shown but not
                            -- drawn ("alpha 0", "tiny scale")

ns.L["windows.on"] = "Window log on. Each window that opens or closes prints here and is kept in TouchPlayDB.windowlog. /touch windows off stops it."
ns.L["windows.off"] = "Window log off."
ns.L["windows.cleared"] = "Window log cleared."
ns.L["windows.usage"] = "Use /touch windows [on|off|clear]. With no word it switches the window log on or off."

local function NameOf(frame)
    local name = frame.GetName and frame:GetName()
    if name then return name end
    local chain, parent, guard = {}, frame.GetParent and frame:GetParent(), 0
    while parent and guard < 12 do
        chain[#chain + 1] = (parent.GetName and parent:GetName()) or "?"
        parent, guard = parent.GetParent and parent:GetParent(), guard + 1
    end
    if #chain == 0 then return "<unnamed>" end
    return "<unnamed> in " .. table.concat(chain, " > ")
end

local function Emit(full, short)
    local db = ns.db
    if type(db) == "table" then
        if type(db.windowlog) ~= "table" then db.windowlog = {} end
        local log = db.windowlog
        log[#log + 1] = full
        while #log > KEEP_LOG do table.remove(log, 1) end
    end
    if short then ns.Print(short) end
end

local function Stamp() return ("%.3f"):format(GetTime()) end

-- Writes a line for each counted frame whose state differs from what the log last said.
local function LogChanges()
    if not logging then return end
    for i = 1, #overlays do
        local frame = overlays[i]
        local state = frame:IsVisible() and (NotDrawn(frame) or true) or false
        if state ~= (logged[frame] or false) then
            logged[frame] = state
            local name, source = NameOf(frame), isOverlay[frame]
            local word = state and "OPEN" or "CLOSE"
            local full = Stamp() .. " | " .. word .. " | " .. name .. " | " .. source
            local short = "window " .. (state and "open" or "closed") .. ": " .. name .. " (" .. source .. ")"
            if type(state) == "string" then
                full, short = full .. " | " .. state .. ", not counted", short .. ", " .. state .. ", not counted"
            end
            Emit(full, short)
        end
    end
end

function Signal.WindowLogOn() return logging end

-- /touch windows [on|off|clear]
function Signal.WindowsCommand(word)
    word = (word or ""):lower()
    if word == "" then word = logging and "off" or "on" end
    if word == "on" then
        if logging then return end
        logging, logged = true, {}
        Emit(Stamp() .. " | START")
        ns.Print(ns.T("windows.on"))
        LogChanges()                -- the windows open now
    elseif word == "off" then
        if not logging then return end
        logging = false
        Emit(Stamp() .. " | STOP")
        ns.Print(ns.T("windows.off"))
    elseif word == "clear" then
        if type(ns.db) == "table" then ns.db.windowlog = nil end
        ns.Print(ns.T("windows.cleared"))
    else
        ns.Print(ns.T("windows.usage"))
    end
end

-- ---------------------------------------------------------------------------------------
-- Counting

local Settle

-- Counts the overlays and tells the app when "any open" changed (3 open, 1 closed: ruling A32).
local function SettleNow()
    local wait = settleAt - GetTime()
    if wait > 1e-6 then C_Timer.After(wait, Settle); return end      -- moved on by a later open or close
    pending = false
    LogChanges()
    local open, sheet = AnyOpen(), AnySheetOpen()
    if open == covered and sheet == sheetOpen then return end
    covered, sheetOpen = open, sheet
    ReleaseLooks()
    if not Enabled() or inWorld == false then return end     -- switching On or entering tells the app then
    Sync()                          -- 2 while a sheet is open (A37), 3 while a window is, 1 when the last one closed
end

Settle = function() ns.Guard("Signal overlays", SettleNow) end

-- An overlay opened or closed (OnShow, OnHide): count again once things have settled. Nothing waits when the
-- answer is the one the app already has.
local function Changed()
    if not pending and AnyOpen() == covered and AnySheetOpen() == sheetOpen then return end
    settleAt = GetTime() + SETTLE
    if pending then return end
    pending = true
    C_Timer.After(SETTLE, Settle)
end
Signal.Changed = Changed

local function OnShowOrHide()
    ReleaseLooks()
    LogChanges()
    Changed()
end

-- Counts `frame` as an overlay from now on; `source` says who found it ("own" when not given: TouchPlay's panels and
-- cards, and the info card when it is made); `sheet` marks one of TouchPlay's full-screen sheets (ruling A37: 2, not 3).
-- Safe to call twice: the first source stays.
function Signal.Track(frame, source, sheet)
    if type(frame) ~= "table" or isOverlay[frame] or not frame.HookScript or not frame.IsVisible then return end
    isOverlay[frame] = source or "own"
    if sheet then isSheet[frame] = true end
    overlays[#overlays + 1] = frame
    frame:HookScript("OnShow", OnShowOrHide)
    frame:HookScript("OnHide", OnShowOrHide)
    if frame:IsVisible() then OnShowOrHide() end
end

-- ---------------------------------------------------------------------------------------
-- Finding the game's windows

-- A frame the game lists that is not a window for the app (see "Left out on purpose" above).
local function Excluded(frame, name)
    if name == "LootFrame" or frame == _G.LootFrame then return true end
    if type(name) == "string" and name:match("^StaticPopup%d+$") then return true end
    if ns.Contract and frame == ns.Contract.notice then return true end
    return false
end

-- Tracks `entry` (a frame, or a global frame name) found by `source`, unless it is left out. A forbidden frame (the
-- shop's) cannot be hooked and is skipped.
local function Consider(entry, source)
    local frame, name = entry, nil
    if type(entry) == "string" then name, frame = entry, _G[entry] end
    if type(frame) ~= "table" or isOverlay[frame] then return end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then return end
    if not frame.HookScript or not frame.IsVisible then return end
    name = name or (frame.GetName and frame:GetName())
    if Excluded(frame, name) then return end
    Signal.Track(frame, source)
end

local function EachEntry(list, source, byKey)
    if type(list) ~= "table" then return end
    for key, value in pairs(list) do Consider(byKey and key or value, source) end
end

-- Reads every registry again (cheap: a few hundred table reads) and hooks what is new.
local function FindWindows()
    EachEntry(_G.UIPanelWindows, "panel", true)
    EachEntry(_G.UIChildWindows, "panel")
    local holder = _G.ContainerFrameContainer
    if type(holder) == "table" then EachEntry(holder.ContainerFrames, "bag") end
    Consider("ContainerFrameCombinedBags", "bag")
    EachEntry(_G.UISpecialFrames, "special")
    EachEntry(EXTRA, "named")
end
Signal.FindWindows = FindWindows

local function Find() ns.Guard("Signal windows", FindWindows) end

-- Whether an overlay is open, as last counted (for the tests and /touch).
function Signal.Covered() return covered end

-- Whether one of TouchPlay's full-screen sheets is open, as last counted (ruling A37).
function Signal.SheetOpen() return sheetOpen end

-- TouchPlay's own sheets, panels and cards (the info card is made on first use and tracks itself then; the reload
-- notice is left out: it is placed clear of every touch area).
-- The first four are full-screen sheets (ruling A37: 2 pulses, the app switches the walk stick off); the rest are
-- cards and panels that leave the world in view (3).
Signal.SHEETS = { { "Picker", "sheet" }, { "Menu", "panel" }, { "Feel", "panel" }, { "Guide", "dim" } }
for _, path in ipairs(Signal.SHEETS) do
    local module = ns[path[1]]
    if module then Signal.Track(module[path[2]], "own", true) end
end
for _, path in ipairs({
    { "Loot", "card" }, { "Perf", "panel" }, { "Perf", "card" }, { "Hud", "afk" }, { "Interact", "card" },
    { "InfoCard", "frame" },
}) do
    local module = ns[path[1]]
    if module then Signal.Track(module[path[2]], "own") end
end
FindWindows()
ns.On("ADDON_LOADED", FindWindows, true)
ns.On("PLAYER_LOGIN", FindWindows, true)

-- The panel manager's entry points (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua). ShowUIPanel's frame
-- is a window even without a UIPanelWindows entry (the game shows it all the same, :891); the others only make the
-- registries be read again and the count be taken (the OnShow and OnHide hooks already see what they do; Escape's
-- handler holds the original CloseAllWindows, :1190, so there only those hooks see it). ToggleFrame, ToggleUIPanel and
-- SetUIPanelShown (:841, :863, :938) go through ShowUIPanel and HideUIPanel.
local function ShownByPanelManager(frame)
    ReleaseLooks()
    if type(frame) == "table" then Consider(frame, "panel") end
    FindWindows()
    LogChanges()
    Changed()
end
local function AfterShowUIPanel(frame) ns.Guard("Signal ShowUIPanel", ShownByPanelManager, frame) end
local function AfterPanelCall()
    ReleaseLooks()
    Find()
    LogChanges()
    Changed()
end
if type(_G.ShowUIPanel) == "function" then hooksecurefunc("ShowUIPanel", AfterShowUIPanel) end
for _, fn in ipairs({ "HideUIPanel", "RegisterUIPanel", "CloseWindows", "CloseAllWindows", "CloseSpecialWindows" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, AfterPanelCall) end
end
-- Bag add-ons such as Bagnon make their windows on first use (and put them in UISpecialFrames): look again just after
-- the game's bag functions ran (Mainline/ContainerFrame.lua: ToggleBackpack :189, ToggleBag :237, OpenBag :313,
-- OpenBackpack :378, OpenAllBags :2153, ToggleAllBags :2173).
local function BagsMaybeOpened() C_Timer.After(0, Find) end
for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, BagsMaybeOpened) end
end
