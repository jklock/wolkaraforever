# How the simulator suites build, install and run their fixtures. Sourced by the touch suites
# after simulators.sh, once simulator_use has set SIM_ID.
#
# fixture_step <label> <command...>
#     Runs one slow step under a time limit (FIXTURE_STEP_LIMIT seconds, 300 by default; a
#     compile gets FIXTURE_COMPILE_LIMIT, 900, and a first boot 900) and names it first. Past
#     the limit it fails with 124 and names the step and its pid; it kills nothing (a hang is
#     reported, never repaired), so the hung step is left for whoever runs the suite. A stuck
#     compiler or simctl call then fails within minutes and says which step it was, instead of
#     holding the job until something outside cancels it: measured on 2026-11-21, a hosted
#     runner's clang and ld sat for 13 minutes on a fixture that normally compiles in seconds,
#     and the run ended "cancelled" with no hint of where.
#
# fixture_compile <xcrun ... -o OUTPUT ...>
#     The compile, skipped when OUTPUT exists and nothing it reads has changed (the arguments,
#     every input file and every file under each -I folder). The binaries live in the prepared
#     tree, which prepare.sh rebuilds whenever anything it is made from changes, so a reused
#     binary can only ever come from the same tree. The second call of a suite (the gamepad's
#     --self-test-input) reuses the first call's binary instead of compiling it again.
#
# fixture_refuse_if_running <bundle id>
#     Fails, naming the app and its pid, when that app is already running on the simulator
#     (SIM_ID), and ends nothing: a running app or session is left alone, and whoever started it
#     decides. Called before a fixture is installed or launched, since `simctl install` and
#     `uninstall` end a running copy just as `launch --terminate-running-process` would.
#
# fixture_launch <log> <bundle id> [arguments...]
#     Launches the fixture, waits for that process to exit (at most FIXTURE_STEP_LIMIT
#     seconds; past that it fails with 124 and leaves the fixture running, killing nothing)
#     and writes everything it said to <log>, relative or absolute, replacing what was there,
#     so the suite can grep it. Keep <log> in the prepared tree or the repository, never the
#     system temp folder: the simulator's app cannot write there, and its output would be
#     lost. Not `simctl launch --console`: the console relay drops the end of a run. Measured
#     on 2026-11-21: a controls self-test logged its PASS line at 14:19:36 and exited normally
#     (status 0, voluntary) at 14:19:40, and the console capture stopped at 14:19:35, so the
#     suite reported a failure the test did not have; flushing in the fixture before exit did
#     not change it. Here the app writes stdout and stderr straight to files, and that
#     process's own entries in the simulator's system log (where NSLog lands) are added,
#     matched by its pid so an earlier launch can never count.

FIXTURE_STEP_LIMIT=${FIXTURE_STEP_LIMIT:-300}

fixture_step() {
    local label=$1 deadline=$((SECONDS + FIXTURE_STEP_LIMIT)) pid out status
    shift
    echo "step: $label" >&2
    # The step's output goes to a file, read back only once it has finished: a step left running
    # past its limit would otherwise hold a caller's $(...) open, and the caller would hang too.
    out=$(mktemp "${TMPDIR:-/tmp}/fixture-step.XXXXXX")
    "$@" > "$out" &
    pid=$!
    # `kill -0` sends no signal: it only asks whether the process is still running.
    while kill -0 "$pid" 2> /dev/null; do
        sleep 0.2
        # Wall-clock seconds, not a count of sleeps: on a loaded machine each sleep overruns.
        if (( SECONDS > deadline )); then
            # A hang is reported, never repaired: nothing is killed. The step is named and left
            # running for whoever runs the suite to deal with; the suite fails here.
            echo "time limit: '$label' still running after ${FIXTURE_STEP_LIMIT} s" \
                "(pid $pid); left running, not killed" >&2
            return 124
        fi
    done
    status=0
    wait "$pid" || status=$?
    cat "$out"
    rm -f "$out"
    return "$status"
}

fixture_refuse_if_running() {
    local bundle=$1 apps pid
    # The simulator's launchd lists each app as UIKitApplication:<bundle id>[...], with its pid
    # while it runs and "-" once it has exited. A check that cannot answer refuses too. It gets a
    # launch's limit: on a just-booted simulator this call took over a minute on a hosted runner
    # (2026-11-24), as `simctl launch` itself does.
    apps=$(FIXTURE_STEP_LIMIT=${FIXTURE_LAUNCH_LIMIT:-300} \
        fixture_step "check that $bundle is not running" xcrun simctl spawn "$SIM_ID" launchctl list) || {
        echo "fixture: could not tell whether $bundle is running; not starting it" >&2
        return 1
    }
    pid=$(printf '%s\n' "$apps" |
        awk -v label="UIKitApplication:$bundle[" \
            'index($3, label) == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }')
    if [ -n "$pid" ]; then
        echo "fixture: $bundle is already running on this simulator (pid $pid); not ending it -" \
            "quit it, then run the suite again" >&2
        return 1
    fi
}

fixture_compile() {
    local arg out= previous= key
    local -a inputs=()
    for arg in "$@"; do
        if [[ "$previous" == -o ]]; then
            out=$arg
        elif [[ "$arg" == -I* && -d "${arg#-I}" ]]; then
            inputs+=("${arg#-I}")
        elif [[ -f "$arg" ]]; then
            inputs+=("$arg")
        fi
        previous=$arg
    done
    [[ -n "$out" ]] || { echo "fixture_compile: no -o in: $*" >&2; return 2; }
    # ${inputs[@]+...}: macOS's bash 3.2 treats an empty array as unset under `set -u`.
    key=$({ printf '%s\n' "$@"
            [ ${#inputs[@]} -eq 0 ] || find ${inputs[@]+"${inputs[@]}"} -type f -print0 | sort -z | xargs -0 shasum
          } | shasum | cut -d' ' -f1)
    if [[ -f "$out" && "$(cat "$out.inputs" 2> /dev/null)" == "$key" ]]; then
        echo "step: compile of $out reused, nothing it reads has changed" >&2
        return 0
    fi
    rm -f "$out.inputs"
    # A compile gets longer than the other steps: on a hosted runner whose simulators are still
    # in their first boot, the launcher fixture's compile took over five minutes (2026-11-22)
    # and the default limit stopped a healthy step. 15 minutes still catches a hang.
    FIXTURE_STEP_LIMIT=${FIXTURE_COMPILE_LIMIT:-900} fixture_step "compile of $out" "$@"
    printf '%s\n' "$key" > "$out.inputs"
}

fixture_launch() {
    local log=$1 bundle=$2 line pid base stdio_out stdio_err
    shift 2
    case "$log" in /*) base=$log ;; *) base=$PWD/$log ;; esac
    rm -f "$base.stdout" "$base.stderr"
    # A copy already running is left alone: the launch fails, named, rather than end it.
    fixture_refuse_if_running "$bundle" 2>&1 | tee "$log" >&2
    [ "${PIPESTATUS[0]}" = 0 ] || return 1
    # The simulator's launchd opens these files itself, and it is refused a path on a volume other
    # than the boot volume: with `--stdout` in a tree on an external disk, `simctl launch` answers
    # "did not return a process handle nor launch error" and the app never starts (measured
    # 2026-11-25). The console is captured under TMPDIR and copied to the caller's path after the
    # fixture has finished; the app keeps writing to that same descriptor throughout the run.
    stdio_out=$(mktemp "${TMPDIR:-/tmp}/fixture-launch-out.XXXXXX")
    stdio_err=$(mktemp "${TMPDIR:-/tmp}/fixture-launch-err.XXXXXX")
    # The launch command gets its own limit: the caller's FIXTURE_STEP_LIMIT is for the run that
    # follows, and on a just-booted simulator `simctl launch` alone took over a minute on a hosted
    # runner (2026-11-22), which a suite's 60 s run limit then stopped.
    line=$(FIXTURE_STEP_LIMIT=${FIXTURE_LAUNCH_LIMIT:-300} fixture_step "launch of $bundle" xcrun simctl launch \
        --stdout="$stdio_out" --stderr="$stdio_err" "$SIM_ID" "$bundle" "$@")
    pid=${line##*: }
    echo "$line"
    # A launch that never started still leaves a log, so the suite's own checks read something.
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        cp "$stdio_out" "$base.stdout" 2> /dev/null || true
        cp "$stdio_err" "$base.stderr" 2> /dev/null || true
        rm -f "$stdio_out" "$stdio_err"
        echo "fixture_launch: no pid in: $line" | tee "$log" >&2
        return 1
    fi
    # The fixtures stop themselves: each has a 30-second watchdog. This is the backstop, and it
    # reports rather than repairs: a fixture still running at the limit is named, left running,
    # and the launch fails after writing what the fixture said so far.
    local deadline=$((SECONDS + FIXTURE_STEP_LIMIT)) hung=
    while kill -0 "$pid" 2> /dev/null; do
        sleep 0.2
        if (( SECONDS > deadline )); then
            hung="time limit: $bundle (pid $pid) still running after ${FIXTURE_STEP_LIMIT} s; left running, not killed"
            echo "$hung" >&2
            break
        fi
    done
    {
        cat "$stdio_out" "$stdio_err" 2> /dev/null || true
        echo "--- the system log of $bundle ($pid) ---"
        xcrun simctl spawn "$SIM_ID" log show --last 15m --style compact \
            --predicate "processIdentifier == $pid" 2> /dev/null || true
        [ -z "$hung" ] || echo "$hung"
    } | tee "$log"
    cp "$stdio_out" "$base.stdout" 2> /dev/null || true
    cp "$stdio_err" "$base.stderr" 2> /dev/null || true
    rm -f "$stdio_out" "$stdio_err"
    [ -z "$hung" ] || return 124
}
