# Changelog

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
