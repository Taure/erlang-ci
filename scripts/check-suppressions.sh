#!/usr/bin/env bash
# Fails when a pull request ADDS a type-checker suppression.
#
# eqwalizer:fixme, -dialyzer(nowarn_...) and a .eqwalizer ignore file all turn
# a type error into silence. Clearing a backlog is exactly when someone reaches
# for one to finish a tranche, so the rule needs to be enforced rather than
# remembered.
#
# Scoped to lines the diff ADDS, deliberately: a repo carrying existing
# suppressions is not broken by turning this on, but no new one can land. Note
# `% elp:ignore <rule>` is ELP *lint*, a different tool with per-rule
# justifications, and is not covered here.
set -euo pipefail

# A suppression this repo refuses to accept, and why, one per line as
# "<pattern>|<explanation>". Patterns are grep -E.
suppression_patterns() {
    cat <<'PATTERNS'
eqwalizer:fixme|eqwalizer:fixme silences a type error instead of fixing the type
-dialyzer\(nowarn_|-dialyzer(nowarn_...) silences a dialyzer warning instead of fixing the type
-dialyzer\(\{nowarn_|-dialyzer({nowarn_...}) silences a dialyzer warning instead of fixing the type
PATTERNS
}

# Reads a unified diff on stdin, prints one "file:line: explanation" per
# offending ADDED line. Returns 1 if any were found.
scan_diff() {
    local found=0 file="" line
    local -a pats=() msgs=()
    while IFS='|' read -r pat msg; do
        [ -n "$pat" ] || continue
        pats+=("$pat")
        msgs+=("$msg")
    done < <(suppression_patterns)

    while IFS= read -r line; do
        case "$line" in
            '+++ b/'*)
                file="${line#+++ b/}"
                continue
                ;;
            '+++ '*|'--- '*|'+++'|'---')
                continue
                ;;
            '+'*)
                local added="${line#+}"
                local i
                for i in "${!pats[@]}"; do
                    if printf '%s' "$added" | grep -qE -- "${pats[$i]}"; then
                        echo "${file:-<unknown>}: ${msgs[$i]}"
                        echo "    ${added}"
                        found=1
                    fi
                done
                ;;
        esac
    done

    return "$found"
}

# A new ignore file is a suppression the diff scan cannot see, because its
# content is not what matters - its existence is.
scan_added_files() {
    local found=0 f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            .eqwalizer|*/.eqwalizer)
                echo "$f: a .eqwalizer ignore file excludes modules from type checking"
                found=1
                ;;
        esac
    done
    return "$found"
}

main() {
    local base="${1:-}" head="${2:-HEAD}" rc=0
    if [ -z "$base" ]; then
        echo "usage: check-suppressions.sh <base-ref> [head-ref]" >&2
        return 2
    fi

    local diff added
    diff=$(git diff --unified=0 "$base...$head" -- '*.erl' '*.hrl' '*.escript' || true)
    added=$(git diff --name-only --diff-filter=A "$base...$head" || true)

    if ! printf '%s\n' "$diff" | scan_diff; then
        rc=1
    fi
    if ! printf '%s\n' "$added" | scan_added_files; then
        rc=1
    fi

    if [ "$rc" -ne 0 ]; then
        echo ""
        echo "::error::This change adds a type-checker suppression. Fix the type instead."
        return 1
    fi
    echo "No new type-checker suppressions."
    return 0
}

# When sourced, export functions only. When run directly, scan.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
