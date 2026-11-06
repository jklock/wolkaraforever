# Support: logging, stubs, alerts, menus, monitors and drawing

The last files that complete the coverage: the shared support layer every adapter builds on,
and the AppKit pieces that exist so a guest's classes and selectors resolve.

## `AKSupport/AKSupport.m` — 66 lines

- **`AKLogC` (5–9)** writes `"[ak] "`, the formatted message and a newline to `stderr` with
  `vfprintf` — unbuffered, so a crash cannot swallow the last line before it. Every `AKLogC`
  in the layer is therefore a `write(2)`, which is why no adapter calls it on a per-frame or
  per-buffer path (see `Audio.md` and `Core.md`).
- **`AKLog` (11–16)** builds the message with `initWithFormat:arguments:` and prints its
  UTF-8 form. It allocates, and it exists for the messages that need `%@` on an `NSError` or
  a class name.
- **`AKStubHit` (18–23)** reports a generated stub's first call with `dladdr`, printing the
  caller's image name and offset inside it — the diagnostic that turns "some function
  returned zero" into "this call, from this library, at this offset".
- **`AKStubObject` (25–42)** is the base class that keeps an unimplemented selector from
  crashing: `forward` (26–34) builds a `"-[Class selector]"` key, logs it **once per key**
  under a lock (`27–33`) so a call in a loop cannot flood the log, and zeroes the return
  value (`34`) — only object returns, as the comment states: struct and floating-point
  returns are not zeroed, because this is a discovery aid, not a complete ABI. Both instance
  and class `methodSignatureForSelector:` (36–37) fall back to `"@@:"` — "treat it as
  `id f(id, SEL)`" — and the extra arguments are harmless on arm64, and both
  `forwardInvocation:` forms (38–39) route to the same `forward`.
- **`AKQuartzEvent` (41–49)** is the Quartz event behind `-[NSEvent CGEvent]`: a dictionary
  of field number → `NSNumber`, with `integerValueField:` and `doubleValueField:` able to
  read either kind (43–44) — which is what Quartz does — and unset fields reading as zero.
  Every accessor takes `@synchronized(self)` (43–48), so the event is safe to read from
  another thread while it is being built.
- **Cursor state (51–55)**: one atomic counter; `AKCursorIsHidden` is a load, `AKCursorHide`
  an increment, and `AKCursorUnhide` a compare-and-exchange loop that never goes below zero.
  A count rather than a flag because two parts of the UI may hide the cursor independently.
- **Mouse state (56–66)**: two atomics, `mouseCaptured` and `mouseConfined`;
  `AKMouseIsCaptured` is the OR, so a confinement rectangle implies capture — which is what
  makes relative mouse mode engage. Both setters post `AKMouseCaptureDidChange` **only when
  the value actually changed** (`58–66`), so a redundant call from a guest is one atomic
  exchange and no notification.

## `AppKit/Alerts.m` — 53 lines

`NSAlert` is a desktop model built on a worker thread and presented on the main thread, and
the file's first comment says exactly that. `AKAlertButton` (4–9) stores a title, a key
equivalent and an enabled flag; `addButtonWithTitle:` (20) appends one and returns it.
`runModal` (21–52) logs the alert, adds an `OK` button when there are none (23), copies the
buttons and texts (24), then builds a `UIAlertController` whose actions return
`1000 + index` (39) — the AppKit convention that <cite>first button</cite> is 1000 — and
signals a semaphore. On the main thread it presents and then **spins the run loop in 0.1 s
slices** until the answer arrives (46), because a modal alert must keep the guest's own
callbacks alive; on another thread it dispatches the presentation and waits on the semaphore
forever (48–49). A failed presentation finishes with `-1001` (`NSModalResponseAbort`), so a
caller never blocks on an alert that cannot appear.

## `AppKit/Menus.m` — 29 lines

`NSMenuItem` (2–10): the designated initialiser copies title and key equivalent and defaults
`enabled` to YES; `+separatorItem` creates an item flagged as a separator, which
`isSeparatorItem` reports. `NSMenu` (11–29): a title and an ordered list with
`autoenablesItems` defaulting to YES; `itemArray` returns a copy (guests iterate while
removing); `addItem:`, `insertItem:atIndex:`, both removals maintain the menu back-pointer;
lookups by index (bounds-checked), tag and title; `indexOfItem:` returns −1 for an item not
present rather than `NSNotFound`'s unsigned value. Every method is the AppKit contract,
including the details that matter to a guest: the copy, the −1, and the back-pointer.

## `AppKit/EventMonitors.m` — 40 lines

The local-monitor table. `AKEventMonitor` (3–8) holds a mask and a copied handler. `monitors()`
(10–14) creates the list once. `AKEventMonitorAdd` (15–21) refuses a nil handler, stores the
monitor under a lock and returns it as the token. `AKEventMonitorRemove` (22–26) removes by
identity. `AKEventMonitorRun` (27–40) is the interesting one: it takes a **snapshot** under
the lock and runs the handlers outside it (28–30), so a handler may add or remove monitors
without deadlocking; it skips a monitor whose mask does not contain the event type (32), and
it **re-checks that each monitor is still installed before calling it** (33–35), because a
handler earlier in the list may have removed a later one — without that check the removed
handler would still run once. A handler returning nil stops the chain (36–37): that is the
"consumed" contract.

## `AppKit/Drawing.h` (41) and `Drawing.m` (94)

`Drawing.h` declares the colour-space name constants (3–4), `NSColor` (7–23) registered under
the runtime name `AKColor` **because UIKit has a private class of that name** — the header
says so, and `ldflags` exports AppKit's symbol names for it, which is what guests bind to —
`NSGraphicsContext` (24–39) with its CGContext, graphics port, flipped flag, the two factory
methods, the per-thread current context, save/restore, and `flushGraphics`, and `NSRectFill`
(41).

`Drawing.m` implements the parts that matter: the four colour-space names as literal
constants (2–3); `NSColor` over a retained `CGColorRef` (5–25), where **sRGB, calibrated and
device components mean the same thing** because the iPad's display is sRGB (4, 14–15) — the
three factory methods differ only in name, which is the honest translation rather than an
invented colour management; `colorWithCalibratedWhite:` builds a grey from the generic grey
space (16–19); `windowBackgroundColor` is macOS's light appearance, 236/255 grey (24); and
`getRed:green:blue:alpha:` converts the stored colour into the sRGB space and reads the
components (26–…). The remainder of the file implements `set`, `setFill`, `setStroke` onto
the current context, the `NSGraphicsContext` factories over a bitmap representation and over
a `CGContextRef`, the per-thread current-context stack, and `NSRectFill` — each as its header
declares.

## The small headers

`AKSupport/KeyboardLayout.h` (6) declares `AK_KEY_LAYOUT_MAGIC` (`0x414b5553`, "AKUS") and the
four-byte `AKUSLayout` blob: the magic `UCKeyTranslate` checks and Carbon hands out as the
layout data, which is what ties `CoreServices/Keyboard.m` and `Carbon/Keyboard.m` to one
format. `AppKit/NibArchive.h` (5) declares `AKReadNibArchive(NSData *)`. `AppKit/ImageHints.h`
(6) and `ImageHints.m` (5) declare and define the drawing-hint string constants a guest
passes to `CGImageForProposedRect:context:hints:` — empty strings, because no hint is acted
on (see `Images.m`).

## Per-frame cost

None of these is per frame. `AKLog`/`AKLogC` write to stderr and are deliberately kept off
every per-frame and per-buffer path; `AKStubObject`'s forwarding runs only when a guest calls
a selector nobody implemented, once per distinct selector; alerts and menus run on user
action; monitors run per delivered event; drawing runs when a guest asks for a colour or a
fill. The cursor and mouse state are one atomic load each at the points that ask.
