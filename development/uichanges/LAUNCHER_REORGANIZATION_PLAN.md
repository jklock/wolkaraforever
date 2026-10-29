# Launcher reorganization and device-profile plan

## Intent

Reorganize the WolkaraForever home screen so game identity, language, performance choices, and
game-file recovery are discoverable without mixing their responsibilities. This is a product/UI
plan; it does not authorize automatic graphics changes, game-data mutation, or unsupported
device claims.

## Proposed home layout

### 1. Game Edition

Keep this as the first card. Its rows become:

1. **Game edition:** `World of Warcraft — Forever` (and the selected alternative edition when
   available). This is a label/selector change, not a new compatibility promise.
2. **Game language:** `United States · English` (or the selected CDN region and game language).
   It opens the existing independent region/language preference flow. It controls CDN selection,
   `textLocale`, and `audioLocale`; it never changes the login portal.
3. **App language:** `English`, `German`, or `System Default`. It controls WolkaraForever's
   interface only. **Implemented** as `wow.language` — its own identifier, as this plan asks —
   with the German alignment confirmation described in
   [the localization guide](../guides/LOCALIZATION.md); the review of that work is in
   [the record](../archive/validation/56ddc87-german-app-localization.md).

The card must state English names clearly enough that a user knows whether a choice changes the
app, the game content, or the CDN region. Preserve accessibility identifiers with new stable
names; do not overload the existing `wow.preferences` identifier for a different semantic row.

### 2. Add-on Manager

Keep the existing add-on install, Mac-Ever, and directory actions together. No behavior change.

### 3. Voice & Input Manager

Keep permissions, key/button configuration, and Test Voice together. The app-language selector
is not a voice-recognition-language setting; speech language needs its own future product decision.

### 4. Performance Manager (new card)

Place directly below Voice & Input Manager. It owns:

- **Device profile:** selected iPad/iPhone hardware target and the resulting safe render profile.
- **Render profile:** Performance, Balanced, Quality, or a device-specific safe default.
- **Restore performance defaults:** restores the recommended profile for the selected device;
  it must not reset WoW account/UI configuration.
- **Performance Overlay:** the existing switch, moved from the UI card with no behavior change.

The selected profile is an app render/backing-scale preference. It does not claim to alter WoW
CVars, change game content, or guarantee a frame rate. Any in-game measurement remains evidence,
not a preset promise.

### 5. Performance & UI Manager (retained, narrower scope)

Keep the existing safe game-file tools here, in this order:

1. Backup WoW UI Configuration
2. Restore WoW UI Configuration
3. Reset to Default Graphical Settings
4. Open Settings Folder
5. Gamepad UI

Do not include Performance Overlay or Render Profile in this card after the move. Preserve the
current availability guard: it is enabled only for a ready Forever installation, when no update,
start, session, or conflicting UI file operation is active. Backup/restore/reset remain bounded
to their current documented file/CVar allowlists.

## Device-profile system

### Product requirements

- Auto-detect the current device model first. A manual selector may provide preview/override
  profiles for testing, but must label an override clearly and offer **Use this device** to return
  to automatic detection.
- Never permit a profile to claim hardware unavailable on the running device. The default must be
  a conservative, tested profile for the actual device.
- Store profile definitions as versioned, data-only records, not scattered `if` statements in UI
  code. Each record has: stable identifier, display name, family, chip generation, native logical
  size, safe backing-scale/render target, quality cap, notes, and validation state.
- Do not infer performance solely from screen resolution. Thermal state, Low Power Mode, memory
  pressure, game build, and scene complexity remain runtime variables.

### Coverage matrix to create

Create records for every supported M-series iPad family/generation and all requested modern iPhones:

| Family | Required records | Initial policy |
| --- | --- | --- |
| iPad Pro | M1, M2, M4, M5; each available screen-size/model identifier | Safe auto profile per exact hardware; benchmark before Quality is offered as default. |
| iPad Air | M1, M2, M3, M4, M5; each available screen-size/model identifier | Conservative Balanced/Performance defaults until measured. |
| iPad mini | Every M-series model if/when released | Add only when an actual model identifier exists; do not invent future hardware. |
| iPhone | iPhone 17 family, iPhone 18 family, and iPhone Duo permutations | One exact record per shipping model identifier and display class. Do not treat a marketing family as one GPU/display target. |

The request names future/device-family labels that may not yet have stable public model identifiers.
Maintain the matrix as **planned** until the hardware and identifiers are confirmed. No production
selector should expose a speculative device as an actual detected target.

### Profile selection UX

1. Display `This iPad: <model>` and its auto-selected profile.
2. Offer `Automatic (recommended)` plus supported profile choices. Hide unsupported quality levels
   rather than letting users choose combinations known to be unstable.
3. If a user changes device/profile, show the render target and explain that it applies on next
   game start. Require confirmation only when increasing rendering load above the recommendation.
4. **Restore performance defaults** restores `Automatic (recommended)` for the actual device and
   removes only WolkaraForever-owned profile overrides.
5. Record the selected profile, actual device identifier, and effective backing scale in redacted
   diagnostics. Never log device UDID, Apple team, or account data.

## Implementation sequence

1. Inventory existing home-card identifiers, layout constraints, `WolkaraForeverBackingScale`,
   render-profile choices, overlay persistence, and Forever UI guards.
2. Define a `DeviceProfile` data schema and a resolver using `UIDevice`/supported model mapping.
   Add an explicit unknown-device fallback with a safe lower-scale profile.
3. Add tests for model mapping, unknown fallback, persisted override/migration, profile reset,
   and no mutation of game UI settings from performance actions.
4. Refactor the home screen into the five cards above without changing the action behavior.
   Preserve/rename accessibility identifiers deliberately and update UIKit fixture hierarchy tests.
5. Implement localized labels together with the app-language work; do not bake English-only layout
   measurements into the redesign.
6. Validate on simulator sizes and physical iPad models. For iPhone support, validate portrait,
   landscape, Dynamic Type, safe areas, compact widths, and performance-profile defaults on actual
   devices or explicitly labelled simulations.
7. Update user docs, technical feature inventory, screenshots, accessibility notes, and Wiki.

## Acceptance checks

- The home page fits supported iPad and iPhone layouts without clipping, hidden primary actions,
  or a horizontal scroll requirement.
- Render/profile actions never alter WoW `Config.wtf`; UI-recovery actions never alter the
  render profile except where separately documented.
- A ready Forever installation preserves the current backup/reset/restore/gamepad safeguards.
- Tests cover every supported profile record and unknown fallback. Device performance claims are
  tied to an exact installed SHA, hardware model, iOS version, game build, and observed metrics.
