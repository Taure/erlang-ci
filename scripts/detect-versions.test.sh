#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect-versions.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
ORIG_DIR=$(pwd)
trap 'cd "$ORIG_DIR"; rm -rf "$TMPDIR"' EXIT

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

# --- detect_file tests ---

echo "=== detect_file ==="

# Explicit version-file takes priority
export INPUT_VERSION_FILE="mise.toml" INPUT_OTP_VERSION=""
assert_eq "explicit version-file" "mise.toml" "$(detect_file)"

# Falls back to .tool-versions when no otp-version and file exists
mkdir -p "$TMPDIR/with-tv"
touch "$TMPDIR/with-tv/.tool-versions"
cd "$TMPDIR/with-tv"
export INPUT_VERSION_FILE="" INPUT_OTP_VERSION=""
assert_eq "auto-detect .tool-versions" ".tool-versions" "$(detect_file)"

# No file when otp-version is set (even if .tool-versions exists)
export INPUT_VERSION_FILE="" INPUT_OTP_VERSION="28"
assert_eq "otp-version suppresses auto-detect" "" "$(detect_file)"

# No file when nothing is set and no .tool-versions
mkdir -p "$TMPDIR/empty"
cd "$TMPDIR/empty"
export INPUT_VERSION_FILE="" INPUT_OTP_VERSION=""
assert_eq "no file, no otp-version, no .tool-versions" "" "$(detect_file)"

cd "$ORIG_DIR"

# --- detect_version_type tests ---

echo "=== detect_version_type ==="

# Explicit override always wins
export INPUT_VERSION_TYPE="loose"
assert_eq "explicit loose override with file" "loose" "$(detect_version_type ".tool-versions")"

export INPUT_VERSION_TYPE="strict"
assert_eq "explicit strict override without file" "strict" "$(detect_version_type "")"

# Auto-detect: strict when file is set
export INPUT_VERSION_TYPE=""
assert_eq "strict when .tool-versions" "strict" "$(detect_version_type ".tool-versions")"

export INPUT_VERSION_TYPE=""
assert_eq "strict when mise.toml" "strict" "$(detect_version_type "mise.toml")"

# Auto-detect: loose when no file
export INPUT_VERSION_TYPE=""
assert_eq "loose when no version-file" "loose" "$(detect_version_type "")"

# --- Summary ---

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
