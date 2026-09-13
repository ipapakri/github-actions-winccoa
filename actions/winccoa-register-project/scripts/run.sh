#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ -z "${WINCCOA_VERSION:-}" ]; then
  echo "::error::winccoa-version is required"
  exit 2
fi
if [ -z "${LANGUAGES:-}" ]; then
  echo "::error::languages is required"
  exit 2
fi
if [ -z "${PACKAGE_VERSION:-}" ] || [ "${PACKAGE_VERSION}" = "main" ]; then
  echo "::error::package-version must be a published npm version or dist-tag (not main)"
  exit 2
fi

PROJECT_PATH_NORM="$(normalize_rel_path "${PROJECT_PATH:-.}")"
export LANGS
LANGS="$(normalize_langs "${LANGUAGES}")"
if [ -z "${LANGS}" ]; then
  echo "::error::languages resolved to an empty list"
  exit 2
fi

PKG_NAME="@winccoa-tools-pack/npm-winccoa-register-project"
export PKG_SPEC="${PKG_NAME}@${PACKAGE_VERSION}"

if [ -n "${DOCKER_IMAGE:-}" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "::error::docker-image was set but docker is not available on the runner"
    exit 127
  fi

  HOST_PROJ_PATH="${GITHUB_WORKSPACE}/${PROJECT_PATH_NORM}"
  if [ ! -d "${HOST_PROJ_PATH}" ]; then
    echo "::error::Project path does not exist: ${HOST_PROJ_PATH}"
    exit 2
  fi

  ACTION_PATH="${ACTION_PATH:-${SCRIPT_DIR}/..}"
  CONTAINER_PROJ_PATH="/workspace/${PROJECT_PATH_NORM}"
  echo "Running ${PKG_SPEC} inside ${DOCKER_IMAGE}"
  docker run --rm \
    --user root \
    -v "${GITHUB_WORKSPACE}:/workspace:rw" \
    -v "${ACTION_PATH}:/action:ro" \
    -w /workspace \
    -e PROJECT_PATH="${CONTAINER_PROJ_PATH}" \
    -e SUB_PROJECTS="${SUB_PROJECTS:-}" \
    -e LANGS="${LANGS}" \
    -e WINCCOA_VERSION="${WINCCOA_VERSION}" \
    -e PACKAGE_VERSION="${PACKAGE_VERSION}" \
    -e NODE_VERSION="${NODE_VERSION:-22}" \
    -e PKG_SPEC="${PKG_SPEC}" \
    "${DOCKER_IMAGE}" \
    bash /action/scripts/run-in-container.sh
else
  HOST_PROJ_PATH="${GITHUB_WORKSPACE}/${PROJECT_PATH_NORM}"
  if [ ! -d "${HOST_PROJ_PATH}" ]; then
    if [ -d "${PROJECT_PATH}" ]; then
      HOST_PROJ_PATH="${PROJECT_PATH}"
    else
      echo "::error::Project path does not exist: ${HOST_PROJ_PATH}"
      exit 2
    fi
  fi
  if [ ! -d "/opt/WinCC_OA/${WINCCOA_VERSION}" ]; then
    echo "::error::WinCC OA install not found at /opt/WinCC_OA/${WINCCOA_VERSION}. Provide docker-image or run inside a WinCC OA container."
    exit 2
  fi
  run_register_cli "${HOST_PROJ_PATH}"
fi
