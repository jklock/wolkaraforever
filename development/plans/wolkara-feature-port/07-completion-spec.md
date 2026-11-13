# Completion specification

This fills in the product decisions needed to execute the phase plans.  Values
labelled **target** are acceptance limits, not claimed measurements.

## Performance contract

Before changing behavior, add timing and capture a baseline on each required
simulator in the applicable interface mode. Add physical-iPad timing only when a
real controller route is available; do not invent a before value or call
simulator timing physical proof.

| Metric | Target | Measurement boundary |
| --- | --- | --- |
| Controller callback → Composer visible | p95 ≤ 50 ms, max ≤ 100 ms | physical button callback to native Composer state update |
| Callback → voice capture started | p95 ≤ 150 ms, max ≤ 300 ms | excludes speech recognition time |
| Command mailbox overflow | 0 | any overflow is a failed run |
| Unmapped input command work | 0 mailbox admissions | 60-second normal play trace |
| Claimed press/release ordering | 100% | one down/up each, no stuck claim |

Run baseline and final checks on iPhone Duo and iPad Pro 13-inch (M5), including
the applicable `InterfaceMode`. If physical iPad measurement is available, run
it in developer-service mode with diagnostics off and then bounded trace on.
Record game state, mapped button, feature flags and source SHA. Speech
recognition latency is reported separately: it depends on utterance length and
must never be used to excuse routing latency.

## Product decisions

### Composer

- Entry points: toolbar microphone, mapped controller button, and keyboard
  microphone.  All open the same Composer.
- Default for new Composer users: **Review then Send**.  Existing auto-submit
  users remain in **Classic direct** until they opt in.
- Send buttons: **Send**, **Cancel**, and up to four user-configured destinations.
  Destinations are disabled until configured.
- Composer opens chat with Return, presents native draft, then Send injects text,
  Return, Escape.  Cancel sends Escape only if Composer opened chat.
- If text injection fails, retain the draft and show “Message was not sent.”
  Never retry automatically.

### Controller claim

- Default: Listen only.  Mapping does not change the game until a player turns
  on **Use this button for Composer**.
- Settings row: `Mapped button: <name>` and a switch labelled `Keep this button
  out of the game while Composer is enabled`.
- If the current route cannot claim the button, show `This controller cannot
  claim this button yet`; do not show a switch that does nothing.
- Disable, disconnect, background, route failure and app exit restore normal
  guest delivery immediately.

### Speech

- Speech language options: System, English (US), German (Germany), French
  (France), and the current game text locale when it is supported. Initial
  default: System.
- On-device recognition remains required.  Unsupported language shows a local
  error and leaves prior setting unchanged.
- Dictation task hint/punctuation are enabled only where the iOS SDK supports
  them; recognition still requires explicit Send in review mode.

### Keyboard and touch

- Composer is the only route that owns editable marked text.  Guest key events
  get committed text only.
- Touch Controller 2 default remains existing Full layout.  Simple is opt-in.
- L3/R3 double-tap is off by default.  Ability zones are off by default and
  cannot issue more than the virtual-controller press/release caused by a touch.

### Add-on Hub and acquisition

- Default screen: native **My Add-ons**, with all API, browser, Files and
  pre-existing unmanaged packages in one first-class catalog. It has native
  search, sort/filter, Refresh, per-row update state and Update all.
- Native **Discover** and **Browse** use API metadata when an API key is present.
  Without a key, **Browse CurseForge** opens the browser only as a no-key
  discovery/download route; it never replaces the native home/list screen.
- Alternate providers: **Use API key** opens the existing API-backed flow; Files
  import remains independent. Existing API-provider records keep working.
- Normal site login, cookies and challenge pages are allowed only inside WebKit.
  WolkaraForever neither reads/copies credentials nor automates/bypasses a site
  flow.
- A download must be HTTPS, have no embedded credentials, and remain within
  `curseforge.com`/subdomains or `forgecdn.net`/subdomains across every redirect.
  Accept only 2xx ZIP responses. Enforce 128 MiB during receipt, then use the
  same archive validation/staged transaction as API and Files.
- A package with unknown source identity remains managed and fully usable, but
  has `Update unavailable until linked to a CurseForge project`; never guess an
  update by matching its display name.

## Concrete persistence shapes

Store these in `wolkaraforever-config.json` through `WolkaraForeverConfig`, with
`version: 1` and strict limits.

```json
{
  "chat": {
    "deliveryMode": "review",
    "speechLanguage": "system",
    "destinations": [
      { "id": "say", "title": "Say", "command": "/say", "enabled": true }
    ]
  },
  "controllerClaims": {
    "vendor-product-id": { "element": "controller.button.share", "claimed": true }
  }
}
```

- Destination maximum: 4; title 24 visible characters; command 64 characters;
  printable text plus one leading `/`; duplicate IDs/commands rejected.
- Claim record must name one canonical controller button and boolean claim.
- Invalid child record is dropped; valid siblings remain.  Unknown future fields
  are retained by the config codec where it already supports that, otherwise
  ignored safely.
- Existing settings migrate to `deliveryMode: classicDirect`, `speechLanguage:
  system`, no destinations, no claims.  Downgrade leaves unknown keys harmless.

## Minimal UX layout

The Composer is a compact bottom-safe-area card above the keyboard:

```text
 [ Listening / Ready to send / Error ]
 [ editable draft                         ]
 [ Cancel ] [ destination chips ] [ Send ]
```

The Voice page owns preferences: mapping, claim, delivery mode, speech language
and custom words. The Add-ons page owns provider selection; it never places web
provider setup in a generic settings page. All labels have English/German/French
keys before UI code is considered complete. UI additions preserve the approved
launcher contract and carry their own UI-review record/baseline where required.

## Feasibility spike: controller claim

**PR 1 is a spike, not a release feature.** Implement a test-only claim for one
known physical controller button through the current Controller Manager/virtual
controller seam.  Prove on the simulator fixture that it prevents the guest key
while preserving every other button and releases on disconnect.  On the physical
iPad, Device Hub verifies only the user-operated button behavior.  If that route
cannot safely claim one button, ship Composer listen-only and keep claim work
separate; do not intercept broad controller input as a workaround.

## PR cuts

| PR | Scope | Proof |
| --- | --- | --- |
| 1 | Controller timing + test-only claim spike | controller fixture, Device Hub baseline |
| 2 | Command ingress/mailbox, no behavior default change | router ordering/overflow tests |
| 3 | User controller claim preference | migration/disconnect/restore tests |
| 4 | Composer state machine and native draft, toolbar entry | voice/touch state tests |
| 5 | Mapped-controller Composer entry | phase-1 timing targets on device |
| 6 | Composer Send/Cancel and destination records | exactly-once injection tests |
| 7 | Speech language and request quality | locale/stale-callback tests |
| 8 | Committed Unicode guest path | composition fixture + Device Hub |
| 9 | Simple layout/L3-R3/direct-camera work | touch suites + device interaction |
| 10 | Web provider and large TOCs | loopback provider/archive suites |
| 11 | Storage/enrollment/launch recovery | owning focused suites |
| 12 | Inactive Metal only if reproduced | targeted background fixture/device evidence |

## Manual Device Hub scripts

### Controller/Composer

1. Map one controller button; capture timing with diagnostics off.
2. Enable claim; press/release once while the game is active; confirm Composer
   opens and the game does not receive that control.
3. Speak, edit draft, Send; confirm one message action.  Repeat Cancel; confirm
   no message action.  Disconnect controller during capture; confirm no stuck
   input or send.

### Keyboard/speech

1. Enter `é`, combining accent, `ñ`, `ü` and emoji into the Composer.
2. Change language during capture; confirm the old callback cannot alter draft.
3. Background and return; confirm draft recovery or explicit cancellation, never
   an automatic send.

### Add-ons/reliability

1. Browse and install a harmless add-on through CurseForge without an API key;
   compare digest and managed record.
2. Switch to API-key mode and install/inspect one provider result; confirm My
   Add-ons remains the default screen and both installs have the same row/actions.
3. Cancel an oversized/invalid browser download; confirm existing package remains.
3. Exercise the specific recovery fixture before device install; do not alter
   user game data merely to create a failure.

## Rollback

Composer, command ingress and claims each have independent saved feature flags.
Turning a flag off cancels Composer, restores controller delivery, clears only
ephemeral drafts and leaves mappings/destinations for later re-enable.  Web
provider can be disabled without touching managed packages.  A release issue
therefore has a safe user-visible exit without uninstalling the app or changing
game data.
