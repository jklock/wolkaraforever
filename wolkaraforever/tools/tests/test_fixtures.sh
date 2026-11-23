#!/bin/bash
# The simulator suites' fixture helpers, without a simulator: a stub xcrun stands in for the
# compiler and for simctl. Covers a hung step failing, named and left running (nothing is killed),
# a running copy of a fixture refusing a launch rather than being ended, a failure staying a
# failure, a compile reused only while nothing it reads is unchanged, and a launch whose
# output reaches the log even though the console never sees it, whether the log path is
# relative or absolute and even when the launch never started.
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
work=$(mktemp -d -t wolkaraforever-fixtures)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tree/inc"

cat > "$work/bin/xcrun" <<'SHIM'
#!/bin/bash
# The compiler: count the compiles and write the -o output.
if [ "${1:-}" = --sdk ]; then
    echo compiled >> "$STUB_COMPILES"
    previous=
    for arg; do [ "$previous" = -o ] && echo binary > "$arg"; previous=$arg; done
    exit 0
fi
case "${1:-} ${2:-}" in
"simctl launch")
    # Every launch is recorded, so a test can see whether one happened and with what.
    echo "$*" >> "$STUB_LAUNCHES"
    # A bundle that is not installed: simctl's own refusal, and no pid.
    for arg; do [ "$arg" = org.tolkara.tests.missing ] && { echo "launch failed: not installed" >&2; exit 4; }; done
    # Print the pid line the real one prints, then run a short-lived "app" that writes its
    # result straight to the --stdout file and exits, as the fixtures do.
    out=
    for arg; do case "$arg" in --stdout=*) out=${arg#--stdout=};; esac; done
    ( sleep 1; echo "TOUCH_UI_SELF_TEST_PASS: stub" > "$out" ) &
    echo "org.tolkara.tests.stub: $!"
    ;;
"simctl spawn")
    case " $* " in
    *" launchctl list "*)
        # The simulator's launchd: one app that has exited, and the one named in
        # STUB_RUNNING still running.
        echo "PID	Status	Label"
        echo "-	0	UIKitApplication:org.tolkara.tests.stub[1a2b][rb-legacy]"
        [ -z "${STUB_RUNNING:-}" ] || echo "4242	0	UIKitApplication:$STUB_RUNNING[9c8d][rb-legacy]"
        ;;
    *) echo "stub system log" ;;
    esac
    ;;
*) exit 2 ;;
esac
SHIM
chmod +x "$work/bin/xcrun"
export PATH="$work/bin:$PATH" STUB_COMPILES="$work/compiles" STUB_LAUNCHES="$work/launches"

checks=0
# check <what> <command...>: the command decides, and a failure names the check before stopping.
check() { local what=$1; shift; checks=$((checks + 1)); "$@" || { echo "FAIL: $what"; exit 1; }; }

cd "$work/tree"
. "$root/wolkaraforever/tools/fixtures.sh"
SIM_ID=stub-simulator

FIXTURE_STEP_LIMIT=1
start=$SECONDS
set +e
fixture_step "a hung step" sleep 4 2> "$work/hung.err"
rc=$?
set -e
check "a hung step fails with 124" [ "$rc" = 124 ]
check "a hung step fails near its limit, not after it finishes" [ $((SECONDS - start)) -lt 3 ]
check "a failed step says which step it was" grep -q "time limit: 'a hung step'" "$work/hung.err"
hung=$(sed -n 's/.*(pid \([0-9]*\)).*/\1/p' "$work/hung.err")
# A hang is reported, never repaired: the step is still running, not killed.
check "a hung step is left running, not killed" kill -0 "$hung"
start=$SECONDS
set +e
answer=$(fixture_step "a hung step in a substitution" sleep 4 2> /dev/null)
set -e
check "a hung step left running does not hold its caller's \$(...) open" [ $((SECONDS - start)) -lt 3 ]
check "a finished step still hands its output back" [ "$(fixture_step "an echo" echo hello 2> /dev/null)" = hello ]

FIXTURE_STEP_LIMIT=10
set +e
fixture_step "a failing step" false 2> /dev/null
rc=$?
set -e
check "a failing step keeps its own exit code" [ "$rc" = 1 ]
check "a longer limit for one step lets it finish" eval 'FIXTURE_STEP_LIMIT=20 fixture_step "a slow step" sleep 2 2> /dev/null'
check "a limit given for one step does not outlive it" [ "$FIXTURE_STEP_LIMIT" = 10 ]

echo 'int x;' > a.m
echo one > inc/h.h
compile() { fixture_compile xcrun --sdk iphonesimulator clang -Iinc a.m -o out.bin 2> /dev/null; }
compiles() { wc -l < "$STUB_COMPILES" | tr -d ' '; }
compile
check "the first compile runs" [ "$(compiles)" = 1 ]
compile
check "an unchanged compile is reused" [ "$(compiles)" = 1 ]
echo two > inc/h.h
compile
check "a changed header compiles again" [ "$(compiles)" = 2 ]
echo 'int y;' > a.m
compile
check "a changed source compiles again" [ "$(compiles)" = 3 ]
rm out.bin
compile
check "a missing output compiles again" [ "$(compiles)" = 4 ]

fixture_launch run.log org.tolkara.tests.stub > /dev/null 2>&1
check "the app's own output reaches the log" grep -q "TOUCH_UI_SELF_TEST_PASS: stub" run.log
check "the app's system log is added to the log" grep -q "stub system log" run.log
fixture_launch "$work/absolute.log" org.tolkara.tests.stub > /dev/null 2>&1
check "an absolute log path works" grep -q "TOUCH_UI_SELF_TEST_PASS: stub" "$work/absolute.log"
check "a launch that never started fails" eval '! fixture_launch missing.log org.tolkara.tests.missing > /dev/null 2>&1'
check "a launch that never started still leaves a log" grep -q "no pid" missing.log
check "a launch never ends a running copy" eval '! grep -q -- --terminate-running-process "$STUB_LAUNCHES"'

# A copy already running is left alone: the launch fails, named, and never happens.
: > "$STUB_LAUNCHES"
set +e
STUB_RUNNING=org.tolkara.tests.stub fixture_launch running.log org.tolkara.tests.stub > /dev/null 2> "$work/running.err"
rc=$?
set -e
check "a launch over a running copy fails" [ "$rc" != 0 ]
check "and says which app and pid" grep -q "org.tolkara.tests.stub is already running on this simulator (pid 4242)" "$work/running.err"
check "and that log says so too" grep -q "already running" running.log
check "and launches nothing" [ ! -s "$STUB_LAUNCHES" ]
check "an app that has exited does not count as running" fixture_refuse_if_running org.tolkara.tests.stub 2> /dev/null
check "another app running does not block this one" eval 'STUB_RUNNING=org.tolkara.tests.other fixture_refuse_if_running org.tolkara.tests.stub 2> /dev/null'

echo "fixtures: $checks checks PASS"
