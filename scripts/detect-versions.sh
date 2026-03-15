#!/usr/bin/env bash
# Extracted version detection logic from action.yml
# Used by both the action and unit tests
set -euo pipefail

# Inputs: INPUT_VERSION_FILE, INPUT_OTP_VERSION, INPUT_REBAR3_VERSION, INPUT_VERSION_TYPE
# Outputs: file, version-type, otp-version, rebar3-version

detect_file() {
    if [ -n "${INPUT_VERSION_FILE:-}" ]; then
        echo "$INPUT_VERSION_FILE"
    elif [ -z "${INPUT_OTP_VERSION:-}" ] && [ -f .tool-versions ]; then
        echo ".tool-versions"
    else
        echo ""
    fi
}

detect_version_type() {
    local file="$1"
    if [ -n "${INPUT_VERSION_TYPE:-}" ]; then
        echo "$INPUT_VERSION_TYPE"
    elif [ -n "$file" ]; then
        echo "strict"
    else
        echo "loose"
    fi
}

# When version-file is active, suppress explicit version inputs
# to avoid setup-beam "must choose one or the other" error
detect_otp_version() {
    local file="$1"
    if [ -n "$file" ]; then
        echo ""
    else
        echo "${INPUT_OTP_VERSION:-}"
    fi
}

detect_rebar3_version() {
    local file="$1"
    if [ -n "$file" ]; then
        echo ""
    else
        echo "${INPUT_REBAR3_VERSION:-3}"
    fi
}

# When sourced, just export functions. When run directly, write outputs.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    file=$(detect_file)
    version_type=$(detect_version_type "$file")
    otp_version=$(detect_otp_version "$file")
    rebar3_version=$(detect_rebar3_version "$file")

    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "file=$file" >> "$GITHUB_OUTPUT"
        echo "version-type=$version_type" >> "$GITHUB_OUTPUT"
        echo "otp-version=$otp_version" >> "$GITHUB_OUTPUT"
        echo "rebar3-version=$rebar3_version" >> "$GITHUB_OUTPUT"
    else
        echo "file=$file"
        echo "version-type=$version_type"
        echo "otp-version=$otp_version"
        echo "rebar3-version=$rebar3_version"
    fi
fi
