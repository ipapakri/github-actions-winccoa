#!/usr/bin/env bash
set -euo pipefail

if [ -n "${SCRIPT_PATH:-}" ]; then
  SCRIPT_ABS="${GITHUB_WORKSPACE}/${SCRIPT_PATH#./}"
  if [ ! -f "${SCRIPT_ABS}" ]; then
    echo "::error::Missing script ${SCRIPT_PATH}"
    exit 2
  fi
fi

if [ -z "${SOURCE_PATHS// }" ]; then
  echo "::error::source-paths must not be empty"
  exit 2
fi

mkdir -p "${GITHUB_WORKSPACE}/.artifacts"
REPORT="${GITHUB_WORKSPACE}/.artifacts/ctrl-copyright-check.txt"
: > "${REPORT}"

# Build normalized blacklist of repo-relative paths.
BLACKLIST_FILE="$(mktemp)"
printf '%s\n' "${BLACKLIST:-}" \
  | tr '\r' '\n' \
  | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | awk 'NF { print }' \
  | sed -e 's#^\./##' \
  > "${BLACKLIST_FILE}"

is_blacklisted() {
  local rel="$1"
  [ ! -s "${BLACKLIST_FILE}" ] && return 1
  grep -Fxq -- "${rel}" "${BLACKLIST_FILE}"
}

rc=0
skipped=0
scanned=0
while IFS= read -r -d '' file; do
  rel="${file#${GITHUB_WORKSPACE}/}"
  rel="${rel#./}"
  scanned=$((scanned + 1))

  if is_blacklisted "${rel}"; then
    echo "SKIPPED-BLACKLIST: ${rel}" >> "${REPORT}"
    skipped=$((skipped + 1))
    continue
  fi

  if ! grep -Eq "@copyright|Copyright" "${file}"; then
    echo "MISSING-COPYRIGHT: ${rel}" >> "${REPORT}"
    rc=1
  fi

  if grep -Eq "SPDX-License-Identifier:[[:space:]]*GPL-3.0-only" "${file}"; then
    echo "WRONG-SPDX: ${rel}" >> "${REPORT}"
    rc=1
  fi

  if grep -Eiq "Copyright [0-9]{4} SIEMENS AG" "${file}"; then
    echo "WRONG-OWNER: ${rel}" >> "${REPORT}"
    rc=1
  fi
done < <(
  for rel in ${SOURCE_PATHS}; do
    base="${GITHUB_WORKSPACE}/${rel#./}"
    [ -d "${base}" ] || continue
    find "${base}" -type f -name "*.ctl" -print0
  done
)

rm -f "${BLACKLIST_FILE}"

echo "Scanned ${scanned} CTL file(s); skipped ${skipped} blacklisted file(s)."

if [ "${rc}" -ne 0 ]; then
  echo "::error::Copyright/license mismatches found."
  cat "${REPORT}"
  exit 1
fi

echo "Copyright and SPDX checks passed."
if [ -s "${REPORT}" ]; then
  cat "${REPORT}"
fi
