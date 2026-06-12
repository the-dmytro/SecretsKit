# 04 · Roadmap

Three phases, ordered so that value lands early and no phase blocks on a decision you have not made
yet. Effort is rough calendar estimate for one developer; treat as relative sizing, not commitment.

Each item links to its flaw ID in [02-flaw-catalog.md](02-flaw-catalog.md) and the design decision in
[03-target-architecture-v2.md](03-target-architecture-v2.md).

## Phase 0 — Stop the bleeding (≈ 2–4 days) — ✅ done in 0.2.0

Pure correctness and safety fixes. **No architectural debate, no breaking the format.** Ship these
regardless of what you decide about v2. A shipping app is materially safer after Phase 0 alone.

Completed 2026-06-12; see [`CHANGELOG.md`](../../CHANGELOG.md). Sealed-file format unchanged, so no
data migration was needed — only API migration, guided by deprecation warnings.

- [x] **Replace `fatalError` with throwing API.** Added `requiredValue(for:) throws` +
      `optionalValue(for:)`; `value(for:)` is now a deprecated shim. (H1 · Decision 4)
- [x] **Remove the debugger → `""` substitution.** `SecretProtection.protect` removed from the value
      path; the type is now an opt-in `isDebuggerAttached()` utility; no-op `isHooked()` deleted.
      (H2 · Decision 4)
- [x] **Rewrote `ProtectedSecret`** to store secret bytes and best-effort zero them on release, with
      an honest doc comment about what `String` can and cannot guarantee. (M1 · Decision 4)
- [x] **Require HTTPS for Vault** with a loud `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1` escape hatch.
      (H3 · Decision 6)
- [x] **Fixed `validate(requiredKeys:)`**: deprecated it; added `validateRequiredKeys(_:) throws` that
      runs in every build config without placeholder over-matching. (M5)
- [x] **Docs honesty pass.** README runtime API updated; obfuscation-not-encryption note + threat-model
      pointer added to Security notes. (L1)
- [x] **Stood up test targets** (`SecretsRuntimeTests`, `SecretCompilerTests`) covering throwing errors
      on missing/empty/corrupt sealed data and Vault HTTPS rejection — 13 tests, all green. (L2)

Exit criteria (met): no `fatalError` in the runtime value path; no code path returns a silently-empty
secret; Vault refuses plaintext HTTP by default; `swift test` runs the new suites.

## Phase 1 — Honest obfuscation + trustworthy build (≈ 1–2 weeks)

Removes the cryptographic theater and the supply-chain hole. The bundled format changes, so bump the
sealed `version` and gate the runtime on it.

- [ ] **Separate key from ciphertext.** Codegen the root key material into a compiled Swift source;
      ship only ciphertext + per-entry nonce + tag in the resource. (C1 · Decision 1)
- [ ] **Per-entry nonce + per-key HKDF domain separation** (`info = bundleId || keyName`). Add a test
      that seals ≥2 values and asserts distinct nonces. (C2 · Decision 1)
- [ ] **Sign the manifest (Ed25519)** at seal time; verify with embedded public key at load. (M4 ·
      Decision 2)
- [ ] **Rename for honesty.** `SecretObfuscator` stays; remove crypto-implying names from the public
      surface (`ProtectedSecret`, "seal/encrypt" prose). (L1)
- [ ] **Harden the runner to `strict` by default.** Lock the compiler ref from `Package.resolved`,
      verify checkout revision, pin/verify ambient binaries by digest, kill the silent `main`
      fallback; keep `compat` as documented opt-in. (H4 · Decision 5)
- [ ] **Provider hardening.** Vault path via `URLComponents` + segment validation + bounded timeout +
      reject non-string KV values; stricter/clearer `.xcconfig` handling. (M2, M3, L3 · Decision 6)
- [ ] **Security regression suite.** Nonce uniqueness, manifest signature verification, runner rejects
      mutable refs/unverified binaries, CLI never prints values. (L2)

Exit criteria: opening `Secrets.sealed` no longer yields the key; tampering with it fails
verification; the runner will not seal with an unpinned compiler; the README's "not easy to extract"
claim is once again literally true.

## Phase 2 — The by-design fix (project-sized; decision gate first)

This is where the *design* stops being able to bundle a true secret. It is larger and has a real
decision in it, so it gets a gate.

### Decision gate

Answer before starting Phase 2:

1. **Do any of your keys actually need `serverOnly` protection?** If everything you ship is genuinely
   a publishable/`clientBundled` (local-only) value — which is the correct, often unavoidable answer
   for autonomous/offline apps or when you don't own a backend — Tier B stays unbuilt and Phase 2
   reduces to *just* mandatory classification + the build-fail guard + the classification report
   (cheap, ≈ 2–3 days). Build Tier B only if and when you have a real secret *and* a backend to
   mediate it; until then, the classification system still earns its keep by making the local-only
   decision explicit and intentional.
2. **Do you control a backend** that can run a token-exchange + App Attest verification endpoint? Tier
   B needs one. If not, the honest interim answer is: classify those keys `serverOnly`, let the build
   fail, and *don't ship them at all* until the backend exists — which is itself the correct
   security outcome.

### Work items

- [ ] **Mandatory `classification` in schema v2**; `seal` fails on a missing class. (Decision 0) —
      *do this part even if you skip Tier B; it is the keystone guarantee.*
- [ ] **Build-fail guard:** any `serverOnly` key routed to the bundle aborts `seal` with a clear
      error. (Decision 0)
- [ ] **Classification report** emitted by `seal` (keys + classes, never values). (Decision 0)
- [ ] **Tier B client SDK slot + backend contract**: token-exchange shape, App Attest/DeviceCheck
      gating, TTL/rotation/revocation guidance, reference docs. (Decision 3) — *defer the reference
      backend implementation if needed, but define the contract.*
- [ ] **Vault short-lived auth guidance** (OIDC/JWT CI auth over long-lived `VAULT_TOKEN`); align with
      least-privilege, path-scoped policies. (Decision 3, also in audit)

Exit criteria: a `serverOnly` key cannot be sealed into the bundle under any configuration; every
shipped key has a declared classification visible in the seal report; `serverOnly` keys have a
documented runtime path that does not bundle them.

## Sequencing summary

| Phase | Theme | Effort | Breaking? | Gated? |
|-------|-------|--------|-----------|--------|
| 0 | Correctness / safety foot-guns | 2–4 days | API-additive (deprecations) | No — do now |
| 1 | Honest obfuscation + build provenance | 1–2 weeks | Sealed format `version` bump | No |
| 2 | Classification wall + server-mediated tier | days → project | Schema v2 | Yes (decision gate) |

If you do nothing else, do **Phase 0** — it is cheap and removes real ways a shipping app can break or
leak. **Phase 1** is what makes the tool stop overpromising. **Phase 2** is what makes the design
itself sound; even its cheapest slice (mandatory classification + build-fail guard) delivers most of
the by-design guarantee for a few days of work.
