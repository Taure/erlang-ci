#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/eqwalize-scope.sh"

PASS=0
FAIL=0

assert_eq() {
    local test_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

DIAGS='{"path":"src/a.erl","severity":"error","msg":"one"}
{"path":"src/b.erl","severity":"error","msg":"two"}
{"path":"src/b.erl","severity":"warning","msg":"three"}
{"path":"_build/default/lib/x/src/a.erl","severity":"error","msg":"generated"}'

filt() { printf '%s\n' "$DIAGS" | filter_by_paths "$1" | jq -r '.msg' | tr '\n' ',' ; }
summ() { printf '%s\n' "$DIAGS" | filter_by_paths "$1" | summarise; }

echo "--- filter_by_paths ---"

assert_eq "keeps only the changed module" "one," "$(filt 'src/a.erl')"
assert_eq "keeps every diagnostic of a changed module" "two,three," "$(filt 'src/b.erl')"
assert_eq "keeps both when both changed" "one,two,three," "$(filt 'src/a.erl
src/b.erl')"

# The backlog is the whole point: an untouched module must not gate the PR.
assert_eq "drops untouched modules" "" "$(filt 'src/never.erl')"
assert_eq "empty changed set keeps nothing" "" "$(filt '')"
assert_eq "whitespace-only changed set keeps nothing" "" "$(filt '
   ')"

# A generated copy under _build shares a basename with a real source file and
# would otherwise report the same error a second time.
assert_eq "never keeps _build copies" "one," "$(filt 'src/a.erl
_build/default/lib/x/src/a.erl')"

# git may report a path relative to a subdirectory of the checkout.
assert_eq "matches on a path suffix" "one," "$(filt 'a.erl')"

echo "--- summarise ---"

assert_eq "counts errors and warnings apart" '{"errors":1,"warnings":1,"total":2}' "$(summ 'src/b.erl')"
assert_eq "clean scope is zero" '{"errors":0,"warnings":0,"total":0}' "$(summ 'src/never.erl')"

# The unit tests above call filter_by_paths directly, which is why an empty
# changed set looked fine while the real pipeline exited 2. Under
# `set -o pipefail` a right-hand side that returns without reading stdin makes
# the writer take SIGPIPE, and the whole pipeline fails.
echo "--- pipeline under pipefail ---"

pipeline_rc() {
    (
        set -euo pipefail
        printf '%s\n' "$DIAGS" | grep '^\s*{' | filter_by_paths "$1" | summarise >/dev/null
    ) 2>/dev/null
    echo $?
}

assert_eq "empty changed set does not break the pipe" "0" "$(pipeline_rc '')"
assert_eq "whitespace changed set does not break the pipe" "0" "$(pipeline_rc '   ')"
assert_eq "a matching path still succeeds" "0" "$(pipeline_rc 'src/a.erl')"
assert_eq "a non-matching path still succeeds" "0" "$(pipeline_rc 'src/never.erl')"

echo "--- main ---"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.jsonl"
assert_eq "an empty run is zero, not an error" \
    '{"errors":0,"warnings":0,"total":0}' "$(main "$TMP/empty.jsonl" HEAD 2>/dev/null)"
assert_eq "a missing input is zero, not a crash" \
    '{"errors":0,"warnings":0,"total":0}' "$(main "$TMP/nope.jsonl" HEAD 2>/dev/null)"

# A PR touching no Erlang is the ordinary case for a docs or CI change, and it
# must report zero rather than fail. This is what asobi#553 hit.
printf '%s\n' "$DIAGS" > "$TMP/diags.jsonl"
main_rc() {
    ( set -euo pipefail; main "$1" "$2" >/dev/null ) 2>/dev/null
    echo $?
}
assert_eq "main exits 0 when the PR touches no Erlang" "0" \
    "$(cd "$TMP" && git init -q . 2>/dev/null; main_rc "$TMP/diags.jsonl" HEAD)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
