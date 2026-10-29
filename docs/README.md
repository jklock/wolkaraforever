# Documentation

Start with the [README](../README.md). Then pick the page that matches the job.

Everything here describes the fork — the WoW launcher, the input layer, the layer split.
The vendored engine keeps its own docs, unchanged, under `platform/docs/`.

## Using the app

| Page | Covers |
| --- | --- |
| [FROM_ZERO.md](FROM_ZERO.md) | Bare Mac to playing, checkpointed, with troubleshooting. |
| [GETTING_STARTED.md](GETTING_STARTED.md) | The short build-and-install route. |
| [USING_WOLKARAFOREVER.md](USING_WOLKARAFOREVER.md) | The app itself: home, add-ons, Performance & UI, voice, settings. |
| [FEATURES.md](FEATURES.md) | What the product does, its safety boundary, and how each part is proved. |
| [WOW_LAUNCHER.md](WOW_LAUNCHER.md) | Editions, download, verification, resume, updates. |
| [FRESH_INSTALL_TEST.md](FRESH_INSTALL_TEST.md) | Clean-device checklist for a first full download. |
| [DEVICE_WORKFLOW.md](DEVICE_WORKFLOW.md) | Prerequisites, device variables, copying the game from a Mac. |
| [COMPATIBILITY.md](../COMPATIBILITY.md) | Dated device results. |

### Input

| Page | Covers |
| --- | --- |
| [TOUCH_INPUT.md](TOUCH_INPUT.md) | Toolbar, keyboard, trackpad, draft, dictation. |
| [TOUCH_CONTROLLER_PROPOSAL.md](TOUCH_CONTROLLER_PROPOSAL.md) | The on-screen controller: layout, customisation, HUD. |
| [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) | Physical controllers and the inspector. |
| [CONTROLLER_PROFILES.md](CONTROLLER_PROFILES.md) | Per-controller profiles. |
| [INPUT_TRIGGERS.md](INPUT_TRIGGERS.md) | Trigger modes, key mapping, ownership. |
| [VOICE.md](VOICE.md) | Dictation modes, auto-submit, what was verified. |

## Developing

| Page | Covers |
| --- | --- |
| [TESTING.md](TESTING.md) | Which command proves what, and what still needs a device or a person. |
| [TOOLING.md](TOOLING.md) | Every script, its arguments, side effects and preconditions. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Loader, translation layer, execution modes. |
| [MAINTAINING.md](MAINTAINING.md) | The layers; updating Tolkara, the app and the game; the two upstreams. |
| [BUILDING.md](BUILDING.md) | Advanced engine builds and execution modes. |
| [PERFORMANCE_LANES.md](PERFORMANCE_LANES.md) | Where the layer could cost performance, measured or marked unmeasured. |
| [PERFORMANCE_THERMAL.md](PERFORMANCE_THERMAL.md) | Frame pacing and thermal behaviour under load. |
| [GPU_SUPPORT.md](GPU_SUPPORT.md) | BC textures and the Metal path. |
| [LOCAL_AUTHORIZATION.md](LOCAL_AUTHORIZATION.md) | The developer-service protocol. |
| [ADDON_MANAGER_PLAN.md](ADDON_MANAGER_PLAN.md) | How the add-on manager works. |
| [WOLKARAFOREVER_DISTRIBUTION.md](WOLKARAFOREVER_DISTRIBUTION.md) | Distribution channels, and what is unverified. |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Ground rules and workflow. |
| [../SECURITY.md](../SECURITY.md) | Reporting a vulnerability. |
| [../NOTICE.md](../NOTICE.md) | Licences and third-party notices. |

## Historical records

Past states, kept as evidence. Each begins with a banner naming what it was true of.

| Page | Records |
| --- | --- |
| [LAYER_BASELINE.md](LAYER_BASELINE.md) | Measurements taken before the layer split. |
| [LAYER_DELTAS.md](LAYER_DELTAS.md) | The delta set of the layer split. |
| [../development/validation/](../development/validation/) | Per-commit validation records. |

## The layer split

The engine is vendored at `platform/`, byte-identical to `upstream/main`, never edited by
hand. Everything the fork adds lives in `wolkaraforever/` and reaches the build two ways: a
**patch** against a platform file, or an **overlay** of one of our files
(`wolkaraforever/overlay.map`). `prepare.sh` exports `platform/` to `build/platform/`,
applies patches, then the overlay. `check_layers.sh` is the gate that keeps the split
honest. The short version is [`wolkaraforever/README.md`](../wolkaraforever/README.md).
