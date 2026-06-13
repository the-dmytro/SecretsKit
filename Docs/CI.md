# CI Usage

Preferred mode in CI is `env` or `vault` to avoid creating plaintext files in the workspace.

## Environment provider (example)
```
export SECRETS_PROVIDER=env
export SECRETS_CONFIG_PATH=/path/to/Config/SecretsKit.config.json
export SECRETS_OUTPUT_PATH=${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed
export SECRETS_OBF_KEY_MATERIAL=/path/to/Config/AppObfKey.material

# Secrets as environment variables
export EXAMPLE_API_KEY="..."
export EXAMPLE_CLIENT_ID="..."

${SRCROOT}/Scripts/SecretsKit/secretskit.sh validate
${SRCROOT}/Scripts/SecretsKit/secretskit.sh seal
```

## Vault provider (example)
```
export SECRETS_PROVIDER=vault
export SECRETS_CONFIG_PATH=/path/to/Config/SecretsKit.config.json
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="..."
export SECRETS_VAULT_PATH="kv/apps/your-app"
export SECRETS_OBF_KEY_MATERIAL=/path/to/Config/AppObfKey.material

${SRCROOT}/Scripts/SecretsKit/secretskit.sh validate
${SRCROOT}/Scripts/SecretsKit/secretskit.sh seal
```
