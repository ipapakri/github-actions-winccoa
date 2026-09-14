#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ ! -d "/opt/WinCC_OA/${OA_VERSION}" ]; then
  echo "::error::WinCC OA install not found at /opt/WinCC_OA/${OA_VERSION}"
  exit 2
fi

PROJECT_PATH_IN_CONTAINER="${PROJECT_PATH_IN_CONTAINER:-}"
if [ -z "${PROJECT_PATH_IN_CONTAINER}" ]; then
  # Derive from config path: .../config/config -> project root
  PROJECT_PATH_IN_CONTAINER="$(dirname "$(dirname "${CONFIG_FILE}")")"
fi

# Register runnable project in THIS container so WCCOAui sees pvssInst.conf.
if [ "${REGISTER_PROJECT:-true}" = "true" ]; then
  echo "Registering project as runnable before syntax check"
  run_register_cli "${PROJECT_PATH_IN_CONTAINER}"
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
