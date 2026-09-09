# syntax-check

Runs WinCC OA syntax validation.

## Runtime and compatibility

- This action supports Linux runners only.
- The current test baseline is Debian-based Docker images with WinCC OA 3.21.
- It is expected to work with WinCC OA 3.21 patch versions.
- It should also work with WinCC OA 3.22.
- Legacy WinCC OA 3.20 and 3.19 may work, but this is not guaranteed and should be validated in your environment.
 - Node.js and `npm` must be available in the runner or container. The action will not install Node.js; ensure the workflow config (or container image) provides the desired Node.js version.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `path` | No | `.` | Project root relative to the repository root |
| `fail-on-error` | No | `true` | Fails the job when the checker returns an error |
| `winccoa-version` | No | empty | Installed WinCC OA version such as `3.21`. Optional; if omitted the workflow must provide a runner/container with WinCC OA installed |
| `languages` | No | `en_US.utf8` | Newline-separated list of locales to include in generated config (one per line). Default is `en_US.utf8` |
| `register-project` | No | `true` | When `true` the action will invoke the local `winccoa-register-project` action prior to running the syntax check. Workflows may instead call `uses: ./actions/winccoa-register-project` in a prior step |
| `config` | No | empty | Path to project config file relative to the repo root. If empty defaults to `<path>/config/config` |
| `mode` | No | `all` | `all`, `scripts`, or `panels` |
| `integrity` | No | `false` | Enables integrity checks |
| `timeout-ms` | No | `60000` | Validation timeout in milliseconds |
| `node-version` | No | `20.17.0` | Node.js version to install when node/npm are missing in the image |

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

    steps:
      - uses: actions/checkout@v4

      - name: Run syntax check
        uses: winccoa-tools-pack/github-actions-winccoa/actions/syntax-check@v1
        with:
          path: .
          winccoa-version: '3.21'
          languages: |
            en_US.utf8
          fail-on-error: 'true'

      # Note: This action does not allocate or manage Docker images.
      # Provide a runner or a container that has WinCC OA installed, or
      # call `uses: ./actions/winccoa-register-project` in a prior step
      # to prepare the project in an environment that contains WinCC OA.
```
