# Validation: German app localization (2014c7e)

> **Historical record.** Evidence for the German app-language work, recorded by hand on the
> device as the prompt requires.
>
> **Scope.** Everything WolkaraForever shows *before a game runs*: the launcher, its pages and
> sheets, the launch status lines, and the game-language choice with its update gate. The running
> game's own text and audio are the game's, not ours, and are not in scope here.
>
> It is not current guidance for later builds. See
> [docs/README.md](../../docs/README.md) for the live documents and
> [localization](../guides/LOCALIZATION.md) for how the feature is built.

- Code revision: `2014c7e` *feat: translate the startup progress view*, on top of `0f44553`
  (the presentation fix), `a0d3510`, `8eb56bb` (this record's first version) and `1bf95d0`
  *feat: make German a complete app language*. The screenshots below are from an install of
  `2014c7e`: every follow-up changed something a person can see - when a page is presented, what
  an alert says, or the startup caption - so the launcher was re-checked on the build that carries
  them rather than assumed.
- Recorded: 2026-10-29T10:46Z
- Host: macOS, Xcode 27.1 (arm64)
- Device: **Dadpad**, iPad Pro 12.9-inch (5th generation), **iPadOS 27.0.1**, landscape, over the
  local network
- Execution mode: **Developer service** (enrollment unchanged; the app kept the identity it had)
- Installed build: `local.wolkaraforever.johnklock` 0.1 (1), built by
  `wolkaraforever/tools/install.sh --replace-running`
- Game: World of Warcraft Forever 1.60.1.70685, region `us`, game language `enUS` before and after

## What was run

| Step | Result |
| --- | --- |
| `wolkaraforever/tools/check_localization.py` | PASS, 470 keys in both tables |
| `wolkaraforever/tools/test_localization.sh` | PASS, 58 checks |
| `wolkaraforever/tools/test_wow_launcher_ui.sh` | PASS, including the German flow, the pre-game page sweep and the two presentation-race assertions |
| `wolkaraforever/tools/test_voice.sh` | PASS, 303 checks |
| `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` | PASS |
| `wolkaraforever/tools/test_touch_gamepad_ui.sh --self-test` | PASS |
| `wolkaraforever/tools/test_wow_launcher.sh` | PASS |
| `wolkaraforever/tools/test_curseforge.sh` | PASS, 27 checks |
| `wolkaraforever/tools/test_forever_ui.sh` | PASS (Config.wtf rules and archive) |
| `wolkaraforever/tools/test_addon_archive.sh` | PASS, 58 checks |
| `wolkaraforever/tools/test_translation_sim.sh` | PASS |
| `wolkaraforever/tools/check_localization.py` after the last string change | PASS, 486 keys, no German string left identical to its English one |
| `wolkaraforever/tools/check_layers.sh` | OK (now also checks the string tables) |
| `wolkaraforever/tools/check_docs.sh` | OK, 73 markdown files |
| `wolkaraforever/tools/install.sh --replace-running` | installed and launched |

## What was observed on the iPad

1. **The new row exists, in English.** The Game Edition card shows `Forever`, `US · English`,
   and a third row `App language: English`, with Play enabled and "Your game is up to date".2. **German persisted and applied at launch.** With `"WolkaraForeverAppLanguage": "de"` in the
   app's own settings file (`Documents/wolkaraforever-config.json`, the file the app imports at
   launch and writes when a setting changes), the app was terminated and relaunched and came up
   **entirely in German**: `Bereit zum Spielen`, `Ihr Spiel ist aktuell`, `Spielen`,
   `SPIELEDITION`, `ADD-ON-VERWALTUNG`, `SPRACHE & EINGABE`, `LEISTUNG & OBERFLÄCHE`,
   `App-Sprache: Deutsch`. The game row still read `US · Englisch`, which is the separation the
   change is about.
3. **The game language is a separate setting, and its update gate still works.** Adding
   `"WoWLocale": "deDE"` to the same file and relaunching produced `US · Deutsch` with the app
   language still `Deutsch`, and the page entered the existing selected-language update state:
   `Ihr Spiel wird aktualisiert …`, `Aktualisierung wird gelesen`, `Aktualisierung läuft …`, with
   the update controls shown and Play withdrawn. Nothing about the region changed.
4. **Nothing was left broken.** The check was stopped during the update's verify phase (no
   download had started; `546.2 MB / 50.8 GB` verified when it was stopped). The settings file
   was then restored, the app was relaunched, and the page came back to
   `Ready to play / Your game is up to date / Version 1.60.1.70685` with Play enabled and
   `US · English`.

   Two details of that restore are worth writing down, because they are behaviour, not
   housekeeping. A key **absent** from the settings file leaves the value already in the app's
   defaults, so English had to be written explicitly (`"WolkaraForeverAppLanguage": "en"`,
   `"WoWLocale": "enUS"`) rather than omitted; the same is true of
   `WolkaraForeverGameLanguageOfferShown`, which has to be written as `false` - deleting it
   left the imported `true` in place, and the person holding the iPad would then never be offered
   the German game language at all.

## The pre-game surface, in German

The fixture now opens **every page WolkaraForever shows before a game runs** with German selected
— About, the Add-on Manager, Key / Button Configuration, Test Voice, and the Settings sheet — and
scans each one. The scan fails on two things: a visible localization key, and a visible string
that is the *English* copy of a key whose German differs. It reads labels, buttons, field and
search placeholders and segmented-control items, which is what makes it a check of the page
rather than of the labels a test remembered to name.

Both rules were shown to bite before they were kept: one label put back to English in the add-on
manager produced

```
ENGLISH STILL SHOWN on ADD-ON-VERWALTUNG: Browse CurseForge (key addons.mode.browse)
```

and the table check now refuses a German string that is simply the English one, with a short
allowlist for the words that really are the same in both (`Name`, `Region`, `Downloads`,
`Edition`, `Warm`, `Nominal`, `Controller`, and two proper nouns).

One screen in that surface is not the layer's: the startup progress view, whose caption read
"Elapsed" and whose VoiceOver value read "3 minutes, 4 seconds", both English, for minutes, on
every launch. `2014c7e` replaces `launcher/App/LaunchProgressView.m` in the layer for those three
strings only - the ring, the digits, the animation and the reduce-motion behaviour are the
platform's file unchanged - and platform patch 0041 keeps the platform's own visual fixture
building. Checked by launching that fixture's probe in the simulator: `Elapsed 00:03` in English,
`Dauer 00:03` in German, same place and same layout.

## What re-checking the work found

Reading the German flow again, against the same build, found a real defect in it: UIKit drops a
presentation that starts while another is being dismissed, so choosing German closed the sheet and
**lost the one-time offer**, spending its flag as it did - the offer would have been made once,
never, and the flag said it had been. The same race made "Language" in Download preferences,
"Manage add-ons" and "Technical details" in Settings dead taps, which predated this work.

`a0d3510` puts every sheet, page and message the launcher shows behind one wait until nothing is
presented, and `0f44553` moves that wait into `WolkaraForeverTheme` so the add-on manager uses it
too instead of a second copy. Both cases are now assertions in the launcher fixture, and both were
shown to fail without the wait before it was kept.

The device was left on that home screen with the app running and no game started.

The build installed there is `2014c7e`, the commit this record names.

## What this is not

- It is not gameplay proof, and nothing here says the German *client* renders correctly in game.
- It is not a record of a person tapping the App language row: the row was observed, and the
  language was selected the way the app stores it, through its own settings file, then applied by
  a relaunch. The tap path — the sheet, its three choices, the immediate redraw and the one-time
  German game-language offer — is proven by the launcher fixture in
  `wolkaraforever/WoW/tests/test_wow_launcher_app.m`, not by this record.
- What happens once a game runs - the client's own text and audio, and the overlay and keyboard
  drawn over it - is out of scope: it is the game's, and no guest was started. Those views are
  localized anyway and are covered by `test_touch_controls_ui.sh --self-test` and
  `test_touch_gamepad_ui.sh --self-test` in the simulator.
- The interrupted German update was not resumed. The installation remains verified for `enUS`,
  which is what the last screenshot shows.
- Enrollment is still not possible over the network (`tools/enroll.sh` needs USB); the installed
  app kept the identity it already had, and installation did not depend on it.
