# WinCC OA TestFramework runner

Executes WinCC OA tests using the WinCC OA TestFramework with automatic jUnit report generation and artifact uploads.

## Inputs

| Input | Required | Default | Description |
| ------- | ---------- | --------- | ------------- |
| `winccoa-test-path` | yes | - | Path to the test sources based on WinCC OA TestFramework struct (e.g., `tests/WinCC_OA_Test`) |
| `test-run-id` | yes | - | Unique test run identifier (e.g., `Squirt-regression`) |
| `languages` | yes | - | Test languages, space-separated full locale names (e.g., `en_US.utf8 de_AT.utf8`) |
| `winccoa-version` | yes | - | WinCC OA version (e.g., `3.21`) |
| `upload-artifacts` | no | `true` | Upload failed tests and results as artifacts |
| `publish-junit-report` | no | `true` | Publish jUnit report as GitHub check |

## Outputs

No outputs planned now.

## Behavior

1. **Setup** — Configures `TfCustomized` test project with language support using the `winccoa-register-project` action. The setup step creates only `Projects/Stored/` and `Results/` — the TestFramework (`testRunner.ctl`) creates `Failed/` and `Valid/` subfolders as needed.
2. **Execution** — Runs `testRunner.ctl` via `WCCOActrl`
3. **Conversion** — Converts results to jUnit format via `oaTestParsers/jsonToJUnit.ctl`
4. **Upload** (optional) — Uploads test results and failed projects as artifacts
5. **Report** (optional) — Publishes jUnit report as GitHub check

## Usage

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-run-tests@main
  with:
    winccoa-test-path: tests/WinCC_OA_Test
    test-run-id: Squirt-regression
    languages: en_US.utf8 de_AT.utf8
    winccoa-version: 3.21

Notes:
- See the action `skills.md` for developer guidance: [actions/winccoa-ctrl-test-framework-runner/skills.md](actions/winccoa-ctrl-test-framework-runner/skills.md)
- Setup uses [actions/winccoa-register-project](actions/winccoa-register-project/action.yml) to create and register the test project; the action accepts `sub-projects` as a newline-separated input.
 - Setup uses [actions/winccoa-register-project](actions/winccoa-register-project/action.yml) to create and register the test project; the action accepts `sub-projects` as a newline-separated input.

Optional inputs:
- `parse-results` (default `false`) — set to `true` to parse jUnit results and populate action outputs. Leave `false` for very large test suites to avoid long parse times.
```

## Exit Code

- `0`: All tests passed
- `1`: Test failures or errors detected
- `!= 0`: Setup or execution error

## Artifacts

When `upload-artifacts: true` (default):

- **`test-results`** — Test output directory with jUnit XML and logs
- **`failed-tests`** — Failed test projects (if any)

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
