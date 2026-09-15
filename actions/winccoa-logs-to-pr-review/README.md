# WinCC OA Logs to PR Review

Parse classic WinCC OA logs (`PVSS_II.log` shape / WCCOAui `-syntax` stderr)
with [`@winccoa-tools-pack/npm-winccoa-log-reader`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-log-reader)
and publish a quick PR report:

- **OK / NOK file counts** (from `PARAM,INFO` checked paths minus findings)
- Optional **PR review comments** on Script/Library line locations
- Always emits GitHub **workflow annotations** for findings (capped)

## Runtime

- Linux runners with Node 20+ (bootstraps Node when missing)
- Needs `pull-requests: write` (and usually `contents: read`) when commenting
- Intended to run after `winccoa-syntax-check` (or any step that produces a classic OA log)

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `log-path` | yes | - | Classic OA log file path |
| `title` | no | `WinCC OA log report` | PR comment heading |
| `comment-marker` | no | `<!-- winccoa-logs-to-pr-review -->` | Upsert marker |
| `comment-on-pr` | no | `true` | Upsert PR issue comment |
| `review-comments` | no | `false` | Try PR line review comments |
| `fail-on-findings` | no | `false` | Fail step when findings remain |
| `severities` | no | `WARNING,SEVERE,FATAL` | Severities treated as findings |
| `include-error-types` | no | empty | Optional type filter (e.g. `CTRL`) |
| `path-strip-prefixes` | no | `/workspace/` | Prefixes stripped from absolute paths |
| `summary-path` | no | `.artifacts/winccoa-log-report.json` | JSON summary output |
| `package-version` | no | `0.1.1` | npm version of log-reader |
| `node-version` | no | `22` | Node major when bootstrapping |
| `github-token` | no | `github.token` | Token for PR APIs |

## Outputs

| Output | Description |
| --- | --- |
| `ok-count` | Files checked without findings |
| `nok-count` | Unique files (or system bucket) with findings |
| `finding-count` | Total matching findings |
| `checked-count` | Unique checked files discovered |
| `summary-path` | Absolute path to JSON summary |

## Example (with syntax-check)

```yaml
permissions:
  contents: read
  packages: read
  pull-requests: write

jobs:
  syntax:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - id: syntax
        continue-on-error: true
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-syntax-check@main
        with:
          path: src/Squirt
          winccoa-version: '3.21'
          docker-image: ghcr.io/winccoa-tools-pack/winccoa:v3.21.3-debian12-all
          fail-on-error: 'true'

      - if: always() && github.event_name == 'pull_request'
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-logs-to-pr-review@main
        with:
          log-path: ${{ steps.syntax.outputs.log-path }}
          title: Syntax check report
          comment-marker: '<!-- winccoa-syntax-check-report -->'
          include-error-types: CTRL
          review-comments: 'true'
          fail-on-findings: 'false'

      - if: steps.syntax.outcome == 'failure'
        run: exit 1
```

## Notes

- OK inventory prefers `PARAM,INFO` lines emitted while WCCOAui walks files.
  If those lines are missing, OK may be `0` and only NOK files are listed.
- Review comments only attach to lines present in the PR diff; others are skipped
  with a warning. Annotations still show in the Checks UI.
- Never pin the npm package to a git ref such as `main`.

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
