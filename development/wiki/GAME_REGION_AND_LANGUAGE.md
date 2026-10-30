# Game region and language

> **Source of truth:** [`docs/USING_WOLKARAFOREVER.md`](../../docs/USING_WOLKARAFOREVER.md)
> **Last reviewed:** 2026-10-30

WolkaraForever has four settings that are easy to confuse. Two of them are the CDN region and the
game's language; the other two are the app's own language and your account.

| Setting | Where it is | What it changes |
| --- | --- | --- |
| **Region** | Game Edition → Game language row's sheet → Region | Which Blizzard CDN you download from: Europe, Americas, Korea, or Taiwan. |
| **Game language** | Game Edition → Game language row | The text and audio World of Warcraft downloads (`textLocale` and `audioLocale`). English, Spanish, and German. |
| **App language** | Game Edition → App language row | WolkaraForever's own labels only. See [App language](APP_LANGUAGE.md). |
| **Account** | In the game | Nothing here touches it. |

## What a game-language change does

- Writes both `textLocale` and `audioLocale` to the game's configuration.
- If the installed files belong to another language, marks the installation as requiring a
  language update, and downloads the selected-language files before Play becomes available.
- Does **not** change the login region, the account, bindings, add-ons, or any other setting.

## What no setting here does

- Region and language do not change the game's login portal: your account's own region decides
  that, and choosing Americas does not move an account to the Americas.
- The app language never starts a download. It is a redraw.
- Neither setting changes anything about a running game; both are read when one starts.

## German

German is available in both places, and they are independent:

- **Game language → German** downloads and configures the German client text and audio. It is the
  path described above, with the same update gate.
- **App language → Deutsch** translates the launcher. The first time it is chosen, WolkaraForever
  offers once to set the game language to German as well; declining leaves the game untouched.
