# WinCC OA Register Project

Thin GitHub Action wrapper around the public npm package
[`@winccoa-tools-pack/npm-winccoa-register-project`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-register-project).

The action installs the published package and runs its CLI. It does **not**
reimplement config generation or `WCCILpmon` registration in shell.

## Runtime

- Linux runners only
- Requires a WinCC OA install either via:
  - `docker-image` (recommended on GitHub-hosted runners), or
  - a job container / host that already has WinCC OA under `/opt/WinCC_OA/<version>`
- If Node.js is missing, the action bootstraps a Node binary from nodejs.org

## Inputs

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `project-path` | yes | - | Path to the main WinCC OA project directory (e.g., `src/Squirt`) |
| `sub-projects` | no | empty | Optional newline-separated list of sub-project paths or IDs |
| `languages` | yes | - | Space- or newline-separated locales (e.g., `en_US.utf8 de_AT.utf8`) |
| `winccoa-version` | yes | - | WinCC OA version (e.g., `3.21`) |
| `docker-image` | no | empty | Optional WinCC OA container image |
| `package-version` | no | `1.1.1` | npm version/dist-tag (not a git ref like `main`) |
| `node-version` | no | `22` | Node major used when bootstrapping Node |

## Behavior

- Installs `@winccoa-tools-pack/npm-winccoa-register-project@<package-version>`
- Invokes the compiled CLI entry (`dist/cjs/cli.js`, fallback `dist/cjs/index.js`)
- Passes `--project-path`, `--langs`, `--wincc-oa-version`, optional `--sub-project`
- When `docker-image` is set, runs the CLI inside the image with the workspace
  mounted at `/workspace`

## Usage

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-register-project@main
  with:
    project-path: src/Squirt
    languages: |
      en_US.utf8
      de_AT.utf8
    winccoa-version: '3.21'
    docker-image: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
    package-version: '1.1.1'
```

## Notes

- Never pin npm packages to git branch names such as `@main`
- Published package `1.1.1` has a broken `bin` path (`src/index.js` is not
  shipped). This action calls `dist/cjs/*` directly to work around that

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
