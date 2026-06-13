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
- `VAULT_ADDR` must be `https` unless `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1` is set for local
  development.
- Mount and path are treated as path segments: query delimiters, fragments, control characters,
  relative segments, and empty segments are rejected; valid characters that need escaping are
  percent-encoded.

## Short-lived credentials (recommended)
Prefer CI-native, short-lived Vault auth (e.g. OIDC/JWT) over a long-lived `VAULT_TOKEN` kept in a
shell profile. Scope the policy to read-only on the specific path with a short TTL.

## Scope: client-bundled values only
The `vault` provider feeds the build-time bundle, so only point it at `public`/`clientBundled` values.
A `serverOnly` secret must never reach `Secrets.sealed` (the build refuses it) — read those from Vault
on your **backend** at request time instead. See [`ServerMediatedSecrets.md`](ServerMediatedSecrets.md).
