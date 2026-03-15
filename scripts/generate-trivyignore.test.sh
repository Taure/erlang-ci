#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/generate-trivyignore.sh"

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

assert_true() {
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

assert_false() {
    local test_name="$1"
    shift
    if "$@"; then
        echo "  FAIL: $test_name (expected false)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    fi
}

# --- normalize_version tests ---

echo "=== normalize_version ==="

assert_eq "simple version" "000280000400001" "$(normalize_version "28.4.1")"
assert_eq "two segments" "000280000400000" "$(normalize_version "28.4")"
assert_eq "single segment" "000280000000000" "$(normalize_version "28")"
assert_eq "old version" "000260000200005" "$(normalize_version "26.2.5")"

# --- version_gte tests ---

echo "=== version_gte ==="

assert_true "28.4.1 >= 28.0.3" version_gte "28.4.1" "28.0.3"
assert_true "28.4.1 >= 28.4.1" version_gte "28.4.1" "28.4.1"
assert_false "28.0.3 not >= 28.4.1" version_gte "28.0.3" "28.4.1"
assert_true "28.4 >= 28.0.3" version_gte "28.4" "28.0.3"
assert_false "27.3.4 not >= 28.0.1" version_gte "27.3.4" "28.0.1"

# --- extract_otp_patched_version tests ---

echo "=== extract_otp_patched_version ==="

advisory='{"patched":["28.0.3, 27.3.4.3, 26.2.5.15","5.3.3, 5.2.11.3, 5.1.4.12"]}'
assert_eq "extracts OTP 28 patch" "28.0.3" "$(extract_otp_patched_version "$advisory" "28")"
assert_eq "extracts OTP 27 patch" "27.3.4.3" "$(extract_otp_patched_version "$advisory" "27")"
assert_eq "extracts OTP 26 patch" "26.2.5.15" "$(extract_otp_patched_version "$advisory" "26")"
assert_eq "no match for OTP 25" "" "$(extract_otp_patched_version "$advisory" "25")"

# --- Summary ---

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
