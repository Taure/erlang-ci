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

export INPUT_VERSION_FILE="mise.toml" INPUT_OTP_VERSION=""
assert_eq "explicit version-file" "mise.toml" "$(detect_file)"

mkdir -p "$TMPDIR/with-tv"
touch "$TMPDIR/with-tv/.tool-versions"
cd "$TMPDIR/with-tv"
export INPUT_VERSION_FILE="" INPUT_OTP_VERSION=""
assert_eq "auto-detect .tool-versions" ".tool-versions" "$(detect_file)"

export INPUT_VERSION_FILE="" INPUT_OTP_VERSION="28"
assert_eq "otp-version suppresses auto-detect" "" "$(detect_file)"

mkdir -p "$TMPDIR/empty"
cd "$TMPDIR/empty"
export INPUT_VERSION_FILE="" INPUT_OTP_VERSION=""
assert_eq "no file, no otp-version, no .tool-versions" "" "$(detect_file)"

cd "$ORIG_DIR"

# --- detect_version_type tests ---

echo "=== detect_version_type ==="

export INPUT_VERSION_TYPE="loose"
assert_eq "explicit loose override with file" "loose" "$(detect_version_type ".tool-versions")"

export INPUT_VERSION_TYPE="strict"
assert_eq "explicit strict override without file" "strict" "$(detect_version_type "")"

export INPUT_VERSION_TYPE=""
assert_eq "strict when .tool-versions" "strict" "$(detect_version_type ".tool-versions")"

export INPUT_VERSION_TYPE=""
assert_eq "strict when mise.toml" "strict" "$(detect_version_type "mise.toml")"

export INPUT_VERSION_TYPE=""
assert_eq "loose when no version-file" "loose" "$(detect_version_type "")"

# --- detect_otp_version tests ---

echo "=== detect_otp_version ==="

export INPUT_OTP_VERSION="28.4.1"
assert_eq "passthrough when no file" "28.4.1" "$(detect_otp_version "")"

export INPUT_OTP_VERSION="28.4.1"
assert_eq "suppressed when file active" "" "$(detect_otp_version ".tool-versions")"

export INPUT_OTP_VERSION=""
assert_eq "empty when no file and no input" "" "$(detect_otp_version "")"

# --- detect_rebar3_version tests ---

echo "=== detect_rebar3_version ==="

export INPUT_REBAR3_VERSION="3.24"
assert_eq "passthrough when no file" "3.24" "$(detect_rebar3_version "")"

export INPUT_REBAR3_VERSION="3.24"
assert_eq "suppressed when file active" "" "$(detect_rebar3_version ".tool-versions")"

export INPUT_REBAR3_VERSION=""
assert_eq "default 3 when no file and no input" "3" "$(detect_rebar3_version "")"

# --- Summary ---

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
