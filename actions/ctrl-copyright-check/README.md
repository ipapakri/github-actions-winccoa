# Ctrl Copyright Check

Reusable GitHub Action that scans `*.ctl` files for copyright/license header
problems commonly found when migrating WinCC OA codebases.

## Checks

- Missing `@copyright` / `Copyright` marker
- Forbidden `SPDX-License-Identifier: GPL-3.0-only`
- Forbidden `Copyright YYYY SIEMENS AG` owner line

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `source-paths` | No | `.` | Space-separated directories to scan |
| `script-path` | No | empty | Optional helper script path; existence-checked when set |
| `expected-owner` | No | `winccoa-tools-pack` | Informational expected owner |
| `expected-spdx` | No | `MIT` | Informational expected SPDX id |
| `blacklist` | No | empty | Known exception paths (newline/space separated, `#` comments OK) |

## Example

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/ctrl-copyright-check@main
  with:
    source-paths: "src tests"
    expected-owner: "winccoa-tools-pack"
    expected-spdx: "MIT"
    blacklist: |
      # vendor / generated files without project headers
      tests/vendor/legacy.ctl
```

## Notes

- Blacklisted files are skipped and logged as `SKIPPED-BLACKLIST: <path>`
- A report is written to `.artifacts/ctrl-copyright-check.txt`
- Shell logic lives in `scripts/run.sh` so `action.yml` stays valid YAML

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
