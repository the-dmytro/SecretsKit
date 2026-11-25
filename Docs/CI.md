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

## Compiler provenance in CI
- Use `cli.policy: "locked"` (or `strict`) in `Config/SecretsKit.config.json` so the compiler ref is
  pinned by `Package.resolved`.
- Set `SECRETSKIT_CLI_SHA256` to the SHA-256 of the approved `secretcompiler` binary. Under strict
  policy the runner refuses `SECRETSKIT_CLI_PATH`, `PATH`, cached, and bootstrapped binaries whose
  digest does not match, and auto-bootstrap for `seal`/`validate` requires the digest to be set.
- Do not point `SECRETSKIT_REPO_URL` at untrusted locations.
- Never set `SECRETS_VAULT_ALLOW_INSECURE_HTTP` in CI (it would send `VAULT_TOKEN` over plaintext HTTP).

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
