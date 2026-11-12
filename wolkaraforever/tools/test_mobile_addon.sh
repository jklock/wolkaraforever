#!/bin/bash
# The Interface mobile add-on (addons/WolkaraRoue), checked on the Mac: every Lua file compiles
# as the game's Lua 5.1 would read it, every file the .toc lists exists, and the save module
# saves as tests/test_mobile_addon_save.lua expects; the turning wheels, their tabs and the wheel
# that lights up as it comes, the
# cooldown text, the touch and long press on a spell, the bag placement, the game's windows, the
# minimap, the chat, the moves of old saves and the settings panel, the game API values a client
# may not have, and the Duo fan and quick bar behave as
# tests/test_mobile_addon_turn.lua, test_mobile_addon_cooldown.lua, test_mobile_addon_press.lua,
# test_mobile_addon_bags.lua, test_mobile_addon_windows.lua, test_mobile_addon_minimap.lua,
# test_mobile_addon_chat.lua, test_mobile_addon_settings.lua, test_mobile_addon_api.lua and
# test_mobile_addon_duo.lua expect.
#
# usage: wolkaraforever/tools/test_mobile_addon.sh
#
# Needs LuaJIT (brew install luajit), which reads Lua 5.1 like the game.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
addon=addons/WolkaraRoue
command -v luajit > /dev/null || { echo "test_mobile_addon: needs luajit (brew install luajit)" >&2; exit 1; }

for file in "$addon"/*.lua; do
    luajit -bl "$file" > /dev/null || { echo "test_mobile_addon: $file does not compile" >&2; exit 1; }
done
while read -r line; do
    line=${line%$'\r'}
    case "$line" in ''|'#'*) continue ;; esac
    [ -f "$addon/$line" ] || { echo "test_mobile_addon: the .toc lists $line, which is missing" >&2; exit 1; }
done < "$addon/WolkaraRoue.toc"
echo "mobile add-on: $(ls "$addon"/*.lua | wc -l | tr -d ' ') Lua files compile, every .toc entry exists: PASS"

# A change is written when the user closes a panel: the game reloads the interface for an add-on
# only on a real touch, never from a timer (measured on the iPhone, 2026-11-09), so both panels
# have to go through the save module's secure button rather than merely hiding.
for panel in Settings.lua Controls.lua; do
    grep -q 'ns.SaveOver(' "$addon/$panel" || {
        echo "test_mobile_addon: $panel closes without going through ns.SaveOver" >&2; exit 1; }
done
echo "mobile add-on: both settings panels save on a real touch: PASS"

luajit wolkaraforever/tools/tests/test_mobile_addon_save.lua "$addon/Save.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_turn.lua "$addon/Turn.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_cooldown.lua "$addon/Actions.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_press.lua "$addon/Actions.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_bags.lua "$addon/Bags.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_windows.lua "$addon/Windows.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_minimap.lua "$addon/Minimap.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_chat.lua "$addon/Chat.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_settings.lua "$addon/Core.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_migration.lua "$addon/Core.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_api.lua "$addon/Core.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_duo.lua "$addon"

