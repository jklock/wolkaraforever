# Audio adapters

| File | Lines | Role |
| --- | ---: | --- |
| `AudioToolbox/Output.m` | 136 | the AudioUnit output path: component lookup with `ahal`→`rioc`, the device and render-callback properties, the render probe |
| `AudioUnit/ldflags` | 1 | the whole AudioUnit adapter: one linker flag re-exporting the AudioToolbox adapter |
| `CoreAudio/Hardware.m` | 143 | the legacy `AudioHardware*`/`AudioDevice*` API and the `AudioObject*` property API, answered from `AVAudioSession` |

## `AudioUnit/ldflags`

One line: `-Wl,-reexport_library,{outdir}/akAudioToolbox.dylib`. On iPadOS
`AudioUnit.framework` has no library image — every AudioUnit entry point lives in
AudioToolbox — so re-exporting puts that adapter's symbols into this library's export
table. That is how one hand-written file set serves two library names without a second
copy of the code. There is no source in the directory; `build_shims.py` treats a directory
containing only `ldflags` as a real adapter and builds the re-exported dependency first.

## `AudioToolbox/Output.m` — 136 lines

**Shape:** imports (1–5), the probe object (6–12), its registry and 5-second reporter
(13–29), the render-callback wrapper (30–42), a `dlsym` helper (43–47), two predicates
(48–58), then six wrappers (59–136).

### The probe (6–42)

`AKAudioRenderProbe` (6–12) holds the guest's `AURenderCallbackStruct` verbatim (`8`) and
five `atomic_uint_fast64_t` counters (`9`) — `uint_fast64_t` because at 48 kHz a 32-bit
frame counter overflows in 24.8 hours, and an iPad session can outlive that. The fields are
`@public` (7) so the C render callback can read them without a message send. The registry
(13) maps unit pointer → its probes, keyed by unit because disposal receives exactly that
pointer.

`prepareProbes` (14–29) creates the registry and, once per process, a
`DISPATCH_SOURCE_TYPE_TIMER` on a **`QOS_CLASS_UTILITY`** global queue (`19`) — deliberately
below the audio and render QoS classes, so measuring the audio path cannot preempt it —
firing every 5 s with 1 s of leeway (`20`) so the kernel may coalesce the wakeup. Its handler
copies the probe arrays **under the lock** and then logs outside it (22–25), so a probe added
mid-report cannot mutate a collection being enumerated, and the file's only lock is never
held across a `write(2)`. `dispatch_resume` (29) is required: a timer source is created
suspended and silently never fires otherwise.

`observeRender` (30–42) is the only code in the file on the render thread, and it is written
for that: `__bridge` cast (31), the guest's callback **first** with the guest's own refcon
(32), then three relaxed atomics on the common path (33, 34, 39) and two conditional ones
(35, 36); the byte scan (37–39) runs only when the callback claimed success and there is a
buffer list, per buffer, stopping at the first non-zero byte, with `mData` null-checked. The
guest's status is returned unchanged (40).

### The predicates (48–58)

`remoteOutput` (48–52) is the gate every special case hangs on: the unit must be type
`'auou'` **and** subtype `'rioc'`, so an output unit of another subtype gets no
translation. `defaultOutput` (53–58) obtains the one accepted device ID **through the same
`AudioHardwareGetProperty` the guest itself uses**, so the two shims agree numerically by
construction; no function or no route is `kAudioUnitErr_InvalidPropertyValue`, never an
invented ID.

### The six wrappers (59–136)

`AudioComponentFindNext` (59–72): `'ahal'` (AUHAL, the desktop HAL output) and `'def '`
(the default output request) are the desktop spelling of "the machine's speakers", which on
iPadOS is RemoteIO — so the **copy** of the description has only its subtype rewritten
(62–64). Before the component is found, the session is set to Playback and activated (66),
because RemoteIO's stream format and route are only concrete once the session is; the `&&`
short-circuits so activation is never attempted after a category failure, which would
succeed and then behave wrongly for the whole session. Playback rather than Ambient is
deliberate: a desktop game expects its audio to survive the silent switch and not be ducked.
Line 70 logs the request *and* the mapped subtype.

`AudioComponentInstanceNew` (73–76) logs only the status, because a failed creation must be
visible as such rather than as a later "property not set".

`AudioUnitSetProperty` (77–103) has three exclusive branches. Device selection (82–85): a
`UInt32` device ID is accepted **only when it is the default output device** — RemoteIO has
no device selection, the route comes from the session, and honouring an arbitrary ID would
be a lie a desktop client would then rely on. Render callback (86–96): every condition is
load-bearing (property, Input scope, element 0, exact struct size, RemoteIO), a probe is
created and the guest's struct copied **here, not on the render thread** (87), and the
observer is installed in place of the guest's callback (89, 95); clearing the callback
(`inputProc == NULL`) goes straight through so the guest can stop its own render. Everything
else passes through (97). Stream format is logged on the way past (98–100).

`AudioUnitGetProperty` (104–122) is the read half: the device (108–110) with the caller's
capacity checked before writing, and the stream format (112–117), where an **unspecified
rate** (`mSampleRate == 0`) is replaced by the session's — only when the session has a
concrete one, so a real answer is never overwritten.

`AudioUnitInitialize` (123–125) and `AudioOutputUnitStart` (126–131) pass through and log;
start logs *after* the call, and then records the actual route and session figures — after
the session is active and the unit started, which is the only moment the route is real.

`AudioComponentInstanceDispose` (132–136) drops the unit's probes only when disposal
succeeded, because a failed dispose leaves a unit whose callback may still fire. A guest
that never disposes leaks one small object and one dictionary entry, which costs nothing.

## `CoreAudio/Hardware.m` — 143 lines

Two APIs answer the same question — *what is the one output device* — from
`AVAudioSession`, because iPadOS answers neither usefully. `AudioDeviceID` and the
listener signature are redeclared (6–7) because the legacy types do not exist in the iOS
SDK; `defaultOutputDevice` (8) is `_Atomic(UInt32)` and zero means "not yet known".

`outputName` (9–15) repairs the session **only when** category, rate or route is wrong
(11–12) — so the common path is three property reads and no mutation — and returns the
first output's `portName`. Because it can call `setCategory:`/`setActive:`, it must never be
reached from a render path, and it is not.

`copyName` (16–22) takes the caller's **original capacity** (threaded from line 59, because
the native call may rewrite `*size`), writes the required size unconditionally first (19) —
the API's documented two-step pattern — and NUL-terminates at exactly `bytes.length` (21).

`report` (28–32) caps itself at 64 lines per process (30), so a driver that enumerates
devices in a burst cannot put a global lock and a `write(2)` on thousands of lines, and it
prints property IDs as four-character codes (31) rather than five-digit numbers.

`AudioHardwareGetProperty` (37–42) is the **only writer** of `defaultOutputDevice`: the ID
comes from the system, so a guest's later device calls compare against the number it was
itself given.

`AudioDeviceGetPropertyInfo`/`AudioDeviceGetProperty` (47–73) are where the file's subtlest
rule lives: the name is emulated **only when the system failed** (`s &&`), because
overriding a successful answer would be gratuitous — but `'nsrt'` (nominal rate) and
`'fsz#'` (buffer frames) are overridden **unconditionally**, because iPadOS *succeeds* on
them while returning a zero rate: a success with useless data. The frames figure is
`llround(rate × IOBufferDuration)` (65), not a truncation, because `48000 × 0.021333…` must
come out as `1024` and truncating `1023.9999` would report a buffer one frame short of the
one actually used. Measured: `audio route nominal_rate=48000 buffer_frames=1024`, and the
render callback then delivered exactly 1024 frames per call — the cross-check that the
arithmetic is right.

The property API (79–143) answers a fixed table (`answeredSize`, 95–108) and delegates
everything else: the system object answers `'dOut'` and `'dev#'`; the device object answers
`'slay'` (stream list, size computed as `offsetof(AudioBufferList, mBuffers)` plus one
`AudioBuffer` for output and nothing for input), `'lnam'` and `'uid '` (`CFStringRef`),
`'nsrt'`, `'ltnc'`, and `'stm#'` as `UINT32_MAX` — a sentinel meaning "present and empty",
because a real 0 would be indistinguishable from "the system answers". `'uidd'` with the
qualifier `@"TolkaraOutput"` translates the stable UID back into the numeric ID (117–118),
which is what lets a guest re-find the device after a relaunch. The session values are
clamped where a zero would be harmful: `MAX(outputNumberOfChannels, 1)` (130) and a 48 kHz
fallback (133–134). `AudioObjectSetPropertyData` (139–143) answers success for a volume set
on our device without writing anything: the route's volume belongs to the user, and a
well-behaved client that gets an error here often aborts playback.

## Per-buffer cost — measured

The wrapper is installed at `Output.m:86–95` (the log confirms `property=23 scope=1
element=0 size=16`), so `observeRender` runs on the guest's own callback slot.

| Cost | Lines | Per buffer |
| --- | --- | --- |
| Allocations | none | only at install (`87`, `92`) |
| Locks | none | `@synchronized(renderProbes)` is at `23`, `90`, `134` only |
| Message sends | none | `__bridge`, one indirect C call, `atomic_*` builtins |
| I/O | none | `AKLogC` is unbuffered stderr and is called from the utility queue, never here |
| Atomic RMW | 33, 34, 39 | 3 per non-silent buffer; `35`/`36` were 0 in the run |
| Byte scan | 39 | stops at the first non-zero byte |

Measured configuration: 48 000 Hz, `'lpcm'` float32 interleaved stereo, 8 bytes per frame,
**1024 frames** (8192 bytes) per callback, 21.333 ms period, 46.9 callbacks/s, and
`nonzero_buffers == calls` on every one of 17 five-second reports — so the byte loop always
exited on its first bytes. Worst case, a fully silent buffer, is 8192 loads ≈ 2–3 µs ≈
0.013 % of the 21.333 ms period.

The reporter runs at utility QoS with 1 s leeway and takes a lock the render path never
takes, so the render thread can never wait on it; the only sharing left is one cache-line
transfer per probe per 5 s.

The expensive audio work is `setCategory:`/`setActive:` and the session reads — synchronous,
millisecond-scale, and reachable only from the guest's configuration thread. In the measured
session the entire bring-up (component find, instance, `EnableIO` ×2, device, format query
and set, layout, initialise, start) took ~6 ms, after which the session was never touched
again.
