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
  echo "::error::PROJECT_PATH_IN_CONTAINER is required inside the container"
  exit 2
fi

if [ ! -d "${PROJECT_PATH_IN_CONTAINER}" ]; then
  echo "::error::Project path does not exist: ${PROJECT_PATH_IN_CONTAINER}"
  exit 2
fi

COMPANY_NAME="${COMPANY_NAME:-}"
if [ -z "${COMPANY_NAME}" ]; then
  COMPANY_NAME="$(resolve_company_name "")"
fi

set +e
OUTPUT=$(run_docu_cli "${PROJECT_PATH_IN_CONTAINER}" "${COMPANY_NAME}" 2>&1)
EC=$?
set -e

printf '%s\n' "${OUTPUT}"
echo "exit-code=${EC}"
exit "${EC}"
