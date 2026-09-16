# github-actions-winccoa

Reusable GitHub Actions for WinCC OA projects.

This repository is structured as a multi-action repository. Each action lives in its own subdirectory under `actions/` and is published from the same repository tag.

## Why one repository

For an expected set of 20-25 actions, one repository is the better default:

- lower maintenance overhead for branching, rulesets, CI, security, and release automation
- one place for shared contribution guidelines and examples
- easier discovery for consumers looking for WinCC OA automation
- consistent version tags across related actions

Use separate repositories only when an action needs one of these:

- independent ownership or permissions
- a very different runtime or toolchain
- a separate release cadence with breaking changes unrelated to the rest
- a security boundary that should not share CI or release flows

## Repository layout

```text
github-actions-winccoa/
  .github/
    workflows/
      ci.yml
  actions/
    project-metadata/
      action.yml
      README.md
    syntax-check/
      action.yml
      README.md
  docs/
    repository-strategy.md
  scripts/
    list-actions.mjs
    validate-actions.mjs
  package.json
```

## Available actions

### ctrl-copyright-check

Scan *.ctl files for missing copyright headers and forbidden legacy
Siemens/GPL markers. Supports a path blacklist for known exceptions.

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/ctrl-copyright-check@main
  with:
    source-paths: src tests
    expected-owner: winccoa-tools-pack
    expected-spdx: MIT
    blacklist: |
      tests/vendor/legacy.ctl
```

### winccoa-build-docs

Builds WinCC OA help documentation in a container and extracts Doxygen
warnings for PR reporting or quality gates.

```yaml
- id: docs
  uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-build-docs@main
  with:
    path: src/Squirt
    winccoa-version: '3.21'
    docker-image: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
    max-warning-count: '0'
```

### winccoa-logs-to-pr-review

Parse classic WinCC OA logs with `@winccoa-tools-pack/npm-winccoa-log-reader`
and post an OK/NOK PR summary (optional line review comments). Supports
optional ignore of findings outside the PR’s changed files (default off) for
legacy baseline noise. See the [action README](actions/winccoa-logs-to-pr-review/README.md)
for screenshots of the summary comment, inline review, and out-of-range fallback.

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-logs-to-pr-review@main
  with:
    log-path: .artifacts/syntax-check.log
    title: Syntax check report
    include-error-types: CTRL
    review-comments: 'true'
    # optional (default false): only treat findings in PR-touched files as active
    ignore-outside-pr-changes: 'true'
```

## Runtime and compatibility

- Actions in this repository are intended for Linux environments.
- The current validation baseline is Debian-based Docker images with WinCC OA 3.21.
- Compatibility is expected for WinCC OA 3.21 patch versions and WinCC OA 3.22.
- Legacy WinCC OA 3.20 may work, but should be treated as best-effort and validated per project.

### winccoa-syntax-check

Runs WinCC OA syntax validation (npm package) and writes a classic log for PR reporting.

```yaml
- id: syntax
  uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-syntax-check@main
  with:
    path: src/Squirt
    winccoa-version: '3.21'
    docker-image: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
```

### winccoa-style-check

Runs CTL style check/format via
`@winccoa-tools-pack/npm-winccoa-ctrl-code-style` (worker + StyleCheck model)
and writes a classic log for PR reporting.

```yaml
- id: style
  uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-style-check@main
  with:
    path: src/Squirt
    source-path: src/Squirt/scripts
    winccoa-version: '3.21'
    docker-image: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
    package-version: '0.1.1'
```

### project-metadata

Normalizes project and config paths for downstream workflow steps.

```yaml
- id: metadata
  uses: winccoa-tools-pack/github-actions-winccoa/actions/project-metadata@v1
  with:
    path: demo-oa-repo

- run: echo "Config is ${{ steps.metadata.outputs.config-path }}"
```

## Release model

- tag the repository with full versions such as `v1.2.0`
- move the major tag such as `v1` after compatible releases
- keep breaking changes grouped into a new major tag

That model is simple and works well until one action needs its own release lifecycle. If that happens, split only that action into its own repository.

## Development

```powershell
npm install
npm run validate
npm run list:actions
```
