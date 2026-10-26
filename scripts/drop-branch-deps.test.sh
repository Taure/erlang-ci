#!/usr/bin/env bash
# Needs escript on PATH (Erlang/OTP).
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/drop-branch-deps.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

command -v escript >/dev/null 2>&1 || { echo "escript not on PATH"; exit 1; }

assert() {
    local test_name="$1"
    shift
    if "$@"; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        FAIL=$((FAIL + 1))
    fi
}

# project NAME: fresh dir with a cached copy of every dep the cases use
project() {
    local dir="$TMPDIR/$1"
    mkdir -p "$dir"
    for d in default/lib/locked_branch default/lib/no_lock_branch \
        test/lib/meck test/lib/no_ref test/lib/empty_ref test/lib/subdir \
        test/lib/legacy test/lib/tagged test/lib/pinned test/lib/hexdep \
        test/plugins/rebar3_audit; do
        mkdir -p "$dir/_build/$d"
    done
    echo "$dir"
}

run() {
    (cd "$1" && bash -e -o pipefail "$SCRIPT")
}

gone() { [ ! -e "$1" ]; }
kept() { [ -d "$1" ]; }

CONFIG='{deps, [
    {locked_branch, {git, "https://example.invalid/a.git", {branch, "main"}}},
    {hexdep, "1.0.0"}
]}.
{project_plugins, [{rebar3_audit, {git, "https://example.invalid/p.git", {branch, "main"}}}]}.
{profiles, [
    {test, [{deps, [
        {meck, {git, "https://example.invalid/meck.git", {branch, "master"}}},
        {no_ref, {git, "https://example.invalid/n.git"}},
        {empty_ref, {git, "https://example.invalid/e.git", ""}},
        {subdir, {git_subdir, "https://example.invalid/s.git", {branch, "main"}, "apps/subdir"}},
        {legacy, ".*", {git, "https://example.invalid/l.git", {branch, "main"}}},
        {tagged, {git, "https://example.invalid/t.git", {tag, "v1.0.0"}}},
        {pinned, {git, "https://example.invalid/r.git", {ref, "0123456789abcdef"}}},
        hexdep
    ]}]},
    {prod, not_a_proplist}
]}.'

LOCK='{"1.2.0",
[{<<"locked_branch">>,
  {git,"https://example.invalid/a.git",
       {ref,"0123456789abcdef0123456789abcdef01234567"}},
  0}]}.
[].'

echo "=== locked repo ==="
p=$(project locked)
printf '%s\n' "$CONFIG" >"$p/rebar.config"
printf '%s\n' "$LOCK" >"$p/rebar.lock"
out=$(run "$p")
assert "exits 0" [ $? -eq 0 ]
assert "drops profile branch dep" gone "$p/_build/test/lib/meck"
assert "drops dep with no ref" gone "$p/_build/test/lib/no_ref"
assert "drops dep with empty ref" gone "$p/_build/test/lib/empty_ref"
assert "drops git_subdir branch dep" gone "$p/_build/test/lib/subdir"
assert "drops {Name, Vsn, Source} branch dep" gone "$p/_build/test/lib/legacy"
assert "keeps locked branch dep" kept "$p/_build/default/lib/locked_branch"
assert "keeps tag dep" kept "$p/_build/test/lib/tagged"
assert "keeps ref dep" kept "$p/_build/test/lib/pinned"
assert "keeps hex dep" kept "$p/_build/test/lib/hexdep"
assert "leaves plugins alone" kept "$p/_build/test/plugins/rebar3_audit"
assert "logs what it drops" grep -q "_build/test/lib/meck" <<<"$out"

echo "=== repo without rebar.lock ==="
p=$(project nolock)
printf '%s\n' "$CONFIG" >"$p/rebar.config"
run "$p" >/dev/null
assert "exits 0" [ $? -eq 0 ]
assert "drops default branch dep" gone "$p/_build/default/lib/locked_branch"
assert "keeps hex dep" kept "$p/_build/test/lib/hexdep"

echo "=== old lock format ==="
p=$(project oldlock)
printf '%s\n' "$CONFIG" >"$p/rebar.config"
printf '%s\n' '[{<<"locked_branch">>,{git,"u",{ref,"abc"}},0}].' >"$p/rebar.lock"
run "$p" >/dev/null
assert "keeps locked branch dep" kept "$p/_build/default/lib/locked_branch"

echo "=== no rebar.config ==="
p=$(project noconfig)
run "$p" >/dev/null
assert "exits 0" [ $? -eq 0 ]
assert "drops nothing" kept "$p/_build/test/lib/meck"

echo "=== no _build ==="
p="$TMPDIR/nobuild"
mkdir -p "$p"
printf '%s\n' "$CONFIG" >"$p/rebar.config"
run "$p" >/dev/null
assert "exits 0" [ $? -eq 0 ]
assert "creates nothing" gone "$p/_build"

echo "=== empty rebar.config and rebar.lock ==="
p=$(project empty)
: >"$p/rebar.config"
: >"$p/rebar.lock"
run "$p" >/dev/null
assert "exits 0" [ $? -eq 0 ]
assert "drops nothing" kept "$p/_build/test/lib/meck"

echo "=== unparseable rebar.config ==="
p=$(project broken)
printf '%s\n' '{deps, [' >"$p/rebar.config"
out=$(run "$p" 2>/dev/null)
assert "exits 0" [ $? -eq 0 ]
assert "warns" grep -q "::warning::" <<<"$out"
assert "drops nothing" kept "$p/_build/test/lib/meck"

echo "=== unsafe dep name ==="
p=$(project unsafe)
mkdir -p "$p/_build/test/lib/ok_name"
printf '%s\n' "{profiles, [{test, [{deps, [{'..', {git, \"u\", {branch, \"main\"}}}]}]}]}." >"$p/rebar.config"
run "$p" >/dev/null
assert "exits 0" [ $? -eq 0 ]
assert "keeps _build" kept "$p/_build/test/lib"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
