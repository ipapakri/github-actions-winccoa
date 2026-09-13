#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ ! -d "/opt/WinCC_OA/${OA_VERSION}" ]; then
  echo "::error::WinCC OA install not found at /opt/WinCC_OA/${OA_VERSION}"
  exit 2
fi
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "::error::Project config not found at ${CONFIG_FILE}"
  exit 2
fi

set +e
OUTPUT=$(run_syntax_cli "${CONFIG_FILE}" 2>&1)
EC=$?
set -e

printf '%s\n' "${OUTPUT}"
ERROR_COUNT=$(printf '%s\n' "${OUTPUT}" | grep -Eic 'error:|SEVERE|FATAL|syntax error' || true)
echo "error-count=${ERROR_COUNT}"
echo "exit-code=${EC}"
exit "${EC}"
