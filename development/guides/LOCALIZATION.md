# Localization: the app's language, and the game's

WolkaraForever has two language settings, and they are independent on purpose:

| Setting | Stored as | Controls | Where it is changed |
| --- | --- | --- | --- |
| **App language** | `WolkaraForeverAppLanguage` (`en`, `de`, `system`) | every label, alert, menu, accessibility string and status line that WolkaraForever draws, including the in-game overlay and the on-screen keyboard | **App language** in the Game Edition card |
| **Game language** | `WoWLocale` (`enUS`, `esES`, `deDE`) | what World of Warcraft downloads and what its `textLocale`/`audioLocale` say | **Game language** in the Game Edition card |

A player can read the launcher in German and play the English client, or the other way round.
Neither setting changes the game's login region, and neither touches the other unless the user
says so: the first time German is chosen as the app language, the launcher offers to put the game
into German as well, and does nothing to the game unless that offer is accepted. That acceptance
goes through the same validated writer and update gate as the Game language row.

`system` is resolved once, from the iPad's preferred-language list: the first entry that is a
language this app ships decides (German for a German preference, English for an English one), and
a list with neither resolves to English. Nothing else in the app resolves the language for itself.

## Where the code is

- `wolkaraforever/Shell/WKLocalization.h` and `.m` — the whole service: the setting, the
  resolution rules, the tables, the fallback chain, plural selection, and the change
  notification. Foundation only, usable from Objective-C and Swift, and safe before any UI exists
  (the closing countdown and the launch status lines use it before a view controller does).
- `wolkaraforever/Shell/en.lproj/Localizable.strings` and `de.lproj/…` — the strings. They are the
  app's own resources and are compiled into the bundle by the target that already includes
  `launcher/`.
- `wolkaraforever/Touch/AKHostLocalization.h` and `.m` — the shim the compatibility libraries use.
  The on-screen keyboard and the performance overlay are compiled into the guest's libraries,
  which are a different binary from the app; they ask the app's `WKLocalization` class by name at
  runtime, so the setting and the resolution rules stay in one place. A standalone adapter fixture
  has no app to ask, and the shim then reads the same defaults key and the same tables itself.
- `wolkaraforever/tools/check_localization.py` — the table check. Run it before every pull
  request that touches strings.
- `wolkaraforever/tools/test_localization.sh` — the Mac-side suite (resolution, stored values,
  fallback, formatting, plurals, change notification).
- `wolkaraforever/tools/test_wow_launcher_ui.sh` — the UIKit fixture, which includes the German
  screen flow: the row, the immediate switch, the absence of raw keys, the one-time offer, the
  validated game-language write, and German at the largest text size.

## What is translated, and what never is

Translated: alerts, buttons, menus, section headings, status and progress lines, empty and error
states, permission explanations, Settings, About, accessibility labels and hints, the performance
overlay, the touch keyboard's and gamepad's own labels.

Never translated:

- user data — add-on names, file names, paths, backup names, versions, account text;
- WoW CVar names, Blizzard product identifiers (`wowf`, `wow_classic_era`), region codes, and the
  game's own `.build.info` tags;
- log tags and event names, `--flag=` command-line arguments, and the identifiers the device
  matrix greps for;
- the diagnostics' *output*: the report text a self-test or a probe prints. The menu around it is
  translated; what it reports is not;
- licence and notice text, which is shown as the licensors wrote it;
- hardware button names as the input layer reports them ("Button A", "Left shoulder"), because
  they name a physical button.

Text produced deep inside the download, verification and file-operation stacks (an HTTP failure, a
damaged archive, a CASC generation that will not bind) is English and stays English. It is
detail, it matches the log line beside it, and a translator cannot review it. The alert around it
is ours and is complete in the app's language.

System UI — the document picker, the share sheet, the keyboard's own chrome — follows iPadOS, not
this setting. That is the platform's behaviour, not a gap.

## Adding or changing a string

1. Choose a namespaced key: the screen or subsystem, then the row
   (`home.performance.backup`, `addons.sort.title`, `overlay.thermal.serious`).
2. Add it to **both** `en.lproj/Localizable.strings` and `de.lproj/Localizable.strings`, with the
   same conversions in the same sense — `%@`, `%lu`, `%.0f`, and a literal per cent written `%%`.
3. Use it: `WKLocalized(@"key")` for a plain label, `WKLocalizedFormat(@"key", arg…)` when the
   table supplies the format, and `WKLocalizedCount`/`WKLocalizedCountFormat` for a count.
4. For a count, write the forms the language needs: `.one` and `.other`, plus `.zero` where a
   language says "no add-ons" differently. A form a language does not need is simply left out; the
   service falls back to `.other`.
5. Run `wolkaraforever/tools/check_localization.py`. It refuses a key in one table and not the
   other, a conversion that differs between them, an empty German string, and a key the source
   asks for that no table has.
6. Run `wolkaraforever/tools/test_localization.sh` and the fixture that owns the screen
   (`test_wow_launcher_ui.sh`, `test_voice.sh`, `test_touch_controls_ui.sh`).

Anything that changes the strings a screen shows also has to survive a language change without a
relaunch. The home page has one `-localize` method that both `-viewDidLoad` and the change
notification call: set fixed words there, and let `-render` own the words that change with the
installation. A string set in `-viewDidLoad` alone is a label that stays in the old language.

## Translator instructions (German)

- Address the reader as **Sie**, consistently, and keep sentences short enough for a control.
- Use German typographic punctuation: „…“ for quotes, an en dash – for an aside or a range, and a
  space before an ellipsis („Wird geladen …“).
- Keep meaningful product names as they are: WolkaraForever, World of Warcraft, CurseForge,
  Mac-Ever, iPadOS, GitHub, Tolkara.
- Keep file names, paths, CVar names and identifiers exactly as they appear in the English string,
  including their capitalisation.
- Prefer the noun the app itself uses over a synonym: edition → Edition, add-on → Add-on, backup →
  Sicherung, restore → Wiederherstellen, Play → Spielen.
- Long compounds are expected; check that a label still fits at the largest Dynamic Type size
  rather than shortening it into something vague.
- Do not ship machine translation as final copy. A fluent German reader reviews the whole table in
  context — on the screens, not only in the file.

## Review checklist for a key or a string

- [ ] The key is namespaced and reads as the place it is used, not as the sentence it contains.
- [ ] It exists in both tables, with identical conversions, in an identical order where the
      sentence allows it.
- [ ] The German string is a sentence a person would say, in formal address, with German
      punctuation, and no English word left in it that is not a product name or a technical value.
- [ ] Anything the string quotes — a file name, a CVar, a version — is unchanged.
- [ ] A count has the forms German needs, and a `1` reads correctly.
- [ ] The string is not one of the never-translated categories above.
- [ ] The screen still reads correctly after switching language without a relaunch.
- [ ] The largest Dynamic Type size does not clip it.
- [ ] Nothing in either table is a machine translation that has not been read by a person.

## Verification before merge

```sh
wolkaraforever/tools/check_localization.py     # the tables agree, and the source's keys exist
wolkaraforever/tools/test_localization.sh      # the service's own behaviour
wolkaraforever/tools/test_wow_launcher_ui.sh   # the English and German launcher flows
wolkaraforever/tools/check_layers.sh           # the layer still builds the way it is split
wolkaraforever/tools/check_docs.sh             # every link and image still resolves
```

A German launcher claim also needs the physical check: `wolkaraforever/tools/install.sh`, then on
the iPad, select German as the app language, reopen the app, choose German as the game language,
and see the selected-language update state appear before Play. Record the source SHA, the device,
iPadOS, the execution mode, and what the person doing it observed. That is a launcher check, not
gameplay proof.
