#!/usr/bin/env bash
# Narrows an `elp eqwalize-all --format json` run to the modules a pull request
# touched, so a repo with an existing backlog can gate NEW type errors without
# fixing the backlog first.
#
# Filtering the output of one whole-project run, rather than invoking
# `elp eqwalize <module>` per changed file: eqwalize needs the whole project
# built either way, and per-module invocations re-analyse shared dependencies
# once each. One run, then a path filter, is both simpler and no slower.
#
# Why this exists: with the job off entirely, a tree drifts. asobi went from
# 312 to 391 errors in twelve days while nothing was checking.
set -euo pipefail

# Reads eqwalize JSONL on stdin, prints the diagnostics whose `path` is in the
# newline-separated allowlist given as $1. An empty allowlist keeps nothing.
#
# _build is excluded here as well as in the caller: a generated copy of a source
# file can otherwise match a changed path and report the same error twice.
filter_by_paths() {
    local paths="$1"
    if [ -z "${paths//[[:space:]]/}" ]; then
        return 0
    fi
    jq -c --arg want "$paths" '
        ($want | split("\n") | map(select(length > 0))) as $paths
        | select((.path // "") | test("(^|/)_build/") | not)
        | select(
            (.path // "") as $p
            | any($paths[]; . as $want | $p == $want or ($p | endswith("/" + $want)))
          )
    '
}

# Collapses diagnostics on stdin into the {errors, warnings, total} shape the
# rest of the pipeline already speaks.
summarise() {
    jq -sc '{
        errors: [.[] | select(.severity == "error" or .severity == "Error")] | length,
        warnings: [.[] | select(.severity == "warning" or .severity == "Warning")] | length,
        total: length
    }'
}

# The Erlang sources a PR touched. Deleted files are excluded: eqwalize cannot
# report on a file that is gone, and asking git for them only adds noise.
changed_erl_paths() {
    local base="$1" head="${2:-HEAD}"
    git diff --name-only --diff-filter=d "$base...$head" -- '*.erl' '*.hrl' || true
}

main() {
    local input="${1:-}" base="${2:-}" head="${3:-HEAD}"
    if [ -z "$input" ] || [ -z "$base" ]; then
        echo "usage: eqwalize-scope.sh <jsonl-file> <base-ref> [head-ref]" >&2
        return 2
    fi
    if [ ! -s "$input" ]; then
        echo '{"errors":0,"warnings":0,"total":0}'
        return 0
    fi

    local paths
    paths=$(changed_erl_paths "$base" "$head")
    grep '^\s*{' "$input" | filter_by_paths "$paths" | summarise
}

# When sourced, export functions only. When run directly, filter.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
