-- TouchPlay: the Interact, Jump and Dive faces, aiming, the flight card (rule 9; mockups 01, 10,
-- 16-18, 23, 24, 25, 77, 91).
--
--   * Interact (area "interact", tap = INTERACTTARGET, hold = the hidden "stop" button) shows what a
--     tap will do for whatever the game's soft interact has picked: Talk, Loot, Skin, Attack, Open, Reel in, or greyed
--     "Nothing near". While a ground spell is being aimed it shows a red X and "Cancel", and a
--     green line above the cluster says "Let go to cast <spell>" (the app sends Interact's hold key,
--     the secure "stop" button that calls SpellStopTargeting, when a drag from a spell ends on this area).
--     Under its word it names what a tap will use (the soft interact unit's name: "Talk" / "Apothecary Lydon"), one
--     short line, so a tap is never a guess (world taps, 18 Nov; the game's own mark sits over it in the world,
--     Targeting.lua). A name the game hides in a fight is not shown.
--   * Jump (area "jump", press = JUMP) reads "Swim up" in water. The Dive ring (area "dive") then
--     appears with SITORSTAND, the game's swim-down command (Bindings_Camelot.xml). When mounted
--     it reads "Dismount" and its key clicks a hidden secure /dismount button instead.
--   * On land and not mounted the same ring reads "Mount" (R50) when the character has a mount: its key
--     clicks a hidden secure macro button that runs C_MountJournal.SummonByID (not restricted in the API
--     documentation): 0, the journal's random favourite, or the mount the player pinned from the picker's
--     Mounts tab (TouchPlayCharDB.mount). The macro stops itself in a fight ([combat]), and the ring greys
--     then: the game allows mounting out of combat only. A ghost gets no Mount. The key is bound again (out of combat, through
--     Contract) whenever the ring changes between Dive, Dismount and Mount.
--   * On a flight path a card says where you are flying and offers "Request stop"
--     (TaxiRequestEarlyLanding, as the game's own Leave button does); Jump greys out and Interact
--     goes away.
--   * "Target needs to be in front of you." also shows centred near the top for 2 seconds, with a
--     hint to drag the view the first 3 times.
--
-- The faces are pictures: the app's keys do the work, so they take no taps. They live on
-- ns.moveRoot, which a pause never hides (mockup 91), and their events run while the add-on is
-- paused or off. The flight card lives on ns.root.
--
-- Nothing here acts for the player: no interact, cast or target call runs from an event or a
-- timer. Request stop runs from a tap. Only plain facts are tested (anything that a fight can
-- hide goes through Bool/Plain first).

local ADDON_NAME, ns = ...

local Interact = ns.Register("Interact", {})
local Kit = ns.Kit

ns.L["interact.talk"] = "Talk"
ns.L["interact.loot"] = "Loot"
ns.L["interact.skin"] = "Skin"
ns.L["interact.attack"] = "Attack"
ns.L["interact.open"] = "Open"
ns.L["interact.reelin"] = "Reel in"
ns.L["interact.none"] = "Nothing near"
ns.L["interact.cancel"] = "Cancel"
ns.L["interact.cvar"] = "Touch turned soft interact up so objects and the bobber count. Type /touch to switch Touch off and it goes back."
ns.L["jump.jump"] = "Jump"
ns.L["jump.swimUp"] = "Swim up"
ns.L["dive.dive"] = "Dive"
ns.L["dive.dismount"] = "Dismount"
ns.L["dive.mount"] = "Mount"
ns.L["dive.afterFight"] = "You can mount after the fight"
ns.L["jump.taxi"] = "Not on a flight path"
ns.L["aim.letGo"] = "Let go to cast %s"
ns.L["aim.letGoPlain"] = "Let go to cast"
ns.L["facing.hint"] = "Drag the view until it is in front of you."
ns.L["flight.title"] = "Flying to %s"
ns.L["flight.titlePlain"] = "On a flight path"
ns.L["flight.stop"] = "Request stop"
ns.L["flight.requested"] = "Stop requested"

-- ---------------------------------------------------------------------------------------
-- Numbers from the mockups (layout units, 1366 x 1024; top-left of each ring)

local CORNER = "BR"
local INTERACT_D, INTERACT_X, INTERACT_Y = 84, 906, 792
local JUMP_D, JUMP_X, JUMP_Y = 58, 1118, 915
-- Mockup 16 puts the Dive ring at (832, 820), the same square as the last pet button of the pet row
-- (ClassBars: 10 buttons of 52, centred at x 580, y 820 to 872). The ring sits 84 units higher,
-- in the same column, so a hunter in water or on a mount can still reach both.
local DIVE_D, DIVE_X, DIVE_Y = 56, 832, 736
-- "Let go to cast": under the aiming circle, centred at (645, 640) as mockup 23 (R24); mirrored left-handed
local AIM_CX, AIM_CY, AIM_W, AIM_H = 645, 640, 320, 28
local FACING_W, FACING_H, FACING_Y = 600, 34, 200
local FACING_SECONDS, FACING_HINTS = 2, 3
local CARD_X, CARD_Y, CARD_W = 486, 134, 394
local AIM_WINDOW = 1                      -- a spell press this recent names the spell being aimed
local FISHING_SPELL = 131474

local GOLD = { 1, 0.82, 0 }
local GREY = { 0.5, 0.5, 0.5 }
local GREEN = { 0.3, 1, 0.3 }
local RED = { 1, 0.13, 0.13 }

-- The mockups' glyphs, our own sharp art (R48; Style.lua Kit.GLYPHS): the game's 16 px gossip bubble and 32 px
-- arrows came out soft at touch size on the iPad.
local ICONS = {
    talk = "talk", loot = "loot", skin = "skin", attack = "sword", open = "open", reelin = "hook",
    none = "talk", cancel = "cancel", up = "jump", down = "dive", mount = "mount",
}
Interact.ICONS = ICONS

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

-- A fact from the game as true or false; a hidden one counts as false.
local function Bool(value)
    if not Plain(value) then return false end
    return value and true or false
end

-- ---------------------------------------------------------------------------------------
-- What Interact will do (pure)

-- s = { exists, dead, lootable, attackable, isObject, fishing, skinnable } -> the label key.
function Interact.Label(s)
    if s.fishing then return "reelin" end
    if not s.exists then return "none" end
    if s.dead and s.lootable then return "loot" end
    if s.dead and s.skinnable then return "skin" end
    if s.dead then return "none" end              -- looted and nothing to skin: nothing to do there
    if s.attackable then return "attack" end
    if s.isObject then return "open" end
    return "talk"
end

-- ---------------------------------------------------------------------------------------
-- The faces

local function NewFace(d, icon, label)
    local face = Kit.RingButton(ns.moveRoot, d, icon, label)
    face:EnableMouse(false)             -- a picture: the app's key does the work
    face:SetFrameLevel(30)
    return face
end

local interact = NewFace(INTERACT_D, ICONS.none, ns.T("interact.none"))
-- the name line under the word: one line, cut short, kept inside the face's column (the spell ring's second button
-- starts 52 right of the face's centre line + 52)
local NAME_W = 104
interact.nameLine = interact:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(interact.nameLine, Kit.FONT_TITLE, 11, "")
interact.nameLine:SetTextColor(0.9, 0.86, 0.72)
interact.nameLine:SetWidth(NAME_W)
interact.nameLine:SetWordWrap(false)
interact.nameLine:SetJustifyH("CENTER")
interact.nameLine:SetPoint("TOP", interact.label, "BOTTOM", 0, -1)
interact.nameLine:SetText("")
interact.nameLine:Hide()
local jump = NewFace(JUMP_D, ICONS.up, ns.T("jump.jump"))
local dive = NewFace(DIVE_D, ICONS.down, ns.T("dive.dive"))
dive:Hide()
Interact.interact, Interact.jump, Interact.dive = interact, jump, dive

-- "Let go to cast <spell>": a green line under the aiming circle while a ground spell is aimed.
local aimLine = ns.moveRoot:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(aimLine, Kit.FONT_TITLE, 22, "")
aimLine:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
aimLine:SetSize(AIM_W, AIM_H)
aimLine:SetJustifyH("CENTER")
aimLine:Hide()
Interact.aimLine = aimLine

-- The red facing message, centred near the top, and the drag hint under it.
local facing = CreateFrame("Frame", nil, ns.moveRoot)
facing:SetSize(FACING_W, FACING_H)
facing:EnableMouse(false)
facing:SetFrameLevel(40)
facing.text = facing:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(facing.text, Kit.FONT_TITLE, 26, "")
facing.text:SetTextColor(RED[1], RED[2], RED[3])
facing.text:SetPoint("TOP", facing, "TOP", 0, 0)
facing.hint = facing:CreateFontString(nil, "OVERLAY")
ns.Kit.SetFont(facing.hint, Kit.FONT_TITLE, 17, "")
facing.hint:SetTextColor(1, 1, 1)
facing.hint:SetPoint("TOP", facing.text, "BOTTOM", 0, -6)
facing:Hide()
Interact.facing = facing

-- The hidden secure button the Dive key clicks while mounted.
local dismount = CreateFrame("Button", "TouchPlayDismount", UIParent, "SecureActionButtonTemplate")
dismount:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
dismount:RegisterForClicks("AnyUp")
dismount:SetAttribute("type", "macro")
dismount:SetAttribute("macrotext", "/dismount")
dismount:Hide()
Interact.dismount = dismount

-- The hidden secure button Interact's hold key clicks (ruling A19): the app sends that key when a finger that
-- dragged off a spell button to aim a ground spell lifts over Interact. The game's own "stop" action calls
-- SpellStopTargeting() only while SpellIsTargeting(), so with nothing aimed it does nothing (never Escape, which
-- would open the game menu).
local stopAim = CreateFrame("Button", "TouchPlayStopAim", UIParent, "SecureActionButtonTemplate")
stopAim:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
stopAim:RegisterForClicks("AnyUp")
stopAim:SetAttribute("type", "stop")
stopAim:Hide()
Interact.stopAim = stopAim

-- The hidden secure button the Dive key clicks on land (R50): a macro that summons the pinned mount, or the
-- journal's random favourite (id 0). The game runs it from the key's up click; nothing here calls it.
-- One /run line that does nothing in a fight (the game refuses a summon there anyway): this client's chat has no
-- /stopmacro (iPad run 5, IMG_0012: "Type '/help' for a listing of a few commands." as the raptor came), so a
-- "/stopmacro [combat]" line printed that every time.
local function MountMacro(id)
    return ("/run if not InCombatLockdown() then C_MountJournal.SummonByID(%d) end"):format(id or 0)
end
Interact.MountMacro = MountMacro

local mountButton = CreateFrame("Button", "TouchPlayMount", UIParent, "SecureActionButtonTemplate")
mountButton:SetAttribute("useOnKeyDown", false)   -- act on the up click our taps and keys send (R47)
mountButton:RegisterForClicks("AnyUp")
mountButton:SetAttribute("type", "macro")
mountButton:SetAttribute("macrotext", MountMacro(nil))
mountButton:Hide()
Interact.mountButton = mountButton

local function Place()
    ns.Anchor(interact, CORNER, INTERACT_X, INTERACT_Y, true)
    ns.Anchor(jump, CORNER, JUMP_X, JUMP_Y, true)
    ns.Anchor(dive, CORNER, DIVE_X, DIVE_Y, true)
    ns.Anchor(facing, "TL", (1366 - FACING_W) / 2, FACING_Y)
    -- the aim line, centred; left-handed mirrors it with the rest of the thumb side (R33)
    ns.Anchor(aimLine, "TL", AIM_CX - AIM_W / 2, AIM_CY - AIM_H / 2, "side")
end

-- ---------------------------------------------------------------------------------------
-- The flight card (mockup 17): where you are flying, and Request stop

local card = Kit.Card(ns.root)
card:SetWidth(CARD_W)
card.title:SetJustifyH("CENTER")
card:SetTitle(ns.T("flight.titlePlain"), GOLD[1], GOLD[2], GOLD[3])

local taxiDestination                 -- the stop you chose at the flight master, if we saw it
local cardTitle

local function RequestStop()
    if card.buttons[1].busy then return end      -- already asked; the game answers at the next stop
    ns.Guard("interact stop", function()
        if TaxiRequestEarlyLanding then TaxiRequestEarlyLanding() end
    end)
    local button = card.buttons[1]
    button:SetBusy(true)               -- the request is in; the button waits
    button.label:SetText(ns.T("flight.requested"))
end

card:SetButtons({ { label = ns.T("flight.stop"), onClick = RequestStop } })
card:SetFrameLevel(35)
card:Hide()
Interact.card = card

local function PlaceCard() ns.Anchor(card, "TL", CARD_X, CARD_Y) end
PlaceCard()

-- ---------------------------------------------------------------------------------------
-- State

local swimming, mounted, taxi, aiming = false, false, false, false
local diveMode = "dive"               -- what the Dive ring is now: "dive", "dismount" or "mount"
local boundMode = "dive"              -- which kind of press the dive key has now
local hasMount                        -- the character has a mount to summon (nil: look again)
local fishing = false
local lastSlot, lastPressAt = nil, -100
local aimedSpell
local shownKey, shownJump, shownDive, shownAim
local registered = false              -- the areas are with the contract

local inputs = {}                     -- the soft interact facts, reused

local function ReadInputs()
    local s = inputs
    local unit = "softinteract"
    s.exists = Bool(UnitExists(unit))
    s.dead, s.lootable, s.attackable, s.isObject, s.skinnable = false, false, false, false, false
    s.fishing = fishing
    s.name = ""
    if not s.exists then return s end
    local name = UnitName(unit)
    if Plain(name) and type(name) == "string" then s.name = name end
    s.dead = Bool(UnitIsDead(unit))
    local guid = UnitGUID(unit)
    if Plain(guid) and guid and CanLootUnit then s.lootable = Bool((CanLootUnit(guid))) end
    s.attackable = not s.dead and Bool(UnitCanAttack("player", unit))
    if UnitIsGameObject then
        s.isObject = Bool(UnitIsGameObject(unit))
    else
        local kind = UnitCreatureType and UnitCreatureType(unit)
        s.isObject = not Bool(UnitIsPlayer(unit)) and Plain(kind) and not kind
    end
    if s.dead and not s.lootable and UnitCreatureType then
        local _, id = UnitCreatureType(unit)
        s.skinnable = Plain(id) and (id == 1 or id == 2) or false      -- beasts and dragonkin
    end
    return s
end

local function Colour(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- A greyed face still takes its key (the app sends it); pressed, it lights grey and says why (polish pass).
local function GreyReason(face)
    if not face.touchGrey then return nil end
    return face.touchReason or true
end

local function PaintFace(face, icon, text, grey, reason)
    face.touchGrey, face.touchReason = grey and true or false, grey and reason or nil
    face.touchRefused = GreyReason
    Kit.SetRingIcon(face, icon)
    face.icon:SetDesaturated(grey and true or false)
    face.label:SetText(text)
    Colour(face.label, grey and GREY or GOLD)
    face.ring:SetVertexColor(grey and 0.55 or 1, grey and 0.55 or 1, grey and 0.55 or 1)
end

-- The words that name nothing: the name line stays empty under them.
local NAMELESS = { none = true, cancel = true, reelin = true }

local function RefreshInteract()
    local key, name
    if aiming then
        key, name = "cancel", ""
    else
        local s = ReadInputs()
        key = Interact.Label(s)
        name = NAMELESS[key] and "" or s.name
    end
    if taxi then
        if interact:IsShown() then interact:Hide() end
        return
    end
    if not interact:IsShown() then interact:Show() end
    local shown = key .. "|" .. name
    if shown == shownKey then return end
    shownKey = shown
    PaintFace(interact, ICONS[key], ns.T("interact." .. key), key == "none")
    interact.nameLine:SetText(name)
    interact.nameLine:SetShown(name ~= "")
end

local function RefreshJump()
    local text = swimming and ns.T("jump.swimUp") or ns.T("jump.jump")
    local key = text .. (taxi and "|off" or "")
    if key == shownJump then return end
    shownJump = key
    PaintFace(jump, ICONS.up, text, taxi, ns.T("jump.taxi"))
    jump:SetAlpha(taxi and 0.6 or 1)
end

-- Whether the character has a mount to call: one the journal shows as collected for this character. Looked up
-- once and again after the journal changes (NEW_MOUNT_ADDED, MOUNT_JOURNAL_USABILITY_CHANGED, entering the world).
local function HasMount()
    if hasMount ~= nil then return hasMount end
    local journal = C_MountJournal
    if not journal or not journal.GetMountIDs or not journal.GetMountInfoByID then
        hasMount = true                       -- nothing to ask: offer it, the game answers a tap
        return hasMount
    end
    hasMount = false
    for _, id in ipairs(journal.GetMountIDs() or {}) do
        local _, _, _, _, _, _, _, _, _, hidden, collected = journal.GetMountInfoByID(id)
        if Bool(collected) and not Bool(hidden) then hasMount = true; break end
    end
    return hasMount
end

-- What the Dive ring is: Dismount when mounted, Dive in water, Mount on land (with a mount to call). With none
-- of those it is hidden, and its key is the swim-down command as before.
local function DiveMode()
    if mounted then return "dismount" end
    if swimming or taxi then return "dive" end
    if Bool(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return "dive" end   -- a ghost cannot mount
    if HasMount() then return "mount" end
    return "dive"
end

local function RefreshDive()
    local want = (mounted or swimming or diveMode == "mount") and not taxi
    if dive:IsShown() ~= want then dive:SetShown(want) end
    if not want then return end
    local grey = diveMode == "mount" and ns.InFight()        -- mounting waits for the end of the fight
    local key = diveMode .. (grey and "|grey" or "")
    if key == shownDive then return end
    shownDive = key
    PaintFace(dive, diveMode == "mount" and ICONS.mount or ICONS.down, ns.T("dive." .. diveMode), grey,
        ns.T("dive.afterFight"))
end

local function RefreshAim()
    if aiming then
        local text = aimedSpell and ns.T("aim.letGo", aimedSpell) or ns.T("aim.letGoPlain")
        if text ~= shownAim then shownAim = text; aimLine:SetText(text) end
        if not aimLine:IsShown() then aimLine:Show() end
    else
        shownAim = nil
        if aimLine:IsShown() then aimLine:Hide() end
    end
end

local function RefreshCard()
    if not taxi then
        if card:IsShown() then card:Hide() end
        taxiDestination = nil
        return
    end
    local title = taxiDestination and ns.T("flight.title", taxiDestination) or ns.T("flight.titlePlain")
    if title ~= cardTitle then
        cardTitle = title
        card:SetTitle(title, GOLD[1], GOLD[2], GOLD[3])
        PlaceCard()
    end
    if not card:IsShown() then
        local button = card.buttons[1]
        button:SetBusy(false)
        button.label:SetText(ns.T("flight.stop"))
        card:Show()
    end
end

-- ---------------------------------------------------------------------------------------
-- The dive key's press: the game's swim-down command, or the hidden /dismount button

local PRESS = {
    dive = { command = "SITORSTAND" },
    dismount = { click = "TouchPlayDismount", button = "LeftButton" },
    mount = { click = "TouchPlayMount", button = "LeftButton" },
}

local function RegisterDive()
    ns.Contract.Area("dive", dive, { anchor = CORNER, press = PRESS[boundMode] })
end

-- The key is bound in one place (Contract); when the press changes, bind it again. After a pause
-- or while off only the three movement keys stay, so that is what is bound then.
local function RebindDive()
    if not registered then return end
    RegisterDive()
    if ns.IsActive() then ns.Contract.Apply() else ns.Contract.OnPause() end
end

-- Swimming, mounted and on a flight path: read again, act on what changed.
local function RefreshMovement()
    local nowSwimming = Bool(IsSwimming and IsSwimming())
    local nowMounted = Bool(IsMounted and IsMounted())
    local nowTaxi = Bool(UnitOnTaxi and UnitOnTaxi("player"))
    local changed = nowSwimming ~= swimming or nowMounted ~= mounted or nowTaxi ~= taxi
    swimming, mounted, taxi = nowSwimming, nowMounted, nowTaxi
    local mode = DiveMode()
    if mode ~= diveMode then diveMode, changed = mode, true end
    if diveMode ~= boundMode then
        boundMode = diveMode
        RebindDive()
    end
    if changed then
        RefreshJump()
        RefreshDive()
        RefreshCard()
        RefreshInteract()
    end
end

-- ---------------------------------------------------------------------------------------
-- Aiming

local function SpellNameOf(slot)
    if not slot or not GetActionInfo then return nil end
    local kind, id = GetActionInfo(slot)
    if not Plain(kind) or kind ~= "spell" or not Plain(id) or type(id) ~= "number" then return nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and Plain(name) then return name end
    return nil
end

local function NoteSpellPress(self)
    lastSlot, lastPressAt = self:GetAttribute("action"), GetTime()
end

local function RefreshAiming()
    local now = Bool(SpellIsTargeting and SpellIsTargeting())
    aimedSpell = nil
    if now and GetTime() - lastPressAt <= AIM_WINDOW then aimedSpell = SpellNameOf(lastSlot) end
    aiming = now
    RefreshAim()
    RefreshInteract()
end

-- ---------------------------------------------------------------------------------------
-- Fishing: the player channels the Fishing spell

local fishingName
local function FishingName()
    if fishingName == nil and C_Spell and C_Spell.GetSpellInfo and not InCombatLockdown() then
        local info = C_Spell.GetSpellInfo(FISHING_SPELL)
        if info and type(info.name) == "string" then fishingName = info.name end
    end
    return fishingName
end

local function ChannelIsFishing(spellID)
    if Plain(spellID) and spellID == FISHING_SPELL then return true end
    local want = FishingName()
    if not want or not UnitChannelInfo then return false end
    local name = UnitChannelInfo("player")
    return Plain(name) and name == want
end

local function ChannelStarted(_, _, spellID)
    fishing = ChannelIsFishing(spellID)
    RefreshInteract()
end

local function ChannelStopped()
    fishing = false
    RefreshInteract()
end

-- ---------------------------------------------------------------------------------------
-- The facing message

local facingUntil = -100

local function HideFacing()
    if GetTime() >= facingUntil - 0.01 then facing:Hide() end
end

local function ShowFacing(message)
    local db = ns.db
    local seen = db and tonumber(db.facingHints) or 0
    local hint = seen < FACING_HINTS
    if db and hint then db.facingHints = seen + 1 end
    facing.text:SetText(message)
    facing.hint:SetText(hint and ns.T("facing.hint") or "")
    facing:Show()
    facingUntil = GetTime() + FACING_SECONDS
    C_Timer.After(FACING_SECONDS, HideFacing)
end

local function ErrorMessage(_, message)
    if type(message) ~= "string" or not Plain(message) then return end
    if ERR_BADATTACKFACING and message == ERR_BADATTACKFACING then ShowFacing(message) end
end

-- ---------------------------------------------------------------------------------------
-- Soft interact, so the bobber and objects count

local SOFT = "SoftTargetInteract"

local function ApplySoftInteract()
    if not (GetCVar and SetCVar) or InCombatLockdown() then return end
    local current = tonumber(GetCVar(SOFT))
    if current == nil or current >= 3 then return end
    if ns.db.softInteractOld == nil then ns.db.softInteractOld = current end
    SetCVar(SOFT, 3)
    if not ns.db.softInteractTold then
        ns.db.softInteractTold = true
        ns.Print(ns.T("interact.cvar"))
    end
end

local function RestoreSoftInteract()
    local old = ns.db and ns.db.softInteractOld
    if old == nil or ns.db.enabled or not SetCVar then return end
    SetCVar(SOFT, old)
    ns.db.softInteractOld = nil
end

-- ---------------------------------------------------------------------------------------
-- Events: they run while the add-on is paused or off too, so the faces stay true

local function OnSwimmingMaybeChanged() RefreshMovement() end

-- The journal changed (a new mount, a new zone, a new session): ask it again. A character never loses a mount, so
-- once one is found nothing is asked again.
local function OnJournalChanged()
    if hasMount ~= true then hasMount = nil end
    RefreshMovement()
end
for _, event in ipairs({ "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, OnJournalChanged, true)
end
-- A fight greys Mount, its end lights it again.
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, RefreshDive, true)
end

for _, event in ipairs({ "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "UPDATE_BONUS_ACTIONBAR", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, OnSwimmingMaybeChanged, true)
end
for _, event in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_TARGET_CHANGED" }) do
    ns.On(event, RefreshInteract, true)
end
ns.On("CURRENT_SPELL_CAST_CHANGED", RefreshAiming, true)
ns.On("UI_ERROR_MESSAGE", ErrorMessage, true)

-- The player's own channel only (RegisterUnitEvent), straight to the two handlers above.
local channel = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    pcall(channel.RegisterUnitEvent, channel, event, "player")
end
channel:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        ns.Guard("interact channel", ChannelStarted, ...)
    else
        ns.Guard("interact channel", ChannelStopped, ...)
    end
end)

-- Pressing Jump is a cheap moment to look again: the game has no event for entering the water.
local function OnJumpPressed() ns.Guard("interact jump", RefreshMovement) end
if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", OnJumpPressed) end

-- The stop chosen at the flight master names the flight.
local function OnTakeTaxi(index)
    ns.Guard("interact taxi", function()
        local name = TaxiNodeName and TaxiNodeName(index)
        if type(name) == "string" and Plain(name) then
            taxiDestination = name:match("^([^,]+)") or name
        end
    end)
end
if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTakeTaxi) end

Place()

-- ---------------------------------------------------------------------------------------
-- Module steps

function Interact:Init()
    local cluster = ns.Cluster
    if cluster then
        for _, button in ipairs(cluster.buttons) do button:HookScript("PreClick", NoteSpellPress) end
    end
    local Contract = ns.Contract
    if not Contract then return end
    Contract.Area("interact", interact, { anchor = CORNER, tap = { command = "INTERACTTARGET" },
        hold = { click = "TouchPlayStopAim", button = "LeftButton" } })
    Contract.Area("jump", jump, { anchor = CORNER, press = { command = "JUMP" } })
    mounted = Bool(IsMounted and IsMounted())
    swimming = Bool(IsSwimming and IsSwimming())
    diveMode = DiveMode()
    boundMode = diveMode
    RegisterDive()
    registered = true
    ns.Queue("mount macro", function() mountButton:SetAttribute("macrotext", MountMacro(Interact.PinnedMount())) end)
end

-- The mount pinned to the Mount ring (a mount id), or nil for the random favourite. Kept per character.
function Interact.PinnedMount()
    local id = ns.char and ns.char.mount
    if type(id) == "number" and id > 0 then return id end
    return nil
end

-- Pins a mount to the Mount ring (nil or 0: the random favourite again). From a tap in the picker; the macro
-- changes out of combat only (the button is protected), so in a fight it waits for the end.
function Interact.PinMount(id)
    if type(id) ~= "number" or id <= 0 then id = nil end
    if ns.char then ns.char.mount = id end
    ns.Queue("mount macro", function() mountButton:SetAttribute("macrotext", MountMacro(id)) end)
end

function Interact:Layout()
    ns.Queue("interact layout", function()
        Place()
        PlaceCard()
    end)
    ns.Queue("interact cvar", ApplySoftInteract)
end

function Interact:Refresh()
    shownKey, shownJump, shownDive = nil, nil, nil     -- paint everything once
    RefreshMovement()
    RefreshJump()
    RefreshDive()
    RefreshCard()
    RefreshAiming()
end

-- Off gives the cvar back; a pause keeps it, because Interact still works through the pause.
function Interact:Restore()
    RestoreSoftInteract()
end

-- What the face shows now (for the tests).
function Interact.label() return interact.label:GetText() end
function Interact.unitName() return interact.nameLine:GetText() or "" end
function Interact.jumpLabel() return jump.label:GetText() end
function Interact.diveLabel() return dive.label:GetText() end
function Interact.diveMode() return diveMode end
