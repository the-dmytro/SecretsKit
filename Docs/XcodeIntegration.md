# Xcode Integration

## 1) Add SecretsRuntime
Add the package and link `SecretsRuntime` to your iOS/watchOS targets.

## 2) Provide a secrets schema
Create a schema file (committed, no values):
- `Config/Secrets.schema.json`

Optionally give each key a `classification` (`public` | `clientBundled` | `serverOnly`). `serverOnly`
keys are never bundled. See the README's "Key classification" section.

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

## 5) Generate the obfuscation key (once)
The `OBF3` format keeps the obfuscation key in the app binary, not the bundle. Generate it once and
commit the Swift file into your app target:
```
secretcompiler generate-key \
  --swift-output Sources/Generated/AppObfKey.swift \
  --material-output Config/AppObfKey.material
```
- Add `AppObfKey.swift` to your app target (it contains the key, not your secrets).
- Keep `AppObfKey.material` available to the seal step, e.g. export `SECRETS_OBF_KEY_MATERIAL` in the
  seal wrapper, or pass `--key-material Config/AppObfKey.material`. Without it, `seal` refuses to write
  obfuscated entries. Use `--legacy-obf2` / `SECRETSKIT_ALLOW_LEGACY_OBF2=1` only for temporary
  migration builds that must still emit deprecated `OBF2`.

## 6) Runtime usage
```swift
import SecretsRuntime

let secrets = try SecretsManager(obfuscationKey: AppObfKey.obfuscationKey)
let apiKey = try secrets.requiredValue(for: "EXAMPLE_API_KEY")
```
