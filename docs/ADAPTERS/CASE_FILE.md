# Tolkara performance case file: validated evidence only

## Status

The previous case file is retracted. Its quoted 43.0 fps median, 29.7 fps
minimum, 44.4/43.7 fps resolution comparison, and 36 fps thermal samples are
not present in the file it cites (`build/device-log/native-guest.log`). They
were not reproducible from this checkout, so they are not evidence.

The available log is a World of Warcraft run: it records the guest window and
then `World of Warcraft`, followed by Metal frame timing. Its 16 five-second
samples are 60.0--60.2 fps (median 60.0), at the native 2732x2048 drawable.
This proves only that this recorded run met the 60 fps presentation cap. It does
not prove sustained in-world performance, thermal behavior, or the benefit of
the changes below.

## Reproducible facts

| Claim | Status | Proof |
| --- | --- | --- |
| The recorded guest run presented at 60.0--60.2 fps in 16 five-second samples. | MEASURED | `build/device-log/native-guest.log:14136-14172` |
| That run used a 2732x2048 drawable, despite a 1366x1024 content-size line. | MEASURED | `build/device-log/native-guest.log:14103,14117-14118` |
| The AppKit event pump performed 4,000 zero-date polls and 4,000 one-millisecond run-loop turns, totaling 4,617 ms. | MEASURED | `build/device-log/native-guest.log:14151,14166` |
| The installed device app was built from the Debug product path. | PROVEN-CODE | `platform/tools/install.sh:35-41` |
| Adapter shims were compiled with `-O1`. | PROVEN-CODE | `platform/tools/build_shims.py:38-39` |
| The source does not establish CPU submission time, command-buffer waits, thermal degradation, or a resolution A/B. | UNKNOWN | No corresponding instrumentation result exists in the cited log. |

The fourth fact is a real, bounded layer cost: 4,617 / 4,000 = 1.154 ms per
poll. The log's frame counts make it consistent with roughly one poll per
presented frame, but that attribution is an inference, not a benchmark of every
game workload.

## Changes made

1. Patch `0024-appkit-event-pump-cost.patch` changes a nonblocking event poll
   from a one-millisecond `CFRunLoopRunInMode` to a zero-duration turn. Ready
   UIKit work still runs; an idle frame no longer deliberately waits one
   millisecond.
2. Patch `0025-release-performance-build.patch` makes device installs use the
   Release product and compiles adapter shims at `-O2`. It deliberately does not
   add LTO without device evidence.

These changes are source-validated, not performance-proven until the exact
candidate is built, installed, and measured on Dadpad.

## Required device proof

Use the same scene, settings, execution mode, and a cold-start/thermal protocol
for a baseline and this candidate. Record:

- candidate commit SHA and whether `--measure-native` is enabled;
- 5-second presentation windows for at least 15 minutes, including the worst
  one-percent and longest frame gap;
- event-pump polls, turns, and milliseconds;
- drawable size, CPU submission time (`nextDrawable` return to final `commit`),
  `waitUntilCompleted`/`waitUntilScheduled` counts, and thermal state.

Do not claim a frame-rate gain unless those two runs differ only by the candidate
and the candidate's raw logs are retained.

## Commands

Run from the repository root.

```sh
# Current log facts; expected: 16 samples, min/median 60.0, max 60.2.
python3 - <<'PY'
import re
values = [float(m.group(1)) for line in open('build/device-log/native-guest.log')
          if (m := re.search(r'fps=([0-9.]+)', line))]
assert values, 'no fps samples'
values.sort()
print(f'n={len(values)} min={values[0]:.1f} median={values[(len(values)-1)//2]:.1f} max={values[-1]:.1f}')
PY
rg -n 'World of Warcraft|window content size|Metal drawable 1 acquired|pump polls=' build/device-log/native-guest.log

# Ensure every layer change applies cleanly to the pinned platform.
wolkaraforever/tools/check_layers.sh
```
