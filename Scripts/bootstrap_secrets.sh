#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/../Config/Secrets.xcconfig.example"

if [ -z "${SECRETS_SOURCE_PATH:-}" ]; then
    echo "SECRETS_SOURCE_PATH is required to bootstrap local secrets."
    exit 1
fi

if [ ! -f "${TEMPLATE_PATH}" ]; then
    echo "Template not found: ${TEMPLATE_PATH}"
    exit 1
fi

TARGET_DIR="$(dirname "${SECRETS_SOURCE_PATH}")"
mkdir -p "${TARGET_DIR}"

if [ -f "${SECRETS_SOURCE_PATH}" ]; then
    echo "Secrets file already exists: ${SECRETS_SOURCE_PATH}"
    exit 0
fi

cp "${TEMPLATE_PATH}" "${SECRETS_SOURCE_PATH}"
echo "Created secrets file at ${SECRETS_SOURCE_PATH}. Fill in real values."
