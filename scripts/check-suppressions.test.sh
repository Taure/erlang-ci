#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/check-suppressions.sh"

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

# scan_diff returns 1 when it finds something, 0 when clean.
rc_of() {
    printf '%s\n' "$1" | scan_diff >/dev/null 2>&1
    echo $?
}

out_of() {
    printf '%s\n' "$1" | scan_diff 2>&1 || true
}

echo "--- scan_diff ---"

clean='+++ b/src/a.erl
+foo() -> ok.
+%% a comment'
assert_eq "clean diff passes" "0" "$(rc_of "$clean")"

fixme='+++ b/src/a.erl
+% eqwalizer:fixme bad type
+foo() -> ok.'
assert_eq "added eqwalizer:fixme fails" "1" "$(rc_of "$fixme")"

nowarn='+++ b/src/a.erl
+-dialyzer(nowarn_function).'
assert_eq "added -dialyzer(nowarn_ fails" "1" "$(rc_of "$nowarn")"

nowarn_brace='+++ b/src/a.erl
+-dialyzer({nowarn_function, foo/0}).'
assert_eq "added -dialyzer({nowarn_ fails" "1" "$(rc_of "$nowarn_brace")"

# The whole point of scoping to added lines: existing debt must not break a repo.
removed='+++ b/src/a.erl
-% eqwalizer:fixme bad type
+foo() -> ok.'
assert_eq "REMOVING a fixme passes" "0" "$(rc_of "$removed")"

context='+++ b/src/a.erl
 % eqwalizer:fixme bad type
+foo() -> ok.'
assert_eq "fixme in context line passes" "0" "$(rc_of "$context")"

# `+++ b/...` is a header, not an added line, so a filename must not self-trigger.
header_only='+++ b/src/eqwalizer_fixme_notes.erl
+foo() -> ok.'
assert_eq "filename resembling a suppression passes" "0" "$(rc_of "$header_only")"

# elp:ignore is a different tool with per-rule justifications; not our rule.
elp_ignore='+++ b/src/a.erl
+% elp:ignore W0023 - bounded by config'
assert_eq "elp:ignore is not covered" "0" "$(rc_of "$elp_ignore")"

assert_eq "names the file it found" "src/a.erl" \
    "$(out_of "$fixme" | head -1 | cut -d: -f1)"

echo "--- scan_added_files ---"

added_rc() { printf '%s\n' "$1" | scan_added_files >/dev/null 2>&1; echo $?; }

assert_eq "a new .eqwalizer fails" "1" "$(added_rc ".eqwalizer")"
assert_eq "a nested .eqwalizer fails" "1" "$(added_rc "apps/foo/.eqwalizer")"
assert_eq "an ordinary new file passes" "0" "$(added_rc "src/a.erl")"
assert_eq "no added files passes" "0" "$(added_rc "")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
