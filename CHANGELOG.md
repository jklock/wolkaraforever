# Changelog

> **Documentation index current as of 2026-10-30 · branch `main`.**

This page names no source revision on purpose: it describes whatever commit you are
reading, and a pinned hash here would be stale by the next commit. Physical results are
kept as dated records under [development/validation/](development/validation/), where
they name the revision that actually ran.

This changelog records release history. It is not a compatibility guarantee: read the current
[installation guide](docs/INSTALLATION.md), [user guide](docs/USING_WOLKARAFOREVER.md), and
[compatibility boundary](COMPATIBILITY.md) for the current project state.

## Unreleased

- A launch through the iPad Developer service that cannot be prepared now says **which
  step refused**, in the app's language, instead of reporting a dead helper: not enrolled,
  pairing identity did not verify, no usable debugger service, local service unreachable,
  or memory preparation finished without a confirmed detach. A launch on an iPad that holds
  no enrolment is stopped before the route is even started, rather than after a timeout.
  Nothing gains a fallback and no check is weakened — every path still refuses and the game
  is not started.
- Added a separate **App language** setting for everything WolkaraForever draws: English, German,
  or the iPad's preferred language. It takes effect without a relaunch and covers rows, alerts,
  menus, status and progress lines, accessibility strings, the performance overlay and the touch
  keyboard. Game language and app language stay independent, and the first German selection
  offers once — never silently — to put the game into German through the existing validated
  writer and update gate. The German launcher was checked on an iPad (iPadOS 27.0.1) at `56ddc87`;
  see [the record](development/archive/validation/56ddc87-german-app-localization.md) and
  [the localization guide](development/guides/LOCALIZATION.md).
- Rebuilt the public documentation around the current source tree.
- Moved development-only layer, profile, contribution, and adapter material under
  `development/`; `docs/` now contains user-facing material only.
- Documented the current Forever launcher feature set, including background-aware frame
  pacing, current locale behavior, add-on management, voice controls, and UI recovery.

## Historical releases

Earlier release claims and dated validation evidence are retained in Git history and in
[`development/validation/`](development/validation/). They apply only to the revisions,
devices, and game builds they name.
