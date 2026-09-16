#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if ! [[ "${TIMEOUT_MS:-}" =~ ^[0-9]+$ ]] || [ "${TIMEOUT_MS}" -le 0 ]; then
  echo "::error::Invalid timeout-ms '${TIMEOUT_MS}'"
  exit 2
fi

if [ -z "${OA_VERSION:-}" ]; then
  echo "::error::winccoa-version is required"
  exit 2
fi

if [ -z "${PACKAGE_VERSION:-}" ] || [ "${PACKAGE_VERSION}" = "main" ]; then
  echo "::error::package-version must be a published npm version or dist-tag (not main)"
  exit 2
fi

PROJECT_PATH_NORM="$(normalize_rel_path "${PROJECT_PATH:-.}")"
COMPANY_NAME="$(resolve_company_name "${COMPANY_NAME_INPUT:-}")"

PKG_NAME="@winccoa-tools-pack/npm-winccoa-docu-builder"
export PKG_SPEC="${PKG_NAME}@${PACKAGE_VERSION}"

HOST_PROJ_PATH="${GITHUB_WORKSPACE}/${PROJECT_PATH_NORM}"
CONTAINER_PROJ_PATH="/workspace/${PROJECT_PATH_NORM}"

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
  echo "Running docs build (${PKG_SPEC}) inside ${DOCKER_IMAGE}"
  # One container: DocuBuilder registration + WCCOActrl must share pvssInst.conf.
  OUTPUT=$(docker run --rm \
    --user root \
    --shm-size=2g \
    -v "${GITHUB_WORKSPACE}:/workspace:rw" \
    -v "${ACTION_PATH}:/action:ro" \
    -w /workspace \
    -e OA_VERSION="${OA_VERSION}" \
    -e TIMEOUT_MS="${TIMEOUT_MS}" \
    -e PACKAGE_VERSION="${PACKAGE_VERSION}" \
    -e NODE_VERSION="${NODE_VERSION:-22}" \
    -e PKG_SPEC="${PKG_SPEC}" \
    -e REGISTER_PROJECT="${REGISTER_PROJECT:-true}" \
    -e LANGUAGES="${LANGUAGES:-en_US.utf8}" \
    -e COMPANY_NAME="${COMPANY_NAME}" \
    -e INSTALL_DOXYGEN="${INSTALL_DOXYGEN:-true}" \
    -e PROJECT_PATH_IN_CONTAINER="${CONTAINER_PROJ_PATH}" \
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
  echo "Running docs build on current host/container"
  OUTPUT=$(run_docu_cli "${HOST_PROJ_PATH}" "${COMPANY_NAME}" 2>&1)
  EXIT_CODE=$?
fi
set -e

echo "--- Docs build output ---"
printf '%s\n' "${OUTPUT}"
echo "--- end output ---"

LOG_REL="${LOG_PATH:-.artifacts/docu-builder.log}"
if [[ "${LOG_REL}" = /* ]]; then
  LOG_ABS="${LOG_REL}"
else
  LOG_ABS="${GITHUB_WORKSPACE:-$(pwd)}/${LOG_REL}"
fi
mkdir -p "$(dirname "${LOG_ABS}")"
printf '%s\n' "${OUTPUT}" > "${LOG_ABS}"
echo "Wrote docs log: ${LOG_ABS}"

WARNING_REL="${WARNING_OUTPUT_FILE:-.artifacts/doxygen-warnings.txt}"
if [[ "${WARNING_REL}" = /* ]]; then
  WARNING_ABS="${WARNING_REL}"
else
  WARNING_ABS="${GITHUB_WORKSPACE:-$(pwd)}/${WARNING_REL}"
fi

set +e
extract_and_annotate_warnings "${PROJECT_PATH_NORM}" "${OUTPUT}" "${WARNING_ABS}"
WARN_RC=$?
set -e

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "exit-code=${EXIT_CODE}"
    echo "log-path=${LOG_ABS}"
  } >> "${GITHUB_OUTPUT}"
fi

if [ "${WARN_RC}" -ne 0 ]; then
  if [ "${FAIL_ON_ERROR:-true}" = "true" ]; then
    exit "${WARN_RC}"
  fi
  echo "::warning::Warning threshold / annotation step returned ${WARN_RC}"
fi

if [ "${EXIT_CODE}" -ne 0 ]; then
  MESSAGE="Docs build failed (exit ${EXIT_CODE})"
  if [ "${FAIL_ON_ERROR:-true}" = "true" ]; then
    echo "::error::${MESSAGE}"
    exit "${EXIT_CODE}"
  fi
  echo "::warning::${MESSAGE}"
fi
