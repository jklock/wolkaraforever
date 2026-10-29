# Using WolkaraForever

The in-app guide, for an installation that is already built, installed and enrolled. Setup
is in [Build and run](GETTING_STARTED.md). Screenshots come from the iPad; your edition,
add-ons and mappings will differ.

## Home

![WolkaraForever home screen](screenshots/launcher-home.jpg)

1. Tap the edition to choose **Forever**, **Classic Era**, **Classic**, **Retail** or
   **Retail · Beta**. This picks the client to prepare; it does not change your account.
2. Tap the region/language label for download preferences: Europe, Americas, Korea or
   Taiwan, and English or Spanish. Download content only — not your login region.
3. Keep the app open while it downloads or updates. **Play** appears only when the client
   is ready.

While the game starts the page says **Starting…** and rows that would change something are
grey. Once its window is up it says **Running**. Quit from the game's own menu and you
return here with **Game closed** — the game can only be entered once per process, so the
**Close WolkaraForever** button is how you start over.

4. Tap **Play**, wait out startup preparation, then sign in yourself.

Starting can take minutes even when the client is current.

## Add-ons

![Add-on Manager installed list](screenshots/addon-manager.jpg)

**Install Addons (Curse & Direct)** shows the installed packages for the selected edition.

- **Installed** lists them; search narrows it, the circular arrow refreshes. Select one to
  **Disable**/**Restore**, **Pin this version**/**Unpin updates**, or **Remove managed
  package**. **Cancel** changes nothing.
- **Browse CurseForge** needs an approved Core API key, stored only in this device's
  Keychain, entered only if you are approved to use it. Once configured it lists real
  projects with artwork, downloads, rank, last update, category, game version and author.
  **Sort**, **Filters** and **Columns** behave like the site; sorting and filtering are
  CurseForge's own.
- **+** imports one archive from Files. **Open Add-on Directory** opens the add-on folder.
- **Done** returns home.

The list marks what WolkaraForever manages. Existing add-ons are kept; only packages it
installed and recorded are removed. Do not change an add-on mid-update or mid-start.

## Performance & UI Manager

The last home-screen box holds Forever's file operations and two switches. The file
operations need a ready Forever edition and no update, start or session in progress.

Changing **Language** (English or Spanish) for a ready install changes only `textLocale` and
`audioLocale` in `WTF/Config.wtf` — not the login region, not anything else.

- **Backup WoW UI Configuration** writes a verified ZIP of `WTF` (minus its `Backups`) and
  `Interface` into `WTF/Backups`.
- **Reset to Default Graphical Settings** asks first, backs up, then removes only graphics
  and display settings from `Config.wtf`. Accounts, locale, audio, input, gamepad,
  bindings, SavedVariables and unknown lines are kept byte for byte.
- **Restore WoW UI Configuration** opens `WTF/Backups`; a snapshot is taken first, so a
  restore can itself be undone.
- **Gamepad UI** writes `SET GamePadEnable`. No bindings change; it applies on next start.
- **Performance Overlay** toggles the in-game HUD — frame rate, frame time, thermal state,
  battery, memory, Low Power Mode. Off by default, applies immediately.
- **Open Settings Folder** opens `WTF`.

## Voice input

Test any mapping on the device: your controller, permissions and game field differ from
mine.

### Map a button

![Key and button configuration](screenshots/voice-configuration.jpg)

**Key / Button Configuration** → **Use a button to talk** → **Map a button**, then press the
control. The microphone does not open until voice is on and a button is mapped.

- **Hold to talk** records while held. **Press to start and stop** is for controls where
  iPadOS delivers no release.
- **Send it straight away** presses Return after inserting. **Add a space after the text**
  appends a space instead.
- **Words to expect** takes comma-separated names and game terms to bias recognition.

The mapped input still reaches the game, so pick a button the game does not use.
**Keep the game from seeing it** works for a keyboard key, not a controller button.

### Test it

![Test Voice screen](screenshots/test-voice.jpg)

**Test Voice** before opening the game: hold, speak, release, read the transcript. It types
nothing into the game; the box is editable and **Clear** only empties the test text. The
status line says off, waiting, listening or finalising. "No controller connected" means
connect it and map again.

### Permissions

**Permissions (Microphone, Speech)** opens this app's page in iPad Settings; turn on
**Microphone** and **Speech Recognition** there, then re-run **Test Voice**. The app cannot
grant or reset them itself.

## Settings and recovery

![Launcher settings menu](screenshots/launcher-settings.jpg)

The gear, upper right:

- **Manage add-ons** — the Add-on Manager.
- **Verify and repair game files** — for a damaged client or an update that cannot finish.
  It may download content.
- **Diagnostics and logs** — the first stop on a launch or update failure. Share the message
  and a redacted log; never account credentials, pairing material or device identifiers.
- **About and open-source licenses** — the licences the app must ship.

Let an update or a start finish before changing add-ons or retrying Play.
