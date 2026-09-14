#!/usr/bin/env bash
# Shared helpers for winccoa-syntax-check action scripts.

normalize_rel_path() {
  local p="${1#./}"
  if [ -z "${p}" ]; then
    p="."
  fi
  printf '%s' "${p}"
}

normalize_langs() {
  printf '%s\n' "$1" | tr '\n' ' ' | xargs | tr ' ' ','
}

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    echo "Using existing Node $(node -v) / npm $(npm -v)"
    return 0
  fi
  local major="${NODE_VERSION:-22}"
  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "::error::Unsupported architecture: $(uname -m)"
      exit 2
      ;;
  esac
  echo "Node/npm not found; installing Node ${major} (${arch}) from nodejs.org"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl xz-utils >/dev/null
  fi
  local ver
  ver="$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c "import json,sys; major=sys.argv[1]; data=json.load(sys.stdin); lts=[x['version'] for x in data if x['version'].startswith('v'+major+'.') and x.get('lts')]; cands=[x['version'] for x in data if x['version'].startswith('v'+major+'.')]; print((lts or cands)[0])" "${major}")"
  curl -fsSL "https://nodejs.org/dist/${ver}/node-${ver}-linux-${arch}.tar.xz" | tar -xJ -C /usr/local --strip-components=1
  hash -r || true
  echo "Installed Node $(node -v) / npm $(npm -v)"
}

# Register project as runnable in the *current* environment.
# Must run in the same container/host as WCCOAui so pvssInst.conf is visible.
run_register_cli() {
  local project_path="$1"
  local langs
  langs="$(normalize_langs "${LANGUAGES:-en_US.utf8}")"
  if [ -z "${langs}" ]; then
    echo "::error::languages resolved to an empty list"
    exit 2
  fi
  if [ -z "${REGISTER_PACKAGE_VERSION:-}" ] || [ "${REGISTER_PACKAGE_VERSION}" = "main" ]; then
    echo "::error::register-package-version must be a published npm version or dist-tag (not main)"
    exit 2
  fi
  if [ ! -d "${project_path}" ]; then
    echo "::error::Project path does not exist: ${project_path}"
    exit 2
  fi

  ensure_node
  local workdir
  workdir="$(mktemp -d)"
  cd "${workdir}"
  npm init -y >/dev/null 2>&1
  local reg_spec="@winccoa-tools-pack/npm-winccoa-register-project@${REGISTER_PACKAGE_VERSION}"
  echo "Installing ${reg_spec} (runnable registration)"
  npm install --silent --no-fund --no-audit "${reg_spec}"

  local pkg_root="${workdir}/node_modules/@winccoa-tools-pack/npm-winccoa-register-project"
  local entry=""
  if [ -f "${pkg_root}/dist/cjs/cli.js" ]; then
    entry="${pkg_root}/dist/cjs/cli.js"
  elif [ -f "${pkg_root}/dist/cjs/index.js" ]; then
    entry="${pkg_root}/dist/cjs/index.js"
  else
    echo "::error::Could not find register CLI entry in ${pkg_root}"
    ls -la "${pkg_root}" || true
    exit 2
  fi

  # Syntax check requires a runnable registered project.
  local args=(
    --project-path "${project_path}"
    --langs "${langs}"
    --wincc-oa-version "${OA_VERSION}"
    --runnable true
  )

  echo "Running: node ${entry} ${args[*]}"
  node "${entry}" "${args[@]}"
}

run_syntax_cli() {
  local config_file="$1"
  ensure_node
  local workdir
  workdir="$(mktemp -d)"
  cd "${workdir}"
  npm init -y >/dev/null 2>&1
  echo "Installing ${PKG_SPEC}"
  npm install --silent --no-fund --no-audit "${PKG_SPEC}"
  local pkg_root="${workdir}/node_modules/@winccoa-tools-pack/npm-winccoa-syntax-check"
  local entry="${pkg_root}/dist/cjs/cli.js"
  if [ ! -f "${entry}" ]; then
    echo "::error::Missing CLI entry ${entry}"
    exit 2
  fi

  # WCCOAui refuses root without -runas-os-root. Ensure the installed package
  # adds it (older published versions did not). Safe no-op if already present.
  ensure_runas_os_root_flag "${pkg_root}"

  local args=(-v "${OA_VERSION}" -c "${config_file}" -m "${MODE}" -t "${TIMEOUT_MS}")
  if [ "${INTEGRITY:-false}" = "true" ]; then
    args+=(-i)
  fi
  if [ -n "${SCRIPTS_PATH:-}" ]; then
    args+=(-s "${SCRIPTS_PATH}")
  fi
  if [ -n "${PANELS_PATH:-}" ]; then
    args+=(-p "${PANELS_PATH}")
  fi
  echo "Running: node ${entry} ${args[*]}"
  node "${entry}" "${args[@]}"
}

# Ensure WCCOAui gets -runas-os-root when the process is root (Docker CI).
ensure_runas_os_root_flag() {
  local pkg_root="$1"
  local target
  for target in \
    "${pkg_root}/dist/cjs/syntax-checker.js" \
    "${pkg_root}/dist/esm/syntax-checker.js"
  do
    if [ ! -f "${target}" ]; then
      continue
    fi
    if grep -q -- '-runas-os-root' "${target}"; then
      echo "Package already supports -runas-os-root ($(basename "$(dirname "${target}")"))"
      continue
    fi
    echo "Patching $(basename "$(dirname "${target}")")/syntax-checker.js for -runas-os-root"
    # Insert after platform minimal push; tolerate single/double quotes and spacing.
    python3 - "${target}" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "-runas-os-root" in text:
    raise SystemExit(0)
pattern = re.compile(
    r"(args\.push\(\s*['\"]-platform['\"]\s*,\s*['\"]minimal['\"]\s*\)\s*;)",
    re.M,
)
replacement = r"\1\n        args.push('-runas-os-root');"
new_text, n = pattern.subn(replacement, text, count=1)
if n != 1:
    # Fallback: append near end of buildArgs return if pattern missed
    pattern2 = re.compile(r"(return args;\s*\n\s*\})", re.M)
    new_text, n = pattern2.subn(
        "args.push('-runas-os-root');\n        return args;\n    }",
        text,
        count=1,
    )
if n != 1:
    print(f"::warning::Could not patch {path} for -runas-os-root", file=sys.stderr)
    raise SystemExit(0)
path.write_text(new_text, encoding="utf-8")
print(f"Patched {path}")
PY
  done
}
