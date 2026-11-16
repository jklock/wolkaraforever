#!/usr/bin/env python3
"""Generate the tracked-file inventory used by docs/agent.

The catalog is deliberately mechanical: source must be read before behavior is
changed. Its job is to prove that every tracked path has one current record.
"""
from __future__ import annotations

import hashlib
import subprocess
from collections import defaultdict
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/agent/catalog"
SOURCE = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
TODAY = date.today().isoformat()

SHARDS = {
    ".github/": "github.md",
    "addons/": "addons.md",
    "docs/": "docs.md",
    "platform/": "platform.md",
    "profiles/": "profiles.md",
    "wolkaraforever/": "wolkaraforever.md",
}

# The build and run mechanisms each have one owner, and the catalogue's job is to say which one.
# Without this table every script in the directory carried the same sentence - including the two
# whose whole point is to refuse - so "read the applicable catalog entry" told an agent nothing
# about the tool it was about to change.
TOOLS = {
    "prepare.sh": ("Build assembly tool",
                   "Exports platform/ as committed, applies the patches and the overlay, then generates the project"),
    "apply.sh": ("Build assembly tool",
                 "Applies the patches then the overlay to a tree; the one implementation prepare.sh and adopt.sh share"),
    "overlay_map.sh": ("Build assembly generator",
                       "Regenerates overlay.map, the layer-to-platform path mapping the overlay follows"),
    "generate.sh": ("Build tool",
                    "Prepares the tree and runs the platform's own project generator with local.env"),
    "open_xcode.sh": ("Build tool",
                      "Generates the disposable Xcode project and opens it"),
    "install.sh": ("Build and install tool",
                   "Guards a live session, prepares, builds and signs, runs the mode's post-install step, verifies, then returns to the launcher"),
    "after_install.sh": ("Build tool",
                         "Does the post-install step each execution mode requires, and none for a mode that needs none"),
    "run.sh": ("Run tool",
               "Prepares the tree then runs the platform's own run script in the simulator or on the device"),
    "launch.sh": ("Run tool",
                  "Launches only when no session is live, and records the client error baseline first"),
    "pilot.sh": ("Run tool",
                 "Device state, stop, install, launch, wait, view, crash, log and self-test - refusing when the device is not ready"),
    "package_ipa.sh": ("Packaging tool",
                       "Builds the unsigned generic TolkaraDiagnostics .ipa through the platform's own packaging script"),
    "package_altstore_ipa.sh": ("Packaging tool",
                                "Refuses a dirty tree, builds the unsigned External JIT .ipa and verifies it"),
    "verify_ipa.sh": ("Packaging verification tool",
                      "Proves an .ipa is unsigned, External-JIT, extension-free and free of this Mac's trust roots"),
    "verify_external_jit.sh": ("Device verification tool",
                               "Verifies an installed build and requires its External-JIT runtime evidence"),
    "test_install.sh": ("Test harness",
                        "Drives install.sh end to end with stubbed device tools and an isolated configuration"),
}


def shard(path: str) -> str:
    for prefix, name in SHARDS.items():
        if path.startswith(prefix):
            return name
    return "root.md"


def kind(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if path.startswith("platform/"):
        return "immutable vendor file"
    if "/tests/" in path or path.startswith("tests/"):
        return "test" if suffix not in {".png", ".jpg", ".jpeg"} else "reviewed fixture"
    if "ui-baselines" in path:
        return "reviewed fixture"
    if path.endswith((".sh", ".py")):
        return "script"
    if suffix in {".m", ".mm", ".c", ".h", ".swift", ".lua"}:
        return "source"
    if suffix in {".md"}:
        return "documentation"
    if suffix in {".png", ".jpg", ".jpeg", ".xcassets"}:
        return "asset"
    if suffix in {".plist", ".json", ".yml", ".yaml", ".xcconfig", ".map", ".toc"}:
        return "configuration"
    return "repository file"


def describe(path: str, file_kind: str) -> tuple[str, str, str, str]:
    parent = str(Path(path).parent)
    deps = "Sibling files in its subsystem"
    human = "None"
    if path.startswith("docs/") and not path.startswith("docs/agent/"):
        return ("Standalone human documentation or public asset", "Explains a supported user task or illustrates it", "User-guide links and screenshots", "This document")
    if path.startswith("wolkaraforever/tools/"):
        entry = TOOLS.get(Path(path).name)
        if entry:
            return (entry[0], entry[1], "platform/ export, wolkaraforever/patches, wolkaraforever/overlay.map, local.env",
                    "docs/BUILDING.md when a command, execution mode, or safety guard changes")
        human = "docs/INSTALLATION.md or docs/USING_WOLKARAFOREVER.md when user-run behavior changes"
        return ("Project operation or verification tool", "Prepares, validates, operates, packages, or tests the product", "Source tree, prepared platform, or named suite", human)
    if path.startswith("wolkaraforever/WoW/"):
        human = "docs/USING_WOLKARAFOREVER.md when user behavior changes"
        return ("Forever lifecycle or launcher component", "Implements game data lifecycle, launcher UI, add-ons, or its tests", "Shell, Touch, product tools, and focused tests", human)
    if path.startswith("wolkaraforever/"):
        human = "docs/USING_WOLKARAFOREVER.md when user behavior changes"
        return ("WolkaraForever product-layer component", "Implements product behavior or an overlay/patch boundary", "Prepared platform and owning tests", human)
    if path.startswith("addons/"):
        return ("Bundled add-on component", "Implements or packages the optional in-game add-on", "Add-on packaging and launcher verification", "docs/USING_WOLKARAFOREVER.md when user behavior changes")
    if path.startswith("platform/"):
        return ("Tolkara vendor-tree component", "Provides upstream runtime, translation, authorization, launcher, profile, test, or tool behavior", "Immutable upstream subsystem", "None; update product docs only if an approved overlay changes behavior")
    if path.startswith("profiles/"):
        return ("Product profile data", "Declares supported application metadata", "Launcher/profile loader", "docs/USING_WOLKARAFOREVER.md when behavior changes")
    if path.startswith(".github/"):
        return ("Repository automation or governance configuration", "Controls review, ownership, or release workflow", "GitHub and repository policy", "None")
    return ("Repository-level file", f"{file_kind.capitalize()} supporting repository operation or policy", parent, human)


def esc(value: str) -> str:
    return value.replace("|", "\\|")


def main() -> None:
    files = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
    grouped: dict[str, list[str]] = defaultdict(list)
    for path in files:
        # Catalog markdown documents are self-describing generated outputs. Their
        # existence is recorded in FILE_CATALOG.md rather than recursively hashed.
        if path.startswith("docs/agent/catalog/"):
            continue
        grouped[shard(path)].append(path)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, paths in grouped.items():
        lines = [
            f"# {name.removesuffix('.md').replace('-', ' ').title()} catalog",
            "",
            f"> Verified: {TODAY} · Source: `{SOURCE}` · Proof: SHA-256 of each tracked file",
            "",
            "| Path | Folder | Type | Purpose | Contents/function | Dependencies | Human-doc impact | Proof |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for path in sorted(paths):
            payload = (ROOT / path).read_bytes()
            digest = hashlib.sha256(payload).hexdigest()
            file_kind = kind(path)
            purpose, function, dependencies, human = describe(path, file_kind)
            lines.append("| {} | {} | {} | {} | {} | {} | {} | `sha256:{}`; `{}`; {} |".format(
                esc(path), esc(str(Path(path).parent)), esc(file_kind), esc(purpose),
                esc(function), esc(dependencies), esc(human), digest, SOURCE, TODAY,
            ))
        (OUT / name).write_text("\n".join(lines) + "\n", encoding="utf-8")
    # A migration record deliberately stays short: removed historical material is
    # available in Git history and is no longer current operational guidance.
    (OUT / "development.md").write_text(
        "# Development migration record\n\n"
        f"> Verified: {TODAY} · Source: `{SOURCE}` · Proof: repository index\n\n"
        "The former `development/` documentation, completed plans, reviews, and validation records "
        "were removed from the tracked documentation set. Their current operational replacements are "
        "the documents in `docs/agent/`; completed records remain recoverable from Git history but are "
        "not current instructions.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
