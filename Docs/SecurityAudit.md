# SecretsKit Security Audit

Audit date: 2026-05-19  
Scope: repository-wide review of the current Swift package, runtime library, CLI, integration scripts, and example configuration.

## Summary

SecretsKit has the right top-level warning: anything bundled into a client app must be treated as client-visible. The main risks are therefore not classic server-side vulnerabilities; they are secure-by-default problems around build-tool provenance, the sealed resource design, Vault transport validation, and APIs that can make downstream teams overestimate what the library protects.

Priority order:

1. Harden the runner so consumer builds do not process plaintext secrets with mutable or unverified compiler code.
2. Redesign the sealed format so it is clearly obfuscation, does not reuse AEAD nonces, and cannot be mistaken for a strong encryption boundary.
3. Enforce safe Vault transport and structured Vault path construction.
4. Make runtime failures and memory/debug protection claims more explicit and less footgun-prone.

## Fix Plan For Existing Implementation

### 1. Lock down compiler provenance in the integration runner

Affected file: `IntegrationTemplates/Scripts/SecretsKit/secretskit.sh`

Current behavior:

- Compatible mode falls back to `main` when no explicit ref is resolved.
- `SECRETSKIT_CLI_PATH` and `secretcompiler` on `PATH` are accepted before cached builds.
- Locked policy only does an exact version comparison when the locked ref is shaped like a semantic version, not when the ref is a commit revision.

Fix plan:

- Make `locked` the recommended and template-default policy for secret-processing builds.
- Remove the implicit `main` fallback for `validate` and `seal`; require an explicit release tag, commit, or `Package.resolved` revision.
- Treat `SECRETSKIT_CLI_PATH` and `PATH` binaries as explicit opt-in. In locked mode, reject them unless the binary reports an expected version and matches a configured digest/signature.
- When bootstrapping from source, verify the checked-out revision equals the resolved revision before building.
- Add runner tests that cover:
  - no ref in locked mode fails closed,
  - compatible mode never silently uses `main` for `seal`,
  - locked semantic-version checks still work,
  - locked commit-revision checks reject unrelated PATH binaries,
  - cache hits are tied to the selected ref.

### 2. Redesign `OBF2` format semantics and nonce handling

Affected files:

- `Sources/SecretCompiler/main.swift`
- `Sources/SecretsRuntime/SecretObfuscationMaterial.swift`
- `Sources/SecretsRuntime/SecretObfuscator.swift`
- `Sources/SecretsRuntime/SealedSecrets.swift`

Current behavior:

- One `SecretObfuscationMaterial` is generated per sealed file and reused for all keys.
- The same derived key and nonce are used for every obfuscated value in the file.
- The sealed JSON stores `hkdfSaltHex`, `hkdfSeedHex`, `nonceBase64`, and `xorMask` beside the obfuscated values, so offline reversal is expected.

Fix plan:

- Change the format to store per-entry nonce/material metadata if the AEAD-shaped transform remains.
- Add tests that seal at least two values and assert nonce uniqueness per entry.
- Rename docs and code comments away from encryption language; call the mechanism obfuscation consistently.
- Consider replacing ChaChaPoly-with-embedded-key material with a simpler, explicitly reversible obfuscation transform if the goal is only anti-accidental-disclosure. A cryptographic API shape can mislead users into relying on a boundary that does not exist.
- Add schema-level secret classes:
  - `public`: safe to commit or ship,
  - `clientBundled`: acceptable in an app bundle but should be rotatable,
  - `serverOnly`: must fail validation/sealing if configured for client bundling.
- Fail `seal` when a required key is marked `serverOnly`.

### 3. Enforce safe Vault URL construction

Affected files:

- `Sources/SecretCompiler/main.swift`
- `Sources/SecretCompiler/SecretsProvider.swift`

Current behavior:

- `VAULT_ADDR` or configured `vault.addr` can use any scheme accepted by `URL(string:)`.
- Vault API paths are built with string concatenation.
- `X-Vault-Token` is sent after URL construction without enforcing HTTPS.

Fix plan:

- Require `https` for Vault by default.
- Add an explicit local-development escape hatch, for example `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1`, and make it noisy.
- Build Vault URLs with `URLComponents` or validated path segments.
- Reject mount/path values containing query delimiters, fragments, control characters, or empty path segments after normalization.
- Bound `SECRETS_VAULT_TIMEOUT` to a sane range.
- Add tests for HTTPS rejection, local override, path encoding, KV v1/v2 request path formation, and namespace header behavior.

### 4. Make runtime API failures non-fatal where possible

Affected file: `Sources/SecretsRuntime/SecretsManager.swift`

Current behavior:

- `value(for:)` calls `fatalError` when a key is missing, empty, or fails deobfuscation.
- `SecretsError.secretMissing` and `secretInvalid` exist but are not used by the public accessor.

Fix plan:

- Add a throwing API, for example `func requiredValue(for:obfuscated:) throws -> String`.
- Keep the current `value(for:)` only as a convenience wrapper or deprecate it with migration guidance.
- Return typed errors for missing, empty, malformed, and deobfuscation-failed values.
- Add tests for malformed sealed files, missing keys, empty values, and bad obfuscation material.

### 5. Tighten local secret-file safety guidance

Affected files:

- `.gitignore`
- `Docs/XcodeIntegration.md`
- `Docs/CI.md`
- `Docs/SecurityNotes.md`
- `Config/SecretsKit.config.json.example`

Fix plan:

- Add recommended ignore patterns for consumer repos, such as local secret xcconfigs and generated sealed files when they are not app resources.
- Document that `Secrets.sealed` should be generated into the build products directory, not committed.
- Add a validation warning when `file.sourcePath` resolves inside the repository root unless explicitly allowed.
- Add a bootstrap mode that writes private source files with `0600` and refuses to overwrite non-private permissions.

## Propositions For A More Secure Solution

### 1. Separate client-bundled config from true secrets

The strongest design correction is to stop treating client-bundled values as secrets. SecretsKit can become safer if it formalizes two separate products:

- Client configuration bundling for publishable or low-risk values.
- Server-mediated secret access for anything privileged.

Recommended direction:

- Extend the schema with a required `classification` field.
- Fail builds when `serverOnly` keys are routed to `Secrets.sealed`.
- Generate a report during `seal` that lists each key classification without printing values.
- Add docs and templates for backend-issued short-lived tokens, token exchange, and revocation.

### 2. Use signed manifests for integrity, not embedded-key encryption for secrecy

If the app needs to know that `Secrets.sealed` was produced by the build pipeline and not tampered with, use signing semantics rather than embedded encryption semantics.

Possible design:

- Build-time CLI signs the sealed manifest with a private signing key stored in CI or a release pipeline.
- Runtime verifies the manifest with a public key embedded in the app.
- This protects integrity of bundled config but still does not pretend to hide it from app users.

This is a clearer boundary than storing encryption material beside ciphertext.

### 3. Prefer short-lived build credentials for Vault

Vault integration should encourage short-lived authentication rather than long-lived `VAULT_TOKEN` values.

Recommended direction:

- Document CI-native Vault auth patterns such as OIDC/JWT auth where possible.
- Support reading Vault token from a command that returns a short-lived token only if the command path is explicitly configured and trusted.
- Add guidance for token TTL, least-privilege policy, and path-scoped read permissions.
- Avoid examples that imply persistent tokens in local shell profiles.

### 4. Ship a hardened runner profile

Provide two runner modes:

- `strict`: locked ref, verified digest/signature, no PATH binary, no mutable fallback, HTTPS-only Vault, no source file inside repo root.
- `compat`: current flexible behavior, explicitly documented as lower assurance.

Make `strict` the default in templates and docs. Let users opt down to `compat` when they understand the tradeoff.

### 5. Add a small security regression test suite

High-value tests for this project:

- Multiple sealed entries never reuse nonce/material in a way that violates the selected format.
- Sealing refuses `serverOnly` keys.
- Vault refuses HTTP unless an explicit insecure-local flag is set.
- Vault URL path formation preserves intended mount/path segments.
- Runner locked mode rejects mutable refs and unverified PATH binaries.
- Runtime throwing API returns typed errors instead of crashing.
- CLI never prints secret values in success or failure paths.

### 6. Make the threat model part of the shipped docs

`Docs/SecurityNotes.md` is accurate but short. Expand it into an explicit support matrix:

- What SecretsKit protects against: accidental commits, casual log exposure, plaintext intermediates in normal build output.
- What it does not protect against: reverse engineering, compromised build hosts, malicious compiler binaries, privileged device attackers.
- Which keys are safe to bundle.
- Which keys must stay server-side.
- Recommended rotation and revocation process after accidental bundling.

## Audit Artifacts

Full Codex Security scan bundle:

- `/tmp/codex-security-scans/SecretsKit/84f081e_20260519T122204Z/report.md`
- `/tmp/codex-security-scans/SecretsKit/84f081e_20260519T122204Z/artifacts/`
