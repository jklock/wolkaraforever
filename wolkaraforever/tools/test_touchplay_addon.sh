#!/bin/bash
# The TouchPlay add-on (addons/TouchPlay, iPad touch's buttons), checked on the Mac: every Lua file
# compiles as the game's Lua 5.1 reads it, every file the .toc lists exists, and every
# tests/touchplay/test_*.lua passes. The tests are the add-on's own, written against its folder
# layout (addon/TouchPlay, tests/, tools/make-art.py), so they run in a scratch tree of links to
# addons/TouchPlay, wolkaraforever/tools/tests/touchplay and wolkaraforever/tools/touchplay.
#
# usage: wolkaraforever/tools/test_touchplay_addon.sh
#
# Needs LuaJIT (brew install luajit), which reads Lua 5.1 like the game.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
root=$PWD
addon=addons/TouchPlay
command -v luajit > /dev/null || { echo "test_touchplay_addon: needs luajit (brew install luajit)" >&2; exit 1; }

for file in "$addon"/*.lua; do
    luajit -bl "$file" > /dev/null || { echo "test_touchplay_addon: $file does not compile" >&2; exit 1; }
done
while read -r line; do
    line=${line%$'\r'}
    case "$line" in ''|'#'*) continue ;; esac
    [ -f "$addon/$line" ] || { echo "test_touchplay_addon: the .toc lists $line, which is missing" >&2; exit 1; }
done < "$addon/TouchPlay.toc"
echo "TouchPlay: $(ls "$addon"/*.lua | wc -l | tr -d ' ') Lua files compile, every .toc entry exists: PASS"

tree=$(mktemp -d "${TMPDIR:-/tmp}/touchplay-tests.XXXXXX")
trap 'rm -rf "$tree"' EXIT
mkdir -p "$tree/addon" "$tree/tests"
ln -s "$root/$addon" "$tree/addon/TouchPlay"
# The test files themselves are linked one by one into a real folder: a test that finds the add-on from
# its own folder ("tests/../addon") then resolves inside the scratch tree, not beside the link's target.
for file in "$root"/wolkaraforever/tools/tests/touchplay/*.lua; do ln -s "$file" "$tree/tests/"; done
ln -s "$root/wolkaraforever/tools/touchplay" "$tree/tools"
cd "$tree"
for file in tests/*.lua; do
    luajit -bl "$file" > /dev/null || { echo "test_touchplay_addon: $file does not compile" >&2; exit 1; }
done
count=0
for t in tests/test_*.lua; do
    luajit "$t" > "$tree/last.log" 2>&1 || { cat "$tree/last.log"; echo "test_touchplay_addon: $t FAILED" >&2; exit 1; }
    count=$((count + 1))
done
echo "TouchPlay: $count test files pass: PASS"
