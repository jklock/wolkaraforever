# Security, GameController and the shared headers

## `Security/Keychain.m` — 82 lines

A keychain adapter with no keychain in it: one path, one certificate store, one string that
stands in for a handle.

`marker()` (6) returns `@"Tolkara public system certificate source"` — the whole "handle".
It is a constant string, not a pointer into a store, and no call maps it to anything: **the
handle holds nothing, so it cannot be turned into access to anything.**

`AKLoadSystemCertificateCandidates` (7–20) refuses a file over 4 MiB before parsing (9),
requires an array of at most 1024 items each `NSData` of at most 64 KiB (11, 14), creates
each certificate with `SecCertificateCreateWithData` (15) — a structural check only, **no
trust decision** — and **aborts the whole load on any bad item** (16), so a partly good file
never becomes a partly trusted store. The result is published under
`@synchronized(NSProcessInfo.class)` (19).

`AKOpenSystemKeychain` (21–28) accepts **only**
`/System/Library/Keychains/SystemRootCertificates.keychain` (23); the login keychain, a file
path or a `..` traversal is `errSecUnimplemented`. That refusal is what makes the rest of the
file safe. A missing `CompatibilityRootCertificates.plist` (a `TOLKARA_SYSTEM_ROOTS=NO`
build) is `errSecNotAvailable` — an empty trust source, not a permissive one.

`AKCopySystemCertificates` (29–73) only claims a query once it has the marker (34–35); every
refusal after that stands. It requires exactly one keychain, `kSecClassCertificate`,
`kSecReturnRef` (37), refuses any key outside a six-key whitelist with `errSecUnimplemented`
(40) — so no `kSecValueData`, no `kSecReturnData`, no attributes, no access-control keys
— and accepts only a `SecSSL`/basic policy (45–50). Evaluation (56–68) uses
`SecPolicyCreateBasicX509` and **never calls `SecTrustSetAnchorCertificates`**: each root
must be accepted by the iPad's own trust store, and network fetch is disabled (65), so no
revocation data is fetched. The recorded measurement behind that choice is in the source
(52–55): evaluating a root as an SSL *server leaf* rejects most CAs — macOS selects 158
roots, the leaf test accepts three — so selection happens at packaging time and the runtime
check is the device's own trust of the root. Nothing matched is `errSecItemNotFound` (71);
no root is ever fabricated. Under `TARGET_OS_IPHONE` (74) the two names export, and an
unclaimed query goes to the platform's real `SecItemCopyMatching` (80) — which still
applies iOS access groups and entitlements; this adapter contributes nothing to that
decision.

`SystemRoots.h` (6) declares only those three functions: no `SecItemAdd`, `SecItemUpdate`,
`SecItemDelete`, `SecIdentityCopyPrivateKey` or `SecKeyCreate*` anywhere in the adapter.

## `Security/LegacyCrypto.c` (132) and `LegacyCrypto.h` (34)

The retired CDSA CSP over CommonCrypto: PBKDF2-HMAC-SHA1 and AES-CBC with PKCS#7.

Two `_Static_assert`s (10–11) pin the macOS key layout (76- and 96-byte structures, the data
pointer at offset 80) so a layout drift fails the build rather than misreading a guest
structure. `gGuidAppleCSP` (12) is the GUID the guest compares and every key is stamped
with; the error enum (13–14) carries macOS's values; `MAX_DATA` is 1 MiB (16).

`CSSM_Init`/`CSSM_ModuleLoad` (30–36) accept version 2.0 and the Apple CSP GUID and **no
callback** — a callback would be a way to be entered during an operation. `CSSM_ModuleAttach`
(37–43) requires the caller's `malloc_func`/`free_func`, so key bytes live in the guest's own
allocator; `CSSM_ModuleDetach` (44–49) **refuses while any context references the module**,
which is what prevents a live context holding a pointer to freed module memory.
`add_context` re-checks the module under the lock (52).

`CSSM_CSP_CreateDeriveKeyContext` (55–64) accepts only PBKDF2, AES, 128/192/256 bits, rounds
1…10 000 000, **no base key and no seed** — so no key wrapping and no derive-from-key — and
caps the rounds, which bounds both how long one call holds the global lock and how much CPU a
single request can buy. `CSSM_DeriveKey` (65–79) accepts only "give me the raw AES key
bytes, session, not permanent, not sensitive" (70 refuses any ACL, because an ACL is an
access-control promise this shim cannot enforce), allocates with the guest's allocator (73),
runs `CCKeyDerivationPBKDF` (75), **wipes the buffer on failure** (76) and returns the
macOS-shaped key (77). `CSSM_CSP_CreateSymmetricContext` (80–90) requires the key to look
like one this file produced and the header's bit count to equal the actual bytes × 8 (84–85)
— a header claiming 256 bits over 16 bytes is `KEY`, not reinterpreted — and **copies** the
key and IV into the context (88), so the caller may free its buffers.

`CSSM_DeleteContext` (91–94) wipes the context (key and IV) before freeing.
`CSSM_FreeKey` (95–100) **refuses a permanent key** (96) — nothing here writes to a keychain
or a file, so the honest answer is no — and wipes the caller's key bytes and structure.

`encrypt_decrypt` (101–132) requires exactly one input and one output fragment (103), takes
the global lock, allocates `input + 16` for the padding block (107) and calls `CCCrypt`
(108). On decrypt it **unpads by hand** (111–118) because on some OS versions CommonCrypto
accepts a zero padding length and would return the padding bytes as cleartext (109–110); the
padding check runs over all 16 bytes with a mask rather than stopping at the first wrong byte
(115), so timing does not depend on how much padding is right; and an invalid padding becomes
`DATA` **before anything is copied** (120), which is the difference between a padding oracle
and not. A NULL output buffer is allocated at exactly the plaintext size (123). The scratch
holding the plaintext is wiped and freed (127). Line 128 is one stderr line per decrypt,
status only — no key, no IV, no data — and it is per call.

`LegacyCrypto.h` declares the LP64 CDSA ABI the iPhoneOS SDK no longer ships, with the exact
arity of the macOS headers so the guest's calls bind by name.

## `Security/Session.c` (11) and `Session.h` (19)

`SessionGetInfo` accepts only `callerSecuritySession` or the shim's own id (7), echoes one
session, reports **exactly one attribute — graphic access** (9) — and succeeds.
`sessionIsRoot`, `sessionHasTTY` and `sessionIsRemote` are never set, and a caller naming any
other session gets `errSessionInvalidId`: a program cannot probe for a root, remote or TTY
session by asking. The header carries the macOS constants with their values and
`AKCallerSessionId = 100000` so the shim can tell its own id from the caller's.

## `GameController/GameController.m` — 78 lines

Deliberately a façade, and the header comments say why: the AppKit adapter links the real
framework for `GCMouse` raw input, and iOS then activates a legacy device session that reports
the host's keyboard and mouse — and in the simulator even a virtual MFi controller — posting
connect notifications macOS would only post for real hardware, which crashed one game
(6–7). So the shim stands alone: `+[GCController controllers]` returns a fresh empty array
(18), `+[GCController current]` returns nil (19), `GCDualSenseGamepad`/`GCDualShockGamepad`
exist as empty classes so a class lookup does not fail (22–30), and the eight notification
names are `AK`-prefixed (34–41) so nothing in the process ever posts them — an observer
registered for them never fires, as on a Mac with no controller. Product categories, haptic
localities, input names and paddles (44–77) carry their macOS values so keying and comparison
still work. The cost is stated plainly in the source (11): **real gamepads are hidden too**,
and it is opt-in behind `TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`.

## The shared headers

`AppKit/EventMonitors.h` (9) is the local-monitor interface: a block taking an event and
returning `id` (nil = consumed), a token, and `AKEventMonitorRun`. They are run from
`-[AKApplication sendEvent:]`, **inside the application's own delivery**, so a monitor sees
only what the application already receives. `AppKit/TouchControls.h` (27) is the on-screen
keyboard/trackpad: a delegate of six callbacks that *report* what a finger did, a stored
Boolean choosing whether it exists at all (iPhone yes, iPad no), and two safety decisions —
only the two buttons intercept hit testing, and hardware mouse input keeps its own path.
`AppKit/TouchTrackpad.h` (19) is the gesture state machine: four possible actions, direct
finger input only, coordinates in UIKit points, and **no inspection of the guest and no input
of its own**. `AppKit/WindowFullscreen.h` (16) declares the four public notifications and
`AKToggleFullscreenWindow`, with UIKit owning the geometry and the adapter completing the
AppKit transition inside it. `AppKit/Images.h` (44) declares `AKCreateCursorPath`
(`CF_RETURNS_RETAINED`, because the name is not an `alloc`/`copy`/`new` name), the bitmap and
image representations and the cursor. `AKSupport/TextInput.h` (7) is where `AKInterpretTextKey`
and `AKEnumerateTextKeys` are declared.

## Per-frame cost

**Nothing in any of these files runs per frame.** There is no display link, no repeating
timer, no render callback and no polling loop in `Security/`, `GameController/` or the
headers.

Worth knowing where it could bite:

| Entry point | Lines | Cost |
| --- | --- | --- |
| candidate trust evaluation | `Keychain.m:59–68` | up to 1024 `SecTrustEvaluateWithError` calls on the first query, network fetch disabled; results are **not** cached per certificate, so a second query re-evaluates |
| PBKDF2 | `LegacyCrypto.c:75` | up to 10 000 000 rounds **while holding the global lock**, so a long derivation serialises every other crypto call in the process |
| AES one-shot | `LegacyCrypto.c:101–130` | bounded at 1 MiB of input, one scratch allocation, also under the global lock |
| decrypt log | `LegacyCrypto.c:128` | one stderr line per decrypt |
| `+[GCController controllers]` | `GameController.m:18` | one autoreleased empty array per call |
| `AKTrackpadHold` | `TouchControls.m:179–184` | a **one-shot** timer re-armed per touch batch, invalidated by the next — never a repeating tick |
