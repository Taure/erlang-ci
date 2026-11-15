# erlang-ci

A standardized CI/CD pipeline for Erlang/OTP projects.

**Four ways to use it:**

1. **Reusable CI workflow** — a complete CI pipeline with parallel jobs
2. **Reusable release workflow** — auto-tag and release from conventional commits
3. **Standalone composite actions** — use individual tools (dialyzer, ELP, audit, SBOM, mutate) independently
4. **Setup action** — just setup + caching, bring your own jobs

> **Security:** All release tags are immutable (protected by repository rulesets). Pin to exact semver versions (e.g. `@v2.0.0`). Floating major tags (`@v1`, `@v2`) are not used.

## Quick start

Create `.github/workflows/ci.yml` in your project:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
```

This runs **compile → fmt | xref | dialyzer | eunit** in parallel.

## CI pipeline

After compile, all enabled steps run in parallel:

```
                    ┌─ fmt ─────────────────────┐
                    ├─ xref ────────────────────┤
                    ├─ dialyzer ────────────────┤
                    ├─ lint ────────────────────┤
                    ├─ hank ────────────────────┤
                    ├─ sheldon ─────────────────┤
                    ├─ audit ───────────────────┤
compile ──────────► ├─ eunit ───────────────────┤
                    ├─ ct ──────────────────────┤
                    ├─ coverage ────────────────┤
                    ├─ sbom ────────────────────┤
                    ├─ mutate ──────────────────┤
                    ├─ dependency-submission ───┤
                    ├─ ex-doc ──────────────────┤
                    └───────────────────────────┘
```

### PR vs main optimization

Steps are automatically scoped to where they provide value. No configuration needed — the workflow detects the event type.

| Step | PR | Main | Rationale |
|------|:--:|:----:|-----------|
| Compile | Yes | Yes | Catch merge-induced breakage |
| EUnit / CT | Yes | Yes | Catch merge-induced breakage |
| Audit | Yes | Yes | Advisories can appear anytime |
| SBOM scan | Yes | Yes | Catch vulnerabilities early |
| Format / Xref | Yes | — | Already validated in PR |
| Dialyzer | Yes | — | Already validated in PR |
| Lint / Hank / Sheldon | Yes | — | Already validated in PR |
| ELP Lint / eqWAlize | Yes | — | Already validated in PR |
| Coverage | Yes | — | Already validated in PR |
| Mutation testing | Yes | — | Already PR-only (diff mode) |
| Summary comment | Yes | — | PR context only |
| Documentation (ex_doc) | — | Yes | Publish on merge |
| SBOM artifact upload | — | Yes | Persist for releases |
| Dependency submission | — | Yes | Update GitHub dep graph |

### Step reference

| Step | Default | Input | Requires |
|------|---------|-------|----------|
| Compile | always | — | — |
| Format (`rebar3 fmt --check`) | **on** | `enable-fmt` | `erlfmt` plugin |
| Xref | **on** | `enable-xref` | — |
| Dialyzer | **on** | `enable-dialyzer` | — |
| Lint (`rebar3 lint`) | off | `enable-lint` | `rebar3_lint` plugin |
| Hank (`rebar3 hank`) | off | `enable-hank` | `rebar3_hank` plugin |
| Sheldon (`rebar3 spellcheck`) | off | `enable-sheldon` | `rebar3_sheldon` plugin |
| EUnit | **on** | `enable-eunit` | — |
| Common Test | off | `enable-ct` | — |
| ExDoc | off | `enable-ex-doc` | `rebar3_ex_doc` plugin |
| Audit | off | `enable-audit` | `rebar3_audit` plugin |
| Coverage | off | `enable-coverage` | `covertool` plugin + `{cover_enabled, true}` |
| SBOM | off | `enable-sbom` | `rebar3_sbom` plugin |
| SBOM vulnerability scan | off | `enable-sbom-scan` | `rebar3_sbom` plugin + `enable-sbom` |
| Mutation Testing | off | `enable-mutate` | `rebar3_mutate` plugin |
| Dependency Submission | off | `enable-dependency-submission` | — (self-contained) |

## Release workflow

A reusable workflow that auto-tags and creates GitHub releases from conventional commits using [git-cliff](https://git-cliff.org/).

**How it works:**

1. Analyzes commits since the last tag
2. Determines the next semver (`feat:` → minor, `fix:` → patch, breaking → major)
3. Creates a git tag and pushes it
4. Creates a GitHub release with auto-generated changelog
5. Skips silently if no version bump is needed

**Usage:**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'

  release:
    needs: ci
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.0.0
    permissions:
      contents: write
    secrets: inherit
```

**Requirements:**

- Conventional commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`)
- A `cliff.toml` in your project root (copy from this repo)

| Input | Default | Description |
|-------|---------|-------------|
| `cliff-config` | `cliff.toml` | Path to git-cliff config file |

| Output | Description |
|--------|-------------|
| `tag` | Tag this run created. Empty when it created none. |
| `released` | `"true"` when this run created a tag and a GitHub release, otherwise `"false"` |

## Publishing to Hex

`hex-publish.yml` publishes the tag that `release.yml` just created to [hex.pm](https://hex.pm), package and docs, using [Hex Workload Identity](https://hex.pm/docs/workload-identity). GitHub signs a short-lived OIDC token for the job, Hex exchanges it for a token that lasts 15 minutes and can publish one package. No `HEX_API_KEY` is stored anywhere.

It is opt-in. A repo that does not call `hex-publish.yml` is unaffected, and `release.yml` still needs `contents: write` only.

```yaml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.3.1
    permissions:
      contents: write

  hex-publish:
    needs: release
    if: needs.release.outputs.released == 'true'
    uses: Taure/erlang-ci/.github/workflows/hex-publish.yml@v2.3.1
    permissions:
      contents: read
      id-token: write
    with:
      tag: ${{ needs.release.outputs.tag }}
```

The two jobs must be in the same workflow run. A tag pushed with `GITHUB_TOKEN` starts no other workflow, so a separate `on: push: tags` workflow would never run, and Hex refuses tokens from `workflow_run`.

What the job does:

1. Fails unless the run was triggered by `push`, `workflow_dispatch` or `release`.
2. Checks out the tag with full history and refuses a tag that is not on the default branch.
3. Installs OTP and rebar3 from `.tool-versions` (or the inputs) without restoring any cache.
4. Fails if `HEX_API_KEY` is set, if OTP is older than 27, if rebar3 is older than 3.27.1, if rebar3_hex is older than 7.5, or if the version rebar3 computes differs from the tag.
5. Runs `rebar3 hex publish --yes`, which publishes the package and its docs with the same token.
6. Fails unless the release is then visible on hex.pm.

A push that produces no version bump creates no tag, so `released` is `"false"` and nothing is published. A failed publish fails the run. The tag and the GitHub release already exist at that point and are left alone, see [Re-running a failed publish](#re-running-a-failed-publish).

| Input | Default | Description |
|-------|---------|-------------|
| `tag` | required | Existing `vX.Y.Z` tag to publish |
| `environment` | `release` | GitHub environment named by the Hex workload identity |
| `otp-version` | | OTP version, 27 or later. Empty reads `.tool-versions`, or installs 28 when there is none |
| `rebar3-version` | `3` | Rebar3 version. Ignored when a version file is used |
| `version-file` | | Version file to read instead of `.tool-versions` |
| `wait-for-approval` | `false` | Wait for a staged release to be approved instead of failing |

### Requirements

- The package already exists on hex.pm. See [First release](#first-release).
- `rebar3_hex` 7.5 or later in `project_plugins`, for example `{rebar3_hex, "~> 7.5"}`, and a doc provider (`{hex, [{doc, ex_doc}]}`).
- OTP 27 or later and rebar3 3.27.1 or later in the publish job. A `.tool-versions` that pins an older rebar3 has to be raised.
- One application in `src/` with `{vsn, "git"}`. Umbrella projects are not supported.
- The publish job runs in the workflow run that a `push` to the default branch started.

### One-time setup per package

Only the package owner can do these. Nothing here is automated.

**1. GitHub environment.** Hex requires an environment for a public repository. Create `release` in the calling repository and restrict it to the default branch:

```bash
gh api -X PUT repos/OWNER/REPO/environments/release --input - <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
gh api -X POST repos/OWNER/REPO/environments/release/deployment-branch-policies \
  -f name=main -f type=branch
```

GitHub matches the branch rule against the ref that triggered the run, which is `refs/heads/main` for a push to `main`, not against the tag the job checks out.

**2. Workload identity on hex.pm.** Open the package, then Settings > Workload identities. This needs full ownership of the package and two-factor authentication on the Hex account.

| Field | Value |
|-------|-------|
| Repository owner | The GitHub user or organisation that owns the calling repository, for example `Taure` |
| Repositories | The calling repository's name without the owner, for example `shigoto` |
| Workflow | The file name of the workflow in the calling repository that contains the `hex-publish` job: `release.yml` for the snippet above, `ci.yml` when the jobs live in your CI workflow. Never `hex-publish.yml` |
| Environment | `release` |

Hex matches the calling workflow, not the reusable one, and the file name is case-sensitive. If you later move the jobs to another workflow file, add an identity for the new file name first.

**3. Staged publishing.** See the next section. For a fully automatic release it has to be off for the package.

**4. Old credentials.** Delete any `HEX_API_KEY` secret that was only there for publishing, and revoke that key on hex.pm. The publish job receives no secrets, so a leftover secret cannot reach it, but it is still a long-lived publishing credential.

### Who approves a release

Workload Identity removes the stored key. It does not add a human check. Pick one:

| Setup | What happens on a release | Who can publish |
|-------|---------------------------|-----------------|
| Environment restricted to the default branch, no reviewer, staged publishing off | Fully automatic. Every push to the default branch that bumps the version is on hex.pm a few minutes later | Anyone who can get a commit onto the default branch. Protect that branch |
| Environment with a required reviewer | The publish job waits in GitHub until a reviewer approves it. The tag and GitHub release are created before the approval | A reviewer, for each release |
| Staged publishing on for the package | The job uploads the release and Hex holds it. It is not in the registry until an owner approves it on hex.pm with a 2FA code. A staged release expires after seven days | A package owner, for each release |

Staged publishing is a package setting under Settings > Staged publishing on hex.pm. It is off for packages that existed before it was introduced and on by default for new public packages, so check it after a first release. Changing it needs 2FA.

With staged publishing on and `wait-for-approval: false`, the publish job fails with a message that the release is staged, because nothing reached the registry. Approving the staged release on hex.pm completes it and needs no re-run. With `wait-for-approval: true` the job passes `--wait` to rebar3, waits up to six hours, and fails if the release is rejected or expires.

Hex can also switch on an emergency publishing mode during an incident. Every release published from CI is then staged, whatever the package setting.

### First release

A workload identity cannot create a package or publish its first release. Publish the first version from your own machine with `rebar3 hex publish` and your Hex account, then add the workload identity. New public packages start with staged publishing on.

### Re-running a failed publish

A failed publish leaves the tag and the GitHub release in place and the run red. Fix the cause, then use **Re-run failed jobs** on that run. Only `hex-publish` runs again, with the tag from the first attempt, so no second tag is created. If the package was published and only the docs failed, the re-run publishes the docs alone.

Do not use **Re-run all jobs**: `release` then finds nothing to bump, reports `released: "false"`, and the publish is skipped.

GitHub keeps a run re-runnable for 30 days. To publish an existing tag after that, or after a failed `release` job, give the calling workflow a manual trigger:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      hex-tag:
        description: 'Existing tag to publish to Hex'
        type: string
        required: true

jobs:
  release:
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.3.1
    permissions:
      contents: write

  hex-publish:
    needs: release
    if: ${{ !cancelled() && (needs.release.outputs.released == 'true' || (github.event_name == 'workflow_dispatch' && inputs.hex-tag != '')) }}
    uses: Taure/erlang-ci/.github/workflows/hex-publish.yml@v2.3.1
    permissions:
      contents: read
      id-token: write
    with:
      tag: ${{ inputs.hex-tag || needs.release.outputs.tag }}
```

Run it from the default branch. The environment's branch rule refuses any other ref.

### Troubleshooting

| Symptom | Cause |
|---------|-------|
| The calling workflow fails at startup with `is requesting 'id-token: write', but is only allowed 'id-token: none'` | The `hex-publish` job in the calling workflow does not grant `id-token: write` |
| `HEX_API_KEY is set` | A key is in the job's environment. rebar3 would publish with it instead of Workload Identity |
| `access_denied`, no matching workload identity | The identity's repository, workflow file name or environment does not match the run. The workflow is the calling file (`release.yml`, `ci.yml`), matched case-sensitively |
| `access_denied` on a public repository with the right file name | The identity has no environment, or the job's environment has another name than the identity's |
| `Hex rejects OIDC tokens from workflow_run runs` | The publish was started by `workflow_run` or `pull_request_target`. Move it into the run started by the `push` |
| The publish job fails before its first step with an environment protection rules error | The ref that triggered the run is not allowed by the environment's branch rule |
| `rebar3_hex ... is too old` or `rebar3_hex is not a plugin` | Add `{rebar3_hex, "~> 7.5"}` to `project_plugins` |
| `Workload Identity needs OTP 27 or later` | Raise the OTP version in `.tool-versions` or pass `otp-version` |
| `Workload Identity needs rebar3 3.27.1 or later`. On v2.3.0: `Uncaught error in rebar_core` right after the Code of Conduct lines | rebar3 before 3.27.1 has no Workload Identity support. Raise `rebar` in `.tool-versions` or pass `rebar3-version` |
| `rebar3 computes version ... which does not match` | `vsn` is not `"git"`, or a newer tag exists than the one being published |
| `is staged on hex.pm and is not in the registry` | Staged publishing is on. Approve the release on hex.pm, or turn the setting off |
| Publishing fails because the package does not exist | The first release has to be published by hand |

## Examples

### Simple library

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
```

### Library with OTP version matrix

Tests run on all OTP versions. Dialyzer, xref, and fmt run on the primary version only.

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      otp-matrix: '["27", "28"]'
```

### Web application with PostgreSQL

When `postgres: true` is set, eunit, CT, and mutation testing jobs get a PostgreSQL service container with built-in health checks (the job waits until PostgreSQL is ready). PG connection details are available as environment variables (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`).

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-ct: true
      postgres: true
      postgres-version: '17'
      postgres-db: 'myapp_test'
```

### Application with Kafka

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-ct: true
      kafka: true
```

Kafka runs in KRaft mode (no ZooKeeper) with built-in health checks. It is available at `localhost:9092`. The environment variables `KAFKA_HOST` and `KAFKA_PORT` are set for test configuration.

### Application with PostgreSQL and Kafka

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-ct: true
      postgres: true
      kafka: true
```

### Library with mutation testing

Mutation testing verifies your tests can detect real bugs by introducing small code changes (mutants) and checking that tests catch them. On PRs, only changed code is mutated via `--diff`.

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-mutate: true
      mutate-min-score: '80'
```

Set `mutate-min-score` to fail the build if the mutation score drops below a threshold. Use `mutate-test-framework: ct` if your tests are Common Test suites.

### Full pipeline with everything enabled

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    permissions:
      contents: write
      pull-requests: write
    secrets: inherit
    with:
      otp-version: '28'
      otp-matrix: '["27", "28"]'
      enable-ct: true
      enable-ex-doc: true
      enable-audit: true
      enable-lint: true
      enable-hank: true
      enable-sheldon: true
      enable-coverage: true
      enable-sbom: true
      enable-sbom-scan: true
      enable-dependency-submission: true
      enable-mutate: true
      mutate-min-score: '80'
      postgres: true

  release:
    needs: ci
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.0.0
    permissions:
      contents: write
    secrets: inherit
```

**Required rebar.config plugins for the full pipeline:**

```erlang
{project_plugins, [
    erlfmt,
    rebar3_ex_doc,
    rebar3_lint,
    rebar3_hank,
    rebar3_sheldon,
    rebar3_audit,
    covertool,
    rebar3_sbom,
    rebar3_mutate
]}.

{cover_enabled, true}.
```

### Enterprise application with private deps, custom services, and pre-test setup

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    permissions:
      contents: write
      pull-requests: write
    secrets:
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
      hex-api-key: ${{ secrets.HEX_API_KEY }}
    with:
      otp-version: '28'
      enable-ct: true
      enable-audit: true
      enable-coverage: true
      enable-sbom: true
      enable-sbom-scan: true
      postgres: true
      postgres-db: 'myapp_test'
      kafka: true
      extra-services-compose: docker-compose.test.yml
      pre-test-command: |
        rebar3 kura migrate
        ./scripts/create_kafka_topics.sh
```

Services (PostgreSQL, Kafka) use native GitHub Actions service containers with built-in health checks — the job won't start until all services are healthy. The `extra-services-compose` input is the escape hatch for additional services (authz-mock, fake-gcs-server, etc.) that aren't built in.

### Auto-detect .tool-versions

If your project has a `.tool-versions` file, it will be used automatically — no configuration needed:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
```

You can also point to a specific file explicitly:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      version-file: 'mise.toml'
```

### Standalone composite actions

Individual tools are available as composite actions. Each assumes you've already run the setup action. Use them to build custom pipelines without the full reusable workflow.

| Action | Description |
|--------|-------------|
| `Taure/erlang-ci` | Setup: OTP, rebar3, caching |
| `Taure/erlang-ci/dialyzer` | PLT caching + `rebar3 dialyzer` |
| `Taure/erlang-ci/elp` | ELP install + lint and/or eqWAlize |
| `Taure/erlang-ci/audit` | `rebar3 audit` with JSON output |
| `Taure/erlang-ci/sbom` | CycloneDX SBOM + Trivy vulnerability scan |
| `Taure/erlang-ci/mutate` | Mutation testing with `rebar3 mutate` |

**Example: dialyzer + ELP in a custom workflow**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v2.0.0
    with:
      otp-version: '28'
  - run: rebar3 compile
  - uses: Taure/erlang-ci/dialyzer@v2.0.0
    with:
      otp-version: '28'
  - uses: Taure/erlang-ci/elp@v2.0.0
    with:
      mode: both
```

**Example: audit + SBOM scan**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v2.0.0
    with:
      otp-version: '28'
  - run: rebar3 compile
  - uses: Taure/erlang-ci/audit@v2.0.0
    id: audit
    with:
      level: high
  - uses: Taure/erlang-ci/sbom@v2.0.0
    with:
      scan: 'true'
      github-token: ${{ github.token }}
```

Each action exposes structured JSON outputs for integration with custom reporting.

### Standalone setup action

If you prefer writing your own workflow but want the setup and caching handled:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v2.0.0
    with:
      otp-version: '28'
  - run: rebar3 compile
  - run: rebar3 eunit
```

The setup action handles:
- Installing Erlang/OTP and rebar3 via [erlef/setup-beam](https://github.com/erlef/setup-beam)
- Caching `~/.cache/rebar3` (hex packages, plugins)
- Caching `_build` (compiled dependencies), keyed on the resolved OTP version, `rebar.config` and `rebar.lock`. A cache built on another OTP version is never restored.

Plugins, and git deps that track a branch without a `rebar.lock` pin (deps in a profile other than default, or any dep in a repo with no lock), are dropped from the restored `_build` so rebar3 fetches them fresh. Pin them to a tag or ref to keep builds reproducible.

## Extending with custom jobs

Reusable workflows run as complete jobs — you cannot inject steps into them. Instead, add your own jobs **alongside** the reusable workflow and use `needs:` to control execution order.

### How `needs:` chaining works

Every job in a workflow file runs in parallel by default. Adding `needs: job_name` makes a job wait until `job_name` completes successfully. This is how you build a pipeline:

```
ci ──► black-box ──► release
```

```yaml
jobs:
  ci:                              # 1. runs first (no needs)
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'

  black-box:                       # 2. runs after ci passes
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v2.0.0
        with:
          otp-version: '28'
      - run: rebar3 release
      - run: ./scripts/black_box_tests.sh

  release:                         # 3. runs after black-box passes, only on merge
    needs: black-box
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.0.0
    permissions:
      contents: write
```

You can require multiple jobs with a list — the job waits for all of them:

```
       ┌─ ci ──────────┐
start ─┤               ├─► deploy
       └─ security ────┘
```

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'

  security:                        # runs in parallel with ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: company/security-scanner@v2

  deploy:                          # waits for both ci AND security
    needs: [ci, security]
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: company/deploy-action@v1
```

### Full example: CI → black-box → deploy → release

```
ci ──► black-box ──► deploy-staging ──► release
```

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    permissions:
      contents: write
      pull-requests: write
    with:
      otp-version: '28'
      enable-ct: true
      enable-audit: true
      postgres: true

  black-box:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v2.0.0
        with:
          otp-version: '28'
      - run: rebar3 release
      - run: ./scripts/black_box_tests.sh

  deploy-staging:
    needs: black-box
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: company/deploy-action@v1
        with:
          environment: staging

  release:
    needs: deploy-staging
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v2.0.0
    permissions:
      contents: write
```

### Company-internal reusable workflow wrapping erlang-ci

For organizations that want to enforce additional steps across all repos, create an internal wrapper workflow. Reusable workflows can nest up to 10 levels deep.

```yaml
# company/.github/workflows/erlang-ci.yml
name: Company Erlang CI

on:
  workflow_call:
    inputs:
      otp-version:
        type: string
        default: '28'
      enable-ct:
        type: boolean
        default: false
      postgres:
        type: boolean
        default: false
      pre-test-command:
        type: string
        default: ''
      extra-services-compose:
        type: string
        default: ''

jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    permissions:
      contents: write
      pull-requests: write
    secrets: inherit  # passes ssh-key, hex-api-key from caller
    with:
      otp-version: ${{ inputs.otp-version }}
      enable-ct: ${{ inputs.enable-ct }}
      enable-audit: true
      enable-dependency-submission: true
      postgres: ${{ inputs.postgres }}
      pre-test-command: ${{ inputs.pre-test-command }}
      extra-services-compose: ${{ inputs.extra-services-compose }}

  compliance:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: company/license-checker@v1
      - uses: company/sbom-attestation@v1
```

Individual repos then call the company wrapper with minimal config:

```yaml
jobs:
  ci:
    uses: company/.github/workflows/erlang-ci.yml@v1
    secrets: inherit
    with:
      otp-version: '28'
      enable-ct: true
      postgres: true
      pre-test-command: |
        rebar3 kura migrate
```

### Using the composite action for full control

When the reusable workflow is too opinionated, use the composite action directly and build your own pipeline:

```yaml
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v2.0.0
        with:
          otp-version: '28'
      - run: rebar3 compile
      - run: rebar3 fmt --check
      - run: rebar3 xref
      - run: rebar3 eunit
      # Add whatever custom steps you need
      - run: ./scripts/custom_checks.sh
      - uses: company/notify-slack@v1
        if: failure()
```

### Choosing the right approach

| Approach | When to use |
|----------|-------------|
| **Reusable workflow only** | Standard Erlang library, no custom steps needed |
| **Reusable workflow + extra jobs** | Need to add steps before/after the standard pipeline |
| **Company wrapper workflow** | Enforce org-wide policies across all repos |
| **Composite action only** | Need full control over job structure and step order |

## Inputs reference

### Versions

| Input | Default | Description |
|-------|---------|-------------|
| `otp-version` | `28` | Erlang/OTP version |
| `rebar3-version` | `3` | Rebar3 version |
| `version-file` | — | Read versions from `.tool-versions` or `mise.toml` |
| `version-type` | — | Version match type (`strict` or `loose`). Defaults to `strict` when `version-file` is set |
| `otp-matrix` | — | JSON array of OTP versions for matrix testing (e.g. `'["27","28"]'`). When empty, eunit and ct run on the `version-file` OTP if set, else `otp-version` |

### Steps

| Input | Default | Description |
|-------|---------|-------------|
| `enable-fmt` | `true` | Run `rebar3 fmt --check` |
| `enable-xref` | `true` | Run `rebar3 xref` |
| `enable-dialyzer` | `true` | Run `rebar3 dialyzer` (with PLT caching) |
| `enable-eunit` | `true` | Run `rebar3 eunit` |
| `enable-ct` | `false` | Run `rebar3 ct` |
| `enable-ex-doc` | `false` | Run `rebar3 ex_doc` |
| `enable-audit` | `false` | Run `rebar3 audit` (dep vulnerability scanning) |
| `audit-level` | `low` | Minimum severity to fail on (`critical`, `high`, `medium`, `low`) |
| `audit-ignores` | — | GHSA IDs to skip (space- or comma-separated). For unpatched advisories that do not apply; document each in SECURITY.md. |
| `enable-coverage` | `false` | Coverage via covertool (reported in PR summary) |
| `enable-sbom` | `false` | Generate CycloneDX SBOM via `rebar3 sbom` |
| `enable-sbom-scan` | `false` | Scan SBOM for vulnerabilities using Trivy (requires `enable-sbom`) |
| `enable-dependency-submission` | `false` | Submit deps to GitHub Dependency Graph |
| `enable-mutate` | `false` | Run mutation testing via `rebar3 mutate` |
| `mutate-min-score` | — | Minimum mutation score (0-100), fail if below |
| `mutate-test-framework` | `eunit` | Test framework for mutation testing (`eunit` or `ct`) |
| `mutate-args` | — | Extra args for `rebar3 mutate` |
| `enable-summary` | `true` | Post CI summary comment on PRs (coverage, audit, SBOM scan results) |

### Custom setup

| Input | Default | Description |
|-------|---------|-------------|
| `pre-test-command` | — | Shell command to run before tests (e.g., DB migrations, Kafka topic creation) |
| `extra-services-compose` | — | Path to `docker-compose.yml` for additional services |

`pre-test-command` runs in eunit, CT, and mutation testing jobs after services are started:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-ct: true
      postgres: true
      pre-test-command: |
        rebar3 kura migrate
        ./scripts/create_kafka_topics.sh
```

`extra-services-compose` starts additional Docker services alongside the built-in ones:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    with:
      otp-version: '28'
      enable-ct: true
      extra-services-compose: docker-compose.test.yml
```

### Caching (composite action only)

| Input | Default | Description |
|-------|---------|-------------|
| `cache-key-prefix` | `erlang-ci` | Custom cache key prefix for cache isolation |

### PostgreSQL

| Input | Default | Description |
|-------|---------|-------------|
| `postgres` | `false` | Enable PostgreSQL service for eunit and CT |
| `postgres-version` | `17` | PostgreSQL Docker image version |
| `postgres-db` | `test_db` | Database name |
| `postgres-user` | `postgres` | Username |
| `postgres-password` | `postgres` | Password |
| `postgres-port` | `5432` | Host port |

### Kafka

| Input | Default | Description |
|-------|---------|-------------|
| `kafka` | `false` | Enable Kafka service for eunit and CT |
| `kafka-version` | `3.9` | Apache Kafka Docker image version |
| `kafka-port` | `9092` | Broker port |

### Test configuration

| Input | Default | Description |
|-------|---------|-------------|
| `ct-config` | — | Path to CT sys.config file |
| `ct-args` | — | Extra args for `rebar3 ct` |
| `eunit-args` | — | Extra args for `rebar3 eunit` (e.g. `--module=foo_tests`) |
| `rebar3-compile-args` | — | Extra args for `rebar3 compile` |

### Secrets (reusable workflow)

| Secret | Description |
|--------|-------------|
| `ssh-key` | SSH private key for accessing private git dependencies |
| `hex-api-key` | Hex.pm API key for accessing private packages |

For projects with private rebar3 deps (`{dep, {git, "git@github.com:org/repo.git", ...}}`), pass an SSH key so `rebar3 compile` can fetch them:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    secrets:
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
    with:
      otp-version: '28'
```

The composite action accepts `ssh-key` as an input:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v2.0.0
    with:
      otp-version: '28'
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
  - run: rebar3 compile
```

For private Hex packages, pass `hex-api-key`:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    secrets:
      hex-api-key: ${{ secrets.HEX_API_KEY }}
    with:
      otp-version: '28'
```

Both secrets can be combined:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
    secrets:
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
      hex-api-key: ${{ secrets.HEX_API_KEY }}
    with:
      otp-version: '28'
```

## PR summary comment

When `enable-summary` is enabled and any reporting feature is active (`enable-coverage`, `enable-audit`, or `enable-sbom-scan`), a single unified comment is posted on PRs with all results. The comment is updated on re-runs (never duplicated).

Requires `pull-requests: write` permission on the caller's `ci` job.

### Coverage (`enable-coverage`)

> ### 🟢 Code Coverage — 87.3%
> 1042 of 1193 lines covered.

The badge color reflects coverage level: green (90%+), yellow (70%+), orange (50%+), red (below 50%).

With an `otp-matrix`, the coverdata from every OTP leg is merged, so a line counts as covered if any leg ran it.

### Security Audit (`enable-audit`)

**Clean scan:**

> ### 🛡️ Security Audit
> No vulnerabilities found in 5 dependencies.

**Vulnerabilities found:**

> ### 🚨 Security Audit — 2 vulnerabilities found
>
> | Severity | Package | Version | Advisory | Fix |
> |:---:|---|---|---|---|
> | 🔴 Critical | **pgo** | `0.14.0` | GHSA-xxxx (CVE-2025-0001) | Upgrade to `0.15.0` |
> | 🟡 Medium | **cowlib** | `2.12.0` | GHSA-yyyy | No fix available |

Each vulnerability includes an expandable details section with the full description and vulnerable version range.

The `audit-level` input controls the minimum severity that causes the job to fail (default: `low` — all vulnerabilities fail the build). Set to `high` or `critical` to allow lower-severity issues to pass.

The `audit-ignores` input lists GHSA IDs to skip. Use it sparingly, only for advisories that have no upstream patch and that genuinely do not apply to your code (e.g. a vulnerable function your project never calls). Each entry should be documented in `SECURITY.md` or an audit report with the justification.

```yaml
with:
  enable-audit: true
  audit-ignores: 'GHSA-g2wm-735q-3f56 GHSA-xxxx-yyyy-zzzz'
```

### SBOM Scan (`enable-sbom-scan`)

**Clean scan:**

> ### 📦 SBOM Scan
> No vulnerabilities found.

**Vulnerabilities found:**

> ### 📦 SBOM Scan — 1 vulnerability found
>
> | Severity | Package | Version | Vulnerability | Fix |
> |:---:|---|---|---|---|
> | 🔴 Critical | **pgo** | `0.14.0` | CVE-2025-9999 | Upgrade to `0.15.0` |

SBOM scan uses [Trivy](https://github.com/aquasecurity/trivy) against a CycloneDX SBOM generated by `rebar3 sbom`. The `trivy-action` is pinned by SHA to mitigate supply chain attacks (see [trivy-action incident, March 2026](https://github.com/aquasecurity/trivy/discussions/10425)). The build fails on `high` or `critical` severity vulnerabilities. Duplicate matches (same CVE + package from multiple data sources) are deduplicated automatically.

When both audit and SBOM scan are enabled, both sections appear in the same PR comment separated by a divider.

### Mutation Testing (`enable-mutate`)

**All mutants caught:**

> ### 🟢 Mutation Testing — 100%
> 12 mutants tested. 12 killed.

**Some mutants survived:**

> ### 🟡 Mutation Testing — 75.0%
> 20 mutants tested. 15 killed, 4 survived, 1 timed out.

The badge color reflects mutation score: green (80%+), yellow (60%+), orange (40%+), red (below 40%).

On PRs, only code changed in the PR is mutated (`--diff`). Set `mutate-min-score` to enforce a quality gate — the job fails if the score drops below the threshold.

## Templates

### Migration rollback testing

A Common Test suite template for testing Kura migration rollbacks is available at [`templates/migration_rollback_SUITE.erl`](templates/migration_rollback_SUITE.erl). It rolls back every migration one by one, verifies a clean state, then re-applies all migrations.

### cliff.toml

A default git-cliff config for conventional commits is available at [`cliff.toml`](cliff.toml). Copy it to your project root to use with the release workflow.

## Real-world usage

These projects use erlang-ci:

| Project | Config |
|---------|--------|
| [Nova](https://github.com/novaframework/nova) | OTP matrix 26/27/28, fmt, + nova_request_app integration |
| [Kura](https://github.com/Taure/kura) | PostgreSQL, CT, eunit, ex_doc, audit, coverage, SBOM, dependency submission, auto-release |
| [rebar3_fly](https://github.com/Taure/rebar3_fly) | OTP matrix 27/28, ex_doc |
| [rebar3_kura](https://github.com/Taure/rebar3_kura) | OTP matrix 27/28 |
| [rebar3_audit](https://github.com/Taure/rebar3_audit) | Standard + custom dogfood job |

## What this replaces

Instead of copying 50-120 lines of boilerplate YAML into every Erlang project:

```yaml
# before: setup-beam, cache config, compile, fmt, xref, dialyzer, eunit...
# repeated in every repo, drifting apart over time

# after:
uses: Taure/erlang-ci/.github/workflows/ci.yml@v2.0.0
with:
  otp-version: '28'
```

## Security

- All `v*` release tags are **immutable** — protected by repository rulesets that prevent deletion and force-push
- No floating major tags (`@v1`, `@v2`) — pin to exact semver versions
- All third-party action references are SHA-pinned
- `hex-publish.yml` takes no secrets, restores no cache and requests `contents: read` and `id-token: write` only
- Workflows are scanned by [zizmor](https://docs.zizmor.sh/) and [actionlint](https://github.com/rhysd/actionlint) on every PR

## License

Apache-2.0
