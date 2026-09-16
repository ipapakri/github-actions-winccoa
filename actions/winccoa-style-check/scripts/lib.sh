#!/usr/bin/env bash
# Shared helpers for winccoa-style-check action scripts.

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

# Run winccoa-ctrl-style against a worker project path in the current environment.
run_style_cli() {
  local project_path="$1"
  local source_path="${2:-}"

  ensure_node
  local workdir
  workdir="$(mktemp -d)"
  cd "${workdir}"
  npm init -y >/dev/null 2>&1
  echo "Installing ${PKG_SPEC}"
  npm install --silent --no-fund --no-audit "${PKG_SPEC}"

  local pkg_root="${workdir}/node_modules/@winccoa-tools-pack/npm-winccoa-ctrl-code-style"
  local entry="${pkg_root}/dist/cjs/cli.js"
  if [ ! -f "${entry}" ]; then
    echo "::error::Missing CLI entry ${entry}"
    ls -la "${pkg_root}" || true
    exit 2
  fi

  local cmd="${COMMAND:-check}"
  case "${cmd}" in
    check|format) ;;
    *)
      echo "::error::Invalid command '${cmd}'. Expected check or format."
      exit 2
      ;;
  esac

  local langs
  langs="$(normalize_langs "${LANGUAGES:-en_US.utf8}")"
  if [ -z "${langs}" ]; then
    echo "::error::languages resolved to an empty list"
    exit 2
  fi

  local args=(
    "${cmd}"
    "${project_path}"
    -v "${OA_VERSION}"
    --langs "${langs}"
    -t "${TIMEOUT_MS}"
  )

  if [ -n "${source_path}" ]; then
    args+=(-s "${source_path}")
  fi

  if [ "${REGISTER_PROJECT:-true}" != "true" ]; then
    args+=(--no-register)
  fi

  echo "Running: node ${entry} ${args[*]}"
  node "${entry}" "${args[@]}"
}
