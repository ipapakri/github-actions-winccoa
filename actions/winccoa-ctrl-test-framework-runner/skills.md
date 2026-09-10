Developer notes (skills) for `winccoa-ctrl-test-framework-runner`

- The action intentionally creates the following directories before test execution:
  - `Results/` — where the TestFramework writes test output
  - `Projects/Stored/` — top-level storage for generated project folders

- Do NOT create `Projects/Stored/Failed` or `Projects/Stored/Valid` here: the TestFramework (`testRunner.ctl`) will create `Failed/` and `Valid/` subfolders as needed during the test run.

- The action uploads artifacts from `Projects/Stored/Failed/` (if present). The upload step uses `if-no-files-found: ignore` so missing `Failed/` is not an error.

- If you need different behavior (e.g., pre-populate a `Failed/` folder for debugging), change the action to create that directory explicitly.

Note (2026-09-09): the `pmon-port` input and related `pmonPort` config were removed from the action because the `TfCustomized` project is not started by this action — only single managers (test runner) are used. If you need to run the full project locally (for development), add a `pmon-port` input at that time and pass it through to the generated config.

About naming: we standardized per-action notes to `skills.md` to provide a consistent, discoverable filename across actions. Use `skills.md` for concise developer guidance and small how-tos.

Contact: winccoa-tools-pack maintainers
