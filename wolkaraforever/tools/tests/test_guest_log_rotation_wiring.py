"""main.m keeps the previous game log before each truncation and reports the result once."""
import pathlib
import re

main = pathlib.Path("wolkaraforever/Shell/main.m").read_text()
failures = []


def check(ok, name):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failures.append(name)


def body(signature):
    start = main.find(signature)
    if start < 0:
        return ""
    end = main.find("\n}\n", start)
    return main[start:end if end >= 0 else len(main)]


for method in ("- (void)refuseNativeGame:", "- (void)runNativeGame:"):
    source = body(method)
    if method.endswith("runNativeGame:"):
        opens = list(re.finditer(r"\bfopen\s*\(\s*logPath\.fileSystemRepresentation\s*,\s*\"w\"\s*\)", source))
    else:
        opens = list(re.finditer(r"\bfopen\s*\([^;]*native-guest\.log[^;]*[\"']w[\"']\s*\)", source, re.S))
    check(len(opens) == 1, f"{method} opens the current log once")
    if opens:
        before = source[:opens[0].start()]
        check(re.search(r"WKGuestLogKeepPrevious\s*\(\s*(?:logPath|[^,]+),\s*[^,]*native-guest\.previous\.log", before, re.S) is not None,
              f"{method} keeps the previous log before truncating the current one")

run = body("- (void)runNativeGame:")
refuse = body("- (void)refuseNativeGame:")
for suffix in ("moved to native-guest.previous.log", "none", "not kept ("):
    check("previous session's log: " + suffix in run, f"a game start reports '{suffix}'")
for value, message in (("Moved", "moved to native-guest.previous.log"), ("Nothing", "none")):
    check(re.search(r"(?:if|else if)\s*\(\s*kept\s*==\s*WKGuestLogKeep" + value +
                    r"\s*\)\s*fprintf\s*\([^;]*previous session's log: " + re.escape(message), run, re.S) is not None,
          f"{value} reports its own result")
check(run.find("previous session's log:") > run.find("fopen("), "the report follows a successful open")
check("previous session's log:" not in refuse, "a refused start adds no previous-session line")

raise SystemExit(bool(failures))
