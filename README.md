# erlang-ci

A standardized CI pipeline for Erlang/OTP projects.

**Two ways to use it:**

1. **Reusable workflow** — a complete CI pipeline with parallel jobs
2. **Composite action** — just setup + caching, bring your own jobs

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

## Pipeline

After compile, all enabled steps run in parallel:

```
                    ┌─ fmt ──────────┐
                    ├─ xref ─────────┤
compile ──────────► ├─ dialyzer ─────┤
                    ├─ eunit ────────┤
                    ├─ ct ───────────┤
                    ├─ ex-doc ───────┤
                    └─ audit ────────┘
```

| Step | Default | Input |
|------|---------|-------|
| Compile | always | — |
| Format (`rebar3 fmt --check`) | **on** | `enable-fmt` |
| Xref | **on** | `enable-xref` |
| Dialyzer | **on** | `enable-dialyzer` |
| EUnit | **on** | `enable-eunit` |
| Common Test | off | `enable-ct` |
| ExDoc | off | `enable-ex-doc` |
| Audit | off | `enable-audit` |
| Coverage | off | `enable-coverage` |

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

### Full pipeline with coverage

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
      otp-matrix: '["27", "28"]'
      enable-ct: true
      enable-ex-doc: true
      enable-audit: true
      enable-coverage: true
      postgres: true
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

### Mix with custom jobs

Use the reusable workflow for the standard pipeline, then add custom jobs alongside:

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'

  integration:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Taure/erlang-ci@v1
        with:
          otp-version: '28'
      - run: rebar3 compile
      - run: ./scripts/integration_test.sh
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

## Inputs reference

### Versions

| Input | Default | Description |
|-------|---------|-------------|
| `otp-version` | `28` | Erlang/OTP version |
| `rebar3-version` | `3` | Rebar3 version |
| `version-file` | — | Read versions from `.tool-versions` or `mise.toml` |
| `otp-matrix` | — | JSON array of OTP versions for matrix testing (e.g. `'["27","28"]'`) |

### PostgreSQL

| Input | Default | Description |
|-------|---------|-------------|
| `postgres` | `false` | Enable PostgreSQL service for eunit and CT |
| `postgres-version` | `17` | PostgreSQL Docker image version |
| `postgres-db` | `test_db` | Database name |
| `postgres-user` | `postgres` | Username |
| `postgres-password` | `postgres` | Password |
| `postgres-port` | `5432` | Host port |

### Other

| Input | Default | Description |
|-------|---------|-------------|
| `ct-config` | — | Path to CT sys.config file |
| `rebar3-compile-args` | — | Extra args for `rebar3 compile` |

## Real-world usage

These projects use erlang-ci:

| Project | Config |
|---------|--------|
| [Nova](https://github.com/novaframework/nova) | OTP matrix 26/27/28, fmt, + nova_request_app integration |
| [Kura](https://github.com/Taure/kura) | PostgreSQL, CT, eunit, ex_doc, + release job |
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
