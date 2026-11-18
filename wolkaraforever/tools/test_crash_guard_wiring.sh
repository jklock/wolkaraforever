#!/bin/bash
# The iPad touch crash fallback is only as good as the places that call it. Shell/main.m has no
# test of its own, so this reads it: the session is begun once, before the guest is entered, and
# every way a game can end well or never start is one of the session functions - so deleting a
# call, or going back to the bare primitives, fails here. The behaviour of the functions
# themselves is in test_touch_gamepad_ui.sh.
#
#   wolkaraforever/tools/test_crash_guard_wiring.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 -I - <<'PY'
import re, sys
main = open("wolkaraforever/Shell/main.m", encoding="utf-8").read()
launcher = open("wolkaraforever/WoW/WoWViewController.m", encoding="utf-8").read()
failures = []

def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)

def body(source, signature):
    """The text of one method or function, from its signature to the closing brace in column 0."""
    start = source.find(signature)
    if start < 0:
        return ""
    end = source.find("\n}\n", start)
    return source[start:end if end > 0 else len(source)]

calls = lambda name, text: len(re.findall(r"\b%s\(\)" % name, text))

check(calls("AKTouchCrashGuardBeginSession", main) == 1, "main.m begins the session exactly once")
run = body(main, "- (void)runNativeGame:")
begin = run.find("AKTouchCrashGuardBeginSession()")
enter = run.find("ng_initialize(")
check(0 <= begin < enter, "the session begins inside runNativeGame, before ng_initialize enters the guest")
check(re.search(r"if\s*\(ok\)\s*AKTouchCrashGuardEndSession\(\);\s*else\s*AKTouchCrashGuardAbandonSession\(\);", run) is not None,
      "a guest that returned ends the session, and one that did not start abandons it")
check(run.find("AKTouchCrashGuardEndSession()") > enter, "the end follows the guest's return")
check("AKTouchCrashGuardEndSession()" in body(main, "- (void)closeAfterGuestRefusedToQuit:"),
      "the user's Leave game ends the session")
check("AKTouchCrashGuardEndSession()" in body(main, "static void GuestExitObserver"),
      "the guest's exit observer (_exit(0), which skips atexit) ends the session")
check(calls("AKTouchCrashGuardEndSession", main) == 3 and calls("AKTouchCrashGuardAbandonSession", main) == 1,
      "no other call sites: three ends, one abandon")
check(not re.search(r"AKTouchCrashGuard(WillStart|DidExitCleanly)", main),
      "main.m goes through the session functions, never the bare primitives")
# Every other interface mode keeps the guest's exit observer it had: the cloud path's own flush. Only
# iPad touch swaps in the observer that also ends the session.
check(re.search(r"if\s*\(\s*AKInterfaceModeIsTouchPlay\(\)\s*\)\s*ng_set_exit_observer\(GuestExitObserver", run) is not None,
      "the session's exit observer is installed in iPad touch only")
check("ng_set_exit_observer(FlushSteamCloudAtExit" in run, "every other mode keeps the cloud path's own exit observer")
check(calls("AKTouchCrashGuardApplyFallback", launcher) == 1 and
      "AKTouchCrashGuardApplyFallback()" in body(launcher, "- (void)presentTouchFallbackIfNeeded"),
      "the launcher applies the fallback in one place")
guard = body(launcher, "- (void)presentTouchFallbackIfNeeded")
guard_at, apply_at = guard.find("_starting || _running || _sessionUsed"), guard.find("AKTouchCrashGuardApplyFallback")
check(0 <= guard_at < apply_at, "the fallback is never applied while a game is starting, running or finished")
view = body(launcher, "- (void)viewDidAppear:")
check("presentTouchFallbackIfNeeded" in view, "the fallback is looked at whenever the launcher appears")
sys.exit(1 if failures else 0)
PY
