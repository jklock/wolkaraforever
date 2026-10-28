#!/bin/bash
# Compare this fork with the original Wolkara, https://github.com/fJavierLasso/wolkara
# - the second upstream: not engine code, but the project this fork continues.
#
# The fork's history is re-rooted on that project's tip: `main` is a true ancestor here, and
# commits after the fork point kept their trees and metadata, only the identity changed. So a
# ref that is an ancestor has nothing to port, and any other ref is compared by what each side
# *did*: its subjects, and then the files of the commits whose subject has no equivalent.
# Read-only. It never fetches unless asked, never merges, never cherry-picks.
#
# usage: wolkaraforever/tools/check_origin.sh [options]
#
#   --fetch      Fetch the remote first (needs network). Without it the report
#                describes the refs as they were last fetched.
#   --strict     Exit 1 when the original Wolkara has work this fork does not.
#                Without it the report is information only.
#   --remote N   Remote name        (default: fJavierLasso)
#   --branch N   Compare this ref   (default: every branch of the remote)
#
# Environment: WOLKARA_REMOTE, WOLKARA_URL, WOLKARA_BRANCH.
#
# Exit status: 0 nothing to port; 1 something to port and --strict was given;
# 2 error.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

remote=${WOLKARA_REMOTE:-fJavierLasso}
url=${WOLKARA_URL:-https://github.com/fJavierLasso/wolkara.git}
branch=${WOLKARA_BRANCH:-}
fetch=0
strict=0

while [ $# -gt 0 ]; do
    case "$1" in
        --fetch) fetch=1;;
        --strict) strict=1;;
        --remote) shift; remote=${1:?--remote needs a name};;
        --branch) shift; branch=${1:?--branch needs a name};;
        -h|--help) sed -n '2,32p' "$0"; exit 0;;
        *) printf 'check_origin: unknown option: %s\n' "$1" >&2; exit 2;;
    esac
    shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'check_origin: %s\n' "$*" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git working tree"

# 1. The remote may not exist in a fresh clone. Add it; never overwrite one.
if ! git remote get-url "$remote" >/dev/null 2>&1; then
    say "no '$remote' remote; adding $url"
    git remote add "$remote" "$url" || die "cannot add remote '$remote'"
fi
say "check_origin: $remote -> $(git remote get-url "$remote")"

if [ "$fetch" = 1 ]; then
    say "fetching $remote"
    git fetch "$remote" --no-tags || die "cannot fetch '$remote'"
fi

# 2. Which refs to compare. The default is every branch the remote has, because
#    work sits on branches upstream has not merged (the iPhone support is one).
refs=""
if [ -n "$branch" ]; then
    git rev-parse --quiet --verify "$remote/$branch" >/dev/null \
        || die "'$remote/$branch' does not exist; run with --fetch"
    refs=$branch
else
    refs=$(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$remote/" 2>/dev/null \
        | grep -v '^HEAD$' | sort)
    [ -n "$refs" ] || die "no branches under '$remote'; run with --fetch"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check_origin.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

# 3. The comparison is by subject, because the SHAs were rewritten. One subject
#    per line, sorted, so `comm` can subtract one history from the other.
git log --format=%s HEAD >"$tmp/here.all" 2>/dev/null || die "cannot read this history"
sort -u "$tmp/here.all" >"$tmp/here"

missing_total=0
missing_shas=""

for ref in $refs; do
    # A ref that is already an ancestor needs no comparison at all: its work is
    # in this history by construction.
    if git merge-base --is-ancestor "$remote/$ref" HEAD 2>/dev/null; then
        say ""
        say "$remote/$ref"
        say "  joined: an ancestor of HEAD, nothing to port"
        continue
    fi

    git log --format=%s "HEAD..$remote/$ref" >"$tmp/theirs.all" 2>/dev/null || continue
    if [ ! -s "$tmp/theirs.all" ]; then
        say ""
        say "$remote/$ref"
        say "  nothing after the point this fork already carries"
        continue
    fi
    sort -u "$tmp/theirs.all" >"$tmp/theirs"
    comm -23 "$tmp/theirs" "$tmp/here" >"$tmp/missing"

    by_sha=$(wc -l <"$tmp/theirs.all" | tr -d ' ')
    by_subject=$(wc -l <"$tmp/missing" | tr -d ' ')

    say ""
    say "$remote/$ref"
    say "  $by_sha commit(s) by SHA are not in this history (their SHAs predate the rewrite; compare subjects)"
    if [ "$by_subject" = 0 ]; then
        say "  every one of them has an equivalent here: nothing to port"
        continue
    fi
    say "  $by_subject commit(s) carry work this fork does not have:"

    # 4. Name the files of the missing commits and what each one becomes here:
    #    a patch on a platform file, a layer module, or documentation.
    git log --reverse --format='%h%x09%s' "HEAD..$remote/$ref" >"$tmp/log"
    while IFS=$'\t' read -r sha subject; do
        grep -Fxq "$subject" "$tmp/missing" || continue
        missing_shas="$missing_shas $sha"
        missing_total=$((missing_total + 1))
        say "    $sha  $subject"
        git show --name-only --format='' "$sha" 2>/dev/null | sed '/^$/d' >"$tmp/files"
        files=$(wc -l <"$tmp/files" | tr -d ' ')
        shown=0
        while IFS= read -r path; do
            shown=$((shown + 1))
            if [ "$shown" -gt 8 ]; then
                say "        ... and $((files - 8)) more file(s); git show --name-status $sha"
                break
            fi
            case "$path" in
                launcher/*)
                    say "        $path -> layer: wolkaraforever/ (the module that owns this file)";;
                runtime/*|translation/*|authorization/*|tests/*|testguest/*|tools/*|profiles/*|support/*|management/*|project.yml)
                    say "        $path -> patch: platform/$path (never edit it there)";;
                docs/*)
                    say "        $path -> documentation: $path";;
                *.md)
                    say "        $path -> documentation: the same file at the repository root";;
                *)
                    say "        $path -> review: no mapping, decide by hand";;
            esac
        done <"$tmp/files"
    done <"$tmp/log"
done

say ""
if [ "$missing_total" = 0 ]; then
    say "check_origin: in sync - every commit of $remote has an equivalent here."
    exit 0
fi

say "check_origin: $missing_total commit(s) to port, by hand, as layer changes:"
say "  a patch when the file is a platform file, a wolkaraforever/ module when it is"
say "  the launcher, documentation when it is prose. Then run check_layers.sh and the"
say "  focused suite. Never cherry-pick: the diffs were written against a tree this"
say "  fork no longer has."
if [ "$strict" = 1 ]; then
    exit 1
fi
exit 0
