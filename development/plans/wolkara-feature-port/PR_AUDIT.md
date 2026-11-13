# Source pull-request audit

Source state was re-read from GitHub and fetched refs on 2026-11-10. PRs #10
and #13 do not exist. The fetched `main` is still
`ebc51c6140935765075a40747813592f4cdbe8c8`: 45 commits after `fc270359`, 12
merge commits and 33 implementation commits. GitHub's per-PR commit API was
also checked for every PR #1–#21. This audit covers every source PR and every
commit they expose; a source claim is not evidence for WolkaraForever.

| PR | State / commits | What it fixes or adds | Comparison and disposition |
| --- | --- | --- | --- |
| [#1](https://github.com/fJavierLasso/wolkara/pull/1) | merged; `5c017d0`, `05035cc` | Keyboard, trackpad, composed Unicode and accessory keys. | **Covered and surpassed.** Current product owns richer keyboard/trackpad/draft behavior. See `KEYBOARD_AND_DICTATION.md`. |
| [#2](https://github.com/fJavierLasso/wolkara/pull/2) | closed; `d718d01`, `a6d109d` | Optional performance HUD. | **Covered.** Keep the product `AKPerformanceOverlay`, its frame attribution and tests. |
| [#3](https://github.com/fJavierLasso/wolkara/pull/3) | closed; `887389e` | German language, manifest verification, stale CASC cleanup. | **Covered/gap review.** Forever owns locales and verified recovery. Compare only a reproducible bootstrap-manifest or stale-lock gap. |
| [#4](https://github.com/fJavierLasso/wolkara/pull/4) | closed; `d3a63c6` | Add-on-manager design document. | **No port.** Current product has an implemented, tested manager; retain only research references if independently verified. |
| [#5](https://github.com/fJavierLasso/wolkara/pull/5) | open; `91e878a`, `661d254`, `0fd0d4f`, `de30ef4`, `030efbb`, `53c753c` | A stacked, older bundle of HUD, add-ons, locale sync, backup and USB reenrollment. | **Superseded/provenance.** It combines unrelated work and duplicates current product features. Evaluate its stale-trust recovery only through `7cb348c`; do not merge. |
| [#6](https://github.com/fJavierLasso/wolkara/pull/6) | merged; `ecf7e93`, `a8a6082`, `c243f5b`, `01eade2`, `7cb348c`, `27f61a3`, `245c4e1`, `e4d2b64`, `fdc4e76`, `49e2ed9`, `6ad2858`, `ebc7345`, `0a91425`, `6027980`, `dbe9a35` | Capacity accounting; an add-on experiment and its removal; downloader; enrollment recovery; execution/UI/display maintenance. | **Split:** assess capacity and enrollment recovery; downloader is covered; reverted experiments are excluded; External JIT/progress are superseded; display/verification is a targeted gap review; fixture-only changes do not port alone. |
| [#7](https://github.com/fJavierLasso/wolkara/pull/7) | merged; `4a3a78f`, `d6a21c5` | Imports an older Forever snapshot plus bundle audit. | **No direct port.** The product is the upstream of this bulk import; use only for provenance. |
| [#8](https://github.com/fJavierLasso/wolkara/pull/8) | merged; `4b34d2a` | Files import folder/guide. | **UX assessment only.** It must not bypass safe game-data tooling. |
| [#9](https://github.com/fJavierLasso/wolkara/pull/9) | merged; `53e7ebd` | Source iPhone validation record. | **No port.** Different SHA, test matrix and evidence rules. |
| [#11](https://github.com/fJavierLasso/wolkara/pull/11) | merged; `4077d08` | Editable ability circles and modifier groups. | **Discovery candidate.** Redesign against Forever's input and Controller Manager contracts; do not import its game add-on. |
| [#12](https://github.com/fJavierLasso/wolkara/pull/12) | merged; `0a20a66` | Camera drag survives guest cursor recentering. | **Targeted candidate.** Reproduce with current direct-camera tests; port only the failing gesture state transition. |
| [#14](https://github.com/fJavierLasso/wolkara/pull/14) | merged; `ed3109e` | Modifier/ability delivery phase ordering. | **Part of #11 discovery.** No standalone merge. |
| [#15](https://github.com/fJavierLasso/wolkara/pull/15) | merged; `da87790` | Separate drag intent and independent ability-group editing. | **Part of #11/#12 discovery.** Preserve current direct-touch ownership. |
| [#16](https://github.com/fJavierLasso/wolkara/pull/16) | merged; `ecfc521` | Repeated drag repair; Simple controller with shoulders. | **Candidate package.** Compare Simple-mode ergonomics against the current gamepad and Controller Manager first. |
| [#17](https://github.com/fJavierLasso/wolkara/pull/17) | merged; `3c2231d` | Independent Simple-mode shoulder positions. | **Fold into #16.** Layout persistence has no value without the mode decision. |
| [#18](https://github.com/fJavierLasso/wolkara/pull/18) | merged; `04fbc09` | Lifecycle servicing while native startup sleeps. | **High-value candidate.** Reproduce rotation/fold during startup and port as a narrow runtime patch if confirmed. |
| [#19](https://github.com/fJavierLasso/wolkara/pull/19) | merged; `f06674b`, `bb8ad20`, `7f4241e`, `f47931f`, `0822463`, `dea2eb3`, `3aad8e8` | Shoulder defaults, dictation/language, stick buttons, composition/memory, add-on install/web downloads/TOCs. | **Split.** Keyboard/dictation and composition are P1; L3/R3 and shoulders are P2; serial install and large TOCs need invariant/fixture review. Use `dea2eb3`'s browser/download model as a no-key acquisition route, but make a native unified Add-on Hub the default UI and retain API-key/Files alternatives. |
| [#20](https://github.com/fJavierLasso/wolkara/pull/20) | closed; `cdff9b7`, `8dc7d43`, `71d6919`, `9f87823`, `651bd26`, `6af747f` | Retired mobile add-on, fixed its routing, fixed chat drafts, paused inactive Metal work. | **Split.** Retired/add-on code excluded; reviewed chat send and configurable destinations are opt-in feature candidates; inactive Metal pause is a separate candidate from current 5-fps background pacing. |
| [#21](https://github.com/fJavierLasso/wolkara/pull/21) | open; `640c586`, `84b19cb` | Experimental StikDebug IPA packaging. | **Exclude.** Forever already owns External JIT packaging/security policy; do not add another distribution path. |

## Commit-level decisions

The table below is intentionally granular: commits sharing an implementation
decision are grouped only where neither can safely be ported independently.

| Commit(s) | Decision | Why / evidence needed before any change |
| --- | --- | --- |
| `5c017d0`, `05035cc` | retain current | Keyboard/trackpad exists in richer product-owned form. |
| `d718d01`, `a6d109d`, `91e878a`, `661d254` | retain current | Performance HUD already product-owned. |
| `887389e`, `0fd0d4f`, `de30ef4` | targeted gap review | Locale/verification exist; test only a concrete missing behavior. |
| `d3a63c6` | no port | Proposal-only source documentation. |
| `030efbb` | retain current | Current UI archive/restore is more defensive and tested. |
| `53c753c`, `7cb348c` | assess | Reinstall trust recovery crosses authorization; add pairing-storage regression first. |
| `ecf7e93` | retain current | `TKWoWUpdater` already uses important-usage capacity with safe filesystem fallback; `test_wow_update.m` covers the source case. |
| `a8a6082`, `27f61a3` | exclude | Experimental game add-on was deliberately removed. |
| `c243f5b`, `ebc7345` | exclude | Feature was reverted by source. |
| `01eade2`, `6ad2858` | retain current | Current client suite covers bounded concurrent download/serial consumption. |
| `245c4e1`, `e4d2b64` | fold | Preference churn belongs with Simple-mode product decision. |
| `fdc4e76` | retain current | Current execution modes supersede the StikDebug coordinator. |
| `49e2ed9` | retain current | Product localized launch-progress view supersedes it. |
| `0a91425`, `6027980`, `dbe9a35` | targeted gap review | Display/CASC/fixture changes need a failing product test. |
| `4a3a78f`, `d6a21c5` | provenance | Reverse import from this product. |
| `4b34d2a` | assess UX | Must preserve guarded game-data workflows. |
| `53e7ebd`, `8dc7d43` | no port | Source evidence only. |
| `4077d08`, `ed3109e`, `da87790` | discovery | Ability zones require a new product design. |
| `0a20a66` | reproduce first | Current touch suite owns direct-camera behavior. |
| `ecfc521`, `3c2231d`, `f06674b` | candidate package | Simple mode/shoulder layout are inseparable. |
| `04fbc09` | candidate | Startup lifecycle responsiveness is independently useful. |
| `bb8ad20` | split candidate | Language/draft contract; camera regression; HUD already covered. |
| `7f4241e` | candidate | Define trigger collision and persistence first. |
| `f47931f` | split candidate | Composition reproduction separate from shader lifetime reproduction. |
| `0822463` | invariant review | Prove whether current add-on operations need serialization. |
| `dea2eb3` | transform | Use its normal CurseForge browser/download model for no-key acquisition. Do not copy its API-provider deletion; native unified Add-on Hub remains default and API-key/Files alternatives share one archive transaction. |
| `3aad8e8` | candidate | Add large-TOC fixture, then minimize parser change. |
| `cdff9b7`, `71d6919` | exclude | Mobile game add-on is not a safe product port. |
| `9f87823`, `651bd26` | opt-in candidate | Reuse reviewed-draft/send ordering, but make destinations user-configured and disabled by default. |
| `6af747f` | candidate | Reproduce inactive Metal issue; do not conflate with current frame cap. |
| `640c586`, `84b19cb` | exclude | New Experimental IPA route conflicts with current release policy. |
