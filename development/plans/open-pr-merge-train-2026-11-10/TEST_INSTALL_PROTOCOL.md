# Stable/test iPad protocol

Stable is customer data. Every hardware run uses a separately signed `WolkaraForever Test` app with a distinct bundle ID, Keychain group, Documents container, logs, game data, enrollment, and External JIT identity.

The v1.0.2 wrapper reads ignored `local.test.env`, refuses stable/test identifier or Keychain-group equality, prints the test bundle, and runs read-only stable `pilot.sh state` before and after each operation. It may route only `preflight`, `install`, `pilot`, `device_log`, `push_game`, `device_matrix`, and `verify_external_jit` to the test identity.

Game data enters the test container only after explicit storage/source confirmation, through `push_game.sh`; never copy automatically or use raw device file operations. Device Hub targets only the test app. External JIT uses the test sideloaded bundle and a supported enabler; no debugger remains after guest entry.
