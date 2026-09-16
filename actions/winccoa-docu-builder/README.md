# WinCC OA Docu Builder

Thin GitHub Action wrapper around the public npm package
[`@winccoa-tools-pack/npm-winccoa-docu-builder`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-docu-builder).

Uses the **worker + DocuBuilder** model:

1. Register bundled **DocuBuilder** as a non-runnable sub-project
2. Register the **worker / source project** as runnable with DocuBuilder attached
3. Run `WCCOActrl -config <worker>/config/config ... buildHelp.ctl <CompanyName>`
4. Extract doxygen warnings, emit PR annotations, optionally enforce a max count

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
| `company-name` | No | empty | Company label; defaults to org/repo name |
| `fail-on-error` | No | `true` | Fail the job when docs build fails |
| `winccoa-version` | Yes | - | Installed WinCC OA version such as `3.21` |
| `languages` | No | `en_US.utf8` | Locales for worker registration |
| `docker-image` | No | empty | Optional WinCC OA container image |
| `register-project` | No | `true` | Let the package register DocuBuilder + worker |
| `timeout-ms` | No | `600000` | WCCOActrl timeout in milliseconds |
| `package-version` | No | `0.1.0` | npm version/dist-tag, or `github:owner/repo#ref` bootstrap spec |
| `log-path` | No | `.artifacts/docu-builder.log` | Captured log path |
| `warning-output-file` | No | `.artifacts/doxygen-warnings.txt` | Extracted warnings file |
| `annotate-warnings` | No | `true` | Emit GitHub warning annotations |
| `max-warning-count` | No | `-1` | Fail when warnings exceed this (`-1` = off) |
| `max-annotations` | No | `200` | Cap for annotations |
| `install-doxygen` | No | `true` | apt-get install doxygen/graphviz when missing |
| `node-version` | No | `22` | Node major when bootstrapping Node |

## Outputs

| Output | Description |
| --- | --- |
| `exit-code` | Docs CLI exit code |
| `log-path` | Absolute path to the captured docs log |
| `warning-count` | Number of extracted warning lines |
| `warning-file` | Path to the extracted warnings file |

## Example

```yaml
name: WinCC OA Docs

on:
  push:
  pull_request:

jobs:
  docs:
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

      - id: docs
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-docu-builder@main
        with:
          path: src/Squirt
          winccoa-version: '3.21'
          docker-image: ${{ env.WINCCOA_IMAGE }}
          company-name: winccoa-tools-pack
          package-version: '0.1.0'
          max-warning-count: '-1'
```

## Bootstrap before npm publish

Until `@winccoa-tools-pack/npm-winccoa-docu-builder` is published, you can pass a
git install spec:

```yaml
package-version: 'github:winccoa-tools-pack/npm-winccoa-docu-builder#feature/initial-docu-builder'
```

After the first npm release, switch back to a semver such as `0.1.0`.

## Scope notes

- v1 builds documentation from the **runner/worker project only**.
- Test-suite source documentation can be added later.
- Annotations map `file:line[:col]: message` style doxygen lines onto PR files
  when paths are present in the warning text.
- After a successful build, the action stages doxygen configs next to
  `warning-output-file` for artifact upload/debug:
  - `advanced_doxygenConfig.txt` (user/advanced fragment from
    `<path>/data/projectDocu/`)
  - `doxygenConfig.txt` (merged config written by WinCC OA
    `DoxygenConfig::create()`)

---

<center>Made with ❤️ for and by the WinCC OA community</center>
