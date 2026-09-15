# WinCC OA Logs to PR Review

Parse classic WinCC OA logs (`PVSS_II.log` shape / WCCOAui `-syntax` stderr)
with [`@winccoa-tools-pack/npm-winccoa-log-reader`](https://www.npmjs.com/package/@winccoa-tools-pack/npm-winccoa-log-reader)
and publish a quick PR report:

- **OK / NOK file counts** (from `PARAM,INFO` checked paths minus findings)
- Optional **PR review comments** on Script/Library line locations
- Always emits GitHub **workflow annotations** for findings (capped)
- Optional **ignore findings outside PR changed files** (default off)

## Runtime

- Linux runners with Node 20+ (bootstraps Node when missing)
- Needs `pull-requests: write` (and usually `contents: read`) when commenting
  or when `ignore-outside-pr-changes` is enabled (lists PR files via API)
- Intended to run after `winccoa-syntax-check` (or any step that produces a classic OA log)

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `log-path` | yes | - | Classic OA log file path |
| `title` | no | `WinCC OA log report` | PR comment heading |
| `comment-marker` | no | `<!-- winccoa-logs-to-pr-review -->` | Upsert marker |
| `comment-on-pr` | no | `true` | Upsert PR issue comment |
| `review-comments` | no | `false` | Try PR line review comments |
| `fail-on-findings` | no | `false` | Fail step when **active** (non-ignored) findings remain |
| `ignore-outside-pr-changes` | no | `false` | On `pull_request`, ignore findings in files not changed in the PR (file-level). Default off. Useful for legacy repos with baseline syntax noise. |
| `annotate-ignored` | no | `false` | When ignoring outside PR changes, still emit workflow annotations for ignored findings |
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
| `ok-count` | Files checked without **active** findings |
| `nok-count` | Unique files (or system bucket) with **active** findings |
| `finding-count` | Active (non-ignored) matching findings |
| `finding-count-total` | Matching findings before ignore filter |
| `ignored-count` | Findings ignored because outside PR changes |
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

      - id: report
        if: always() && github.event_name == 'pull_request'
        uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-logs-to-pr-review@main
        with:
          log-path: ${{ steps.syntax.outputs.log-path }}
          title: Syntax check report
          comment-marker: '<!-- winccoa-syntax-check-report -->'
          include-error-types: CTRL
          review-comments: 'true'
          # Legacy baseline: only fail on findings in files this PR touches
          ignore-outside-pr-changes: 'true'
          fail-on-findings: 'false'

      # PR: fail only on active findings. Push: fail if syntax step failed.
      - if: always()
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            FINDINGS="${{ steps.report.outputs.finding-count }}"
            FINDINGS="${FINDINGS:-0}"
            if [ "$FINDINGS" -gt 0 ]; then
              echo "::error::Active syntax findings: $FINDINGS"
              exit 1
            fi
            exit 0
          fi
          if [ "${{ steps.syntax.outcome }}" = "failure" ]; then
            echo "::error::Syntax check failed"
            exit 1
          fi
```

## Notes

- OK inventory prefers `PARAM,INFO` lines emitted while WCCOAui walks files.
  If those lines are missing, OK may be `0` and only NOK files are listed.
- The step prints `--- filtered-log-json-begin ---` … with full filtered entries
  (`metadata.line`, `rawLines`, cleaned `message`) plus the summary JSON for
  debugging location/message issues in the job log.
- Line numbers come from WinCC OA log metadata (`Script` / `Library` / `Line`).
  For duplicate-identifier warnings OA often points at the **function** line,
  not the second declaration line.
- Review comments only attach to lines present in the PR diff; otherwise the
  action falls back to a **file-level** review comment. Annotations still show
  in the Checks UI.
- `ignore-outside-pr-changes` matches at **file** level (not hunk/line). Findings
  with no file path stay active. Ignored findings still appear in the PR comment
  under a separate section; they do not count toward NOK / `fail-on-findings` /
  review comments unless `annotate-ignored` is true for Checks annotations.
- When the syntax step uses `fail-on-error: true` and `continue-on-error: true`,
  gate the job on **report** `finding-count` (active) rather than
  `steps.syntax.outcome`, or ignored baseline findings will still fail the job.
- Never pin the npm package to a git ref such as `main`.

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
