#!/usr/bin/env bash
# Extracted version-type detection logic from action.yml
# Used by both the action and unit tests
set -euo pipefail

# Inputs: INPUT_VERSION_FILE, INPUT_OTP_VERSION, INPUT_VERSION_TYPE
# Outputs: file, version-type (written to GITHUB_OUTPUT or stdout)

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

# When sourced, just export functions. When run directly, write outputs.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    file=$(detect_file)
    version_type=$(detect_version_type "$file")

    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "file=$file" >> "$GITHUB_OUTPUT"
        echo "version-type=$version_type" >> "$GITHUB_OUTPUT"
    else
        echo "file=$file"
        echo "version-type=$version_type"
    fi
fi
