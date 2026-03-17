# erlang-ci

A standardized CI/CD pipeline for Erlang/OTP projects.

**Three ways to use it:**

1. **Reusable CI workflow** — a complete CI pipeline with parallel jobs
2. **Reusable release workflow** — auto-tag and release from conventional commits
3. **Composite action** — just setup + caching, bring your own jobs

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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'

  release:
    needs: ci
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v1
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

## Examples

### Simple library

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
```

### Library with OTP version matrix

Tests run on all OTP versions. Dialyzer, xref, and fmt run on the primary version only.

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
      otp-matrix: '["27", "28"]'
```

### Web application with PostgreSQL

When `postgres: true` is set, both eunit and CT jobs get a PostgreSQL service container. PG connection details are available as environment variables (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`).

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
      enable-ct: true
      kafka: true
```

Kafka is available at `localhost:9092`. The environment variables `KAFKA_HOST` and `KAFKA_PORT` are set for test configuration.

### Application with PostgreSQL and Kafka

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    permissions:
      contents: write
      pull-requests: write
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
    uses: Taure/erlang-ci/.github/workflows/release.yml@v1
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

### Auto-detect .tool-versions

If your project has a `.tool-versions` file, it will be used automatically — no configuration needed:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
```

You can also point to a specific file explicitly:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      version-file: 'mise.toml'
```

### Standalone setup action

If you prefer writing your own workflow but want the setup and caching handled:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v1
    with:
      otp-version: '28'
  - run: rebar3 compile
  - run: rebar3 eunit
```

The composite action handles:
- Installing Erlang/OTP and rebar3 via [erlef/setup-beam](https://github.com/erlef/setup-beam)
- Caching `~/.cache/rebar3` (hex packages, plugins)
- Caching `_build` (compiled dependencies)

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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'

  black-box:                       # 2. runs after ci passes
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v1
        with:
          otp-version: '28'
      - run: rebar3 release
      - run: ./scripts/black_box_tests.sh

  release:                         # 3. runs after black-box passes, only on merge
    needs: black-box
    if: github.event_name == 'push'
    uses: Taure/erlang-ci/.github/workflows/release.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
      - uses: Taure/erlang-ci@v1
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
    uses: Taure/erlang-ci/.github/workflows/release.yml@v1
    permissions:
      contents: write
```

### Company-internal reusable workflow wrapping erlang-ci

For organizations that want to enforce additional steps across all repos, create an internal wrapper workflow:

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

jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    permissions:
      contents: write
      pull-requests: write
    with:
      otp-version: ${{ inputs.otp-version }}
      enable-ct: ${{ inputs.enable-ct }}
      enable-audit: true
      enable-dependency-submission: true

  compliance:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: company/license-checker@v1
      - uses: company/sbom-attestation@v1

  black-box:
    needs: ci
    runs-on: ubuntu-latest
    services:
      app:
        image: ${{ needs.ci.outputs.image }}  # if you build a container
    steps:
      - uses: company/black-box-tests@v1
```

Individual repos then call the company wrapper with minimal config:

```yaml
jobs:
  ci:
    uses: company/.github/workflows/erlang-ci.yml@v1
    with:
      otp-version: '28'
```

### Using the composite action for full control

When the reusable workflow is too opinionated, use the composite action directly and build your own pipeline:

```yaml
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v1
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
| `otp-matrix` | — | JSON array of OTP versions for matrix testing (e.g. `'["27","28"]'`) |

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
| `enable-coverage` | `false` | Coverage via covertool (reported in PR summary) |
| `enable-sbom` | `false` | Generate CycloneDX SBOM via `rebar3 sbom` |
| `enable-sbom-scan` | `false` | Scan SBOM for vulnerabilities using Grype (requires `enable-sbom`) |
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
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

For projects with private rebar3 deps (`{dep, {git, "git@github.com:org/repo.git", ...}}`), pass an SSH key so `rebar3 compile` can fetch them:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    secrets:
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
    with:
      otp-version: '28'
```

The composite action accepts `ssh-key` as an input:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v1
    with:
      otp-version: '28'
      ssh-key: ${{ secrets.PRIVATE_DEPS_SSH_KEY }}
  - run: rebar3 compile
```

## PR summary comment

When `enable-summary` is enabled and any reporting feature is active (`enable-coverage`, `enable-audit`, or `enable-sbom-scan`), a single unified comment is posted on PRs with all results. The comment is updated on re-runs (never duplicated).

Requires `pull-requests: write` permission on the caller's `ci` job.

### Coverage (`enable-coverage`)

> ### 🟢 Code Coverage — 87.3%
> 1042 of 1193 lines covered.

The badge color reflects coverage level: green (90%+), yellow (70%+), orange (50%+), red (below 50%).

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

SBOM scan uses [Grype](https://github.com/anchore/grype) against a CycloneDX SBOM generated by `rebar3 sbom`. The build fails on `high` or `critical` severity vulnerabilities. Duplicate matches (same CVE + package from multiple data sources) are deduplicated automatically.

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
uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
with:
  otp-version: '28'
```

## License

Apache-2.0
