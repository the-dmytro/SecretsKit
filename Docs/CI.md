# CI Usage

Preferred mode in CI is `env` or `vault` to avoid creating plaintext files in the workspace.

## Environment provider (example)
```
export SECRETS_SCHEMA_PATH=/path/to/Secrets.schema.json
export SECRETS_PROVIDER=env
export SECRETS_OUTPUT_PATH=${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed

# Secrets as environment variables
export EXAMPLE_API_KEY="..."
export EXAMPLE_CLIENT_ID="..."

${PATH_TO_SECRETSKIT}/Scripts/validate_secrets.sh
${PATH_TO_SECRETSKIT}/Scripts/seal_secrets.sh
```

## Vault provider
`SECRETS_PROVIDER=vault` is a placeholder for a future implementation.
