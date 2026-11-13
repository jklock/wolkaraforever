# Chat Composer: one owner for an in-game message

Status: implemented; unit and in-game fixtures pass on both matrix simulators (iPhone Duo and
iPad Pro 13-inch (M5)). Physical-iPad Device Hub status is recorded in the pull request; where it
was not run, the pull request says so.

## Why it exists

Three asynchronous systems meet at one line of chat: UIKit's text and IME, the on-device
recogniser, and the guest's own key events. Before the Composer each owned a piece of the
lifecycle, so a final transcript could arrive after the text - and the Return - had already gone
to the game. The old path also assumed an already-registered guest text view, and typed straight
into it.

The Composer makes ownership explicit:

- the native card owns the editable draft;
- the guest sees committed text only, exactly once, after **Send**;
- every capture carries a generation, and a callback from an older generation is ignored before
  it can touch the draft or the game.

## Where the code is

| Layer file | Prepared-tree path | What it is |
| --- | --- | --- |
| `wolkaraforever/Chat/ChatComposer.{h,m}` | `translation/AppKit/ChatComposer.{h,m}` | the state machine, the send transaction, the destination store |
| `wolkaraforever/Touch/TouchControls.{h,m}` | `translation/AppKit/TouchControls.m` | the card, its buttons, the draft editor, the guest's keys |
| `wolkaraforever/Voice/Dictation.{h,m}` | `launcher/Voice/Dictation.m` | capture, with a Composer client that replaces direct delivery |
| `wolkaraforever/Shell/main.m` | `launcher/App/main.m` | routes a mapped button, bridges capture across the dylib boundary |
| `wolkaraforever/Shell/WolkaraForeverConfig.m` | `launcher/App/WolkaraForeverConfig.m` | the schema for the flag, the mode and the destinations |

The Composer is compiled into the AppKit compatibility library rather than the app, because
everything it drives lives there: the draft editor, the keyboard geometry, the guest's key path.
The app does not link that library. The two places that must cross - the microphone and the
mapped button - cross by notification, exactly as the keyboard's microphone key already did.

## States

`idle → opening → listening → editing/ready → sending → idle`, with `cancelled` and `failed` as
terminal states. `failed` keeps the card up, because that is the error the player has to see;
`cancelled` takes it away.

| Event | Result |
| --- | --- |
| Open (the card's microphone, the layer keyboard's microphone key, a mapped button) | one Return to open the game's chat, then capture starts; the entry is logged as `toolbar`, `keyboard` or `controller` |
| Repeated Open while open | ignored: one Composer, one Return |
| Partial result | draft only; **Send** disabled while provisional |
| Final result | replaces the recognised segment, state `ready` |
| Typing | pauses capture first (the generation moves on), state `editing` |
| Send | text once, Return once, Escape once only when the Composer opened the chat |
| Duplicate Send | ignored |
| Cancel | capture cancelled, at most one Escape, never any text |
| Background | capture cancelled, draft kept for the return, never sent |
| Controller disconnect | capture cancelled, nothing sent, late results ignored |
| Flag off (rollback) | draft dropped, destinations and mappings kept |

## The send transaction

1. Validate the displayed line: control characters become spaces, the result is trimmed and
   bounded at 1024 characters, and valid composed Unicode is preserved.
2. Increment the generation and stop capture. Every callback from before this moment is now
   stale and is dropped.
3. If the chat is not already open, ask the target for one Return.
4. Insert the committed line once.
5. Post Return once.
6. Post Escape once, only where the Composer opened the chat and only after the Return went in.
7. Clear the draft and publish `idle`.

A failure before step 4 keeps the draft and shows `Message was not sent.`. A failure after it is
reported and never retried: a retry is the duplicate message this transaction exists to prevent.

## Storage and migration

`wolkaraforever-config.json`, through `WolkaraForeverConfig`, with the keys
`AKChatComposerEnabled` (bool), `AKChatDeliveryMode` (`classicDirect` or `review`) and
`AKChatDestinationsV1` (at most four records of `id`, `title`, `command`, `enabled`; a title of
24 characters, a command of 64 that starts with one slash and holds no control characters, unique
identifiers and unique commands). An invalid record is dropped on its own and its valid siblings
are kept.

The mode is migrated once, on first read: an installation that has any voice setting from before
the Composer keeps `classicDirect`, which is what those settings already produced; anything else
starts in `review`, the product's default for a new installation. The decision is written down so
it cannot drift between launches or between its two readers (the Composer, and the shell that
routes a mapped button). Unknown keys in a newer file are ignored, so a downgrade is harmless.

## Rollback

`AKChatComposerEnabled` is the feature flag, independent of the mode. Turning it off cancels any
open session, drops the ephemeral draft, restores every entry path to its classic behaviour and
leaves mappings and destinations in place for a later re-enable. Choosing `Classic direct` in the
card's settings does the same without touching the flag.

## Logging

`chat-composer:` lines on the adapter's log: state transitions, generation, entry source,
Send/Cancel outcome, failure stage, lifecycle cleanup and rollback. Lengths are logged; the draft,
the dictated words and the game's own text never are. The fixture asserts both halves: that every
terminal outcome is in the log, and that no draft from the fixture appears in it.

## Tests

- `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` - the classic controls, the
  Composer card against a real guest (one insertion, one Return, one Escape; Cancel posts one
  Escape and no text; a refused open shows the localized error; a backgrounded draft is kept),
  and the standalone Composer fixture (`tests/test_chat_composer_app.m`) with its log assertions.
- `wolkaraforever/tools/test_voice.sh` - the capture bridge: partials offered as drafts, one
  final, a stop reported as a stop, a failure that never delivers a partial, and the classic
  route still delivering when no Composer is involved.

Both run on iPhone Duo and iPad Pro 13-inch (M5); the runner refuses any other device.

`wolkaraforever/tools/capture_composer_states.sh` takes the three screenshots the review record
names - idle, ready and error - from the same fixture, on either matrix device. The captures are
local evidence under `build/` and are never committed.

Both fixtures are installed over an empty container: `simctl install` keeps an app's data, and
these fixtures write `NSUserDefaults`, so a run that aborted left the delivery mode behind and the
next run started in the previous case's world. Measured both ways - a stale container fails the
self-test's 64-edit draft loop, a clean one passes, and a pristine `main` checkout with the stale
container fails in the same place.

## Text size

The card follows the player's text size. Its fonts come from `preferredFontForTextStyle:`, and
its label row, action row and destination chips are sized from those fonts, so at the default
category every measurement is the one every release through v1.0.10 has drawn and a larger one
grows the card rather than clipping it. Measured on both matrix simulators, on both interfaces:

| Category | Card | Action row | Draft editor |
| --- | --- | --- | --- |
| default (`UICTContentSizeCategoryL`) | 130 pt | 44 pt | 48 pt |
| `UICTContentSizeCategoryAccessibilityXXXL` | 202 pt | 80 pt | 48 pt |

The suite runs the card a second time with
`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and asserts the
row, the editor's height, the label's own line box and that **Send** stays inside the card.
