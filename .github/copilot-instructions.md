# Documentation instructions

Before changing a tracked file, read `docs/agent/README.md`, the applicable catalog entry, and the owning operational document. Refresh `docs/agent/` after every tracked-file change with `python3 wolkaraforever/tools/generate_agent_docs.py`. Update the applicable standalone user guide for user-visible changes. Do not make user documentation depend on agent documentation.

Never edit `platform/` directly. Keep generated reports, logs, captures, credentials, device identifiers, and compatibility observations out of Git. Keep reviewed source fixtures and UI baselines tracked.

Never run a raw device-layer command: no `xcrun simctl`, no `xcrun devicectl`, no `simctl`, no `devicectl`, no `killall`, no `pkill` against simulator, WebKit, SpringBoard or CoreSimulator processes, and no shutting down, erasing, rebooting or force-restarting anything that was not started by the run. Simulator and device work goes through `wolkaraforever/tools/` only, and "read-only" is not an exemption. If a script hangs, report it and stop; do not repair it by hand.
