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
Commit a runner script in your project (recommended):
```
Scripts/SecretsKit/secretskit.sh
```

Your build phases should call the runner (not scripts inside the package), e.g.:
```
${SRCROOT}/Scripts/SecretsKit/secretskit.sh validate
${SRCROOT}/Scripts/SecretsKit/secretskit.sh seal
```

The runner sets `SECRETS_CONFIG_PATH` and `SECRETS_OUTPUT_PATH`, then invokes `secretcompiler`.

## 5) Runtime usage
```swift
import SecretsRuntime

let secrets = try SecretsManager()
let apiKey = secrets.value(for: "EXAMPLE_API_KEY")
```
