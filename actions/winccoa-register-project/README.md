# WinCC OA Register Project

Creates  WinCC OA project config file and register the project with support for:

- multiple languages
- multiple sub-projects
- set correct WinCC OA version

Thic action might be used as for runnable projects and also for sub-projects (not runnable)

## Inputs

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `project-path` | yes | - | Path to the main WinCC OA project directory (e.g., `src/Squirt`) |
| `sub-projects` | no | empty | Optional newline-separated list of sub-project identifiers or paths (one per line). IDs may contain spaces. |
| `languages` | yes | - | Languages to configure, space-separated full locale names (e.g., `en_US.utf8 de_AT.utf8`) |
| `winccoa-version` | no | - | WinCC OA version (e.g., `3.21`) This is mandaotry in case your gh runner has more the 1 WinCC OA version installed |

## Behavior

- Creates a config directory at `{project-path}/config`
- Generates a WinCC OA config file with:
  - `pvss_path = "/opt/WinCC_OA/{winccoa-version}"`
  - Optional sub-project `proj_path` entries, one per configured sub-project ID
  - Final `proj_path` entry for the main project
  - Multiple `langs` entries (one per language)
  - `proj_version = "{winccoa-version}"`
- Registers the WinCC OA (sub-) project

## Usage

```yaml
- uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-register-project@main
  with:
    project-path: src/Squirt
    languages: en_US.utf8 de_AT.utf8

## Example: multiple projects (sub-projects/add-ons)

- uses: winccoa-tools-pack/github-actions-winccoa/actions/winccoa-register-project@main
  with:
    project-path: src/Squirt
    sub-projects: |
      addons/plugin1
      "Test Framework 3.21"
      path/to/proj3
    languages: en_US.utf8 de_AT.utf8
    winccoa-version: 3.21
```

## Exit Code

- `0`: Success (config created and registered)
- `!= 0`: Error during config creation or registration

---

<!-- markdownlint-disable-next-line MD033 -->
<center>Made with ❤️ for and by the WinCC OA community</center>
