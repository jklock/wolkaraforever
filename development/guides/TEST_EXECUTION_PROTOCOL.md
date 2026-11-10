# Test execution protocol

No policy, baseline, release, PR integration, tag, or device-validation work may start until the
owning focused fixture passes from a clean simulator container on every required matrix simulator.

For launcher UI work, the mandatory order is:

1. Run `wolkaraforever/tools/test_launcher_matrix.sh --fixture`.
2. Correct every failure and rerun from the beginning until it prints `WoW UIKit PASS`.
3. The runner executes iPhone Duo then iPad Pro 13-inch (M5), stops on the first failure, and
   retains terminal-streamed transcripts and `SUMMARY.txt` under `logs/launcher-matrix/`.
4. Record the complete screenshots only after both clean fixture passes with
   `UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE wolkaraforever/tools/test_launcher_matrix.sh --record`.
5. Rerun `wolkaraforever/tools/test_launcher_matrix.sh --check`; it compares all named PNGs
   before any broader suite.

Each active run writes an unredacted local transcript under `logs/live-tests/` and tails it to the
visible terminal. Do not redirect a live run exclusively to a temporary file. Check active runs
at least every five minutes; on exit, immediately inspect the transcript and either fix/restart
or advance to the next matrix step. A test failure is an active repair task, never a reason to
start unrelated policy or release work.
