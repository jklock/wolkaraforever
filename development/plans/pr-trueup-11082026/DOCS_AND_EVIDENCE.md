# Documentation and evidence rules

## Documentation ownership

`UI_POLICY.md` defines what contributors may change. `LAUNCHER_UI_BASELINE.md` defines named
fixture images and recording authority. `DEVICE_CONTRACT.md` remains the measured geometry
contract. `FEATURES.md` maps capability to owner/test. `USING_WOLKARAFOREVER.md` explains user
behaviour, including recovery. `LOCALIZATION.md` and localization tests require every visible
string in all supported tables. Update the user-facing guide whenever setup, settings, defaults,
or recovery instructions change; run `check_docs.sh` for every documentation release.

## Evidence record content

Every PR/release body records:

1. Original PR number, branch, integrated head SHA, and direct parent/main SHA.
2. Plain-English code change, user-visible effect, default, toggle/selection route, and any user
   action needed before/after merge.
3. UI classification and exact existing elements/baselines preserved.
4. Commands, exit results, named matrix simulators, physical iPad model/iPadOS/execution mode,
   Device Hub observation, and final device state.
5. Exact post-squash main SHA, validation-record path, tag, and known risks/not-run boundaries.

Generated validation records are evidence, not hand-written status. Do not edit them. Do not
commit device IDs, signing information, game data, captures outside approved fixture baselines,
or credentials.

## Baseline inventory rule

The launcher test has a closed expected-state list. A feature adds a state by changing that list,
adding the file on both matrix devices, documenting it in the review record, and preserving every
old image. Deleting/overwriting an old image is a UI-contract amendment, never an additive PR.
