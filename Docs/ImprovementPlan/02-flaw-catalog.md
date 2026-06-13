# 02 · Flaw Catalog

Every concrete flaw found in the current code, severity-ranked, with file references. The "Audit?"
column marks whether [`Docs/SecurityAudit.md`](../SecurityAudit.md) already covers it — several here
are **new** findings from this pass.

Severity key: **C** critical (breaks the core promise or a shipping app) · **H** high · **M** medium
· **L** low.

## Critical

### C1 — The decryption key ships inside the ciphertext file *(Audit: yes)*

[`SealedSecrets.swift`](../../Sources/SecretsRuntime/SealedSecrets.swift) stores `obfuscation`
(the full `SecretObfuscationMaterial`: `hkdfSeedHex`, `hkdfSaltHex`, `nonceBase64`, `xorMask`) in the
**same JSON** as the obfuscated `secrets`. The HKDF `info` is the hardcoded constant
`"secretskit-obfuscation"` ([`SecretObfuscationMaterial.swift:35`](../../Sources/SecretsRuntime/SecretObfuscationMaterial.swift#L35)).
Anyone with the bundle reconstructs the key and decrypts everything with a few lines of CryptoKit.
This makes the ChaChaPoly/HKDF machinery **security theater**: it looks like encryption and provides
none. This is the headline flaw.

### C2 — AEAD nonce + key reused across every secret in the file *(Audit: yes)*

[`main.swift:232`](../../Sources/SecretCompiler/main.swift#L232) generates **one** `material`, then
the loop at [`main.swift:234`](../../Sources/SecretCompiler/main.swift#L234) obfuscates every key
with that same material — i.e. the same `(key, nonce)` pair for all secrets
([`SecretObfuscator.swift:8-10`](../../Sources/SecretsRuntime/SecretObfuscator.swift#L8)). Reusing a
ChaChaPoly `(key, nonce)` across multiple plaintexts is a textbook catastrophic misuse: the XOR of
two ciphertexts equals the XOR of two plaintexts (keystream cancels), and the Poly1305 one-time
authenticator is no longer safe against forgery. This would be fatal even *after* C1 is fixed, so it
must be fixed as part of any redesign that keeps AEAD.

## High

### H1 — `value(for:)` crashes a shipping app on missing/empty/corrupt data *(Audit: yes)*

[`SecretsManager.swift:24,30,36`](../../Sources/SecretsRuntime/SecretsManager.swift#L24) call
`fatalError` when a key is absent, deobfuscation fails, or the value is empty. A single mistyped key,
a stale schema, or a truncated `Secrets.sealed` takes the whole app down in production. Typed errors
(`secretMissing`, `secretInvalid`) already exist in
[`SecretsError.swift`](../../Sources/SecretsRuntime/SecretsError.swift) but the public accessor never
uses them. The API should throw, not crash.

### H2 — Silent empty-string substitution when a debugger is attached *(Audit: no — new)*

[`SecretProtection.protect`](../../Sources/SecretsRuntime/SecretProtection.swift#L7) returns `""`
when `isDebugging()` is true, and `value(for:)` returns that result unguarded
([`SecretsManager.swift:32,39`](../../Sources/SecretsRuntime/SecretsManager.swift#L32)). The empty
checks happen on the *pre-protection* value, so in a Release build with a debugger attached **every
secret silently becomes `""`** and flows into network calls as an empty credential. This is both a
correctness landmine (impossible for the caller to distinguish "real secret" from "we blanked it")
and a debugging trap. Worse, the protection it buys is negligible: it is one `sysctl(P_TRACED)`
check, trivially bypassed by any jailbreak tweak or Frida — and `isHooked()`
([`SecretProtection.swift:22`](../../Sources/SecretsRuntime/SecretProtection.swift#L22)) is a no-op
stub returning `false`. The mechanism costs real correctness for near-zero security. Fail-closed is
fine; doing it by returning a valid-looking empty string is not — it should throw a typed error if
anything.

### H3 — Vault token can be sent over plaintext HTTP / arbitrary URL scheme *(Audit: yes)*

[`resolveVaultSettings`](../../Sources/SecretCompiler/main.swift#L57) and
[`VaultSecretsProvider.loadSecrets`](../../Sources/SecretCompiler/SecretsProvider.swift#L217) accept
any `VAULT_ADDR` that `URL(string:)` will parse, then attach `X-Vault-Token`. An `http://` address,
or an attacker-controlled `VAULT_ADDR` in CI, leaks a Vault token in cleartext. HTTPS must be
required by default with a loud, explicit local-only escape hatch.

### H4 — Compiler provenance is trust-on-first-use with a mutable `main` fallback *(Audit: yes)*

[`secretskit.sh`](../../IntegrationTemplates/Scripts/SecretsKit/secretskit.sh) resolves the
`secretcompiler` from `SECRETSKIT_CLI_PATH` or `PATH` *before* cached builds
([`resolve_cli`](../../IntegrationTemplates/Scripts/SecretsKit/secretskit.sh#L214)), and in the
default `compatible` policy falls back to building from `main`
([`resolve_cli_ref`](../../IntegrationTemplates/Scripts/SecretsKit/secretskit.sh#L144)). A compromised
PATH binary or a re-pointed `main` runs with **plaintext secrets in hand** during sealing. There is
no digest or signature pinning. `bootstrap_cli`
([line 172](../../IntegrationTemplates/Scripts/SecretsKit/secretskit.sh#L172)) checks out a ref and
builds without verifying the resolved revision or any tag signature.

## Medium

### M1 — `ProtectedSecret` memory zeroing does nothing *(Audit: no — new)*

[`ProtectedSecret.deinit`](../../Sources/SecretsRuntime/ProtectedSecret.swift#L14) reassigns
`value = String(repeating: " ", …)` then `value = ""`. A Swift `String` is immutable and
copy-on-write; reassigning the property does **not** overwrite the original heap buffer in place — it
drops a reference and lets ARC free the buffer unscrubbed, whenever it chooses. Every `value(for:)`
call also returns a fresh `String` whose buffer is copied again the moment it bridges to
`NSString`/CFString for any Foundation/network API. The class implies a memory-hygiene guarantee it
cannot deliver. Real zeroization needs a caller-owned `[UInt8]`/`Data` buffer (and even then iOS
offers weak guarantees) — or the claim should be dropped.

### M2 — Vault non-string values coerced via `String(describing:)` *(Audit: no — new)*

[`SecretsProvider.swift:257`](../../Sources/SecretCompiler/SecretsProvider.swift#L257) falls back to
`String(describing: value)` for non-string Vault fields. A numeric, boolean, array, or null field
gets sealed as its Swift debug description (e.g. `"Optional(…)"`, `"[1, 2]"`), silently embedding a
malformed credential that passes the non-empty check. Non-string values should be rejected or
explicitly, narrowly coerced.

### M3 — `.xcconfig` parser is naive *(Audit: no — new)*

[`parseXcconfig`](../../Sources/SecretCompiler/SecretsProvider.swift#L91) does a plain `split(=)`. It
does not handle `$(inherited)`, `#include`, `KEY[sdk=…]` conditionals, or `$(VAR)` interpolation. A
secret defined via any of those constructs is silently misparsed or dropped, then either fails
validation confusingly or seals a wrong value. Low blast radius but a real correctness gap for the
documented `file` provider.

### M4 — No integrity/authenticity on `Secrets.sealed` *(Audit: yes — via "signed manifest")*

Nothing binds the sealed file to the build that produced it. A swapped or hand-edited
`Secrets.sealed` is accepted by [`SecretsManager.init`](../../Sources/SecretsRuntime/SecretsManager.swift#L13)
as long as it decodes. Integrity (not secrecy) is genuinely achievable here via a signed manifest and
is the one legitimate use of crypto in this project.

### M5 — `validate(requiredKeys:)` is DEBUG-only and over-matches *(Audit: no — new)*

[`SecretsManager.validate`](../../Sources/SecretsRuntime/SecretsManager.swift#L42) only runs under
`#if DEBUG` and flags any value `contains("__")`, which false-positives on legitimate secrets
containing a double underscore. It gives a false sense of a runtime guard that does not exist in
Release.

## Low

### L1 — README/API oversell what is protected *(Audit: partially)*

[`README.md`](../../README.md) frames the goal as preventing extraction and surfaces a crypto-shaped
API, while the accurate caveats live only in
[`Docs/SecurityNotes.md`](../../Docs/SecurityNotes.md). The naming (`SecretObfuscator` is honest;
`protect`, `ProtectedSecret`, `seal`, ChaChaPoly are not) nudges consumers toward over-reliance.

### L2 — No test suite at all *(Audit: yes)*

`Package.swift` declares no test target; there are no tests anywhere. For a security tool this is
itself a defect — every fix below needs a regression test, and several flaws (nonce reuse,
HTTPS rejection, throwing API) are exactly the kind that silently regress.

### L3 — `auto` provider merge surfaces errors weakly *(Audit: no — new)*

[`AutoSecretsProvider.loadMerged`](../../Sources/SecretCompiler/SecretsProvider.swift#L177) collects
provider errors into `attempts` but only throws if keys remain unfilled; a misconfigured provider
that happens to be shadowed by a later one fails silently. Minor, but worth a diagnostic.

## Summary table

> **Status (0.4.1):** Phase 0 fixed H1, H2, M1, M5, H3, L1, L2. Phase 1 fixed **C1, C2** (the critical
> pair — `OBF3` separates key from ciphertext and uses per-entry nonces), **H4** (strict runner, with
> digest-pinned PATH handling tightened in 0.3.1), **M2, M3** (provider hardening, including Vault path
> validation in 0.3.1). Phase 2 (0.4.0) added **key classification** with a `serverOnly` build-fail
> guard — the by-design half of the plan's keystone; 0.4.1 tightened the serverOnly-only sealing path.
> **M4** (manifest signing) stays **deferred**;
> Tier B's runtime token-exchange is documented but unbuilt by design (no backend today). Remaining: M4
> and Tier B runtime. The findings below are kept as the original analysis; see
> [`CHANGELOG.md`](../../CHANGELOG.md) and [04-roadmap.md](04-roadmap.md) for what shipped.

| ID | Severity | One-line | Phase |
|----|----------|----------|-------|
| C1 | Critical | Key ships with ciphertext | 1 |
| C2 | Critical | AEAD nonce/key reused across secrets | 1 |
| H1 | High | `fatalError` crashes app on bad data | 0 |
| H2 | High | Silent `""` secret when debugger attached | 0 |
| H3 | High | Vault token over plaintext HTTP possible | 0/1 |
| H4 | High | Compiler provenance TOFU + `main` fallback | 1 |
| M1 | Medium | `ProtectedSecret` zeroing is a no-op | 0 |
| M2 | Medium | Vault non-string coercion garbage | 1 |
| M3 | Medium | Naive `.xcconfig` parsing | 1 |
| M4 | Medium | No integrity on sealed file | 1 |
| M5 | Medium | `validate` DEBUG-only + over-matches | 0 |
| L1 | Low | Docs/API oversell | 0 |
| L2 | Low | No tests | 0→all |
| L3 | Low | Auto-merge weak diagnostics | 2 |
