# Documentation instructions

Before changing a tracked file, read `docs/agent/README.md`, the applicable catalog entry, and the owning operational document. Refresh `docs/agent/` after every tracked-file change with `python3 wolkaraforever/tools/generate_agent_docs.py`. Update the applicable standalone user guide for user-visible changes. Do not make user documentation depend on agent documentation.

Never edit `platform/` directly. Keep generated reports, logs, captures, credentials, device identifiers, and compatibility observations out of Git. Keep reviewed source fixtures and UI baselines tracked.
