#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional overrides:
# export SECRETS_CONFIG_PATH="/absolute/or/project/path"
# export SECRETS_OUTPUT_PATH="/path/to/Secrets.sealed"
# export SECRETS_REQUIRED_KEYS="KEY1,KEY2"
# export SECRETS_OBF_KEY_MATERIAL="${SRCROOT}/Config/AppObfKey.material"
# export SECRETSKIT_REQUIRE_CLASSIFICATION=1
# Migration-only fallback:
# export SECRETSKIT_ALLOW_LEGACY_OBF2=1

"${SCRIPT_DIR}/secretskit.sh" seal "$@"
