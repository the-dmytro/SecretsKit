# Vault Provider

SecretsKit supports HashiCorp Vault KV v1/v2 for build-time secrets.

## Required environment
- `VAULT_ADDR` (e.g. `https://vault.example.com`)
- `VAULT_TOKEN` (token with read access)
- `SECRETS_VAULT_PATH` (path to the secret)

## Optional environment
- `VAULT_NAMESPACE` (enterprise namespaces)
- `SECRETS_VAULT_MOUNT` (default: `secret`)
- `SECRETS_VAULT_KV_VERSION` (default: `2`)
- `SECRETS_VAULT_TIMEOUT` (seconds, default: `10`)

## Notes
- Values are read in-memory only.
- The CLI never prints secret values in logs.
