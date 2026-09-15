#!/usr/bin/env bash
# Shared helpers for winccoa-logs-to-pr-review.

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

resolve_log_path() {
  local p="${1:-}"
  if [ -z "${p}" ]; then
    echo "::error::log-path is required"
    exit 2
  fi
  if [ -f "${p}" ]; then
    printf '%s' "$(cd "$(dirname "${p}")" && pwd)/$(basename "${p}")"
    return 0
  fi
  if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -f "${GITHUB_WORKSPACE}/${p}" ]; then
    printf '%s' "${GITHUB_WORKSPACE}/${p}"
    return 0
  fi
  echo "::error::Log file not found: ${p}"
  exit 2
}
