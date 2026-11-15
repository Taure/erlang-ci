#!/usr/bin/env bash
# Static checks on release.yml and hex-publish.yml. GitHub rejects a caller at
# startup when a called workflow requests a permission the caller did not
# grant, so release.yml asking for more than `contents: write` would break
# every existing caller, including those that never publish to Hex.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT/.github/workflows" <<'PY'
import re
import subprocess
import sys

import yaml

root = sys.argv[1]
passed = failed = 0


def check(name, ok):
    global passed, failed
    if ok:
        passed += 1
        print("  PASS: %s" % name)
    else:
        failed += 1
        print("  FAIL: %s" % name)


def load(name):
    with open("%s/%s" % (root, name)) as handle:
        return yaml.safe_load(handle)


def trigger(workflow):
    # PyYAML reads the bare key `on` as the boolean True.
    return workflow.get("on", workflow.get(True))


def steps(workflow):
    return [s for job in workflow["jobs"].values() for s in job.get("steps", [])]


print("=== release.yml ===")
release = load("release.yml")
call = trigger(release)["workflow_call"]
check(
    "jobs request contents: write and nothing else",
    all(job.get("permissions") == {"contents": "write"} for job in release["jobs"].values()),
)
check("no workflow-level permissions", "permissions" not in release)
check("no required inputs", not any(i.get("required") for i in call.get("inputs", {}).values()))
check("no secrets", "secrets" not in call)
check("outputs tag and released", set(call.get("outputs", {})) == {"tag", "released"})

print("=== self-release.yml ===")
self_release = load("self-release.yml")
check(
    "calls release.yml with contents: write only",
    all(job.get("permissions") == {"contents": "write"} for job in self_release["jobs"].values()),
)

print("=== hex-publish.yml ===")
publish = load("hex-publish.yml")
call = trigger(publish)["workflow_call"]
jobs = publish["jobs"]
check("workflow-level permissions are empty", publish.get("permissions") == {})
check("one job", list(jobs) == ["hex-publish"])
job = jobs["hex-publish"]
check(
    "job requests contents: read and id-token: write only",
    job.get("permissions") == {"contents": "read", "id-token": "write"},
)
check("job runs in the environment input", job.get("environment") == "${{ inputs.environment }}")
check("no secrets declared", "secrets" not in call)
with open("%s/hex-publish.yml" % root) as handle:
    text = handle.read()
check("no secrets referenced", "secrets." not in text)
check("only tag is required", [k for k, v in call["inputs"].items() if v.get("required")] == ["tag"])
check("environment defaults to release", call["inputs"]["environment"].get("default") == "release")

uses = [s["uses"] for s in steps(publish) if "uses" in s]
check("actions are pinned by commit SHA", all(re.search(r"@[0-9a-f]{40}$", u) for u in uses))
check("no cache is restored", not any(u.startswith("actions/cache") for u in uses))
check("no Taure/erlang-ci action", not any(u.startswith("Taure/erlang-ci") for u in uses))
check("no expression inside run scripts", not any("${{" in s.get("run", "") for s in steps(publish)))

checkout = [s for s in steps(publish) if s.get("uses", "").startswith("actions/checkout@")]
check("one checkout", len(checkout) == 1)
options = checkout[0].get("with", {}) if checkout else {}
check("checkout takes the tag", options.get("ref") == "refs/tags/${{ inputs.tag }}")
check("checkout fetches all tags", options.get("fetch-depth") == 0)
check("checkout does not persist credentials", options.get("persist-credentials") is False)

names = [s.get("name") for s in steps(publish)]
check("trigger guard runs first", names[0] == "Check trigger and tag")
check(
    "preflight precedes publish",
    "Preflight" in names and "Publish" in names and names.index("Preflight") < names.index("Publish"),
)
preflight = next(s for s in steps(publish) if s.get("name") == "Preflight")


def rebar3_check(version_output):
    # Runs the preflight's rebar3 version check against a stubbed rebar3.
    lines = preflight["run"].splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip().startswith("REBAR3=$("))
    end = next(i for i in range(start, len(lines)) if lines[i].strip() == "fi")
    script = "\n".join(
        [
            "set -eo pipefail",
            'fail() { echo "FAIL: $1"; exit 1; }',
            "rebar3() { cat <<'OUT'",
            version_output,
            "OUT",
            "}",
        ]
        + lines[start : end + 1]
    )
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    return result.returncode, result.stdout


FETCH = (
    "\x1b[0;32m===> Fetching rebar3_hex v7.5.0\n"
    "\x1b[0m\x1b[0;32m===> Analyzing applications...\n"
    "\x1b[0m\x1b[0;32m===> Compiling rebar3_hex\n"
    "\x1b[0m"
)
check("rebar3 3.28.0 passes", rebar3_check("rebar 3.28.0 on Erlang/OTP 29 Erts 17.0") == (0, ""))
check("rebar3 3.27.1 passes", rebar3_check("rebar 3.27.1 on Erlang/OTP 28 Erts 16.1") == (0, ""))
check(
    "rebar3 3.28.0 passes behind plugin fetch lines",
    rebar3_check(FETCH + "rebar 3.28.0 on Erlang/OTP 29 Erts 17.0") == (0, ""),
)
code, out = rebar3_check("rebar 3.27.0 on Erlang/OTP 29 Erts 17.0")
check("rebar3 3.27.0 is refused", code == 1 and "this job runs rebar3 3.27.0" in out)
code, out = rebar3_check(FETCH + "rebar 3.26.0 on Erlang/OTP 28 Erts 16.1")
check("rebar3 3.26.0 is refused behind plugin fetch lines", code == 1 and "this job runs rebar3 3.26.0" in out)
code, out = rebar3_check(FETCH.rstrip())
check("an unreadable version warns and continues", code == 0 and "::warning::" in out)
check(
    "rebar3 version is read after compile",
    preflight["run"].index("rebar3 compile") < preflight["run"].index("REBAR3=$("),
)
check("preflight refuses rebar3_hex before 7.5.0", "printf '%s\\n' 7.5.0 \"$HEX_VSN\"" in preflight["run"])
publish_step = next(s for s in steps(publish) if s.get("name") == "Publish")
check("publishes with rebar3 hex publish", "rebar3 hex publish" in publish_step["run"])
check("verifies the registry last", names[-1] == "Verify the release is on Hex")

print()
print("Results: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PY
