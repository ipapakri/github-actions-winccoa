# WinCC OA CTL Style Check

Thin GitHub Action wrapper around the public npm package
[`@winccoa-tools-pack/npm-winccoa-ctrl-code-style`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-ctrl-code-style).

Uses the **worker + StyleCheck** model:

1. Register bundled **StyleCheck** as a non-runnable sub-project
2. Register the **worker / source project** as runnable with StyleCheck attached
3. Run `WCCOActrl -config <worker>/config/config ... astyle.ctl <source>`

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
| `path` | No | `.` | Runnable worker project root relative to repo root |
| `source-path` | No | empty | Optional CTL tree to scan (`-s`); defaults to `path` |
| `command` | No | `check` | `check` (dry-run) or `format` (in place) |
| `fail-on-error` | No | `true` | Fail the job when style operation fails |
| `winccoa-version` | Yes | - | Installed WinCC OA version such as `3.21` |
| `languages` | No | `en_US.utf8` | Locales for worker registration |
| `docker-image` | No | empty | Optional WinCC OA container image |
| `register-project` | No | `true` | Let the package register StyleCheck + worker |
| `timeout-ms` | No | `120000` | WCCOActrl timeout in milliseconds |
| `package-version` | No | `0.1.1` | npm version/dist-tag for ctrl-code-style |
| `log-path` | No | `.artifacts/style-check.log` | Captured log path |
| `node-version` | No | `22` | Node major when bootstrapping Node |

## Outputs

| Output | Description |
| --- | --- |
| `exit-code` | Style CLI exit code |
| `log-path` | Absolute path to the captured style log |

## Example

```yaml
name: WinCC OA CTL Style Check

on:
  push:
  pull_request:

jobs:
  style:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
      pull-requests: write
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

      - id: style
        continue-on-error: true
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-style-check@main
        with:
          path: src/Squirt
          source-path: src/Squirt/scripts
          winccoa-version: '3.21'
          docker-image: ${{ env.WINCCOA_IMAGE }}
          command: check
          languages: |
            en_US.utf8
          fail-on-error: 'true'
          package-version: '0.1.1'
          log-path: .artifacts/style-check.log

      - if: always() && github.event_name == 'pull_request'
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-logs-to-pr-review@main
        with:
          log-path: ${{ steps.style.outputs.log-path }}
          title: CTL style check report
          comment-marker: '<!-- winccoa-style-check-report -->'
          include-error-types: CTRL
          review-comments: 'true'

      - if: steps.style.outcome == 'failure'
        run: exit 1
```

## Notes

- This action installs and runs the public npm CLI; it does not duplicate package logic
- Never pin npm packages to git branch names such as `@main`
- Registration and CTRL run in the **same** host/container so `pvssInst.conf` is shared
- StyleCheck is non-runnable and ships scripts only; logs stay on the worker project
- Full WCCOActrl output is written to `log-path` for `winccoa-logs-to-pr-review`
- Shell logic lives in `scripts/` (`run.sh`, `run-in-container.sh`, `lib.sh`)

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
