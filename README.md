# SecretsKit

SecretsKit bundles build-time values for iOS and watchOS apps. The compiler reads from an
`env`, `file`, `vault`, or `auto` provider and writes `Secrets.sealed`. The app reads that
file at runtime, so you can keep the original values out of source control.

## Key classification
Use `classification` in the schema to control how each key ships.

- `public` ships as plaintext by default. Use it for values such as a published client ID.
- `clientBundled` ships obfuscated by default and also applies to unclassified keys.
- `serverOnly` stays out of the bundle. The compiler rejects attempts to include it through
  `--required-keys` or `SECRETS_REQUIRED_KEYS`. Keep operations that need these secrets on
  your backend. [Server-mediated secrets](Docs/ServerMediatedSecrets.md)

`seal` prints key names and their classifications. Pass `--require-classification` to fail on
unclassified keys processed by the command. For a schema containing only `serverOnly` keys, the
compiler writes an empty `OBF3` resource without contacting a provider.

```json
{
  "keys": {
    "EXAMPLE_CLIENT_ID": { "classification": "public" },
    "EXAMPLE_API_KEY":    { "classification": "clientBundled" },
    "EXAMPLE_SERVER_TOKEN": { "classification": "serverOnly" }
  }
}
```

## Components

`SecretsRuntime` loads `Secrets.sealed` from the app bundle and returns values on demand.
The `secretcompiler` CLI runs on macOS.

- `validate` checks required keys for missing and placeholder values.
- `seal` writes `Secrets.sealed` to the app's resources.
- `generate-key` creates the Swift key and the matching material used during sealing.

Keep a copy of the runner script in your project so Xcode build phases can use a stable path
outside DerivedData. The runner looks for the compiler at an explicit path, on `PATH`, or in
its source-build cache.

## Platform requirements
- iOS 14+
- watchOS 7+
- macOS 11+

## Quick start (Xcode)

1. In Xcode, choose **File → Add Package Dependencies…** and enter
   `https://github.com/the-dmytro/SecretsKit.git`. Add the `SecretsRuntime` product to your app targets.
2. Create `Config/Secrets.schema.json` with your key names and classifications.
   [Example schema](Config/Secrets.schema.json)
3. Create `Config/SecretsKit.config.json` with your provider settings. Commit the schema and
   config without secret values. [Example config](Config/SecretsKit.config.json.example)
4. Copy the runner templates into `Scripts/SecretsKit/` in your project and run
   `chmod +x Scripts/SecretsKit/*.sh`. Add the ignore entries to your project's
   `.gitignore`. [Runner templates](IntegrationTemplates/Scripts/SecretsKit) ·
   [Ignore entries](IntegrationTemplates/README.md#keep-secrets-out-of-source-control)
5. Use an approved compiler. To build one on macOS, run
   `swift build -c release --product secretcompiler` from a trusted SecretsKit checkout. Find the
   binary at `$(swift build -c release --show-bin-path)/secretcompiler`. Set its absolute path and
   approved SHA-256 in the wrappers or build environment for Xcode and CI. Export the same
   settings in your terminal before running the next step.

   ```sh
   export SECRETSKIT_CLI_PATH="/absolute/path/to/secretcompiler"
   export SECRETSKIT_CLI_SHA256="<approved SHA-256>"
   ```

   The default `strict` policy and its `locked` alias check the digest for compilers selected by
   path, found on `PATH`, or loaded from the cache. Auto-bootstrap during `seal` or `validate`
   requires a digest too, and the runner checks it after the build. With either policy,
   `secretskit.sh install` can read the SecretsKit revision from Xcode's `Package.resolved`.
   If you set `SECRETSKIT_CLI_REF`, use the same value for install and the build phases.
   `seal` and `validate` never fall back to `main`. Build the compiler
   before injecting secrets into CI.
   [Runner integration](Docs/RunnerIntegration.md) · [CI setup](Docs/CI.md)

6. If you bundle obfuscated entries, generate the obfuscation key once per app from your project root.

   ```sh
   "$SECRETSKIT_CLI_PATH" generate-key \
     --symbol AppObfKey \
     --swift-output Sources/Generated/AppObfKey.swift \
     --material-output Config/AppObfKey.material
   ```

   Add the Swift file to your app target. Keep the matching `.material` file out of source control
   and make it available locally and in CI. In the seal wrapper, export
   `SECRETS_OBF_KEY_MATERIAL="${SRCROOT}/Config/AppObfKey.material"` or pass the file with
   `--key-material`.

7. Add a **Validate Secrets** build phase early and a **Seal Secrets** phase after Xcode stages
   resources. Quote the paths to support project directories containing spaces.

   ```sh
   "${SRCROOT}/Scripts/SecretsKit/validate_secrets.sh"
   "${SRCROOT}/Scripts/SecretsKit/seal_secrets.sh"
   ```

## Providers

### `file`
Reads a private `.xcconfig` (`KEY = VALUE`) or JSON file. The compiler resolves a relative
`sourcePath` from the directory that contains the config. Keep the input file out of source control.
`Scripts/bootstrap_secrets.sh` creates a local `.xcconfig` with owner-only permissions at
`SECRETS_SOURCE_PATH`.

```json
{ "provider": "file", "file": { "sourcePath": "../../your-secrets/Secrets.xcconfig" } }
```

### `env`
Set an environment variable for each client value, using the key from the schema as its name.
In CI, use the compiler pin from the quick start and supply the matching `.material` file if
you seal obfuscated entries.

```sh
export SECRETS_PROVIDER=env
./Scripts/SecretsKit/secretskit.sh validate
./Scripts/SecretsKit/secretskit.sh seal --output "$PWD/Secrets.sealed"
```

### `vault`
Reads secrets from HashiCorp Vault KV (v1/v2). Use an HTTPS `VAULT_ADDR` without embedded
credentials, supply the token through `VAULT_TOKEN`, and set `SECRETS_VAULT_PATH`.
[Vault configuration](Docs/VaultProvider.md)

### `auto`
Tries providers in order until it finds one with every required key. Use it when local builds and
CI pull values from different providers.

## Runtime usage
```swift
import SecretsRuntime

// Pass the obfuscation key compiled into your app (generated by `secretcompiler generate-key`).
let secrets = try SecretsManager(obfuscationKey: AppObfKey.obfuscationKey)
let apiKey = try secrets.requiredValue(for: "EXAMPLE_API_KEY")
// or, to handle absence without throwing:
let optionalKey = secrets.optionalValue(for: "EXAMPLE_API_KEY")
```

An `OBF3` file can contain both plaintext and obfuscated entries. For obfuscated entries,
`seal` uses the `.material` file and the runtime uses the matching key compiled into the app.
Plaintext-only bundles can use `SecretsManager()` without a key. The runtime can still read legacy
`OBF2` files. To seal obfuscated entries as `OBF2` for migration, omit the key material and
pass `--legacy-obf2` or set `SECRETSKIT_ALLOW_LEGACY_OBF2=1`.

## Configuration overrides

- `SECRETS_CONFIG_PATH`
- `SECRETS_PROVIDER` (`env|file|vault|auto`)
- `SECRETS_SOURCE_PATH` (for `file`)
- `SECRETS_OUTPUT_PATH` (for `seal`)
- `SECRETS_OBF_KEY_MATERIAL` (for `OBF3` seal)
- `SECRETS_PLACEHOLDER_REGEX` or `--placeholder-regex` for a custom pattern. An invalid pattern
  fails the placeholder check.
- `SECRETSKIT_REQUIRE_CLASSIFICATION=1` (fail on keys without `classification`)
- `SECRETSKIT_ALLOW_LEGACY_OBF2=1` (migration-only fallback)

## Security notes
- Keep plaintext inputs out of the repository and DerivedData. The compiler writes sealed output
  and generated `.material` files with owner-only (`0600`) permissions.
- Ship only values you can expose. Anyone inspecting the app can recover obfuscated values from
  `Secrets.sealed` using the key compiled into the app.
- The threat model and roadmap describe the remaining risks and planned changes.
  [`Docs/ImprovementPlan/`](Docs/ImprovementPlan/README.md)

## Local tests

Run `swift test` from the SecretsKit repository root on macOS.
