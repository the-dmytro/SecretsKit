# Changelog

## 0.5.0

### Fixed

- The runner verifies the approved SHA-256 for cached and bootstrapped compilers under
  `strict` and `locked`, including cached binaries found during bootstrap. Automatic
  bootstrap for `seal` and `validate` requires the digest under either policy.
- Only `install` can fall back to `main` when no ref is configured.
- The local bootstrap script creates plaintext input files with owner-only permissions.
- Vault addresses with embedded credentials are rejected.
- Invalid placeholder patterns fail validation and sealing when client values are checked.
- Sealed output and key material use a `0600` temporary file. The compiler moves it into
  place on the first write, replaces an existing file atomically, and refuses a directory.

### Added

- The `vault` provider supports `vault.backend: "1password"` and schema-key
  mappings to 1Password CLI field references.
- `secretcompiler exec` resolves required credentials and replaces itself
  with a child process that receives them in its environment.
- Regression tests for compiler digest enforcement, Vault URL validation, placeholder
  patterns, and sealed-file permissions.
- Consumer ignore patterns for the runner cache, sealed output, and local secret inputs.

## 0.4.1

### Fixed

- Schemas with only `serverOnly` keys seal an empty `OBF3` resource without reading a provider.

### Added

- Tests for server-only schemas and runner forwarding of `--require-classification`.

## 0.4.0

Key classification controls which values the compiler can put in the bundle.

### Added
- **`classification` per schema key**: `public` (bundled, not obfuscated), `clientBundled` (bundled +
  obfuscated; the default when unset), or `serverOnly` (never bundled).
- **`serverOnly` build-fail guard**: `seal` excludes `serverOnly` keys from the bundle and **aborts** if
  one is explicitly routed in (e.g. named in `--required-keys`).
- **Classification report**: `seal` prints `key → classification` (never values), marking `serverOnly`
  keys as `NOT bundled`.
- `--require-classification` and `SECRETSKIT_REQUIRE_CLASSIFICATION` fail the command if a
  key it processes has no declared classification.
- [Server-mediated secrets](Docs/ServerMediatedSecrets.md) describes how apps can use
  privileged credentials through their backend.
- Vault docs: short-lived (OIDC/JWT) auth guidance and the client-bundled-only scope note.
- Tests: serverOnly exclusion + explicit-route abort, public→plain, require-classification, invalid
  classification, unclassified→clientBundled default (37 tests total).

### Changed
- Obfuscation now defaults from classification: `public` keys ship as plain unless `obfuscate` is set
  explicitly; everything else obfuscates by default (unchanged for existing schemas).

### Migration
No data migration: classification is optional and defaults to `clientBundled`, so existing schemas seal
exactly as before. To adopt the guarantee, add `"classification": "..."` to each key (the example
`Config/Secrets.schema.json` shows all three), and optionally turn on `--require-classification`.

## 0.3.1

Security hardening patch for the 0.3.x Phase 1 rollout.

### Changed
- `secretcompiler seal` no longer silently falls back to legacy `OBF2` for obfuscated entries when
  key material is missing. Pass `--key-material` / `SECRETS_OBF_KEY_MATERIAL` for `OBF3`; use
  `--legacy-obf2` or `SECRETSKIT_ALLOW_LEGACY_OBF2=1` only as an explicit migration escape hatch.
- Vault request paths are now built from validated path segments and percent-encoded before request
  construction. Query delimiters, fragments, control characters, relative segments, and empty path
  segments are rejected.
- Runner `strict` mode now fails closed when a `secretcompiler` exists on `PATH` without a matching
  `SECRETSKIT_CLI_SHA256`, instead of silently ignoring it and continuing.

### Added
- Regression tests for the new seal default, explicit legacy opt-in, Vault path validation/encoding,
  and strict runner digest behavior.

## 0.3.0

`OBF3` keeps the obfuscation key in the app binary and uses a fresh nonce for each
obfuscated entry. The runtime still reads legacy `OBF2` bundles.

### Added
- `OBF3` uses ChaChaPoly with HKDF domain separation (`info = key name`). Obfuscated
  entries store ciphertext, nonce, and authentication tag.
- **`secretcompiler generate-key`** — generates the obfuscation key once: a Swift file to compile into
  the app binary, plus a `.material` sidecar for `seal`. Options: `--swift-output`, `--material-output`,
  `--symbol`.
- **`secretcompiler seal --key-material <path>`** (or `SECRETS_OBF_KEY_MATERIAL`) — writes keyless
  `OBF3`. Without it, `seal` writes legacy `OBF2` and prints a deprecation warning.
- **`SecretsManager(obfuscationKey:)`** and `init(url:obfuscationKey:)` — supply the compiled-in key to
  read `OBF3` obfuscated entries. New runtime types `SecretsObfuscationKey`, `SealedSecretsV2`,
  `SealedEntry`, `SecretObfuscatorV3`; new errors `obfuscationKeyRequired`, `unsupportedFormat`.
- Tests: `OBF3` round-trip, per-entry nonce uniqueness, key-name domain separation, key-required vs.
  keyless reads, legacy `OBF2` read-back, and key-material round-trip (25 tests total).

### Changed
- **Runner defaults to the `strict` policy.** Strict resolves the compiler ref from `Package.resolved`
  (no silent `main` fallback), refuses an ambient `SECRETSKIT_CLI_PATH`/`PATH` binary unless
  `SECRETSKIT_CLI_SHA256` matches its digest, and verifies the checked-out revision after bootstrap.
  Opt down with `cli.policy: compatible` (documented as lower assurance).
- **Vault rejects non-string KV values** instead of coercing them via `String(describing:)`.
- **`.xcconfig` parsing** now warns (stderr) on `$(...)` interpolation and `[sdk=...]` conditionals it
  cannot evaluate, instead of silently misparsing.

### Not included (deferred)
- Ed25519 manifest signing was deferred to avoid adding signing-key management in CI.
  See [deferred work](Docs/SecurityNotes.md#deferred-work).

### Migration (OBF2 → OBF3)
No data migration is needed — secrets live in your provider (env/file/vault), and `Secrets.sealed` is
regenerated each build. The runtime reads both formats during transition, so do this at your own pace:

1. Update SecretsKit to 0.3.0.
2. Run once: `secretcompiler generate-key --symbol AppObfKey --swift-output Sources/ObfKey.swift --material-output Secrets/ObfKey.material`.
   Commit `ObfKey.swift` into your app target; keep `ObfKey.material` available to the seal step.
3. Add `--key-material <path>` (or `SECRETS_OBF_KEY_MATERIAL`) to your seal build phase → it now emits `OBF3`.
4. Pass the key at runtime: `try SecretsManager(obfuscationKey: AppObfKey.obfuscationKey)`.

In 0.3.0, the compiler could still emit legacy `OBF2` automatically. Starting with 0.3.1,
sealing obfuscated entries as `OBF2` requires explicit opt-in.

## 0.2.0

Correctness and safety fixes for the runtime and CLI. **No sealed-file format change** — existing
`Secrets.sealed` files remain readable, so no data migration is required. This is an API + runtime
behavior update; migrate at the deprecation warnings.

### Added
- `SecretsManager.requiredValue(for:obfuscated:) throws` — throws a typed `SecretsError`
  (`.secretMissing` / `.secretInvalid`) instead of crashing on missing, empty, or undecodable secrets.
- `SecretsManager.optionalValue(for:obfuscated:) -> String?` — returns `nil` instead of throwing.
- `SecretsManager.requiredProtectedValue(for:obfuscated:) throws -> ProtectedSecret`.
- `SecretsManager.validateRequiredKeys(_:) throws` — validates in every build config, not just DEBUG.
- `SecretProtection.isDebuggerAttached() -> Bool` — opt-in, best-effort debugger check (a speed bump only).
- `ProtectedSecret.withBytes(_:)` — read the raw secret bytes without materializing a `String` copy.
- Unit tests for the runtime library and the CLI's Vault transport check (first test targets in the package).

### Changed
- `ProtectedSecret` now stores the secret as bytes and best-effort zeroes them on release. `get()` still
  returns a `String` (which cannot be reliably zeroed) — documented on the type.
- Vault now **requires HTTPS**. Set `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1` to permit plaintext HTTP for
  local development only; any other scheme is rejected.

### Removed
- `SecretProtection.protect(_:)` — it silently returned an empty string when a debugger was attached,
  turning real secrets into empty credentials that flowed into network calls. Use `isDebuggerAttached()`
  explicitly if you want a tamper check.
- `SecretProtection`'s no-op `isHooked()` stub.

### Deprecated
- `SecretsManager.value(for:)` → use `requiredValue(for:)` or `optionalValue(for:)`.
- `SecretsManager.protectedValue(for:)` → use `requiredProtectedValue(for:)`.
- `SecretsManager.validate(requiredKeys:)` → use `validateRequiredKeys(_:)`.

### Migration
```swift
// Before
let key = secrets.value(for: "EXAMPLE_API_KEY")

// After — handle absence instead of crashing
let key = try secrets.requiredValue(for: "EXAMPLE_API_KEY")
// or
guard let key = secrets.optionalValue(for: "EXAMPLE_API_KEY") else { /* handle */ }
```
