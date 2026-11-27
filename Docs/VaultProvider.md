# Vault provider

The `vault` provider supports HashiCorp Vault KV and 1Password. Client bundle
schemas can only seal values allowed by their classifications.
[Server-mediated secrets](ServerMediatedSecrets.md)

## HashiCorp Vault

Omit `vault.backend`, or set it to `hashicorp`, to use Vault KV v1 or v2.

| Setting | Default or requirement |
| --- | --- |
| `VAULT_ADDR` | HTTPS address, such as `https://vault.example.com` |
| `VAULT_TOKEN` | Token with read access to the secret path |
| `SECRETS_VAULT_PATH` | Path relative to the mount, such as `apps/your-app` |
| `VAULT_NAMESPACE` | Optional Vault Enterprise namespace |
| `SECRETS_VAULT_MOUNT` | `secret` |
| `SECRETS_VAULT_KV_VERSION` | `2` |
| `SECRETS_VAULT_TIMEOUT` | 10 seconds, clamped to 1–60 seconds |

With mount `kv` and path `apps/your-app`, KV v2 requests `/v1/kv/data/apps/your-app` and
KV v1 requests `/v1/kv/apps/your-app`. If a path already begins with the mount segments, the
compiler treats it as the full API path after `/v1/`. Mount and path segments are
percent-encoded. Query and fragment delimiters, control characters, relative segments, and
empty interior segments are rejected.

The compiler accepts non-secret defaults such as `vault.addr`, `vault.mount`, and
`vault.path` in the config. It reads the token from the environment and sends it in the
`X-Vault-Token` header. The address rejects embedded credentials, queries, and fragments.
The CLI uses system TLS trust. Plain HTTP is available only with the explicit local
development override `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1`.

In CI, prefer a short-lived token obtained through the job's Vault authentication flow
and scope it to read access on the specific path. [Example config](../Config/SecretsKit.config.json.example)

## 1Password

Install the 1Password CLI (`op`) and enable desktop CLI integration for an
interactive local build. Copy each value's secret reference into the config.
References can use field names or IDs, with an optional section.

```json
{
  "schemaPath": "Secrets.schema.json",
  "provider": "vault",
  "vault": {
    "backend": "1password",
    "references": {
      "APP_TOKEN": "op://Development/Example App/api key"
    }
  }
}
```

The compiler resolves only requested schema keys. It uses PATH, then the
standard Homebrew paths, to locate `op`. `vault.timeoutSeconds` or
`SECRETS_VAULT_TIMEOUT` bounds each lookup (default 30 seconds, range 1–60).
Troubleshoot access in the desktop app and verify that the configured
reference points to a non-empty field. CLI output is private to the compiler.

To pass required server-side values to a process, use
`secretcompiler exec --config ServerSecrets.config.json -- /path/to/server`.
The server config can reference `serverOnly` keys. No sealed bundle is created.
[Secret references](https://www.1password.dev/cli/secret-reference-syntax) ·
[Desktop integration](https://www.1password.dev/cli/app-integration)
