# Changelog

## 0.4.1 — Unreleased

Patch hardening for the 0.4.x classification rollout.

### Fixed
- Schemas with only `serverOnly` keys now seal an empty `OBF3` resource without requiring any local
  provider/source path, because no client-bundled value is loaded.
- Runner (`secretskit.sh`): `strict`/`locked` policy now digest-checks **cached and bootstrapped**
  `secretcompiler` binaries too (`SECRETSKIT_CLI_SHA256`), not just `SECRETSKIT_CLI_PATH`/`PATH`
  binaries; auto-bootstrap for `seal`/`validate` requires the digest to be set, and the freshly
  built binary is verified before use. `seal`/`validate` no longer fall back to a mutable `main`
  branch (the fallback remains for `install` only).
- `Scripts/bootstrap_secrets.sh` sets `umask 077`, so the created plaintext secrets file is not
  world-readable.
- Vault provider rejects `VAULT_ADDR` values with embedded credentials (`user:pass@host`), which
  could otherwise leak into request-error logs; authenticate via `VAULT_TOKEN` only.
- An invalid `--placeholder-regex` / `SECRETS_PLACEHOLDER_REGEX` now fails the build instead of
  silently falling back to the default pattern.
- Sealed output and `generate-key` material are written via a `0600` temp file that is moved into
  place when the destination is absent and atomically `replaceItemAt`-replaced when it exists, so
  they are never briefly world-readable regardless of the caller's umask, a directory destination is
  refused instead of being deleted, and first-time writes succeed.
- Runner: the bootstrap cache fast path now verifies `SECRETSKIT_CLI_SHA256` too, so a cached binary
  with a mismatching digest cannot be executed via `SECRETSKIT_AUTO_BOOTSTRAP=1` after the
  resolve-time refusal.

### Added
- Regression tests for serverOnly-only sealing and runner forwarding of `--require-classification`,
  plus new tests for runner digest enforcement on cached binaries, the no-`main`-fallback rule,
  Vault userinfo rejection, placeholder-regex handling, and `0600` sealed-file permissions.
- `.gitignore` and `IntegrationTemplates/README.md` now cover consumer artifacts: `.tools/`,
  `*.sealed`, `*.material`, `Secrets.xcconfig`.
- Docs: runner policy semantics, CI provenance guidance (`SECRETSKIT_CLI_SHA256`, never set
  `SECRETS_VAULT_ALLOW_INSECURE_HTTP` in CI), and Vault transport notes.

## 0.4.0 — Unreleased

Phase 2 of the improvement plan: **key classification** — the bundle-or-not decision becomes explicit
and build-enforced, so a value you declare a true secret cannot be bundled by accident. Graceful: keys
with no classification keep today's behavior.

### Added
- **`classification` per schema key**: `public` (bundled, not obfuscated), `clientBundled` (bundled +
  obfuscated; the default when unset), or `serverOnly` (never bundled).
- **`serverOnly` build-fail guard**: `seal` excludes `serverOnly` keys from the bundle and **aborts** if
  one is explicitly routed in (e.g. named in `--required-keys`).
- **Classification report**: `seal` prints `key → classification` (never values), marking `serverOnly`
  keys as `NOT bundled`.
- **`--require-classification` / `SECRETSKIT_REQUIRE_CLASSIFICATION`**: opt-in strict mode that fails the
  build on any key without a declared classification.
- **`Docs/ServerMediatedSecrets.md`**: the contract for `serverOnly` keys (App Attest/DeviceCheck-gated,
  short-lived, revocable tokens) so they have a real destination instead of being downgraded.
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

## 0.3.1 — Unreleased

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
