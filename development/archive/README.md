# Archived development records

This directory preserves completed design records that are useful for lineage but
are not active implementation instructions. Current workflows and behavior live
in the sibling `architecture/`, `guides/`, `technical/`, and `testing/`
directories.

| Area | Contents |
| --- | --- |
| [plans/](plans/) | Completed implementation plans, retained with their original scope and evidence links. |
| [validation/](validation/) | Completed, dated validation evidence retained outside the live validation output directory. |

Validation records intentionally remain in
[`../validation/`](../validation/): `validate.sh` writes one immutable record
per revision there. Archive a record only after its result is superseded by
later work or no longer represents the current implementation.
