# Changelog

> Verified: 2026-11-13 · Source: `3c33543`

## Unreleased

- **The unsigned package is named after the app.** It is `wolkaraforever-unsigned.ipa`,
  not `Tolkara-unsigned.ipa`, from the packaging script, the verification report and the
  release that carries it.
- **The unsigned `.ipa` can log in.** It was built without this Mac's public root
  certificates, so the client could not validate Battle.net's certificate and
  answered `BLZ51900003` on every attempt, with the experimental Battle.net login
  on and off. Every package this toolchain builds now carries the same
  certificates as a build from your own Mac, and the packaging and verification
  scripts refuse one that does not.
- **The experimental Battle.net login can keep one game password.** With that opt-in feature on, a
  yellow key on the keyboard's row appears while the game's password field has the keyboard: it
  types a password you chose to save on the device, behind Face ID or the device passcode, and
  holding it forgets it. The password is a Keychain item on this device only - never synchronised,
  never logged, never written into the game's files - and it is deleted when the feature is turned
  off or **Clear sign-in data** is used. **Sign in with the saved password** starts the game
  without opening the browser. The key is part of that feature, so it does not exist anywhere else,
  and its row now stays inside the safe area instead of running under a phone's camera cut-out.
- **The iPad Pro 11-inch (M5) has its own device profile.** It was not in the table, so it got the fallback: Performance only (908 × 626). Its measured record (`iPad17,1`) also offers Balanced (1210 × 834) and **Quality at the panel's own 2420 × 1668**, which asks first. The default stays Performance, so nothing changes until Quality is picked.
- **The render-profile confirmation says what a choice costs, on every device.** It used to say that the higher choice was measured missing the frame budget, which was only measured on the 12.9-inch M1. It now says what Quality or Balanced draws and that it takes more graphics work, then adds a measured sentence only where that device's record has one (the 12.9-inch M1 keeps its missed budget; the 11-inch M5 says about 2.5 times the graphics work of Performance). In en, de and fr.
- **A dropped connection no longer stalls the game download.** The retry wait now always has a real scheduler, so it cannot spin while holding the download lock and block transfers or Cancel.

## v1.0.19

- **Controller touchpad as mouse.** In **Input Manager**, configure and test an opt-in DualSense or DualShock touchpad pointer with saved speed, live coordinates, one-finger movement, two-finger scrolling, and physical-click buttons. DualSense and DualShock use iPadOS's controller profile touchpad path; DualSense Edge users whose Bluetooth connection omits touch reports can use USB-C.
- **Input Manager organization.** Dictation is now under **Key / Controller Button Configuration**, and controller-touchpad setup has its own **Controller Touchpad Configuration** page.
- **UI Manager cleanup.** Gamepad UI is first, retains its selected state while saving, Backup appears before Restore, and the reset action is named **Reset to Default Wow UI Configuration**.
- **Add-on access controls.** CurseForge key controls moved to the top-bar menu and correctly save edited keys.
- **Operational documentation.** Added a plain-language guide for sending logs and audited the build/run surface.

## v1.0.18

- Documentation now separates standalone user guidance from the agent-only operational catalog.
- **My Add-ons no longer sits on "Updating…".** "Never asked" is its own state, **Not checked yet**, with a **Check** action that runs the check; *Checking…* appears only while a request is genuinely in flight, and a sweep with no key clears its own in-flight marks and says why. Opening **My Add-ons**, and **Refresh**, still ask the provider about every linked package.
- **Update All settles.** The batch used to advance before each archive write committed and re-asked the packages it had just reported, so every row returned to **Not checked yet**. It now finishes on the archive transaction, keeps the settled answer, and ends with every row up to date.
- **Installed rows carry their CurseForge thumbnail.** The project's artwork is kept with the package's provider identity, and the whole page is filled in one provider query rather than one request per row; a package with no recorded identity keeps the neutral placeholder.
- **A first run without a provider key has a door.** Browse and Discover each offer **Set up access**, which opens the key sheet; with a key the Sort and Filter rows open the sheets they name.
- **Backup Add-ons and Restore Add-ons**: the whole add-on folder as one ZIP under `WTF/Backups/`, restorable transactionally, and neither row reaches the network.
- **The four Controller Layout decisions are four rows**: create, edit, restore and back up, the last through the system share sheet.
- **The in-app add-on browser no longer opens during a transition**, which removes UIKit's unbalanced begin/end appearance transitions.
- A disabled Voice page stays readable while its controls remain off.

## v1.0.16

- Added a native Add-on Hub.
- Added explicit dictation-language controls.
- Added touch-controller and bounded controller-command improvements.
- Added review-then-send Chat Composer behavior.
- Improved enrollment, stale-log, and reliability handling.

## Earlier releases

Earlier releases established the Forever launcher, interface modes, localization, add-on handling, UI recovery, voice, diagnostics, and source-built installation. Use the current guides for supported behavior rather than historical release notes.
