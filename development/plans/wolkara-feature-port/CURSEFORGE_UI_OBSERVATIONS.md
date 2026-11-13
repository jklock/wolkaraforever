# CurseForge desktop UI observations — 2026-11-11

Observed directly in the installed CurseForge desktop app with the Forever game
selection. This is interaction reference, not source code to copy.

## My Add-ons

- It is the initial tab. Its toolbar has Update all with a count, Sync, Create
  Group, text filter, view/filter controls and Refresh.
- Rows show icon, add-on name, installed archive filename, an Update action,
  latest archive/version, game version and author. The installed list includes
  a mix of source packages but presents one unified catalog.
- Row actions are stateful: each row exposes an Update button only when an update
  is available. The table supports sorting by Name, Action, Latest Version,
  Game Version and Author.

## Discover and Browse

- Discover is a native landing view with promoted cards plus Latest Addons and
  Popular Addons sections, each with Install actions.
- Browse is native. It has query, sort, filters, list/grid controls and result
  rows containing icon, name, compatible archive, Install, downloads/rank,
  latest date, category, game version and author.
- Filters include Hide installed content, game version and category/subcategory
  selection. The observed Forever browse result reports 10,000 projects.

## Product implication

WolkaraForever should copy the interaction model—one native installed catalog
and native catalog views where supported—not the desktop app's branding, ads,
subscription UI, or its undocumented data transport. Browser download is a
fallback acquisition path; it must not replace the native My Add-ons screen.
