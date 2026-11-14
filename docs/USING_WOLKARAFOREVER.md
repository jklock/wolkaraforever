# Using WolkaraForever

> **Current as of 2026-10-30 · branch `main`.**

Use this guide after [installing the app](INSTALLATION.md). Labels may differ slightly as
the selected client, download state, and iPad permissions change.

## Home and game installation

![Current WolkaraForever home screen in the simulator](screenshots/launcher-home.jpg)

On the home screen, choose **Forever**, then select a region and game language. Regions are
Europe, Americas, Korea, and Taiwan; game languages are English, Spanish, and German. The
launcher itself can be read in English or German: see [App language](#app-language) below.
Choose **Install** to download and verify the client, or let the app complete a required
update before playing. Keep WolkaraForever foregrounded while it downloads, verifies, or
prepares a launch. The screen stays awake during a file check. Brief interruptions
such as opening Control Centre do not cancel it. Switching to another app pauses
unfinished work; returning to the home page resumes it without starting the game.

If a connection drops or times out, the launcher retries the affected request after
1, 2, 4, and 8 seconds. Only that request waits: the rest of the download keeps
going. A retried request discards the part it had already received and asks for its
range again. If all four retries fail, tap **Try again**. Nothing already verified
is downloaded again, and a retry never activates an update on its own. For the same
build and game language, the updater reuses verified data saved on the device. The
total shown under **Downloading new data** is what remains for the current attempt.

During **Downloading new data**, the byte counts are followed by the recent verified
download speed in MB/s, averaged over roughly 30 seconds, and an estimated time
remaining at that speed. Both are left out while the app has not yet measured a
second of transfer, while no bytes are arriving, and when the estimate is more than a
day away.

The first check of an imported installation still reads its game data. Later
updates reuse checks for unchanged files, and long checks save their progress
periodically so an unexpected app closure does not discard the whole scan.
**Verify and repair game files** deliberately performs a full check.

If World of Warcraft reports its documented damaged-installation condition, WolkaraForever
shows the reported error in its own **Game files need repair** alert instead of leaving an
unexplained game popup. Choose **Repair game files**; WolkaraForever closes the spent game
session, and its next launch performs the full repair while preserving `WTF` and add-ons.

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
  not have to be restarted. **System Default** follows the device's own preferred-language list, and
  uses German when that list prefers German, English otherwise.
- **Game language** (the row above it) changes the text and audio World of Warcraft downloads. It
  is the setting described above, and it is the only one of the two that costs a download.

The first time you choose German as the app language, WolkaraForever offers to change the game
language as well. Accepting that offer sets the game to German and downloads its German files; declining it leaves the game exactly as it was. Either answer is remembered, and the offer is not
made again — the **Game language** row is always there if you change your mind later.

Changing one setting never changes the other: reading the launcher in German does not download
German game text, and playing the German game does not change the launcher's language.

## Add-ons

![Add-on Manager with no recorded installed add-ons in the simulator](screenshots/addon-manager.jpg)

Choose **Install Addons (Curse & Direct)** to manage add-ons for the selected edition. The
page is native and has three tabs; it opens on **My Add-ons**.

- **My Add-ons** lists every installed package, whichever way it arrived: through the
  CurseForge API, through the in-app browser, from a ZIP you picked in Files, or as a folder
  that was already on the device. Opening the tab, and **Refresh**, ask the provider about every
  linked package and compare the file it holds with the file the provider has. Search narrows
  the list; **Sort** and **Filter** change its order and its contents. Each row shows its name,
  version, author, the interface versions its TOC declares, and one word about its update, with
  one action that goes with that word: **Update**, **Check**, **Retry**, **Open** (see below),
  **Link**, or **Manage**. "Not checked yet" means nothing has asked about that package - usually
  because no API key is stored - and **Check** is what asks. "Checking…" only ever appears while
  a request is genuinely in flight. Selecting a row opens its detail sheet, which adds
  enable/disable, pin, remove, group membership and the package's activity. **Update All** runs
  one package at a time and reports each result; while it runs the same button cancels it.
- **Create Group** organizes the packages you already have into headings of your own. A group
  moves no file and changes no ownership.
- **Discover** shows featured, latest and popular projects from the API.
- **Browse** searches CurseForge through its Core API. It needs an approved API key; the key is
  stored in this device's Keychain. The browser supports search, sorting, category and
  game-version filtering, configurable columns, project artwork and metadata, and
  compatible-file selection.
- A project whose author does not allow API downloads is not a dead end. Its row's action reads
  **Open** and opens that exact project inside WolkaraForever, in an ordinary `WKWebView`. You
  may sign in to the site there, and the app keeps that session in WebKit's own store; it never
  reads, copies or logs a cookie. A ZIP the page hands over is installed under the project you
  chose, then returns you to the same row. The app never opens Safari for this.
- A package with no project identity shows **No linked project** and a **Link** action. Linking
  records the project you choose through native search; nothing is guessed from the package's
  name, and nothing on disk moves. Until you link it, the package is still fully manageable
  locally - enabled, removed, grouped, searched - and simply takes no part in updates.
- The **plus** control imports one add-on archive from Files. **Open Add-on Directory** opens
  the relevant folder. Nothing changes until you select an archive or confirm an action.
- **Install Recommended Add-ons** opens this page rather than installing anything by itself. On
  **iPadOS** it reads **Install Recommended Add-ons (Mac-Ever)** and opens Browse filtered to
  Mac-Ever, with the same API key and Install flow as any other project. On **iOS on Duo** it
  reads **Install Recommended Add-ons (WolkaraRoue)** and opens My Add-ons with the bundled
  WolkaraRoue package, showing its version and SHA-256; tap **Install** to install it. A package
  that is not the one this app shipped is refused, and nothing is written.

Two rows on the home screen hold the whole folder as a copy:

- **Backup Add-ons** writes one ZIP of everything under `Interface/AddOns` - every package
  folder and the manifest that records which of them this app owns - into `WTF/Backups`, named
  `AddOns-<date>T<time>Z.zip`. It runs only when you press it, and it reports the name it
  wrote.
- **Restore Add-ons** lists the backups that row made and asks you to confirm, naming the one
  you picked. The folder is replaced in one move: if anything fails part-way the add-on folder
  is exactly as it was. The previous contents are not kept afterwards, so take a backup of what
  you have before restoring an older one.

Do not change add-ons while a download, update, or game startup is active.

## Launcher Manager and interface mode

The **Launcher Manager** card holds one setting, **Interface Mode**, with exactly two choices:

- **iPadOS** — the standard interface. This is the default, and what a missing or unrecognised
  setting means.
- **iOS on Duo** — the mobile arrangement built for the phone form factor.

The choice is remembered across launches. Changing it only records the setting: it never
installs, disables, removes or updates an add-on, and it does not change your game files. The
recommendation row in the Add-On Manager card follows the choice, as described above.

The same card holds four rows for the on-screen controls' arrangement, one decision each:

- **Create Controller Layout** asks for a starting point (**Plain**, **Duo**, **Duo with room
  for an add-on**) and then for a name. The starting point becomes the layout in use, and the
  name is how **Restore** finds it again.
- **Edit Controller Layout** changes the layout in use: which gamepad button each control sends,
  the screen area the controls leave alone, Full or Simple, the stick buttons, and the ability
  zones.
- **Restore Controller Layout** puts a named layout back, offers **Restore From a Backup
  File…** for a `WolkaraForever-Layout-….json` that **Backup** wrote, and can delete a layout you
  no longer want.
- **Backup Controller Layout** writes the layout in use, and every layout you have saved, as one
  JSON file and hands it to the system share sheet, so it can go to Files or anywhere else.

All four write only the dictionary the on-screen controls read. None of them reads or writes a
game file, and none of them changes an installed add-on.

## Performance, device profile and UI recovery

The home screen groups its controls into six cards — **Game Settings Manager**, **Add-On
Manager**, **Dictation (V2T) Manager**, **Performance Manager**, **UI Manager**, and **Launcher
Manager**. Each card is one job. They sit two across on an iPad and stack into one column on an
iPhone or at the largest text sizes; a phone scrolls down, and no card ever hangs off the side.

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

**Render profile** offers Performance and Balanced on supported devices, with Quality on the
iPad profile where native rendering was measured. iPhones use a 2× Balanced default for
readability; it is not a measured frame-rate guarantee. Raising the load above the
recommendation asks first and shows the render size. The choice takes effect on the next
game session after reopening the app.

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

![Current Key / Button Configuration screen in the simulator](screenshots/voice-configuration.jpg)

The in-game toolbar exposes the cursor, keyboard, gamepad, settings, and leave-game controls.
The touch trackpad supports pointer movement, two-finger scrolling, and drag gestures. The
on-screen keyboard includes text, symbols, and dictation entry; the gamepad has layout,
size, opacity, grid, and haptic controls. Physical keyboard and controller input can also be
mapped in the app.

With a physical mouse or trackpad, holding a mouse button while moving passes a held-button
drag to the game. The touch trackpad's hold-then-slide gesture applies to the touchscreen;
physical trackpad dragging does not require that delay.

What you type goes to a draft first. **Done** on the system keyboard writes the draft into
the selected game field and does not press Return; **Replace** does the same from the draft
panel, and an empty draft clears the field. **↵** on the accessory bar is a plain Return.

### The Chat Composer

A new installation composes in-game messages in the **Chat Composer**: the same card, with a
microphone, **Cancel**, **Send** and any destinations you have written yourself. The toolbar
microphone, the keyboard's microphone key and a mapped controller button all open it, and nothing
reaches the game until you press **Send** - which types the line once, presses Return once and
closes the chat. **Cancel** closes the chat without sending a word. If you leave the app with a
message half-written, it is still there when you come back; it is never sent for you.

Open the card's gear to choose between **Review then Send** (the default) and **Classic direct**,
and to add up to four destinations - a name on a chip and the command it puts in front of your
line, for example `/say`. An installation that already had dictation settings keeps **Classic
direct**, so nothing about the way it worked changes until you change it.

The app's own language can be English, German, French, or follow the iPad - the row named
**App language** changes the launcher's words immediately. World of Warcraft's download
language is a separate setting (**Game language**) and offers English, French, Spanish and
German; changing it changes what the game downloads, so it is never done silently.

Touch settings use two columns when there is enough width and remain scrollable in smaller
windows. **Triggers on the outside** swaps LT/LB and RT/RB positions without changing their
inputs. New or reset layouts put the triggers inside; existing saved layouts keep their
positions until you choose otherwise. Connecting a physical controller closes the touch
settings or layout editor and releases touch inputs.

### Two arrangements, stick buttons and ability zones

The on-screen gamepad has two arrangements, chosen in **Touch controls** or in the launcher's
**Edit Controller Layout** sheet:

- **Full** is every control the app has always drawn, and it is what every existing
  installation keeps after an update.
- **Simple** draws both sticks, A/B/X/Y, LB and RB at the far top corners, and the menu. The
  triggers and the D-pad are not drawn. Its shoulders keep their own saved positions, so
  dragging one in Simple never moves the one in Full; turning Simple off puts every control
  back exactly where it was, and deletes nothing.

**Stick buttons (L3/R3)** is off unless you turn it on. A double tap on a stick then presses
that stick's own button once, for a moment; one tap does nothing, and moving the stick is
unchanged - a drag is never a tap. It is released when its moment passes, and always when the
controls hide, the keyboard opens, or the settings are opened. Apple's virtual controller does
not carry a stick button at all (measured: its extended profile has the face buttons, the
shoulders, the triggers, the menu, the D-pad and the sticks' directions, and nothing else), so
on this build the row says the controller has no stick button and stays off.

**Ability zones** are extra buttons you place: up to six, each sending one controller button
while your finger is on it. In the layout editor you drag a zone to move it and tap it to
choose which button it sends. Two zones may send the same button; the game sees that button
held until the last finger leaves it. A zone sends nothing but that press and its release - no
sequences, no repeats, and nothing the game did not receive from your touch.

Every one of these is virtual-controller input: nothing here issues a game command, runs a
macro, or inspects the game.

Open **Key / Button Configuration** for voice input:

1. Enable **Use a button to talk** and choose **Map a button**.
2. Press a supported keyboard key or controller control.
3. Choose **Hold to talk** or **Press to start and stop**.
4. Use **Test Voice** before opening the game, especially after changing a mapping.

The recogniser's own **Language** is in the draft composer beside the words it types: **System**
follows the iPad and is the default, and English, German, French and Spanish can be chosen
explicitly. It belongs to the recogniser and is never changed by the app's own language. A
language this iPad cannot recognise on the device falls back to System for that hold, and the
app says so.

Voice requires Microphone and Speech Recognition permission. The mapping can send text when
recognition completes or leave it for review; it can add a space after the text and accept
expected words. A mapped control can be withheld from the game while voice is active. Check
the controller-button collision warning before relying on a mapping—the safe choice depends
on the button bindings you use in the game.

## Help and safe recovery

Open **Settings → Technical details** for the app's current state and exact failure message.
Guest-owned alerts are recorded in the runtime log with a `[guest-alert]` marker and forwarded to
the launcher log as `guest-error class=guest-alert`. A recognized damaged-installation error is
recorded as `guest-error class=damaged-installation` and offers repair.

### Issue reports

Do not guess from a screenshot alone. Include all of the following:

1. The exact **Technical details** message and any **Game files need repair** message.
2. What you pressed, what you expected, what happened, and the local date/time and time zone.
3. On a Mac with the iPad connected, run these read-only commands and attach the resulting
   redacted output:

   ```sh
   wolkaraforever/tools/device_log.sh 400 '\\[guest-alert\\]|\\[host\\]|\\[native\\]|\\[wow-update\\]'
   wolkaraforever/tools/pilot.sh log 400 'guest-error|fatal|error|failed'
   ```

   The first command saves the complete runtime record at
   `build/device-log/native-guest.log` without stopping or restarting the app. The second reads
   launcher events without touching game files. Redact account names, credentials, API keys,
   signing data, pairing material, device identifiers, and unrelated personal paths before
   posting. Do not edit timestamps, error lines, or the surrounding context.

Do not delete the app as a first repair step: it removes downloaded game data. The
enrollment itself survives - the trust record is kept in the device's keychain, and the
app recovers its reference to it at the next launch - so a reinstall normally does not
mean enrolling again. If a download or startup fails, reopen the app, preserve its data,
and use the Technical details message to identify the next step.

For the boundary between feature availability and device-tested compatibility, see
[Compatibility](../COMPATIBILITY.md).

### iPhone render size

On iPhone Pro, Pro Max and Duo, **Balanced** renders at two pixels per window point;
**Performance** uses one. The default is Balanced for readability. These are resolution
choices, not frame-rate guarantees. iPad profiles retain their existing settings.
The first launch of a build with phone profiles migrates the old automatic, unknown-phone
profile to Balanced once. A manually selected device override is preserved.

The current window supplies the dimensions. Folding/unfolding Duo and rotating the device
update the virtual display mode; no fixed panel dimensions or iPad viewport are imposed.
Choose the render profile before starting the game. After a game session, close and reopen
WolkaraForever to apply a different profile. The game's graphics, interface scale and files
are not reset by this change.
