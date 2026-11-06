-- Interface mobile : la carte des quêtes. Elle remplace le suivi des objectifs sous la
-- mini-carte, illisible sur tablette : en haut à gauche sous ta barre, en gros texte, les
-- quêtes suivies d'abord, avec leurs objectifs (en vert quand c'est fait) et « À rendre »
-- quand la quête est finie. Toucher l'en-tête la replie ; toucher une quête ouvre le journal.

local _, ns = ...

local Objectives = ns.Register("Quêtes", {})
local WIDTH = 320
local MAX_QUESTS = 5
local MAX_LINES = 4

local card, header, body, blocks

local function Collect()
    local list = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden and info.title then
                local objectives = {}
                local raw = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID)
                for _, objective in ipairs(raw or {}) do
                    objectives[#objectives + 1] = { text = objective.text, done = objective.finished }
                end
                list[#list + 1] = {
                    title = info.title, level = info.level, objectives = objectives, index = i,
                    complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID),
                    watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(info.questID) ~= nil,
                }
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
            if title and not isHeader then
                local objectives = {}
                for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
                    local text, _, finished = GetQuestLogLeaderBoard(j, i)
                    if text then objectives[#objectives + 1] = { text = text, done = finished } end
                end
                list[#list + 1] = {
                    title = title, level = level, objectives = objectives, index = i,
                    complete = isComplete == 1 or isComplete == true,
                    watched = IsQuestWatched and IsQuestWatched(i) and true or false,
                }
            end
        end
    end
    -- Les quêtes suivies d'abord, puis dans l'ordre du journal.
    table.sort(list, function(a, b)
        if a.watched ~= b.watched then return a.watched end
        return a.index < b.index
    end)
    return list
end

local function OpenLog()
    if ToggleQuestLog then
        ToggleQuestLog()
    elseif QuestLogMicroButton then
        QuestLogMicroButton:Click()
    end
end

local function Render()
    if not card or not ns.db then return end
    local quests = Collect()
    local settings = ns.db.quests
    header.text:SetText(("Quêtes (%d)  %s"):format(#quests, settings.collapsed and "+" or "-"))
    local y = 0
    for i = 1, MAX_QUESTS do
        local block, quest = blocks[i], quests[i]
        if quest and i <= settings.shown and not settings.collapsed then
            block:ClearAllPoints()
            block:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            block.title:SetText(("[%s] %s"):format(quest.level or "?", quest.title))
            local height = block.title:GetStringHeight() + 4
            for j = 1, MAX_LINES do
                local line, objective = block.lines[j], quest.objectives[j]
                if quest.complete and j == 1 then
                    line:SetText("À rendre")
                    line:SetTextColor(0.3, 1, 0.3)
                    line:Show()
                elseif objective and not quest.complete then
                    line:SetText(objective.text)
                    if objective.done then line:SetTextColor(0.3, 1, 0.3) else line:SetTextColor(0.9, 0.9, 0.9) end
                    line:Show()
                else
                    line:SetText("")
                    line:Hide()
                end
                if line:IsShown() then
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -height)
                    height = height + line:GetStringHeight() + 2
                end
            end
            block:SetHeight(height + 6)
            block:Show()
            y = y + height + 8
        else
            block:Hide()
        end
    end
    body:SetHeight(math.max(1, y))
    card:SetHeight(header:GetHeight() + (settings.collapsed and 0 or y) + 6)
end

function Objectives:Init()
    card = CreateFrame("Frame", "WolkaraMobileQuests", UIParent)
    card:SetSize(WIDTH, 40)
    card:SetFrameStrata("LOW")
    ns.Box(card, "BACKGROUND", 0, 0, 0, 0.35)
    card.glow = ns.EditFrame(card)
    ns.Movable(card, function() return ns.db.quests end, "pos", { "TOPLEFT", "TOPLEFT", 12, -92 })

    header = CreateFrame("Button", nil, card)
    header:SetSize(WIDTH, 34)
    header:SetPoint("TOPLEFT")
    header:RegisterForClicks("AnyUp")
    header.text = ns.Label(header, "GameFontNormalLarge")
    header.text:SetPoint("LEFT", 10, 0)
    header:SetScript("OnClick", function()
        if ns.editing then return end
        ns.db.quests.collapsed = not ns.db.quests.collapsed
        Render()
    end)
    ns.DragHandle(header, card)

    body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetSize(WIDTH, 1)

    blocks = {}
    for i = 1, MAX_QUESTS do
        local block = CreateFrame("Button", nil, body)
        block:SetWidth(WIDTH)
        block:RegisterForClicks("AnyUp")
        block.title = ns.Label(block, "GameFontNormal")
        block.title:SetPoint("TOPLEFT", 8, 0)
        block.title:SetWidth(WIDTH - 16)
        block.title:SetJustifyH("LEFT")
        block.lines = {}
        for j = 1, MAX_LINES do
            local line = ns.Label(block, "GameFontHighlight")
            line:SetWidth(WIDTH - 24)
            line:SetJustifyH("LEFT")
            block.lines[j] = line
        end
        local highlight = ns.Box(block, "HIGHLIGHT", 1, 1, 1, 0.08)
        highlight:SetBlendMode("ADD")
        block:SetScript("OnClick", function() if not ns.editing then ns.Guard("journal", OpenLog) end end)
        ns.DragHandle(block, card)
        block:Hide()
        blocks[i] = block
    end
end

function Objectives:Layout()
    if ns.db.quests.enabled then
        card:PlaceSaved()
        card:Show()
        Render()
    else
        card:Hide()
    end
end

function Objectives:Refresh() if ns.db and ns.db.quests.enabled then Render() end end

function Objectives:SetEditing(on)
    card.glow:SetShown(on)
    card:EnableMouse(on)
end

for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
        "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_WATCH_LIST_CHANGED" }) do
    ns.On(event, function() Objectives:Refresh() end)
end
