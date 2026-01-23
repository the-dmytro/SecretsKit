#!/bin/bash
set -euo pipefail

COMMAND="${1:-}"
if [ -n "${COMMAND}" ]; then
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use SRCROOT (set by Xcode) as primary source, fallback to script-relative calculation
if [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}" ]; then
  PROJECT_ROOT="${SRCROOT}"
else
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  echo "SecretsKit: $*" >&2
}

config_value() {
  local key="${1:-}"
  if [ -z "${SECRETS_CONFIG_PATH:-}" ] || [ ! -f "${SECRETS_CONFIG_PATH}" ]; then
    echo ""
    return 0
  fi
  /usr/bin/python3 - "${SECRETS_CONFIG_PATH}" "${key}" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("")
    sys.exit(0)

current = data
for part in key.split("."):
    if isinstance(current, dict) and part in current:
        current = current[part]
    else:
        current = None
        break

if isinstance(current, list):
    print(",".join(str(item) for item in current))
elif current is None:
    print("")
else:
    print(str(current))
PY
}

find_package_resolved() {
  local found
  found="$(find "${PROJECT_ROOT}" -maxdepth 6 -path "*/xcshareddata/swiftpm/Package.resolved" -print -quit 2>/dev/null || true)"
  if [ -n "${found}" ]; then
    echo "${found}"
    return 0
  fi
  return 1
}

resolve_ref_from_package_resolved() {
  local resolved_path
  resolved_path="$(find_package_resolved || true)"
  if [ -z "${resolved_path}" ]; then
    echo ""
    return 1
  fi
  /usr/bin/python3 - "${resolved_path}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

pins = data.get("pins") or data.get("object", {}).get("pins") or []
for pin in pins:
    identity = (pin.get("identity") or pin.get("package") or "").lower()
    location = (pin.get("location") or "").lower()
    if identity == "secretskit" or location.endswith("/secretskit.git"):
        state = pin.get("state", {})
        for key in ("revision", "version", "branch"):
            if state.get(key):
                print(state[key])
                sys.exit(0)
print("")
PY
}

version_ge() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import sys

def parse(v):
    parts = [p for p in v.strip().split(".") if p]
    values = []
    for part in parts:
        try:
            values.append(int(part))
        except ValueError:
            values.append(0)
    return values

left = parse(sys.argv[1])
right = parse(sys.argv[2])
length = max(len(left), len(right))
left += [0] * (length - len(left))
right += [0] * (length - len(right))
print("1" if left >= right else "0")
PY
}

read_cli_version() {
  local cli="$1"
  local output
  output="$("${cli}" version --json 2>/dev/null || true)"
  if [ -n "${output}" ]; then
    /usr/bin/python3 - "${output}" <<'PY'
import json
import sys
try:
    data = json.loads(sys.argv[1])
    print(data.get("version", ""))
except Exception:
    print("")
PY
    return 0
  fi
  output="$("${cli}" version 2>/dev/null || true)"
  echo "${output##* }"
}

resolve_cli_ref() {
  if [ -n "${SECRETSKIT_CLI_REF:-}" ]; then
    echo "${SECRETSKIT_CLI_REF}"
    return 0
  fi
  if [ "${SECRETSKIT_CLI_POLICY:-}" = "locked" ] || [ "${CLI_POLICY:-}" = "locked" ]; then
    local ref
    ref="$(resolve_ref_from_package_resolved || true)"
    if [ -n "${ref}" ]; then
      echo "${ref}"
      return 0
    fi
    return 1
  fi
  echo "${SECRETSKIT_CLI_REF_FALLBACK:-main}"
}

resolve_cached_cli() {
  local ref="$1"
  local cache_root="${SECRETSKIT_CACHE_DIR:-${PROJECT_ROOT}/.tools/secretskit}"
  local candidate="${cache_root}/${ref}/secretcompiler"
  if [ -x "${candidate}" ]; then
    echo "${candidate}"
    return 0
  fi
  return 1
}

bootstrap_cli() {
  if [ "$(uname -s)" != "Darwin" ]; then
    die "Secret compiler build requires macOS."
  fi

  local ref
  ref="$(resolve_cli_ref || true)"
  if [ -z "${ref}" ]; then
    die "Unable to resolve SecretsKit ref. Set SECRETSKIT_CLI_REF or ensure Package.resolved is available."
  fi

  local cache_root="${SECRETSKIT_CACHE_DIR:-${PROJECT_ROOT}/.tools/secretskit}"
  local target_dir="${cache_root}/${ref}"
  local src_dir="${target_dir}/src"
  local bin_path="${target_dir}/secretcompiler"
  local repo_url="${SECRETSKIT_REPO_URL:-https://github.com/the-dmytro/SecretsKit.git}"

  if [ -x "${bin_path}" ]; then
    echo "${bin_path}"
    return 0
  fi

  mkdir -p "${target_dir}"
  if [ ! -d "${src_dir}/.git" ]; then
    git clone "${repo_url}" "${src_dir}"
  fi

  (
    cd "${src_dir}"
    git fetch --tags origin
    git fetch origin "${ref}" || true
    git checkout "${ref}"
  )

  local build_bin_dir
  build_bin_dir="$(cd "${src_dir}" && xcrun --sdk macosx swift build -c release --product secretcompiler >/dev/null && xcrun --sdk macosx swift build -c release --show-bin-path)"
  cp "${build_bin_dir}/secretcompiler" "${bin_path}"
  chmod 755 "${bin_path}"

  echo "${bin_path}"
}

resolve_cli() {
  if [ -n "${SECRETSKIT_CLI_PATH:-}" ] && [ -x "${SECRETSKIT_CLI_PATH}" ]; then
    echo "${SECRETSKIT_CLI_PATH}"
    return 0
  fi

  if command -v secretcompiler >/dev/null 2>&1; then
    command -v secretcompiler
    return 0
  fi

  local ref
  ref="$(resolve_cli_ref || true)"
  if [ -n "${ref}" ]; then
    resolve_cached_cli "${ref}" || true
  fi
}

ensure_cli_available() {
  local cli
  cli="$(resolve_cli || true)"
  if [ -n "${cli}" ] && [ -x "${cli}" ]; then
    echo "${cli}"
    return 0
  fi

  if [ "${SECRETSKIT_AUTO_BOOTSTRAP:-}" = "1" ] || [ "${COMMAND}" = "install" ]; then
    bootstrap_cli
    return 0
  fi

  die "secretcompiler not found. Run '${SCRIPT_DIR}/secretskit.sh install' or install via Homebrew."
}

check_cli_policy() {
  local cli="$1"
  local ref="$2"

  local min_version="${SECRETSKIT_MIN_VERSION:-}"
  if [ -z "${min_version}" ]; then
    min_version="$(config_value cli.minVersion)"
  fi

  local policy="${SECRETSKIT_CLI_POLICY:-}"
  if [ -z "${policy}" ]; then
    policy="$(config_value cli.policy)"
  fi
  policy="${policy:-compatible}"

  local cli_version
  cli_version="$(read_cli_version "${cli}")"

  if [ "${policy}" = "locked" ] && [ -n "${ref}" ]; then
    if [[ "${ref}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] && [ -n "${cli_version}" ]; then
      if [ "${cli_version}" != "${ref}" ]; then
        die "secretcompiler version ${cli_version} does not match locked ref ${ref}."
      fi
    fi
  fi

  if [ -n "${min_version}" ] && [ -n "${cli_version}" ]; then
    if [ "$(version_ge "${cli_version}" "${min_version}")" != "1" ]; then
      die "secretcompiler version ${cli_version} is below required minimum ${min_version}."
    fi
  fi
}

if [ -z "${COMMAND}" ]; then
  die "Usage: secretskit.sh <validate|seal|install> [args...]"
fi

CONFIG_PATH_DEFAULT="${PROJECT_ROOT}/Config/SecretsKit.config.json"
export SECRETS_CONFIG_PATH="${SECRETS_CONFIG_PATH:-${CONFIG_PATH_DEFAULT}}"

CLI_POLICY="${SECRETSKIT_CLI_POLICY:-}"
if [ -z "${CLI_POLICY}" ]; then
  CLI_POLICY="$(config_value cli.policy)"
fi
CLI_POLICY="${CLI_POLICY:-compatible}"

if [ "${COMMAND}" = "install" ]; then
  ensure_cli_available >/dev/null
  log "secretcompiler installed."
  exit 0
fi

if [ ! -f "${SECRETS_CONFIG_PATH}" ]; then
  die "SecretsKit config not found at ${SECRETS_CONFIG_PATH}"
fi

if [ "${COMMAND}" = "seal" ]; then
  if [ -z "${SECRETS_OUTPUT_PATH:-}" ] && [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    export SECRETS_OUTPUT_PATH="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed"
  fi
fi

CLI_PATH="$(ensure_cli_available)"
CLI_REF="$(resolve_cli_ref || true)"
check_cli_policy "${CLI_PATH}" "${CLI_REF}"

if [ "${COMMAND}" = "validate" ] || [ "${COMMAND}" = "seal" ]; then
  "${CLI_PATH}" "${COMMAND}" --config "${SECRETS_CONFIG_PATH}" "$@"
  exit 0
fi

die "Unsupported command: ${COMMAND}"
