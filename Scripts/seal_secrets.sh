#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Secret sealing requires a macOS build host."
    exit 1
fi

umask 077

if [ -z "${SECRETS_OUTPUT_PATH:-}" ]; then
    if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
        export SECRETS_OUTPUT_PATH="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed"
    else
        echo "SECRETS_OUTPUT_PATH is required (or set TARGET_BUILD_DIR + UNLOCALIZED_RESOURCES_FOLDER_PATH)."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"

xcrun --sdk macosx swift run --package-path "${PACKAGE_PATH}" --configuration release secretcompiler seal "$@"
