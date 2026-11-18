-- TouchPlay: the class bars: stance and form buttons, the pet bar, Leave for vehicles, and the
-- caption that names your form; and for a hunter, Call pet / Revive pet and Feed pet (mockup 21).
--
-- Every button is one of the game's own: a stance or form is a secure spell button (tap casts
-- the form), a pet button is the game's PetActionButtonTemplate on the pet's slots 1 to 10 (tap
-- commands the pet), Leave is a secure /leavevehicle macro. A tap acts and nothing else does: a
-- hold opens the info card (the spell for a stance, the pet action for a pet button) and never
-- casts. The game's own right click on a pet button toggles autocast; a secure wrapper stops that
-- click reaching the game's handler, and the card's Autocast button does the toggle instead.
--
-- Secure attributes and positions change only out of combat (ns.Queue). What is shown in a fight
-- is shown by the game's state drivers: the pet bar while a living pet exists (and not in a
-- vehicle, an override bar or a possess bar), Leave with `[vehicleui][overridebar]`, the stance
-- bar away in a vehicle, an override bar or a possess bar. Pictures,
-- colours, checked marks and the caption are plain textures and text, so they stay current in a
-- fight; plain cooldown numbers go to the cooldown frame (hidden ones are refused from add-on code, so skipped).
--
-- Positions (layout units, 1366 x 1024): the pet row is 52-unit buttons, 10 apart, centred above
-- the chat strip (centre x 580) at y 820; the stance row is the same buttons just left of the
-- page boxes (right edge fixed at x 1140, centred on their height, growing leftward); the
-- caption sits above the page boxes at (1100, 532). Call / Revive pet sits on pet slot 5's square while the bar is
-- away; Feed pet sits above slot 5 with the red "Unhappy" line to its left.
--
-- The layout contract (16 Nov): the app's taps on the world are mouse clicks, which proved unreliable for buttons, so
-- these buttons are contract areas with keys, like the cluster. The app reads the list only after a reload, so the
-- areas follow what the character can have, not what is on screen: a class with forms has one stance area per form;
-- a hunter or a warlock has the ten pet slots (and a hunter Feed pet), pet out or not; everyone has Leave. A pet
-- slot's keys click a hidden secure "key button" whose action the game's own conditions pick, in a fight too: the
-- pet's action while it lives; in a vehicle, /leavevehicle for the slots that lie under Leave; with no pet or a dead
-- one, Call or Revive Pet on slot 5 (a hunter's), and nothing on the other slots. The game's pet button is never
-- clicked by a key: with Shift held (the app holds Ctrl, Alt and Shift) it would pick the action up.

local ADDON_NAME, ns = ...

local ClassBars = ns.Register("ClassBars", {})

ns.L["classbars.leave"] = "Leave"
ns.L["classbars.prowling"] = "Prowling"
ns.L["classbars.stealthed"] = "Stealthed"
ns.L["classbars.caption"] = "%s · %s"
ns.L["classbars.unhappy"] = "Unhappy · deals less damage"

-- Mockup numbers.
local SIZE, GAP, ROW_Y = 52, 10, 820
local STEP = SIZE + GAP
local CENTRE_X = 580                          -- the chat strip: 296 + 568 / 2
local SCREEN_W = 1366
local CORNER = "BL"                       -- the pet row and Leave: nearest corner is bottom-left
local STANCE_CORNER = "BR"                -- the stance row sits with the page boxes at the right
local STANCE_RIGHT = 1140                 -- its right edge: 16 units left of page box 1 (x 1156 at Button size 1)
local STANCE_Y = 566 + 21 - SIZE / 2      -- centred on the page boxes (y 566, 42 tall)
local MAX_FORMS, PET_SLOTS = 10, 10
local LEAVE_W = 170
local CAPTION_X, CAPTION_Y, CAPTION_W, CAPTION_H = 1100, 532, 220, 20
local MOOD_W = 4 * STEP - GAP                 -- the mood line: over slots 1 to 4, left of Feed pet
local CALL_SLOT = 5                           -- Call / Revive pet sit on this slot; Feed pet above it
local CALL_PET, REVIVE_PET, FEED_PET = 883, 982, 6991
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local SEPARATORS = { 3, 7 }                   -- after these pet slots: commands | abilities | stances
local EMPTY_ALPHA = 0.35
local UNHAPPY = 1                             -- C_PetInfo.GetPetHappiness: 1 mad, 2 neutral, 3 happy
local MOOD_ICON = "UI-PetMad"                 -- the game's own atlas for it
local GOLD, WHITE = { 1, 0.82, 0, 1 }, { 1, 1, 1, 1 }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The pet row and Leave sit under the chat strip; left-handed mirrors the strip, so their centre mirrors too
-- (R33), which keeps them clear of the mirrored Interact ring and spell ring.
local function CentreX() return ns.LeftHanded() and (SCREEN_W - CENTRE_X) or CENTRE_X end

local function RowStart(n) return CentreX() - (n * SIZE + (n - 1) * GAP) / 2 end

local function TapSound(_, button)
    if button == "LeftButton" then ns.Kit.Sound("tap") end
end

-- ---------------------------------------------------------------------------------------
-- Stance and form buttons

-- The bar is a plain frame so the game's visibility driver can take it away in a vehicle; each
-- button is shown or hidden (out of combat) by how many forms the class has.
local stanceBar = CreateFrame("Frame", "TouchPlayStanceBar", ns.root)
stanceBar:SetAllPoints(ns.root)
ClassBars.stanceBar = stanceBar

-- A hold (the right click the hold key sends) asks the info card about the form's spell; it never casts.
local function StancePostClick(self, button)
    if button ~= "RightButton" or not ns.InfoCard then return end
    local spellID = self:GetAttribute("spell")
    if not spellID then return end
    ns.Guard("stance hold", function()
        ns.InfoCard.Show({ kind = "spell", spellID = spellID }, self)
    end)
end

local function NewStanceButton(i)
    local b = CreateFrame("Button", "TouchPlayStance" .. i, stanceBar, "SecureActionButtonTemplate")
    b:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    -- Only a left click casts (*type1: with any keys held, as the app sends them). With no generic `type`, a
    -- right click has nothing to do.
    b:SetAttribute("*type1", "spell")
    -- the picture: the game's tooltip frame (as the page boxes) with the form's icon in it
    local art = ns.Kit.Backdrop(b, "tooltip", "tooltip")
    art:SetAllPoints(b)
    art:EnableMouse(false)
    b.art = art
    b.icon = art:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", art, "TOPLEFT", 5, -5)
    b.icon:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -5, 5)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cooldown = CreateFrame("Cooldown", nil, art, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(art)
    b.active = false
    ns.Kit.AddPress(b, "square", art, 1)    -- pressed: the pale-gold edge (polish pass)
    b:HookScript("PostClick", TapSound)
    b:HookScript("PostClick", StancePostClick)
    b:Hide()
    return b
end

ClassBars.stance = {}
for i = 1, MAX_FORMS do ClassBars.stance[i] = NewStanceButton(i) end

local formCount = 0                           -- buttons shown now

-- Which form you are in, which can be used, their cooldowns: pictures only, safe in a fight.
local function UpdateFormCooldowns()
    if not GetShapeshiftFormCooldown then return end
    for i = 1, formCount do
        local start, duration = GetShapeshiftFormCooldown(i)
        -- SetCooldown refuses a hidden value from add-on code: hidden in a fight, the sweep waits
        if ns.Plain(start) and ns.Plain(duration) then ClassBars.stance[i].cooldown:SetCooldown(start, duration) end
    end
end

local function UpdateFormState()
    if not GetShapeshiftFormInfo then return end
    for i = 1, formCount do
        local b = ClassBars.stance[i]
        local texture, isActive, isCastable = GetShapeshiftFormInfo(i)
        if b.lastTexture ~= texture then
            b.lastTexture = texture
            b.icon:SetTexture(texture)
        end
        isActive = isActive and true or false
        if b.active ~= isActive then
            b.active = isActive
            local c = isActive and GOLD or WHITE
            b.art:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
        end
        isCastable = isCastable and true or false
        if b.lastCastable ~= isCastable then
            b.lastCastable = isCastable
            local v = isCastable and 1 or 0.4
            b.icon:SetVertexColor(v, v, v)
        end
    end
    UpdateFormCooldowns()
end

-- Button 1 is leftmost; the right edge stays 16 units left of page box 1, so the row grows leftward.
local function StanceRight()
    local cluster = ns.Cluster
    if cluster and cluster.PageX then return cluster.PageX(1) - (1156 - STANCE_RIGHT) end
    return STANCE_RIGHT
end

local function PlaceStance()
    local n = math.max(formCount, 1)
    local start = StanceRight() - (n * SIZE + (n - 1) * GAP)
    for i = 1, MAX_FORMS do
        ns.Anchor(ClassBars.stance[i], STANCE_CORNER, start + (i - 1) * STEP, STANCE_Y, true)
    end
end

-- How many forms the class has, and the spell each button casts. Out of combat only: a form
-- learnt in a fight appears when it ends.
local function SyncForms()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    if n > MAX_FORMS then n = MAX_FORMS end
    for i = 1, MAX_FORMS do
        local b = ClassBars.stance[i]
        if i <= n then
            local spellID = select(4, GetShapeshiftFormInfo(i))
            if spellID and b:GetAttribute("spell") ~= spellID then b:SetAttribute("spell", spellID) end
            if not b:IsShown() then b:Show() end
        elseif b:IsShown() then
            b:Hide()
        end
    end
    formCount = n
    PlaceStance()
    UpdateFormState()
    -- left-handed, the quest list keeps clear of the row (Hud.lua); out of combat here, as the list is secure
    if ns.Hud and ns.Hud.PlaceQuest then ns.Hud.PlaceQuest() end
    -- a stance learnt or lost changes the contract's areas
    if ClassBars.RegisterAreas then ClassBars.RegisterAreas() end
end

-- ---------------------------------------------------------------------------------------
-- The caption: "Cat Form · Prowling" above the page boxes (mockup 73)

local captionFrame = CreateFrame("Frame", "TouchPlayFormCaption", ns.root)
captionFrame:SetSize(CAPTION_W, CAPTION_H)
captionFrame:Hide()
local captionText = captionFrame:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(captionText, ns.Kit.FONT_TITLE, 15, "")
captionText:SetTextColor(1, 0.82, 0)
captionText:SetJustifyH("RIGHT")
captionText:SetAllPoints(captionFrame)
captionFrame.text = captionText
ClassBars.caption = captionFrame

local function SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local isDruid
local function PlayerIsDruid()
    if isDruid == nil then
        local class = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
        isDruid = class == "DRUID"
    end
    return isDruid
end

local lastCaptionKey
local function UpdateCaption()
    local index = GetShapeshiftForm and GetShapeshiftForm() or 0
    local stealthed = IsStealthed and IsStealthed() and true or false
    local key = index * 2 + (stealthed and 1 or 0)
    if key == lastCaptionKey then return end
    lastCaptionKey = key
    local name = index > 0 and GetShapeshiftFormInfo and SpellName(select(4, GetShapeshiftFormInfo(index))) or nil
    local text
    if name then
        -- a druid in a stealthed form is prowling; another class's stealth form already says it
        if stealthed and PlayerIsDruid() then
            text = ns.T("classbars.caption", name, ns.T("classbars.prowling"))
        else
            text = name
        end
    elseif stealthed then
        text = ns.T("classbars.stealthed")
    end
    if text then captionText:SetText(text) end
    captionFrame:SetShown(text ~= nil)
end

-- ---------------------------------------------------------------------------------------
-- The pet bar

local petBar = CreateFrame("Frame", "TouchPlayPetBar", ns.root)
petBar:SetAllPoints(ns.root)
petBar:Hide()                                  -- the driver shows it while there is a pet
ClassBars.petBar = petBar

-- A hold asks the info card about the pet action in that slot; it never commands the pet.
local function PetPostClick(self, button)
    self.lastActive = nil                       -- the game clears the mark on a click; the next update restores it
    TapSound(self, button)
    if button ~= "RightButton" or not ns.InfoCard or not GetPetActionInfo(self:GetID()) then return end
    ns.Guard("pet hold", function()
        ns.InfoCard.Show({ kind = "petAction", index = self:GetID() }, self)
    end)
end

-- The game's pet button toggles autocast on a right click. This wrapper (secure, so it works in a
-- fight) keeps that click from reaching the game's handler: the hold opens the card instead, and
-- the card's Autocast button is the way to toggle.
local petGuard = CreateFrame("Frame", "TouchPlayPetGuard", ns.root, "SecureHandlerBaseTemplate")
local HOLD_BODY = [[ if button == "RightButton" then return false end ]]

local function NewPetButton(i)
    local b = CreateFrame("CheckButton", "TouchPlayPet" .. i, petBar, "PetActionButtonTemplate")
    b:SetID(i)
    b.index = i
    b.lastIcon = false                          -- nothing drawn yet: the first update draws it
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    ns.Kit.FitActionButton(b, SIZE)             -- the game's small button is made for 30 units: icon and frame fill ours
    if b.AutoCastOverlay then b.AutoCastOverlay:SetSize(SIZE, SIZE) end
    if b.HotKey then b.HotKey:SetAlpha(0) end   -- no key labels: the keys belong to the app
    if SecureHandlerWrapScript then SecureHandlerWrapScript(b, "OnClick", petGuard, HOLD_BODY) end
    ns.Kit.AddPress(b, "square")
    b:HookScript("PostClick", PetPostClick)
    return b
end

ClassBars.pet = {}
for i = 1, PET_SLOTS do ClassBars.pet[i] = NewPetButton(i) end

-- thin gold lines between the commands, the pet's abilities and its stances
local separators = {}
for n, after in ipairs(SEPARATORS) do
    local line = petBar:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetSize(1, SIZE)
    line.after = after
    separators[n] = line
end

-- the unhappy hunter's pet: the game's icon and a red line (mockup 21)
local mood = CreateFrame("Frame", "TouchPlayPetMood", petBar)
mood:SetSize(MOOD_W, 24)
mood:Hide()
mood.icon = mood:CreateTexture(nil, "ARTWORK")
mood.icon:SetSize(24, 24)
mood.icon:SetPoint("LEFT", mood, "LEFT", 0, 0)
if mood.icon.SetAtlas then mood.icon:SetAtlas(MOOD_ICON) end
mood.text = mood:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(mood.text, ns.Kit.FONT_TITLE, 14, "")
mood.text:SetTextColor(1, 0.125, 0.125)
mood.text:SetPoint("LEFT", mood.icon, "RIGHT", 6, 0)
mood.text:SetText(ns.T("classbars.unhappy"))
ClassBars.mood = mood

-- ---------------------------------------------------------------------------------------
-- The pet slots' keys: hidden secure buttons the game points at the right action (see the header)

local PET_KEY_BODY = [[
    if name ~= "state-petkey" and name ~= "underleave" and name ~= "callspell" and name ~= "revivespell" then return end
    local state = self:GetAttribute("state-petkey")
    local kind, action, spell, macro
    if state == "leave" then
        if self:GetAttribute("underleave") then kind, macro = "macro", "/leavevehicle" end
    elseif state == "pet" then
        kind, action = "pet", self:GetAttribute("slot")
    elseif state == "dead" then
        spell = self:GetAttribute("revivespell")
        if spell then kind = "spell" end
    else
        spell = self:GetAttribute("callspell")
        if spell then kind = "spell" end
    end
    self:SetAttribute("*type1", kind)
    self:SetAttribute("*action1", action)
    self:SetAttribute("*spell1", spell)
    self:SetAttribute("*macrotext1", macro)
]]
local PET_KEY_STATES = "[vehicleui][overridebar] leave; [@pet,exists,nodead] pet; [@pet,exists,dead] dead; none"

-- A hold on a slot: the card for the pet's action there, or for Call / Revive Pet on slot 5; never an action.
local function PetKeyPostClick(self, button)
    TapSound(self, button)
    if button ~= "RightButton" or not ns.InfoCard then return end
    local state, slot = self:GetAttribute("state-petkey"), self.slot
    local subject, anchor
    if state == "pet" and GetPetActionInfo(slot) then
        subject, anchor = { kind = "petAction", index = slot }, ClassBars.pet[slot]
    elseif (state == "none" or state == "dead") and self:GetAttribute("*spell1") then
        subject, anchor = { kind = "spell", spellID = self:GetAttribute("*spell1") }, ClassBars.call
    end
    if subject then ns.Guard("pet key hold", function() ns.InfoCard.Show(subject, anchor) end) end
end

local function NewPetKey(i)
    local k = CreateFrame("Button", "TouchPlayPetKey" .. i, UIParent, "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    k:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
    k:RegisterForClicks("AnyUp")
    k:SetAttribute("_onattributechanged", PET_KEY_BODY)
    k:SetAttribute("slot", i)
    k:SetAttribute("state-petkey", "none")
    k.slot = i
    k:Hide()
    k:HookScript("PostClick", PetKeyPostClick)
    RegisterStateDriver(k, "petkey", PET_KEY_STATES)
    return k
end

ClassBars.petKey = {}
for i = 1, PET_SLOTS do ClassBars.petKey[i] = NewPetKey(i) end

-- ---------------------------------------------------------------------------------------
-- Call pet / Revive pet (a hunter's): on slot 5's square while the bar is away, gold-bordered (mockup 21)

local call = CreateFrame("Button", "TouchPlayPetCall", ns.root, "SecureActionButtonTemplate")
call:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
call:SetSize(SIZE, SIZE)
call:RegisterForClicks("AnyUp")
-- a plain click (the game's windows: plain taps) does what slot 5's key does
call:SetAttribute("*type1", "click")
call:SetAttribute("*clickbutton1", ClassBars.petKey[CALL_SLOT])
do
    local art = ns.Kit.Backdrop(call, "tooltip", "tooltip")
    art:SetAllPoints(call)
    art:EnableMouse(false)
    art:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    call.art = art
    call.icon = art:CreateTexture(nil, "ARTWORK")
    call.icon:SetPoint("TOPLEFT", art, "TOPLEFT", 5, -5)
    call.icon:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -5, 5)
    call.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
call:HookScript("PostClick", TapSound)
ns.Kit.AddPress(call, "square", call.art, 1)
call:Hide()                                    -- a driver shows it, for a hunter who knows Call Pet (SyncPet)
ClassBars.call = call

-- ---------------------------------------------------------------------------------------
-- Feed pet (a hunter's): lights up above the bar while the pet is unhappy (mockup 21). A pet cannot be fed in a
-- fight, so the button comes and goes out of combat only; the red line beside it shows at once.

local feed = CreateFrame("Button", "TouchPlayPetFeed", petBar, "SecureActionButtonTemplate")
feed:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
feed:SetSize(SIZE, SIZE)
feed:RegisterForClicks("AnyUp")
do
    local art = ns.Kit.Backdrop(feed, "tooltip", "tooltip")
    art:SetAllPoints(feed)
    art:EnableMouse(false)
    art:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    feed.art = art
    feed.icon = art:CreateTexture(nil, "ARTWORK")
    feed.icon:SetPoint("TOPLEFT", art, "TOPLEFT", 5, -5)
    feed.icon:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -5, 5)
    feed.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- "lights up": the game's gold button glow round it
    feed.glow = art:CreateTexture(nil, "OVERLAY")
    feed.glow:SetTexture(GLOW_TEXTURE)
    feed.glow:SetBlendMode("ADD")
    feed.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    feed.glow:SetPoint("TOPLEFT", art, "TOPLEFT", -SIZE * 0.35, SIZE * 0.35)
    feed.glow:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", SIZE * 0.35, -SIZE * 0.35)
end
feed:HookScript("PostClick", TapSound)
ns.Kit.AddPress(feed, "square", feed.art, 1)
-- a hold on it: what Feed Pet does (the game's spell card)
feed:HookScript("PostClick", function(self, button)
    if button ~= "RightButton" or not ns.InfoCard or not self:GetAttribute("*spell1") then return end
    ns.Guard("feed hold", function() ns.InfoCard.Show({ kind = "spell", spellID = self:GetAttribute("*spell1") }, self) end)
end)
feed:Hide()
ClassBars.feed = feed

-- ---------------------------------------------------------------------------------------
-- What the character can have

local function PlayerClass()
    return UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
end

local function Knows(spellID)
    if IsPlayerSpell then return IsPlayerSpell(spellID) and true or false end
    if IsSpellKnown then return IsSpellKnown(spellID) and true or false end
    return true
end

local function IsHunter() return PlayerClass() == "HUNTER" end
local function HasPetRow() return ns.Units ~= nil and ns.Units.PET_CLASSES[PlayerClass()] == true end

-- ---------------------------------------------------------------------------------------
-- Placement of the pet row and its neighbours

-- The highest y at or above `y` (layout units) where a SIZE-tall box from x0 to x1 clears the thumb side's touch
-- areas (ns.ThumbAreas) by the row's own 10-unit gap: y 820 under the chat lines for the row, raised as far as it
-- takes when a stand or large buttons bring the thumb side down over it (I5).
local thumbAreas = {}
local function ClearY(x0, x1, y)
    local list = ns.ThumbAreas(thumbAreas)
    local moved = true
    while moved do
        moved = false
        for _, o in ipairs(list) do
            if o.x < x1 and x0 < o.x + o.w and o.y < y + SIZE + GAP and y < o.y + o.h + GAP then
                y = o.y - GAP - SIZE
                moved = true
            end
        end
    end
    return y
end

local rowY = ROW_Y

local function PlacePet()
    local start = RowStart(PET_SLOTS)
    rowY = ClearY(start, start + PET_SLOTS * SIZE + (PET_SLOTS - 1) * GAP, ROW_Y)
    for i = 1, PET_SLOTS do ns.Anchor(ClassBars.pet[i], CORNER, start + (i - 1) * STEP, rowY) end
    for _, line in ipairs(separators) do
        ns.Anchor(line, CORNER, start + line.after * STEP - GAP / 2 - 0.5, rowY)
    end
    ns.Anchor(call, CORNER, start + (CALL_SLOT - 1) * STEP, rowY)
    -- Feed pet above slot 5, the red line to its left (over slots 1 to 4)
    local feedX = start + (CALL_SLOT - 1) * STEP
    local feedY = ClearY(feedX, feedX + SIZE, rowY - GAP - SIZE)
    ns.Anchor(feed, CORNER, feedX, feedY)
    ns.Anchor(mood, CORNER, start, feedY + (SIZE - 24) / 2)
end

local function UpdateMood()
    local happiness = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
    local level = happiness and happiness()
    local hunter = true
    if HasPetUI then hunter = select(2, HasPetUI()) and true or false end
    local on = hunter and level == UNHAPPY
    if mood:IsShown() ~= on then mood:SetShown(on) end
    -- Feed pet follows out of combat (it is a secure button)
    if (feed:IsShown() and true or false) ~= (on and IsHunter() and Knows(FEED_PET)) then
        ns.Queue("classbars feed", ClassBars.SyncFeed)
    end
end

-- Feed pet shows (and its key feeds) only while the hunter's pet is unhappy; otherwise its key does nothing.
function ClassBars.SyncFeed()
    local on = mood:IsShown() and IsHunter() and Knows(FEED_PET)
    feed:SetAttribute("*type1", on and "spell" or nil)
    feed:SetAttribute("*spell1", on and FEED_PET or nil)
    if on then
        feed.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(FEED_PET) or nil)
        feed:Show()
    else
        feed:Hide()
    end
end

-- The picture on Call / Revive pet: plain texture, current in a fight.
local function UpdateCall()
    local dead = UnitExists("pet") and UnitIsDead("pet") and true or false
    if call.dead == dead then return end
    call.dead = dead
    local id = dead and REVIVE_PET or CALL_PET
    call.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil)
end

local function UpdatePetCooldowns()
    if not GetPetActionCooldown then return end
    for i = 1, PET_SLOTS do
        local start, duration = GetPetActionCooldown(i)
        -- SetCooldown refuses a hidden value from add-on code: hidden in a fight, the sweep waits
        if ns.Plain(start) and ns.Plain(duration) then ClassBars.pet[i].cooldown:SetCooldown(start, duration) end
    end
end

local function UpdatePet()
    for i = 1, PET_SLOTS do
        local b = ClassBars.pet[i]
        local name, texture, isToken, isActive, autoAllowed, autoOn = GetPetActionInfo(i)
        local icon = nil
        if texture then icon = isToken and _G[texture] or texture end
        if b.lastIcon ~= icon then
            b.lastIcon = icon
            b.icon:SetTexture(icon)
            b.icon:SetShown(icon ~= nil)
            b:SetAlpha(icon and 1 or EMPTY_ALPHA)   -- an empty slot stays on screen as a quiet frame
        end
        isActive = isActive and true or false
        if b.lastActive ~= isActive then
            b.lastActive = isActive
            b:SetChecked(isActive)
        end
        local auto = (autoAllowed and 1 or 0) + (autoOn and 2 or 0)
        if b.lastAuto ~= auto then
            b.lastAuto = auto
            local overlay = b.AutoCastOverlay
            if overlay then
                overlay:SetShown(autoAllowed and true or false)
                if overlay.ShowAutoCastEnabled then overlay:ShowAutoCastEnabled(autoOn and true or false) end
            end
        end
        if icon then
            local usable = GetPetActionSlotUsable and GetPetActionSlotUsable(i)
            if usable ~= nil and not Secret(usable) then
                usable = usable and true or false
                if b.lastUsable ~= usable then
                    b.lastUsable = usable
                    local v = usable and 1 or 0.4
                    b.icon:SetVertexColor(v, v, v)
                end
            end
        end
    end
    UpdateMood()
    UpdateCall()
end

-- ---------------------------------------------------------------------------------------
-- Leave

local leave = CreateFrame("Button", "TouchPlayLeaveVehicle", ns.root, "SecureActionButtonTemplate")
leave:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
leave:SetSize(LEAVE_W, SIZE)
leave:RegisterForClicks("AnyUp")
leave:SetAttribute("type", "macro")
leave:SetAttribute("macrotext", "/leavevehicle")
-- the picture: the kit's red button; the secure button over it takes the tap
local face = ns.Kit.RedButton(leave, LEAVE_W, SIZE, ns.T("classbars.leave"))
face:SetAllPoints(leave)
face:EnableMouse(false)
leave.face = face
ns.Kit.FitHit(leave)
ns.Kit.AddPress(leave, "rect", face)           -- the red button's own press look, lit by the secure button
leave:HookScript("PostClick", TapSound)
leave:Hide()                                   -- the driver shows it in a vehicle
ClassBars.leave = leave

-- ---------------------------------------------------------------------------------------
-- Placement

-- Which pet slots lie under Leave (in a vehicle their keys leave it: the app gives a finger to the smallest area under
-- it, so on Leave's middle that is a pet slot). Out of combat: attributes of secure buttons.
local function MarkUnderLeave()
    local l = leave.touchAnchor
    for i = 1, PET_SLOTS do
        local a = ClassBars.pet[i].touchAnchor
        local under = l and a and a.x < l.x + l.w and l.x < a.x + a.w and a.y < l.y + l.h and l.y < a.y + a.h
        local key = ClassBars.petKey[i]
        if (key:GetAttribute("underleave") and true or false) ~= (under and true or false) then
            key:SetAttribute("underleave", under and true or nil)
        end
    end
end

local function PlaceStatic()
    PlacePet()
    PlaceStance()
    ns.Anchor(leave, CORNER, CentreX() - LEAVE_W / 2, rowY)
    ns.Anchor(captionFrame, "BR", CAPTION_X, CAPTION_Y, true)
    MarkUnderLeave()
end
PlaceStatic()

-- The game's own conditions decide what is on screen, in a fight too.
RegisterStateDriver(stanceBar, "visibility", "[vehicleui][overridebar][possessbar] hide; show")
-- the pet bar: a living pet, and not in a vehicle, an override bar or a possess bar (Leave takes its place)
RegisterStateDriver(petBar, "visibility", "[vehicleui][overridebar][possessbar] hide; [@pet,exists,nodead] show; hide")
RegisterStateDriver(leave, "visibility", "[vehicleui][overridebar] show; hide")
local CALL_SHOWS = "[vehicleui][overridebar][possessbar] hide; [@pet,exists,nodead] hide; show"

-- ---------------------------------------------------------------------------------------
-- The contract areas (see the header): what the character can have. Out of combat.

local function Click(name, mouse) return { click = name, button = mouse } end

function ClassBars.RegisterAreas()
    local Contract = ns.Contract
    if not Contract then return end
    local before = {}
    for _, name in ipairs(Contract.EXTRA_NAMES) do before[name] = Contract.Has(name) end
    local stances = formCount > 0
    local pets = not stances and HasPetRow()
    for i = 1, MAX_FORMS do
        local name = "stance" .. i
        if stances and i <= formCount then
            local button = "TouchPlayStance" .. i
            Contract.Area(name, ClassBars.stance[i], { tap = Click(button, "LeftButton"), hold = Click(button, "RightButton") })
        elseif Contract.Has(name) then
            Contract.Drop(name)
        end
    end
    for i = 1, PET_SLOTS do
        local name = "pet" .. i
        if pets then
            local key = "TouchPlayPetKey" .. i
            Contract.Area(name, ClassBars.pet[i], { tap = Click(key, "LeftButton"), hold = Click(key, "RightButton") })
        elseif Contract.Has(name) then
            Contract.Drop(name)
        end
    end
    if pets and IsHunter() then
        Contract.Area("petfeed", feed, { tap = Click("TouchPlayPetFeed", "LeftButton") })
    elseif Contract.Has("petfeed") then
        Contract.Drop("petfeed")
    end
    Contract.Area("leave", leave, { tap = Click("TouchPlayLeaveVehicle", "LeftButton") })
    local changed = false
    for _, name in ipairs(Contract.EXTRA_NAMES) do
        if name ~= "petcard" and before[name] ~= Contract.Has(name) then changed = true end
    end
    if changed then Contract.Changed() end
end

-- Call / Revive pet on slot 5's key (a hunter who knows them), the Call button's driver, Feed pet. Out of combat.
local callDriven = false
local function SyncPet()
    local key = ClassBars.petKey[CALL_SLOT]
    local hunter = IsHunter() and HasPetRow()
    local callSpell = hunter and Knows(CALL_PET) and CALL_PET or nil
    local reviveSpell = hunter and Knows(REVIVE_PET) and REVIVE_PET or nil
    if key:GetAttribute("callspell") ~= callSpell then key:SetAttribute("callspell", callSpell) end
    if key:GetAttribute("revivespell") ~= reviveSpell then key:SetAttribute("revivespell", reviveSpell) end
    local want = callSpell ~= nil
    if want ~= callDriven then
        callDriven = want
        if want then
            RegisterStateDriver(call, "visibility", CALL_SHOWS)
        else
            UnregisterStateDriver(call, "visibility")
            call:Hide()
        end
    end
    call.dead = nil
    UpdateCall()
    ClassBars.SyncFeed()
end

-- ---------------------------------------------------------------------------------------
-- Events

local function QueueForms() ns.Queue("classbars forms", SyncForms) end
local function QueuePet() ns.Queue("classbars pet", function() SyncPet(); ClassBars.RegisterAreas() end) end

ns.On("PLAYER_ENTERING_WORLD", QueueForms)
ns.On("UPDATE_SHAPESHIFT_FORMS", QueueForms)
ns.On("SPELLS_CHANGED", QueueForms)
ns.On("SPELLS_CHANGED", QueuePet)
ns.On("UPDATE_SHAPESHIFT_FORM", function() UpdateFormState(); UpdateCaption() end)
ns.On("UPDATE_SHAPESHIFT_USABLE", UpdateFormState)
ns.On("UPDATE_SHAPESHIFT_COOLDOWN", UpdateFormCooldowns)
ns.On("UPDATE_STEALTH", UpdateCaption)

ns.On("PET_BAR_UPDATE", UpdatePet)
ns.On("PET_BAR_UPDATE_USABLE", UpdatePet)
ns.On("PET_UI_UPDATE", UpdatePet)
ns.On("UNIT_PET", UpdatePet)
-- the pet's own flags and health only (dead or alive: the Call / Revive picture): unit events for "pet", not
-- UNIT_FLAGS for every unit in sight
local petFlags = CreateFrame("Frame")
pcall(petFlags.RegisterUnitEvent, petFlags, "UNIT_FLAGS", "pet")
pcall(petFlags.RegisterUnitEvent, petFlags, "UNIT_HEALTH", "pet")
petFlags:SetScript("OnEvent", function(_, event)
    if ns.IsActive() then ns.Guard(event, UpdatePet) end
end)
ns.On("UNIT_HAPPINESS", UpdateMood)
ns.On("PET_BAR_UPDATE_COOLDOWN", UpdatePetCooldowns)

-- ---------------------------------------------------------------------------------------
-- Module steps

local function LayoutAll()
    PlaceStatic()
    SyncPet()
    SyncForms()          -- registers the areas too
end

function ClassBars:Layout()
    ns.Queue("classbars layout", LayoutAll)
end

function ClassBars:Refresh()
    UpdateFormState()
    UpdateCaption()
    UpdatePet()
    UpdatePetCooldowns()
end
