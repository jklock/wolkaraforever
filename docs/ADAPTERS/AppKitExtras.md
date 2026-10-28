# AppKit: the header and the three remaining files

Completes the AppKit coverage. `AppKit.h` declares the surface; the other three files are
the nib-archive parser, the on-screen touch controls and the trackpad state machine.

## `AppKit.h` — 266 lines, pure declaration

The header exists so a guest's compiled `#import <AppKit/AppKit.h>` finds every type and
selector it names, with the macOS arity. Nothing here executes; every implementation is in
`AppKit.m`, `Screens.m`, `Images.m`, `Nibs.m`, `TextInput.m`, `WindowFullscreen.m`,
`TouchControls.m` or `TouchTrackpad.c`, and each is documented in its own section.

**Types (9–25).** `NSRect`/`NSPoint`/`NSSize` are `CGRect`/`CGPoint`/`CGSize` (9–11) — the
layout is identical and the renaming is the whole of the translation. `NSEventType` (13–20)
is an `NS_ENUM` whose values are AppKit's (left/right/other mouse down/up/dragged, moved,
scroll, key down/up, flags changed), because `-[NSEvent CGEvent]` copies the type through to
Quartz and the numbers must match. `NSEventModifierFlags` (21–25) is the `NS_OPTIONS` mask
with AppKit's bits — shift 17, control 18, option 19, command 20, caps 16 — which is what
`TextInput.m` and the modifier tables in `AppKit.m` decode.

**The declared surface**, in file order:

| Lines | Class | What its declarations establish |
| --- | --- | --- |
| 29–50 | `NSResponder` | `nextResponder`, the three first-responder answers, `interpretKeyEvents:`, `insertText:`, `doCommandBySelector:`, and the thirteen event methods (`keyDown:` … `scrollWheel:`) that the `PASS` macro implements as forwarding |
| 53–66 | `NSEvent` | the stored properties — type, flags, timestamp, weak window, location in window (bottom-left points), the four delta fields, key code, both character strings, auto-repeat, button and click count — plus `CGEvent` and `+mouseLocation` |
| 72–77 | `NSTrackingArea` | the initialiser and the four read-only properties |
| 80–123 | `NSView` | frame, bounds, `wantsLayer`, autoresizing mask and flag, hidden, layer, weak window, superview, subviews; `makeBackingLayer`, the two `addSubview:` forms, `resizeSubviewsWithOldSize:`, removal, the two conversions, `setFrameSize:`, `viewDidMoveToWindow`, the cursor-rect API, the six backing conversions, tracking areas, `updateTrackingAreas`, `setNeedsDisplay:`, `setNeedsDisplayInRect:`, `displayIfNeeded`, `display`, `wantsUpdateLayer`, `updateLayer` |
| 125–202 | `NSWindow` | conforms to `AKFullscreenWindow`; the two initialisers, the two window-number class methods, frame/content sizing, `screen`, `mouseLocationOutsideOfEventStream`, the four screen conversions, `toggleFullScreen:`, the four frame/content rectangle helpers, the ordering methods, `makeFirstResponder:`, `sendEvent:`, `close` |
| 205–230 | `NSApplication` | `sharedApplication`, `windowWithWindowNumber:`, `setActivationPolicy:`, `activateIgnoringOtherApps:`, `finishLaunching`, `run`, `stop:`, `terminate:`, `replyToApplicationShouldTerminate:`, `sendEvent:`, `postEvent:atStart:`, `nextEventMatchingMask:untilDate:inMode:dequeue:` |
| 232 | `NSPanel` | an empty subclass of `NSWindow` |
| 234–245 | `NSWindowController` | `initWithWindow:`, `window`, `showWindow:`, `close` |

Plus `NSMenu`/`NSMenuItem` (used by `Nibs.m`), the `NSScreen` subclass whose implementation
is `Screens.m`, and the image and cursor classes implemented in `Images.m`. Every class
derives from `AKStubObject` (`AKSupport.h`), which is what makes an unimplemented selector
answer rather than crash — the same base the generated stubs use.

## `NibArchive.m` — 125 lines: reading a guest's compiled nib

The fallback path when no prepared graph exists. It parses the `NIBArchive` container: a
10-byte magic, a header of ten 32-bit words, and **four tables** (objects, keys, values,
class names), each a count and an offset.

`nib_varint` (6–15) reads a little-endian base-128 varint, seven bits at a time with the top
bit as continuation, sets `bad` on a truncated or over-long value and returns 0.
`nib_string` (17–25) bounds-checks the length against what remains (18), advances past it,
**strips zero padding** (21) and decodes UTF-8, marking `bad` on invalid text.
`nib_value` (26–67) decodes a typed value: `4`/`5` are YES/NO, `9` is null, `8` is a data
blob which is **hex-encoded into a single allocated buffer** (39–47) — the comment says why:
one buffer for the whole blob rather than one object per byte — and the numeric types read
from a width table (51) by `memcpy` so alignment cannot matter; the default case is a
four-byte reference (`{"ref": n}`), which is how the tables cross-reference.

`AKReadNibArchive` (69–125) validates the magic and a minimum length (72), requires header
version 1 and encoding 9 or 10 (75), then reads each of the four tables (77–104) with a
100 000-entry cap and offset bounds (79). Objects are triples of varints (85–87); the key
and class tables are length-prefixed strings, with a class entry allowed to name the classes
it extends (90–93) which are skipped by their byte count; the value table is a key index and
a value (95–99). Any `bad` cursor or nil entry aborts the whole parse (101) — a partly
decoded archive is never returned. The final pass (105–124) resolves each object's class and
its list of `(key, value)` pairs, rejecting a class index out of range, a value range
outside the table, a key index outside the key table, **and a reference that points past the
object table** (117–119) — the last is what keeps a malformed nib from producing a
dangling index that the instantiator would then chase. The result is the same
`{format:1, objects:[{class, values}]}` shape the prepared graph uses, so `Nibs.m` has one
consumer for both sources.

## `TouchControls.m` — 210 lines: the on-screen keyboard and trackpad

`AKEmitTouch` (14–22) is the only bridge from the trackpad state machine to the host view:
it maps the four `AKTrackpadAction` values onto the delegate's `touchMoveBy:`,
`touchScrollBy:` and `touchButton:pressed:`.

`+enabled` (24–28) reads the stored Boolean and otherwise **shows the controls on iPhone and
not on iPad**, per the header's stated design.

`buttonWithSymbol:label:action:` (30–42) builds a 44-point system button with a
semi-transparent dark background, a hairline border, a tint and an accessibility label — the
accessibility strings are real UI, not decoration: this is the only way a VoiceOver user can
reach a game that has no accessible interface of its own.

`initWithFrame:` (44–71) sets `zPosition` 100001 (above the guest's layer), creates the
keyboard and trackpad buttons with their accessibility identifiers and a long hint
describing the gestures (51), builds the **mouse-button menu** (53–64) whose three actions
press and release left, right and middle — cancelling any touch in flight first (59) so a
menu tap cannot be confused with a drag — reads the stored trackpad setting (65–66), and
observes resign-active and window-resign-key (67–68) so input is suspended when the game is
not frontmost.

`pointInside:withEvent:` (73–77) is the hit-testing rule the header promised: only the two
buttons intercept, and **the gap between them belongs to the game**. `layoutSubviews`
(78–82) places them 44 points apart.

`setTrackpadEnabled:` (83–90) cancels touches, recolours the button, updates label and value,
and tells the delegate. `toggleTrackpad` (91–92) is the button's action.

The `UIKeyInput` half (121–140) is the text sink: `hasText` always YES and the comment says
why — **the guest owns the text and the selection**, so the overlay neither caches nor
claims knowledge of it, and a backspace is always allowed; `insertText:` forwards to the
delegate; `deleteBackward` posts the Delete key; every autocorrect, autocapitalisation,
spell-check, smart-quote, smart-dash and smart-insert-delete behaviour is turned off,
because a game expects the bytes it typed; and `isSecureTextEntry` is YES, which is what
stops iPadOS recording a keyboard-training cache of what is typed into a game.

`inputAccessoryView` (142–163) builds one row of six buttons — Esc, Tab, ←, →, ↵, hide — with
their accessibility labels; `accessoryKey:` (164–170) maps them to key codes 53, 48, 123,
124, 36 and the matching characters, with tag 5 dismissing the keyboard.

`processTouches:withEvent:` (172–…) is the input path: it cancels on any cancelled touch,
computes the **centroid of the direct touches on the host view only** (182–191 — a touch on
the overlay itself is excluded, so pressing the buttons cannot move the pointer), feeds the
state machine, and arms a **one-shot** `NSTimer` (194–…) for the long-press, invalidated and
re-armed on every sample. A one-shot re-armed per batch is at most one pending timer; it is
never a repeating tick, which is what keeps the overlay off the frame path.

## `TouchTrackpad.c` — 72 lines: the gesture state machine

Plain C, no UIKit, tested on the Mac.

`AKTrackpadCancel` (5–10) releases a button if one is down, **blocks the rest of the gesture
until every finger lifts** (8) — so a cancelled tap cannot be completed by fingers still on
the glass — and clears the scroll accumulator.

`AKTrackpadHold` (12–18) is the long-press resolver: it refuses non-finite time, a blocked,
lifting or already-dragging gesture, more than two fingers, movement beyond 8 points, and
anything under 0.45 s — then starts a drag with the right button (two fingers = right).
Those six conditions are the definition of "held still", and each is there because without
it a scroll or a tap would turn into a drag.

`AKTrackpadUpdate` (20–72) is the whole gesture grammar:

- **No fingers (22–32)**: end a drag if one is in flight; otherwise, if the gesture was
  short (≤ 8 points, ≤ 0.35 s) and not blocked, emit a **tap** whose button comes from the
  peak finger count (three = middle, two = right, one = left) (24–29); then zero the state.
- **Bad input (33–38)**: more than three fingers, a non-finite coordinate or time, or time
  going backwards cancels and re-seeds the finger count.
- **First sample (39–42)**: records the start time and position.
- **Finger count changed (43–50)**: sets `lifting` when fingers are removed, cancels a drag,
  re-seeds the position and clears the scroll accumulator — the comment states the reason:
  **a changed centroid must not jump the pointer or produce a scroll**.
- **Blocked or lifting (55)**: consumes samples without emitting, which is how a lift is
  drained instead of becoming a drag.
- **Absurd movement (56–60)**: a jump over 10 000 points is treated as a glitch and cancels.
- **One finger, or dragging (63)**: emits a move with the raw delta.
- **Two fingers after 8 points of travel (64–71)**: accumulates `delta / 12` into a
  fractional line count and emits whole lines with `trunc`, keeping the remainder — the
  comment explains it: the Quartz adapter exposes integer wheel ticks, so sub-line motion
  would otherwise be lost entirely.

## Per-frame cost

None of these four files is per frame. `AppKit.h` is declarations; `NibArchive.m` runs once
per nib load; `TouchControls.m`'s only timer is a **one-shot** re-armed by touch samples; and
`TouchTrackpad.c` is a pure function called per touch sample, not per frame.
