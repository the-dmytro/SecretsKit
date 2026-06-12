# 04 · Roadmap

Three phases, ordered so that value lands early and no phase blocks on a decision you have not made
yet. Effort is rough calendar estimate for one developer; treat as relative sizing, not commitment.

Each item links to its flaw ID in [02-flaw-catalog.md](02-flaw-catalog.md) and the design decision in
[03-target-architecture-v2.md](03-target-architecture-v2.md).

## Phase 0 — Stop the bleeding (≈ 2–4 days)

Pure correctness and safety fixes. **No architectural debate, no breaking the format.** Ship these
regardless of what you decide about v2. A shipping app is materially safer after Phase 0 alone.

- [ ] **Replace `fatalError` with throwing API.** Add `requiredValue(for:) throws`; make `value(for:)`
      a deprecated shim. (H1 · Decision 4) — *the single highest-value fix; one bad key currently
      crashes the app.*
- [ ] **Remove the debugger → `""` substitution.** Take `SecretProtection.protect` out of the value
      path; delete the no-op `isHooked()`. If fail-closed is wanted, make it explicit and throwing.
      (H2 · Decision 4)
- [ ] **Drop or rewrite `ProtectedSecret`'s zeroing claim.** Either remove the cosmetic `deinit`
      scrubbing or replace with a caller-owned byte buffer; update docs to state the real guarantee.
      (M1 · Decision 4)
- [ ] **Require HTTPS for Vault** with a loud `SECRETS_VAULT_ALLOW_INSECURE_HTTP=1` escape hatch.
      (H3 · Decision 6) — *small change, closes a token-leak hole.*
- [ ] **Fix `validate(requiredKeys:)`**: remove the `contains("__")` false-positive; or remove the
      method if the CLI's `validate` supersedes it. (M5)
- [ ] **Docs honesty pass.** Align `README.md` with `Docs/SecurityNotes.md`: state the threat model,
      stop implying bundled = secret. (L1)
- [ ] **Stand up a test target** and cover every Phase 0 fix: throwing errors on missing/empty/corrupt
      sealed data, Vault HTTPS rejection, no empty-string substitution. (L2)

Exit criteria: no `fatalError` in the runtime value path; no code path returns a silently-empty
secret; Vault refuses plaintext HTTP by default; CI runs the new tests.

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
   a publishable/`clientBundled` value, Tier B may be optional and Phase 2 reduces to *just*
   mandatory classification + the build-fail guard (cheap, ≈ 2–3 days). If you have real secrets
   (payment keys, privileged API tokens), Tier B is the point of the whole project and worth the
   investment.
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
