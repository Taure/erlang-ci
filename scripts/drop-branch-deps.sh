#!/usr/bin/env bash
# rebar3 keeps a dep already in _build and only re-resolves what rebar.lock
# pins, and it locks the default profile alone. A dep that tracks a git branch
# from any other profile, or from a repo without a lock, therefore stays at
# whatever commit a restored cache holds while the branch moves on. Drop those
# so rebar3 fetches the branch head. Run from the project root.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f rebar.config ] || exit 0
[ -d _build ] || exit 0
command -v escript >/dev/null 2>&1 || exit 0

if ! deps=$(escript "$script_dir/unlocked-branch-deps.escript"); then
    echo "::warning::Could not read branch-tracked deps from rebar.config; cached copies were kept."
    exit 0
fi

while IFS= read -r dep; do
    case "$dep" in
        '' | *[!A-Za-z0-9_]*) continue ;;
    esac
    for dir in _build/*/lib/"$dep"; do
        [ -e "$dir" ] || [ -L "$dir" ] || continue
        echo "Dropping $dir: it tracks a git branch rebar.lock does not pin"
        rm -rf "$dir"
    done
done <<<"$deps"
