# Historical records kept for provenance

> Restored 2026-11-05 from reachable Git history. Nothing here is current
> product documentation: each file is the last committed version before its
> deletion, kept byte-identical so a later claim can be traced to the record
> it actually rested on.

## Why this directory exists

A live-playtest review found that iPad and iPhone evidence, device contracts and
engineering records had been removed from the working tree by several
unrelated clean-ups. The removals were legitimate at the time — they were
superseded documents, scaffolding, or records tied to SHAs that had been
replaced — but the *evidence* they carried was still the only record of what
had actually been measured on hardware, and deleting it quietly turned a
measured claim into an unsupported one.

The current records live at their active paths (`development/`,
`docs/`, `COMPATIBILITY.md`). This directory holds what those paths no longer
carry, so `development/architecture/RESTORATION_MATRIX.md` can point at both
halves of the story.

## Restored paths and where they came from

| Restored path | Original path | Deleting commit |
| --- | --- | --- |
| `development/*.md` | `development/*.md` | `478244a` "Deleted old dev docs" |
| `validation/*.md` | `development/validation/*.md` | `478244a` |
| `docs/IPHONE.md` | `docs/IPHONE.md` | `f149066` |
| `docs/TOUCH_ADDON.md` | `docs/TOUCH_ADDON.md` | `27f61a3` |
| `docs/GETTING_STARTED.md` | `docs/GETTING_STARTED.md` | `982a0f0` |
| `docs/WINDOWS.md` | `docs/WINDOWS.md` | `813c1ec` |
| `docs/ADAPTERS/*` | `docs/ADAPTERS/*` | `4934e20` |
| `addons/WolkaraTouch/*` | `addons/WolkaraTouch/*` | `27f61a3` |
| `launcher/WoW/TouchAddon.{h,m}` | `launcher/WoW/TouchAddon.{h,m}` | `27f61a3` |

`launcher/`, `authorization/`, `runtime/` and the other top-level source
directories moved into the vendored `platform/` tree; those paths appear in
`git log --diff-filter=D` as deletions but are relocations, and are **not**
restored here. See the matrix for the reason each non-relocation deletion was
classified the way it was.

## Rules for this directory

- Do not edit a file here. It is evidence, and the commit and path in the table
  above are what make it checkable.
- If a behaviour recorded here becomes current again, restore it at its *active*
  path through the reconciliation described in the matrix — do not point
  documentation at this directory.
- `wolkaraforever/tools/check_docs.sh` does not treat this directory as product
  documentation; links out of it are checked, links into it are not.
