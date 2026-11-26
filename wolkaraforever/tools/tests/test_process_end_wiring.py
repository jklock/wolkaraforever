"""showClosingPage: in Shell/main.m never calls exit(); its three ends call WKEndProcess(0)."""
import pathlib
import re

main = pathlib.Path("wolkaraforever/Shell/main.m").read_text()
failures = []


def check(ok, name):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failures.append(name)


start = main.find("- (void)showClosingPage:")
end = main.find("\n}\n", start)
closing = main[start:end] if start >= 0 else ""
check(bool(closing), "showClosingPage: is found")
check(not re.search(r"(?<![\w_])exit\s*\(", closing), "the closing page never calls exit()")
check(len(re.findall(r"\bWKEndProcess\s*\(\s*0\s*\)", closing)) == 3,
      "no scene, Close and the countdown each end with WKEndProcess(0)")
check('#import "ProcessEnd.h"' in main, "main.m imports ProcessEnd.h")

raise SystemExit(bool(failures))
