#!/usr/bin/env bash
# Shared helpers for winccoa-docu-builder action scripts.

normalize_rel_path() {
  local p="${1#./}"
  if [ -z "${p}" ]; then
    p="."
  fi
  printf '%s' "${p}"
}

normalize_langs() {
  printf '%s\n' "$1" | tr '\n' ' ' | xargs | tr ' ' ','
}

resolve_company_name() {
  local input="${1:-}"
  if [ -n "${input}" ]; then
    printf '%s' "${input}"
    return 0
  fi
  local repo_full="${GITHUB_REPOSITORY:-}"
  local org_name="${repo_full%%/*}"
  local repo_name="${repo_full##*/}"
  if [ -n "${org_name}" ] && [ "${org_name}" != "${repo_full}" ]; then
    printf '%s' "${org_name}"
  elif [ -n "${repo_name}" ]; then
    printf '%s' "${repo_name}"
  else
    printf '%s' "WinCC OA community"
  fi
}

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

ensure_doxygen() {
  if [ "${INSTALL_DOXYGEN:-true}" != "true" ]; then
    echo "Skipping doxygen/graphviz install (install-doxygen=false)"
    return 0
  fi
  if command -v doxygen >/dev/null 2>&1; then
    echo "Using existing doxygen $(doxygen --version 2>/dev/null || true)"
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing doxygen and graphviz"
    apt-get update -qq
    apt-get --assume-yes install -f doxygen graphviz
  else
    echo "::warning::apt-get not available; assuming doxygen and graphviz are preinstalled"
  fi
}

# Run winccoa-docu-builder against a worker project path in the current environment.
run_docu_cli() {
  local project_path="$1"
  local company_name="$2"

  # Prefer absolute paths for WCCOActrl -config reliability.
  if command -v realpath >/dev/null 2>&1; then
    project_path="$(realpath "${project_path}")"
  else
    project_path="$(cd "${project_path}" && pwd -P)"
  fi

  ensure_doxygen
  ensure_node
  local workdir
  workdir="$(mktemp -d)"
  cd "${workdir}"
  npm init -y >/dev/null 2>&1
  echo "Installing ${PKG_SPEC}"
  npm install --silent --no-fund --no-audit "${PKG_SPEC}"

  local pkg_root="${workdir}/node_modules/@winccoa-tools-pack/npm-winccoa-docu-builder"
  # Git installs may land under a different folder name; resolve via package name.
  if [ ! -d "${pkg_root}" ]; then
    pkg_root="$(node -p "try{require('path').dirname(require.resolve('@winccoa-tools-pack/npm-winccoa-docu-builder/package.json'))}catch(e){''}" 2>/dev/null || true)"
  fi
  if [ -z "${pkg_root}" ] || [ ! -d "${pkg_root}" ]; then
    echo "::error::Could not locate installed @winccoa-tools-pack/npm-winccoa-docu-builder under ${workdir}"
    find "${workdir}/node_modules" -maxdepth 3 -type d 2>/dev/null || true
    exit 2
  fi

  local entry="${pkg_root}/dist/cjs/cli.js"
  if [ ! -f "${entry}" ]; then
    echo "dist/cjs/cli.js missing (likely git install); building package in place"
    (
      cd "${pkg_root}"
      npm install --silent --no-fund --no-audit --include=dev
      npm run build
    )
  fi
  if [ ! -f "${entry}" ]; then
    echo "::error::Missing CLI entry ${entry} after build"
    ls -la "${pkg_root}" || true
    ls -la "${pkg_root}/dist" || true
    exit 2
  fi

  local langs
  langs="$(normalize_langs "${LANGUAGES:-en_US.utf8}")"
  if [ -z "${langs}" ]; then
    echo "::error::languages resolved to an empty list"
    exit 2
  fi

  local args=(
    build
    "${project_path}"
    -v "${OA_VERSION}"
    -c "${company_name}"
    --langs "${langs}"
    -t "${TIMEOUT_MS}"
  )

  if [ "${REGISTER_PROJECT:-true}" != "true" ]; then
    args+=(--no-register)
  fi

  echo "Running: node ${entry} ${args[*]}"
  node "${entry}" "${args[@]}"
}

extract_and_annotate_warnings() {
  local project_path_norm="$1"
  local output_text="$2"
  local warning_file="$3"

  mkdir -p "$(dirname "${warning_file}")"

  local log_dir="${project_path_norm}/log"
  local doxygen_stderr="${log_dir}/doxygen_stdErr.txt"
  local doxygen_stdout="${log_dir}/doxygen_stdOut.txt"
  # Preferred durable path when advanced config sets WARN_LOGFILE via $PROJ_PATH.
  local doxygen_warn_logfile="${log_dir}/doxygen_warn_logfile.txt"
  local warning_pattern='[Ww]arning:|\bWARNING\b|\bSEVERE\b|\bFATAL\b'
  local warning_source=""

  : > "${warning_file}"

  collect_warnings_from() {
    local src="$1"
    local label="$2"
    if [ ! -f "${src}" ]; then
      return 1
    fi
    local total
    total="$(wc -l < "${src}" | tr -d '[:space:]')"
    local preview=120
    echo "::notice::Found ${label} at ${src} (${total} lines)"
    echo "::group::${label} preview (${total} lines total, showing up to ${preview})"
    sed -n "1,${preview}p" "${src}" || true
    if [ "${total}" -gt "${preview}" ]; then
      echo "... truncated ..."
    fi
    echo "::endgroup::"
    grep -E "${warning_pattern}" "${src}" > "${warning_file}" || true
    if [ -s "${warning_file}" ]; then
      warning_source="${src}"
      return 0
    fi
    # Non-empty WARN_LOGFILE with no pattern match still counts as the warning source
    # (doxygen often writes plain warning lines without a WARNING token).
    if [ "${label}" = "doxygen WARN_LOGFILE" ] && [ -s "${src}" ]; then
      cp -f "${src}" "${warning_file}" || true
      warning_source="${src}"
      return 0
    fi
    return 1
  }

  # Prefer WARN_LOGFILE (advanced config), then OA stderr capture, then stdout, then process output.
  if ! collect_warnings_from "${doxygen_warn_logfile}" "doxygen WARN_LOGFILE"; then
    if ! collect_warnings_from "${doxygen_stderr}" "doxygen stderr log"; then
      if ! collect_warnings_from "${doxygen_stdout}" "doxygen stdout log"; then
        printf '%s\n' "${output_text}" | grep -E "${warning_pattern}" > "${warning_file}" || true
        if [ -s "${warning_file}" ]; then
          warning_source="process-output"
          echo "::notice::Extracted warnings from process output fallback"
        fi
      fi
    fi
  fi

  if [ -n "${warning_source}" ]; then
    echo "::notice::Warning source selected: ${warning_source}"
  else
    echo "::notice::No doxygen warning lines found in WARN_LOGFILE/stderr/stdout/process output"
  fi

  if [ -f "${doxygen_stdout}" ] && [ "${warning_source}" != "${doxygen_stdout}" ]; then
    echo "::notice::Found doxygen stdout log at ${doxygen_stdout}"
  fi

  # Stage doxygen configs and warn logfile next to warning/log artifacts.
  # OA writes the merged config to data/projectDocu/doxygenConfig.txt and may
  # append advanced_doxygenConfig.txt when GlobalStorage doxygen/advancedConfig=1.
  local project_docu="${project_path_norm}/data/projectDocu"
  local artifact_dir
  artifact_dir="$(dirname "${warning_file}")"
  mkdir -p "${artifact_dir}"
  if [ -f "${project_docu}/advanced_doxygenConfig.txt" ]; then
    cp -f "${project_docu}/advanced_doxygenConfig.txt" \
      "${artifact_dir}/advanced_doxygenConfig.txt" || true
    echo "::notice::Staged advanced doxygen config at ${artifact_dir}/advanced_doxygenConfig.txt"
  else
    echo "::warning::advanced_doxygenConfig.txt not found under ${project_docu}"
  fi
  if [ -f "${project_docu}/doxygenConfig.txt" ]; then
    cp -f "${project_docu}/doxygenConfig.txt" \
      "${artifact_dir}/doxygenConfig.txt" || true
    echo "::notice::Staged merged doxygen config at ${artifact_dir}/doxygenConfig.txt"
  else
    echo "::warning::Merged doxygenConfig.txt not found under ${project_docu} (docs build may not have written it)"
  fi
  if [ -f "${doxygen_warn_logfile}" ]; then
    cp -f "${doxygen_warn_logfile}" \
      "${artifact_dir}/doxygen_warn_logfile.txt" || true
    echo "::notice::Staged WARN_LOGFILE at ${artifact_dir}/doxygen_warn_logfile.txt"
  fi

  local warning_count
  warning_count="$(wc -l < "${warning_file}" | tr -d '[:space:]')"
  if [ -z "${warning_count}" ]; then
    warning_count=0
  fi

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "warning-count=${warning_count}"
      echo "warning-file=${warning_file}"
    } >> "${GITHUB_OUTPUT}"
  fi

  if ! [[ "${MAX_WARNING_COUNT:-}" =~ ^-?[0-9]+$ ]]; then
    echo "::error::Invalid max-warning-count value '${MAX_WARNING_COUNT}'. Use an integer, e.g. -1, 0, 10."
    return 2
  fi

  if [ "${ANNOTATE_WARNINGS:-true}" = "true" ] && [ -f "${warning_file}" ]; then
    local annotation_count=0
    local truncated=0
    while IFS= read -r warning_line; do
      [ -z "${warning_line}" ] && continue
      if [ "${annotation_count}" -ge "${MAX_ANNOTATIONS:-200}" ]; then
        truncated=1
        break
      fi

      local file_path="" line_no="" col_no="" message=""
      if [[ "${warning_line}" =~ ^([^:]+):([0-9]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
        file_path="${BASH_REMATCH[1]#/workspace/}"
        line_no="${BASH_REMATCH[2]}"
        col_no="${BASH_REMATCH[3]}"
        message="${BASH_REMATCH[4]}"
      elif [[ "${warning_line}" =~ ^([^:]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
        file_path="${BASH_REMATCH[1]#/workspace/}"
        line_no="${BASH_REMATCH[2]}"
        message="${BASH_REMATCH[3]}"
      else
        message="${warning_line}"
      fi

      message="${message//'%'/'%25'}"
      message="${message//$'\r'/'%0D'}"
      message="${message//$'\n'/'%0A'}"

      if [ -n "${file_path}" ] && [ -n "${line_no}" ] && [ -n "${col_no}" ]; then
        echo "::warning file=${file_path},line=${line_no},col=${col_no}::${message}"
      elif [ -n "${file_path}" ] && [ -n "${line_no}" ]; then
        echo "::warning file=${file_path},line=${line_no}::${message}"
      else
        echo "::warning::${message}"
      fi
      annotation_count=$((annotation_count + 1))
    done < "${warning_file}"

    if [ "${truncated}" -eq 1 ]; then
      echo "::notice::Warning annotations truncated at ${MAX_ANNOTATIONS} items"
    fi
  fi

  if [ "${MAX_WARNING_COUNT}" -ge 0 ] && [ "${warning_count}" -gt "${MAX_WARNING_COUNT}" ]; then
    echo "::error::Doxygen warning count ${warning_count} exceeds configured max-warning-count ${MAX_WARNING_COUNT}"
    return 3
  fi

  return 0
}
