# Implementation standards

These are shared engineering rules for every feature task. Feature-specific
plans and task lists live under `features/`.

## Working rules for every task

1. Create a worktree from current `origin/main`; name the branch `feature/...`
   or `fix/...` as the task says.  Never work on `main`.
2. Read `development/architecture/PROJECT_MAP.md`, the named task, and every
   named source/test file before editing.
3. Do not edit `platform/`.  Add/replace files only under `wolkaraforever/` and
   register every prepared-tree file in `wolkaraforever/overlay.map`; use a
   numbered patch only when the platform needs a hook.
4. Do not add game automation, guest-memory inspection, game add-ons that issue
   commands, custom CAPTCHA/login handling, credential copying, device IDs or
   test captures. The CurseForge browser may render normal site login/cookie/
   challenge pages inside WebKit; it must not automate or inspect them.
5. Add the focused test first when a defect can be reproduced.  Run the exact
   commands listed.  Report command, device, pass/fail and key failure only.
6. Stop and report—not improvise—if a required platform hook is unavailable, a
   product decision conflicts with this task, or the focused test shows that the
   claimed gap does not exist.

### Required start and finish protocol

At the start of every task, run and record `git status --short`, `git log -1
--oneline`, and `wolkaraforever/tools/check_layers.sh`. If the worktree is
already dirty for an unrelated reason, stop; do not absorb or discard another
change.

Before review, state in the PR Proof section: source SHA, task, changed files,
focused commands and outcomes on **both** iPhone Duo and iPad Pro 13-inch (M5),
interface mode, local live-QA observations, physical device/mode when used, and
missing proof. Generated validation reports, logs and screenshots stay local;
do not commit, attach, or link them. Clear them with
`wolkaraforever/tools/clear_validation_reports.sh` before handoff. Never say
"fixed", "fast", "no regression", or "works in game" without the named test
or Device Hub result. Use the repository What/Why/How/Proof/Risks PR format.

For UI work, create a `development/reviews/ui/` review record before code and
run the UI-policy checker. Preserve current launcher UI and approved baselines;
new named optional states need their own reviewed source baseline. Treat
`InterfaceMode`, `LayoutStore`, `TouchGamepadLayout`, `WolkaraRoue`, the current
Add-on Manager and the current three app localizations (English, German, French)
as existing behavior to extend, never silently replace.

### Decisions an execution agent may not make

- Do not change defaults fixed in `07-completion-spec.md`.
- Do not enable controller claiming by default, claim an entire controller, or
  hide a control from the game merely because it has a mapping.
- Do not auto-send Composer text, use partial recognition as text, or send on
  background, disconnect, or error.
- Do not hard-code a chat channel/destination; it stays absent or disabled until
  player-configured.
- Do not expand CurseForge/ForgeCDN download hosts, 128 MiB cap, archive
  extraction permissions, redirect policy, or WebKit-only credential boundary.
- Do not call logs a performance measurement. Timing must include sequence,
  enqueue/dequeue boundaries, and drop/overflow count.

### Exact validation meanings

- `wolkaraforever/tools/test_voice.sh` defaults to the iPad Pro 13-inch (M5)
  simulator. Rerun with `SIMULATOR=iphone` for every visible/interactive flow;
  Duo is not an optional regression check.
- `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` follows that
  simulator rule. `wolkaraforever/tools/test_touch_gamepad_ui.sh` owns touch
  gamepad changes.
- Run `wolkaraforever/tools/check_layers.sh` after every layer, `overlay.map`,
  or patch change. Run `wolkaraforever/tools/check_docs.sh` after documentation.
- Device Hub verification is manual, user-operated WolkaraForever UI testing;
  never gameplay automation. It is required to support a physical claim but is
  not a substitute for the required simulator matrix. Leave the physical iPad
  at the normal home screen with the app running when finished.

## Historical PR-cut detail — reference only

The feature-specific `features/*/TASKS.md` files are authoritative. This older
PR-cut breakdown is retained only to preserve rationale from the source audit;
it must not be used to skip, reorder, or override a feature task or completion
gate.

**Goal:** prove or disprove safe single-button physical-controller claim.

Read `wolkaraforever/Controller/ControllerInspector.{h,m}`,
`wolkaraforever/Input/{InputElement,InputInterest,InputRouter,Trigger}.{h,m}`,
the Controller Manager view/controller,
`wolkaraforever/Voice/{VoiceSettings,VoiceViewController}.{h,m}`, and
`wolkaraforever/Voice/tests/test_voice_app.m`. Add test-only claim plumbing for
one canonical controller button. It must suppress only that button before guest
delivery, leave every other button unchanged, restore on disconnect/background,
and expose no user UI or persistence.

Do not refactor diagnostics. Do not claim a button by filtering events after the
guest received them. Add fixture cases for claimed, unclaimed, disconnect,
background and unsupported controller. Run `wolkaraforever/tools/test_voice.sh`
and `wolkaraforever/tools/check_layers.sh`, then Device Hub only to verify one
user-operated button on the physical iPad. If claim cannot be proven safe,
remove the spike code and deliver only the test/evidence document. The only
allowed conclusion is `safe hook found` or `no safe hook found`; do not turn the
spike into a shipping preference.

## PR 2 — `feature/controller-command-ingress`

**Goal:** create measured, bounded ingress without changing default behavior.

Add `Input/ControllerCommandIngress.*`; map it in `overlay.map`.  Reuse canonical
elements from `InputElement.*`.  Accept only claimed/mapped button edges, assign
sequence numbers, use a bounded FIFO, and schedule one main-queue drain.  Axes,
d-pads and repeated held samples never enter it.  Keep `InputRouter` as the
consumer so behavior mirrors current triggers.  Add counters and timing only;
do not change Voice UI or claims.

Test FIFO order, duplicate suppression, axis rejection, overflow verdict and
one scheduled drain.  Run `test_voice.sh`, the focused new test, and
`check_layers.sh`.  Do not claim p95 values until physical measurement exists.

## PR 3 — `feature/controller-composer-claim`

**Goal:** expose the proven claim from PR 1 as an opt-in setting.

Only after PR 1 proved a safe hook, add versioned per-device claim persistence
to `VoiceSettings.*`, UI to `VoiceViewController.m`, localized strings, migration
defaulting every existing mapping to listen-only, and immediate restore on every
lifecycle exit.  The unavailable route must render a non-interactive explanation.
Never silently claim a previously mapped control.

Test migration, settings toggle, route failure, disconnect, background and
feature disable.  Run `test_voice.sh`, launcher UI fixture, layer check, then
Device Hub claimed/unclaimed proof.

## PR 4 — `feature/chat-composer-core`

**Goal:** build a reviewable native draft state machine; do not change mapped
controller entry or default delivery yet.

Create `Chat/ChatComposer.*` with states and generation checks exactly as in
`02-chat-composer.md`.  Integrate it into `TouchControls` using the existing
`AKKeyboardTextView`; retain `Dictation` audio/recognition ownership.  Implement
Open, partial/final draft update, edit-pauses-capture, Cancel, background and
failure.  Do not inject guest text in this PR.

Test every state transition and stale callback.  Run `test_voice.sh`,
`test_touch_controls_ui.sh --self-test`, and layer check.

## PR 5 — `feature/chat-composer-controller-entry`

**Goal:** have the controller ingress open Composer exactly once.

Wire only the existing router trigger callback to Composer Open.  Preserve
hold/toggle semantics.  Do not change claim default, speech language, Send or
guest injection.  Instrument callback-to-visible timing.  Prove repeated down
samples make one Composer and release does not create another.

Run PR 2 tests plus voice/touch tests.  On the physical iPad capture the stated
timing boundaries with diagnostics off and bounded trace; report measured values
or report that device proof is pending.

## PR 6 — `feature/chat-composer-send`

**Goal:** implement explicit Send/Cancel and configurable destinations.

Add validated config records and localized Composer controls.  Send must
invalidate callbacks, inject text once, Return once, Escape once only when
Composer owns chat; failure retains draft and never retries.  Cancel sends no
text and at most one Escape.  Start with at most four disabled-by-default,
user-configured destinations; no hard-coded channels.

Test exact key/insertion sequence, empty text, control stripping, duplicate Send,
late final, Cancel/background and invalid records.  Run voice/touch/config tests
and Device Hub Send/Cancel proof.

## PR 7 — `feature/composer-speech-language`

**Goal:** add explicit speech language without changing privacy guarantees.

Add only System, en-US, de-DE and supported game text locale choices.  Validate
before persist; create recognizer per session; cancel/invalidate old generation
before restart; never reopen chat.  Add task hint/punctuation only behind SDK
availability checks.  Keep on-device recognition mandatory.

Test migration, unsupported locale, request construction, mid-capture change and
stale callbacks.  Run voice suite and physical one-language-switch proof.

## PR 8 — `fix/committed-unicode-input`

**Goal:** prove and repair guest committed Unicode delivery.

First add the fixture for accent, combining mark, ñ, ü, emoji, deletion, cancelled
composition and Return.  If it passes end to end, stop: document no code gap.  If
it fails, add the smallest adapter seam that delivers committed strings while
keeping special keys explicit.  Do not inspect guest selection/text or emit fake
keycodes.  Run touch controls and translation simulation plus Device Hub manual
composition proof.

## PR 9 — `feature/touch-controller-2`

**Goal:** Full/Simple layout, L3/R3 and direct-camera reliability as one migration.

Version `AKGamepadLayout`; migrate existing values to Full; keep Simple opt-in;
give Simple independent shoulders.  Add optional-off L3/R3 double taps that fail
on drag threshold and release on every lifecycle path.  Add ability groups only
as explicit virtual-controller events.  Run touch fixtures, translation suite,
and physical Device Hub gesture proof.

## PR 10 — `feature/addon-hub`

**Goal:** default native Add-on Hub with browser/API/Files acquisition.

Create native My Add-ons first, unifying every local package by normalized record
and update state. Add native Discover/Browse behind available API metadata; use
the browser as no-key acquisition only. Accept CurseForge/ForgeCDN HTTPS ZIPs
under 128 MiB with redirect/MIME/body checks, digest/provenance and one archive
transaction. WebKit owns normal site login/cookies/challenges; never scrape,
automate, copy or handle credentials. Add large-TOC fixtures. Run archive,
launcher and UI tests plus Device Hub mixed-provider proof.

## PR 11 — `fix/reliability-recovery`

**Goal:** ship only reproduced storage, enrollment, manifest or startup fixes.

Make one PR per reproduced item from phase 5.  Add the failing fixture first,
implement idempotent fail-closed recovery, then run its owning suite and layer
check.  Never combine authorization, updater and runtime changes.

This is deliberately not executable until there is a failing case. Before code,
name the exact symptom, current reproducer, owning module, and affected user
data. If one is unknown, create no code PR: add only a diagnostic plan and ask
the maintainer which failure to prioritize.

## PR 12 — `fix/inactive-metal-submission`

**Goal:** only after a reproduction, pause unsafe inactive Metal submission.

Keep foreground pacing unchanged.  Preserve caller-owned pending work, resume once
on foreground, bound error records, and do not promise background execution.
Run focused background/Metal fixture, translation simulation and coordinated
physical evidence.

## Review gate for every implementation PR

Reject the PR unless every answer is explicit:

1. Which task is this, and did the diff stay within it?
2. Which current behavior remains unchanged by default?
3. What event/message remains native-only, and what is never sent to the game?
4. Which focused tests prove ordering, lifecycle cleanup, and failure behavior?
5. For user-visible in-game claims, where is physical-iPad Device Hub evidence?
   If absent, is the PR labelled simulator/source evidence only?
6. Is the rollback flag/config named, default-off where required, and proven to
   restore normal controller/input behavior?
