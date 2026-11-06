# Core adapters: CoreGraphics, CoreServices, Carbon, IOKit

Eleven files, 969 lines. Nothing here calls CoreGraphics, CoreServices, Carbon or IOKit
themselves; each symbol is answered from UIKit, Metal or state the file keeps. Where the
guest expects a display list it gets one display; where it expects a gamma ramp it gets
back the ramp it set.

## `CoreGraphics/DisplayModes.m` — 35 lines

A display mode is **not an object here**: it is the five-key `CFDictionary` that
`Displays.m:15` builds, so every getter is one dictionary lookup. `CGDisplayModeRef` is
declared as `CFDictionaryRef` (5), which is why retain/release are `CFRetain`/`CFRelease`
and no separate type exists. The five getters (6–10) read `width`, `height`, `pixelWidth`,
`pixelHeight` and `refresh` through one bridge and one lookup each, with no allocation.
`CGDisplayModeGetIOFlags` returns `3` — valid and safe — for any mode, because every mode
this adapter can produce is both; `CGDisplayModeCopyPixelEncoding` returns a retained
constant (`"--------RRRRRRRRGGGGGGGGBBBBBBBB"`, the 32-bit RGB encoding); the release (13)
guards NULL because `CFRelease(NULL)` aborts; `CGDisplayModeIsUsableForDesktopGUI` (14–16)
is "exists and both dimensions non-zero", which keeps a guest from installing a 0×0 mode.
The three identity predicates (21–23) are `display == 1` for main and built-in and `false`
for mirrored. `CGDisplayPixelsWide`/`High` (24–35) each copy the mode, read one field,
release: **three allocations' worth of work to answer one number**.

## `CoreGraphics/Displays.m` — 70 lines

- `CGCursorIsVisible` (5) is one atomic load of the capture counter — the cheapest call in
  the file.
- `CGAssociateMouseAndMouseCursorPosition` (6) sets capture to `!connected`, because on
  macOS *connecting* the cursor to the mouse means capture is off; `AKMouseSetCaptured`
  posts its notification only on a real change.
- `CGWarpMouseCursorPosition` (7–11) refuses when the mouse is not captured
  (`kCGErrorNotImplemented` — an uncaptured pointer is the system's) and otherwise posts
  the anchor to the host view, which places the software cursor.
- `mode()` (15) builds `{width, height, pixelWidth, pixelHeight, refresh}` from
  `UIScreen.mainScreen`: bounds in points, `points × nativeScale` in pixels, the panel's
  maximum frame rate. **A new dictionary of five boxed numbers on every call, with no
  cached copy** — see the performance section.
- `CGGetActiveDisplayList` (17–20) answers 1, 0 or writes one id according to whether the
  caller passed a NULL count, a NULL array (a size query), an array with room, or an array
  without. `CGGetOnlineDisplayList` (22) is the same, because nothing can be offline.
- `CGDisplayBounds` (23) returns the screen in **points**, so a guest and UIKit agree;
  `CGDisplayScreenSize` (24–29) converts to millimetres at 132 points per inch (a 264 ppi
  panel at 2×), the physical size a Mac would report.
- The two display-mask calls (33–34) round-trip 1 ↔ 1. `CGDisplayIOServicePort` (35) is
  `MACH_PORT_NULL`: there is no port to hand out, and the null is what a caller must
  already handle. `CGDirectDisplayCopyCurrentMetalDevice` (36) is Metal's own device at
  +1, which is Metal's contract for the call.
- Capture/restore/shield (39–42): an iPad app already owns the screen, so capture is a
  state the host is always in; the shield level is returned as the number a guest expects
  even though nothing is shielded.
- `CGDisplayCopyDisplayMode` (43) and `CGDisplayCopyAllDisplayModes` (44) both hand back
  the same dictionary, at +1, one element long — a guest that enumerates finds exactly one
  mode and cannot pick another. `CGDisplaySetDisplayMode` (47–51) **compares** the request
  with a freshly built mode: equal is success, different is `kCGErrorIllegalArgument`,
  because nothing can be applied and silence would be worse than a refusal.
- Reconfiguration callbacks (57–70): a process-wide dictionary keyed by
  `"%p:%p"` of callback and context; registration is synchronised on the `UIScreen` class
  so the same pair cannot be added twice, and the observer fires the guest's callback with
  flag `1 << 4` (`kCGDisplayAddFlag`) — where macOS sends `1 << 3` for a mode change, so a
  guest filtering on set-mode will not act on it. Removal before registration is safe
  because messaging nil is a no-op.

## `CoreGraphics/Events.m` — 28 lines

Quartz events: the objects `-[NSEvent CGEvent]` hands out (see `AppKit.md`), and those a
guest creates here. `CGEventCreate` (6) ignores the source and returns a new `AKQuartzEvent`
at +1. `CGEventCreateKeyboardEvent` (7–13) sets type 10/11 and field 9 (the keycode),
recording neither source nor keyboard type because nothing reads them.
`CGEventGetLocation`/`SetLocation` (14–15) read and write the stored property: a struct
return, no allocation. The four **field** accessors (22–25) go through the event's
dictionary under `@synchronized(self)` — a getter is a lock, a boxed-key lookup and a
`longLongValue`, a setter a lock and an insert; this is the only part of the file that does
real work per call, and it is why type/location/timestamp/flags are stored outside the
dictionary. `CGEventCreateSourceFromEvent` (27) returns NULL and
`CGEventSourceGetPixelsPerLine` (28) returns 10, the documented default a NULL source
implies, so wheel scrolling has a rate with no source in existence. Every accessor is
NULL-tolerant by construction.

## `CoreGraphics/Gamma.c` (38) and `Gamma.h` (16)

iPadOS lets no app change the display's gamma, so a program that sets a ramp is told it
took and reads back what it set. Three 256-`float` static tables and one `table_size` (6–7)
are the whole state. `CGDisplayGammaTableCapacity` (9–11) is 256 for display 1 so a caller
can size its buffer. `CGSetDisplayTransferByTable` (13–20) rejects a wrong display, a size
above capacity and a size with a NULL channel, but **allows size 0 with all-NULL
pointers** — a legitimate "no custom ramp" — then copies and records the size; nothing
reaches the display. `CGGetDisplayTransferByTable` (22–36) reports 256 when nothing was ever
set and the stored size otherwise, clamped to the caller's capacity, and computes
`linear = i / (size - 1)` (0 when `size <= 1`, so no division by zero) even when a stored
table means it is discarded; a read is ~256 divisions and up to 768 float stores, no
allocation, no syscall. `CGDisplayRestoreColorSyncSettings` (38) clears the size.
`Gamma.h` declares the shared typedefs, `CGGammaValue` as `float`, `AKMainDisplay = 1`,
`AKGammaTableCapacity = 256` and the four prototypes.

## `CoreServices/Errors.c` — 27 lines

Two status-to-string functions, both non-NULL and neither allocating. The POSIX range
`100000…100999` is tested **first** (6–15) and answered from `strerror`, so every POSIX code
has a real message; four Carbon codes (−50, −43, −108, 0) follow, everything else is `""`.
`GetMacOSStatusErrorString` (16–27) answers the *symbolic* names instead (`noErr`,
`paramErr`, `fnfErr`, `memFullErr`, plus `EPERM`/`ENOENT`/`EACCES` by number) and
deliberately does not call `strerror`: it answers "which code is it", not "what does it
mean".

## `CoreServices/Keyboard.m` (33) and `USKeyMap.h` (324)

`UCKeyTranslate` is answered from one 32 × 128 table. The guard (10–11) requires a non-NULL
layout beginning with `AK_KEY_LAYOUT_MAGIC` (`0x414b5553`, "AKUS"), a keycode under 128, an
action of at most 3 and three non-NULL out-parameters — anything else is `paramErr`, which
is also what a guest gets if it passes a layout loaded from a Mac, because no such layout is
accepted. `*length` is zeroed before anything can fail later. The translation itself is
one load (13): row = `modifiers & 31`, column = keycode. Dead keys are the option layer
with command and control clear and action not 3 (15): five keys produce combining accents
(16–18); with none pending the accent is stored and the call returns success with **zero
characters**, which is what makes the next keystroke compose (20). Composition (22–29)
builds an `NSString` from the base letter followed by the combining mark and asks for
`precomposedStringWithCanonicalMapping` — **the only allocation in the file and the only
Unicode work** — using the composed character when it yields one, and otherwise emitting
the spacing accent followed by the base (or the accent alone after a space). Too little
room is `kUnicodeNoRoomForConversionErr`, with the caller's buffer untouched and the dead
state kept. A successful translation always clears the pending accent (31).

`USKeyMap.h` is 8 KB of `const` `uint16_t[32][128]`: row = the five Carbon modifier bits in
the order line 2 states (command, shift, caps lock, option, control), column = the ANSI
keycode, value = one UTF-16 code unit. The rows: unshifted labels; command rows identical
to unshifted; shift and shift+caps identical; caps-lock uppercase with unshifted symbols;
the option layer; and sixteen control rows carrying Ctrl+A…Ctrl+Z as `0x01`…`0x1A`. Two
places where the data does not follow the documented rule are recorded in `Appendices` of
the source review: row 13 (option + caps + command) is the lowercase `^`/`~` variant while
row 12 (option + caps) is the uppercase `ˆ`/`˜` one, and rows 10/11/14/15 collapse into one
row, so option+shift and option+shift+caps are indistinguishable. The table is what the
translator reads; the documents record it as found.

## `Carbon/Keyboard.m` — 64 lines

One keyboards input source, answered from a dictionary built once (`19–36`) whose
`kTISPropertyUnicodeKeyLayoutData` is an `NSData` wrapping `AKUSLayout` — the four bytes
`UCKeyTranslate` checks against its magic, which ties the two files together. The thirteen
`kTIS…` constants (5–17) are compile-time `CFStringRef`s whose content is their own name,
which is what they are on macOS: tokens compared by identity. `TISCopyCurrentKeyboardLayoutInputSource`
and its two siblings (37–39) return the same object at +1, because a guest asking for the
ASCII layout and the current layout must get the same thing or it will believe the layout
changed. `TISGetInputSourceProperty` (40–43) lends a property only from our own source.
`TISCreateInputSourceList` (44–53) filters against the caller's dictionary and returns an
empty array on a mismatch or a match-all for a NULL filter — one `CFArray` per call, as the
`Create` naming requires. `TISSelectInputSource` accepts only our source; `LMGetKbdType` is
40 (the ANSI family); `KBGetLayoutType` is 0. `CopySymbolicHotKeys` (60–64) returns
`unimpErr` rather than an empty list, because "no hotkeys are defined" and "this system has
no hotkey registry" are different answers.

## `IOKit/Registry.m` — 300 lines

Ten interposed entry points. Each resolves the real function once per process
(`realFunction`, 23–33, which refuses to return the wrapper itself and logs the one symbol
that cannot be forwarded), then either answers as a Mac's GPU entry would or forwards
untouched.

- `configure` (40–48) reads the launch arguments once: `--trace-iokit` turns tracing on and
  `--native-gpu-identity` turns the Mac answers off.
- `trace` (51–60) returns immediately when tracing is off — **the one branch that keeps the
  trace free**, except that its call sites build their arguments first (see performance).
- `useStandIn` (112–127) builds the Mac-shaped entry: the Metal device's name with `" GPU"`
  stripped, the `vendor-id` from `GPUIdentity.h`, and a real `IOResources` or
  `IOPlatformExpertDevice` object to stand as the registry object a guest may hold.
- `acceleratorMatch` (134–138) takes over exactly the `IOAccelerator`/`IOGPU` provider
  match; `isGPU` (140–142) is one or two `IOObjectConformsTo` calls.
- `macGPUProperty` (144–148) answers only when identity overrides are on, a key exists and
  the entry is the GPU, so any other property read is forwarded untouched.
- `IOServiceGetMatchingServices` (150–176) runs the query **twice** when it has to log or
  serve the accelerator match, retaining the matching dictionary first because each call
  consumes a reference (162), then re-issues the query against the stand-in's class when
  the accelerator match found nothing.
- `IOServiceGetMatchingService` (177–190) does the same for the single-service form.
- The property readers (198–229) replace the value on the stand-in, may replace it for the
  GPU, and trace — building the trace string on **every** call, including a class lookup
  and a value summary.
- `IORegistryEntryCreateCFProperties` (230–255) overwrites the identifying keys inside the
  whole property set so a guest reading the set sees the same `vendor-id` it would see from
  a single-key read, and it is **the only wrapper whose trace string is inside
  `if (tracing)`** (246) — the shape the others should have.
- `IORegistryEntryGetChildIterator` (271–287) answers for the stand-in with the real
  accelerator match, which on the iPad is empty: a Mac's GPU entry has only user clients
  below it, and a game reads nothing from them.
- `IORegistryEntryGetRegistryEntryID` (288–300) gives the stand-in the Metal device's id —
  it deliberately claims to be the GPU behind the device.

## `IOKit/GPUIdentity.h` — 34 lines

Four pure `static inline` functions, tested on the Mac.
`AKGPUIdentityKeys()` returns `@[@"vendor-id"]` — a fresh array per call, existing so the
override list cannot drift from the loop and the log that use it.
`AKGPUIdentityProperty` answers only `vendor-id`, with four bytes `6b 10 00 00` (`0x106b`,
little endian, as IOKit stores it) in a freshly allocated `NSData`, and nil for everything
else — the instruction to keep the iPad's own value.
`AKGPUStandInProperties` strips a trailing `" GPU"` from the Metal name (so `"Apple M5 GPU"`
becomes the `"Apple M5"` a Mac's `model` carries), fills a dictionary from
`AKGPUIdentityKeys` and adds `model`; called once, at `Registry.m:118`.
`AKGPUIdentityPrivateKey` (28–34) lowercases the key and tests fifteen substrings —
`serial`, `uuid`, `udid`, `unique`, `ecid`, `chip-id`, `mac-address`, `imei`, `meid`,
`iccid`, `wifi`, `bluetooth`, `ethernet`, `region-info`, `mlb` — so anything that identifies
a device or a person is logged as `(withheld)`.

## Per-call cost — by inspection

The captured session never passed `--trace-iokit` (zero `IOKit ` lines in the log), so
**these call frequencies are unmeasured**. What follows is a property of the code.

| Family | Per call | Note |
| --- | --- | --- |
| `CGMainDisplayID`, `CGCursorIsVisible`, `CGEventGetLocation/Type/Flags/Timestamp`, `CGGetDisplayTransferByTable` variants | cached read / bounded copy | free or bounded |
| `mode()` and everything that calls it (`CGDisplayCopyDisplayMode`, `CopyAllDisplayModes`, `CGDisplayPixelsWide/High`, `CGDisplaySetDisplayMode`) | **five boxed numbers + a dictionary per call**, no cache | the only display family that allocates |
| `CGEventGet/SetIntegerValueField` | lock + boxed-key dictionary lookup | per event, not per frame |
| `UCKeyTranslate` | one table load; allocation only when a dead key composes | per keystroke |
| `TISCopyCurrentKeyboardLayoutInputSource` | one `CFRetain` | one atomic increment |
| `TISCreateInputSourceList` | one `CFArray` | the `Create` contract |
| IOKit property readers | **4–5 kernel round trips** (the read, `isStandIn`, one or two `IOObjectConformsTo`, `IOObjectGetClass`) **plus string formatting, tracing or not** | `IORegistryEntryCreateCFProperties` is the exception: free when tracing is off |

Two facts worth keeping: **gamma never touches the panel** (there is no way to, and the
adapter says so by returning what was set), and **the registry diagnostic builds its strings
whether or not tracing is on**, which is a real cost on every property read — the one place
in these files where the code does work for a log line that will be discarded.
