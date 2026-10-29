# Validation: German app localization (56ddc87 + this record)

> **Historical record.** Evidence for the German app-language work, recorded by hand on the
> device as the prompt requires. It is not current guidance for later builds. See
> [docs/README.md](../../docs/README.md) for the live documents and
> [localization](../guides/LOCALIZATION.md) for how the feature is built.

- Code revision: `56ddc87` plus the localization work in the working tree (this record is part
  of it). Two installs were made: one while the work was being checked, and a second of the final
  tree so that the build on the device and the code in the record are the same; the screenshots
  below are from the second.
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
| `wolkaraforever/tools/test_wow_launcher_ui.sh` | PASS, including the German flow |
| `wolkaraforever/tools/test_voice.sh` | PASS, 303 checks |
| `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` | PASS |
| `wolkaraforever/tools/test_touch_gamepad_ui.sh --self-test` | PASS |
| `wolkaraforever/tools/test_wow_launcher.sh` | PASS |
| `wolkaraforever/tools/test_curseforge.sh` | PASS, 27 checks |
| `wolkaraforever/tools/test_forever_ui.sh` | PASS (Config.wtf rules and archive) |
| `wolkaraforever/tools/test_addon_archive.sh` | PASS, 58 checks |
| `wolkaraforever/tools/test_translation_sim.sh` | PASS |
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
   housekeeping: a key absent from the settings file leaves the value already in the app's
   defaults, so English had to be written explicitly (`"WolkaraForeverAppLanguage": "en"`,
   `"WoWLocale": "enUS"`) rather than omitted; and
   `WolkaraForeverGameLanguageOfferShown` was removed again, so a German selection by the person
   holding the iPad still gets the one-time offer.

The device was left on that home screen with the app running and no game started.

## What this is not

- It is not gameplay proof, and nothing here says the German *client* renders correctly in game.
- It is not a record of a person tapping the App language row: the row was observed, and the
  language was selected the way the app stores it, through its own settings file, then applied by
  a relaunch. The tap path — the sheet, its three choices, the immediate redraw and the one-time
  German game-language offer — is proven by the launcher fixture in
  `wolkaraforever/WoW/tests/test_wow_launcher_app.m`, not by this record.
- The interrupted German update was not resumed. The installation remains verified for `enUS`,
  which is what the last screenshot shows.
- Enrollment is still not possible over the network (`tools/enroll.sh` needs USB); the installed
  app kept the identity it already had, and installation did not depend on it.
