#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional overrides:
# export SECRETS_CONFIG_PATH="/absolute/or/project/path"
# export SECRETS_REQUIRED_KEYS="KEY1,KEY2"

"${SCRIPT_DIR}/secretskit.sh" validate "$@"
