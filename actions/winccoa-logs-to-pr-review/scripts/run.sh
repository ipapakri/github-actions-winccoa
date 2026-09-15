#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ -z "${PACKAGE_VERSION:-}" ] || [ "${PACKAGE_VERSION}" = "main" ]; then
  echo "::error::package-version must be a published npm version or dist-tag (not main)"
  exit 2
fi

LOG_ABS="$(resolve_log_path "${LOG_PATH}")"
SUMMARY_REL="${SUMMARY_PATH:-.artifacts/winccoa-log-report.json}"
if [[ "${SUMMARY_REL}" = /* ]]; then
  SUMMARY_ABS="${SUMMARY_REL}"
else
  SUMMARY_ABS="${GITHUB_WORKSPACE:-$(pwd)}/${SUMMARY_REL}"
fi

ensure_node

WORKDIR="$(mktemp -d)"
cd "${WORKDIR}"
npm init -y >/dev/null 2>&1
PKG_SPEC="@winccoa-tools-pack/npm-winccoa-log-reader@${PACKAGE_VERSION}"
echo "Installing ${PKG_SPEC}"
npm install --silent --no-fund --no-audit "${PKG_SPEC}"

PKG_ROOT="${WORKDIR}/node_modules/@winccoa-tools-pack/npm-winccoa-log-reader"
if [ ! -d "${PKG_ROOT}" ]; then
  echo "::error::Failed to install ${PKG_SPEC}"
  exit 2
fi

export LOG_PATH="${LOG_ABS}"
export SUMMARY_PATH="${SUMMARY_ABS}"
export LOG_READER_PKG_ROOT="${PKG_ROOT}"
export IGNORE_OUTSIDE_PR_CHANGES="${IGNORE_OUTSIDE_PR_CHANGES:-false}"
export ANNOTATE_IGNORED="${ANNOTATE_IGNORED:-false}"

echo "Building report from ${LOG_ABS}"
if [ "${IGNORE_OUTSIDE_PR_CHANGES}" = "true" ]; then
  echo "ignore-outside-pr-changes=true (findings outside PR files will be ignored)"
fi

REPORT_OUT="$(node "${SCRIPT_DIR}/build-report.mjs")"
printf '%s\n' "${REPORT_OUT}"

# Parse machine lines from report output
OK_COUNT="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^OK_COUNT=//p' | tail -n1)"
NOK_COUNT="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^NOK_COUNT=//p' | tail -n1)"
FINDING_COUNT="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^FINDING_COUNT=//p' | tail -n1)"
FINDING_COUNT_TOTAL="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^FINDING_COUNT_TOTAL=//p' | tail -n1)"
IGNORED_COUNT="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^IGNORED_COUNT=//p' | tail -n1)"
CHECKED_COUNT="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^CHECKED_COUNT=//p' | tail -n1)"
SUMMARY_FROM_NODE="$(printf '%s\n' "${REPORT_OUT}" | sed -n 's/^SUMMARY_PATH=//p' | tail -n1)"
if [ -n "${SUMMARY_FROM_NODE}" ]; then
  SUMMARY_ABS="${SUMMARY_FROM_NODE}"
fi

OK_COUNT="${OK_COUNT:-0}"
NOK_COUNT="${NOK_COUNT:-0}"
FINDING_COUNT="${FINDING_COUNT:-0}"
FINDING_COUNT_TOTAL="${FINDING_COUNT_TOTAL:-${FINDING_COUNT}}"
IGNORED_COUNT="${IGNORED_COUNT:-0}"
CHECKED_COUNT="${CHECKED_COUNT:-0}"

echo "OK=${OK_COUNT} NOK=${NOK_COUNT} findings=${FINDING_COUNT} total=${FINDING_COUNT_TOTAL} ignored=${IGNORED_COUNT} checked=${CHECKED_COUNT}"
echo "Summary: ${SUMMARY_ABS}"

if [ -f "${SUMMARY_ABS}" ]; then
  echo "--- summary-json-begin ---"
  cat "${SUMMARY_ABS}"
  echo ""
  echo "--- summary-json-end ---"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "ok-count=${OK_COUNT}"
    echo "nok-count=${NOK_COUNT}"
    echo "finding-count=${FINDING_COUNT}"
    echo "finding-count-total=${FINDING_COUNT_TOTAL}"
    echo "ignored-count=${IGNORED_COUNT}"
    echo "checked-count=${CHECKED_COUNT}"
    echo "summary-path=${SUMMARY_ABS}"
  } >> "${GITHUB_OUTPUT}"
fi

export SUMMARY_PATH="${SUMMARY_ABS}"
if [ "${COMMENT_ON_PR:-true}" = "true" ] || [ "${REVIEW_COMMENTS:-false}" = "true" ]; then
  node "${SCRIPT_DIR}/post-pr.mjs"
fi

# Fail only on active (non-ignored) findings
if [ "${FAIL_ON_FINDINGS:-false}" = "true" ] && [ "${FINDING_COUNT}" -gt 0 ]; then
  echo "::error::Failing due to ${FINDING_COUNT} active log finding(s) (NOK files: ${NOK_COUNT}; ignored: ${IGNORED_COUNT})"
  exit 1
fi

if [ "${IGNORE_OUTSIDE_PR_CHANGES}" = "true" ] && [ "${IGNORED_COUNT}" -gt 0 ] && [ "${FINDING_COUNT}" -eq 0 ]; then
  echo "All ${IGNORED_COUNT} finding(s) were outside PR changes and were ignored."
fi