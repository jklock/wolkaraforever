#!/bin/bash
# Every Tolkara action the profile can store is one the page can offer, and both languages can name.
#
# Why this exists: the action list lives in the profile store (`AKControllerAction*`), the chooser
# that offers it lives in the page (`controller.action.*` string keys), and the words live in the
# string tables. Three places, two binaries, and a drift between any pair is silent: an action the
# store accepts and the page never offers is dead weight, an action the page offers and the store
# rejects does nothing when chosen, and a missing string prints a raw key at a person.
#
# It is deliberately source-level, like check_controller_targets.sh: a build cannot catch this.
set -eu
cd "$(dirname "$0")/../.." || exit 2

store=wolkaraforever/Controller/ControllerProfile.h
page=wolkaraforever/WoW/ControllerManagerViewController.m
table_en=wolkaraforever/Shell/en.lproj/Localizable.strings
table_de=wolkaraforever/Shell/de.lproj/Localizable.strings

for file in "$store" "$page" "$table_en" "$table_de"; do
    [ -f "$file" ] || { echo "check_controller_actions: missing $file" >&2; exit 2; }
done

# Declared actions: `extern NSString *const AKControllerAction<Name>;`
declared=$(grep -oE 'extern NSString \*const AKControllerAction[A-Za-z]+;' "$store" |
           sed -E 's/.*AKControllerAction([A-Za-z]+);/\1/' | tr 'A-Z' 'a-z' | sort -u)
# Offered actions: the `controller.action.<name>` keys the page actually asks for.
offered=$(grep -oE '@"controller\.action\.[a-z]+"' "$page" |
          sed -E 's/@"controller\.action\.([a-z]+)"/\1/' | sort -u)

if [ -z "$declared" ]; then
    echo "check_controller_actions: no actions found in $store - this check would pass on an empty list" >&2
    exit 2
fi

missing_from_page=$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$offered"))
missing_from_store=$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$offered"))

if [ -n "$missing_from_page" ]; then
    echo "check_controller_actions: FAIL - the store accepts actions the page never offers:" >&2
    printf '  %s\n' $missing_from_page >&2
    exit 1
fi
if [ -n "$missing_from_store" ]; then
    echo "check_controller_actions: FAIL - the page offers actions the store would reject:" >&2
    printf '  %s\n' $missing_from_store >&2
    exit 1
fi

# Every offered action has a name in both languages, and every state label the page prints does too.
for table in "$table_en" "$table_de"; do
    for action in $offered; do
        grep -q "^\"controller\.action\.$action\" *=" "$table" || {
            echo "check_controller_actions: FAIL - $table has no controller.action.$action" >&2
            exit 1
        }
    done
    for key in controller.state.action controller.state.passthrough; do
        grep -q "^\"$key\" *=" "$table" || {
            echo "check_controller_actions: FAIL - $table has no $key" >&2
            exit 1
        }
    done
done

count=$(printf '%s\n' "$declared" | grep -c .)
echo "check_controller_actions: PASS - $count action(s), each offered by the page and named in English and German."
