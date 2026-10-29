# GitHub Wiki implementation plan

## Purpose and boundary

The GitHub Wiki should be a readable, task-oriented front door for users and contributors. It
summarizes maintained repository documentation; it must not become a second, drifting source of
truth. The repository's `docs/` folder remains canonical for users, and `development/` remains
canonical for engineering detail, plans, and validation evidence.

## Publishing model

- Keep the Wiki enabled and edit it through its Git-backed wiki repository.
- Create Wiki pages from this plan only after their linked canonical pages are current.
- Every Wiki page has a **Source of truth** link to a repository Markdown file and a **Last
  reviewed** date. Update the Wiki in the same PR/release cycle when that source changes.
- Never copy `local.env`, device identifiers, team IDs, signing identities, pairing records,
  game data, raw device logs, or private validation records into the Wiki.
- Use relative GitHub links where possible and public repository links for stable cross-references.

## Initial page tree

```text
Home
├── What WolkaraForever Is
├── Install on iPad
├── First Launch and Game Installation
├── Using the Launcher
│   ├── Game Region and Language
│   ├── App Language (when released)
│   ├── Add-ons and CurseForge
│   ├── Controls, Controllers, and Voice
│   └── UI Backup, Restore, and Performance
├── Troubleshooting and Diagnostics
├── Compatibility and Evidence
├── Safety and Security Boundaries
├── Contributing
│   ├── Repository Workflow
│   ├── Architecture and Layering
│   ├── Testing and Device Evidence
│   └── Localization and iPhone Work
├── Releases
└── Credits, Licenses, and Upstream
```

## Page specifications

Two pages of this tree are already written and only need publishing from the files named here:
[App language](APP_LANGUAGE.md) and [Game region and language](GAME_REGION_AND_LANGUAGE.md). Both
carry their canonical source and a review date, which is what the rollout checklist asks for.

| Wiki page | Content | Canonical repository sources |
| --- | --- | --- |
| Home | One-paragraph purpose, current support boundary, quick links, safety statement, and source-build expectation. | `README.md`, `docs/README.md` |
| What WolkaraForever Is | Tolkara/Wolkara/WolkaraForever lineage, what the product adds, and what it does not do. | `README.md`, `NOTICE.md`, `development/architecture/PROJECT_MAP.md` |
| Install on iPad | Prerequisites, safe setup, `local.env` concept without values, installation command, and first-launch expectations. | `docs/INSTALLATION.md` |
| First Launch and Game Installation | Edition, CDN region, game language, download/update behavior, selected-language update gate, and no game-data distribution. | `docs/USING_WOLKARAFOREVER.md`, `development/technical/WOW_LAUNCHER.md` |
| Game Region and Language | Distinguish region, game text/audio locale, app language, portal boundary, and the one-time offer to align the game language. | `docs/USING_WOLKARAFOREVER.md`, `development/guides/LOCALIZATION.md` |
| Add-ons and CurseForge | What import does, what the app manages, Core API key boundary, and safe recovery behavior. | `docs/USING_WOLKARAFOREVER.md`, `development/technical/FEATURES.md` |
| Controls, Controllers, and Voice | Touch, keyboard, controller, dictation permissions, and what needs human/device testing. | `docs/USING_WOLKARAFOREVER.md`, `development/testing/TESTING.md` |
| UI Backup, Restore, and Performance | Backup contents/exclusions, graphics reset boundary, gamepad switch, overlay, profiles, background behavior. | `docs/USING_WOLKARAFOREVER.md`, `development/technical/FEATURES.md` |
| Troubleshooting and Diagnostics | Symptom/action table, preflight, safe pilot scripts, logs, and what to include in an issue. | `docs/INSTALLATION.md`, `development/guides/TOOLING.md` |
| Compatibility and Evidence | Exact-SHA evidence categories, tested combinations, and why simulator/build success differs from device/gameplay proof. | `COMPATIBILITY.md`, `development/testing/TESTING.md` |
| Safety and Security Boundaries | Original executable/data boundary, no automation/anti-cheat bypasses, credential hygiene, supported execution modes. | `README.md`, `AGENTS.md`, `development/architecture/ARCHITECTURE.md` |
| Contributing | Branch/PR workflow, layer rule, review, code ownership, required checks, and issue labels. | `CONTRIBUTING.md`, `development/guides/REPOSITORY_WORKFLOW.md` |
| Architecture and Layering | Prepared-tree model, modules, patches/overlays, and upstream updates. | `development/architecture/PROJECT_MAP.md`, `development/architecture/ARCHITECTURE.md` |
| Testing and Device Evidence | Which scripts prove what, physical-device protocol, and report template. | `development/testing/TESTING.md` |
| Localization and iPhone Work | Contribution boundaries, app/game language separation, what is translated and what never is, translator instructions and review checklist, and links to the completed localization record plus the active launcher plan. | `development/guides/LOCALIZATION.md`, `development/archive/plans/GERMAN_APP_LOCALIZATION_PROMPT.md`, `development/uichanges/LAUNCHER_REORGANIZATION_PLAN.md` |
| Releases | Exact-SHA/tagging rule, experimental IPA scope, release-note template, and rollback policy. | `development/guides/REPOSITORY_WORKFLOW.md`, `.github/workflows/release.yml` |
| Credits, Licenses, and Upstream | Attribution, licences/notices, upstream relationships, and non-affiliation. | `README.md`, `LICENSE`, `NOTICE.md`, `platform/LICENSE`, `platform/NOTICE.md` |

## Authoring standards

1. Write for the page's reader before linking into engineering detail. Keep install/usage pages
   short, numbered, and executable; put design history in repository development docs.
2. Use screenshots only when they show the current shipped UI. Provide descriptive alt text and
   do not expose account names, device IDs, game files, or credentials.
3. State scope precisely: **source build**, **simulator test**, **installed app**, and
   **human-confirmed gameplay** are different evidence levels.
4. Prefer linking to a stable heading rather than reproducing a lengthy technical procedure.
5. Mark planned features as planned, including iPhone device profiles, until their exact release
   proof exists. The app language is implemented and is described as such; the German launcher
   claim still needs its recorded physical check on the released SHA.

## Rollout checklist

1. Create the Home page and its navigation tree first.
2. Publish Install, Launcher, Troubleshooting, Compatibility, and Safety pages from the current
   user docs; have a new user follow the links without repository knowledge.
3. Publish Contributor, Architecture, Testing, and Release pages from current development docs.
4. Add credits/licences and upstream attribution; verify every outbound link.
5. Have a contributor review the Wiki for missing setup information and a user review it for
   readability. Fix the canonical docs first when the Wiki exposes a gap.
6. Add a recurring release checklist item: compare the Wiki navigation/source links with the
   repository documentation and update changed pages in the same release PR.
