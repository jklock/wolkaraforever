# Using WolkaraForever

> **Current as of 2026-10-29**

Use this guide after [installing the app](INSTALLATION.md). Labels may differ slightly as
the selected client, download state, and iPad permissions change.

## Home and game installation

![WolkaraForever home screen](screenshots/launcher-home.jpg)

On the home screen, choose **Forever**, then select a region and game language. Regions are
Europe, Americas, Korea, and Taiwan; game languages are English, Spanish, and German. The
launcher itself can be read in English or German: see [App language](#app-language) below.
Choose **Install** to download and verify the client, or let the app complete a required
update before playing. Keep WolkaraForever foregrounded while it downloads, verifies, or
prepares a launch.

For a ready Forever installation, changing the game language updates both `textLocale` and
`audioLocale` in the game's configuration. If its installed files belong to another language,
WolkaraForever marks the install as requiring a language update and downloads the selected-language
files before Play is available. It does not change the login region or other game settings.

Select **Play** when it becomes available. Startup preparation can take several minutes.
When the game is running, use **Leave game** in the in-game toolbar if the game has no useful
quit path. It closes WolkaraForever; reopen the app for a fresh session.

## App language

WolkaraForever has two language settings, and they are separate.

- **App language** (`English`, `Deutsch`, or `System Default`) changes the labels, alerts, menus
  and spoken (VoiceOver) descriptions that WolkaraForever itself draws — including the in-game
  performance overlay and the on-screen keyboard. The change applies immediately; the app does
  not have to be restarted. **System Default** follows the iPad's own preferred-language list, and
  uses German when that list prefers German, English otherwise.
- **Game language** (the row above it) changes the text and audio World of Warcraft downloads. It
  is the setting described above, and it is the only one of the two that costs a download.

The first time you choose German as the app language, WolkaraForever offers to change the game
language as well. Accepting that offer sets the game to German and downloads its German files; declining it leaves the game exactly as it was. Either answer is remembered, and the offer is not
made again — the **Game language** row is always there if you change your mind later.

Changing one setting never changes the other: reading the launcher in German does not download
German game text, and playing the German game does not change the launcher's language.

## Add-ons

![Add-on Manager installed list](screenshots/addon-manager.jpg)

Choose **Install Addons (Curse & Direct)** to manage add-ons for the selected edition.

- **Installed** lists packages on the device. Search narrows the list and refresh reloads it.
  Select a managed package to disable or restore it, pin or unpin its version, or remove it.
  WolkaraForever records the packages it manages and removes only those packages.
- **Browse CurseForge** searches CurseForge through its Core API. It needs an approved API
  key; the key is stored in this device's Keychain. The browser supports search, sorting,
  category and game-version filtering, configurable columns, project artwork and metadata,
  and compatible-file selection. A project or file can still be unavailable through the API;
  the app reports the provider's reason.
- The **plus** control imports one add-on archive from Files. **Open Add-on Directory** opens
  the relevant folder. Nothing changes until you select an archive or confirm an action.

Do not change add-ons while a download, update, or game startup is active.

## Performance, device profile and UI recovery

The home screen groups its controls into five cards — **Game Edition**, **Add-On Manager**,
**Voice & Input Manager**, **Performance Manager**, and **UI Manager**. Each card is one job.
They sit two across on an iPad and stack into one column on an iPhone or at the largest text
sizes; a phone scrolls down, and no card ever hangs off the side.

### Device profile

**Device profile** shows the model WolkaraForever detects — for example
`Device profile: Automatic — iPad Pro 13-inch (M5)` — and the render profile it recommends for
that hardware. The sheet offers **Automatic (recommended)** for the device actually in use, and
the other profiles the app knows about, so two devices can be compared.

Choosing another profile is a preview: the row then reads `Preview — …`, and a note says which
device it belongs to. Rendering follows that profile's safe scale, and **Automatic** is the way
back. A device the app has no record for is named as unrecognised and falls back to a
conservative profile rather than a guess.

### Render profile

**Render profile** offers only the levels that hardware was measured at — Performance, Balanced
and Quality where each was measured, fewer where they were not. A level that could not hold its
frame budget on that device is not offered at all. Raising the load above the recommendation
asks first, and says the size it will render at. The choice takes effect the next time the game
starts.

These two rows change **only WolkaraForever's own render scale**. They never write the game's
`Config.wtf`. The rows in the last card are the ones that touch game files, and each says so.

- **Restore performance defaults** returns to **Automatic** for the device in use and removes
  only WolkaraForever's own profile keys. It does not reset game, account, or UI settings, and
  it stays dimmed until you have made a performance choice of your own — with nothing
  customised there is nothing to restore.
- **Performance Overlay** shows frame rate, frame time, thermal state, battery, memory, and
  Low Power Mode in the game. It is off by default and applies immediately.

### UI recovery

The **UI Manager** card operates on a ready Forever installation when no update, launch
preparation, or session is active.

- **Backup WoW UI Configuration** creates a verified ZIP of `WTF` (excluding its `Backups`
  folder) and `Interface` in `WTF/Backups`.
- **Restore WoW UI Configuration** restores a chosen `WoW-UI-…zip` from Files. It snapshots
  the current state first, so the restore itself can be reversed.
- **Reset to Default Graphical Settings** makes a backup, then removes only graphics and
  display settings from `WTF/Config.wtf`. Account data, locale, audio, input, gamepad
  configuration, bindings, SavedVariables, and unknown settings remain unchanged.
- **Open Settings Folder** opens `WTF` in Files.
- **Gamepad UI** writes only `GamePadEnable` and takes effect when Forever next starts. It
  does not create or replace bindings.

The app also uses background-aware frame pacing: when it loses the foreground it limits its
Metal frame loop to 5 fps and restores normal pacing when foregrounded. This reduces active
work while another app is in front; iPadOS still controls background execution.

## Controls and voice

![Key and button configuration](screenshots/voice-configuration.jpg)

The in-game toolbar exposes the cursor, keyboard, gamepad, settings, and leave-game controls.
The touch trackpad supports pointer movement, two-finger scrolling, and drag gestures. The
on-screen keyboard includes text, symbols, and dictation entry; the gamepad has layout,
size, opacity, grid, and haptic controls. Physical keyboard and controller input can also be
mapped in the app.

Open **Key / Button Configuration** for voice input:

1. Enable **Use a button to talk** and choose **Map a button**.
2. Press a supported keyboard key or controller control.
3. Choose **Hold to talk** or **Press to start and stop**.
4. Use **Test Voice** before opening the game, especially after changing a mapping.

Voice requires Microphone and Speech Recognition permission. The mapping can send text when
recognition completes or leave it for review; it can add a space after the text and accept
expected words. A mapped control can be withheld from the game while voice is active. Check
the controller-button collision warning before relying on a mapping—the safe choice depends
on the button bindings you use in the game.

## Help and safe recovery

Open **Settings → Technical details** for the app's current state and an exact failure
message. Include that message and a redacted log in a support report. Do not share account
credentials, API keys, signing data, pairing material, or device identifiers.

Do not delete the app as a first repair step: it removes downloaded game data and enrollment
state. If a download or startup fails, reopen the app, preserve its data, and use the
Technical details message to identify the next step.

For the boundary between feature availability and device-tested compatibility, see
[Compatibility](../COMPATIBILITY.md).
