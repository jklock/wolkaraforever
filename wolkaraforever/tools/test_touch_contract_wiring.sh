#!/bin/bash
# TouchPlay's button list is loaded by the app at game start, and Shell/main.m has no test of its
# own, so this reads it: the load happens once, in iPad touch mode only, in the game's folder and
# before the guest is entered, and the player is told (in the app's language) when it is missing.
# The reader itself is tested by test_touch_contract.m, run from test_touch_controls_ui.sh.
#
#   wolkaraforever/tools/test_touch_contract_wiring.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 -I - <<'PY'
import re, sys
main = open("wolkaraforever/Shell/main.m", encoding="utf-8").read()
failures = []

def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)

def body(source, signature):
    """The text of one method, from its signature to the closing brace in column 0."""
    start = source.find(signature)
    if start < 0:
        return ""
    end = source.find("\n}\n", start)
    return source[start:end if end > 0 else len(source)]

run = body(main, "- (void)runNativeGame:")
check('#import "../WoW/TouchContract.h"' in main, "main.m imports the contract reader")
check(len(re.findall(r"\bAKTouchContractLoadForGame\(", main)) == 1, "the contract is loaded from exactly one place")
load = run.find("AKTouchContractLoadForGame(")
chdir = run.find("chdir(directory.fileSystemRepresentation)")
enter = run.find("ng_initialize(")
check(0 <= chdir < load < enter, "the load is in runNativeGame, after the chdir into the game folder and before the guest is entered")
gate = run.rfind("AKInterfaceModeIsTouchPlay()", 0, load)
check(gate > chdir and re.search(r"if\s*\(\s*AKInterfaceModeIsTouchPlay\(\)\s*\)", run[gate - 6:gate + 40]) is not None,
      "the load is gated on iPad touch mode")
check("directory" in run[load:load + 160], "it is given the game folder (the working directory the app just entered)")
check('WKLocalized(@"touch.contract.missing")' in run, "a missing contract is shown with touch.contract.missing")
sys.exit(1 if failures else 0)
PY
