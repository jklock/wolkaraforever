#!/bin/bash
# The Interface mobile add-on (addons/WolkaraRoue), checked on the Mac: every Lua file compiles
# as the game's Lua 5.1 would read it, every file the .toc lists exists, and the save module
# decides when to reload the interface as tests/test_mobile_addon_save.lua expects, and the
# turning wheel turns as tests/test_mobile_addon_turn.lua expects.
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

luajit wolkaraforever/tools/tests/test_mobile_addon_save.lua "$addon/Save.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_turn.lua "$addon/Turn.lua"
