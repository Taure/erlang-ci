# erlang-ci

A standardized CI pipeline for Erlang/OTP projects.

Provides two things:

1. **Reusable workflow** — a complete CI pipeline with parallel jobs for compile, format, xref, dialyzer, eunit, common test, and more
2. **Composite action** — setup Erlang/OTP + rebar3 with build caching (used internally, also available standalone)

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

That's it. This runs: **compile → fmt → xref → dialyzer → eunit** in parallel after compile.

## Examples

### Library with OTP matrix

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
      otp-matrix: '["27", "28"]'
```

Tests run on all OTP versions. Dialyzer, xref, and fmt run on the primary version only.

### Web application with PostgreSQL

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      otp-version: '28'
      enable-ct: true
      postgres: true
      postgres-version: '17'
```

### Full pipeline

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

### Read versions from .tool-versions

```yaml
jobs:
  ci:
    uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
    with:
      version-file: '.tool-versions'
```

### Standalone setup action

If you prefer writing your own workflow but want the setup+caching handled:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: Taure/erlang-ci@v1
    with:
      otp-version: '28'
  - run: rebar3 compile
  - run: rebar3 eunit
```

## Pipeline steps

All steps after compile run in **parallel**:

| Step | Default | Input |
|------|---------|-------|
| Compile | always | — |
| Format check | on | `enable-fmt` |
| Xref | on | `enable-xref` |
| Dialyzer | on | `enable-dialyzer` |
| EUnit | on | `enable-eunit` |
| Common Test | off | `enable-ct` |
| ExDoc | off | `enable-ex-doc` |
| Audit | off | `enable-audit` |
| Coverage | off | `enable-coverage` |

## Inputs reference

### Versions

| Input | Default | Description |
|-------|---------|-------------|
| `otp-version` | `28` | Erlang/OTP version |
| `rebar3-version` | `3` | Rebar3 version |
| `version-file` | — | Read versions from `.tool-versions` or `mise.toml` |
| `otp-matrix` | — | JSON array of OTP versions for matrix testing |

### PostgreSQL

| Input | Default | Description |
|-------|---------|-------------|
| `postgres` | `false` | Enable PostgreSQL service |
| `postgres-version` | `17` | PostgreSQL version |
| `postgres-db` | `test_db` | Database name |
| `postgres-user` | `postgres` | Username |
| `postgres-password` | `postgres` | Password |
| `postgres-port` | `5432` | Port |

### Other

| Input | Default | Description |
|-------|---------|-------------|
| `ct-config` | — | Path to CT sys.config file |
| `rebar3-compile-args` | — | Extra args for rebar3 compile |

## What this replaces

Instead of copying ~50 lines of YAML into every Erlang project, you get:

```yaml
# before: 50+ lines of setup, caching, steps, matrix config
# after:
uses: Taure/erlang-ci/.github/workflows/ci.yml@v1
with:
  otp-version: '28'
```

## License

Apache-2.0
