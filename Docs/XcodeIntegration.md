# Xcode Integration

## 1) Add SecretsRuntime
Add the package and link `SecretsRuntime` to your iOS/watchOS targets.

## 2) Provide a secrets schema
Create a schema file (committed, no values):
- `Config/Secrets.schema.json`

## 3) Provide secrets (outside the repo)
For local development, keep secrets in a private `.xcconfig` outside the repo and set:
- `SECRETS_PROVIDER=file`
- `SECRETS_SOURCE_PATH=/path/to/Secrets.xcconfig`
- `SECRETS_SCHEMA_PATH=/path/to/Secrets.schema.json`

## 4) Add build phases
Add two Run Script phases per target:

1. Validate Secrets (early)
```
${PATH_TO_SECRETSKIT}/Scripts/validate_secrets.sh
```

2. Seal Secrets (Release only, after resources are staged)
```
${PATH_TO_SECRETSKIT}/Scripts/seal_secrets.sh
```

Ensure `SECRETS_OUTPUT_PATH` points at the bundle resource location:
```
${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed
```

## 5) Runtime usage
```swift
import SecretsRuntime

let secrets = try SecretsManager()
let apiKey = secrets.value(for: "EXAMPLE_API_KEY")
```
