#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Secrets validation requires a macOS build host."
    exit 1
fi

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"

xcrun --sdk macosx swift run --package-path "${PACKAGE_PATH}" --configuration release secretcompiler validate "$@"
