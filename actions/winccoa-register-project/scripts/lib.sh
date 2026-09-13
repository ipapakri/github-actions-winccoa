#!/usr/bin/env bash
# Shared helpers for winccoa-register-project action scripts.

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
      echo "::error::Unsupported architecture for Node bootstrap: $(uname -m)"
      return 2
      ;;
  esac

  echo "Node/npm not found; installing Node ${major} (${arch}) from nodejs.org"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl xz-utils >/dev/null
  fi

  local ver
  ver="$(curl -fsSL "https://nodejs.org/dist/index.json" | \
    python3 -c "import json,sys; major=sys.argv[1]; data=json.load(sys.stdin); lts=[x['version'] for x in data if x['version'].startswith('v'+major+'.') and x.get('lts')]; cands=[x['version'] for x in data if x['version'].startswith('v'+major+'.')]; print((lts or cands)[0])" \
    "${major}")"

  local url="https://nodejs.org/dist/${ver}/node-${ver}-linux-${arch}.tar.xz"
  curl -fsSL "${url}" | tar -xJ -C /usr/local --strip-components=1
  hash -r || true
  echo "Installed Node $(node -v) / npm $(npm -v)"
}

run_register_cli() {
  local project_path="$1"
  ensure_node

  local workdir
  workdir="$(mktemp -d)"
  cd "${workdir}"
  npm init -y >/dev/null 2>&1
  echo "Installing ${PKG_SPEC}"
  npm install --silent --no-fund --no-audit "${PKG_SPEC}"

  local pkg_root="${workdir}/node_modules/@winccoa-tools-pack/npm-winccoa-register-project"
  local entry=""
  if [ -f "${pkg_root}/dist/cjs/cli.js" ]; then
    entry="${pkg_root}/dist/cjs/cli.js"
  elif [ -f "${pkg_root}/dist/cjs/index.js" ]; then
    # Prefer compiled CLI; fall back to index for older package layouts.
    entry="${pkg_root}/dist/cjs/index.js"
  else
    echo "::error::Could not find CLI entry in ${pkg_root}"
    ls -la "${pkg_root}" || true
    exit 2
  fi

  local args=(
    --project-path "${project_path}"
    --langs "${LANGS}"
    --wincc-oa-version "${WINCCOA_VERSION}"
    --runnable true
  )

  if [ -n "${SUB_PROJECTS:-}" ]; then
    while IFS= read -r sp || [ -n "${sp}" ]; do
      sp="$(printf '%s' "${sp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "${sp}" ] && continue
      sp="${sp%\"}"
      sp="${sp#\"}"
      args+=(--sub-project "${sp}")
    done <<< "${SUB_PROJECTS}"
  fi

  echo "Running: node ${entry} ${args[*]}"
  node "${entry}" "${args[@]}"
}
