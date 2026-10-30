# App language

> **Source of truth:** [`docs/USING_WOLKARAFOREVER.md` → App language](../../docs/USING_WOLKARAFOREVER.md#app-language)
> and [`development/guides/LOCALIZATION.md`](../../development/guides/LOCALIZATION.md)
> **Last reviewed:** 2026-10-30

WolkaraForever can be read in **English** or **German**, or follow your iPad.

Open the home screen and look at the **Game Edition** card. Its third row is **App language**:

| Choice | What it does |
| --- | --- |
| English | The launcher is drawn in English. |
| Deutsch | The launcher is drawn in German. |
| System Default | Follows the iPad's preferred-language list: German if that list prefers German, English otherwise. |

The change applies as soon as you pick it — there is no restart, and the installation the page was
showing stays exactly as it was. Everything WolkaraForever draws follows it: rows, alerts, menus,
status and progress lines, the About page, the spoken descriptions VoiceOver reads, the in-game
performance overlay, and the on-screen keyboard's own labels.

## App language is not game language

The row directly above it is **Game language**, and it is a different setting:

- **App language** changes WolkaraForever's own interface. It costs nothing and downloads nothing.
- **Game language** changes the text and audio World of Warcraft downloads. Changing it can
  require a multi-gigabyte download, and WolkaraForever will not let you press Play until the
  selected-language files are installed.

The first time you choose German as the app language, the launcher asks whether it should change
the game language too. It changes nothing about the game unless you say yes. Either answer is
remembered and the question is not asked again; the Game language row is always there if you
change your mind later.

## If something looks wrong

- **The launcher is still in the other language.** Check the App language row rather than the game
  language row; the two are separate. If it says *System Default*, the iPad's preferred language
  decides — choose English or Deutsch explicitly to override it.
- **A message is still in English.** A few things are deliberately not translated: file names,
  WoW settings names, and the technical detail a failed download reports. The sentence around it
  is translated. See [the localization guide](../../development/guides/LOCALIZATION.md).
- **The App language row cannot be tapped.** It is disabled while the game is starting or running.
  Return to the launcher first.
