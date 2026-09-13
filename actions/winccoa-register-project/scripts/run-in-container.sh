#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ ! -d "/opt/WinCC_OA/${WINCCOA_VERSION}" ]; then
  echo "::error::WinCC OA install not found at /opt/WinCC_OA/${WINCCOA_VERSION}"
  ls -la /opt/WinCC_OA || true
  exit 2
fi
if [ ! -d "${PROJECT_PATH}" ]; then
  echo "::error::Project path does not exist in container: ${PROJECT_PATH}"
  exit 2
fi

# Resolve workspace-relative sub-projects against /workspace.
RESOLVED_SUBS=""
if [ -n "${SUB_PROJECTS:-}" ]; then
  while IFS= read -r sp || [ -n "${sp}" ]; do
    sp="$(printf '%s' "${sp}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "${sp}" ] && continue
    sp="${sp%\"}"
    sp="${sp#\"}"
    if [ -d "/workspace/${sp#./}" ]; then
      sp="/workspace/${sp#./}"
    fi
    RESOLVED_SUBS+="${sp}"$'\n'
  done <<< "${SUB_PROJECTS}"
fi
SUB_PROJECTS="${RESOLVED_SUBS}"
export SUB_PROJECTS

run_register_cli "${PROJECT_PATH}"
