# Send us a log when something goes wrong

> Verified: 2026-11-17 · Source: `db5470a`

A log is a text file that records what the app was doing. When something fails, the log
usually says why, and it saves a lot of guessing. You do not need a Mac, a computer cable,
or any technical knowledge to send one — it is three taps on the iPad.

## The short version

1. Open WolkaraForever and stay on the home screen (the one with **Play**).
2. Tap **Settings** at the top right, then **Diagnostics and logs**.
   (On the app-library screen, the stethoscope icon opens the same page.)
3. Scroll to **Logs and reports**. The **newest file is at the top** — usually
   `wolkaraforever.log`, or `native-guest.log` if you have just played.
4. Tap it, then tap the **share icon** at the top right (a square with an arrow), and
   choose **Mail**, **Messages**, **AirDrop**, or **Save to Files**.
5. Send it with a couple of sentences about what went wrong — see
   [what to write](#what-to-write-with-the-log).

That is the whole procedure. The page you are reading has more detail for the times when
it does not go that smoothly.

## Which file to send

Send the **newest** file unless the situation below matches better.

| File | What it holds | Send it when |
| --- | --- | --- |
| `wolkaraforever.log` | What the launcher did: start-up, the game check and download, add-ons, settings, the interface | The launcher is slow, a row does nothing, a setting does not stick, a download or repair misbehaves |
| `native-guest.log` | The game and the compatibility layer **during a run** — including anything the game itself printed | The game crashed, would not start, showed a black or frozen screen, had no sound, or the controls or keyboard did wrong |
| `host-diagnostics.txt`, `*-probe.log`, `*-probe.txt` | The reports produced by the checks on the Diagnostics page | Only when you were asked to run a specific check — mention which one |

If you played and then sent `wolkaraforever.log` alone, the game part is missing. When in
doubt, send both: two small files are better than one that has to be asked for twice.

## If the app will not open at all

You can still get the files out, because the app keeps them in a folder iPadOS lets you
browse:

1. Open the **Files** app.
2. Tap **On My iPad**, then the folder named after the app (**WolkaraForever** unless you
   renamed your build).
3. Tap and hold the file you want, then **Share**.

With a Mac and a cable you can instead open **Finder**, select the iPad, open the **Files**
tab, find the app, and drag the files out. No cable and no computer is needed for the Files
app route.

## If you are on a Mac and have the project

These read the app's own logs from the iPad without disturbing a running game — they copy a
file, they do not attach to the app:

```sh
wolkaraforever/tools/device_log.sh 200          # the last 200 lines of the run log
wolkaraforever/tools/device_log.sh 120 error    # only lines matching "error"
wolkaraforever/tools/pilot.sh log 80            # the launcher's own log
```

`device_log.sh` reads `native-guest.log`; `pilot.sh log` reads `wolkaraforever.log`. Both
need `DEVICE` and `TOLKARA_BUNDLE_ID` set in your `local.env`.

## What to write with the log

Five short lines are plenty:

1. **What you expected** — "I expected the game to start".
2. **What happened instead** — "It showed a black screen", "It closed after the loading
   bar", "The keyboard typed nothing".
3. **What you did just before** — "Chose German, then pressed Play", "Connected a
   controller", "Opened the add-on manager".
4. **Today's date and the time it happened** — to the nearest few minutes, so the right part
   of the log can be found.
5. **Your setup** — the mode you chose (Developer service, External JIT, or Local signing),
   which game edition, the iPad model and iPadOS version (**Settings → General → About** on
   the iPad), and the app version from **About and open-source licenses** in the app's
   Settings.

Screenshots help too, especially for anything visual. Take them before you restart the app
if you can.

## What is in a log, and what is not

The logs are technical text: timings, file names, error messages, and what the game asked
for. They do **not** contain your Apple Account password, payment details, or your pairing
or signing files.

You are welcome to open a log and read it before sending — it is plain text. If you would
rather not share a line that mentions a folder path or a device name, say so and we will tell
you which lines matter; you can blank the rest.

Never send:

- passwords, or an Apple Account e-mail and password;
- signing certificates, provisioning profiles, or anything from your keychain;
- pairing records or anything from `authorized_keys`-style files.

Do not delete or reinstall the app as a first step. The log you would need is deleted with
it, and most problems are configuration, which reinstalling does not change.

## When the instructions above do not fit

| What you see | What to do |
| --- | --- |
| **Logs and reports** says "No logs yet" | Nothing has been logged in this install. Open the game once (even if it fails), come back, and the list will be there |
| The list is long and you cannot tell which file is which | The top one is the newest. Its name is in the row; tap it and the first lines say when the app started |
| The share sheet has no Mail | Choose **Save to Files**, then attach the saved file to an e-mail or a message |
| The file is very large | The viewer shows only the last part; that is normal. Share the **file** — the full log is what is wanted |
| You cannot find a log for the game | `native-guest.log` appears after the game has actually run at least once. Start the game, let it fail, then send it |
| Someone asked you for "the exact Technical details message" | In the app's **Settings** sheet, choose **Technical details** when it is offered (it appears after a failure) and copy the text it shows. It is one line, and it goes with the log |
