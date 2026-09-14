#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

case "${MODE:-all}" in
  all|scripts|panels) ;;
  *)
    echo "::error::Invalid mode '${MODE}'. Expected all, scripts, or panels."
    exit 2
    ;;
esac

if ! [[ "${TIMEOUT_MS:-}" =~ ^[0-9]+$ ]] || [ "${TIMEOUT_MS}" -le 0 ]; then
  echo "::error::Invalid timeout-ms '${TIMEOUT_MS}'"
  exit 2
fi

if [ -z "${PACKAGE_VERSION:-}" ] || [ "${PACKAGE_VERSION}" = "main" ]; then
  echo "::error::package-version must be a published npm version or dist-tag (not main)"
  exit 2
fi

PROJECT_PATH_NORM="$(normalize_rel_path "${PROJECT_PATH:-.}")"
PKG_NAME="@winccoa-tools-pack/npm-winccoa-syntax-check"
export PKG_SPEC="${PKG_NAME}@${PACKAGE_VERSION}"

HOST_PROJ_PATH="${GITHUB_WORKSPACE}/${PROJECT_PATH_NORM}"
HOST_CONFIG_FILE="${HOST_PROJ_PATH}/config/config"
CONTAINER_PROJ_PATH="/workspace/${PROJECT_PATH_NORM}"
CONTAINER_CONFIG_FILE="${CONTAINER_PROJ_PATH}/config/config"

set +e
if [ -n "${DOCKER_IMAGE:-}" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "::error::docker-image was set but docker is not available on the runner"
    exit 127
  fi
  if [ ! -d "${HOST_PROJ_PATH}" ]; then
    echo "::error::Project path does not exist: ${HOST_PROJ_PATH}"
    exit 2
  fi

  ACTION_PATH="${ACTION_PATH:-${SCRIPT_DIR}/..}"
  echo "Running register+syntax (${PKG_SPEC}) inside ${DOCKER_IMAGE}"
  # One container for both steps: registration writes /etc/opt/pvss/pvssInst.conf
  # which is not shared across containers.
  OUTPUT=$(docker run --rm \
    --user root \
    --shm-size=1g \
    -v "${GITHUB_WORKSPACE}:/workspace:rw" \
    -v "${ACTION_PATH}:/action:ro" \
    -w /workspace \
    -e OA_VERSION="${OA_VERSION}" \
    -e MODE="${MODE}" \
    -e INTEGRITY="${INTEGRITY:-false}" \
    -e TIMEOUT_MS="${TIMEOUT_MS}" \
    -e SCRIPTS_PATH="${SCRIPTS_PATH:-}" \
    -e PANELS_PATH="${PANELS_PATH:-}" \
    -e PACKAGE_VERSION="${PACKAGE_VERSION}" \
    -e NODE_VERSION="${NODE_VERSION:-22}" \
    -e PKG_SPEC="${PKG_SPEC}" \
    -e CONFIG_FILE="${CONTAINER_CONFIG_FILE}" \
    -e PROJECT_PATH_IN_CONTAINER="${CONTAINER_PROJ_PATH}" \
    -e REGISTER_PROJECT="${REGISTER_PROJECT:-true}" \
    -e REGISTER_PACKAGE_VERSION="${REGISTER_PACKAGE_VERSION:-1.1.1}" \
    -e LANGUAGES="${LANGUAGES:-en_US.utf8}" \
    "${DOCKER_IMAGE}" \
    bash /action/scripts/run-in-container.sh 2>&1)
  EXIT_CODE=$?
else
  if [ ! -d "${HOST_PROJ_PATH}" ]; then
    echo "::error::Project path does not exist: ${HOST_PROJ_PATH}"
    exit 2
  fi
  if [ ! -d "/opt/WinCC_OA/${OA_VERSION}" ]; then
    echo "::error::WinCC OA install not found at /opt/WinCC_OA/${OA_VERSION}. Provide docker-image or run inside a WinCC OA container."
    exit 2
  fi
  echo "Running on current host/container"
  if [ "${REGISTER_PROJECT:-true}" = "true" ]; then
    echo "Registering project as runnable before syntax check"
    set -e
    run_register_cli "${HOST_PROJ_PATH}"
    set +e
  fi
  if [ ! -f "${HOST_CONFIG_FILE}" ]; then
    echo "::error::Project config not found at ${HOST_CONFIG_FILE}. Enable register-project or provide a config first."
    exit 2
  fi
  OUTPUT=$(run_syntax_cli "${HOST_CONFIG_FILE}" 2>&1)
  EXIT_CODE=$?
fi
set -e

echo "--- Syntax check output ---"
printf '%s\n' "${OUTPUT}"
echo "--- end output ---"

ERROR_COUNT=$(printf '%s\n' "${OUTPUT}" | sed -n 's/^error-count=//p' | tail -n1)
if [ -z "${ERROR_COUNT}" ]; then
  ERROR_COUNT=$(printf '%s\n' "${OUTPUT}" | grep -Eic 'error:|SEVERE|FATAL|syntax error' || true)
fi
if [ "${ERROR_COUNT}" = "0" ] && [ "${EXIT_CODE}" -ne 0 ]; then
  ERROR_COUNT=1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "error-count=${ERROR_COUNT}" >> "${GITHUB_OUTPUT}"
fi

if [ "${EXIT_CODE}" -ne 0 ]; then
  MESSAGE="Syntax check failed (exit ${EXIT_CODE}). Parsed errors: ${ERROR_COUNT}"
  if [ "${FAIL_ON_ERROR:-true}" = "true" ]; then
    echo "::error::${MESSAGE}"
    exit "${EXIT_CODE}"
  fi
  echo "::warning::${MESSAGE}"
fi
