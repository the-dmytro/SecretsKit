# Changelog

## 0.3.0 — Unreleased

Phase 1 of the improvement plan: the `OBF3` format, which fixes the two critical `OBF2` flaws — the
obfuscation key no longer ships beside the ciphertext, and no nonce/key pair is reused across
entries. **This is a format change**, but the runtime still reads legacy `OBF2`, so existing bundles
keep working; see *Migration* below.

### Added
- **`OBF3` sealed format.** Per-entry random nonce, per-key HKDF domain separation (`info = key name`),
  and real ChaChaPoly AEAD — the `OBF2` `xor`/`reverse` theater is gone. The sealed resource carries
  **no key material**, only ciphertext + nonce + tag.
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
- **Ed25519 manifest signing** (integrity, plan item M4). Deferred to keep this release focused on the
  critical secrecy-theater fix and to avoid introducing CI signing-key management before it is needed.
  Tracked in the roadmap; say the word to pull it forward.

### Migration (OBF2 → OBF3)
No data migration is needed — secrets live in your provider (env/file/vault), and `Secrets.sealed` is
regenerated each build. The runtime reads both formats during transition, so do this at your own pace:

1. Update SecretsKit to 0.3.0.
2. Run once: `secretcompiler generate-key --swift-output Sources/ObfKey.swift --material-output Secrets/ObfKey.material`.
   Commit `ObfKey.swift` into your app target; keep `ObfKey.material` available to the seal step.
3. Add `--key-material <path>` (or `SECRETS_OBF_KEY_MATERIAL`) to your seal build phase → it now emits `OBF3`.
4. Pass the key at runtime: `try SecretsManager(obfuscationKey: AppObfKey.obfuscationKey)`.

Until steps 2–4 are done, `seal` keeps producing readable `OBF2` (with a warning) and the runtime keeps
reading it — nothing breaks on the upgrade itself.

## 0.2.0 — Unreleased

Phase 0 of the security improvement plan ([`Docs/ImprovementPlan`](Docs/ImprovementPlan/README.md)):
correctness and safety fixes for the runtime and CLI. **No sealed-file format change** — existing
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
