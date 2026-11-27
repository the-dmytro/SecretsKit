# CI setup

Provision an approved macOS `secretcompiler` before injecting secrets. Use `strict` (the
default) or `locked` with an approved SHA-256. The runner checks the digest for explicit, PATH,
cached, and bootstrapped compilers used by the build. Keep source builds on a trusted repository
and a pinned revision. [Compiler setup](RunnerIntegration.md)

## Standalone validate and seal

Run from the consumer project root after installing the runner templates. This example assumes
the sample schema and config. Inject `EXAMPLE_API_KEY` and `EXAMPLE_CLIENT_ID` through the
CI job environment and make the matching key material available to the job.

```sh
export SECRETS_PROVIDER=env
export SECRETS_CONFIG_PATH="$PWD/Config/SecretsKit.config.json"
export SECRETS_OBF_KEY_MATERIAL="$PWD/Config/AppObfKey.material"

./Scripts/SecretsKit/secretskit.sh validate
./Scripts/SecretsKit/secretskit.sh seal --output "$PWD/Secrets.sealed"
```

For an Xcode build, run the validate and seal phases in the target. The runner uses Xcode's
resource directory for the output when `SECRETS_OUTPUT_PATH` is unset. Omit the material
setting if every bundled entry is plaintext. [Xcode setup](XcodeIntegration.md)

## HashiCorp Vault

Use `SECRETS_PROVIDER=vault` with the same runner commands. For a KV v2 mount named `kv`,
set `SECRETS_VAULT_MOUNT=kv` and `SECRETS_VAULT_PATH=apps/your-app`. Configure the HTTPS
address in `VAULT_ADDR` and inject a short-lived read token as `VAULT_TOKEN`. Leave
`SECRETS_VAULT_ALLOW_INSECURE_HTTP` unset in CI. [Vault settings](VaultProvider.md)

## 1Password

On a macOS job, provision SecretsKit 0.5.0 or later and the 1Password CLI.
Commit the [1Password config](VaultProvider.md#1password) with field references.
Use a 1Password service account with read access to the referenced vault and
inject `OP_SERVICE_ACCOUNT_TOKEN` through the CI job's secret store. Use the
same validate and seal commands above with the 1Password config. Remove the
example `SECRETS_PROVIDER=env` override so the config selects `vault`.
[1Password service accounts with the CLI](https://www.1password.dev/service-accounts/use-with-1password-cli)
