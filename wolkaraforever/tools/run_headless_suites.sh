#!/bin/bash
# Every suite that needs neither a simulator nor a device, run in one place.
#
# The layer's suites are hermetic: they compile a fixture with clang and run it,
# or drive a script against a stub of `simctl`/`devicectl`. The two matrix
# simulators are the exception - they are Xcode 26 device types, so the hosted
# images cannot create them - and so are the UI fixtures that boot them. Those
# stay a local run; everything else belongs in the pipeline.
#
# The default is to RUN a suite. The exempt list below is explicit and each line
# says why, so a suite added tomorrow runs in CI without anyone remembering to
# add it here - the failure mode this repository has already paid for twice, with
# suites that existed for weeks and were run by nothing.
#
#   wolkaraforever/tools/run_headless_suites.sh          every suite, one after another
#   wolkaraforever/tools/run_headless_suites.sh --list   what would run, and what would not
#
# `validate.sh` is the superset for a machine with the two matrix simulators: it
# adds the UI fixtures, the UI policy and the device rows.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

list_only=0
[ "${1:-}" = "--list" ] && list_only=1

# Why a suite cannot run here. A name here is not a failure: the reason is printed.
exempt_reason() {
    case "$1" in
        test_addon_hub_live.sh)        echo "boots the iPad simulator";;
        test_appkit_content_view.sh)   echo "boots a simulator";;
        test_audio_sim.sh)             echo "boots a simulator";;
        test_background_pacing_sim.sh) echo "boots a simulator";;
        test_controller_input.sh)      echo "boots a simulator";;
        test_enrollment_reference_sim.sh) echo "boots a simulator, and reads the Keychain";;
        test_launcher_matrix.sh)       echo "runs the UI fixture on both matrix devices";;
        test_touch_controls_ui.sh)     echo "boots a simulator";;
        test_touch_gamepad_ui.sh)      echo "boots a simulator";;
        test_translation_sim.sh)       echo "boots a simulator";;
        test_voice.sh)                 echo "boots a simulator";;
        test_wow_launcher_ui.sh)       echo "boots a simulator";;
        # Not a suite: a dispatcher over the suites below, and it wants a device.
        test_install.sh)               echo "a dispatcher over the other suites, and it installs";;
        # The wrapper that includes the exempt simulator suites above.
        test_emulation.sh)             echo "the wrapper: it runs the simulator suites too";;
        *) return 1;;
    esac
}

ran=0
declare -a failed=() skipped=()

# tools/tests/ first: they are seconds each and they test the tools everything
# else below is driven through.
for suite in wolkaraforever/tools/test_*.sh wolkaraforever/tools/tests/*.sh; do
    [ -f "$suite" ] || continue
    name=$(basename "$suite")
    case "$suite" in
        *run_headless_suites.sh) continue;;
    esac
    if reason=$(exempt_reason "$name"); then
        skipped+=("$name - $reason")
        [ "$list_only" = 1 ] && printf 'skip  %s (%s)\n' "$name" "$reason"
        continue
    fi
    if [ "$list_only" = 1 ]; then
        printf 'run   %s\n' "$name"
        continue
    fi
    printf '\n== %s\n' "$name"
    if bash "$suite"; then
        ran=$((ran + 1))
    else
        failed+=("$name")
    fi
done

if [ "$list_only" = 1 ]; then
    exit 0
fi

printf '\nheadless suites: %d run, %d failed, %d not run here\n' \
    "$ran" "${#failed[@]}" "${#skipped[@]}"
if [ "${#skipped[@]}" -gt 0 ]; then
    printf '  not run here (needs the simulator matrix or a device):\n'
    printf '    %s\n' "${skipped[@]}"
fi
if [ "${#failed[@]}" -gt 0 ]; then
    printf '  FAILED: %s\n' "${failed[@]}"
    exit 1
fi
exit 0
