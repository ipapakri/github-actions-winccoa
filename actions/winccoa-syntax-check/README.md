# WinCC OA Syntax Check

Thin GitHub Action wrapper around the public npm package
[`@winccoa-tools-pack/npm-winccoa-syntax-check`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-syntax-check).

Optionally registers the project first via
`winccoa-register-project` (also a thin npm wrapper).

## Runtime and compatibility

- Linux runners only
- Baseline: Debian-based Docker images with WinCC OA 3.21
- Expected to work with WinCC OA 3.21 patch versions and 3.22
- Provide either:
  - `docker-image` (recommended on GitHub-hosted runners), or
  - a job container / host that already has WinCC OA installed

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `path` | No | `.` | Project root relative to the repository root |
| `fail-on-error` | No | `true` | Fail the job when syntax check fails |
| `winccoa-version` | Yes | - | Installed WinCC OA version such as `3.21` |
| `languages` | No | `en_US.utf8` | Locales for generated config when `register-project` is true |
| `docker-image` | No | empty | Optional WinCC OA container image |
| `register-project` | No | `true` | Create/register project config before the check |
| `mode` | No | `all` | `all`, `scripts`, or `panels` |
| `integrity` | No | `false` | Enables integrity checks |
| `timeout-ms` | No | `60000` | Validation timeout in milliseconds |
| `scripts-path` | No | empty | Optional scripts start path (`-s`) |
| `panels-path` | No | empty | Optional panels start path (`-p`) |
| `register-package-version` | No | `1.1.1` | npm version for register-project package |
| `package-version` | No | `0.1.0` | npm version/dist-tag for syntax-check package |
| `node-version` | No | `22` | Node major used when bootstrapping Node |

## Outputs

| Output | Description |
| --- | --- |
| `error-count` | Best-effort parsed number of reported errors |

## Example

```yaml
name: WinCC OA Syntax Check

on:
  push:
  pull_request:

jobs:
  syntax:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    env:
      WINCCOA_IMAGE: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - run: docker pull "$WINCCOA_IMAGE"

      - uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-syntax-check@main
        with:
          path: src/Squirt
          winccoa-version: '3.21'
          docker-image: ${{ env.WINCCOA_IMAGE }}
          languages: |
            en_US.utf8
          fail-on-error: 'true'
          package-version: '0.1.0'
```

## Notes

- This action installs and runs the public npm CLI; it does not duplicate package logic
- Never pin npm packages to git branch names such as `@main`
- When `register-project: true`, it calls `winccoa-register-project` first
- Shell logic lives in `scripts/` (`run.sh`, `run-in-container.sh`, `lib.sh`) so
  `action.yml` stays valid YAML

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
