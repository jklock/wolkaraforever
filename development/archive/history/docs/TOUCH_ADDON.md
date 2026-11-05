# Wolkara Touch experiment

`addons/WolkaraTouch` is an original, MIT-licensed WoW addon for the touch
adventure mode. Its first target is Forever beta, interface **16001**. It uses
WoW's normal addon interface; no game executable changes, input replay, account
information, or external game-state inspection are involved.

## Controls

- Eight ability buttons appear at the right in two columns of four. They show
  the current action icons and cooldown sweeps.
- Round **M1–M4** buttons select another set of eight actions. The page stays
  selected after releasing your finger. Tap the selected modifier again to
  return to **BASE**. Each selection only changes the displayed page.
- **Spells, Character, Talents, Bags, Map, Menu** shortcuts sit along the bottom.
  Use Wolkara's controller/trackpad mode to operate the windows they open.

The app reserves the rightmost **33%** and bottom **16%** for direct UI touches
in adventure mode. This addon keeps all its buttons within those regions at
iPhone and iPad landscape aspect ratios. The transparent spaces do not capture
the game's mouse input. Changing display/UI scale during combat defers button
layout until combat ends.

## Put abilities on the bars

Outside combat, select the desired page, switch Wolkara to controller/trackpad
mode and open **Spells**. Drag an ability from the spellbook onto a slot with
the trackpad's hold-and-drag gesture. M1–M4 are latched selectors: selecting M2
before dragging keeps M2 active throughout the drag. Selecting a different
page while an ability is already on the cursor also preserves that ability.
You do not need to hold a second finger down as a keyboard modifier.

Actions use the character's existing WoW action slots:

| Wolkara page | WoW action slots | Existing normal bar |
| --- | --- | --- |
| BASE | 1–8 | First main-bar page |
| M1 | 61–68 | Bottom left |
| M2 | 49–56 | Bottom right |
| M3 | 25–32 | Right |
| M4 | 37–44 | Left |

Installing or selecting a page never fills, clears or rearranges those slots.
If you already use these bars, their abilities appear here. Manually moving an
ability changes the corresponding normal bar too; WoW saves those slots for the
character. Uninstalling the addon does not erase them. The selected page starts
at BASE after login/reload. Normal Blizzard bars remain available.

## Implementation and limits

Ability buttons retain Blizzard's `SecureActionButtonTemplate` click handler.
M1–M4 use `SecureHandlerClickTemplate` to select preconfigured action slots from
a real click, including in combat. Ordinary addon event callbacks only refresh
visuals. Dragging/rearranging actions is deliberately rejected in combat.
The addon does not set bindings, populate macros, poll targets, auto-cast,
repeat inputs, or decide which action the player should take.

The source was written for this project, with API behavior checked against
Blizzard's UI source as published in the
[SecureActionButton definitions](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua),
[secure handler definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureHandlerTemplates.xml),
and [action-button drag handling](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua).
No source or artwork was copied from another addon. `Circle.tga` is an original
64×64 antialiased white circle; the game supplies the fonts and ability icons at
runtime.

The API wrapper supports both `C_ActionBar` and older global action functions;
spellbook/talent shortcuts handle the modern and Classic entry points. The TOC
declares only the verified target interface number, 16001. Retail and other
Classic editions remain experiments, not tested compatibility claims. They
may require **Load out of date AddOns** or a matching TOC interface number.
Do not enable that setting globally on the user's behalf.

Vehicle/possess bars, stance-dependent main-bar paging, spell flyouts, binding
labels, charge counts, range coloring, other UI addons and Retail combat-secret
API changes need real-client validation. This initial addon exposes fixed normal
slots and leaves Blizzard's other bars alone. WoW's addon security checks remain
in force; using secure templates is not a guarantee about Blizzard account policy.

## Installation and verification

Install the **WolkaraTouch folder** in the selected game edition's
`Interface/AddOns` directory. Its runtime payload is `WolkaraTouch.toc`,
`WolkaraTouch.lua`, `Circle.tga`, and `LICENSE`. No files belong inside the game's
`.app` executable bundle. Preserve other addons and all `WTF` settings. Restart
the client so it discovers a newly installed addon.

The branch's launcher integration installs its bundled original payload before
launch. It must preserve user-modified copies and reject symlink destinations;
the addon itself never installs or updates files.

Run the synthetic checks with:

```sh
python3 -m unittest discover -s tests -p test_wolkara_touch_addon.py -v
```

These checks execute the original Lua with fake UI objects and modern/legacy
action APIs. They cover all page mappings, returning to BASE, preserving a
spell on the cursor when changing pages, dropping onto the selected slot,
combat drag rejection, delayed layout, login during combat, and iPhone/iPad
region bounds. A Lua interpreter is required; without one the behavior test is
reported as skipped. This is not a simulation of Blizzard's taint/security
engine and does not prove combat or device behavior.

Before calling this playable, test manually in Forever: load a character; tap
all pages; put a spell onto a non-base page; drag it to another page; verify one
cast per tap; verify page selection and casting in combat; check normal bars
still agree; open the spellbook, talents and menu in trackpad mode; verify camera
drags cannot activate an ability. Repeat after logout/login. No account or
gameplay automation is part of these tests.
