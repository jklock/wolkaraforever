# AppKit on UIKit

`platform/translation/AppKit/` implements the AppKit surface a Mac application uses
for its application object, event loop, windows, views, screens, cursors, text input
and nib loading. It is the largest adapter and the only one on the per-frame path of
a running game together with Metal.

Files, in dependency order: `AppKit.h` (the surface), `AppKit.m` (everything below),
`Screens.m`, `Images.m`, `Nibs.m`, `NibArchive.m`, `TextInput.m`, `EventMonitors.h`,
`WindowFullscreen.m`, `TouchControls.m`, `TouchTrackpad.c`.

The central design decision, stated once and assumed below: **a guest window is a
`UIWindow` with one `AKHostView`**, and a guest `NSView` tree is a `CALayer` tree
hanging off that view's layer. AppKit's view/layer duality is reproduced by making
every `NSView` own its `CALayer` and placing sublayers in the same order as
sublayers would be.

---

## `AppKit.m`, lines 1–29: `NSResponder`

| Line | Explanation |
| --- | --- |
| 1–8 | Imports; `NSApp` is the single global the guest's `NSApplication` is published to (line 10). |
| 10 | `NSApplication *NSApp;` — a real global, because guests read it directly (`NSApp.terminate`) and Wine's driver does too. Setting it early (in `-init`, line 880) means a subclass's `init` sees it already published. |

**`-interpretKeyEvents:` (11–13).** AppKit's contract is that key-down events are
translated to text via the key bindings. There is no key-binding system here, so each
event that carries characters is passed straight to the text interpreter
(`AKInterpretTextKey`, `TextInput.m`) with its characters, key code and modifiers.
Key-up events are ignored: text is inserted on press only.

**`-insertText:` (14).** Hands the text to the next responder. The default AppKit
implementation does the same, and a view that wants text overrides it.

**`-doCommandBySelector:` (15–18).** AppKit's responder-chain protocol for commands
(Return, Tab, arrow keys) that are not text. If this responder implements the selector,
it is invoked with a nil argument through `methodForSelector` — the same shape AppKit
uses, so a guest's `-insertNewline:` override works. Otherwise the command travels on
to `nextResponder`.

**`-acceptsFirstResponder` returns `NO` (19); `-becomeFirstResponder` and
`-resignFirstResponder` return `YES` (20–21).** The two returning YES are the default
in AppKit; `acceptsFirstResponder` NO is also AppKit's default for `NSResponder` (a
plain view must opt in). These matter because `-makeFirstResponder:` (line 786) refuses
a responder that does not accept the role.

**`PASS(sel)` and its expansions (22–25).** The macro synthesizes forwarding methods
that hand the event to the next responder: `keyDown:`, `keyUp:`, `flagsChanged:`, all
three mouse-button families, `mouseMoved:`, `mouseDragged:` and `scrollWheel:`. These
are what make the responder chain behave like AppKit's when nobody in the chain wants
an event. Thirteen methods from one line each.

## Lines 27–40: local event monitors are opt-in

`eventMonitorsEnabled()` reads the launch argument `--appkit-event-monitors` once
(`dispatch_once`) and caches the answer. Off by default because a local monitor
observes events *before* window dispatch and may consume them; Wine's Mac driver
installs one, so it must be honoured when asked for, but turning it on changes delivery
semantics for every application, hence the gate. The `AKLog` on the first call records
which mode this session is in, because "my monitor never fired" is otherwise
indistinguishable from "monitors are off".

## Lines 41–43: `mouseScreenLocation`

A file-static point in **screen** coordinates (bottom-left origin, as AppKit uses). It
exists because `+[NSEvent mouseLocation]` must answer even before any window exists or
after the pointer leaves every window: it is the last location a mouse event left.
`+mouseLocation` (line 45) returns it directly.

## Lines 44–82: `NSEvent`

`NSEvent` is a class extension with one ivar, `AKQuartzEvent *_quartz` (line 44), which
caches the Quartz-side representation.

**`-CGEvent` (48–71).** Builds, once per event and under `@synchronized`, a synthetic
`CGEvent`-shaped object. Each field is explained because a guest reads them by number:

- `type` (53): AppKit's and Quartz's event-type numbers agree for the events this
  adapter produces, so the value is copied rather than translated.
- `location` (54–57): the event's location converted to **global display
  coordinates**, whose origin is top-left; hence `screenHeight - y`. This is the one
  place the two coordinate conventions of macOS meet, and getting it wrong puts every
  click in the wrong place for a guest that reads `CGEvent` position.
- `timestamp` (58): AppKit's seconds become nanoseconds, as Quartz uses.
- `flags` (59): modifier flags, same bit layout in both.
- Fields set by number (60–68): `1` click state, `3` button number, `4`/`5` mouse
  deltas, `8` auto-repeat, `9` key code, `10` keyboard type fixed at 40 (ANSI, the value
  `LMGetKbdType` returns for a US layout), `11`/`12` scroll deltas, `40` the target
  pid — the set Wine's driver reads. Each carries a comment naming the Quartz constant
  so the numbers never have to be looked up again.
- The cached object is returned bridged, not retained, because the ivar owns it.

**`-description` (72).** Diagnostic only: type, location and key code, so a log line
about an event is readable.

**`+addLocalMonitorForEventsMatchingMask:handler:` (74–76).** Returns a monitor only
when `--appkit-event-monitors` is set; otherwise returns nil, which is indistinguishable
to the guest from a monitor that can never fire but costs nothing.

**`+addGlobalMonitorForEventsMatchingMask:handler:` (78).** Always nil: a global monitor
observes *other applications'* events, and on iOS the app receives none. Returning nil
is the honest answer rather than a monitor that silently never fires.

**`+removeMonitor:` (79).** Forwards to the monitor table (`EventMonitors.h`), which is
safe to call with an unknown object.

## Lines 84–92: `NSTrackingArea`

A value object: rectangle, options, owner, user-info copy. AppKit uses tracking areas to
tell a view when the mouse enters, exits or moves within a region. Here they are stored
and queried by the host view when it computes hover delivery; `NSView` keeps a list
(lines 111, 187–189). No behaviour lives in the class itself, which matches AppKit.

## Lines 94–230: `NSView`

The ivars (95) are the view's own state: subviews, cursor rectangles, tracking areas, a
**weak** superview (so a parent does not keep a detached child alive, and so the
retain-cycle in a parent/child pair cannot form), plus everything declared in
`AppKit.h` (`_frame`, `_bounds`, `_layer`, `_window`, flags).

- `-init` (96) redirects to `-initWithFrame:` with a zero rectangle, as AppKit does, so
  a guest that calls plain `init` still gets a fully initialized view.
- `-initWithFrame:` (97–100): stores frame, sets bounds origin to zero and size to the
  frame's (AppKit's default: a view's bounds are its frame moved to the origin), creates
  the three mutable collections, and defaults `autoresizesSubviews` to YES, which is
  AppKit's default and the reason `-setFrame:` calls `-resizeSubviewsWithOldSize:`.
- `-makeBackingLayer` (101) returns a plain `CALayer`. A guest's subclass may override
  it to return a `CAMetalLayer`; that override is how a Metal game gets its surface.
- `-setWantsLayer:` (102–105) creates the backing layer on first request and remembers
  the flag. Idempotent on purpose: guests set it repeatedly.
- `-setLayer:` (106–112) adopts a caller-supplied layer, sets `anchorPoint` to zero
  (so the layer's position is its origin, which is what AppKit's layer placement means
  and what Wine's driver assumes), sizes it to the frame, clears the delegate (AppKit
  forbids a guest becoming its own layer's delegate by accident) and matches visibility.
- `-setHidden:` (113) keeps the layer's hidden flag in step; a hidden guest view must
  not paint.
- `-setFrame:` (114–122): updates frame and bounds size, then applies the same rectangle
  to the layer **inside a `CATransaction` with actions disabled**, so the change is not
  animated — AppKit's `setFrame:` is immediate, and without this every guest resize would
  animate over 0.25 s. Then, if the size actually changed, resizes subviews.
- `-resizeSubviewsWithOldSize:` (123–147) implements AppKit's autoresizing masks. For
  each axis it takes the 3-bit mask for that axis, splits the *old* axis into three
  segments (before the subview, the subview, after it), sums the segments whose bit is
  set, and distributes the axis delta across them proportionally to segment size — or
  equally if all participating segments are zero. It then moves and grows the subview and
  clamps its length at zero. This is the whole of AppKit's springs-and-struts algorithm
  in twenty lines, and it must match AppKit because a guest's layout depends on it.
- `-setFrameSize:` (148) is the frame with a new size, so all the above applies.
- `-superview` (149) returns the weak back-pointer.
- `-subviews` (150) returns a **copy**: AppKit returns an immutable snapshot, and a guest
  iterating while removing must not crash.
- `-addSubview:` (151–153) is AppKit's convenience meaning "insert at the top".
- `-addSubview:positioned:relativeTo:` (154–176): the order of operations matters.
  (a) Refuse nil and refuse a view that is an ancestor of this one — adding an ancestor
  as a child would create a cycle the layer tree cannot represent. (b) Detach it from
  its old parent. (c) Compute the insertion index: `ordering < 0` means *below*
  `relative`, otherwise above; with no `relative`, below means index 0 and above means
  the end. (d) Insert into `_subviews`, set `_superview` (via the ivar, since the
  property is weak), and make the child's hi`nextResponder`/`window` follow the parent.
  (e) Ensure both layers exist, then insert the child's layer on the correct side of
  `relative`'s layer so view order and layer order agree.
- `-removeFromSuperview` (177–181) removes the layer, then the array entry, then clears
  the back-pointer. The layer is removed first so a guest that observes its own removal
  never sees a layer still parented.
- `-setWindow:` (182–186) propagates the window down the tree and calls
  `-viewDidMoveToWindow` at every level, which is AppKit's contract.
- `-viewDidMoveToWindow` (187) is the override point; empty by default, as in AppKit.
- Tracking areas (188–189): return a copy, add without duplicates, remove by identity.
  `-updateTrackingAreas` (190) is the override point, called by the host when the view
  geometry changes.
- `-wantsUpdateLayer` (191) returns NO and `-updateLayer` (192) is empty: AppKit's
  "layer-hosting" mode is not offered; a view redraws through `-display`.
- `-setNeedsDisplay:` (193–201): if cleared, clear the flag; if already set, do nothing;
  otherwise set it and schedule one `-displayIfNeeded` on the **main queue**. That is
  deliberately *one pass per run-loop turn however often the guest asks*: a guest that
  dirties itself repeatedly per frame would otherwise repaint per call. This is the only
  place a guest's drawing request is coalesced.
- `-setNeedsDisplayInRect:` (202) ignores the rectangle and marks the whole view: the
  adapter has no damage tracking, and marking everything is correct, just coarser.
- `-displayIfNeeded` (203) displays if the flag is set; `-display` (204–211) clears the
  flag and, only when `wantsUpdateLayer`, runs `-updateLayer` inside a disabled-action
  transaction. A plain view therefore does nothing on display, which is right: its
  content comes from its layer, which the guest draws into itself (a Metal layer) or
  from the image the guest sets.
- Cursor rectangles (212–217): `discard`/`reset` clear the list (AppKit's reset pattern is
  "discard, then let the view add"); `addCursorRect:cursor:` stores an entry. The lookup
  `ak_cursorAtPoint:` walks the list **in reverse**, so the most recently added rectangle
  wins, which is the AppKit rule for overlapping cursor rects.
- Backing conversions (218–223): to/from backing multiplies or divides by the window's
  `backingScaleFactor`, falling back to the screen's native scale when there is no
  window yet. The rect versions convert the origin and the size separately because a
  scale applies to both (they are not independent, but converting them as two sizes is
  what AppKit's own implementation is defined to do).
- `ak_originInWindow` (224) sums frame origins up the parent chain: the view's origin in
  window coordinates, without using the layer tree (which may not exist).
- `-convertPoint:fromView:` / `toView:` (225–232) use those origins. `nil` means window
  coordinates. The arithmetic is origin subtraction in one direction and addition in the
  other; this works only because every view's bounds origin is zero, which
  `-initWithFrame:` guarantees.

## Lines 234–253: key-code and modifier translation

`AKKeyCode` maps **USB HID usages** (what `UIKey` reports) to **macOS virtual key
codes** (`kVK_*`, what a Mac application expects). Three lookup tables cover letters,
digits and function keys, because their HID usages are contiguous; a `switch` covers the
punctuation, navigation and modifier keys, which are not. `0xFF` means unmapped and the
caller passes that through, so a guest sees an unknown key rather than a wrong one. The
letters table is written as 26 explicit numbers rather than a formula because the HID
order (a,b,c,…) and the `kVK_` order (a=0, s=1, d=2, …) are different permutations.

`AKMods` maps UIKit modifier bits to AppKit flags, one line each; there is no
translation for Function or numeric-pad bits because AppKit has none.

`AKModifierKeys` (258–262) is the eight-entry table that distinguishes **left from
right** modifiers. AppKit reports each physical key as a device-dependent bit in
addition to the generic flag (`NX_DEVICELCTLKEYMASK` etc.), and Wine's driver tells the
keys apart by those bits; without them a guest cannot distinguish ctrl from rctrl.

`AKHeldFlags` (263–268) turns the accumulated device bits into the flags AppKit would
report: caps lock passes through, and each held key contributes both its generic flag
and its side bit.

`AKModifiersAfterKey` (269–274) applies one key press or release to the held set: a
modifier sets or clears its own bit, then `AKHeldFlags` derives the flags. This is used
when the guest's own press/release of a modifier is the authority.

`AKModifiersReconciled` (275–287) is the opposite: UIKit's *reported* flags are the
authority, and the held set is corrected. Caps lock is copied from the report; then for
each physical pair, if the report no longer shows the generic flag, both side bits are
cleared; if it does and neither side is set, the **left** side is assumed. The asymmetry
exists because UIKit reports which modifiers are down but not which physical key; the
left assumption is what makes ctrl+click work when the guest never saw a flags-changed
event for the ctrl key itself.

## Lines 289–296: `AKHostView` declaration

The host view is a `UIView` that receives everything UIKit gives a first responder — key
presses, touches, hover, pointer regions — and turns each into an `NSEvent` posted to
`NSApplication`'s queue. It is also the pointer interaction delegate and the touch-controls
delegate. Its ivars (291–299) are all state that has to survive between events:
last pointer location `_last` (in **top-left** UIKit coordinates), `_mods` (held
modifiers), the three button-down flags, `_pointerInside`, the software-cursor flag and
image, the pointer interaction and its style, delivery counters, the last report time,
the cursor hot spot, the touch-controls view and its cursor state, the double-click
tracker (time, point, button, count), and the viewport size used to detect resizes.

## Lines 300–330: host view initialisation

`-initWithFrame:` (300–330) does, in order:

- `multipleTouchEnabled = NO` (302): one pointer. A second finger must not become a
  second mouse button.
- `_last` is set to the **centre** of the view (305–306). The comment states why: a game
  that polls the pointer position before any event would otherwise hover whatever sits
  in the corner. A Mac's pointer starts somewhere mid-screen, so the centre is the
  closer lie.
- The software-cursor choice (307–309) reads `--software-cursor` and logs which
  presentation is in use, because "the cursor looks wrong" is otherwise ambiguous
  between the two systems.
- `_cursorView` (310–311) is an image view for the software cursor, with interaction
  disabled (it must never receive touches), `zPosition` 100000 (above any guest layer),
  hidden until needed, added to the view.
- The `UIPointerInteraction` (312–313) is UIKit's hardware-pointer machinery; adding it
  is what makes an iPad's trackpad pointer produce regions and styles for this view.
- Six notifications (314–319) are observed: cursor change (software cursor image),
  capture change (pointer lock), anchor change (the game moved the virtual pointer),
  mouse connect, mouse disconnect (treated as a capture change, because losing the mouse
  must release the lock) and pointer-lock state change. Each is a separate event source
  because each arrives at a different time and means something different.
- Existing mice are installed (320), and a hover recognizer is added (321). The
  recognizer is needed because UIKit reports hover on the *view* even when no pointer
  interaction region is active.
- Touch controls are installed only when enabled (322–329), which is on iPhone and off
  on iPad — they would cover part of the game.

`-installTouchControls` (331–344) creates the controls, disables autoresizing
translation, adds them, and pins them with four constraints: 96×44, to the safe-area
trailing edge with 12 points of margin, and 8 points above the keyboard layout guide.
Those numbers are the controls' design, not a layout accident.

## Lines 345–400: host view geometry, cursor and touch cursor

- `-canBecomeFirstResponder` (345) returns YES: this is what makes key input arrive.
- `-setNsWindow:` (346–350) records the guest window and seeds the pointer at the
  current location, converted to the window's bottom-left convention, and publishes the
  screen location. Doing it here means a guest that asks for the mouse position during
  `applicationDidFinishLaunching` gets a sensible answer.
- `-layoutSubviews` (351–365) is the resize path: tell the guest window the new bounds,
  initialise the touch cursor once, and if the size changed, cancel touches (a
  coordinate change must not be delivered as a drag), clamp the pointer into the new
  bounds, recompute window and screen locations, and reposition the cursor. Each of
  those is a separate failure if omitted; this is why the method is longer than a
  one-line forwarding.
- `-touchTrackpadChanged:` (366–374) enables multi-touch, seeds the pointer at the centre
  the first time it is enabled and the view has a size, and marks the touch cursor
  active. The guard on a non-zero size is what prevents a NaN pointer on a view that has
  not been laid out yet.
- `-activateTouchCursor` (375–378) turns the touch cursor on and marks the pointer inside
  the view; called from every touch-driven path so that any touch re-establishes the
  cursor.
- `-touchMoveBy:` (379–391) rejects non-finite deltas (a divided-by-zero gesture can
  produce them), then splits into two behaviours: when the mouse is **captured**, the
  delta is posted as relative motion through the same confined path a physical mouse uses
  (`y` negated because UIKit's y grows downward and AppKit's upward), and the cursor is
  redrawn; when not captured, it moves the absolute pointer within the view's bounds and
  posts the matching drag/move event for the button currently held. The choice of event
  type is why the three pressed flags exist.
- `-touchScrollBy:` (392–400) builds a scroll-wheel event with both the legacy and the
  modern delta fields set to the same value (guests read either), stamps it with the
  current time, and posts it.

## Lines 401–414: touch buttons and text

- `-touchButton:pressed:` (401–414) implements click counting: a press within 0.5 s and
  within 4 points of the previous press on the same button is the second click, otherwise
  the count restarts at one. AppKit's own double-click threshold is a system setting;
  these are the values used here, and they are constants rather than settings because a
  guest cannot change them either. The event type is chosen from the button number
  (2 = other/middle, 1 = right, 0 = left) and the press flag.
- `-postTextKey:characters:unmodified:modifiers:` (415–424) posts a **pair**:
  key-down then key-up, each with characters and the characters without modifiers.
  Two events because a guest that inserts text on key-down and matches releases by key
  code would otherwise leave a key stuck.
- `-touchInsertText:` (425–429) enumerates the characters through `AKEnumerateTextKeys`
  (which maps a character to a key code and the modifiers needed to type it — Shift for a
  capital, Option for an accented character on the US layout) and posts each.
- `-touchSpecialKey:characters:` (430–432) posts a key with no modifiers and with the
  same string for both character fields, which is right for Return, Tab and Escape.

## Lines 433–520: pointer plumbing

- `-usesRelativeMouse` (434) is the single predicate for "this is a captured game
  pointer": captured **and** a physical mouse exists. Both conditions, because capture
  without a mouse means the touch cursor is the pointer.
- `-captureChanged:` (435–441) hops to the main thread if needed (the notification can
  arrive on another), asks the root view controller to re-evaluate its pointer-lock
  preference (`setNeedsUpdateOfPrefersPointerLocked`, which is what makes
  `-prefersPointerLocked` be consulted again), and logs the state with the raw device
  count.
- `-lockChanged:` (442) logs the actual lock state from the window scene, which is the
  only authoritative answer to whether iPadOS accepted the request.
- `-anchorChanged:` (443–451) is how the game moves the virtual pointer: the
  notification carries a **top-left** screen point; it is converted to bottom-left for
  the window, stored, published as the screen location, and mirrored into `_last`
  (top-left view coordinates). Three representations of one position, each needed by a
  different consumer, is the reason this looks repetitive.
- `-mouseConnected:` (452) installs the new device and re-evaluates capture.
- `-installMouse:` (453–478) wires a `GCMouse` to the guest: the handler queue is the
  main queue (so every handler runs where the guest expects), then relative motion is
  posted only when this view is key **and** the pointer is captured (an uncaptured iPad
  pointer already arrives as hover, and posting both would double-count), the two buttons
  go through `rawButton:`, and the scroll value is posted with both signs negated —
  `GCMouse` reports the device's own direction while AppKit's deltas follow natural
  scrolling, which is the iPad's default.
- `-postRelativeMouseX:y:` (479–500) is the confined relative path. It moves the stored
  window location by the delta, clamps it into the mouse confinement rectangle (or the
  view's bounds when there is none), publishes the screen location, mirrors `_last`, and
  posts the event with the right type for the held button and both the absolute location
  and the deltas. AppKit's captured-mouse contract is that a guest gets deltas at the
  edges and absolute positions inside; this is that contract.
- `-rawButton:pressed:` (501–507) ignores a repeat, ignores a press when relative mouse
  is not in use (that path comes from hover/touch instead), and posts the matching
  down/up.
- `-postMouse:at:button:` (509–511) and `-postMouse:at:button:clicks:` (512–534) are the
  absolute path and do five things: maintain the three pressed flags, stamp the event,
  convert the point to AppKit's bottom-left origin, update the stored locations, compute
  deltas from `_last`, resolve the cursor rectangle under the new position and set that
  cursor if it changed, reposition the software cursor, and post. The delta computation
  is why `_last` is updated here rather than by the caller.

## Lines 535–580: software cursor and pointer style

- `-cursorChanged:` (535–562) rebuilds the cursor presentation: it takes the current
  `NSCursor`'s image (or a system arrow if there is none), and, when the native iPad
  pointer is in use, builds a `UIPointerStyle` whose shape is the cursor image at its hot
  spot (`AKCreateCursorPath`), constrained on neither axis. A path-shaped pointer is how
  iPadOS can show an arbitrary cursor image. It then sizes the image view, records the
  hot spot (zero for the fallback arrow, whose tip is its corner), positions it, and
  invalidates the interaction so UIKit asks for a new style.
- `-positionCursor` (563–578) sets the image view's frame from the stored position and
  hot spot inside a disabled-action transaction, computes a three-bit **reason** word
  (pointer outside, game hid the cursor, no image) for logging, sets hidden from
  (software cursor or touch cursor) and no reasons, logs only when the reason word
  changes, commits, and then calls `CATransaction flush`. The flush is the interesting
  line: the desktop client owns a nested run loop, so UIKit's outer-loop commit can be
  deferred until pointer tracking ends; publishing each update immediately is what keeps
  the cursor from lagging a frame behind.
- `-pointerInteraction:styleForRegion:` (579–584) answers hidden when the game hid the
  cursor or the software cursor is drawing it, otherwise the game's path style or the
  system arrow.
- `-pointerInteraction:regionForRequest:defaultRegion:` (585–596) is UIKit's per-move
  callback. It counts the update, reconciles modifiers from the request (a pointer move
  is often the first notice that a modifier was released), feeds the request's location
  into the same hover path the recognizer uses — deliberately duplicated, because the
  hover recognizer's recognition can be deferred by the client's nested loop — and
  returns the default region.

## Lines 597–640: hover and touches

- `-moveHoverTo:inside:` (597–612) is the single absolute-pointer sink: it does nothing
  while relative mouse is in use, clears the touch cursor (a real pointer movement
  supersedes it), and posts a move or drag only if something changed — a hover that
  repeats the same point must not generate an event per callback. Every two seconds it
  logs the two delivery counters and resets them; the comment records that these are
  counts only, no coordinates, so the log can be shared.
- `-hover:` (613–625) counts the callback, and ignores every state except began and
  changed: an ended or cancelled hover (iPadOS hides an idle pointer) reports its
  location as the view's corner, which would teleport the pointer. The pointer therefore
  stays where it last was, as on a Mac.
- `-dealloc` (626) removes the notification observers.
- `AKIsRight` (627) reads the secondary button mask from the `UIEvent`.
- `-handleTrackpadTouches:event:` (628–635) routes direct touches to the touch controls
  when the trackpad overlay is enabled, and reports whether it did.
- `-touchesBegan:` (636–641): touch controls first; then ignore a press when that button
  is already down (UIKit can deliver a second began for the same finger after a cancel);
  record the location; reconcile modifiers; post the down for the button the event
  reports.
- `-touchesMoved:` (642–649): touch controls first; ignore while relative mouse is in
  use; ignore a move to the same point; otherwise post a drag with the held button.
- `-touchesEnded:` (650–655): touch controls first; ignore if no button is down; post the
  up at the touch location, or at the stored location when the pointer is captured (the
  touch position is meaningless once the pointer is locked).
- `-touchesCancelled:` (656) ends the touches: a cancel must release the button or the
  guest believes it is still held.

## Lines 658–676: modifier reconciliation and key posting

- `-reconcileModifiers:` (658–674) compares UIKit's reported flags with the held set; if
  nothing changed it returns. If a modifier was **released** it posts a
  `flagsChanged` event with the new state — necessary because UIKit can report a key's
  release while still reporting its modifier as held, and a guest tracking modifiers
  would otherwise never see the release.
- `-postKeys:down:` (675–695): for each press with a key, build an event; map the key
  code; decide whether it is a modifier by HID usage range (0xE0–0xE7); for a modifier,
  apply the press to the held bits directly, otherwise reconcile from UIKit's flags;
  stamp the resulting flags; choose `flagsChanged` for modifiers and for Caps Lock
  (0x39) and `keyDown`/`keyUp` otherwise; copy both character fields; log the first eight
  events only; post.
- `-pressesBegan:`/`-pressesEnded:`/`-pressesCancelled:` (696–698) forward to
  `-postKeys:down:`; a cancelled press is a release, never a press.

## Lines 700–712: `AKHostViewController`

- `-loadView` (704) is the only place the host view is created, with the screen's bounds
  and a black background.
- `-prefersStatusBarHidden` (705) YES; `-preferredScreenEdgesDeferringSystemGestures`
  (707–709) returns every edge, which asks iPadOS to require a second deliberate swipe
  before leaving a game — a preference, not a device-wide lock, as the comment says;
  `-prefersHomeIndicatorAutoHidden` (710) YES; `-prefersPointerLocked` (711) mirrors
  `-usesRelativeMouse`; `-viewDidAppear:` (712) makes the view first responder, which is
  what starts keyboard delivery.

## Lines 714–745: the launcher-covering experiment

`coversLauncher()` (722–730) reads `--guest-window-covers-launcher` once and creates two
**weak** hash tables: guest windows and the windows it hid. Weak because a window that
the system destroys must not be retained by this bookkeeping.
`coverLauncher` (731–738) hides every normal-level window in the scene that is not a
guest window, remembering it. `uncoverLauncher` (739–744) only restores when no guest
window is visible any more, and only the windows it hid itself. `logLayer` (745–750) is
a bounded (depth 5) recursive layer dump used by the `--sample-native` diagnostic.

## Lines 752–860: `NSWindow`

The ivars (753) are the guest window's state: the single `UIWindow` it maps to, the host
view, the content rectangle before UIKit takes over, the first responder, and the
collection behaviour bits.

- `-initWithContentRect:styleMask:backing:defer:` (754–758) stores the rectangle and
  style, sets the responder chain to the application, and assigns a **monotonic window
  number** from a static atomic — AppKit's window numbers are integers that never repeat,
  and guests compare them.
- `+windowNumbersWithOptions:` (760–765) lists visible windows **frontmost first**,
  which is reverse order of creation here: the window shown last is in front, so
  reversing the array is the whole of the stack model.
- `+windowNumberAtPoint:belowWindowWithWindowNumber:` (766–774) walks the same reverse
  order, starting below the named window when one is given, and returns the first visible
  window containing the point. Zero means none.
- `-initWithContentRect:…screen:` (775–777) ignores the screen argument: there is one
  screen.
- `-screen` (778) is the main screen; `-isMiniaturized` (779) is NO because iPadOS has no
  miniaturisation for a single full-screen surface.
- `-invalidateCursorRectsForView:` (780) discards then resets the view's cursor
  rectangles, which is AppKit's own two-step contract.
- `-setContentSize:` (781) records the size and resizes the content view.
- `-setFrame:display:animate:` (782–791): the desktop asks to be a rectangle; UIKit owns
  the scene's geometry. The method therefore records the rectangle and, if there is a
  host view, tells the guest window its **actual** content dimensions (which is the
  host's bounds), because those are what the guest must render at. Without a host view it
  simply resizes the content view.
- `-setFrame:display:` (792) is the same with animation off.
- `-frame` (793) returns the host's bounds when attached, otherwise the recorded
  rectangle: the window *is* the screen area it occupies.
- `-backingScaleFactor` (794) returns the **screen's** native scale. Note for the
  performance chapter: this is what a guest multiplies points by to size its backing
  store, and it is a hard-coded 2.0 on this panel.
- `-isKeyWindow` (795) defers to the UIWindow; `-isVisible` (796) is "there is a
  UIWindow and it is not hidden"; `-occlusionState` (797) reports visible only when the
  scene is not backgrounded — the two bits AppKit defines.
- `-mouseLocationOutsideOfEventStream` (798) returns the stored location.
- `-setMouseConfinementRect:` (799–803) rejects any non-finite coordinate (a guest
  computing the rectangle from a bad value would otherwise confine the pointer to
  infinity), stores an empty rectangle as no confinement, and tells the input layer
  whether the pointer is confined. That last call is what makes relative mouse mode
  engage.
- `-contentLayoutRect` (806) returns the content view's frame or the recorded size:
  a struct-returning method the stub forwarder could not answer.
- Screen conversion (808–812): one surface, so screen coordinates are window coordinates
  offset by the window's origin. Four one-line methods because guests call all four.
- Collection behaviour and sizes (813–822): stored and returned; `minSize` and the frame
  equals content rectangle because there is no title bar; origins and the two static
  conversions are identities for the same reason.
- `-firstResponder` (823) returns the stored responder or the window itself.
- `-makeFirstResponder:` (824–829) refuses a responder that does not accept the role,
  resigns the old one, stores and notifies the new one. AppKit's contract, and the reason
  `-acceptsFirstResponder` exists.
- `-setContentView:` (830–838) detaches the old layer, adopts the new view with this
  window as its responder parent and window, ensures a layer, and re-attaches if a host
  exists.
- `-ak_attach` (839–842) adds the content view's layer to the host's layer and applies
  the host's bounds.
- `-ak_hostBoundsChanged:` (843–862) is where a guest learns its window's real size, and
  it has three parts. First, the content layer's `contentsScale` is brought to the
  window's backing scale **unless the content view opts out** through
  `layer:shouldInheritContentsScale:fromWindow:` — AppKit's own escape hatch, which a
  view that draws one pixel per point uses. Second, the content view's frame is set to
  the host's bounds. Third, if that was a size change, it logs the new size, calls the
  delegate's `windowDidResize:` directly if implemented, and posts the equivalent
  notification — both, because a guest may use either.

## Lines 863–930: showing, ordering and event dispatch

- `-toggleFullScreen:` (863–866) logs the direction and calls the full-screen helper
  (`WindowFullscreen.m`).
- `-ak_layoutFullscreenWindow` (867–871) forces a layout pass then re-applies the bounds,
  which is how the guest hears the new size after a transition.
- `-makeKeyAndOrderFront:` (872–873) and `-orderFront:` (900) both call `-ak_orderFront`.
  The comment states the reason for the indirection: Wine's driver orders windows with
  `orderFront:`, and a guest's window class may override `makeKeyAndOrderFront:`; every
  route must end in one implementation that a subclass cannot intercept.
- `-ak_orderFront` (874–898) creates the UIWindow lazily: find the first
  `UIWindowScene`, build a `UIWindow`, install an `AKHostViewController`, take its view
  as the host, link it to this window, and attach the content layer if one exists. Then
  make it key and visible, apply the launcher-covering experiment, refresh the cursor,
  register in the application's window list, and — only if this window became key — post
  the became-key and became-main notifications to delegate *and* notification centre, and
  activate the application. The `wasKey` test prevents duplicate notifications when the
  same window is re-ordered.
- `-ak_notify:selector:` (899–903) calls the delegate directly (through
  `methodForSelector`, so no compile-time dependency on optional protocol methods) and
  posts the notification: guests observe either.
- `-ak_logLayers` (904–908) is the diagnostic dump of window, scene, view and layer tree.
- `-makeKeyWindow` (909) orders front only when visible; `-orderOut:` (910) clears any
  confinement, hides the UIWindow and uncovers the launcher; `-setIsVisible:` (911) maps
  the flag to the two operations.
- `-makeMainWindow` (912) is a no-op: there is one surface and it is already key.
- `-close` (913) orders out and removes itself from the application's list.
- `-sendEvent:` (914–930) is AppKit's dispatch: keys and flags to the first responder,
  mouse and scroll to the content view. The comment notes the simplification: hit-testing
  subviews is deferred until a guest needs it — a single full-window content view is the
  only view that receives mouse events today.

## Lines 932–960: `NSPanel` and `NSWindowController`

`NSPanel` (934) is an empty subclass: a panel is a window with different styling, and
there is no styling here. `NSWindowController` (935–943) stores a window and forwards
`-showWindow:` to `-makeKeyAndOrderFront:` and `-close` to the window's close. All four
methods exist so a guest's controller subclass resolves.

## Lines 962–1035: `NSApplication`

Ivars (963): the event queue, the window list, the event currently being dispatched, and
five booleans tracking launch, run-loop entry, activation, termination in progress, and
whether a termination reply is pending.

- `+sharedApplication` (964–969) returns `NSApp` if it exists — the comment notes that
  `[super init]` publishes the singleton before subclass initialisers run, so a subclass
  that calls `sharedApplication` from its own init gets the instance being built rather
  than a second one; otherwise creates it once.
- `-init` (970–978) publishes `NSApp`, creates the queue and window list, and observes
  becoming and resigning active, because `isActive` must be true during normal use and
  false when the system interrupts.
- `-windows` (979), `-currentEvent` (980) and `-keyWindow` (981, the last window) are
  accessors. The key window is the **last** ordered front, matching the stack model above.
- `-windowWithWindowNumber:` (982) is a linear scan: the list is tiny.
- `-mainWindow` (983) is the same window as key.
- `-setActivationPolicy:` (984) returns YES: there is no Dock or menu bar to configure.
- `-isActive` (985) returns the tracked flag.
- `-ak_becameActive:` (986–990) and `-ak_resignedActive:` (991–994) set the flag once and
  notify the delegate and the notification centre; the `if(!_active)` guard prevents
  duplicate activations from repeated UIKit notifications.
- `-activateIgnoringOtherApps:` (995) does nothing except, if the app is genuinely
  active, run the became-active path: AppKit's call is about window ordering, which this
  app cannot do.
- `-ak_notify:sel:` (996–1000) is the delegate-plus-notification helper, as above.
- `-finishLaunching` (1001–1005) sends the will and did finish-launching notifications
  once, guarded by `_launched`.
- `-run` (1006–1020) is the heart of the adapter. The comment states the contract: the
  guest calls this from its `main()`, which the host entered from a run-loop timer
  callout on the UIKit main thread; the method never returns, and pumps the **same** run
  loop re-entrantly so UIKit, `CADisplayLink`, timers and the main dispatch queue keep
  running underneath the guest's stack frame. Each iteration wraps a
  `NSRunLoop -runMode:beforeDate:` in an autorelease pool (so per-iteration objects are
  released) and then drains the event queue.
- `-ak_drain` (1021) dispatches every queued event through `-sendEvent:`.
- `-stop:` (1022) ends the loop.
- `-terminate:` (1023–1047): main-thread hop; ignore a re-entrant call; ask the delegate's
  `applicationShouldTerminate:` for a reply by calling it directly; log the reply; for
  "later" (2) spin the run loop until `-replyToApplicationShouldTerminate:` answers, then
  treat that as yes/no; for anything but "now" cancel termination; otherwise post the
  will-terminate notification and `exit(0)`. The spin is a nested run loop for the same
  reason `-run` is: the guest expects its own callbacks to keep firing while it decides.
- `-replyToApplicationShouldTerminate:` (1048–1051) records the answer and releases the
  spin.
- `-postEvent:atStart:` (1052–1062) is the queue's single entry point and contains the
  one coalescing rule in the adapter: consecutive **motion** events of the same type, for
  the same window, with the same flags and button are merged (deltas added, previous
  removed), and motion is never merged across a key or button event, so a fast pointer
  cannot queue stale movement ahead of a key-up. Events posted at the start go to index
  zero. If the guest has left the loop to us (`_inRun`), the queue is drained immediately
  so latency does not depend on the guest coming back.
- `-sendEvent:` (1063–1068) sets the current event, runs the local monitors
  (`AKEventMonitorRun`), honours a monitor that consumed the event by dropping it, and
  otherwise dispatches to the event's window or the key window.
- `-nextEventMatchingMask:untilDate:inMode:dequeue:` (1069–1100) is the other half of the
  event loop, called by the guest. It may execute a one-off diagnostic
  (`--sample-native` dumps the layer tree three times, fifteen seconds apart). Then, in a
  two-iteration loop: scan the queue in order and return the first event whose type is in
  the mask, removing and remembering it when dequeuing — with a first-eight log of
  keyboard delivery age, which is how input latency was diagnosed. If nothing matched,
  compute the time left; returning nil on the second pass when the deadline has passed.
  Finally the pump: a **non-blocking** ask (deadline in the past) runs one short UIKit
  turn (≤1 ms); a blocking ask waits up to the deadline, capped at 250 ms, and returns
  early if anything happens. The 250 ms cap keeps the guest from sleeping through a
  timer it does not know about; the 1 ms turn keeps deferred UIKit work (gestures, key
  repeat) alive when the guest polls continuously.
- `NSApplicationMain` (1102–1106) runs the application: there is no nib loading, stated
  in the comment, because a guest whose delegate lives in `MainMenu.nib` is not supported
  yet.

## `Screens.m` (40 lines)

`NSScreen` is a singleton wrapper over `UIScreen`.

| Lines | Explanation |
| --- | --- |
| 3 | `+mainScreen` builds and caches one instance with `dispatch_once`; there is one screen. |
| 4 | `+screens` returns the singleton in a one-element array. |
| 5 | `-frame` is `UIScreen.bounds`: the screen in **points**, so a guest's window coordinates and UIKit's agree. |
| 6–7 | The two auxiliary areas (menu bar strip, dock strip) are zero: iPadOS has neither. |
| 8–9 | Backing conversions divide/multiply by `backingScaleFactor`; they exist as methods because a guest may call them, and they must agree with `NSView`'s versions (which use the window first, the screen second). |
| 10 | `-visibleFrame` equals `-frame`: nothing occludes it. |
| 11 | `-backingScaleFactor` is the single line that decides how many pixels the guest believes it has. Returning `UIScreen.nativeScale` (2.0) makes a 1366×1024-point screen 2732×2048 pixels. **This is the line the layer's half-resolution patch changes** (see Deltas). |
| 12 | `deviceDescription` is a fixed dictionary: screen number 1, device size, 72 dpi, 8 bits per sample, calibrated RGB. Guests read it for DPI and colour depth; every value is the conservative one. |
| 13 | `-maximumFramesPerSecond` passes through `UIScreen`'s maximum (120 on this panel). |
| 14–15 | Extended dynamic range is reported as 1.0 (standard range only) in both forms, so a guest cannot ask for HDR it will not get. |
| 16 | `-minimumRefreshInterval` is the reciprocal of the maximum rate, so a guest that computes "the fastest link" gets the panel's real best. |
| 17 | `-maximumRefreshInterval` is a fixed 60 Hz estimate, and the comment says so: it is not the panel's range, because the adapter has no way to observe the actual chosen rate (a `CADisplayLink` reports the link's own rate, not the panel's). |
| 18 | `localizedName` is the only choice left, `@"iPad display"`. |

## `Images.m` (142 lines)

**`AKCreateCursorPath` (4–37).** Builds a `CGPath` outline of a cursor image, for
`UIPointerStyle`'s path shape, from the image's alpha channel only:

- Line 5 refuses a nil image, a non-finite or non-positive size, and a non-finite hot
  spot. Every one of those would otherwise propagate NaN into a path UIKit must render.
- `SAMPLES=128` (7) with the `MIN` on both dimensions (8) bounds the work: a cursor may
  be a 128×128 canvas with a small arrow in it, and a guest could hand over something
  enormous. The clamp is a bound on conversion cost, stated in the comment.
- Lines 10–14 draw the image into an 8-bit **alpha-only** bitmap the size of the
  clamped sample. Alpha only, because the shape comes from opacity; RGB is irrelevant.
- Lines 18–22 find the bounding box of pixels with alpha ≥ 128 — the *visible* part of
  the image. The comment records the concrete case that made this necessary: a mod draws
  its arrow into a 128×128 image, and using the whole canvas would make the system
  pointer enormous.
- Line 23 computes how large that visible box is in points, and line 24 scales the shape
  down so it is never more than 32 points: the system pointer's size is what it is kept
  to, so the pointer stays a pointer rather than a picture.
- Lines 25–33 turn each opaque horizontal run into a rectangle offset by the hot spot, so
  the path is in the pointer's coordinate system and the tip lands where the guest
  expects.
- Line 35 normalises the union so UIKit receives outlines rather than one rectangle per
  pixel run — the comment's exact reason.

**`NSImageRep` (38–39)** is an empty base: it exists so `isKindOfClass:` and subclassing
resolve.

**`NSBitmapImageRep`** (40–107) is the image representation that can be created from
raw planes or from a `CGImage`, and read back as either.

- Ivars (41–43): owned storage, a pointer into it (or into the caller's plane), and a
  cached `CGImage`.
- `-initWithBitmapDataPlanes:…` (45–65) is the main initialiser. Line 46 logs the
  request's geometry once, which is how an incompatible format is diagnosed from a log
  rather than a debugger. Line 50 **rejects** everything this implementation does not
  support — non-8-bit samples, planar, a sample count that does not match the alpha flag,
  a bitmap format with bits above 1,0 (`(format & ~3UL)`), a colour space that is not an
  RGB one — instead of returning storage with a layout the guest would misread. Returns
  nil, which the guest must handle. Line 51 defaults `bitsPerPixel`; line 52 rejects the
  two remaining inconsistencies (a padded pixel only allowed when there is no alpha, and
  a width that would overflow the row-length arithmetic); lines 53–55 compute and check
  the row length and the total size against `LONG_MAX`, so no multiplication can wrap.
  Lines 56–62 fill in the public properties and either adopt the caller's plane or
  allocate zeroed storage of exactly `rowBytes × height`.
- The `…bytesPerRow:bitsPerPixel:` variant (66–68) forwards with a zero bitmap format.
- `-initWithCGImage:` (70–85) allocates a 32-bit RGBA buffer, draws the image into it
  premultiplied-last (the layout the rest of the file assumes), and returns. Line 73
  rejects a zero dimension and a width that would overflow `width × 4`.
- `bitmapData` (86) and `isPlanar` (87) are the accessors a guest uses to write pixels.
- `-getBitmapDataPlanes:` (88) reports plane 0 and nulls the rest: a bitmap rep here is
  never planar.
- `-CGImage` (89–99) snapshots **on every call** — the comment says why: a guest writes
  through `bitmapData` without notifying anyone, so a cached image would be stale. It
  copies the bytes into an `NSData` (the provider must own its data, not the caller's
  plane), wraps it in a `CGDataProvider`, and creates the image with the alpha layout
  from `-ak_bitmapInfo`. The previous snapshot is released.
- `-ak_bitmapInfo` (100–105) translates the `NSBitmapFormat` first/straight flags into
  `CGImageAlphaInfo`: alpha none (skip first or last) when the pixel is 32-bit without
  alpha, otherwise premultiplied or straight, first or last. This is the one place the
  two flag vocabularies meet.
- `-dealloc` (106) releases the snapshot.

**`NSImage`** (109–132) holds a list of representations.

- `-init` (110) is `-initWithSize:` zero. `-initWithSize:` (111) creates the list.
- `-initWithCGImage:size:` (113–119) wraps the image in a bitmap rep and, if the caller
  passed a zero size, uses the image's own pixel size — AppKit's rule for images created
  from pixels.
- Representations (120–122): a copy out, add, remove-by-identity.
- `-CGImageForProposedRect:context:hints:` (123–127) returns the first bitmap
  representation's image, ignoring the rectangle and hints: there is one resolution per
  image here, so there is nothing to choose between.
- `-isValid` (128) is "has a representation".
- `-lockFocus`/`-unlockFocus` (130–131) are inert, and the comment says why: there is no
  offscreen drawing context in this translation. A guest that draws into a locked image
  gets nothing drawn; that is a known gap, recorded here rather than hidden.

**`NSCursor`** (133–142) is a thin holder for an image and a hot spot, with one
file-static "current" pointer and one notification.

- `-initWithImage:hotSpot:` (136) stores both.
- `+arrowCursor` (137) caches a cursor with no image and a zero hot spot; "no image"
  later means "use the system arrow" (`AppKit.m`, `-cursorChanged:`).
- `+currentCursor` (138) returns the stored cursor or the arrow.
- `-set` (139) stores itself as current and posts `AKCursorDidChange`, which is what the
  host view listens for to rebuild the pointer.
- `+hide`/`+unhide` (140–141) forward to the capture flag (`AKCursorHide`/`AKCursorUnhide`
  in `AKSupport`) and notify, so the pointer can react.

## `TextInput.m` (82 lines)

**`AKEnumerateTextKeys` (3–40)** turns a string into the key presses that would type it
on a US layout. The comment is the design rule: key codes are **key positions**, and the
Unicode is always carried too, so an unmapped character is emitted with code `0xFF`
rather than being turned into an arbitrary key press.

- Line 6: the letter key-code table (the same permutation as `AKKeyCode` in `AppKit.m`,
  because both encode the same two orders).
- Line 7: the unshifted punctuation characters in the order their key codes appear in
  line 9; line 8: the shifted characters in the same order. Two parallel strings are the
  whole mapping — index `i` in either maps to `keys[i]`.
- Line 10 normalises CRLF to LF so a pasted text does not produce two Returns.
- Line 11 enumerates by **composed character sequence**, so an accented character or an
  emoji is one unit, not two.
- Lines 14–16 start from "unmapped, no modifiers, unmodified text = the character".
- Line 17 maps newline to Return (36) and makes both text fields CR, which is what a Mac
  application expects for a line break.
- Line 18 maps tab to 48 with no text change.
- Lines 19–36 handle a single character: letters map through the table, with shift
  (`1UL << 17`, `NSEventModifierFlagShift`) for uppercase and the lowercase form as the
  unmodified text; everything else is looked up in the plain string first and then, if
  not found, the shifted string, setting shift when the match came from there. The
  unmodified text is always the plain character at that index.
- Line 38 emits the character, its unmodified form, the code and the modifiers.

**`AKInterpretTextKey` (42–82)** is the reverse path: given a key event, decide whether it
is a command, a command key-equivalent, or text.

- Lines 43–44 decode the four modifiers AppKit cares about from the flag bits.
- Lines 46–60 map key codes to AppKit command selectors: Return and Enter both insert a
  newline; Tab inserts a tab, Shift-Tab back-tabs; Delete forwards to
  `deleteWordBackward:` with Option; Forward Delete likewise; Escape cancels; arrows move,
  with Option moving by word; Home/End/Page Up/Page Down map directly. All of these are
  the names AppKit uses, so a guest's overrides are found.
- Lines 61–68 handle Command: A/C/V/X/Z (with Shift for redo) and Command-left/right for
  line starts. These are the standard key equivalents; a guest that wants different ones
  installs a menu, which this adapter does not implement.
- Line 69 turns any `move…`/`page…` selector into its `…AndModifySelection:` form when
  Shift is held — AppKit's naming rule, applied by string surgery, which is why the
  selectors are chosen to follow it exactly.
- Lines 70–74 dispatch the command through `doCommandBySelector:` if the client
  implements it, and return: once a key is a command, it is not also text.
- Line 75 refuses to insert when there are no characters, when Command is held (a key
  equivalent is never literal text), or Control is held (a control character).
- Lines 76–81 insert the text, preferring `insertText:replacementRange:` and falling back
  to `insertText:`. Two names because both are in use across macOS versions, and a guest
  may implement either.

## `WindowFullscreen.m` (47 lines)

- Lines 5–8 define the four full-screen notification names as real constants, so a guest
  comparing against them gets the same object.
- Line 9 is the associated-object key guarding a transition in flight; line 10 is the
  AppKit style-mask bit for full screen (`1UL << 14`).
- `notify` (12–18) calls the delegate's optional method through `objc_msgSend` and posts
  the notification: guests use both routes.
- `AKToggleFullscreenWindow` (19–47): refuse nil; hop to the main thread (a guest may
  call from a worker); refuse re-entry while the associated flag is set (AppKit ignores a
  toggle during a transition); set the flag; compute the direction from the style mask.
  Then, inside `@try`: send the "will" notification, flip the style bit, and force a
  layout pass — with the flag cleared and the exception re-thrown if anything throws, so a
  throwing delegate cannot leave the window permanently "transitioning". Finally, **as an
  async block**, send the "did" notification and clear the flag. The deferral is
  deliberate and commented: AppKit completes the transition after `toggleFullScreen:`
  returns, and a guest typically enters its event loop at that point; delivering "did"
  synchronously would call back into a guest that has not yet re-entered its loop.

## `Nibs.m` (134 lines): loading a guest's interface

A Mac application's windows and menus usually live in a compiled nib. Two sources are
used, in this order: a **prepared graph** — JSON produced at build time by the platform's
own nib parser, which is the faithful route — and, where no prepared graph exists, the
**guest's own compiled nib** read directly (`NibArchive.m`).

- `nibDirectory` (5) is where the prepared graphs live; `AKSetGuestNibDirectory` (6)
  records it, nil meaning none.
- `AKGuestNib` (9–20) is the fallback: build the path
  `Contents/Resources/<name>.nib`, refuse if it does not exist, append `keyedobjects.nib`
  when the nib is a folder (a compiled nib is either a file or a directory — line 14 says
  so), read it, and parse it with `AKReadNibArchive`. The `AKLog` records whether it was
  readable, because the most common failure is a path that looked right.
- `AKNibGraph` (25–97) is the instantiator for the prepared graph. Its comment states the
  contract: it handles the application object and the menu graph used at startup, and
  **fails explicitly on an unknown class** rather than pretending to load.
  - `-value:` (35–45) converts a scalar entry: `NSNull` to nil, `{"ref": n}` to the
    object at index n (creating it if needed), `{"data": hex}` to an `NSData` decoded from
    hex two characters at a time, anything else to itself.
  - `-field:at:` (46–50) reads a named value from an object's `values` pairs; an index out
    of range marks the graph failed.
  - `-object:` (51–96) instantiates by class name, memoising every result in `instances`
    so a shared object is created once. Before creating, it stores `NSNull` at the index
    (line 55) — a placeholder that also breaks reference cycles during construction. Then:
    - `NSString` from `NS.bytes` as UTF-8 (57).
    - `NSNumber` from `NS.intval`, defaulting to 0 (58).
    - Arrays and sets (59–64): a mutable array filled from the entries carrying the
      empty-key marker. A set is instantiated as an array because nothing in the startup
      graph needs set semantics, and creating one would invite a silent difference.
    - `IBClassReference` becomes its class name (65).
    - `NSCustomObject` (66–74): the class is looked up; an unavailable class fails the
      graph; a subclass of `NSApplication` gets the shared application and must be the
      *same* class the nib names (line 72) — a mismatch is a failure, not a substitution —
      and anything else is created with `new`. This is how the application delegate comes
      into existence from the nib.
    - `NSMenu` (75–80) and `NSMenuItem` (81–89) are built with their titles, key
      equivalents and modifier masks, disabled flag, tag, submenu, action and target; a
      menu named `_NSMainMenu` is installed as the application's main menu.
    - Connectors (90–92) are deferred: their index is returned as a number and the
      connections are applied by `-loadNibNamed:` after instantiation, because applying
      them during construction would set outlets on objects that do not exist yet.
    - Anything else (93) logs the class and fails.
  - Line 94 caches the result, nil included, so a failed object is not retried forever.
- `NSBundle (AKNibLoading)` (99–134): `-loadNibNamed:owner:topLevelObjects:` first tries
  the prepared JSON graph (`<name>.nib.json`), and only if that is absent falls back to
  the guest's own nib (108). Lines 109–110 validate the graph's shape: format 1, an array
  of objects, and no more than 100 000 of them — a bound that keeps a malformed or hostile
  file from allocating without limit. It then instantiates the graph, finds the
  `NSIBObjectData` record that holds the nib's metadata (112–114), takes the root from
  `NSRoot` (115) and the top-level objects and connections from it (116–117). Connections
  are applied in two ways (118–125): a control connector into an `NSMenuItem` sets its
  target and action from the label (the standard menu wiring), and anything else is an
  outlet set through key-value coding. A failed graph returns NO (126) rather than a
  half-built interface. Line 128 keeps every loaded graph alive for the process: the
  comment explains that application delegates may hold only weak references, so letting
  the graph be collected would take their objects with it. Finally each top-level object
  gets `awakeFromNib` (129), the output array is filled, and the count is logged.

---

## Per-frame cost of this adapter (basis for the performance work)

Only three things here run once per presented frame for a game that draws with Metal:

1. `-[NSApplication nextEventMatchingMask:…]`, called by the guest's loop. Measured on
   device: **fewer than 2000 calls in a 330 s session** — a handful per second, so its
   cost is irrelevant at the frame level.
2. `-[NSApplication postEvent:atStart:]` and `ak_drain`, which run only when an input
   event exists.
3. `-[AKHostView positionCursor]`, which runs on pointer events only, not per frame.

Nothing else in this file is on the frame path. That is the factual basis for saying
that AppKit input/window code cannot explain a 14 ms per-frame CPU cost, and it is why
the next candidate is checked in `Metal.md`.

## Deltas applied by this fork

| Patch | File | What it changes | Why |
| --- | --- | --- | --- |
| 0013 | `AppKit/AppKit.m` | key delivery diagnostics | input latency was being measured from the guest's own dequeue time |
| 0021 | `AppKit/AppKit.m` | counts run loops entered in `NSRunLoopCommonModes` | CoreFoundation refuses that mode and returns at once, which can spin the main thread; the log prints once per process, so a count was needed |
| 0023 | `AppKit/Screens.m` | the backing scale the guest is told | native 2.0 makes the guest draw 2732×2048 every frame |
| 0024 | `AppKit/AppKit.m` | the pump's 1 ms turn is allowed at most every 4 ms, with counters | the poll frequency was unknown; measured at fewer than 2000 polls per session, so this was not a frame cost |

Read `wolkaraforever/patches/` for the authoritative text of each.
