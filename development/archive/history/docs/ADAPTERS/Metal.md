# Metal

`platform/translation/Metal/` is the adapter the guest's renderer spends its whole
life in, and therefore the only one that can be on a per-frame path. Files:

| File | Lines | Role |
| --- | --- | --- |
| `Devices.m` | 271 | device enumeration, GPU identity, the guest shader-library loader |
| `Presentation.m` | 133 | development-only presentation timing and frame capture |
| `MetalTrace.m` | 318 | opt-in observation of what the guest asks Metal to create |
| `BCTextures.m` | 600 | BC (block-compressed) texture support for GPUs without it |
| `BCDecode.c` | 516 | the block decoders behind it |
| `ManagedStorage.m` | 100 | opt-in Managed→Shared storage translation |
| `LibraryContainer.m` | 81 | verifies and relabels macOS metallib containers |
| `RenderDiagnostics.m` | 40 | per-command-buffer render-pass recorder (capture mode) |
| `StorageModes.h`, `RealFunction.h`, `LibraryContainer.h` | 41 | shared declarations |

Everything here follows one rule, stated in several files: **a normal run changes
nothing on the frame path.** All hooks except the library loader are behind a launch
argument, and the library loader is per-load, not per-frame.

---

## 1. `Devices.m` — 271 lines

### 1.1 Header, the shader-pause overlay (1–46)

Imports (1–10) bring in Metal, Foundation, `AKSupport` (logging), `LibraryContainer`
(the rewrap), `RealFunction` (resolving Apple's own symbol), the Objective-C runtime,
CommonCrypto (SHA-256) and UIKit (the overlay). Line 11 declares
`static atomic_uint shaderWaiters;` — how many threads are blocked waiting for a shader
translation; line 12 exposes `bool AKShaderWaitPending(void)`, a single atomic load,
consumed by `launcher/App/ShaderPauseProbe.m:21` and `runtime/NativeGuest.m:764,804`.
Line 13 holds the one overlay window, reused so repeated misses do not stack windows.

**`updateShaderPause` (14–42)** runs entirely on the main queue (`dispatch_async`,
15) because it creates UIKit objects. Line 16: no waiters → hide, release, return.
Line 17: already shown → return (several waiters, one overlay). Lines 18–21 find a
`UIWindowScene` in the foreground — a window cannot be created without one, and one
attached to a background scene would be invisible. Line 22 creates the window; line 23
sets `UIWindowLevelAlert + 1` so no game view or system sheet can occlude the
explanation; lines 24–25 give it a plain controller and an 80 % black background (opaque
enough to read, translucent enough to show the game is still there); lines 26–28 a
centred, multiline, dynamic-type-aware white label; lines 29–31 the two messages — a
`TOLKARA_LOCAL_SHADERS_ONLY` build says the iPad refused this shader and to close the
app, a normal build says to connect the Mac with the shader service running and the game
will resume. Lines 32–37 pin it with four constraints (centred, ≤ safe area − 64, ≤ 640
points: the second is a line-length limit in landscape). Line 38 sets the root
controller before showing. Line 39–40 show it **without** becoming key, deliberately:
`makeKeyAndVisible` would take keyboard focus from the game's own window.

**`shaderWaitTick` (43–46)** is how a waiting thread spends 50 ms. On the main thread it
runs `CFRunLoopRunInMode(…, .05, false)`: the overlay is delivered through the main
queue, and a thread waiting on a shader is often *the* main thread, so a plain sleep
would never let that block run. On other threads it sleeps 50 ms: 20 polls a second,
responsive without spinning.

### 1.2 Observer token and GPU identity (47–61)

`AKDeviceObserver` (49–52) is an empty object holding a copied handler block: it is the
token a caller receives from `MTLCopyAllDevicesWithObserver` and later hands back, and
its only purpose is identity and lifetime. `observers` (53) is the set that keeps it
alive. Then the desktop-topology answers, because guests infer the GPU's vendor and
class from them when the I/O Registry is silent: `desktopFalse` (56) answers NO for
`isLowPower`, `isHeadless`, `isRemovable` and `isDepth24Stencil8PixelFormatSupported`;
`builtInLocation` (57) is `MTLDeviceLocationBuiltIn`; `builtInNumber` (58–59) and
`previousNumber` (60–61) return 0 and 1 — a Mac with Apple silicon describes itself this
way, and iPadOS answers some of these *differently*, which can move a guest onto a code
path written for iPad hardware.

### 1.3 Library cache and manifest verification (62–86)

`LibraryLoader` (62–63) is the IMP type for `newLibraryWithData:error:`, and it must
carry `ns_returns_retained` or ARC will over- or under-release the +1 result. Line
65–66 creates a `weakToStrongObjectsMapTable` keyed by device: the key is weak so the
cache never keeps a device alive, and no `dealloc` hook is needed. Line 67 takes
`@synchronized(devices)` because libraries load from any thread. Lines 69–71 give each
device an `NSCache` with a count limit of 1024 and a 64 MB cost limit — bounded memory,
purgable by the system, unlike a dictionary.

`verifiedTranslations` (78–85) reads `<path>.json`, parses it, requires a dictionary,
reads the payload, requires `length == manifest["length"]`, hashes the bytes with
SHA-256 and returns them only when the hash matches. The length check is cheap and
catches truncation; the hash is what makes a file written on another machine across a
cable safe to consume. The manifest is a claim, the hash is the proof.

### 1.4 `captureLibrary` and `loadLibrary` (87–185)

`captureLibrary` (90–94) loads through `loadLibrary`, then hands the result to
`AKTraceMetalLibrary` — *including a cache hit*, so the trace sees what the guest
receives. `AKTraceMetalLibrary` is a no-op unless tracing is on (`MetalTrace.m:287`).

`loadLibrary` (95–185) is the loader the guest actually reaches, and every line is a
decision:

- 96–97: size the `dispatch_data`; refuse empty and > 64 MB by calling the system's own
  implementation. 64 MB is above any real metallib and below the size at which copy +
  SHA-256 would itself stall, and it matches `LibraryContainer.m:23` so the two agree on
  what is analysable.
- 98–103: flatten the (possibly discontiguous) `dispatch_data` into one buffer because
  hashing and parsing need contiguity, then SHA-256 it into `key`. A library's identity
  is its bytes, because guest libraries arrive anonymously.
- 104–109: cache lookup. Libraries are immutable, so identical bytes on the same device
  can share the native object; a hit returns the same object with the +1 the create
  method's contract requires, and `*error` cleared.
- 110–113: the Mac-side translation path, `<sha256>.metallib`, and `localOnly` from
  `TOLKARA_LOCAL_SHADERS_ONLY`, which disables the Mac path *by value* so every later
  check stays honest.
- 117: `AKLocalMetalLibraryData(bytes)` returns nil unless this is a macOS container of a
  known version that passed every structural and hash check (`LibraryContainer.m`).
- 119–123: load the rewrapped data through the **original** implementation with a local
  error, so a failure here does not poison the caller's error; log `loaded`/`rejected`
  with the key and the error, which is how a shader question is answered from a device
  log; on success cache with `cost = local.length`.
- 127: an unrewrappable container logs the version byte, saying *why* no rewrap was
  attempted.
- 128–166: the Mac wait. It is gated by `--translate-shaders` or
  `TOLKARA_WAIT_FOR_MISSING_SHADERS` because waiting needs a human and a Mac on a cable;
  a normal run must fail the way the untouched game would. One `NSLock` (132–133)
  serialises misses so one USB request file means one job, while cache hits and every
  draw stay on the device. `atomic_fetch_add` (134) is what the overlay and
  `AKShaderWaitPending` read. The overlay is deferred 2 s (137) so a cold start does not
  flash it and a 60 fps game is not interrupted for a normal compile. The lock is taken
  with `tryLock` in a loop that ticks (138), so this thread pumps (main) or polls
  (others) while another translation finishes. `@try/@finally` (139–166) repairs the lock
  and the waiter count on every exit. The cache is re-checked after the lock (140)
  because another thread may have finished this exact job. Directories are created
  (142–145), the guest bytes are written to `ShaderRequests/<key>.metallib` **atomically**
  (146) — the Mac must never see a partial file — and `shader-request.json` names the job
  (147–148) so the Mac polls one file rather than watching a directory. The wait loop
  (152–159) keeps waiting after an error marker and logs it once: resuming into a wrong
  shader is worse than not resuming. On exit the lock is released and, when the last
  waiter leaves, the overlay hides (164–165).
- 168–172: the Mac translation, if present, is wrapped, loaded through the original with
  the caller's error, logged and cached on success. On rejection it does **not** return
  early — it falls through so the guest still gets the system's own answer.
- 174–176: final fallback — the guest's own bytes through the original, with the
  system's error forwarded verbatim.
- 177–183: if even that fails, log, create `ShaderRequests/` and save the bytes — the
  capture half of the same mechanism, available without any wait flag.

### 1.5 `addDesktopProperties` (186–230)

Called for every device (line 191 also installs the presentation diagnostics, which cost
two `containsObject:` scans in a normal run). Lines 193–198 save and replace
`newLibraryWithData:error:` with `captureLibrary` on the device class, once per process.
Lines 199–201 install the three optional adapters: managed storage (its own gate),
the BC texture fallback (its own gate, `BCTextures.m:559`, `TOLKARA_BC_FALLBACK`) and
the trace (its own gate).

Lines 203–217 collect and log iPadOS's own answers for the five identity selectors
before overriding them — the `is*` values masked to 8 bits because a `BOOL` returned in a
wider register can carry garbage above bit 0. That log line is the evidence for what was
changed. Line 219 `BOOL mac = !--native-gpu-identity` keeps iPadOS's answers when the
comparison flag is set. Lines 220–229 add the selectors iOS does not have
(`location`, `locationNumber`) and replace the ones it does, **except**
`isDepth24Stencil8PixelFormatSupported`, which is a real capability query and is left to
iPadOS.

### 1.6 Observer API and entry points (231–271)

`MTLCopyAllDevicesWithObserver` (231–241) stores the copied handler in a token, keeps the
token in a synchronized set, and returns the system default device through our own
translated wrapper as a one-element array — an iPad has exactly one device.
`MTLRemoveDeviceObserver` (243–245) removes under the same lock.
`MTLCreateSystemDefaultDevice` (255–260) resolves the real symbol once with
`AKRealFunction(name, AK_METAL_PATH, wrapper)`, which refuses to return *our own* symbol —
the `wrapper` argument is the recursion guard — then calls and translates.
`MTLCopyAllDevices` (263–270) has no iPadOS 17 symbol, so it falls back to the default
device through our wrapper and returns `@[]` rather than nil on failure.

---

## 2. `Presentation.m` — 133 lines

Development-only. The header states the contract: normal execution stays native; the
sample flag also saves one GPU readback after rendering, before present.

Five originals are stored (12–16) — `nextDrawable`, the three `presentDrawable:`
variants, and `commit` — each with its own signature and previous IMP, because chaining
through the stored pointer (rather than re-sending the selector) lets another adapter hook
the same selector without recursion. Two counters (17), two `static char` association keys
(18–19) and two flags (20) follow. `AKFrameTiming` (21–41) is one object per layer,
attached by association, so two layers produce two independent series.

**`-presentedAt:` (27–40).** `time <= 0` returns immediately: Apple documents
`presentedTime` as 0 "if the drawable hasn't been presented or if its associated frame was
dropped", and a 0 read as a timestamp would produce a gigantic gap. `@synchronized(self)`
because the presented handler runs on a Metal-owned thread and frames may arrive on
different threads; the lock is per-object so layers never contend. The first sample seeds
the series. A time not greater than the previous one is ignored, which keeps the series
monotone without a reordering buffer. Then one subtraction and two counters, with
`gap > .05` counted separately as a *visibly* missed frame (three refreshes at 60 Hz) —
one number answers "was it smooth". The 5-second window (34–36) logs
`seconds/fps/max_gap/gaps_over_50ms`, where fps is computed from presentation timestamps,
so it measures **presented** frames, not frames the game asked for. Then the window
resets, so a slow patch is not hidden by an earlier fast one.

**`observedNextDrawable` (44–71), per acquired frame.** Line 46 sets
`framebufferOnly = NO` when capturing, before the drawable is obtained because the flag is
consulted at texture creation. Apple documents exactly why this matters and what it costs:
with `framebufferOnly` true the layer "allocates its MTLTexture objects with only the
renderTarget usage flag. Core Animation can then optimize the texture for display
purposes. However, you may not sample, read from, or write to those textures. To support
sampling and pixel read/write operations (**at a cost to performance**), set this value to
false." That is a one-way change to the guest's own layer and it changes the guest's
rendering cost — see the verdict below. Line 47 obtains the drawable and line 48 leaves a
nil exactly as nil. Line 49 numbers the frame with an atomic so no lock is needed on the
frame path. Line 50 logs at 1/60/600/1800 — one, ten and thirty seconds at 60 Hz — which
shows whether format or size changes later without a line per frame. Line 51 stamps the
drawable for capture and logs layer geometry. Lines 53–58 create the per-layer timing
object under `@synchronized(layer)`, because two threads may call `nextDrawable` on one
layer and a non-atomic association provides no safety. Line 61 adds the presented handler
— one block per frame, retained by the drawable until presented. Lines 66–68 mark the
variable used so a simulator build compiles clean under warnings-as-errors.

**Present wrappers (72–77).** `markCapture` attaches the drawable to the command buffer
through an association when the drawable carries a capture number; the three present
functions forward the exact arguments and return void.

**`observedCommit` (78–109), every commit in the process.** Line 79 is the whole cost of
the hook for a normal frame: one associated-object lookup returning nil. Only a captured
frame continues: frame number and render stats are logged (81–82), the marker is cleared
so a second present cannot capture twice (83), the row stride is rounded to a 256-byte
multiple (84–85) — required for texture→buffer copies on iOS GPUs and for the `CGImage`
below — and line 87 accepts only the two 32-bit BGRA formats, because the `CGImage` at 98
hard-codes that layout; skipping a capture beats mis-saving it. A `Shared` buffer of the
whole frame is allocated (88), a blit copies mip 0 slice 0 (90–92), and the CPU work
happens in a completion handler inside an autorelease pool (93) so the frame is not
stalled at commit: check status (94), copy to `NSData` (95), wrap in a `CGDataProvider`
(96), create the image with `byteOrder32Little|premultipliedFirst` = BGRA in memory (98),
write `Documents/native-frame-<n>.png` (99–101), release the CoreFoundation objects
(102), and clear the command buffer's association (106) because command buffers are
recycled and an uncleared association would keep a drawable alive and could mark a later
commit. Line 108 commits the guest's submission with our blit already part of it.

**Install (110–133).** `replace` returns nil for a missing selector and reuses the real
type encoding, so the signature cannot drift. Lines 116–117 read the two launch arguments;
**line 118 is the gate for the entire file**, and with neither argument nothing below can
happen. `dispatch_once` (119–120) because the function is called per device while the
hooks are process-wide. Line 122 replaces `nextDrawable` **on the class**, catching every
layer including ones created later. Line 125 stops measure-only mode before the
command-buffer hooks, so a measure run cannot read back a frame. Lines 126–127 discover the
private command-buffer class from one throwaway instance and install the render diagnostics
first, so the chain order of `commit` hooks is preserved. Lines 128–131 replace the three
present entry points and `commit`.

---

## 3. `MetalTrace.m` — 318 lines

Opt-in (`--trace-metal`); the invariant in its header is that nothing is changed and every
call reaches the original with the original arguments. `note` (20–27) dedupes successes into
one line per distinct kind (bounded at 1500) and caps failures at 800, and it logs **outside**
the lock, because `AKLog` writes a file and holding the lock across it would serialise every
Metal creation call in the process. `hashed`/`firstLine` (28–39) make a short stable name for a
saved source and keep every log record on one line (newlines become ` | `, 400-character cap).

The formatters (40–69) print exactly the fields that make a macOS creation invalid on
iPadOS: texture type/format/storage/usage/samples/mips/swizzle with the size **only on
failure**; every sampler field; all eight colour attachments of a render pipeline with a
`+blend` marker, plus function names, depth/stencil formats, sample count and
alpha-to-coverage; tile function and threadgroup size match.

`swap` (71–75) is the one place in the adapter where `class_replaceMethod` must be handled
carefully: it returns the **previous IMP** when it replaced, but **NULL when it added a
method to a class that only inherited it** — so the fallback to `method_getImplementation`
is what prevents a jump to NULL.

The hooks (86–247) cover texture, IOSurface texture, buffer, buffer-with-bytes, sampler,
depth-stencil, heap, library-from-source, render pipeline (sync and async), tile pipeline
(sync and async), compute pipeline (sync and async), compute-from-function, plus the
heap/buffer/library-side creations discovered by `watchBuffer`, `watchHeap`, `watchLibrary`.
Two details are worth the reading: the async variants format the descriptor **before** the
call because the caller may release it as soon as the method returns, and the
buffer-texture hook logs the *remainders* of offset and bytesPerRow against
`minimumLinearTextureAlignmentForPixelFormat:` — because misalignment is the usual reason
iPadOS returns nil for a linear texture, and a raw offset does not answer "is it aligned".

Installation (249–318) is gated at 292 **inside** a `dispatch_once`, so with the flag
absent nothing in the process is hooked. The 15-entry table covers every creation entry
point a guest can reach.

---

## 4. `ManagedStorage.m` — 100 lines

Opt-in (`--metal-managed-storage`): macOS's `Managed` storage mode becomes `Shared`, from
the device or from a heap, and `didModifyRange:` is answered as empty because on shared
memory the write is already visible. The header states what it does **not** cover: the blit
encoder's `synchronizeResource:`/`synchronizeTexture:slice:level:`, placement-heap creation
with an offset, and heaps of more than one class. The mapping itself lives in
`StorageModes.m` so every consumer agrees. `allowModifiedRange` (26–29) adds the method
with the literal encoding `v@:{_NSRange=QQ}` — a wrong encoding would corrupt the call
frame. `sharedTexture` (36–41) copies the descriptor only when the mode actually differs and
otherwise returns the same object. `createDeviceHeap` (53–65) also replaces the heap's own
creators once, because a heap's resources must match its storage mode. The gate at 92 wraps
every replacement, so a normal run has no hook at all.

---

## 5. `LibraryContainer.m` — 81 lines

`AKLocalMetalLibraryData` verifies a macOS metallib and returns a copy with the header
relabelled for iPadOS, or nil. Every check exists to make one claim safe: *only the header
changed*.

`number` (5–7) reads little-endian byte by byte because guest data is unaligned. `section`
(8–10) uses subtraction (`size <= length - offset`) so the test cannot overflow. `airMinor`
(14–20) maps container versions 2/3/5 → AIR 2.0/2.1/2.3 and 7/8 → AIR 2.6/2.7, and returns
−1 for anything unmeasured — nothing is guessed. Line 23 requires an 88-byte minimum, the
same 64 MB ceiling as the loader, and the exact magic. Line 33 requires the declared total
length to equal the data length: every offset is relative to a blob whose length the header
states, so a mismatch makes all of them untrustworthy. Line 34 accepts only **macOS**
containers of these versions (an iOS container is already correct and is returned untouched
as nil). Lines 35–42 check the four sections are inside the file, ordered and non-overlapping
— without that, the table walk could read another section's bytes as entries. Lines 45–76
walk every module: 4-byte tags, `ENDT` last with no trailing bytes, exactly one `HASH`
(32 bytes), `OFFT` (24), `MDSZ` (8) and `VERS` (8) — duplicates and wrong sizes are
rejected, unknown tags skipped by length. Line 67 ties the container version to the AIR
minor each module actually carries. Lines 70–73 prove the bytes about to be hashed are a
bitcode module (`0x0b17c0de`, `BC\xc0\xde`). Line 74–75 compares SHA-256 of the whole module
with the entry's hash: that is the integrity check that makes a relabel safe. Line 78 clears
the platform's high byte and sets `0x82` on device or `0x87` in the simulator, and line 79
sets the iOS major version for current containers only. Line 80 returns an immutable copy.

---

## 6. Per-frame cost — the verdict, with evidence

**A normal (unflagged) run: this adapter contributes nothing to the frame path.**
`AKInstallMetalPresentationDiagnostics` returns at `Presentation.m:118` unless
`--sample-native` or `--measure-native` is present (verified in source), so
`nextDrawable`, the three `presentDrawable:` variants and `commit` are Apple's own
implementations for the whole process. `MetalTrace` gates inside its `dispatch_once`
(292); `ManagedStorage` gates at 92; the BC fallback is installed unconditionally
(`Devices.m:200`) but gates internally at `BCTextures.m:559`. `Devices.m`'s work is
per library load and per device creation.

**A `--measure-native` run adds**, per acquired frame: one extra message send, one
atomic, one `@synchronized` and one associated-object lookup; per presented frame: one
block allocation (`addPresentedHandler:`, line 61), one atomic and one
`@synchronized`. That is not 14 ms, but it is not zero either — **the measurement that
produced the 14 ms figure was taken with this flag on and must be repeated with it off
before the layer is implicated.**

**A `--sample-native` run is not comparable to a normal one**, for two documented
reasons: `framebufferOnly = NO` (line 46) removes Core Animation's display-optimised
allocation and, in Apple's words, supports readback "at a cost to performance" — so the
guest's own rendering changes; and each captured frame carries a full-resolution
readback, buffer allocation, `NSData` copy and PNG encode.

**`--trace-metal` and `--metal-managed-storage` are contaminating** if a guest creates
resources per frame: a lock, a string hash and several `NSString` allocations per
creation in one, a descriptor copy per texture in the other.

## Sources

- `CAMetalLayer.framebufferOnly` — "allocates its MTLTexture objects with only the
  renderTarget usage flag. Core Animation can then optimize the texture for display
  purposes. However, you may not sample, read from, or write to those textures. To
  support sampling and pixel read/write operations (at a cost to performance), set this
  value to false." <https://developer.apple.com/documentation/quartzcore/cametallayer/framebufferonly>
- `CAMetalLayer.drawableSize` — "By default, a layer creates textures sized to match its
  content—that is, this property's value is the layer's bounds size multiplied by its
  contentsScale factor." <https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize>
- `MTLDrawable.presentedTime` — "The property value is 0.0 if the drawable hasn't been
  presented or if its associated frame was dropped."
  <https://developer.apple.com/documentation/metal/mtldrawable/presentedtime>
- `UIView.contentScaleFactor` — "The scale factor determines how content in the view is
  mapped from the logical coordinate space (measured in points) to the device coordinate
  space (measured in pixels)… if the scale factor is 2.0 and the view frame size is 50 x
  50 points, the size of the bitmap used to present that content is 100 x 100 pixels."
  <https://developer.apple.com/documentation/uikit/uiview/contentscalefactor>
- Source verified in this session: `Presentation.m:115–132` (the gate), `Presentation.m:78–80`
  (the commit hook's single lookup), `Devices.m:191–201` (install sites),
  `BCTextures.m:559` (the BC gate).
