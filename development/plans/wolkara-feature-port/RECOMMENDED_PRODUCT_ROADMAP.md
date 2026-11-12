# Recommended product roadmap from the Wolkara audit

The source is inspiration, not an integration target.  The question is not which
commits to merge; it is which player outcomes WolkaraForever should own, using
its existing product architecture where that is stronger.

## 1. Make in-game communication a first-class feature

Build one product-owned **Chat Composer** that joins keyboard, controller trigger,
dictation and sending.  This replaces the current split between a native draft,
a direct speech-to-target path and an input router.

### Required behavior

- A mapped controller button opens an owned native draft immediately, without
  requiring the game chat field already to be open.
- Dictation streams/reviews into that draft, with on-device-only recognition,
  final-result safety and a visible failure state.
- Send is explicit.  It performs exactly one open-chat, insert, Return and
  close-chat sequence; Cancel never sends.  Late recognizer callbacks cannot
  change or submit a newer draft.
- Optional, disabled-by-default destination buttons are user-configured command
  strings (for example `/say`, `/p`, or a custom macro command).  Do not hard-code
  channel numbers, colors, or bindings.
- Speech language is its own persisted setting, seeded from the game text locale
  only when supported.  It must be changeable mid-draft without opening or
  closing chat a second time.
- Keyboard composition must preserve Unicode, IME marked text, deletion and
  emoji through the actual game-text route.

### Why this is the top priority

It takes the source's best usability idea—the reviewed chat lifecycle—and combines
it with Forever's stronger on-device/final-only speech and native keyboard fallback.
It solves where text lands, which is separate from speech accuracy.

## 2. Separate controller data-plane performance from UI and diagnostics

Treat mapped input as a real-time data plane.  The current controller inspector
was designed for correctness and observability; it must not be the mandatory hot
path for a gameplay command.

### Build

- A low-allocation routing fast path for only claimed/mapped elements, with no
  log write, UI update, string construction or main-queue hop before the action
  is recorded.
- A bounded mailbox from GameController callbacks to the main/UI owner.  It must
  preserve press/release ordering for a mapped button while coalescing axes.
- End-to-end timing: callback arrival, router decision, chat-composer open,
  microphone/listening, final transcript and text injection.  Report p50/p95/p99
  separately; do not call a display-link proxy input latency.
- A normal-play diagnostic mode that is off by default and cannot enqueue every
  stick motion.  Keep full tracing as an explicit short capture only.
- Controller Manager integration so a user can explicitly claim a mapped
  controller control from the game.  The current keyboard-only ownership rule is
  not adequate for push-to-talk.  Claimed controls need a visible per-controller
  choice and an immediate restore path.

### Why

The latest captured session has 4,205 raw input lines and no mapped-trigger
events; it does not measure the reported press.  It does prove the old class of
failure is possible: diagnostic input work can saturate the main queue.  This
work creates the measurement and removes that structural risk.

## 3. Improve touch and controller play deliberately

Build these as a coherent **Touch Controller 2** feature rather than importing
isolated source files:

- Full and Simple layouts with independently saved shoulder positions/defaults.
- Double-tap stick buttons (L3/R3), with configurable gesture zones and no delay
  to ordinary camera/stick movement.
- Editable ability zones and modifier groups, if they remain user-triggered
  controller input rather than a game automation add-on.
- Direct-camera drag state that cannot be overwritten by cursor recentering,
  repeated drags or an edit gesture.
- Physical-controller routing/claiming integrated with the Composer above.

Do not ship a game add-on that issues commands or automates play.  The usable
ideas are native input ergonomics, not game-side automation.

## 4. Make a native Add-on Hub the default

Adopt the CurseForge interaction model: native My Add-ons, Discover and Browse.
Use the source's normal browser/download implementation for no-key acquisition;
keep the existing Core API provider as an explicit API-key alternative rather
than deleting it.

- My Add-ons unifies API, browser, Files and existing unmanaged packages. Every
  package has local management; unknown source identity means explicit update
  unavailability, not a second-class/hidden record.
- The player browses and clicks the public site in `WKWebView` only when using
  the no-key acquisition route; site login,
  cookies and challenge pages remain WebKit-owned, never app-handled.
- Accept only 128 MiB-or-smaller ZIP downloads over HTTPS from CurseForge/ForgeCDN
  hosts across every redirect; no page scraping or login/challenge automation.
- Reuse the existing archive validation, size caps, staging, update lock, managed
  package records, rollback and recovery; provider choice must not bypass them.
- Preserve API-key native catalog/search for users who configure a key.
- Add serial mutation coordination only if the existing store can demonstrate a
  concurrent-install invariant failure.
- Add bounded large-TOC metadata reading, preserving complete add-on files.

## 5. Finish the reliability backlog

These are small, high-value, independently shippable improvements:

- Reclaimable iPad storage is already covered; do not create work for it unless a
  new failing updater case appears.
- Recover a valid existing developer enrollment reference after reinstall.
- Service scene/lifecycle changes while native startup is sleeping; protect
  rotation, resize and fold/unfold.
- Verify/repair missing bootstrap manifests and stale update artifacts before
  launch, only where the current recovery path demonstrably misses them.
- Pause unsafe Metal submission while inactive only if a focused reproduction
  proves the current background pacing is insufficient.

## Delivery order

1. Controller fast path plus end-to-end instrumentation; measure the reported
   mapped-button lag on the physical iPad.
2. Chat Composer with controller trigger, keyboard composition and reviewed send.
3. Voice language, destination buttons and provider selection.
4. Touch Controller 2.
5. Reliability items as independent small PRs.

Every item needs a product-owned focused test, the permitted simulator matrix,
and Device Hub evidence for live input/launcher claims.  None is a license to
change game code, automate play, inspect gameplay memory or bypass provider or
execution security controls.
