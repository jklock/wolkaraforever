# Application profiles

> Verified: 2026-11-21 · Source: `8375cbb`

A profile is data: it tells the launcher what a tested application is called and where its files
live inside the Tolkara app's `Documents` folder. It contains no code and no settings for the
application itself. The format, including the optional `caseAliases`, `runtime` and `setup` keys, and
the rules `platform/tools/check_profile.py` enforces, are documented in
[platform/profiles/README.md](../platform/profiles/README.md).

| Entry | What it is |
| --- | --- |
| `wow-forever/profile.json` | The Forever profile this layer tests against. |
| `wow-forever/sync_addons.sh` | A helper that merges a Mac add-on folder into the selected game container without deleting anything on the device. It reads `DEVICE` and `TOLKARA_BUNDLE_ID` from the repository root's `local.env` through the engine's own `platform/tools/localenv.sh`, refuses to copy while WolkaraForever is running, and needs the device reachable. The launcher's **Add-On Manager** and `wolkaraforever/tools/push_game.sh` are the other supported routes. |

Profiles in this folder are source data for the Mac Management app and for `TOLKARA_PROFILE` builds.
The engine's own copy of the format lives at `platform/profiles/`, vendored unchanged.
