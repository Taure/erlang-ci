#!/usr/bin/env bash
# Runs the rebar3 version check of hex-publish.yml with the real rebar3, in a
# project that has nothing built yet, which is when rebar3 prints plugin fetch
# lines ahead of its version. The stubbed cases live in
# hex-publish-workflow.test.sh.
#
# Usage: hex-publish-rebar3-check.test.sh <project-dir> <expected-rebar3-version>
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$1"
EXPECTED="$2"

CHECK=$(python3 - "$ROOT/.github/workflows/hex-publish.yml" <<'PY'
import sys

import yaml

with open(sys.argv[1]) as handle:
    workflow = yaml.safe_load(handle)
steps = workflow["jobs"]["hex-publish"]["steps"]
lines = next(s for s in steps if s.get("name") == "Preflight")["run"].splitlines()
start = next(i for i, line in enumerate(lines) if line.strip().startswith("REBAR3=$("))
end = next(i for i in range(start, len(lines)) if lines[i].strip() == "fi")
print("\n".join(lines[start : end + 1]))
PY
)

cd "$PROJECT" || exit 1
rm -rf _build
OUT=$(bash -eo pipefail -c "fail() { echo \"FAIL: \$1\"; exit 1; }
$CHECK
echo \"READ: \$REBAR3\"" 2>&1)
CODE=$?
echo "$OUT" | grep -E '^(READ|FAIL): |::warning::'

if [ "$(printf '%s\n' 3.27.1 "$EXPECTED" | sort -V | head -n 1)" = "3.27.1" ]; then
  WANT="READ: $EXPECTED"
  WANT_CODE=0
else
  WANT="this job runs rebar3 $EXPECTED."
  WANT_CODE=1
fi

if [ "$CODE" -eq "$WANT_CODE" ] && echo "$OUT" | grep -qF "$WANT"; then
  echo "  PASS: the check read rebar3 $EXPECTED"
  exit 0
fi
echo "  FAIL: expected exit $WANT_CODE and '$WANT', got exit $CODE"
exit 1
