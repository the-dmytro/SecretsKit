# Xcode Integration

## 1) Add SecretsRuntime
Add the package and link `SecretsRuntime` to your iOS/watchOS targets.

## 2) Provide a secrets schema
Create a schema file (committed, no values):
- `Config/Secrets.schema.json`

## 3) Add a non-secret config file (committed)
Create `Config/SecretsKit.config.json` with provider and paths. Example:
```json
{
  "schemaPath": "Secrets.schema.json",
  "provider": "auto",
  "auto": { "order": ["env", "vault", "file"], "allowMerge": false },
  "file": { "sourcePath": "../your-secrets/Secrets.xcconfig" }
}
```

## 4) Add a project-owned runner script
Commit the runner (and optional wrappers) in your project:
```
Scripts/SecretsKit/secretskit.sh
Scripts/SecretsKit/validate_secrets.sh
Scripts/SecretsKit/seal_secrets.sh
```

Your build phases should call the runner or wrappers (not scripts inside the package), e.g.:
```
${SRCROOT}/Scripts/SecretsKit/validate_secrets.sh
${SRCROOT}/Scripts/SecretsKit/seal_secrets.sh
```

The runner sets `SECRETS_CONFIG_PATH` and `SECRETS_OUTPUT_PATH`, then invokes `secretcompiler`.
If you need additional `SECRETS_*` overrides, prefer editing the wrapper scripts to avoid Xcode escaping issues.

## 5) Runtime usage
```swift
import SecretsRuntime

let secrets = try SecretsManager()
let apiKey = secrets.value(for: "EXAMPLE_API_KEY")
```
