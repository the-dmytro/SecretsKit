# SecretsKit

SecretsKit is a secrets *build-time sealing* + *runtime loading* system for iOS/watchOS projects.

It helps keep secrets **out of the repo** by producing a bundled `Secrets.sealed` file during the build, and reading it in-app at runtime.

## What it is / isn’t
- ✅ Keeps API keys/tokens out of source control and avoids accidental logging/copying during builds.
- ✅ Supports multiple build-time secret sources: `env`, `file`, `vault`, and `auto`.
- ❌ Not a guarantee of secrecy against reverse engineering. Only embed secrets that are safe to ship in a client bundle.

## Components
- **Runtime library**: `SecretsRuntime`
  - Loads `Secrets.sealed` from the app bundle and returns values on demand.
- **Build-time CLI (macOS only)**: `secretcompiler`
  - `validate`: ensures required keys exist and are not placeholders.
  - `seal`: writes `Secrets.sealed` to the app’s resources.
- **Recommended integration**: a **project-owned runner script**
  - Avoids relying on Xcode/DerivedData package checkout paths.
  - Can use a Homebrew-installed CLI (fast-path) or a cached source build (fallback).

## Quick start (Xcode)
1) Add the package:
- Xcode → **File** → **Add Package Dependencies…**
- URL: `https://github.com/the-dmytro/SecretsKit.git`
- Add product `SecretsRuntime` to your iOS/watchOS targets.

2) Add a schema (committed, no secrets):
- `Config/Secrets.schema.json`

3) Add a non-secret config (committed):
- `Config/SecretsKit.config.json`
- Example: `Config/SecretsKit.config.json.example`

4) Copy the runner into your repo:
- Copy `IntegrationTemplates/Scripts/SecretsKit/secretskit.sh` → `Scripts/SecretsKit/secretskit.sh`
- `chmod +x Scripts/SecretsKit/secretskit.sh`

5) Add Xcode build phases (per target):
- **Validate Secrets** (early):
  - `${SRCROOT}/Scripts/SecretsKit/secretskit.sh validate`
- **Seal Secrets** (after resources are staged; commonly Release only):
  - `${SRCROOT}/Scripts/SecretsKit/secretskit.sh seal`

6) Install the tool (once per machine) or use Homebrew:
```
./Scripts/SecretsKit/secretskit.sh install
```

## Providers

### `file`
Reads from a private file (outside the repo):
- `.xcconfig` (`KEY = VALUE`) or `.json`

Config example:
```json
{ "provider": "file", "file": { "sourcePath": "../your-secrets/Secrets.xcconfig" } }
```

### `env`
Reads secrets from environment variables matching schema keys.

CI example:
```
export SECRETS_PROVIDER=env
export EXAMPLE_API_KEY="..."
./Scripts/SecretsKit/secretskit.sh validate
./Scripts/SecretsKit/secretskit.sh seal
```

### `vault`
Reads secrets from HashiCorp Vault KV (v1/v2).

Required env:
- `VAULT_ADDR`, `VAULT_TOKEN`, `SECRETS_VAULT_PATH`

See `Docs/VaultProvider.md`.

### `auto`
Tries providers in order until all *required keys* are satisfied (recommended for mixed local/CI workflows).

## Runtime usage
```swift
import SecretsRuntime

let secrets = try SecretsManager()
let apiKey = secrets.value(for: "EXAMPLE_API_KEY")
```

## Configuration / overrides
Common environment overrides:
- `SECRETS_CONFIG_PATH`
- `SECRETS_PROVIDER` (`env|file|vault|auto`)
- `SECRETS_SOURCE_PATH` (for `file`)
- `SECRETS_OUTPUT_PATH` (for `seal`)

## Security notes
- The CLI never prints secret values.
- Avoid placing plaintext secrets in the repo or DerivedData.
- `Secrets.sealed` is intentionally bundled as a resource (treat it as “client-visible”).

