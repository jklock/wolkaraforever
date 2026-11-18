-- A fake of the parts of the WoW API that TouchPlay uses, so the add-on runs under LuaJIT on
-- the Mac. Frames keep their parent, shown state, points, attributes, scripts and events;
-- secure templates run their snippets; protected frames refuse changes in combat from
-- insecure code (the game blocks those); a "secret" value throws on any maths or comparison,
-- as the game's combat-hidden numbers do.
--
-- Each tests/test_*.lua starts with dofile("tests/stub.lua"), then T("name", fn) per test and
-- Stub.done("label") at the end.

Stub = {}
local ADDON_DIR = "addon/TouchPlay/"
local ADDON_NAME = "TouchPlay"

local registry, frameList, eventFrames
local combat, secureDepth = false, 0
local loadedFiles = {}

local function noop() end

-- ---------------------------------------------------------------------------------------
-- Counters and records

local function Counter()
    return setmetatable({}, { __index = function() return 0 end })
end

local function count(name) Stub.calls[name] = Stub.calls[name] + 1 end
Stub.count = count

-- ---------------------------------------------------------------------------------------
-- Secret values

local function secretError() error("secret", 2) end
local secretMeta = {
    __add = secretError, __sub = secretError, __mul = secretError, __div = secretError,
    __mod = secretError, __pow = secretError, __unm = secretError, __concat = secretError,
    __lt = secretError, __le = secretError, __eq = secretError, __tostring = secretError,
    __len = secretError, __call = secretError,
    __index = function() secretError() end, __newindex = secretError,
}
function Stub.secret() return setmetatable({}, secretMeta) end
local rawtype = type      -- a test may wrap the global type() to make a hidden value look like a number
function Stub.isSecret(v) return rawtype(v) == "table" and getmetatable(v) == secretMeta end

-- ---------------------------------------------------------------------------------------
-- Frames

local Frame = {}
Stub.Frame = Frame              -- the widget methods (a test may wrap one)
local FrameMeta = {
    __index = function(_, key)
        local method = Frame[key]
        if method ~= nil then return method end
        -- Any other widget method the add-on calls is accepted and answers nothing.
        if type(key) == "string" and key:match("^%u") then return noop end
    end,
    __tostring = function(self) return "Frame<" .. tostring(rawget(self, "name")) .. ">" end,
}

local function blocked(frame, what)
    if combat and secureDepth == 0 and frame:IsProtected() then
        error("ADDON_ACTION_BLOCKED: " .. what .. " on " .. tostring(frame.name) .. " in combat", 3)
    end
end

-- Implicit protection, as the game has it: a frame that holds a protected frame (at any depth), or that a
-- protected frame is anchored to, is protected too (IsProtected answers true, false). The set is worked out
-- once and kept until a protected frame is made, moved or reparented.
local protCache

local function explicitlyProtected(f)
    if f.protectedFlag ~= nil then return f.protectedFlag end
    local t = f.templates
    return t:find("Secure") ~= nil or t:find("ActionBarButtonTemplate") ~= nil
        or t:find("PetActionButtonTemplate") ~= nil
end

local function protectedSet()
    if protCache then return protCache end
    local set, queue = {}, {}
    local function mark(f)
        if type(f) == "string" then f = registry[f] end
        if type(f) ~= "table" or set[f] then return end
        set[f] = true
        queue[#queue + 1] = f
    end
    for _, f in ipairs(frameList) do if explicitlyProtected(f) then mark(f) end end
    local i = 1
    while i <= #queue do
        local f = queue[i]
        i = i + 1
        mark(f.parentFrame)
        for _, p in ipairs(f.points) do
            if p[1] == "ALL" then mark(p[2]) elseif type(p[2]) == "table" or type(p[2]) == "string" then mark(p[2]) end
        end
    end
    protCache = set
    return set
end

-- A protected frame changed where it hangs: the set is worked out again next time.
local function reshaped(frame) if protCache and protCache[frame] then protCache = nil end end
Stub.forgetProtection = function() protCache = nil end

local function runSnippet(frame, code, ...)
    if type(code) ~= "string" or code == "" then return end
    local chunk = assert(loadstring("local self, a1, a2 = ...\n" ..
        "local name, value, button, down = a1, a2, a1, a2\n" ..
        "local stateid, newstate = a1, a2\n" .. code, "snippet"))
    setfenv(chunk, setmetatable({ owner = frame }, { __index = _G }))
    secureDepth = secureDepth + 1
    local ok, problem = pcall(chunk, frame, ...)
    secureDepth = secureDepth - 1
    if not ok then error(problem, 0) end
end
Stub.runSnippet = runSnippet

local function newObject(kind, name, parent, templates)
    local frame = setmetatable({
        kind = kind, name = name, parentFrame = parent, shown = true, attributes = {},
        scripts = {}, hooks = {}, points = {}, refs = {}, events = {}, children = {},
        templates = templates or "", width = 0, height = 0, scale = 1, alpha = 1,
        mouse = true, level = 1, calls = Counter(),
    }, FrameMeta)
    return frame
end

-- (protected, explicitly protected)
function Frame:IsProtected()
    if self.protectedFlag ~= nil then return self.protectedFlag, self.protectedFlag end
    local explicit = explicitlyProtected(self)
    return explicit or protectedSet()[self] == true, explicit
end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:IsObjectType(kind) return self.kind == kind end
function Frame:GetParent() return self.parentFrame end
function Frame:SetParent(parent)
    blocked(self, "SetParent")
    self.calls.SetParent = self.calls.SetParent + 1
    if type(parent) == "string" then parent = _G[parent] end
    local wasVisible = self.fireHideOnReparent and self:IsVisible()
    reshaped(self)
    self.parentFrame = parent
    -- the game's own windows that hide themselves when they lose their parent's visibility
    if wasVisible and not self:IsVisible() then self:_Fire("OnHide") end
end
function Frame:GetChildren() return unpack(self.children) end
-- Edit boxes: focus fires the game's focus scripts
function Frame:HasFocus() return self.focused == true end
function Frame:SetFocus()
    if self.focused then return end
    self.focused = true; Stub.keyboardFocus = self; self:_Fire("OnEditFocusGained")
end
function Frame:ClearFocus()
    if not self.focused then return end
    self.focused = false
    if Stub.keyboardFocus == self then Stub.keyboardFocus = nil end
    self:_Fire("OnEditFocusLost")
end
function Frame:SetPassword(on) self.password = on and true or false end
function Frame:IsPassword() return self.password == true end
function Frame:SetAutoFocus(on) self.autoFocus = on and true or false end
function Frame:HasAutoFocus() return self.autoFocus ~= false end
function Frame:SetIgnoreParentAlpha(on) self.ignoreParentAlpha = on and true or false end
function Frame:IsIgnoringParentAlpha() return self.ignoreParentAlpha == true end
function Frame:Show() blocked(self, "Show"); self.shown = true; self:_Fire("OnShow") end
function Frame:Hide()
    blocked(self, "Hide"); self.calls.Hide = self.calls.Hide + 1
    self.shown = false; self:_Fire("OnHide")
end
-- The game's own frames that Edit Mode manages keep the real hide as HideBase.
function Frame:HideBase() self.shown = false; self:_Fire("OnHide") end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    local f = self
    while f do
        if not f.shown then return false end
        f = f.parentFrame
    end
    return true
end
function Frame:SetPoint(...)
    blocked(self, "SetPoint"); self.calls.SetPoint = self.calls.SetPoint + 1
    reshaped(self)
    self.points[#self.points + 1] = { ... }
end
function Frame:ClearAllPoints()
    blocked(self, "ClearAllPoints"); self.calls.ClearAllPoints = self.calls.ClearAllPoints + 1
    reshaped(self)
    self.points = {}
end
function Frame:SetAllPoints(other)
    blocked(self, "SetAllPoints"); reshaped(self)
    self.points = { { "ALL", other } }
end
function Frame:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
function Frame:GetNumPoints() return #self.points end
function Frame:SetSize(w, h) blocked(self, "SetSize"); self.width, self.height = w, h end
function Frame:SetWidth(w) blocked(self, "SetWidth"); self.width = w end
function Frame:SetHeight(h) blocked(self, "SetHeight"); self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetSize() return self.width, self.height end
function Frame:SetScale(s) blocked(self, "SetScale"); self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:GetEffectiveScale()
    local s, f = 1, self
    while f do s = s * (f.scale or 1); f = f.parentFrame end
    return s
end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:EnableMouse(on) blocked(self, "EnableMouse"); self.mouse = on and true or false end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:SetFrameLevel(l) self.level = l end
-- Strata: a frame takes its parent's unless it set its own (the game gives a new frame its parent's, and setting a
-- parent's strata carries down to its children); UIParent is MEDIUM. A protected frame's strata is a protected change.
function Frame:SetFrameStrata(strata)
    blocked(self, "SetFrameStrata")
    self.strata = strata
end
function Frame:GetFrameStrata()
    if self.strata then return self.strata end
    local parent = rawget(self, "parentFrame")
    if parent and parent.GetFrameStrata then return parent:GetFrameStrata() end
    return "MEDIUM"
end
function Frame:GetFrameLevel() return self.level end
function Frame:SetID(id) self.id = id end
function Frame:GetID() return self.id or 0 end

function Frame:SetAttribute(key, value)
    blocked(self, "SetAttribute")
    self.attributes[key] = value
    if self.templates:find("SecureHandler") and type(key) == "string" and key:sub(1, 1) ~= "_" then
        runSnippet(self, self.attributes._onattributechanged, key, value)
        local state = key:match("^state%-(.+)$")
        if state then runSnippet(self, self.attributes["_onstate-" .. state], state, value) end
    end
    self:_Fire("OnAttributeChanged", key, value)
end
function Frame:GetAttribute(key) return self.attributes[key] end
function Frame:SetFrameRef(label, frame) self.refs[label] = frame end
function Frame:GetFrameRef(label) return self.refs[label] end
function Frame:Execute(code) runSnippet(self, code) end
-- A secure handler's own override bindings, from its snippets only (RestrictedFrames.lua:541 ClearBinding, :564
-- SetBinding): allowed in a fight.
function Frame:SetBinding(priority, key, action)
    if secureDepth == 0 then error("SetBinding is a restricted-frame method (a snippet's self)", 2) end
    Stub.bindings[key] = { command = action, owner = self }
end
function Frame:ClearBinding(key)
    if secureDepth == 0 then error("ClearBinding is a restricted-frame method (a snippet's self)", 2) end
    if Stub.bindings[key] and Stub.bindings[key].owner == self then Stub.bindings[key] = nil end
end
-- SecureHandlerBaseTemplate's own way to wrap a script: header:WrapScript(frame, script, pre, post)
function Frame:WrapScript(frame, script, pre, post) SecureHandlerWrapScript(frame, script, self, pre, post) end

function Frame:SetScript(script, fn) self.scripts[script] = fn; self.hooks[script] = nil end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:HookScript(script, fn)
    self.hooks[script] = self.hooks[script] or {}
    table.insert(self.hooks[script], fn)
end
function Frame:HasScript() return true end
function Frame:_Fire(script, ...)
    local fn = self.scripts[script]
    if fn then fn(self, ...) end
    for _, hook in ipairs(self.hooks[script] or {}) do hook(self, ...) end
end

function Frame:RegisterEvent(event)
    self.events[event] = true
    Stub.allEvents[event] = true
    eventFrames[event] = eventFrames[event] or {}
    for _, f in ipairs(eventFrames[event]) do if f == self then return end end
    table.insert(eventFrames[event], self)
end
-- A unit event registered for some units only reaches the frame for those units (the first argument).
function Frame:RegisterUnitEvent(event, ...)
    self:RegisterEvent(event)
    self.unitFilter = self.unitFilter or {}
    local units = {}
    for i = 1, select("#", ...) do units[(select(i, ...))] = true end
    self.unitFilter[event] = units
end
function Frame:UnregisterEvent(event)
    self.events[event] = nil
    local list = eventFrames[event] or {}
    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
end
function Frame:UnregisterAllEvents() for event in pairs(self.events) do self:UnregisterEvent(event) end end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
-- keyboard input (the key diagnostic): a frame takes keys only while it is shown and keyboard-enabled. The game lists
-- EnableKeyboard as a protected function, so the stub refuses it in a fight on a protected frame.
function Frame:EnableKeyboard(on) blocked(self, "EnableKeyboard"); self.keyboard = on and true or false end
function Frame:IsKeyboardEnabled() return self.keyboard == true end
function Frame:SetPropagateKeyboardInput(on) blocked(self, "SetPropagateKeyboardInput"); self.propagate = on and true or false end
function Frame:GetPropagateKeyboardInput() return self.propagate == true end
function Frame:RegisterForDrag(...) self.dragButtons = { ... } end

-- Regions and widget values
function Frame:CreateTexture(name, layer, template, sub)
    local t = newObject("Texture", name, self)
    t.layer, t.subLayer = layer, sub
    if name then registry[name] = t; _G[name] = t end
    return t
end
function Frame:CreateFontString(name, layer)
    local fs = newObject("FontString", name, self)
    fs.layer = layer
    if name then registry[name] = fs; _G[name] = fs end
    return fs
end
function Frame:CreateMaskTexture(name) return self:CreateTexture(name) end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text end
function Frame:SetFormattedText(fmt, ...)
    -- the arguments are kept in one table per frame, refilled each time, so the call itself allocates nothing (the
    -- game's own SetFormattedText does not allocate Lua memory either)
    self.text = fmt
    local args = self.formatArgs
    if not args then args = {}; self.formatArgs = args end
    local n = select("#", ...)
    for i = 1, math.max(n, args.n or 0) do args[i] = nil end
    for i = 1, n do args[i] = (select(i, ...)) end
    args.n = n
end
function Frame:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
-- A font object (a font family from CreateFontFamily): the string takes its Latin member's file, size and flags.
function Frame:SetFontObject(obj)
    self.fontObject = obj
    if type(obj) == "table" and obj.GetFont then self.font, self.fontSize, self.fontFlags = obj:GetFont() end
end
function Frame:GetFontObject() return self.fontObject end
-- CreateFontFamily(name, members) (FontDocumentation.lua): a named font object with one member per alphabet.
function CreateFontFamily(name, members)
    assert(type(name) == "string" and type(members) == "table" and #members > 0, "CreateFontFamily(name, members)")
    local family = { name = name, members = members }
    for _, m in ipairs(members) do
        assert(type(m.alphabet) == "string" and type(m.file) == "string" and type(m.height) == "number"
            and type(m.flags) == "string", "a member has alphabet, file, height and flags")
        if m.alphabet == "roman" then family.font, family.size, family.flags = m.file, m.height, m.flags end
    end
    function family:GetFont() return self.font, self.size, self.flags end
    _G[name] = family
    return family
end
function Frame:SetTexture(tex) self.texture = tex end
function Frame:GetTexture() return self.texture end
function Frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Frame:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Frame:SetMinMaxValues(min, max) self.minValue, self.maxValue = min, max end
function Frame:GetMinMaxValues() return self.minValue, self.maxValue end
function Frame:SetValue(v)
    local changed = not rawequal(self.value, v)
    self.value = v
    -- a Slider tells whoever listens (the game fires OnValueChanged when the value moves)
    if self.kind == "Slider" and changed then self:_Fire("OnValueChanged", v, false) end
end
function Frame:GetValue() return self.value end
function Frame:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end
function Frame:GetStatusBarTexture()
    self.barTexture = self.barTexture or newObject("Texture", nil, self)
    return self.barTexture
end
-- Functions the game marks SecretArguments = "AllowedWhenUntainted" refuse a hidden value from add-on code.
local function refuseSecret(what, ...)
    for i = 1, select("#", ...) do
        if Stub.isSecret((select(i, ...))) then error(what .. ": a hidden value from add-on code", 3) end
    end
end
Stub.refuseSecret = refuseSecret

function Frame:SetCooldown(start, duration)
    refuseSecret("SetCooldown", start, duration)
    self.cooldownStart, self.cooldownDuration = start, duration
end
function Frame:SetChecked(on) self.checked = on end
function Frame:GetChecked() return self.checked end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:GetStringWidth() return #(type(self.text) == "string" and self.text or "") * 6 end
function Frame:GetCenter() return 0, 0 end
function Frame:GetLeft() return 0 end
function Frame:GetBottom() return 0 end

-- Hit areas: the add-on grows a small touch area with negative insets; the stub reports the
-- size the game would use (size minus insets). GetHitRectSize is a stub helper only.
function Frame:SetHitRectInsets(l, r, t, b) self.hitInsets = { l or 0, r or 0, t or 0, b or 0 } end
function Frame:GetHitRectInsets()
    local i = self.hitInsets or { 0, 0, 0, 0 }
    return i[1], i[2], i[3], i[4]
end
function Frame:GetHitRectSize()
    local l, r, t, b = self:GetHitRectInsets()
    return self.width - l - r, self.height - t - b
end

-- Textures
function Frame:SetTexCoord(...) self.texCoord = { ... } end
function Frame:RemoveMaskTexture(mask) self.removedMask = mask end
function Frame:SetDesaturated(on) self.desaturated = on and true or false end
function Frame:SetBlendMode(mode) self.blendMode = mode end
function Frame:SetDrawLayer(layer, sub) self.layer, self.subLayer = layer, sub end

-- Font strings
function Frame:SetFont(path, size, flags) self.font, self.fontSize, self.fontFlags = path, size, flags; return true end
function Frame:GetFont() return self.font, self.fontSize, self.fontFlags end
function Frame:SetJustifyH(j) self.justifyH = j end
function Frame:GetJustifyH() return self.justifyH or "CENTER" end
function Frame:SetWordWrap(on) self.wordWrap = on and true or false end
function Frame:GetWordWrap() return self.wordWrap ~= false end
function Frame:GetStringHeight()
    -- one line per 15 characters of the wrap width, at the font size
    local text = type(self.text) == "string" and self.text or ""
    local size = self.fontSize or 12
    local perLine = math.max(1, math.floor((self.width > 0 and self.width or 400) / (size * 0.5)))
    return math.max(1, math.ceil(#text / perLine)) * size
end

-- Backdrops (BackdropTemplate)
function Frame:SetBackdrop(info) self.backdrop = info end
function Frame:GetBackdrop() return self.backdrop end
function Frame:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Frame:SetBackdropBorderColor(r, g, b, a) self.backdropBorderColor = { r, g, b, a } end

-- Button textures: SetXTexture(path) makes the texture, GetXTexture() returns it.
for _, part in ipairs({ "Normal", "Pushed", "Highlight", "Disabled" }) do
    Frame["Set" .. part .. "Texture"] = function(self, tex)
        self["part" .. part] = self["part" .. part] or newObject("Texture", nil, self)
        self["part" .. part].texture = tex
    end
    Frame["Get" .. part .. "Texture"] = function(self) return self["part" .. part] end
end

-- Timer status bars, alpha from a boolean, animation groups (Task 5)
function Frame:SetTimerDuration(duration, interpolation, direction)
    refuseSecret("SetTimerDuration", duration)
    self.timerDuration, self.timerInterpolation, self.timerDirection = duration, interpolation, direction
end
function Frame:SetAlphaFromBoolean(flag, whenTrue, whenFalse)
    self.alphaFromBoolean = { flag, whenTrue, whenFalse }
    if not Stub.isSecret(flag) then self.alpha = flag and whenTrue or whenFalse end
end
function Frame:CreateAnimationGroup() return newObject("AnimationGroup", nil, self) end
function Frame:CreateAnimation(kind)
    self.animations = self.animations or {}
    local a = newObject("Animation", nil, self)
    a.animationKind = kind
    table.insert(self.animations, a)
    return a
end
function Frame:Play(reverse) self.playing = true; self.reversed = reverse == true; self:_Fire("OnPlay") end
function Frame:SetToFinalAlpha(on) self.toFinalAlpha = on and true or false end
-- an animation's numbers, kept so a test can read what it would do
function Frame:SetDuration(d) self.duration = d end
function Frame:GetDuration() return self.duration end
function Frame:SetFromAlpha(a) self.fromAlpha = a end
function Frame:SetToAlpha(a) self.toAlpha = a end
function Frame:SetOrder(n) self.order = n end
function Frame:SetSmoothing(kind) self.smoothing = kind end
function Frame:Stop() self.playing = false end
function Frame:IsPlaying() return self.playing == true end

-- Cooldown frames
function Frame:SetCooldownDuration(duration) self.cooldownDuration = duration end
function Frame:Clear() self.cooldownStart, self.cooldownDuration = nil, nil end

-- Template children the add-on reaches for.
local function addActionButtonParts(f)
    f.icon = f:CreateTexture(f.name and (f.name .. "Icon"))
    f.Icon = f.icon
    f.cooldown = newObject("Cooldown", f.name and (f.name .. "Cooldown"), f, "CooldownFrameTemplate")
    f.Cooldown = f.cooldown
    f.HotKey = f:CreateFontString(f.name and (f.name .. "HotKey"))
    f.Count = f:CreateFontString(f.name and (f.name .. "Count"))
    f.Name = f:CreateFontString(f.name and (f.name .. "Name"))
    f.Border = f:CreateTexture(f.name and (f.name .. "Border"))
    f.Flash = f:CreateTexture(f.name and (f.name .. "Flash"))
    f.NormalTexture = f:CreateTexture(f.name and (f.name .. "NormalTexture"))
    f.SlotBackground = f:CreateTexture()
    f.IconMask = f:CreateTexture()
    function f:GetNormalTexture() return self.NormalTexture end
    function f:SetNormalTexture(tex) self.NormalTexture.texture = tex end
    f.NewActionTexture = f:CreateTexture()
    f.SpellHighlightTexture = f:CreateTexture()
    f.PushedTexture = f:CreateTexture()
    f.HighlightTexture = f:CreateTexture()
    f.CheckedTexture = f:CreateTexture()
    function f:GetPushedTexture() return self.PushedTexture end
    function f:GetHighlightTexture() return self.HighlightTexture end
    function f:GetCheckedTexture() return self.CheckedTexture end
end

-- EnumerateFrames(frame): the frame made next after `frame` (the first with none), as the game walks every frame.
function EnumerateFrames(after)
    local i = 1
    if after then i = (rawget(after, "enumIndex") or #frameList) + 1 end
    return frameList[i]
end
-- GetCursorPosition: where the pointer is, in screen units (Stub.pointer sets it).
function GetCursorPosition() return Stub.cursorX or 0, Stub.cursorY or 0 end
function Stub.pointer(x, y) Stub.cursorX, Stub.cursorY = x, y end

function CreateFrame(kind, name, parent, templates)
    if type(parent) == "string" then parent = _G[parent] end
    local f = newObject(kind, name, parent or nil, templates)
    if parent then table.insert(parent.children, f) end
    frameList[#frameList + 1] = f
    f.enumIndex = #frameList
    if explicitlyProtected(f) then protCache = nil end
    if name then registry[name] = f; _G[name] = f end
    if f.templates:find("ActionBarButtonTemplate") then
        addActionButtonParts(f)
        -- the game's template ships as a button that uses its action (ActionBarActionButtonMixin:OnLoad), with
        -- self, focus and mouseover cast switched on
        f.attributes.type, f.attributes.typerelease = "action", "actionrelease"
        f.attributes.checkselfcast, f.attributes.checkfocuscast, f.attributes.checkmouseovercast = true, true, true
    end
    if f.templates:find("PetActionButtonTemplate") then
        -- the game's pet button: not a secure action; its own OnClick casts (left) or toggles autocast (right)
        addActionButtonParts(f)
        f.AutoCastOverlay = newObject("Frame", nil, f)
        function f.AutoCastOverlay:SetShown(on) self.shown = on and true or false end
        function f.AutoCastOverlay:ShowAutoCastEnabled(on) self.autoCastEnabled = on and true or false end
        f.scripts.PreClick = function(self) self:SetChecked(false) end
        f.scripts.OnClick = function(self, button, down)
            -- (a secure wrapper's pre-body answering false keeps this from running: Stub.click)
            -- PetActionButtonMixin_OnClick: a PICKUPACTION click (Shift, the default) picks the action up instead
            if IsModifiedClick("PICKUPACTION") then PickupPetAction(self:GetID()); return end
            if button == "LeftButton" then CastPetAction(self:GetID()) else TogglePetAutocast(self:GetID()) end
        end
    end
    if kind == "StatusBar" then f.minValue, f.maxValue, f.value = 0, 1, 0 end
    if kind == "GameTooltip" then Stub.addTooltipParts(f) end
    return f
end

-- Stub.frames: every named frame; writing a name also writes the global, as the game does.
Stub.frames = setmetatable({}, {
    __index = function(_, name) return registry[name] end,
    __newindex = function(_, name, frame) registry[name] = frame; _G[name] = frame end,
})

-- Every frame made so far (a copy of the list).
function Stub.allFrames()
    local list = {}
    for i, f in ipairs(frameList) do list[i] = f end
    return list
end

function Stub.inherits(frame, template) return frame.templates:find(template, 1, true) ~= nil end
function Stub.unitWatched(frame) return Stub.watched[frame] == true end

-- ---------------------------------------------------------------------------------------
-- Clicks

-- The keys held down now (Stub.hold sets them; a key from a binding holds its own). The game's secure
-- buttons read an attribute through these: SecureTemplates.lua builds the prefix "alt-ctrl-shift-" from them
-- and the suffix from the mouse button, then looks up prefix..name..suffix, *name..suffix, prefix..name*,
-- *name* and name, in that order.
Stub.held = { alt = false, ctrl = false, shift = false }
function Stub.hold(alt, ctrl, shift) Stub.held = { alt = alt and true or false, ctrl = ctrl and true or false,
    shift = shift and true or false } end

local function modifierPrefix()
    local prefix = ""
    if Stub.held.shift then prefix = "shift-" .. prefix end
    if Stub.held.ctrl then prefix = "ctrl-" .. prefix end
    if Stub.held.alt then prefix = "alt-" .. prefix end
    return prefix
end

local function buttonSuffix(mouse)
    if mouse == "LeftButton" then return "1" elseif mouse == "RightButton" then return "2"
    elseif mouse == "MiddleButton" then return "3" end
    return ""
end

-- SecureButton_GetModifiedAttribute (ATTRIBUTE_NOOP "" counts as nothing)
local function modified(frame, name, mouse)
    local prefix, suffix = modifierPrefix(), buttonSuffix(mouse)
    local a = frame.attributes
    local value = a[prefix .. name .. suffix]
    if value == nil then value = a["*" .. name .. suffix] end
    if value == nil then value = a[prefix .. name .. "*"] end
    if value == nil then value = a["*" .. name .. "*"] end
    if value == nil then value = a[name] end
    if value == "" then value = nil end
    return value
end
Stub.modifiedAttribute = modified

-- The game's modified clicks: self cast on Alt (its default), focus cast on Shift (the strictest case).
local MODIFIED_CLICKS = { SELFCAST = "alt", FOCUSCAST = "shift" }

-- The unit an action button would use (SecureButton_GetModifiedUnit): its unit attribute, else mouseover,
-- self or focus cast when the button asks for them and the modifier is held.
local function modifiedUnit(frame, mouse)
    local unit = modified(frame, "unit", mouse)
    if unit then return unit end
    if modified(frame, "checkmouseovercast", mouse) and Stub.cvars and Stub.cvars.enableMouseoverCast == "1"
        and UnitExists("mouseover") then return "mouseover" end
    if modified(frame, "checkselfcast", mouse) and Stub.held[MODIFIED_CLICKS.SELFCAST] then return "player" end
    if modified(frame, "checkfocuscast", mouse) and Stub.held[MODIFIED_CLICKS.FOCUSCAST] then return "focus" end
end

-- What a click does after PreClick, as the game's secure button code does it.
local function secureAction(frame, mouse)
    local actionType = modified(frame, "type", mouse)
    if actionType == nil then return end
    table.insert(Stub.secureActions, { frame = frame, type = actionType, button = mouse })
    if actionType == "action" then
        count("UseAction")
        Stub.lastUsedAction = modified(frame, "action", mouse)
        Stub.lastActionUnit = modifiedUnit(frame, mouse)
    elseif actionType == "click" then
        local target = modified(frame, "clickbutton", mouse)
        if type(target) == "string" then target = _G[target] end
        if target then Stub.click(target, mouse) end
    elseif actionType == "macro" then
        Stub.lastMacro = modified(frame, "macrotext", mouse)
        if type(Stub.lastMacro) == "string" and Stub.lastMacro:match("^%s*/reload") then ReloadUI() end
        if type(Stub.lastMacro) == "string" and Stub.lastMacro:match("^%s*/logout") then count("Logout") end
        -- "/click Name" clicks the game's own button of that name (Task 10)
        if type(Stub.lastMacro) == "string" then
            -- "/click [combat] Name" / "[nocombat]": the macro condition decides whether the line runs
            for line in Stub.lastMacro:gmatch("[^\n]+") do
                local rest = line:match("^%s*/click%s+(.-)%s*$")
                if rest then
                    local cond, name = rest:match("^(%b[])%s*(%S+)$")
                    if not cond then cond, name = "", rest end
                    if (cond ~= "[combat]" or combat) and (cond ~= "[nocombat]" or not combat) then
                        table.insert(Stub.macroClicks, name)
                        if _G[name] then Stub.click(_G[name], mouse) end
                    end
                end
            end
        end
    elseif actionType == "pet" then
        -- SECURE_ACTIONS.pet: CastPetAction(action)
        local action = modified(frame, "action", mouse)
        if action then CastPetAction(action) end
    elseif actionType == "spell" then
        count("CastSpell")
        Stub.lastSpell = modified(frame, "spell", mouse)
        Stub.lastSpellUnit = modifiedUnit(frame, mouse)
    elseif actionType == "target" then
        count("TargetUnit")
        Stub.lastTargeted = modified(frame, "unit", mouse)
    elseif actionType == "item" then
        Stub.lastItemUsed = modified(frame, "item", mouse)
    elseif actionType == "stop" then
        -- SECURE_ACTIONS.stop: SpellStopTargeting only while a spell is aimed
        if SpellIsTargeting() then
            count("SpellStopTargeting")
            Stub.targeting = false
        end
    elseif actionType == "attribute" then
        -- sets attribute-name to attribute-value on attribute-frame (a frame or its name; self when absent)
        local target = modified(frame, "attribute-frame", mouse) or frame
        if type(target) == "string" then target = _G[target] end
        local key = modified(frame, "attribute-name", mouse)
        if target and key then target:SetAttribute(key, modified(frame, "attribute-value", mouse)) end
    end
end

-- SecureActionButton_OnClick from an add-on's button (SecureTemplates.xml passes no isKeyPress / isSecureAction):
-- the action runs on the down click when the button's "useOnKeyDown" attribute (else the ActionButtonUseKeyDown
-- cvar, on by default) says so, else on the up click. A button that hears only up clicks and keeps the default never
-- acts. The game's own action bar buttons pass isSecureAction, so they act on the up click (ActionButton.lua).
local function actsNow(frame, down)
    if frame.templates:find("ActionBarButtonTemplate") then return not down end
    local useOnKeyDown = frame.attributes.useOnKeyDown
    if useOnKeyDown == nil then useOnKeyDown = Stub.cvars and Stub.cvars.ActionButtonUseKeyDown ~= "0" end
    if useOnKeyDown == nil then useOnKeyDown = true end
    if down then return useOnKeyDown and true or false end
    return not useOnKeyDown
end

-- SecureUnitButton_OnClick asks the click bindings first (C_ClickBindings): a "target" or "menu" click that no click
-- binding covers does nothing. The default profile binds only the unmodified left and right clicks.
local function unitClickAllowed(frame, mouse)
    local held = Stub.held.alt or Stub.held.ctrl or Stub.held.shift
    local bound = not held and (mouse == "LeftButton" or mouse == "RightButton")
    local kind = modified(frame, "type", mouse)
    if (kind == "target" or kind == "menu" or kind == "togglemenu") and not bound then return false end
    return true
end

-- Runs a secure wrapper's snippet (SecureHandlerWrapScript): `owner` is the header. Answers what it returns.
local function runWrap(frame, wrap, body, ...)
    if type(body) ~= "string" then return end
    local chunk = assert(loadstring("local self, button, down = ...\n" .. body, "wrap"))
    setfenv(chunk, setmetatable({ owner = wrap.header }, { __index = _G }))
    secureDepth = secureDepth + 1
    local ok, result, message = pcall(chunk, frame, ...)
    secureDepth = secureDepth - 1
    if not ok then error(result, 0) end
    return result, message
end

-- A full click (the release): PreClick, the secure wrappers' pre-bodies, the secure part and OnClick (unless a
-- pre-body answered false), the post-bodies, PostClick.
function Stub.click(frame, mouse, down)
    if type(frame) == "string" then frame = assert(registry[frame], "no frame named " .. frame) end
    mouse = mouse or "LeftButton"
    down = down or false
    frame:_Fire("PreClick", mouse, down)
    local stopped, messages = false, {}
    for i, wrap in ipairs(frame.wraps and frame.wraps.OnClick or {}) do
        local answer, message = runWrap(frame, wrap, wrap.pre, mouse, down)
        if answer == false then stopped = true end
        messages[i] = message
    end
    if not stopped then
        secureDepth = secureDepth + 1
        local ok, problem = pcall(function()
            if frame.templates:find("SecureHandlerClickTemplate") then
                runSnippet(frame, frame:GetAttribute("_onclick"), mouse, down)
            end
            if frame.templates:find("SecureUnitButtonTemplate") then
                if unitClickAllowed(frame, mouse) then secureAction(frame, mouse) end
            elseif frame.templates:find("SecureActionButtonTemplate") or frame.templates:find("ActionBarButtonTemplate") then
                if actsNow(frame, down) then secureAction(frame, mouse) end
            end
        end)
        secureDepth = secureDepth - 1
        if not ok then error(problem, 0) end
        frame:_Fire("OnClick", mouse, down)
    end
    for i, wrap in ipairs(frame.wraps and frame.wraps.OnClick or {}) do
        if wrap.post and messages[i] ~= nil then runWrap(frame, wrap, wrap.post, mouse, down) end
    end
    frame:_Fire("PostClick", mouse, down)
end

-- Whether a button hears this click (RegisterForClicks; a button that never registered hears left-button ups).
local function hears(frame, mouse, down)
    local list = frame.clicks or { "LeftButtonUp" }
    local want = mouse .. (down and "Down" or "Up")
    for _, kind in ipairs(list) do
        if kind == want or kind == (down and "AnyDown" or "AnyUp") then return true end
    end
    return false
end
Stub.hears = hears

-- A key the app presses: the binding's button is clicked (or its command run) with the key's own modifiers
-- held, as the game does for an override binding: a down click and an up click, each only if the button hears it.
-- Answers what the key reached.
-- Keyboard frames (EnableKeyboard, shown) hear the bare key (no modifiers) before the bindings, as the game's do.
local function keyboardFrames(script, bare)
    local list = {}
    for _, f in ipairs(frameList) do
        if f.keyboard and f:IsVisible() and f.scripts[script] then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do f:_Fire(script, bare) end
end
local function bareKey(key) return (key:gsub("^ALT%-", ""):gsub("^CTRL%-", ""):gsub("^SHIFT%-", "")) end

-- The two halves of a key, for a key held down (the app's Jump and Dive) or a test that looks between them.
local heldBefore = {}
function Stub.keyDown(key)
    heldBefore[key] = Stub.held
    Stub.hold(key:find("ALT%-") ~= nil, key:find("CTRL%-") ~= nil, key:find("SHIFT%-") ~= nil)
    keyboardFrames("OnKeyDown", bareKey(key))
    local binding = Stub.bindings[key]
    if not binding then return nil end
    if binding.click then
        local frame = assert(registry[binding.click], "no frame named " .. binding.click)
        local mouse = binding.button or "LeftButton"
        if hears(frame, mouse, true) then Stub.click(frame, mouse, true) end
    else
        Stub.commandsRun[#Stub.commandsRun + 1] = binding.command
    end
    return binding
end
function Stub.keyUp(key)
    local ok, problem = pcall(function()
        keyboardFrames("OnKeyUp", bareKey(key))
        local binding = Stub.bindings[key]
        if binding and binding.click then
            local frame = assert(registry[binding.click], "no frame named " .. binding.click)
            local mouse = binding.button or "LeftButton"
            if hears(frame, mouse, false) then Stub.click(frame, mouse, false) end
        end
    end)
    Stub.held = heldBefore[key] or Stub.held
    heldBefore[key] = nil
    if not ok then error(problem, 0) end
end

function Stub.pressKey(key)
    local binding = Stub.bindings[key]
    if not binding then return nil end
    local before = Stub.held
    local ok, problem = pcall(function()
        Stub.keyDown(key)
        Stub.keyUp(key)
    end)
    Stub.held = before
    heldBefore[key] = nil
    if not ok then error(problem, 0) end
    return binding
end
function Stub.secureClick(frame, mouse) Stub.click(frame, mouse) end
function Stub.mouseDown(frame, mouse) frame:_Fire("OnMouseDown", mouse or "LeftButton") end
function Stub.mouseUp(frame, mouse) frame:_Fire("OnMouseUp", mouse or "LeftButton") end

-- ---------------------------------------------------------------------------------------
-- Events, time, combat

-- PLAYER_REGEN_DISABLED comes just before the game's combat lockdown starts: while it is handled,
-- InCombatLockdown() still answers false and protected frames can still be changed (the last chance to hide
-- them). PLAYER_REGEN_ENABLED comes after the lockdown has ended.
function Stub.fire(event, ...)
    local list = {}
    for i, f in ipairs(eventFrames[event] or {}) do list[i] = f end
    local was = combat
    if event == "PLAYER_REGEN_DISABLED" then combat = false end
    local unit = ...
    local ok, problem = pcall(function(...)
        for _, f in ipairs(list) do
            local only = f.unitFilter and f.unitFilter[event]
            if not only or only[unit] then f:_Fire("OnEvent", event, ...) end
        end
    end, ...)
    if event == "PLAYER_REGEN_DISABLED" then combat = was end
    if not ok then error(problem, 0) end
end
-- The frames that asked for `event`, so a test can call their OnEvent script itself and measure the add-on's own
-- work without Stub.fire's copy of the list.
function Stub.eventFrames(event)
    local list = {}
    for i, f in ipairs(eventFrames[event] or {}) do list[i] = f end
    return list
end
function Stub.combat(on) combat = on and true or false end
function Stub.advance(seconds)
    Stub.now = Stub.now + seconds
    local due = {}
    for i = #Stub.timers, 1, -1 do
        local t = Stub.timers[i]
        if t.at <= Stub.now then table.insert(due, 1, t); table.remove(Stub.timers, i) end
    end
    for _, t in ipairs(due) do if not t.cancelled then t.fn() end end
    Stub.pumpUpdates(seconds)
end

-- One frame of the game's clock: every frame that has an OnUpdate script gets `elapsed` seconds, as the game
-- does each rendered frame. Stub.advance runs this once for the whole step, so a test steps in the size it wants.
function Stub.pumpUpdates(elapsed)
    local list = {}
    for _, f in ipairs(frameList) do
        if f.scripts.OnUpdate or (f.hooks.OnUpdate and #f.hooks.OnUpdate > 0) then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do f:_Fire("OnUpdate", elapsed) end
end

-- Every frame that has an OnUpdate script or hook now (the idle check counts these).
function Stub.onUpdateFrames()
    local list = {}
    for _, f in ipairs(frameList) do
        if f.scripts.OnUpdate or (f.hooks.OnUpdate and #f.hooks.OnUpdate > 0) then list[#list + 1] = f end
    end
    return list
end

-- ---------------------------------------------------------------------------------------
-- Screen size

-- The screen in the game's UIParent units (the tests' default is the 1366 x 1024 mockup).
function Stub.screen(width, height)
    registry.UIParent.width, registry.UIParent.height = width, height
end

-- The centre of a frame placed with ns.Anchor, in the 1366 x 1024 layout space.
function Stub.centre(frame)
    local a = assert(frame.touchAnchor, "frame was never placed with ns.Anchor")
    return a.x + a.w / 2, a.y + a.h / 2
end

-- ---------------------------------------------------------------------------------------
-- Bars, forms and vehicles: what the game's macro conditions read, and the state drivers

local function conditionHolds(cond, unit)
    local name, arg = cond:match("^(%a+):?(%w*)$")
    if name == "overridebar" then return Stub.override
    elseif name == "vehicleui" then return Stub.vehicle
    elseif name == "possessbar" then return Stub.possess
    elseif name == "shapeshift" then return Stub.tempShapeshift
    elseif name == "bonusbar" then return Stub.bonusBar == tonumber(arg)
    elseif name == "pet" then return UnitExists("pet")
    elseif name == "exists" then return UnitExists(unit or "target")
    elseif name == "dead" then return UnitExists(unit or "target") and UnitIsDead(unit or "target")
    elseif name == "nodead" then return not (UnitExists(unit or "target") and UnitIsDead(unit or "target"))
    end
    error("stub: unknown state condition " .. cond)
end

-- "[a,b] one; [c][d] two; other" -> the value of the first clause with a group whose conditions
-- all hold (several groups are an "or", as in the game's macro conditions).
local function evaluate(condition)
    for clause in condition:gmatch("[^;]+") do
        clause = clause:gsub("^%s+", ""):gsub("%s+$", "")
        if not clause:find("^%[") then return clause end
        local rest, any = clause, false
        while true do
            local conds, after = rest:match("^%[(.-)%]%s*(.*)$")
            if not conds then break end
            local all, unit = true, nil
            for cond in conds:gmatch("[^,]+") do
                cond = cond:gsub("%s", "")
                if cond:sub(1, 1) == "@" then
                    unit = cond:sub(2)          -- [@pet,exists]: the conditions that follow are about that unit
                elseif not conditionHolds(cond, unit) then
                    all = false; break
                end
            end
            if all then any = true end
            rest = after
            if not rest:find("^%[") then break end
        end
        if any then return rest end
    end
end

function Stub.setBonusBar(n) Stub.bonusBar = n or 0 end
function Stub.setVehicle(on) Stub.vehicle = on and true or false end
function Stub.setOverride(on) Stub.override = on and true or false end
function Stub.setPossess(on) Stub.possess = on and true or false end
function Stub.setTempShapeshift(on) Stub.tempShapeshift = on and true or false end

-- What the game does each frame: evaluate every registered state driver and, where the answer
-- changed, set state-<name> on its frame (secure, so allowed in combat).
function Stub.applyDrivers()
    secureDepth = secureDepth + 1
    local ok, problem = pcall(function()
        for frame, drivers in pairs(Stub.stateDrivers) do
            for state, condition in pairs(drivers) do
                local value = evaluate(condition)
                if frame:GetAttribute("state-" .. state) ~= value then
                    frame:SetAttribute("state-" .. state, value)
                    if state == "visibility" then
                        if value == "show" then frame:Show() else frame:Hide() end
                    end
                end
            end
        end
    end)
    secureDepth = secureDepth - 1
    if not ok then error(problem, 0) end
end

-- Cooldown numbers hidden in a fight: GetActionCooldown answers secret values.
function Stub.secretCooldowns(on) Stub.secretCooldownsOn = on and true or false end

-- ---------------------------------------------------------------------------------------
-- Units: the player, the target and what the cards read from them

-- Health, power, cast times and "can it be interrupted" answer hidden values in a fight.
function Stub.secretUnits(on) Stub.secretUnitsOn = on and true or false end
-- UnitInRange answers hidden values; the cast duration objects are hidden values.
function Stub.secretRange(on) Stub.secretRangeOn = on and true or false end
function Stub.secretDurations(on) Stub.secretDurationsOn = on and true or false end

-- What the game's unit watch does: a watched unit button is shown while its unit exists.
function Stub.applyUnitWatch()
    for frame in pairs(Stub.watched) do
        local unit = frame:GetAttribute("unit")
        if unit then frame.shown = UnitExists(unit) end
    end
end

-- Merges fields into Stub.units[unit] (creating it). Fields: name, level, classification,
-- reaction, controlled, canAttack, canAttackUs, isPlayer, pvp, ffa, faction, leader, combat,
-- dead, ghost, tapDenied, range, inParty, health, healthMax, power, powerMax, powerType,
-- powerToken, cast = { name =, notInterruptible =, channel = }.
function Stub.setUnit(unit, fields)
    local u = Stub.units[unit] or { exists = true }
    Stub.units[unit] = u
    for k, v in pairs(fields or {}) do u[k] = v end
    return u
end

local TARGETS = {
    enemy = { name = "Starving Mountain Lion", level = 32, reaction = 2, canAttack = true, canAttackUs = true },
    elite = { name = "Deathguard Elite", level = 35, classification = "elite", reaction = 2, canAttack = true, canAttackUs = true },
    rare = { name = "Narillasanz", level = 34, classification = "rare", reaction = 2, canAttack = true, canAttackUs = true },
    rareelite = { name = "Lord Aliden Perenolde", level = 41, classification = "rareelite", reaction = 2, canAttack = true, canAttackUs = true },
    boss = { name = "Drakkisath", level = -1, classification = "elite", reaction = 2, canAttack = true, canAttackUs = true },
    neutral = { name = "Forest Moss Creeper", level = 21, reaction = 4, canAttack = true, canAttackUs = false },
    friendly = { name = "Apothecary Lydon", level = 35, reaction = 5, canAttack = false, canAttackUs = false },
    player = { name = "Tarek", level = 34, reaction = 5, controlled = true, isPlayer = true, canAttack = false, canAttackUs = false },
}

-- Targets something (kind: enemy, elite, rare, rareelite, boss, neutral, friendly, player) or
-- nothing (nil), with opts merged over it, and fires PLAYER_TARGET_CHANGED as the game does.
function Stub.setTarget(kind, opts)
    if kind == nil then
        Stub.units.target = nil
    else
        local u = { exists = true, health = 1000, healthMax = 1000, power = 100, powerMax = 100,
            powerType = 0, powerToken = "MANA" }
        for k, v in pairs(assert(TARGETS[kind], "stub: unknown target kind " .. tostring(kind))) do u[k] = v end
        for k, v in pairs(opts or {}) do u[k] = v end
        Stub.units.target = u
    end
    Stub.applyUnitWatch()
    Stub.fire("PLAYER_TARGET_CHANGED")
end

-- state: "dead", "ghost" or nil (alive again). Health goes to 0 and UNIT_HEALTH fires.
function Stub.setDead(unit, state)
    local u = Stub.setUnit(unit, { dead = state == "dead", ghost = state == "ghost" })
    if state then u.health = 0 elseif u.health == 0 then u.health = u.healthMax or 1 end
    Stub.fire("UNIT_HEALTH", unit)
end

function Stub.setResting(on) Stub.resting = on and true or false; Stub.fire("PLAYER_UPDATE_RESTING") end

-- ---------------------------------------------------------------------------------------
-- Printing

function Stub.printed(text)
    local n = 0
    for _, line in ipairs(Stub.chat) do
        if type(line) == "string" and line:find(text, 1, true) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------------------
-- The game's API

local function installAPI()
    InCombatLockdown = function() return combat end
    IsAltKeyDown = function() return Stub.held.alt end
    IsControlKeyDown = function() return Stub.held.ctrl end
    IsShiftKeyDown = function() return Stub.held.shift end
    -- the left and right modifier keys: a held modifier is the left one unless Stub.rightHeld says the right one
    Stub.rightHeld = {}
    IsLeftControlKeyDown = function() return Stub.held.ctrl and not Stub.rightHeld.ctrl end
    IsRightControlKeyDown = function() return Stub.held.ctrl and Stub.rightHeld.ctrl == true end
    IsLeftAltKeyDown = function() return Stub.held.alt and not Stub.rightHeld.alt end
    IsRightAltKeyDown = function() return Stub.held.alt and Stub.rightHeld.alt == true end
    IsLeftShiftKeyDown = function() return Stub.held.shift and not Stub.rightHeld.shift end
    IsRightShiftKeyDown = function() return Stub.held.shift and Stub.rightHeld.shift == true end
    IsModifiedClick = function(name)
        local key = ({ SELFCAST = "alt", FOCUSCAST = "shift", PICKUPACTION = "shift" })[name]
        return key ~= nil and Stub.held[key] == true
    end
    GetTime = function() return Stub.now end
    time = os.time
    date = os.date
    debugstack = function() return "" end
    issecurevariable = function() return false end
    -- the game's action button template calls this on ACTION_RANGE_CHECK_UPDATE (it colours the key label); the
    -- stub never runs the template, so a test calls it as the game would: (button, checksRange, inRange)
    ActionButton_UpdateRangeIndicator = function() end
    hooksecurefunc = function(a, b, c)
        if type(a) == "table" then
            local old = a[b]
            a[b] = function(...) local r = { old(...) }; c(...); return unpack(r) end
        else
            local old = _G[a]
            _G[a] = function(...) local r = { old(...) }; b(...); return unpack(r) end
        end
    end
    -- EventRegistry: callbacks run as fn(owner, ...), as the game calls them.
    EventRegistry = {
        callbacks = {},
        RegisterCallback = function(self, event, fn, owner)
            self.callbacks[event] = self.callbacks[event] or {}
            table.insert(self.callbacks[event], { fn = fn, owner = owner })
        end,
        UnregisterCallback = function(self, event, owner)
            local list = self.callbacks[event] or {}
            for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
        end,
        TriggerEvent = function(self, event, ...)
            local list = {}
            for i, cb in ipairs(self.callbacks[event] or {}) do list[i] = cb end
            for _, cb in ipairs(list) do cb.fn(cb.owner, ...) end
        end,
    }
    -- the edit box that holds the keyboard (nil when none does)
    GetCurrentKeyBoardFocus = function() return Stub.keyboardFocus end
    C_Timer = {
        After = function(seconds, fn) table.insert(Stub.timers, { at = Stub.now + seconds, fn = fn }) end,
        NewTimer = function(seconds, fn)
            local t = { at = Stub.now + seconds, fn = fn }
            function t:Cancel() self.cancelled = true end
            table.insert(Stub.timers, t)
            return t
        end,
        NewTicker = function(seconds, fn)
            local t = { cancelled = false }
            function t:Cancel() self.cancelled = true end
            local function tick() if not t.cancelled then fn(t); table.insert(Stub.timers, { at = Stub.now + seconds, fn = tick }) end end
            table.insert(Stub.timers, { at = Stub.now + seconds, fn = tick })
            return t
        end,
    }
    RegisterStateDriver = function(frame, state, condition)
        Stub.stateDrivers[frame] = Stub.stateDrivers[frame] or {}
        Stub.stateDrivers[frame][state] = condition
    end
    UnregisterStateDriver = function(frame, state)
        if Stub.stateDrivers[frame] then Stub.stateDrivers[frame][state] = nil end
    end
    RegisterUnitWatch = function(frame)
        blocked(frame, "RegisterUnitWatch"); Stub.watched[frame] = true
        Stub.applyUnitWatch()
    end
    UnregisterUnitWatch = function(frame) Stub.watched[frame] = nil end
    SecureHandlerSetFrameRef = function(frame, label, ref) frame:SetFrameRef(label, ref) end
    SecureHandlerWrapScript = function(frame, script, header, pre, post)
        assert(header and select(2, header:IsProtected()), "Header frame must be explicitly protected")
        frame.wraps = frame.wraps or {}
        frame.wraps[script] = frame.wraps[script] or {}
        table.insert(frame.wraps[script], { header = header, pre = pre, post = post })
    end

    -- CreateFramePool(kind, parent, template, resetFn): Acquire() -> frame, isNew; Release(frame).
    CreateFramePool = function(kind, parent, template, resetFn)
        local pool = { active = {}, free = {}, numActive = 0 }
        function pool:Acquire()
            local f = table.remove(self.free)
            local isNew = f == nil
            if isNew then f = CreateFrame(kind, nil, parent, template) end
            self.active[f] = true; self.numActive = self.numActive + 1
            f:Show()
            return f, isNew
        end
        function pool:Release(f)
            if not self.active[f] then return false end
            self.active[f] = nil; self.numActive = self.numActive - 1
            if resetFn then resetFn(self, f) end
            f:Hide(); table.insert(self.free, f)
            return true
        end
        function pool:ReleaseAll() for f in pairs(self.active) do self:Release(f) end end
        function pool:EnumerateActive() return pairs(self.active) end
        function pool:GetNumActive() return self.numActive end
        return pool
    end

    -- Override bindings (the game refuses them in combat): Stub.bindings[key] is
    -- { click = buttonName, button = mouseButton } or { command = name }.
    local function refuseInCombat(what)
        if combat and secureDepth == 0 then error("ADDON_ACTION_BLOCKED: " .. what .. " in combat", 3) end
    end
    SetOverrideBindingClick = function(owner, isPriority, key, buttonName, mouseButton)
        refuseInCombat("SetOverrideBindingClick")
        count("SetOverrideBindingClick")
        Stub.bindings[key] = { click = buttonName, button = mouseButton, owner = owner }
    end
    SetOverrideBinding = function(owner, isPriority, key, command)
        refuseInCombat("SetOverrideBinding")
        count("SetOverrideBinding")
        Stub.bindings[key] = { command = command, owner = owner }
    end
    -- GetBindingAction(key, checkOverride): what the key runs. Override bindings (ours) count only when asked for.
    GetBindingAction = function(key, checkOverride)
        count("GetBindingAction")
        local own = Stub.gameBindings[key]
        if own then return own end
        local binding = checkOverride and Stub.bindings[key]
        if not binding then return "" end
        if binding.click then return "CLICK " .. binding.click .. ":" .. (binding.button or "LeftButton") end
        return binding.command
    end
    ClearOverrideBindings = function(owner)
        refuseInCombat("ClearOverrideBindings")
        count("ClearOverrideBindings")
        for key, binding in pairs(Stub.bindings) do
            if binding.owner == owner then Stub.bindings[key] = nil end
        end
    end
    ReloadUI = function() count("ReloadUI") end

    -- Which bar page each kind of paging uses: slot = (bar - 1) * 12 + button.
    GetOverrideBarIndex = function() return 14 end
    GetVehicleBarIndex = function() return 12 end
    GetTempShapeshiftBarIndex = function() return 13 end
    GetBonusBarOffset = function() return Stub.bonusBar end
    GetActionCooldown = function()
        if Stub.secretCooldownsOn then return Stub.secret(), Stub.secret(), Stub.secret() end
        return 0, 0, 1
    end

    -- Sounds: Stub.sounds lists every id played.
    SOUNDKIT = {
        IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPEN = 850,
        IG_MAINMENU_CLOSE = 851, IG_QUEST_FAILED = 847,
    }
    PlaySound = function(id) table.insert(Stub.sounds, id) end

    -- Action slots: Stub.actions[slot] = spell id.
    HasAction = function(slot) return Stub.actions[slot] ~= nil end
    GetActionInfo = function(slot) local id = Stub.actions[slot]; if id then return "spell", id end end
    GetActionTexture = function(slot) local id = Stub.actions[slot]; if id then return "icon" .. id end end
    PlaceAction = function(slot)
        count("PlaceAction"); Stub.lastPlaceAction = slot
        if Stub.cursor then Stub.actions[slot] = Stub.cursor.id end
    end
    PickupAction = function(slot)
        count("PickupAction")
        local id = Stub.actions[slot]
        Stub.actions[slot] = nil
        Stub.cursor = id and { kind = "spell", id = id } or nil
    end
    ClearCursor = function() count("ClearCursor"); Stub.cursor = nil end
    GetCursorInfo = function() if Stub.cursor then return Stub.cursor.kind, Stub.cursor.id end end
    PickupSpell = function(id) count("PickupSpell"); Stub.lastPickupSpell = id; Stub.cursor = { kind = "spell", id = id } end
    PickupMacro = function(id) count("PickupMacro"); Stub.lastPickupMacro = id; Stub.cursor = { kind = "macro", id = id } end
    PickupItem = function(id) count("PickupItem"); Stub.lastPickupItem = id; Stub.cursor = { kind = "item", id = id } end
    C_Spell = {
        PickupSpell = function(id) PickupSpell(id) end,
        GetSpellName = function(id) return Stub.spellNames[id] or ("Spell " .. tostring(id)) end,
        GetSpellTexture = function(id) return "icon" .. tostring(id) end,
        GetSpellInfo = function(id) return { name = Stub.spellNames[id] or ("Spell " .. tostring(id)), iconID = "icon" .. tostring(id), spellID = id } end,
    }
    C_Item = {
        PickupItem = function(id) PickupItem(id) end,
    }

    -- Units: Stub.units[unit] is a table of fields (see Stub.setUnit, Stub.setTarget).
    UnitName = function(unit)
        if unit == "player" then return Stub.playerName end
        local u = Stub.units[unit]; return u and u.name
    end
    UnitExists = function(unit) local u = Stub.units[unit]; return u ~= nil and u.exists ~= false end
    local function field(unit, key, default)
        local u = Stub.units[unit]; if not u then return default end
        local v = u[key]; if v == nil then return default end
        return v
    end
    local function hidden(v) if Stub.secretUnitsOn then return Stub.secret() end return v end
    issecretvalue = Stub.isSecret
    UnitLevel = function(unit) return field(unit, "level", 1) end
    UnitClassification = function(unit) return field(unit, "classification", "normal") end
    UnitIsDead = function(unit) return field(unit, "dead", false) and true or false end
    UnitIsGhost = function(unit) return field(unit, "ghost", false) and true or false end
    UnitIsDeadOrGhost = function(unit) return UnitIsDead(unit) or UnitIsGhost(unit) end
    UnitIsTapDenied = function(unit) return field(unit, "tapDenied", false) and true or false end
    UnitIsPVP = function(unit) return field(unit, "pvp", false) and true or false end
    UnitIsPVPFreeForAll = function(unit) return field(unit, "ffa", false) and true or false end
    UnitFactionGroup = function(unit) return field(unit, "faction", nil) end
    UnitIsGroupLeader = function(unit) return field(unit, "leader", false) and true or false end
    UnitAffectingCombat = function(unit) return (field(unit, "combat", false) or (unit == "player" and combat)) and true or false end
    IsResting = function() return Stub.resting == true end
    UnitReaction = function(unit) return field(unit, "reaction", nil) end
    UnitPlayerControlled = function(unit) return field(unit, "controlled", false) and true or false end
    UnitIsPlayer = function(unit) return field(unit, "isPlayer", false) and true or false end
    UnitIsFriend = function(a, b) return field(b, "reaction", 2) >= 5 end
    UnitIsUnit = function(a, b) return a == b end
    UnitCanAttack = function(a, b)
        if a == "player" then return field(b, "canAttack", false) and true or false end
        return field(a, "canAttackUs", false) and true or false
    end
    -- party members answer UnitInRange; everyone else answers nothing checked
    UnitInRange = function(unit)
        if field(unit, "inParty", false) then
            if Stub.secretRangeOn then return Stub.secret(), Stub.secret() end
            return field(unit, "range", true) ~= false, true
        end
        return nil, false
    end
    -- the first spell button's range check: false when the target is out of reach
    IsActionInRange = function(slot)
        if not Stub.units.target then return nil end
        if field("target", "range", true) == false then return false end
        return true
    end
    UnitHealth = function(unit) return hidden(field(unit, "health", 0)) end
    UnitHealthMax = function(unit) return hidden(field(unit, "healthMax", 1)) end
    UnitPower = function(unit) return hidden(field(unit, "power", 0)) end
    UnitPowerMax = function(unit) return hidden(field(unit, "powerMax", 0)) end
    UnitPowerType = function(unit) return field(unit, "powerType", 0), field(unit, "powerToken", "MANA") end
    PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 },
        FOCUS = { r = 1, g = 0.5, b = 0.25 } }
    GetQuestGreenRange = function() return 8 end
    Enum = Enum or {}
    Enum.LuaCurveType = { Linear = 0, Step = 1, Cosine = 2, Cubic = 3 }       -- LuaCurveObjectConstantsDocumentation
    Enum.StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }
    CreateColor = function(r, g, b, a)
        local c = { r = r, g = g, b = b, a = a or 1 }
        function c:GetRGBA() return self.r, self.g, self.b, self.a end
        return c
    end
    C_CurveUtil = {
        -- A step curve answers the value of the last point at or under x; a linear one interpolates. Evaluate is
        -- SecretArguments = AllowedWhenUntainted: a hidden x from add-on code is refused (the game's own
        -- UnitHealthPercent / UnitPowerPercent take the curve and evaluate it inside).
        CreateCurve = function()
            local curve = { points = {}, kind = Enum.LuaCurveType.Linear }
            function curve:SetType(kind) self.kind = kind end
            function curve:AddPoint(x, y) table.insert(self.points, { x = x, y = y }) end
            function curve:_Eval(x)
                local points = self.points
                if self.kind == Enum.LuaCurveType.Step then
                    local value = points[1] and points[1].y
                    for _, p in ipairs(points) do if p.x <= x then value = p.y end end
                    return value
                end
                for i = 1, #points - 1 do
                    local a, b = points[i], points[i + 1]
                    if x <= b.x then
                        if x <= a.x then return a.y end
                        return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
                    end
                end
                return points[#points] and points[#points].y
            end
            function curve:Evaluate(x)
                refuseSecret("Evaluate", x)
                return self:_Eval(x)
            end
            return curve
        end,
        -- a hidden flag cannot be branched on here, so it answers the first colour
        EvaluateColorFromBoolean = function(flag, whenTrue, whenFalse)
            if Stub.isSecret(flag) or flag then return whenTrue end
            return whenFalse
        end,
    }
    CurveConstants = { ScaleTo100 = C_CurveUtil.CreateCurve() }
    CurveConstants.ScaleTo100:AddPoint(0, 0)
    CurveConstants.ScaleTo100:AddPoint(1, 100)
    -- the fraction 0..1, through the curve when one is given; hidden in a fight
    UnitHealthPercent = function(unit, predicted, curve)
        count("UnitHealthPercent")
        if Stub.secretUnitsOn then return Stub.secret() end
        local max = field(unit, "healthMax", 1)
        local fraction = max > 0 and field(unit, "health", 0) / max or 0
        if curve then return curve:_Eval(fraction) end
        return fraction
    end
    SetPortraitTexture = function(texture, unit) Stub.portraits[texture] = unit end
    -- Casting: Stub.units[unit].cast = { name =, notInterruptible =, channel = }
    local function castOf(unit, wantChannel)
        local c = field(unit, "cast", nil)
        if c and (c.channel == true) == wantChannel then return c end
    end
    UnitCastingInfo = function(unit)
        local c = castOf(unit, false); if not c then return nil end
        return hidden(c.name), "", "icon", 0, 0, false, "cast1", hidden(c.notInterruptible == true), 1
    end
    UnitChannelInfo = function(unit)
        local c = castOf(unit, true); if not c then return nil end
        return hidden(c.name), "", "icon", 0, 0, false, hidden(c.notInterruptible == true), 1
    end
    -- the duration object: hidden (a secret) in Stub.secretDurationsOn, nothing when there is no cast
    local function durationOf(unit, kind)
        if not castOf(unit, kind == "channel") then return nil end
        if Stub.secretDurationsOn then return Stub.secret() end
        return { duration = kind }
    end
    UnitCastingDuration = function(unit) return durationOf(unit, "cast") end
    UnitChannelDuration = function(unit) return durationOf(unit, "channel") end
    -- duration text bindings: Stub.bindingsMade lists them; the stub records what the add-on sets
    Enum.DurationTextBindingProperty = { RemainingDuration = 0, RemainingPercent = 1, ElapsedDuration = 2 }
    C_StringUtil = { CreateSecondsFormatter = function() return { kind = "seconds" } end }
    C_DurationUtil = { CreateDurationTextBinding = function()
        local b = { enabled = false }
        function b:SetFontString(fs) self.fontString = fs end
        function b:SetFormatter(f) self.formatter = f end
        -- the format holds one "{}" placeholder per component (the game substitutes them in order)
        function b:SetTextFormat(fmt, components)
            local _, holes = fmt:gsub("{}", "")
            assert(holes == #components, "stub: SetTextFormat needs one {} per component, got " .. holes
                .. " for " .. #components .. " in " .. fmt)
            self.format, self.components = fmt, components
        end
        function b:SetUpdateInterval(i) self.interval = i end
        function b:SetDuration(d) self.duration = d end
        function b:Enable() self.enabled = true end
        function b:Disable() self.enabled = false end
        table.insert(Stub.bindingsMade, b)
        return b
    end }

    -- Chat
    DEFAULT_CHAT_FRAME = registry.ChatFrame1
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(Stub.chat, table.concat(parts, " "))
    end
    SlashCmdList = SlashCmdList or {}
end

-- The game's own frames that exist before any add-on loads.
local BLIZZARD_PROTECTED = {
    "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
    "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
    "MicroMenuContainer", "BagsBar", "PlayerFrame", "TargetFrame", "TargetFrameToT",
    "GamepadMainActionBarFrame",
}
local BLIZZARD_PLAIN = {
    "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
    "ObjectiveTrackerFrame", "QuestWatchFrame",
}

local function buildWorld()
    registry, frameList, eventFrames = {}, {}, {}
    local ui = CreateFrame("Frame", "UIParent")
    ui.width, ui.height = 1366, 1024
    for _, name in ipairs(BLIZZARD_PROTECTED) do
        local f = CreateFrame("Frame", name, ui)
        f.protectedFlag = true
        -- Edit Mode frames carry `system`, and the game sets isShownExternal on them.
        f.system, f.isShownExternal = true, true
    end
    for _, event in ipairs({ "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "UPDATE_BONUS_ACTIONBAR" }) do
        registry.MainActionBar:RegisterEvent(event)
    end
    for _, name in ipairs(BLIZZARD_PLAIN) do CreateFrame("Frame", name, ui) end
    for i = 1, 10 do
        local chat = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i, ui)
        chat.AddMessage = function(self, text) if self == registry.ChatFrame1 then table.insert(Stub.chat, text) end end
        CreateFrame("Button", "ChatFrame" .. i .. "Tab", ui)
        CreateFrame("EditBox", "ChatFrame" .. i .. "EditBox", chat)
    end
end

local function freshState()
    Stub.calls = Counter()
    Stub.allEvents = {}
    Stub.chat = {}
    Stub.sounds = {}
    Stub.timers = {}
    Stub.keyboardFocus = nil
    Stub.now = 1000
    Stub.secureActions = {}
    Stub.stateDrivers = {}
    Stub.watched = {}
    Stub.actions = {}
    Stub.bindings = {}
    Stub.gameBindings = {}          -- the game's own (non-override) bindings: key -> action, set by a test
    Stub.held = { alt = false, ctrl = false, shift = false }
    Stub.commandsRun = {}
    Stub.lastActionUnit, Stub.lastSpellUnit = nil, nil
    Stub.override, Stub.vehicle, Stub.possess, Stub.tempShapeshift, Stub.bonusBar = false, false, false, false, 0
    Stub.secretCooldownsOn = false
    Stub.cursor = nil
    Stub.spellNames = { [430] = "Drink", [433] = "Food" }
    Stub.playerName = "Keepsy"
    Stub.units = { player = { exists = true, level = 34, health = 1284, healthMax = 1460, power = 64,
        powerMax = 100, powerType = 0, powerToken = "MANA", faction = "Alliance", reaction = 5,
        controlled = true, isPlayer = true } }
    Stub.secretUnitsOn, Stub.resting = false, false
    Stub.secretRangeOn, Stub.secretDurationsOn, Stub.bindingsMade = false, false, {}
    Stub.portraits = {}
    Stub.bags = {}
    Stub.quests = {}
    Stub.loot = {}
    Stub.lootOrder = {}
    Stub.lastPickupSpell, Stub.lastPlaceAction = nil, nil
    combat, secureDepth = false, 0
    protCache = nil
    SlashCmdList = {}
    for k in pairs(_G) do
        if type(k) == "string" and k:match("^SLASH_") then _G[k] = nil end
    end
    buildWorld()
    installAPI()
    if Stub.extend then for _, fn in ipairs(Stub.extend) do fn() end end
end

-- Later tasks add their part of the game here: Stub.extend[#Stub.extend + 1] = fn.
Stub.extend = {}

-- A new game session with no saved variables.
function Stub.reset()
    TouchPlayDB, TouchPlayCharDB = nil, nil
    Stub.cursorX, Stub.cursorY = nil, nil
    loadedFiles = {}
    freshState()
    ns = nil
end

-- Runs add-on files in order with one shared namespace (the global `ns` in tests).
function Stub.load(...)
    ns = ns or {}
    for i = 1, select("#", ...) do
        local file = select(i, ...)
        local chunk = assert(loadfile(ADDON_DIR .. file))
        chunk(ADDON_NAME, ns)
        table.insert(loadedFiles, file)
    end
    return ns
end

-- Every file the .toc lists that exists yet, in .toc order.
function Stub.loadAll()
    local files = {}
    for line in io.lines(ADDON_DIR .. "TouchPlay.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            local f = io.open(ADDON_DIR .. line)
            if f then f:close(); files[#files + 1] = line end
        end
    end
    return Stub.load(unpack(files))
end

-- ADDON_LOADED then PLAYER_LOGIN, as the game does at login.
function Stub.login()
    Stub.fire("ADDON_LOADED", ADDON_NAME)
    Stub.fire("PLAYER_LOGIN")
end

-- /reload: the saved variables stay, everything else starts again, the same files load.
function Stub.reload()
    local db, char, files = TouchPlayDB, TouchPlayCharDB, loadedFiles
    loadedFiles = {}
    freshState()
    ns = nil
    TouchPlayDB, TouchPlayCharDB = db, char
    Stub.load(unpack(files))
    Stub.fire("ADDON_LOADED", ADDON_NAME)
end

-- ---------------------------------------------------------------------------------------
-- Tooltips, bags, items and chat links (Task 6: the info cards)

-- A frame placed with ns.Anchor: its rectangle (left, bottom, width, height) in the 1366 x 1024 layout
-- space, which is the screen at the tests' default size.
-- As the game does, in the frame's own units: a frame drawn at a scale (a thumb button at Button size 1.4) answers its
-- layout rectangle divided by its effective scale (the layout root's scale is 1 at the tests' size).
function Frame:GetRect()
    local a = self.touchAnchor
    if not a then return nil end
    local k = self:GetEffectiveScale()
    if not k or k <= 0 then k = 1 end
    return a.x / k, (1024 - (a.y + a.h)) / k, a.w / k, a.h / k
end

function Frame:GetTextColor()
    local c = self.textColor
    if c then return c[1], c[2], c[3], c[4] or 1 end
    return 1, 1, 1, 1
end

-- Stub.tooltipLines(n): every tooltip then answers n lines ("Line 1" ...), whatever it is asked.
function Stub.tooltipLines(n) Stub.tooltipOverride = n end
-- Stub.tooltipSecret(on): the lines' text and colours answer hidden values, as in a fight.
function Stub.tooltipSecret(on) Stub.tooltipSecretOn = on and true or false end
-- Stub.setMouseover(name, fields): the unit under the pointer (nothing when name is nil).
function Stub.setMouseover(name, fields)
    if name == nil then Stub.units.mouseover = nil; return end
    local u = { exists = true, name = name, level = 32, reaction = 2, canAttack = true, canAttackUs = true }
    for k, v in pairs(fields or {}) do u[k] = v end
    Stub.units.mouseover = u
end
-- Stub.setGameTooltip(lines): what the game's own GameTooltip shows (nothing when lines is nil).
-- Each line is a string or { left =, right = }.
function Stub.setGameTooltip(lines)
    local tip = registry.GameTooltip
    tip:ClearLines()
    if not lines then tip.shown = false; return end
    for i, line in ipairs(lines) do
        if type(line) == "string" then line = { left = line } end
        tip:_PutLine(i, line)
    end
    tip.n = #lines
    tip.shown = true
end
function Stub.setMerchant(on) Stub.merchantOpen = on and true or false; if registry.MerchantFrame then registry.MerchantFrame.shown = Stub.merchantOpen end end

-- What the game's tooltip would say for a kind of thing: a list of { left, right, r, g, b }.
local function tooltipFor(kind, a, b)
    if Stub.tooltipOverride then
        local list = {}
        for i = 1, Stub.tooltipOverride do list[i] = { left = "Line " .. i } end
        return list
    end
    if kind == "action" then
        local id = Stub.actions[a]
        if not id then return nil end
        return { { left = C_Spell.GetSpellName(id) }, { left = "125 Mana", right = "30 yd range" },
            { left = "Launches a bolt of frost at the enemy.", r = 1, g = 0.82, b = 0 } }
    elseif kind == "bag" then
        local item = Stub.bags[a] and Stub.bags[a][b]
        if not item then return nil end
        local c = ITEM_QUALITY_COLORS[item.quality or 1]
        return { { left = item.name, r = c.r, g = c.g, b = c.b }, { left = "Binds when equipped" },
            { left = "Back", right = "Cloth" } }
    elseif kind == "link" then
        return { { left = "Item " .. tostring(a) } }
    elseif kind == "unit" then
        local u = Stub.units[a]
        if not u or u.exists == false then return nil end
        return { { left = u.name or (a == "player" and Stub.playerName) or "Unknown", r = u.reaction and u.reaction >= 5 and 0.67 or 1, g = 0.2, b = 0.2 },
            { left = "Level " .. tostring(u.level or 1) } }
    elseif kind == "spell" then
        return { { left = C_Spell.GetSpellName(a) }, { left = "Shapeshift form", right = "Instant" },
            { left = "Changes your shape.", r = 1, g = 0.82, b = 0 } }
    elseif kind == "petAction" then
        local action = Stub.petActions and Stub.petActions[a]
        if not action then return nil end
        return { { left = action.name }, { left = "Pet ability", right = "Instant" } }
    elseif kind == "aura" then
        local aura = Stub.auras[a] and Stub.auras[a][b]
        if not aura then return nil end
        return { { left = aura.name }, { left = aura.text or "", r = 1, g = 0.82, b = 0 } }
    end
end

function Stub.addTooltipParts(tip)
    local base = tip.name or "Tooltip"
    tip.leftLines, tip.rightLines, tip.n = {}, {}, 0
    for i = 1, 60 do
        local l = tip:CreateFontString(base .. "TextLeft" .. i)
        local r = tip:CreateFontString(base .. "TextRight" .. i)
        r.shown = false
        tip.leftLines[i], tip.rightLines[i] = l, r
    end
    function tip:_PutLine(i, line)
        local secret = Stub.tooltipSecretOn
        local l, r = self.leftLines[i], self.rightLines[i]
        l.text = secret and Stub.secret() or line.left
        l.textColor = { line.r or 1, line.g or 1, line.b or 1, 1 }
        if line.right then
            r.text = secret and Stub.secret() or line.right
            r.textColor = { 1, 1, 1, 1 }
            r.shown = true
        end
    end
    function tip:ClearLines()
        for i = 1, 60 do
            self.leftLines[i].text, self.rightLines[i].text, self.rightLines[i].shown = nil, nil, false
        end
        self.n = 0
    end
    function tip:NumLines() return self.n end
    function tip:SetOwner(owner, anchor) self.owner, self.ownerAnchor = owner, anchor end
    function tip:GetOwner() return self.owner end
    local function fill(self, list)
        self:ClearLines()
        if not list then return false end
        for i, line in ipairs(list) do self:_PutLine(i, line) end
        self.n = #list
        self.shown = true
        return true
    end
    function tip:SetAction(slot) return fill(self, tooltipFor("action", slot)) end
    function tip:SetBagItem(bag, slot) return fill(self, tooltipFor("bag", bag, slot)) end
    function tip:SetHyperlink(link) return fill(self, tooltipFor("link", link)) end
    function tip:SetUnit(unit) return fill(self, tooltipFor("unit", unit)) end
    function tip:SetUnitAura(unit, index) return fill(self, tooltipFor("aura", unit, index)) end
    function tip:SetSpellByID(id) return fill(self, tooltipFor("spell", id)) end
    function tip:SetPetAction(index) return fill(self, tooltipFor("petAction", index)) end
end

-- The game refuses its protected functions from insecure code in a fight.
local function protectedInFight(name)
    if combat then error("ADDON_ACTION_BLOCKED: " .. name .. " in combat", 3) end
    count(name)
end

Stub.extend[#Stub.extend + 1] = function()
    Stub.tooltipOverride, Stub.tooltipSecretOn, Stub.merchantOpen = nil, false, false
    Stub.auras, Stub.equippable, Stub.chatLinkOpen = {}, {}, false
    Stub.lastLinked, Stub.lastChatOpened, Stub.lastTell, Stub.lastInvite = nil, nil, nil, nil
    Stub.lastUsedItem, Stub.lastEquipped, Stub.lastCancelledBuff, Stub.lastTargetedUnit = nil, nil, nil, nil
    Stub.lastTargetExact, Stub.lastInspected, Stub.lastTraded, Stub.lastFollowed = nil, nil, nil, nil
    local ui = registry.UIParent
    CreateFrame("GameTooltip", "GameTooltip", ui).shown = false
    -- the game's default tooltip place (SharedTooltipTemplates.lua:87): bottom right, over the thumb side
    GameTooltip_SetDefaultAnchor = function(tooltip, parent)
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -100, 100)
    end
    local merchant = CreateFrame("Frame", "MerchantFrame", ui)
    merchant.shown = false
    ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
    C_Container = {
        GetContainerItemInfo = function(bag, slot)
            local item = Stub.bags[bag] and Stub.bags[bag][slot]
            if not item then return nil end
            return { stackCount = item.count or 1, hyperlink = item.link or item.name, quality = item.quality or 1,
                iconFileID = item.icon or "bagicon", itemName = item.name, itemID = item.itemID }
        end,
        GetContainerItemLink = function(bag, slot)
            local item = Stub.bags[bag] and Stub.bags[bag][slot]
            return item and (item.link or item.name)
        end,
        UseContainerItem = function(bag, slot) protectedInFight("UseContainerItem"); Stub.lastUsedItem = { bag, slot } end,
        PickupContainerItem = function(bag, slot) protectedInFight("PickupContainerItem"); Stub.lastPickedItem = { bag, slot } end,
    }
    C_Item.IsEquippableItem = function(link) return Stub.equippable[link] == true end
    C_Item.EquipItemByName = function(link) protectedInFight("EquipItemByName"); Stub.lastEquipped = link end
    DeleteCursorItem = function() protectedInFight("DeleteCursorItem") end
    -- TargetUnit is restricted to secure code even out of a fight (R35): our own code calling it is an error
    TargetUnit = function(unit, exact)
        if secureDepth == 0 then error("ADDON_ACTION_FORBIDDEN: TargetUnit() can only be called from secure code", 2) end
        protectedInFight("TargetUnit"); Stub.lastTargetedUnit = unit; Stub.lastTargetExact = exact
    end
    CancelUnitBuff = function(unit, index) protectedInFight("CancelUnitBuff"); Stub.lastCancelledBuff = { unit, index } end
    InspectUnit = function(unit) count("InspectUnit"); Stub.lastInspected = unit end
    InitiateTrade = function(unit) protectedInFight("InitiateTrade"); Stub.lastTraded = unit end
    FollowUnit = function(unit) protectedInFight("FollowUnit"); Stub.lastFollowed = unit end
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index)
            local aura = Stub.auras[unit] and Stub.auras[unit][index]
            return aura and { name = aura.name, icon = aura.icon or "auraicon" }
        end,
    }
    C_PartyInfo = { InviteUnit = function(name) count("InviteUnit"); Stub.lastInvite = name end }
    ChatFrameUtil = {
        InsertLink = function(link) count("InsertLink"); Stub.lastLinked = link; return Stub.chatLinkOpen end,
        OpenChat = function(text) count("OpenChat"); Stub.lastChatOpened = text end,
        SendTell = function(name) count("SendTell"); Stub.lastTell = name end,
    }
    C_QuestLog = {
        GetTitleForQuestID = function(id) return Stub.quests[id] and Stub.quests[id].title end,
        GetQuestObjectives = function(id) return Stub.quests[id] and Stub.quests[id].objectives or {} end,
        RemoveQuestWatch = function(id) count("RemoveQuestWatch"); Stub.lastUntracked = id end,
    }
    C_SuperTrack = { SetSuperTrackedQuestID = function(id) count("SuperTrack"); Stub.lastSuperTracked = id end }
    OpenQuestLog = function() count("OpenQuestLog") end
    UnitGUID = function(unit)
        local u = Stub.units[unit]; if not u or u.exists == false then return nil end
        return u.guid or ("guid:" .. tostring(u.name or (unit == "player" and Stub.playerName)))
    end
    UnitInParty = function(unit) local u = Stub.units[unit]; return u ~= nil and u.inParty == true end
end

-- ---------------------------------------------------------------------------------------
-- The spell picker (Task 7): the spellbook, action slots that hold spells or items, bag scans

-- Stub.actions[slot] is a spell id (as before) or { kind = "spell"|"item"|"macro", id = }.
-- Stub.spellbook.lines[i] = { name =, spells = { { id =, name =, passive =, future = }, ... } }:
-- the slot numbers of the spellbook follow the lines in order, as the game numbers them.
-- Stub.itemSpells[itemID] = true marks a bag item that has a use (a potion, food).
Stub.extend[#Stub.extend + 1] = function()
    local function entryOf(slot)
        local a = Stub.actions[slot]
        if type(a) == "number" then return { kind = "spell", id = a } end
        return a
    end
    HasAction = function(slot) return entryOf(slot) ~= nil end
    GetActionInfo = function(slot) local e = entryOf(slot); if e then return e.kind, e.id end end
    GetActionTexture = function(slot) local e = entryOf(slot); if e then return "icon" .. e.id end end
    PlaceAction = function(slot)
        count("PlaceAction"); Stub.lastPlaceAction = slot
        if not Stub.cursor then return end
        local old = entryOf(slot)
        -- a mount on the cursor lands on the button as a "summonmount" action
        Stub.actions[slot] = { kind = Stub.cursor.kind == "mount" and "summonmount" or Stub.cursor.kind, id = Stub.cursor.id }
        Stub.cursor = old and { kind = old.kind, id = old.id } or nil
    end
    PickupAction = function(slot)
        count("PickupAction")
        local old = entryOf(slot)
        Stub.actions[slot] = nil
        Stub.cursor = old and { kind = old.kind, id = old.id } or nil
    end
    function Stub.cursorEmpty() return Stub.cursor == nil end

    Stub.spellbook = { lines = {
        { name = "General", spells = { { id = 6603, name = "Attack" }, { id = 2481, name = "Find Treasure", passive = true } } },
        { name = "Arcane", spells = { { id = 1459, name = "Arcane Intellect" }, { id = 1953, name = "Blink" } } },
        { name = "Fire", spells = { { id = 133, name = "Fireball" }, { id = 2136, name = "Fire Blast" } } },
        { name = "Frost", spells = {
            { id = 116, name = "Frostbolt" }, { id = 120, name = "Cone of Cold" }, { id = 122, name = "Frost Nova" },
            { id = 11958, name = "Cold Snap", future = true }, { id = 115, name = "Frost Channeling", passive = true },
        } },
    } }
    Enum = Enum or {}
    Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
    Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
    local function slotItem(slot)
        local n = 0
        for li, line in ipairs(Stub.spellbook.lines) do
            for _, sp in ipairs(line.spells) do
                n = n + 1
                if n == slot then return sp, li end
            end
        end
    end
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #Stub.spellbook.lines end,
        GetSpellBookSkillLineInfo = function(i)
            local offset = 0
            for li, line in ipairs(Stub.spellbook.lines) do
                if li == i then
                    return { name = line.name, iconID = "lineicon" .. li, itemIndexOffset = offset,
                        numSpellBookItems = #line.spells, isGuild = false, shouldHide = line.hidden == true,
                        offSpecID = line.offSpec and 1 or nil }
                end
                offset = offset + #line.spells
            end
        end,
        GetSpellBookItemInfo = function(slot, bank)
            local sp, li = slotItem(slot)
            if not sp or bank ~= Enum.SpellBookSpellBank.Player then return nil end
            return { actionID = sp.id, spellID = sp.id, itemType = sp.future and 2 or 1, name = sp.name,
                iconID = "icon" .. sp.id, isPassive = sp.passive == true, isOffSpec = false, skillLineIndex = li,
                subName = sp.rank or "" }
        end,
        -- a spell's rank text ("Rank 3"); sp.low marks a rank below a higher known one, as the game's own call does
        IsSpellBookItemLowRank = function(slot, bank)
            local sp = slotItem(slot)
            return sp ~= nil and sp.low == true
        end,
        FindSpellBookSlotForSpell = function(id)
            local n = 0
            for _, line in ipairs(Stub.spellbook.lines) do
                for _, sp in ipairs(line.spells) do
                    n = n + 1
                    if sp.id == id then return n, Enum.SpellBookSpellBank.Player end
                end
            end
        end,
    }
    C_Spell.GetSpellSubtext = function(id)
        for _, line in ipairs(Stub.spellbook.lines) do
            for _, sp in ipairs(line.spells) do
                if sp.id == id then return sp.rank or "" end
            end
        end
        return ""
    end
    -- Stub.addRanks(school, name, { id1, id2, id3 }): a spell known at several ranks (the last id is the highest).
    function Stub.addRanks(school, name, ids)
        for _, line in ipairs(Stub.spellbook.lines) do
            if line.name == school then
                for i, id in ipairs(ids) do
                    line.spells[#line.spells + 1] = { id = id, name = name, rank = "Rank " .. i, low = i < #ids }
                end
            end
        end
    end
    -- The mount journal: Stub.mounts lists the journal in display order (the game's is alphabetical, and the player's
    -- own filters decide what shows). Pickup(displayIndex) puts the mount on the cursor; index 0 is the random
    -- favourite button. SummonByID is protected: the stub fails loudly if anything calls it.
    Stub.mounts = {
        { id = 241, name = "Brown Horse", icon = "mount241", collected = true },
        { id = 17, name = "Frostwolf Howler", icon = "mount17", collected = true, favorite = true },
        { id = 6, name = "Mottled Raptor", icon = "mount6", collected = false },
        { id = 35, name = "Swift Palomino", icon = "mount35", collected = true, favorite = true },
        { id = 90, name = "Nightsaber (other faction)", icon = "mount90", collected = true, hidden = true },
    }
    C_MountJournal = {
        GetNumDisplayedMounts = function() return #Stub.mounts end,
        GetDisplayedMountID = function(i) local m = Stub.mounts[i]; return m and m.id end,
        GetDisplayedMountInfo = function(i)
            local m = Stub.mounts[i]
            if not m then return end
            return m.name, 1000 + m.id, m.icon, false, true, 0, m.favorite == true, false, nil,
                m.hidden == true, m.collected == true, m.id, false
        end,
        Pickup = function(i)
            count("MountPickup")
            if i == 0 then Stub.cursor = { kind = "mount", id = 0 }; return end
            local m = Stub.mounts[i]
            if m then Stub.cursor = { kind = "mount", id = m.id } end
        end,
        SummonByID = function() error("SummonByID is protected: add-on code must not call it") end,
        -- the whole journal by mount id (every mount, collected or not), as GetMountInfoByID answers
        GetMountIDs = function()
            local ids = {}
            for _, m in ipairs(Stub.mounts) do ids[#ids + 1] = m.id end
            return ids
        end,
        GetMountInfoByID = function(id)
            for _, m in ipairs(Stub.mounts) do
                if m.id == id then
                    return m.name, 1000 + m.id, m.icon, false, true, 0, m.favorite == true, false, nil,
                        m.hidden == true, m.collected == true, m.id, false
                end
            end
        end,
    }
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    Stub.itemSpells = {}
    C_Container.GetContainerNumSlots = function(bag)
        local n = 0
        for slot in pairs(Stub.bags[bag] or {}) do if slot > n then n = slot end end
        return n
    end
    C_Item.GetItemSpell = function(id)
        if Stub.itemSpells[id] then return "Use " .. tostring(id), id end
    end
end

-- ---------------------------------------------------------------------------------------
-- The item column (Task 8): bag items with a category and a required level, item counts and
-- cooldowns, the power percentage

-- Stub.addBagItem({ id =, cat = "food"|"drink"|"health"|"mana"|"gem"|"other", req =, count =, name = }) puts a
-- stack in the first free slot of bag 0 and teaches the item APIs what it is: a health or mana potion is a
-- Consumable Potion whose use spell and name say which (as the game's do), "other" is a Potion that is neither
-- (a resistance potion). A "gem" should use a real mana gem id (5513).
Stub.extend[#Stub.extend + 1] = function()
    Stub.itemInfo, Stub.itemCooldowns = {}, {}
    function Stub.addBagItem(item)
        Stub.bags[0] = Stub.bags[0] or {}
        local slot = 1
        while Stub.bags[0][slot] do slot = slot + 1 end
        Stub.bags[0][slot] = { itemID = item.id, count = item.count or 1, link = "item:" .. item.id,
            name = item.name or ("Item " .. item.id) }
        Stub.itemInfo[item.id] = { cat = item.cat, req = item.req or 0, name = item.name, spell = item.spell }
        return slot
    end
    function Stub.removeBagItem(id)
        for _, bag in pairs(Stub.bags) do
            for slot, item in pairs(bag) do if item.itemID == id then bag[slot] = nil end end
        end
    end
    -- Stub.itemUnloaded[id] = true: the game has not cached this item yet (GetItemInfo answers nothing)
    Stub.itemUnloaded = {}
    local classOf = { food = { 0, 5 }, drink = { 0, 5 }, health = { 0, 1 }, mana = { 0, 1 }, other = { 0, 1 }, gem = { 0, 8 } }
    local nameOf = { health = "Greater Healing Potion", mana = "Superior Mana Potion", other = "Fire Resistance Potion" }
    C_Item.GetItemInfoInstant = function(id)
        local info = Stub.itemInfo[id]
        if not info then return id, "Armor", "Cloth", "", "icon" .. id, 4, 1 end
        local class = classOf[info.cat] or { 0, 0 }
        return id, "Consumable", "", "", "icon" .. id, class[1], class[2]
    end
    C_Item.GetItemInfo = function(id)
        local info = Stub.itemInfo[id]
        if not info or Stub.itemUnloaded[id] then return nil end
        return info.name or nameOf[info.cat] or ("Item " .. id), "item:" .. id, 1, 1, info.req, "Consumable", "", 20, "",
            "icon" .. id, 0, 0, 0
    end
    C_Item.GetItemIconByID = function(id) return "icon" .. tostring(id) end
    C_Item.GetItemCount = function(id)
        local n = 0
        for _, bag in pairs(Stub.bags) do
            for _, item in pairs(bag) do if item.itemID == id then n = n + (item.count or 1) end end
        end
        return n
    end
    C_Item.GetItemCooldown = function(id)
        if Stub.secretCooldownsOn then return Stub.secret(), Stub.secret(), true end
        local c = Stub.itemCooldowns[id]
        if c then return c[1], c[2], true end
        return 0, 0, true
    end
    -- the item's use spell, as the game names it: Food or Drink (spells 433 and 430)
    local oldSpell = C_Item.GetItemSpell
    C_Item.GetItemSpell = function(id)
        local info = Stub.itemInfo[id]
        if info and info.spell then return info.spell, 9000 + id end
        if info and info.cat == "food" then return "Food", 433 end
        if info and info.cat == "drink" then return "Drink", 430 end
        if info and info.cat == "health" then return "Healing Potion", 439 end
        if info and info.cat == "mana" then return "Mana Potion", 438 end
        if info and info.cat == "other" then return "Fire Protection", 7233 end
        return oldSpell(id)
    end
    -- UnitPowerPercent(unit, powerType, unmodified, curve): a hidden answer in Stub.secretUnits
    UnitPowerPercent = function(unit, powerType, unmodified, curve)
        count("UnitPowerPercent")
        if Stub.secretUnitsOn then return Stub.secret() end
        local u = Stub.units[unit] or {}
        local max = u.powerMax or 0
        local fraction = max > 0 and (u.power or 0) / max or 0
        if curve then return curve:_Eval(fraction) end
        return fraction
    end
end

-- ---------------------------------------------------------------------------------------
-- Test runner

local passed, failed = 0, {}
function T(name, fn)
    local ok, problem = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = name
        io.stderr:write("FAIL " .. name .. ": " .. tostring(problem) .. "\n")
    end
end

function Stub.done(label)
    if #failed > 0 then
        io.stderr:write(label .. ": " .. #failed .. " FAILED (" .. table.concat(failed, ", ") .. ")\n")
        os.exit(1)
    end
    print_real(label .. ": " .. passed .. " tests PASS")
end

-- ---------------------------------------------------------------------------------------
-- Class bars (Task 9): forms and stances, the pet bar, stealth, the player's class

-- Stub.setForms({ { name =, spell =, castable = }, ... }) is the class's shapeshift forms (or stances);
-- Stub.setActiveForm(n) the one you are in (0 = none). Stub.setPet(true) gives the pet unit;
-- Stub.setPetAction(slot, { name =, texture =, isToken =, active =, autoCastAllowed =, autoCastEnabled =,
-- usable = }) fills a pet slot; Stub.setPetHappiness(1..3 or nil). Each fires the event the game fires.
Stub.extend[#Stub.extend + 1] = function()
    Stub.forms, Stub.activeForm, Stub.stealthed = {}, 0, false
    Stub.petActions, Stub.petHappiness, Stub.hunterPet = {}, nil, true
    Stub.playerClass = "WARRIOR"
    Stub.lastPetAction, Stub.lastAutocast = nil, nil

    GetNumShapeshiftForms = function() return #Stub.forms end
    GetShapeshiftForm = function() return Stub.activeForm end
    GetShapeshiftFormInfo = function(i)
        local form = Stub.forms[i]
        if not form then return nil end
        return form.texture or ("formicon" .. i), Stub.activeForm == i, form.castable ~= false, form.spell
    end
    GetShapeshiftFormCooldown = function()
        if Stub.secretCooldownsOn then return Stub.secret(), Stub.secret(), Stub.secret() end
        return 0, 0, 1
    end
    IsStealthed = function() return Stub.stealthed end
    UnitClassBase = function() return Stub.playerClass end

    GetPetActionInfo = function(i)
        local a = Stub.petActions[i]
        if not a then return nil end
        return a.name, a.texture, a.isToken or false, a.active or false, a.autoCastAllowed or false,
            a.autoCastEnabled or false, a.spell
    end
    GetPetActionCooldown = function()
        if Stub.secretCooldownsOn then return Stub.secret(), Stub.secret(), Stub.secret() end
        return 0, 0, 1
    end
    GetPetActionSlotUsable = function(i)
        local a = Stub.petActions[i]
        return a ~= nil and a.usable ~= false
    end
    CastPetAction = function(i) count("CastPetAction"); Stub.lastPetAction = i end
    PickupPetAction = function(i) count("PickupPetAction"); Stub.lastPickupPetAction = i end
    -- the spells the character knows (nil: every spell, as before this table existed)
    Stub.knownSpells = nil
    IsPlayerSpell = function(id) return Stub.knownSpells == nil or Stub.knownSpells[id] == true end
    TogglePetAutocast = function(i) count("TogglePetAutocast"); Stub.lastAutocast = i end
    HasPetUI = function() return Stub.units.pet ~= nil, Stub.hunterPet end
    C_PetInfo = {
        GetPetHappiness = function()
            if Stub.petHappiness then return Stub.petHappiness, 0, 0 end
        end,
    }
end

function Stub.setForms(list)
    Stub.forms = list
    Stub.fire("UPDATE_SHAPESHIFT_FORMS")
end
function Stub.setActiveForm(n)
    Stub.activeForm = n or 0
    Stub.fire("UPDATE_SHAPESHIFT_FORM")
end
function Stub.setStealth(on)
    Stub.stealthed = on and true or false
    Stub.fire("UPDATE_STEALTH")
end
function Stub.setPet(on)
    if on then Stub.setUnit("pet", { name = "Fang", dead = false }) else Stub.units.pet = nil end
    Stub.fire("UNIT_PET", "player")
end
function Stub.setPetAction(slot, fields)
    Stub.petActions[slot] = fields
    Stub.fire("PET_BAR_UPDATE")
end
function Stub.setPetHappiness(level)
    Stub.petHappiness = level
    Stub.fire("UNIT_HAPPINESS", "pet")
end

-- ---------------------------------------------------------------------------------------
-- The rest of the HUD (Task 10): quests, the minimap and its neighbours, experience, away,
-- mirror timers, the game's buttons the secure clicks reach

-- Stub.setQuests({ { id =, title =, objectives = { { text =, finished = } }, complete =, failed =,
-- timeTotal =, timeElapsed =, watched = false }, ... }) puts those quests in the log (watched
-- unless said otherwise) and fires QUEST_LOG_UPDATE.
Stub.extend[#Stub.extend + 1] = function()
    local ui = registry.UIParent
    Stub.watchList, Stub.questLog, Stub.macroClicks, Stub.gameClicks = {}, {}, {}, {}
    Stub.zone, Stub.hour, Stub.minute, Stub.mail = "Tarren Mill", 3, 10, false
    Stub.mapPos, Stub.instanceKind, Stub.tracking = { 0.623, 0.202 }, nil, {}
    Stub.zoom, Stub.xp, Stub.talentPoints = 0, { have = 4700, max = 10000, rested = nil }, false
    Stub.chatSent = {}

    -- the game's own buttons that the secure clicks reach; each counts its clicks
    local function gameButton(name, parent)
        local b = CreateFrame("Button", name, parent or ui)
        b.scripts.OnClick = function() Stub.gameClicks[name or "?"] = (Stub.gameClicks[name or "?"] or 0) + 1 end
        return b
    end
    gameButton("MainMenuBarBackpackButton")
    gameButton("QuestLogMicroButton")
    gameButton("MainMenuMicroButton")

    -- MinimapCluster.ZoneTextButton (no global name in the game), Tracking.Button, the Minimap
    local cluster = CreateFrame("Frame", "MinimapCluster", ui)
    cluster.ZoneTextButton = CreateFrame("Button", nil, cluster)
    cluster.ZoneTextButton.scripts.OnClick = function() count("ToggleWorldMap") end
    cluster.Tracking = CreateFrame("Frame", nil, cluster)
    cluster.Tracking.Button = CreateFrame("Button", nil, cluster.Tracking)
    cluster.Tracking.Button.scripts.OnClick = function() count("TrackingMenu") end
    local container = CreateFrame("Frame", nil, cluster)
    local map = CreateFrame("Minimap", "Minimap", container)
    map:SetSize(198, 198)
    map:SetPoint("CENTER", container, "CENTER", 0, 0)
    map.GetZoom = function() return Stub.zoom end
    map.SetZoom = function(_, z) Stub.zoom = z end
    map.GetZoomLevels = function() return 6 end
    CreateFrame("Frame", "MinimapBackdrop", map)

    -- the breath timer container: three bars, as the game lays them out
    local box = CreateFrame("Frame", "MirrorTimerContainer", ui)
    box:SetPoint("TOP", ui, "TOP", 0, -100)
    box.mirrorTimers = {}
    for i = 1, 3 do
        local timer = CreateFrame("Frame", nil, box)
        timer:SetSize(206, 32)
        timer.StatusBar = CreateFrame("StatusBar", nil, timer)
        timer.StatusBar:SetSize(195, 13)
        box.mirrorTimers[i] = timer
    end

    local old = C_QuestLog
    C_QuestLog.GetNumQuestWatches = function() return #Stub.watchList end
    C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return Stub.watchList[i] end
    C_QuestLog.IsComplete = function(id) return Stub.quests[id] ~= nil and Stub.quests[id].complete == true end
    C_QuestLog.IsFailed = function(id) return Stub.quests[id] ~= nil and Stub.quests[id].failed == true end
    C_QuestLog.GetTimeAllowed = function(id)
        local q = Stub.quests[id]
        if q and q.timeTotal then return q.timeTotal, q.timeElapsed or 0 end
    end
    C_QuestLog.GetNumQuestLogEntries = function() return #Stub.questLog end
    C_QuestLog.GetInfo = function(i)
        local id = Stub.questLog[i]
        return id and { isHeader = false, questID = id, title = Stub.quests[id].title } or nil
    end

    GetMinimapZoneText = function() return Stub.zone end
    GetGameTime = function() return Stub.hour, Stub.minute end
    HasNewMail = function() return Stub.mail end
    IsInInstance = function()
        if Stub.instanceKind then return true, Stub.instanceKind end
        return false, "none"
    end
    C_Map = {
        GetBestMapForUnit = function() return Stub.mapPos and 1427 or nil end,
        GetPlayerMapPosition = function()
            if not Stub.mapPos then return nil end
            return { GetXY = function() return Stub.mapPos[1], Stub.mapPos[2] end }
        end,
    }
    C_Minimap = {
        GetNumTrackingTypes = function() return #Stub.tracking end,
        GetTrackingInfo = function(i) return Stub.tracking[i] end,
    }
    UnitXP = function() return Stub.xp.have end
    UnitXPMax = function() return Stub.xp.max end
    GetXPExhaustion = function() return Stub.xp.rested end
    BreakUpLargeNumbers = function(n) return tostring(n) end
    C_ClassTalents = { HasUnspentTalentPoints = function() return Stub.talentPoints end }
    UnitIsAFK = function(unit) return (Stub.units[unit] and Stub.units[unit].afk) == true end
    C_ChatInfo = { SendChatMessage = function(text, kind)
        table.insert(Stub.chatSent, { text = text, kind = kind })
        if kind == "AFK" and Stub.units.player then Stub.units.player.afk = not Stub.units.player.afk end
    end }
    Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
    SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 = 43936
    ToggleGameMenu = function() count("ToggleGameMenu") end
    C_DurationUtil.CreateDuration = function()
        local d = {}
        function d:SetTimeFromStart(start, total) self.start, self.total = start, total end
        return d
    end
end

-- Button:Click(): the game's way to press a button from code.
function Frame:Click(mouse) Stub.click(self, mouse) end

function Stub.setQuests(list)
    Stub.watchList, Stub.questLog, Stub.quests = {}, {}, {}
    for _, q in ipairs(list) do
        Stub.quests[q.id] = q
        table.insert(Stub.questLog, q.id)
        if q.watched ~= false then table.insert(Stub.watchList, q.id) end
    end
    Stub.fire("QUEST_LOG_UPDATE")
end

-- The player is away (AFK) or back; fires the flags event as the game does.
function Stub.setAfk(on)
    Stub.setUnit("player", { afk = on and true or false })
    Stub.fire("PLAYER_FLAGS_CHANGED", "player")
end


-- ---------------------------------------------------------------------------------------
-- Interact, Jump, Dive, aiming and flights (Task 11)

-- Stub.units.softinteract is the game's soft interact unit (Stub.setSoftInteract). A unit is a
-- game object when `object` is set; `lootable` gives CanLootUnit; `creatureTypeID` is 1 for a beast.
Stub.extend[#Stub.extend + 1] = function()
    Stub.swimming, Stub.mounted, Stub.targeting, Stub.taxi = false, false, false, false
    Stub.cvars = { SoftTargetInteract = "1" }
    Stub.taxiNodes = {}
    IsSwimming = function() return Stub.swimming end
    IsMounted = function() return Stub.mounted end
    SpellIsTargeting = function() return Stub.targeting end
    UnitOnTaxi = function(unit) return unit == "player" and Stub.taxi end
    GetCVar = function(name) return Stub.cvars[name] end
    SetCVar = function(name, value) count("SetCVar"); Stub.cvars[name] = tostring(value) end
    InteractUnit = function() count("InteractUnit") end
    JumpOrAscendStart = function() count("JumpOrAscendStart") end
    TaxiRequestEarlyLanding = function() count("TaxiRequestEarlyLanding") end
    TaxiNodeName = function(index) return Stub.taxiNodes[index] end
    TakeTaxiNode = function(index) count("TakeTaxiNode") end
    ERR_BADATTACKFACING = "Target needs to be in front of you."
    UnitIsGameObject = function(unit)
        local u = Stub.units[unit]; return u ~= nil and u.object == true
    end
    UnitCreatureType = function(unit)
        local u = Stub.units[unit]; if not u then return nil end
        return u.creatureType or "Humanoid", u.creatureTypeID or 7
    end
    CanLootUnit = function(guid)
        for _, u in pairs(Stub.units) do
            if u.lootable and (u.guid or ("guid:" .. tostring(u.name))) == guid then return true, true end
        end
        return false, false
    end
end

-- The unit the game's soft interact picks (nil for nothing); fires PLAYER_SOFT_INTERACT_CHANGED.
-- fields: name, dead, lootable, canAttack, object, creatureTypeID.
function Stub.setSoftInteract(fields)
    Stub.units.softinteract = nil
    if fields then Stub.setUnit("softinteract", fields) end
    Stub.fire("PLAYER_SOFT_INTERACT_CHANGED")
end
function Stub.setSwimming(on) Stub.swimming = on and true or false end
function Stub.setMounted(on) Stub.mounted = on and true or false end
function Stub.setTargeting(on) Stub.targeting = on and true or false end
-- On a flight path (or off it); the game's own events follow.
function Stub.setTaxi(on)
    Stub.taxi = on and true or false
    Stub.fire(Stub.taxi and "PLAYER_CONTROL_LOST" or "PLAYER_CONTROL_GAINED")
end

-- ---------------------------------------------------------------------------------------
-- Chat strip and loot (Task 12)

-- Stub.setLoot({ { kind = "money", copper = 2340 }, { kind = "item", name = "Wool Cloth", quality = 1,
-- count = 3, quest = true, questID = 5, locked = true }, { kind = "none" } ... }) is what the open loot
-- window holds ("none" is a slot already taken).
-- Stub.setBagsFull(true) leaves no free bag slot. Stub.lootTaken lists every LootSlot call.
Stub.extend[#Stub.extend + 1] = function()
    Stub.lootSlots, Stub.lootTaken, Stub.freeBagSlots, Stub.itemQuality = {}, {}, 8, {}
    Enum = Enum or {}
    Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
    ERR_INV_FULL = "Inventory is full."
    LOOT_ITEM_SELF = "You receive loot: %s."
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    LOOT_ITEM_CREATED_SELF = "You create: %s."
    LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
    for q, c in pairs({ [0] = { 0.62, 0.62, 0.62 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }) do
        ITEM_QUALITY_COLORS[q] = { r = c[1], g = c[2], b = c[3] }
    end
    ITEM_QUALITY0_DESC, ITEM_QUALITY1_DESC, ITEM_QUALITY2_DESC = "Poor", "Common", "Uncommon"
    ITEM_QUALITY3_DESC, ITEM_QUALITY4_DESC = "Rare", "Epic"
    function Stub.setLoot(list) Stub.lootSlots = list end
    function Stub.setBagsFull(on) Stub.freeBagSlots = on and 0 or 8 end
    local function slot(i) return Stub.lootSlots[i] end
    GetNumLootItems = function() return #Stub.lootSlots end
    GetLootSlotType = function(i)
        local s = slot(i); if not s or s.kind == "none" then return Enum.LootSlotType.None end
        if s.kind == "money" then return Enum.LootSlotType.Money end
        if s.kind == "currency" then return Enum.LootSlotType.Currency end
        return Enum.LootSlotType.Item
    end
    GetLootSlotInfo = function(i)
        local s = slot(i); if not s or s.kind == "none" then return nil end
        if s.kind == "money" then return "coinicon", "money text\n", s.copper, nil, 0, false, false, nil, nil, true end
        return s.icon or ("loot" .. i), s.name, s.count or 1, s.currencyID, s.quality or 1, s.locked == true,
            s.quest == true, s.questID, s.questID ~= nil
    end
    GetLootSlotLink = function(i) local s = slot(i); return s and s.kind ~= "money" and (s.link or ("item:" .. i)) or nil end
    LootSlot = function(i) count("LootSlot"); table.insert(Stub.lootTaken, i) end
    CloseLoot = function() count("CloseLoot") end
    OpenAllBags = function() count("OpenAllBags") end
    C_Container.GetContainerNumFreeSlots = function(bag)
        if bag == 0 then return Stub.freeBagSlots, 0 end
        return 0, 0
    end
    C_Item.GetItemQualityByID = function(id) return Stub.itemQuality[id] end
    ChatFrameUtil.ReplyTell = function() count("ReplyTell") end
    ChatFrame_OpenChat = function(text) count("ChatFrame_OpenChat"); Stub.lastChatOpened = text end
    -- the game's own loot window: a frame Edit Mode manages
    -- Its OnHide closes the loot (as LootFrame.lua's does), and it loses its OnHide when reparented
    -- into a hidden frame, so a test sees any CloseLoot an add-on causes by moving it.
    local lootFrame = CreateFrame("Frame", "LootFrame", registry.UIParent)
    lootFrame.system, lootFrame.isShownExternal, lootFrame.shown = true, true, false
    lootFrame.fireHideOnReparent = true
    lootFrame:SetScript("OnHide", function() CloseLoot() end)
    -- ScrollingFlatPanel's open animation: finishing sets the window's alpha to its final value (1,
    -- the animation runs in reverse). Stub.finishAnim(group[, late]) ends it; with `late` the engine
    -- sets the alpha after the OnFinished scripts have run.
    lootFrame.ShowAnim = lootFrame:CreateAnimationGroup()
    lootFrame.ShowAnim:SetToFinalAlpha(true)
    function Stub.finishAnim(group, late)
        group.playing = false
        local function final() if group.toFinalAlpha then group:GetParent():SetAlpha(1) end end
        if not late then final() end
        group:_Fire("OnFinished")
        if late then final() end
    end
    -- the loot ScrollBox: rows come from it, and it tells whoever registered (CallbackRegistry style:
    -- func(owner, ...))
    ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame", OnReleasedFrame = "OnReleasedFrame" } }
    local box = CreateFrame("Frame", nil, lootFrame)
    box.callbacks = {}
    function box:RegisterCallback(event, fn, owner) self.callbacks[event] = { fn = fn, owner = owner } end
    lootFrame.ScrollBox = box
    -- Stub.addLootRow(): the game builds a row (a button) and announces it
    function Stub.addLootRow()
        local row = CreateFrame("Button", nil, box)
        local cb = box.callbacks.OnAcquiredFrame
        if cb then cb.fn(cb.owner, row, {}, true) end
        return row
    end
end

-- ---------------------------------------------------------------------------------------
-- Popups, taps and the death flow (Task 13)

function Frame:SetRotation(r) self.rotation = r end
function Frame:GetRotation() return self.rotation or 0 end
function Frame:GetFontString()
    self.fontStringPart = self.fontStringPart or newObject("FontString", nil, self)
    return self.fontStringPart
end

-- What a finger on `frame` touches: the topmost shown, mouse-enabled frame or button anchored over it
-- (SetAllPoints) or over one of its parents; the frame itself when nothing covers it.
function Stub.coveredBy(frame)
    local best
    for _, f in ipairs(frameList) do
        local p = f.points[1]
        if f ~= frame and f.mouse and (f.kind == "Frame" or f.kind == "Button") and p and p[1] == "ALL"
            and not f.templates:find("Secure") and f:IsVisible() then
            local over = frame
            -- the screen-wide roots are not what a finger lands on
            while over and over ~= registry.UIParent and not (ns and (over == ns.root or over == ns.moveRoot)) do
                if p[2] == over then
                    if not best or f.level >= best.level then best = f end
                    break
                end
                over = over.parentFrame
            end
        end
    end
    return best
end

-- A touch on `frame` that lasts `seconds`: the covering frame gets the press and the release; with no
-- cover the frame itself is clicked, as the game clicks a button released over it.
-- A visible secure button laid over `frame`: the finger lands on it, not on the frame under it. Over means
-- SetAllPoints(frame), or placed with points of its own over it (the stub has no layout engine, so such a button
-- names the frame it covers in its `over` field).
function Stub.secureOver(frame)
    local best
    for _, f in ipairs(frameList) do
        local p = f.points[1]
        local covers = (p and p[1] == "ALL" and p[2] == frame) or rawget(f, "over") == frame
        if f ~= frame and f.mouse and f.templates:find("Secure") and covers and f:IsVisible() then
            if not best or f.level >= best.level then best = f end
        end
    end
    return best
end

function Stub.tap(frame, seconds)
    if type(frame) == "string" then frame = assert(registry[frame], "no frame named " .. frame) end
    local target = Stub.coveredBy(frame)
    local hit = target or frame
    hit:_Fire("OnMouseDown", "LeftButton")
    if seconds and seconds > 0 then Stub.advance(seconds) end
    hit:_Fire("OnMouseUp", "LeftButton")
    if not target then Stub.click(Stub.secureOver(frame) or frame) end
    return hit
end

-- The game's static popups: StaticPopup1..4 with four buttons, the way StaticPopup_Show fills them. A test
-- fills StaticPopupDialogs; the dialog's OnClick runs the accept or cancel function and hides the popup
-- unless that function returns true.
Stub.extend[#Stub.extend + 1] = function()
    Stub.corpse, Stub.mapSize, Stub.facing = nil, { 1000, 700 }, 0
    StaticPopupDialogs = {}
    RepopMe = function() count("RepopMe") end
    RetrieveCorpse = function() count("RetrieveCorpse") end
    AcceptGroup = function() count("AcceptGroup") end
    GetPlayerFacing = function() return Stub.facing end
    C_Map.GetMapWorldSize = function() return Stub.mapSize[1], Stub.mapSize[2] end
    C_DeathInfo = { GetCorpseMapPosition = function()
        if not Stub.corpse then return nil end
        return { GetXY = function() return Stub.corpse[1], Stub.corpse[2] end }
    end }
    local ui = registry.UIParent
    local function onClick(dialog, index)
        local info = StaticPopupDialogs[dialog.which]
        local fn = index == 1 and (info.OnAccept or info.OnButton1) or index == 2 and info.OnCancel or nil
        local keepOpen = fn and fn(dialog, dialog.data)
        if not keepOpen then dialog:Hide() end
    end
    for i = 1, 4 do
        local d = CreateFrame("Frame", "StaticPopup" .. i, ui)
        d:SetFrameStrata("DIALOG")
        d:SetPoint("TOP", ui, "TOP", 0, -135)
        d.shown = false
        d.Text = d:CreateFontString("StaticPopup" .. i .. "Text")
        d.Buttons = {}
        for k = 1, 4 do
            local b = CreateFrame("Button", "StaticPopup" .. i .. "Button" .. k, d)
            b:SetID(k); b:SetSize(128, 21); b.shown = false
            b:SetScript("OnClick", function() onClick(d, k) end)
            d.Buttons[k] = b
        end
        d.ExtraButton = CreateFrame("Button", "StaticPopup" .. i .. "ExtraButton", d)
        d.ExtraButton.shown = false
        function d:GetButton(k) return self.Buttons[k] end
        function d:GetTextFontString() return self.Text end
        function d:Resize() count("PopupResize") end
        d:SetScript("OnShow", function(self)
            local info = StaticPopupDialogs[self.which]
            if info and info.OnShow then info.OnShow(self, self.data) end
        end)
    end
    -- the game fills a free dialog, then shows it (its OnShow script runs before the add-on's hooks)
    function StaticPopup_Show(which, arg1, arg2, data)
        local info = assert(StaticPopupDialogs[which], "no dialog " .. which)
        for i = 1, 4 do
            local d = registry["StaticPopup" .. i]
            if not d:IsShown() then
                d.which, d.data, d.dialogInfo = which, data, info
                d.timeleft = info.timeout or 0          -- the game sets it before it shows the popup
                d.Text:SetText((info.text or ""):format(arg1, arg2))
                for k = 1, 4 do
                    local b = d.Buttons[k]
                    b.shown = info["button" .. k] ~= nil
                    b:SetText(info["button" .. k]); b:Enable()
                end
                d:Show(); d:Resize()
                return d
            end
        end
    end
    function StaticPopup_Hide(which)
        for i = 1, 4 do
            local d = registry["StaticPopup" .. i]
            if d:IsShown() and d.which == which then d:Hide() end
        end
    end
end


-- ---------------------------------------------------------------------------------------
-- Menu, Touch settings and the touch guide (Task 14)

-- The game's own micro buttons that exist (each counts its clicks in Stub.gameClicks); the ones the dump
-- of the game's UI does not have (TalentMicroButton, WorldMapMicroButton, SocialsMicroButton,
-- GameMenuButtonOptions) are missing here too. Stub.professions is a list of
-- { name =, rank = }; Stub.className the player's class as the player reads it; Stub.talentCount the
-- unspent talent points.
Stub.extend[#Stub.extend + 1] = function()
    local ui = registry.UIParent
    Stub.className, Stub.professions, Stub.talentCount = "Mage", {}, 0
    for _, name in ipairs({ "CharacterMicroButton", "PlayerSpellsMicroButton", "ProfessionMicroButton" }) do
        local b = CreateFrame("Button", name, ui)
        b.scripts.OnClick = function() Stub.gameClicks[name] = (Stub.gameClicks[name] or 0) + 1 end
    end
    UnitClass = function() return Stub.className, Stub.playerClass or "MAGE" end
    GetRealZoneText = function() return Stub.zone end
    GetProfessions = function()
        local list = {}
        for i = 1, #Stub.professions do list[i] = i end
        return list[1], list[2], nil, nil, nil
    end
    GetProfessionInfo = function(i)
        local p = Stub.professions[i]
        if not p then return nil end
        return p.name, "profession" .. i, p.rank, 300
    end
    GetUnspentTalentPoints = function() return Stub.talentCount end
    -- The game no longer lets add-on code show or hide a UI panel in a fight (UIParentPanelManager.lua:
    -- CheckProtectedFunctionsAllowed: InCombatLockdown() and not issecure()). Insecure calls in combat do
    -- nothing and are listed in Stub.blocked; a click on a secure button runs them as secure code.
    Stub.blocked = {}
    local function panel(name, countAs)
        return function(...)
            if combat and secureDepth == 0 then table.insert(Stub.blocked, name); return end
            count(countAs or name)
        end
    end
    ShowUIPanel = panel("ShowUIPanel")
    ToggleCharacter = panel("ToggleCharacter")
    ToggleFriendsFrame = panel("ToggleFriendsFrame")
    ToggleQuestLog = panel("ToggleQuestLog")
    ToggleAllBags = panel("ToggleAllBags")
    OpenAllBags = panel("OpenAllBags")
    PlayerSpellsUtil = {
        ToggleSpellBookFrame = panel("ToggleSpellBook"),
        ToggleClassTalentOrSpecFrame = panel("ToggleTalents"),
    }
    ToggleWorldMap = panel("ToggleWorldMap", "ToggleWorldMapFn")
    OpenQuestLog = panel("OpenQuestLog")
    -- this client defines INTERFACE_CATEGORY_ID (and not GAMEPLAY_CATEGORY_ID)
    local openSettings = panel("OpenSettings")
    Settings = { INTERFACE_CATEGORY_ID = 7,
        OpenToCategory = function(id) Stub.lastCategory = id; openSettings(id) end }
    local guild = CreateFrame("Button", "GuildMicroButton", ui)
    guild.scripts.OnClick = function() Stub.gameClicks.GuildMicroButton = (Stub.gameClicks.GuildMicroButton or 0) + 1 end
    GetCVarBool = function(name) return Stub.cvars[name] == "1" end
    C_CVar = {
        GetCVar = function(name) return Stub.cvars[name] end,
        GetCVarBool = function(name) return Stub.cvars[name] == "1" end,
        SetCVar = function(name, value) count("SetCVar"); Stub.cvars[name] = tostring(value) end,
    }
end

-- ---------------------------------------------------------------------------------------
-- Task 15: the add-on profiler, the add-on list, the performance and pause tests

-- Stub.profiler = { recent =, peak = } answers C_AddOnProfiler.GetAddOnMetric (milliseconds); set it to nil for a
-- client without the profiler. Stub.enabledAddOns lists the names C_AddOns.EnableAddOn was asked for.
Stub.extend[#Stub.extend + 1] = function()
    Stub.profiler = { recent = 0.12, peak = 0.8 }
    Stub.enabledAddOns = {}
    -- what a secure button last did, forgotten between tests so "nothing was used or targeted" can be asserted
    Stub.lastItemUsed, Stub.lastTargeted, Stub.lastMacro, Stub.lastUsedItem = nil, nil, nil, nil
    Enum = Enum or {}
    Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2,
        LastTime = 3, PeakTime = 4 }
    C_AddOnProfiler = {
        IsEnabled = function() return Stub.profiler ~= nil end,
        GetAddOnMetric = function(name, metric)
            if not Stub.profiler then error("no profiler") end
            if metric == Enum.AddOnProfilerMetric.PeakTime then return Stub.profiler.peak end
            return Stub.profiler.recent
        end,
    }
    C_AddOns = C_AddOns or {}
    C_AddOns.EnableAddOn = function(name) table.insert(Stub.enabledAddOns, name) end
    C_AddOns.DisableAddOn = function() count("DisableAddOn") end
end

-- ---------------------------------------------------------------------------------------
-- The game's window registries (ruling A30, Signal.lua), as /tmp/wowui has them:
--   UIPanelWindows: Blizzard_UIParentPanelManager/Mainline/UIPanelWindows.lua (a few of its names) and
--     RegisterUIPanel (Shared/UIParentPanelManager.lua:92), which adds a name once;
--   UIChildWindows and UISpecialFrames: Shared/UIParentPanelManager.lua:11 and :21 (names);
--   ShowUIPanel / HideUIPanel (:871, :905): nothing for a missing or already shown (hidden) frame, nothing for add-on
--     code in a fight, else the frame shows (hides);
--   CloseSpecialWindows (:1106), CloseWindows (:1134), CloseAllWindows (:1175, closes the bags first);
--   the bags: Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml: ContainerFrame1..7 (parentArray ContainerFrames of
--     ContainerFrameContainer, :227-:304) and ContainerFrameCombinedBags (:313), all hidden.
-- Stub.calls.ShowUIPanel still counts every call (other tests assert none are made).
Stub.extend[#Stub.extend + 1] = function()
    local ui = registry.UIParent
    local function hidden(name, parent)
        local f = CreateFrame("Frame", name, parent or ui)
        f.shown = false
        return f
    end
    hidden("GameMenuFrame"); hidden("CharacterFrame"); hidden("OpenMailFrame")
    hidden("ItemRefTooltip"); hidden("ColorPickerFrame")
    UIPanelWindows = {
        GameMenuFrame = { area = "center", pushable = 0, whileDead = 1 },
        CharacterFrame = { area = "left", pushable = 3, whileDead = 1 },
        LootFrame = { area = "left", pushable = 0 },
        ProfessionsBookFrame = { area = "left", pushable = 1, whileDead = 1 },  -- its add-on is not loaded yet
    }
    UIChildWindows = { "OpenMailFrame" }
    UISpecialFrames = { "ItemRefTooltip", "ColorPickerFrame", "FloatingPetBattleAbilityTooltip" }
    RegisterUIPanel = function(frame, attributes)
        local name = frame:GetName()
        if not UIPanelWindows[name] then UIPanelWindows[name] = attributes end
    end
    local function allowed() return not (combat and secureDepth == 0) end
    ShowUIPanel = function(frame)
        count("ShowUIPanel")
        if not frame or frame:IsShown() then return end
        if not allowed() then table.insert(Stub.blocked, "ShowUIPanel"); return end
        frame:Show()
    end
    HideUIPanel = function(frame)
        count("HideUIPanel")
        if not frame or not frame:IsShown() then return end
        if not allowed() then table.insert(Stub.blocked, "HideUIPanel"); return end
        frame:Hide()
    end
    CloseSpecialWindows = function()
        local found
        for _, name in pairs(UISpecialFrames) do
            local f = _G[name]
            if f and f:IsShown() then f:Hide(); found = 1 end
        end
        return found
    end
    CloseWindows = function()
        local found
        for name in pairs(UIPanelWindows) do
            local f = _G[name]
            if type(f) == "table" and f.IsShown and f:IsShown() then f:Hide(); found = true end
        end
        return CloseSpecialWindows() or found
    end
    local bags = hidden("ContainerFrameContainer")
    bags.shown = true                       -- setAllPoints on UIParent, always shown; its bags start hidden
    bags.ContainerFrames = {}
    for i = 1, 7 do bags.ContainerFrames[i] = hidden("ContainerFrame" .. i, bags) end
    hidden("ContainerFrameCombinedBags")
    CloseAllBags = function()
        local closed = false
        for _, f in ipairs(bags.ContainerFrames) do if f:IsShown() then f:Hide(); closed = true end end
        if registry.ContainerFrameCombinedBags:IsShown() then registry.ContainerFrameCombinedBags:Hide(); closed = true end
        return closed
    end
    CloseAllWindows = function()
        local bagsVisible = CloseAllBags()
        return CloseWindows() or bagsVisible
    end
end

-- ---------------------------------------------------------------------------------------
-- Targeting (world taps: soft targeting and name plates)

-- Every SetCVar made while the game's combat lockdown is up lands in Stub.cvarInCombat (the game refuses some, e.g.
-- the name plate ones, in a fight; TouchPlay must not even try). Bitfield CVars (nameplateStackingTypes) are kept
-- as a string of "0"/"1", index i at character i + 1 (the game packs them differently; only the API is modelled).
Stub.extend[#Stub.extend + 1] = function()
    Stub.cvarInCombat = {}
    local function guarded(set)
        return function(name, value)
            if combat then table.insert(Stub.cvarInCombat, tostring(name)) end
            return set(name, value)
        end
    end
    SetCVar = guarded(SetCVar)
    C_CVar.SetCVar = guarded(C_CVar.SetCVar)
    GetCVarBitfield = function(name, index)
        local v = Stub.cvars[name]
        return v ~= nil and v:sub(index + 1, index + 1) == "1"
    end
    SetCVarBitfield = function(name, index, on)
        count("SetCVar")
        if combat then table.insert(Stub.cvarInCombat, tostring(name)) end
        local v = Stub.cvars[name] or ""
        while #v < index + 1 do v = v .. "0" end
        Stub.cvars[name] = v:sub(1, index) .. (on and "1" or "0") .. v:sub(index + 2)
    end
    Enum = Enum or {}
    Enum.NamePlateStackType = { None = 0, Enemy = 1, Friendly = 2 }
end

-- The game's own values for the CVars Targeting.lua looks at (a fresh character on this client, as far as the source
-- shows: SoftTargetEnemy 1 = gamepad only, Combat.lua; Interact Key Icons "default" = only SoftTargetIconInteract,
-- Accessibility.lua). Tests call it; the plain stub knows none of them.
function Stub.targetingCVars()
    local c = Stub.cvars
    c.SoftTargetEnemy, c.SoftTargetIconEnemy = "1", "0"
    c.SoftTargetIconInteract, c.SoftTargetIconGameObject = "1", "0"
    c.nameplateShowEnemies, c.nameplateShowAll, c.nameplateSize = "1", "0", "1"
    c.nameplateStackingTypes = "000"
    c.autoSelfCast, c.SoftTargetFriend, c.SoftTargetForce, c.enableMouseoverCast = "1", "0", "0", "0"
end

print_real = print_real or print
Stub.reset()

-- ---------------------------------------------------------------------------------------
-- Sharp screen (Sharp.lua, ruling A39): the game's physical drawable size and render scale range

-- The plain stub has none of these (a client without them: Sharp.lua changes nothing). Stub.sharpScreen gives them.
Stub.extend[#Stub.extend + 1] = function()
    Stub.physicalW, Stub.physicalH = nil, nil
    GetPhysicalScreenSize, GetMinRenderScale, GetMaxRenderScale = nil, nil, nil
    RESAMPLE_QUALITY_FSR = nil
end

-- opts: width, height (the physical drawable, px; default 2420 x 1668 = backing scale 2.0 on the iPad Pro 11 M5),
-- min, max (GetMinRenderScale/GetMaxRenderScale; left out = the client has no such function), fsr (false = this client's
-- Graphics page has no FidelityFX option), and the game's own values RenderScale, ResampleQuality, ResampleSharpness
-- (false = not a CVar in this client). Defaults are a fresh install: RenderScale 1, Bilinear, sharpness 0.5.
function Stub.sharpScreen(opts)
    opts = opts or {}
    Stub.physicalW, Stub.physicalH = opts.width or 2420, opts.height or 1668
    GetPhysicalScreenSize = function() return Stub.physicalW, Stub.physicalH end
    if opts.min then GetMinRenderScale = function() return opts.min end end
    if opts.max then GetMaxRenderScale = function() return opts.max end end
    if opts.fsr ~= false then RESAMPLE_QUALITY_FSR = "FidelityFX Super Resolution 1.0" end
    local c = Stub.cvars
    local function put(name, default)
        if opts[name] == false then c[name] = nil else c[name] = opts[name] or default end
    end
    put("RenderScale", "1")
    put("ResampleQuality", "1")
    put("ResampleSharpness", "0.5")
    -- the game's UI scale (Graphics.lua:910-939): "Use UI Scale" off and the slider at 1 on a fresh install
    put("useUiScale", "0")
    put("uiscale", "1")
    if opts.ui then
        -- the game's UI scale model (ruling A39b): every SetCVar of the two moves UIParent as the game does
        local set = SetCVar
        SetCVar = function(name, value)
            set(name, value)
            if name == "useUiScale" or name == "uiscale" then Stub.uiScaleNow() end
        end
        Stub.uiScaleNow()
    end
end

-- UIParent as the game sizes it (the cause of ruling A39b): its scale is the uiscale CVar while useUiScale is 1, else
-- the game's own default, pixel for pixel: 768 / the physical height (PixelUtil.lua:3-6, one UI unit at scale 1 is
-- physical height / 768 pixels; GetDefaultScale). UIParent is 768 / scale units tall at any size, so a game window of
-- fixed units covers (its height x scale / 768) of the screen: at 626 px tall 1.2268, at 1668 px 0.4604 (2.67x smaller).
-- The game fires UI_SCALE_CHANGED afterwards; tests fire it when they want the add-on to hear it.
function Stub.uiScaleNow()
    local ui = registry.UIParent
    local c = Stub.cvars
    local s = (c.useUiScale == "1" and tonumber(c.uiscale)) or (768 / (Stub.physicalH or 768))
    ui.scale = s
    ui.height = 768 / s
    ui.width = ui.height * (Stub.physicalW or 1024) / (Stub.physicalH or 768)
    return s
end

-- The share of the screen's height a game window `units` tall covers now (it lives in UIParent's units).
function Stub.screenShare(units) return units / registry.UIParent.height end
