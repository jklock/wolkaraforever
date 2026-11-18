-- TouchPlay: the rest of the play screen (mockups 01, 13-19, 25, 32, 33, 72, 76).
--
--   * the quest list (top left, under the player card): Questie's tracked quests when Questie is loaded (by its
--     own rule), else the game's watched quests; nothing watched: the quests in the log; at most 4 quests,
--     "+ n more" for the rest. While TouchPlay is active it is the only tracker (Bars hides Questie's);
--   * the minimap ring: the game's own Minimap moved into our ring (out of a fight only), the
--     zone, coordinates and clock, new mail, the tracking icon, zoom rings, "No map inside" in
--     a dungeon;
--   * the Bags and Menu rings, with a gold dot on Menu when something waits there;
--   * the experience line with its rested stretch, the level-up banner;
--   * the screen edges: a red glow under 25% health, a blue tint as a ghost;
--   * the error text beside the button that was just pressed;
--   * the game's breath and other mirror timers, moved to the top middle;
--   * the away (AFK) dim card.
--
-- The windows (quest log, world map, bags, main menu) open two ways. The app's key (what a finger does while
-- you play) is bound to the game's own binding command, which runs the game's own Toggle function as secure
-- code, so it works in a fight and needs no game button to exist (iPad run 4: this client, the Camelot game
-- type with the controller's bar, has no backpack button, so a secure "/click MainMenuBarBackpackButton"
-- found nothing and Bags did nothing; bindings_Camelot.xml has all three commands):
--   quest  -> TOGGLEQUESTLOG   (ToggleQuestLog)
--   map    -> TOGGLEWORLDMAP   (ToggleWorldMap)
--   bags   -> OPENALLBAGS      (ToggleAllBags; Bagnon hooks it, so its bags open instead)
--   menu   -> ns.Menu.Open() (Menu.lua). A secure click on MainMenuMicroButton is no use: its
--             OnClick only acts while the pointer is over that button (Blizzard_MicroMenu,
--             MainMenuMicroButtonMixin:OnClick).
-- A plain tap on the ring itself (the app sends plain taps while a panel or game window is open, A30) clicks
-- our secure button: out of a fight its PostClick calls the same Toggle function (inside pcall); in a fight
-- the secure macro clicks the game's own button when this client has one.
--
-- Hidden values (health) only ever go into the step curve and then into an alpha. Quest, map,
-- experience and mail data are plain.

local ADDON_NAME, ns = ...

local Hud = ns.Register("Hud", {})
local Kit = ns.Kit

ns.L["hud.complete"] = "(Complete)"
ns.L["hud.failed"] = "(Failed)"
ns.L["hud.new"] = "(new)"
ns.L["hud.done"] = "(Done)"
ns.L["hud.plusOne"] = "+1"
ns.L["hud.ready"] = "Ready to turn in"
ns.L["hud.more"] = "+ %d more · tap to open the quest log"
ns.L["hud.timeLeft"] = "{} left"
ns.L["hud.noMap"] = "No map inside. Open the map."
ns.L["hud.bags"] = "Bags"
ns.L["hud.menu"] = "Menu"
ns.L["hud.zoomIn"] = "+"
ns.L["hud.zoomOut"] = "-"
ns.L["hud.levelUp"] = "You have reached level %d!"
ns.L["hud.levelUp.health"] = "+ %d health"
ns.L["hud.levelUp.mana"] = "+ %d mana"
ns.L["hud.levelUp.power"] = "+ %d power"
ns.L["hud.levelUp.talent"] = "+ %d talent point"
ns.L["hud.levelUp.talents"] = "+ %d talent points"
ns.L["hud.rested"] = "Rested: double experience for the next %s"
ns.L["hud.afk.title"] = "You are away"
ns.L["hud.afk.tap"] = "Tap anywhere to come back."
ns.L["hud.afk.minute"] = "Away for 1 minute · the game logs you out after 30"
ns.L["hud.afk.minutes"] = "Away for %d minutes · the game logs you out after 30"

-- ---------------------------------------------------------------------------------------
-- Numbers from the mockups (layout units, 1366 x 1024)

local QUEST_X, QUEST_Y, QUEST_W, QUEST_AREA_H = 24, 200, 340, 260
local QUEST_X_LEFT = 380                -- mockup 87
local QUEST_GAP = 12                    -- left-handed, from the stance row when it rises into the list's band
local MAX_QUESTS = 4
local MAX_OBJECTIVES = 6
local FLASH_SECONDS = 2
local RED_SECONDS = 60
local MAP_K = 330 / 256
local BORDER_X, BORDER_SIZE = 1035, 330
local DISC_D, DISC_CX, DISC_CY = 172, 1250, 134
local MINIMAP_ART = 256                  -- Art/Minimap.tga's size in units
local ORB_D, ORB_X, BAGS_Y, MENU_Y = 60, 968, 34, 128
local MAIL_D, TRACK_D, ZOOM_D = 44, 46, 40
local MIRROR_X, MIRROR_Y, MIRROR_W = 533, 150, 300
local MIRROR_OLD_W, MIRROR_OLD_BAR_W = 206, 195
local ERROR_LIFT, ERROR_WINDOW, ERROR_SECONDS = 40, 0.5, 2
local LEVELUP_SECONDS = 4
local XP_HEIGHT = 9

local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.62, 0.62, 0.62 }
local GREEN, RED, PINK = { 30 / 255, 1, 0 }, { 1, 0.13, 0.13 }, { 1, 0.5, 0.44 }
-- the rings' glyphs, our own sharp art (R48; Style.lua Kit.GLYPHS)
local LETTER, BAG_ICON, MENU_ICON = "mail", "bag", "menu"
local DOT = "Interface\\Common\\Indicator-Yellow"
local ARROW = "Interface\\Minimap\\MinimapArrow"
local EDGE_ART = "Interface\\FullScreenTextures\\LowHealth"

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end

local function ShowIf(region, on)
    on = on and true or false
    if region:IsShown() ~= on then region:SetShown(on) end
end

local function Text(parent, size, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Kit.SetFont(fs, font or Kit.FONT_TITLE, size, "")
    return fs
end

local function SetText(fs, text)
    if fs.shownText ~= text then
        fs.shownText = text
        fs:SetText(text)
    end
end

-- ---------------------------------------------------------------------------------------
-- The quest list: pure part

-- watched: a list of { id =, title =, complete =, failed =, new =, objectives = { { text =, done = } },
-- timeTotal =, timeElapsed =, flash = index of the objective that just finished }.
-- Returns the first `max` of them as display lines and how many did not fit.
function Hud.QuestLines(watched, max)
    max = max or MAX_QUESTS
    local lines, count = {}, #watched
    for i = 1, math.min(max, count) do
        local q = watched[i]
        local state
        if q.failed then state = "failed"
        elseif q.complete then state = "ready"
        elseif q.timeTotal and q.timeElapsed and q.timeElapsed < q.timeTotal then state = "timed"
        elseif q.new then state = "new"
        else state = "progress" end
        local line = { id = q.id, title = q.title or "", state = state, objectives = {} }
        if state == "failed" then
            line.suffix, line.suffixColour = ns.T("hud.failed"), RED
        elseif state == "ready" then
            line.suffix, line.suffixColour = ns.T("hud.complete"), GREEN
            line.objectives[1] = { text = ns.T("hud.ready"), colour = WHITE }
        elseif state == "new" then
            line.suffix, line.suffixColour = ns.T("hud.new"), GREY
        end
        if state ~= "ready" then
            for index, objective in ipairs(q.objectives or {}) do
                if index > MAX_OBJECTIVES then break end
                local row = { text = objective.text or "", done = objective.done and true or false }
                if state == "failed" then
                    row.colour = PINK
                elseif q.flash == index then
                    row.colour, row.flash = GOLD, true
                else
                    row.colour = WHITE
                end
                line.objectives[#line.objectives + 1] = row
            end
        end
        if state == "timed" then
            line.timeTotal, line.timeElapsed = q.timeTotal, q.timeElapsed
            line.remaining = q.timeTotal - q.timeElapsed
        end
        lines[i] = line
    end
    return lines, math.max(0, count - max)
end

-- ---------------------------------------------------------------------------------------
-- The quest list: what the game (or Questie) says

local newQuests = {}        -- questID -> true until its first progress
local finishedSeen = {}     -- questID -> { [objective index] = true }
local flashing = {}         -- questID -> { index =, expires = }

-- Which quests the list shows (spec: watched quests first, else the quests in the log):
--   * Questie loaded with its tracker on: what Questie tracks, by Questie's own rule (v12.9.0,
--     QuestieQuest:IsQuestTracked): with "auto track" (its default) every quest in the log but the ones the player
--     untracked (Questie.db.char.AutoUntrackedQuests); without it only Questie.db.char.TrackedQuests. iPad run 8: with
--     auto track TrackedQuests stays EMPTY, and reading it alone left the list empty under a quest that was complete.
--   * else the game's watch list (C_QuestLog);
--   * nothing watched: every quest in the log, in the log's order.
-- Questie's tables are only read, never written.

-- The quests in the log, in its order (headers and hidden quests left out).
local function LogIDs()
    local ids, log = {}, C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return ids end
    for i = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(i)
        local id = type(info) == "table" and info.questID
        if type(id) == "number" and id > 0 and not info.isHeader and not info.isHidden then ids[#ids + 1] = id end
    end
    return ids
end

-- nil when Questie is not there or its tracker is off (its tables go stale then; the player tracks with the game's
-- watches, as Questie itself assumes).
local function QuestieIDs(logIDs)
    local questie = _G.Questie
    local db = type(questie) == "table" and type(questie.db) == "table" and questie.db
    local char, profile = db and db.char, db and db.profile
    if type(char) ~= "table" or type(profile) ~= "table" or profile.trackerEnabled == false then return nil end
    local ids = {}
    if profile.autoTrackQuests ~= false then
        local untracked = type(char.AutoUntrackedQuests) == "table" and char.AutoUntrackedQuests or {}
        for _, id in ipairs(logIDs) do
            if not untracked[id] then ids[#ids + 1] = id end
        end
    else
        local tracked = type(char.TrackedQuests) == "table" and char.TrackedQuests or {}
        for _, id in ipairs(logIDs) do
            if tracked[id] then ids[#ids + 1] = id end
        end
    end
    return ids
end

local function GameWatchIDs()
    local ids, log = {}, C_QuestLog
    if not (log and log.GetNumQuestWatches and log.GetQuestIDForQuestWatchIndex) then return ids end
    for i = 1, log.GetNumQuestWatches() do
        local id = log.GetQuestIDForQuestWatchIndex(i)
        if id then ids[#ids + 1] = id end
    end
    return ids
end

local function WatchedIDs()
    local logIDs = LogIDs()
    local ids = QuestieIDs(logIDs) or GameWatchIDs()
    if #ids == 0 then return logIDs end
    return ids
end
Hud.WatchedIDs = WatchedIDs

-- A timer that wants the quest list drawn again (the flash ended, the last minute began). One
-- file-level function, run through the guard, and only while the screen is on.
local function RecheckQuests()
    if ns.IsActive() then ns.Guard("hud quests", Hud.RefreshQuests) end
end

-- Sound and gold flash for an objective that has just been finished.
local function NoteProgress(id, objectives)
    local seen = finishedSeen[id]
    local first = seen == nil
    if first then seen = {}; finishedSeen[id] = seen end
    for index, objective in ipairs(objectives) do
        if objective.finished and not seen[index] then
            seen[index] = true
            if not first then
                flashing[id] = { index = index, expires = GetTime() + FLASH_SECONDS }
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then
                    PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
                end
                C_Timer.After(FLASH_SECONDS + 0.05, RecheckQuests)
            end
        end
    end
    if newQuests[id] and #objectives > 0 then
        for _, objective in ipairs(objectives) do
            if objective.finished or (objective.numFulfilled or 0) > 0 then newQuests[id] = nil; break end
        end
    end
end

function Hud.ReadQuests()
    local log, list = C_QuestLog, {}
    if not log then return list end
    for _, id in ipairs(WatchedIDs()) do
        local objectives = log.GetQuestObjectives and log.GetQuestObjectives(id) or {}
        NoteProgress(id, objectives)
        local q = { id = id, title = log.GetTitleForQuestID and log.GetTitleForQuestID(id),
            complete = log.IsComplete and log.IsComplete(id) and true or false,
            failed = log.IsFailed and log.IsFailed(id) and true or false,
            new = newQuests[id], objectives = {} }
        for index, objective in ipairs(objectives) do
            q.objectives[index] = { text = objective.text, done = objective.finished }
        end
        local flash = flashing[id]
        if flash and GetTime() < flash.expires then q.flash = flash.index else flashing[id] = nil end
        if log.GetTimeAllowed then q.timeTotal, q.timeElapsed = log.GetTimeAllowed(id) end
        list[#list + 1] = q
    end
    return list
end

-- ---------------------------------------------------------------------------------------
-- The quest list: widgets

-- The secure button is the touch area (fixed size, so it never changes in a fight); the
-- words are drawn on an insecure frame inside it.
local quest = CreateFrame("Button", "TouchPlayQuest", ns.root, "SecureActionButtonTemplate")
quest:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
quest:SetSize(QUEST_W, QUEST_AREA_H)
quest:RegisterForClicks("AnyUp")
quest:SetAttribute("*type1", "macro")      -- a left click with any keys held (the app holds three)
quest:SetAttribute("macrotext", "/click [combat] QuestLogMicroButton")   -- out of a fight: PostClick below
quest:SetAttribute("type2", nil)
Kit.AddPress(quest, "rect", quest, 2)          -- a tap lights the list's edge (its key, or a plain tap)
Hud.quest = quest
-- With a target the target card takes the top and the list steps aside; the game does the hiding
-- from secure code, so it follows the target in a fight too.
RegisterStateDriver(quest, "visibility", "[@target,exists] hide; show")

-- iPad run 7: the quest key (the app's tap on the list's area) is bound only while the list has quests to show and
-- no target hides it; else it does nothing. The binding belongs to this secure handler: its snippet binds and clears
-- the key from the state driver (the target, in a fight too) and from attributes set out of combat ("empty", and
-- "key" / "live" from the contract). In this client TOGGLEQUESTLOG opens the world map's quest panel (Camelot's quest
-- log lives in the map, Blizzard_WorldMap.lua:1397).
local QUEST_GATE_BODY = [[
    if name ~= "state-quest" and name ~= "key" and name ~= "empty" and name ~= "live" then return end
    local key, bound = self:GetAttribute("key"), self:GetAttribute("bound")
    if bound and bound ~= key then self:ClearBinding(bound); self:SetAttribute("bound", nil) end
    if not key then return end
    if self:GetAttribute("live") and not self:GetAttribute("empty") and self:GetAttribute("state-quest") ~= "off" then
        self:SetBinding(true, key, "TOGGLEQUESTLOG")
        self:SetAttribute("bound", key)
    else
        self:ClearBinding(key)
        self:SetAttribute("bound", nil)
    end
]]
local questGate = CreateFrame("Frame", "TouchPlayQuestGate", UIParent, "SecureHandlerAttributeTemplate")
questGate:SetAttribute("_onattributechanged", QUEST_GATE_BODY)
questGate:SetAttribute("empty", true)
RegisterStateDriver(questGate, "quest", "[@target,exists] off; on")
Hud.questGate = questGate

local content = CreateFrame("Frame", nil, quest)
content:SetAllPoints(quest)
content:EnableMouse(false)
quest.content = content

local TITLE_SIZE, LINE_SIZE, ENTRY_GAP = 17, 15, 10
local entries = {}

local function NewTimerBar(parent)
    local bar = Kit.Bar(parent, "timer")
    bar:SetSize(260, 18)
    bar:EnableMouse(false)
    bar.timeText = bar.text
    ns.Kit.SetFont(bar.text, Kit.FONT_NUMBER, 14, "")
    if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(bar.text)
        local formatter = C_StringUtil and C_StringUtil.CreateSecondsFormatter and C_StringUtil.CreateSecondsFormatter()
        local property = Enum and Enum.DurationTextBindingProperty
        if formatter and property and binding.SetTextFormat then
            binding:SetTextFormat(ns.T("hud.timeLeft"), { { property = property.RemainingDuration, formatter = formatter } })
        end
        binding:SetUpdateInterval(0.5)
        bar.binding = binding
    end
    if C_DurationUtil and C_DurationUtil.CreateDuration then bar.duration = C_DurationUtil.CreateDuration() end
    return bar
end

local function NewEntry(i)
    local entry = CreateFrame("Frame", nil, content)
    entry:SetSize(QUEST_W, 40)
    entry:EnableMouse(false)
    entry.title = Text(entry, TITLE_SIZE)
    entry.title:SetJustifyH("LEFT")
    entry.title:SetWordWrap(false)
    entry.title:SetWidth(QUEST_W)
    entry.title:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, 0)
    entry.lines = {}
    -- "objective just done" (mockup 72): a gold band behind the line, the game's check mark after
    -- it, and a green +1 at the right; all gone again after the flash
    entry.band = entry:CreateTexture(nil, "BACKGROUND")
    entry.band:SetColorTexture(1, 0.82, 0, 0.35)
    entry.band:Hide()
    entry.check = entry:CreateTexture(nil, "OVERLAY")
    entry.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    entry.check:SetDesaturated(true)
    entry.check:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
    entry.check:SetSize(20, 20)
    entry.check:Hide()
    entry.plus = Text(entry, 18, Kit.FONT_NUMBER)
    entry.plus:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    entry.plus:SetText(ns.T("hud.plusOne"))
    entry.plus:SetPoint("TOPRIGHT", entry, "TOPRIGHT", -6, -2)
    entry.plus:Hide()
    entry:Hide()
    return entry
end
for i = 1, MAX_QUESTS do entries[i] = NewEntry(i) end
Hud.entries = entries

local more = Text(content, TITLE_SIZE)
more:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
more:SetJustifyH("LEFT")
more:SetWidth(QUEST_W)
more:Hide()
Hud.more = more

local function ObjectiveLine(entry, i)
    local fs = entry.lines[i]
    if not fs then
        fs = Text(entry, LINE_SIZE)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWidth(QUEST_W - 10)
        entry.lines[i] = fs
    end
    return fs
end

local recolourAt
local function PaintTimer(entry, line)
    local bar = entry.bar
    if not bar then bar = NewTimerBar(entry); entry.bar = bar end
    local start = GetTime() - line.timeElapsed
    local key = line.id .. ":" .. math.floor(start + 0.5)
    if bar.key ~= key then
        bar.key = key
        if bar.duration and bar.SetTimerDuration then
            bar.duration:SetTimeFromStart(start, line.timeTotal)
            local direction = Enum and Enum.StatusBarTimerDirection
            local interpolation = Enum and Enum.StatusBarInterpolation
            bar:SetTimerDuration(bar.duration, interpolation and interpolation.Immediate or 0,
                direction and direction.RemainingTime or 1)
            if bar.binding then bar.binding:SetDuration(bar.duration); bar.binding:Enable() end
        else
            bar:SetMinMaxValues(0, line.timeTotal)
            bar:SetValue(line.timeTotal - line.timeElapsed)
        end
    end
    local red = line.remaining <= RED_SECONDS
    if red then bar:SetStatusBarColor(1, 0.1, 0.1) else bar:SetStatusBarColor(1, 0.76, 0.1) end
    if not red then
        -- turn red once the last minute starts
        local at = GetTime() + line.remaining - RED_SECONDS
        if recolourAt ~= at then
            recolourAt = at
            C_Timer.After(line.remaining - RED_SECONDS + 0.05, RecheckQuests)
        end
    end
    return bar
end

-- Stacks the entries from the top; returns the height used.
local function ShowEntry(entry, line, y)
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    local title = line.title
    if line.suffix then title = title .. " " .. Hex(line.suffixColour) .. line.suffix .. "|r" end
    SetText(entry.title, title)
    entry.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local h = TITLE_SIZE + 5
    local flashing
    for i, objective in ipairs(line.objectives) do
        local fs = ObjectiveLine(entry, i)
        local text = "- " .. objective.text
        if objective.done and not objective.flash and line.state ~= "failed" and line.state ~= "ready" then
            text = text .. " " .. Hex(GREY) .. ns.T("hud.done") .. "|r"
        end
        SetText(fs, text)
        fs:SetTextColor(objective.colour[1], objective.colour[2], objective.colour[3])
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -h)
        fs:Show()
        local rowHeight = math.max(LINE_SIZE + 6, fs:GetStringHeight() + 4)
        if objective.flash then
            flashing = true
            entry.band:ClearAllPoints()
            entry.band:SetPoint("TOPLEFT", entry, "TOPLEFT", 4, -h)
            entry.band:SetSize(QUEST_W - 50, rowHeight - 2)
            entry.check:ClearAllPoints()
            entry.check:SetPoint("LEFT", fs, "LEFT", math.min(QUEST_W - 40, fs:GetStringWidth() + 6), 0)
        end
        h = h + rowHeight
    end
    ShowIf(entry.band, flashing)
    ShowIf(entry.check, flashing)
    ShowIf(entry.plus, flashing)
    for i = #line.objectives + 1, #entry.lines do entry.lines[i]:Hide() end
    if line.state == "timed" then
        local bar = PaintTimer(entry, line)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", entry, "TOPLEFT", 17, -(h + 7))
        bar:Show()
        h = h + 18 + 14
    elseif entry.bar then
        entry.bar:Hide()
        if entry.bar.binding then entry.bar.binding:Disable() end
        entry.bar.key = nil
    end
    entry:SetHeight(h)
    entry:Show()
    return h
end

local shownLines = {}            -- what is on screen now (for a hold)
Hud.shown = shownLines

function Hud.RefreshQuests()
    local lines, extra = Hud.QuestLines(Hud.ReadQuests(), MAX_QUESTS)
    local y = 0
    for i = 1, MAX_QUESTS do
        local line, entry = lines[i], entries[i]
        shownLines[i] = line and line.id or nil
        entry.questID = line and line.id or nil
        if line then
            y = y + ShowEntry(entry, line, y) + ENTRY_GAP
        else
            entry:Hide()
        end
    end
    if extra > 0 then
        SetText(more, ns.T("hud.more", extra))
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        more:Show()
    else
        more:Hide()
    end
    local empty = #lines == 0
    ShowIf(content, not empty)
    ns.Queue("hud quest mouse", function()
        quest:EnableMouse(not empty)
        if (questGate:GetAttribute("empty") and true or false) ~= empty then questGate:SetAttribute("empty", empty) end
    end)
    return lines, extra
end

-- A game window opened from our code, out of a fight only (the game refuses add-on code to show a panel in a
-- fight, and the secure macro or binding does it there). A missing or changed Blizzard function is no reason to
-- pause, so it runs inside pcall.
local function OpenWindow(name)
    if ns.InFight() then return end
    local open = _G[name]
    if type(open) == "function" then pcall(open) end
end
Hud.OpenWindow = OpenWindow

-- A hold asks the info card about the quest under the finger (the first when the app's key is
-- what was pressed and no finger is on the list); a plain tap opens the quest log.
local function OnQuestPostClick(self, button)
    -- an empty list, or one a target hides, does nothing (iPad run 7)
    if not self:IsShown() or not content:IsShown() then return end
    if button == "LeftButton" then OpenWindow("ToggleQuestLog"); return end
    if button ~= "RightButton" or not ns.InfoCard then return end
    local id, anchor
    for i = 1, MAX_QUESTS do
        local entry = entries[i]
        if entry.questID and entry:IsShown() then
            if not id then id, anchor = entry.questID, entry end
            if entry:IsMouseOver() then id, anchor = entry.questID, entry; break end
        end
    end
    if id then
        ns.Guard("hud quest hold", function()
            ns.InfoCard.Show({ kind = "questObjective", questID = id }, anchor)
        end)
    end
end
quest:HookScript("PostClick", OnQuestPostClick)

-- ---------------------------------------------------------------------------------------
-- Rings: a secure button over the picture, as the Next target ring does it

local function SecureRing(name, d, icon, label)
    local button = CreateFrame("Button", name, ns.root, "SecureActionButtonTemplate")
    button:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    button:SetSize(d, d)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("*type1", "macro")
    button:SetAttribute("type2", nil)
    local face = Kit.RingButton(button, d, icon, label)
    face:SetAllPoints(button)
    face:EnableMouse(false)
    button.face = face
    Kit.FitHit(button)
    Kit.AddPress(button, "round", face)       -- the ring's press glow, lit by the secure button over it
    button:HookScript("PostClick", function(_, mouse) if mouse == "LeftButton" then Kit.Sound("tap") end end)
    return button
end

local bags = SecureRing("TouchPlayBags", ORB_D, BAG_ICON, ns.T("hud.bags"))
bags:SetAttribute("macrotext", "/click [combat] MainMenuBarBackpackButton")   -- out of a fight: PostClick below
bags:HookScript("PostClick", function(_, mouse)
    if mouse == "LeftButton" then OpenWindow("ToggleAllBags") end
end)
Hud.bags = bags

-- Menu has no secure action: the tap (or the app's key) clicks this button and PostClick opens
-- our Menu (Menu.lua), which works in a fight too.
local menu = SecureRing("TouchPlayMenu", ORB_D, MENU_ICON, ns.T("hud.menu"))
menu:SetAttribute("*type1", nil)
Hud.menu = menu
menu.dot = menu:CreateTexture(nil, "OVERLAY")
menu.dot:SetTexture(DOT)
menu.dot:SetSize(22, 22)
menu.dot:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 4, 4)
menu.dot:Hide()

menu:HookScript("PostClick", function(_, mouse)
    if mouse ~= "LeftButton" then return end
    if ns.Menu and ns.Menu.Open then ns.Guard("hud menu", ns.Menu.Open) end
end)

-- The gold dot on Menu: a talent point, a quest ready to hand in, or a whisper nobody has read.
Hud.unreadWhisper = false

local function TalentWaiting()
    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local ok, waiting = pcall(C_ClassTalents.HasUnspentTalentPoints)
        if ok and waiting then return true end
    end
    if GetUnspentTalentPoints then
        local ok, points = pcall(GetUnspentTalentPoints)
        if ok and type(points) == "number" and points > 0 then return true end
    end
    return false
end

local function QuestReady()
    local log = C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.IsComplete) then return false end
    for i = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(i)
        if info and not info.isHeader and log.IsComplete(info.questID) and not log.IsFailed(info.questID) then
            return true
        end
    end
    return false
end

Hud.TalentWaiting, Hud.QuestReady = TalentWaiting, QuestReady

function Hud.MenuDot()
    return TalentWaiting() or QuestReady() or Hud.unreadWhisper
end

function Hud.ClearWhisper()
    Hud.unreadWhisper = false
    Hud.RefreshDot()
end

function Hud.RefreshDot() ShowIf(menu.dot, Hud.MenuDot()) end

-- ---------------------------------------------------------------------------------------
-- The minimap ring

local disc = CreateFrame("Frame", nil, ns.root)
disc:SetSize(DISC_D, DISC_D)
disc:EnableMouse(false)
disc:SetFrameLevel(2)
local discBack = disc:CreateTexture(nil, "BACKGROUND")
discBack:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
discBack:SetAllPoints(disc)
Hud.disc = disc

local noMap = Text(disc, 13)
noMap:SetTextColor(0.62, 0.62, 0.62)
noMap:SetJustifyH("CENTER")
noMap:SetWidth(140)
noMap:SetPoint("CENTER", disc, "CENTER", 0, 14)
noMap:SetText(ns.T("hud.noMap"))
noMap:Hide()
Hud.noMap = noMap
local arrow = disc:CreateTexture(nil, "ARTWORK")
arrow:SetTexture(ARROW)
arrow:SetSize(28, 28)
arrow:SetPoint("CENTER", disc, "CENTER", 0, -34)
arrow:Hide()
Hud.arrow = arrow

local border = CreateFrame("Frame", nil, ns.root)
border:SetSize(BORDER_SIZE, BORDER_SIZE)
border:EnableMouse(false)
border:SetFrameLevel(6)
-- our own ring and zone plate (R48): 256 x 256 units, its top-left 128 units left of the disc's centre
local borderArt = border:CreateTexture(nil, "ARTWORK")
borderArt:SetTexture(Kit.ART_MINIMAP)
borderArt:SetSize(MINIMAP_ART, MINIMAP_ART)
borderArt:SetPoint("TOPLEFT", border, "TOPLEFT", DISC_CX - BORDER_X - MINIMAP_ART / 2, 0)
Hud.borderArt = borderArt
Hud.border = border

local zoneText = Text(border, 16)
zoneText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
zoneText:SetJustifyH("CENTER")
zoneText:SetWordWrap(false)
zoneText:SetWidth(142 * MAP_K)
zoneText:SetPoint("CENTER", border, "TOPLEFT", (86 + 71) * MAP_K, -(4 * MAP_K + 10))
Hud.zoneText = zoneText

local coordText = Text(border, 13, Kit.FONT_NUMBER)
coordText:SetTextColor(1, 1, 1)
coordText:SetJustifyH("CENTER")
coordText:SetWidth(160)
coordText:SetPoint("CENTER", border, "TOPLEFT", DISC_CX - BORDER_X, -(DISC_CY + 103))
Hud.coordText = coordText

-- The touch area over the disc: a tap opens the world map; the pinch comes as the mouse wheel.
local minimap = CreateFrame("Button", "TouchPlayMinimap", ns.root, "SecureActionButtonTemplate")
minimap:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
minimap:SetSize(DISC_D, DISC_D)
minimap:RegisterForClicks("AnyUp")
minimap:SetAttribute("*type1", "click")
minimap:SetAttribute("type2", nil)
minimap:SetFrameLevel(8)
minimap:EnableMouseWheel(true)
Kit.AddPress(minimap, "round", minimap, 6)
Hud.minimap = minimap

local function Zoom(step)
    local map = _G.Minimap
    if not (map and map.GetZoom and map.SetZoom) then return end
    local zoom, levels = map:GetZoom(), map.GetZoomLevels and map:GetZoomLevels() or 6
    local target = math.max(0, math.min(levels - 1, zoom + step))
    if target ~= zoom then map:SetZoom(target) end
    Hud.RefreshZoomRings()
end
minimap:SetScript("OnMouseWheel", function(_, delta) Zoom(delta > 0 and 1 or -1) end)

local function ApplyMapAction()
    local cluster = _G.MinimapCluster
    local toggle = cluster and cluster.ZoneTextButton
    minimap:SetAttribute("clickbutton", toggle)
    minimap:SetAttribute("*type1", toggle and "click" or nil)
    minimap.hasToggle = toggle ~= nil
end
-- without the zone text button (this client may not have it) a plain tap opens the map from our code
minimap:HookScript("PostClick", function(self, mouse)
    if mouse == "LeftButton" and not self.hasToggle then OpenWindow("ToggleWorldMap") end
end)

local function Ring(d, icon, onClick)
    local b = Kit.RingButton(ns.root, d, icon)
    b:SetFrameLevel(10)
    b:SetScript("OnClick", onClick)
    return b
end

-- mail: the letter with a gold dot
local mail = Ring(MAIL_D, LETTER, nil)
mail:SetScript("OnClick", nil)
mail:EnableMouse(false)
mail.dot = mail:CreateTexture(nil, "OVERLAY")
mail.dot:SetTexture(DOT)
mail.dot:SetSize(20, 20)
mail.dot:SetPoint("TOPLEFT", mail, "TOPLEFT", 6, 8)
mail:Hide()
Hud.mail = mail

-- tracking: the icon of what is tracked now; a tap opens the game's own choice (from our code: out of a fight only)
local tracking = Ring(TRACK_D, nil, function()
    if InCombatLockdown() then return end
    local cluster = _G.MinimapCluster
    local button = cluster and cluster.Tracking and cluster.Tracking.Button
    if button and button.Click then ns.Guard("hud tracking", button.Click, button) end
end)
tracking:Hide()
Hud.tracking = tracking

-- zoom
local zoomIn = Ring(ZOOM_D, nil, function() Zoom(1) end)
local zoomOut = Ring(ZOOM_D, nil, function() Zoom(-1) end)
for button, label in pairs({ [zoomIn] = "hud.zoomIn", [zoomOut] = "hud.zoomOut" }) do
    button.icon:Hide()
    button.plus = Text(button, 22, Kit.FONT_NUMBER)
    button.plus:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    button.plus:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.plus:SetText(ns.T(label))
    button:Hide()
end
Hud.zoomIn, Hud.zoomOut = zoomIn, zoomOut

local baseZoom
function Hud.RefreshZoomRings()
    local map = _G.Minimap
    if not (map and map.GetZoom) then return end
    local zoom = map:GetZoom()
    if baseZoom == nil then baseZoom = zoom end
    local zoomed = zoom ~= baseZoom
    ShowIf(zoomIn, zoomed)
    ShowIf(zoomOut, zoomed)
end

-- Left-handed, the list sits right of the mirrored thumb side (mockup 87, x 380), under the game's buffs (iPad run 7:
-- they take the band under the target card at a readable size, Auras.lua); when large buttons raise the mirrored stance
-- row into the list's band, the list moves right of the row's last shown button (I5).
local function QuestTop()
    if not ns.LeftHanded() then return QUEST_Y end
    local bottom = ns.Auras and ns.Auras.Bottom and ns.Auras.Bottom()
    return bottom and math.max(QUEST_Y, bottom + QUEST_GAP / 2) or QUEST_Y
end

local function QuestX()
    if not ns.LeftHanded() then return QUEST_X end
    local x = QUEST_X_LEFT
    local scale = ns.FeelValue("textSize") or 1
    local top, bottom = QuestTop(), QuestTop() + QUEST_AREA_H * scale
    local bars = ns.ClassBars
    for _, b in ipairs(bars and bars.stance or {}) do
        local a = b.touchAnchor
        if a and b:IsShown() then
            local tx, ty, tw, th = ns.TapRect(a.x, a.y, a.w, a.h)
            if ty < bottom and top < ty + th then x = math.max(x, (tx + tw + QUEST_GAP) / scale) end
        end
    end
    return x
end

-- A hunter's or warlock's pet card sits under the player's card (Units.lua): the list starts below its touch area when
-- they share columns (small Text sizes bring the list up to y 160).
local QUEST_BELOW_PET = 2
local function QuestY(x)
    local scale = ns.FeelValue("textSize") or 1
    if ns.LeftHanded() then return QuestTop() / scale end
    local bottom = ns.Units and ns.Units.PetCardBottom and ns.Units.PetCardBottom()
    if not bottom then return QUEST_Y end
    local pet = ns.Units.petTap.touchAnchor
    if pet and x * scale >= pet.x + pet.w then return QUEST_Y end
    return math.max(QUEST_Y, (bottom + QUEST_BELOW_PET) / scale)
end

-- The list's touch area ends above whatever touch area is below it in its columns (the pet row, the thumb side, the
-- item column, Leave, Feed pet), QUEST_GAP clear: with large buttons or large text that leaves it shorter (iPad run 7:
-- left-handed it starts under the buffs; right-handed, Text size 1.4 with large buttons reached the pet row).
local below = {}
local function QuestHeight(x, y)
    local scale = ns.FeelValue("textSize") or 1
    local full = QUEST_AREA_H
    local x0, x1, y0 = x * scale, (x + QUEST_W) * scale, y * scale
    local limit = y0 + full * scale
    local function consider(fx, fy, fw, fh)
        if not fx then return end
        fx, fy, fw, fh = ns.TapRect(fx, fy, fw, fh)
        if fx < x1 and x0 < fx + fw and fy + fh > y0 and fy - QUEST_GAP < limit then
            limit = math.min(limit, fy - QUEST_GAP)
        end
    end
    for _, o in ipairs(ns.ThumbAreas(below)) do consider(o.x, o.y, o.w, o.h) end
    local bars = ns.ClassBars
    if bars then
        if ns.Units and ns.Units.HasPetCard and ns.Units.HasPetCard() then
            for _, b in ipairs(bars.pet or {}) do consider(ns.Final(b)) end
            consider(ns.Final(bars.call)); consider(ns.Final(bars.feed))
        end
        consider(ns.Final(bars.leave))
        for _, b in ipairs(bars.stance or {}) do if b:IsShown() then consider(ns.Final(b)) end end
    end
    for _, b in ipairs(ns.ItemRail and ns.ItemRail.buttons or {}) do consider(ns.Final(b)) end
    return math.max(QUEST_W / 4, (limit - y0) / scale)
end

-- The quest list's place (out of combat: it is a secure button). ClassBars asks again when the forms change.
function Hud.PlaceQuest()
    local x = QuestX()
    local y = QuestY(x)
    local h = QuestHeight(x, y)
    if quest:GetHeight() ~= h then quest:SetHeight(h) end
    ns.Anchor(quest, "TL", x, y, "text")
end

local banner
local function Place()
    ns.Anchor(disc, "TR", DISC_CX - DISC_D / 2, DISC_CY - DISC_D / 2)
    ns.Anchor(minimap, "TR", DISC_CX - DISC_D / 2, DISC_CY - DISC_D / 2)
    ns.Anchor(border, "TR", BORDER_X, 0)
    ns.Anchor(bags, "TR", ORB_X, BAGS_Y)
    ns.Anchor(menu, "TR", ORB_X, MENU_Y)
    ns.Anchor(mail, "TR", DISC_CX - 128 + 17 - MAIL_D / 2, DISC_CY + 10 + 17 - MAIL_D / 2)
    ns.Anchor(tracking, "TR", DISC_CX - 118, DISC_CY - 92)
    -- the zoom rings sit on the disc's edge, kept on the screen (the mockup clips them)
    ns.Anchor(zoomIn, "TR", DISC_CX + 46, DISC_CY + 36)
    ns.Anchor(zoomOut, "TR", DISC_CX + 64, DISC_CY - 6)
    -- left-handed: the quest list moves out of the way of the left thumb
    Hud.PlaceQuest()
    ns.Anchor(banner, "TL", 283, 250)
end

-- The game's Minimap moves into the ring (out of a fight) and Restore puts it back.
local saved
local want = false

local function TakeMinimap()
    local map = _G.Minimap
    if not want or not map or not map.SetParent then return end
    if not saved then
        saved = { parent = map:GetParent(), points = {}, w = map:GetWidth(), h = map:GetHeight(),
            level = map:GetFrameLevel(), strata = map:GetFrameStrata() }
        for i = 1, map:GetNumPoints() do saved.points[i] = { map:GetPoint(i) } end
        local backdrop = _G.MinimapBackdrop
        if backdrop then saved.backdropAlpha = backdrop:GetAlpha() end
    end
    map:SetParent(disc)
    map:SetFrameStrata(disc:GetFrameStrata())   -- the ring's (the play screen's, LOW): under the game's windows
    map:ClearAllPoints()
    map:SetPoint("CENTER", disc, "CENTER", 0, 0)
    map:SetSize(DISC_D, DISC_D)
    map:SetFrameLevel(disc:GetFrameLevel() + 1)
    -- the game's own ring art would sit on top of ours
    if _G.MinimapBackdrop then _G.MinimapBackdrop:SetAlpha(0) end
end

local function GiveMinimapBack()
    local map = _G.Minimap
    if not saved or not map then return end
    map:SetParent(saved.parent)
    if saved.strata then map:SetFrameStrata(saved.strata) end
    map:ClearAllPoints()
    for _, point in ipairs(saved.points) do map:SetPoint(unpack(point)) end
    map:SetSize(saved.w, saved.h)
    map:SetFrameLevel(saved.level)
    map:SetAlpha(1)
    if _G.MinimapBackdrop and saved.backdropAlpha then _G.MinimapBackdrop:SetAlpha(saved.backdropAlpha) end
    saved = nil
end

Hud.IsMinimapInRing = function() return saved ~= nil and _G.Minimap and _G.Minimap:GetParent() == disc end

-- Inside a dungeon or raid there is no map: the words and the arrow only.
local function InsideNoMap()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") and true or false
end

function Hud.RefreshMinimap()
    local none = InsideNoMap()
    ShowIf(noMap, none)
    ShowIf(arrow, none)
    local map = _G.Minimap
    if map and saved then map:SetAlpha(none and 0 or 1) end
    SetText(zoneText, GetMinimapZoneText and GetMinimapZoneText() or "")
    ShowIf(mail, HasNewMail and HasNewMail() or false)
    mail.dot:SetShown(mail:IsShown())
    -- the tracking icon: the one that is on
    local icon
    local info = C_Minimap
    if info and info.GetNumTrackingTypes and info.GetTrackingInfo then
        for i = 1, info.GetNumTrackingTypes() do
            local entry = info.GetTrackingInfo(i)
            if entry and entry.active then icon = entry.texture; break end
        end
    end
    if icon then
        if tracking.shownIcon ~= icon then tracking.shownIcon = icon; tracking.icon:SetTexture(icon) end
        ShowIf(tracking, true)
    else
        tracking.shownIcon = nil
        ShowIf(tracking, false)
    end
    Hud.RefreshZoomRings()
end

-- Coordinates and the clock: nothing says when they change, so one slow tick while the screen is on.
local function PositionOf(mapID)
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then return pos:GetXY() end
end

function Hud.RefreshCoords()
    local hours, minutes = 0, 0
    if GetGameTime then hours, minutes = GetGameTime() end
    local text = ("%d:%02d"):format(hours or 0, minutes or 0)
    if C_Map and C_Map.GetBestMapForUnit and not InsideNoMap() then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local ok, x, y = pcall(PositionOf, mapID)
            if ok and type(x) == "number" and Plain(x) and Plain(y) then
                text = ("%.1f, %.1f · %s"):format(x * 100, y * 100, text)
            end
        end
    end
    SetText(coordText, text)
end

-- The one ticker of this file: while the screen is on it redraws the coordinates and clock and the
-- away minutes. Layout starts it, Restore (a pause, "off", Edit Mode) cancels it, and it cancels
-- itself if it ever finds the add-on off or paused.
local ticker
local AfkMinutes          -- set with the away card, below

local function TickWork()
    Hud.RefreshCoords()
    if Hud.afk:IsShown() then AfkMinutes() end
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function Tick()
    if not ns.IsActive() then StopTicker(); return end
    ns.Guard("hud tick", TickWork)
end

local function StartTicker()
    if ticker or not C_Timer or not C_Timer.NewTicker then return end
    ticker = C_Timer.NewTicker(1, Tick)
end
Hud.HasTicker = function() return ticker ~= nil end

-- ---------------------------------------------------------------------------------------
-- The experience line, with the rested stretch (mockups 01, 32, 72)

local xp = CreateFrame("Frame", nil, ns.root)
xp:SetPoint("BOTTOMLEFT", ns.root, "BOTTOMLEFT", 0, 0)
xp:SetPoint("BOTTOMRIGHT", ns.root, "BOTTOMRIGHT", 0, 0)
xp:SetHeight(XP_HEIGHT)
xp:EnableMouse(false)
xp:SetFrameLevel(9)
local xpEdge = xp:CreateTexture(nil, "OVERLAY")
xpEdge:SetColorTexture(0.35, 0.29, 0.1, 1)
xpEdge:SetPoint("TOPLEFT", xp, "TOPLEFT", 0, 0)
xpEdge:SetPoint("TOPRIGHT", xp, "TOPRIGHT", 0, 0)
xpEdge:SetHeight(1)
local restedBar = Kit.Bar(xp, "xp")
restedBar:SetAllPoints(xp)
restedBar:SetStatusBarColor(0.05, 0.4, 0.88)
restedBar:EnableMouse(false)
restedBar.text:Hide()
local xpBar = Kit.Bar(xp, "xp")
xpBar:SetAllPoints(xp)
xpBar:SetFrameLevel(restedBar:GetFrameLevel() + 1)
xpBar:EnableMouse(false)
xpBar.bg:Hide()
xpBar.text:Hide()
local restedText = Text(ns.root, 13, Kit.FONT_NUMBER)
restedText:SetTextColor(0.44, 0.69, 1)
restedText:SetPoint("BOTTOM", ns.root, "BOTTOM", 0, 16)
restedText:Hide()
Hud.xp, Hud.restedBar, Hud.restedText = xpBar, restedBar, restedText

function Hud.RefreshXp()
    local max = UnitXPMax and UnitXPMax("player")
    if type(max) ~= "number" or not Plain(max) or max <= 0 then
        ShowIf(xp, false)
        ShowIf(restedText, false)
        return
    end
    ShowIf(xp, true)
    local have = UnitXP("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or nil
    xpBar:SetMinMaxValues(0, max)
    xpBar:SetValue(have)
    restedBar:SetMinMaxValues(0, max)
    restedBar:SetValue(rested and math.min(max, have + rested) or 0)
    local resting = IsResting and IsResting() and rested and rested > 0
    if resting then
        restedText:SetText(ns.T("hud.rested", (BreakUpLargeNumbers and BreakUpLargeNumbers(rested)) or tostring(rested)))
    end
    ShowIf(restedText, resting)
end

-- ---------------------------------------------------------------------------------------
-- The level-up banner (mockup 33). The game plays its own sound and burst.

banner = CreateFrame("Frame", nil, ns.root)
banner:SetSize(800, 110)
banner:EnableMouse(false)
banner:SetFrameLevel(30)
banner.title = Text(banner, 44)
banner.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
banner.title:SetShadowColor(0, 0, 0, 1)
banner.title:SetShadowOffset(2, -2)
banner.title:SetPoint("TOP", banner, "TOP", 0, 0)
banner.gains = Text(banner, 28)
banner.gains:SetTextColor(1, 1, 1)
banner.gains:SetPoint("TOP", banner.title, "BOTTOM", 0, -18)
banner:Hide()
Hud.banner = banner
Place()          -- every frame placed with ns.Anchor exists now
local bannerToken = 0

local function GainsText(health, power, talents)
    local parts = {}
    if type(health) == "number" and health > 0 then parts[#parts + 1] = ns.T("hud.levelUp.health", health) end
    if type(power) == "number" and power > 0 then
        local _, token = UnitPowerType("player")
        parts[#parts + 1] = ns.T(token == "MANA" and "hud.levelUp.mana" or "hud.levelUp.power", power)
    end
    if type(talents) == "number" and talents > 0 then
        parts[#parts + 1] = ns.T(talents == 1 and "hud.levelUp.talent" or "hud.levelUp.talents", talents)
    end
    return table.concat(parts, " · ")
end

function Hud.ShowLevelUp(level, health, power, talents)
    banner.title:SetText(ns.T("hud.levelUp", level))
    banner.gains:SetText(GainsText(health, power, talents))
    banner:Show()
    bannerToken = bannerToken + 1
    local mine = bannerToken
    C_Timer.After(LEVELUP_SECONDS, function() if mine == bannerToken then banner:Hide() end end)
end

-- ---------------------------------------------------------------------------------------
-- The screen edges (mockups 14, 19)

local edge = CreateFrame("Frame", nil, ns.root)
edge:SetAllPoints(ns.root)
edge:EnableMouse(false)
edge:SetFrameStrata("BACKGROUND")
edge.low = edge:CreateTexture(nil, "BACKGROUND")
edge.low:SetTexture(EDGE_ART)
edge.low:SetBlendMode("ADD")
edge.low:SetAllPoints(edge)
edge.low:SetAlpha(0)
edge.ghost = edge:CreateTexture(nil, "BACKGROUND")
edge.ghost:SetColorTexture(120 / 255, 160 / 255, 1, 0.14)
edge.ghost:SetAllPoints(edge)
edge.ghost:Hide()
Hud.edge = edge

function Hud.RefreshEdges()
    local ghost = UnitIsGhost("player") and true or false
    local dead = UnitIsDead("player") and true or false
    ShowIf(edge.ghost, ghost)
    local curve = ns.Units and ns.Units.LowCurve and ns.Units.LowCurve()
    if ghost or dead or not curve then
        edge.low:SetAlpha(0)
    else
        -- the percentage may be hidden: the game evaluates the curve, and the answer goes into the alpha
        edge.low:SetAlpha(UnitHealthPercent("player", true, curve))
    end
end

-- ---------------------------------------------------------------------------------------
-- The error text beside the button that was just pressed (mockup 25)

local errorFrame = CreateFrame("Frame", nil, ns.root)
errorFrame:SetSize(360, 30)
errorFrame:EnableMouse(false)
errorFrame:SetFrameLevel(40)
errorFrame.text = Text(errorFrame, 18)
errorFrame.text:SetTextColor(1, 0.13, 0.13)
errorFrame.text:SetJustifyH("RIGHT")
errorFrame.text:SetAllPoints(errorFrame)
errorFrame:Hide()
Hud.errorFrame = errorFrame

local lastPress = { button = nil, at = -100 }
local errorToken = 0

local function NotePress(self)
    lastPress.button, lastPress.at = self, GetTime()
end

function Hud.ShowError(message)
    local button = lastPress.button
    if not button or GetTime() - lastPress.at > ERROR_WINDOW then return false end
    errorFrame:ClearAllPoints()
    errorFrame:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, ERROR_LIFT)
    errorFrame.text:SetText(message)
    errorFrame:Show()
    Kit.PressError(button)                     -- and the button flashes red (the game said no)
    errorToken = errorToken + 1
    local mine = errorToken
    C_Timer.After(ERROR_SECONDS, function() if mine == errorToken then errorFrame:Hide() end end)
    return true
end

-- ---------------------------------------------------------------------------------------
-- The game's mirror timers: breath, fatigue, feign death

local mirrorSaved
local mirrorWant = false
local moving = false

local function MoveMirror()
    local box = _G.MirrorTimerContainer
    if not mirrorWant or not box then return end
    if not mirrorSaved then
        mirrorSaved = { point = { box:GetPoint(1) } }
    end
    moving = true
    box:ClearAllPoints()
    box:SetPoint("TOP", ns.root, "TOPLEFT", MIRROR_X + MIRROR_W / 2, -MIRROR_Y)
    for _, timer in ipairs(box.mirrorTimers or {}) do
        timer:SetWidth(MIRROR_W)
        if timer.StatusBar then timer.StatusBar:SetWidth(MIRROR_W - (MIRROR_OLD_W - MIRROR_OLD_BAR_W)) end
    end
    moving = false
end

local function MirrorBack()
    local box = _G.MirrorTimerContainer
    if not box or not mirrorSaved then return end
    moving = true
    box:ClearAllPoints()
    if mirrorSaved.point[1] then box:SetPoint(unpack(mirrorSaved.point)) end
    for _, timer in ipairs(box.mirrorTimers or {}) do
        timer:SetWidth(MIRROR_OLD_W)
        if timer.StatusBar then timer.StatusBar:SetWidth(MIRROR_OLD_BAR_W) end
    end
    moving = false
    mirrorSaved = nil
end

-- ---------------------------------------------------------------------------------------
-- Away (mockup 76): the screen dims and the first tap only wakes it

local afk = CreateFrame("Button", "TouchPlayAfk", ns.root)
afk:SetAllPoints(ns.root)
afk:SetFrameStrata("FULLSCREEN")
afk:RegisterForClicks("AnyUp")
afk.dim = afk:CreateTexture(nil, "BACKGROUND")
afk.dim:SetColorTexture(0, 0, 0, 0.55)
afk.dim:SetAllPoints(afk)
afk.card = Kit.Backdrop(afk, "gold", "dark")
afk.card:SetSize(500, 190)
afk.card:SetPoint("CENTER", afk, "TOP", 0, -(330 + 95))
afk.card:EnableMouse(false)
afk.title = Text(afk.card, 26)
afk.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
afk.title:SetPoint("TOP", afk.card, "TOP", 0, -34)
afk.title:SetText(ns.T("hud.afk.title"))
afk.tap = Text(afk.card, 18)
afk.tap:SetPoint("TOP", afk.title, "BOTTOM", 0, -14)
afk.tap:SetText(ns.T("hud.afk.tap"))
afk.minutes = Text(afk.card, 15)
afk.minutes:SetTextColor(GREY[1], GREY[2], GREY[3])
afk.minutes:SetPoint("TOP", afk.tap, "BOTTOM", 0, -8)
afk:Hide()
Hud.afk = afk

local afkSince

function AfkMinutes()
    local minutes = math.max(1, math.floor((GetTime() - (afkSince or GetTime())) / 60))
    SetText(afk.minutes, minutes == 1 and ns.T("hud.afk.minute") or ns.T("hud.afk.minutes", minutes))
end

function Hud.RefreshAfk()
    local away = UnitIsAFK and UnitIsAFK("player") and true or false
    if away == afk:IsShown() then return end
    if away then
        afkSince = GetTime()
        AfkMinutes()
        afk:Show()
    else
        afk:Hide()
    end
end

-- The tap wakes the screen and tells the game you are back (the one chat call here, from a tap).
afk:SetScript("OnClick", function()
    afk:Hide()
    if UnitIsAFK and UnitIsAFK("player") and C_ChatInfo and C_ChatInfo.SendChatMessage then
        ns.Guard("hud afk", C_ChatInfo.SendChatMessage, "", "AFK")
    end
end)

-- ---------------------------------------------------------------------------------------
-- Events

local function RefreshAll()
    Hud.RefreshQuests()
    Hud.RefreshMinimap()
    Hud.RefreshCoords()
    Hud.RefreshXp()
    Hud.RefreshEdges()
    Hud.RefreshDot()
    Hud.RefreshAfk()
end

local function QuestChanged() Hud.RefreshQuests(); Hud.RefreshDot() end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_REMOVED",
    "QUEST_TURNED_IN", "QUEST_WATCH_LIST_CHANGED" }) do
    ns.On(event, QuestChanged)
end
-- QUEST_ACCEPTED carries the quest ID last (a log index may come first in older clients).
ns.On("QUEST_ACCEPTED", function(...)
    local n = select("#", ...)
    local id = n > 0 and select(n, ...) or nil
    if type(id) == "number" then newQuests[id] = true end
    QuestChanged()
end)
ns.On("UPDATE_PENDING_MAIL", Hud.RefreshMinimap)
ns.On("MINIMAP_UPDATE_TRACKING", Hud.RefreshMinimap)
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    ns.On(event, function() Hud.RefreshMinimap(); Hud.RefreshCoords() end)
end
for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" }) do
    ns.On(event, Hud.RefreshXp)
end
ns.On("PLAYER_LEVEL_UP", function(level, health, power, talents)
    Hud.ShowLevelUp(level, health, power, talents)
    Hud.RefreshXp()
    Hud.RefreshDot()
end)
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    ns.On(event, Hud.RefreshDot)
end
ns.On("CHAT_MSG_WHISPER", function() Hud.unreadWhisper = true; Hud.RefreshDot() end)
ns.On("CHAT_MSG_BN_WHISPER", function() Hud.unreadWhisper = true; Hud.RefreshDot() end)
ns.On("PLAYER_ENTERING_WORLD", RefreshAll)
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do ns.On(event, Hud.RefreshEdges) end
ns.On("PLAYER_FLAGS_CHANGED", function(unit) if unit == nil or unit == "player" then Hud.RefreshAfk() end end)
ns.On("UI_ERROR_MESSAGE", function(_, message)
    if type(message) == "string" and Plain(message) then Hud.ShowError(message) end
end)

-- Health: only the player's own, through the step curve (a hidden number is never tested).
local health = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    pcall(health.RegisterUnitEvent, health, event, "player")
end
health:SetScript("OnEvent", function()
    if ns.IsActive() then ns.Guard("hud edge", Hud.RefreshEdges) end
end)

-- ---------------------------------------------------------------------------------------
-- Module steps

function Hud:Init()
    -- the seven spell buttons: the press is noted before the game's answer (an error comes
    -- during the click, not after it)
    local cluster = ns.Cluster
    if cluster then
        for _, button in ipairs(cluster.buttons) do button:HookScript("PreClick", NotePress) end
    end
    -- the item column too (polish pass): an item the game refuses flashes its slot red, with the error beside it
    local rail = ns.ItemRail
    if rail and rail.buttons then
        for _, button in ipairs(rail.buttons) do button:HookScript("PreClick", NotePress) end
    end
    local box = _G.MirrorTimerContainer
    if box and box.SetPoint then
        hooksecurefunc(box, "SetPoint", function()
            if mirrorWant and not moving then ns.Guard("hud mirror", MoveMirror) end
        end)
    end
    local Contract = ns.Contract
    if not Contract then return end
    Contract.Area("quest", quest, { anchor = "TL",
        tap = { command = "TOGGLEQUESTLOG", gate = questGate },
        hold = { click = "TouchPlayQuest", button = "RightButton" } })
    Contract.Area("minimap", minimap, { anchor = "TR",
        tap = { command = "TOGGLEWORLDMAP" } })
    Contract.Area("bags", bags, { anchor = "TR",
        tap = { command = "OPENALLBAGS" } })
    Contract.Area("menu", menu, { anchor = "TR",
        tap = { click = "TouchPlayMenu", button = "LeftButton" } })
end

function Hud:Layout()
    ns.Queue("hud layout", function()
        Place()
        ApplyMapAction()
    end)
    -- while Edit Mode is open the minimap and the mirror timers are the game's (R44)
    if ns.inEditMode then return end
    want, mirrorWant = true, true
    ns.Queue("hud minimap", TakeMinimap)
    MoveMirror()
    StartTicker()
end

function Hud:Refresh()
    RefreshAll()
end

function Hud:Restore()
    want, mirrorWant = false, false
    ns.Queue("hud minimap", GiveMinimapBack)
    MirrorBack()
    StopTicker()
end
