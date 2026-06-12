# 03 · Target Architecture (v2)

This is the redesign that removes the fundamental flaw **by construction** rather than by
documentation. It rests on the principle from [01-threat-model.md](01-threat-model.md):

> A client secrets system is only sound if its design refuses to bundle what it cannot protect.

Everything below serves that sentence. The guiding move is to **split one dishonest product into two
honest ones** with a hard, build-enforced wall between them.

```
                         ┌─────────────────────────────────────────┐
                         │  Secrets.schema.json                     │
                         │  every key REQUIRES a `classification`   │
                         └──────────────┬──────────────────────────┘
                                        │  secretcompiler routes by class
              ┌─────────────────────────┴──────────────────────────┐
              ▼                                                      ▼
   ┌──────────────────────────┐                       ┌──────────────────────────────┐
   │ TIER A — Bundled Config   │                       │ TIER B — Server-Mediated      │
   │ public | clientBundled    │                       │ serverOnly                    │
   │                           │                       │                               │
   │ • obfuscated, NOT secure  │                       │ • NOTHING bundled             │
   │ • key compiled into binary│   serverOnly key  ┌──▶│ • runtime fetches short-lived │
   │ • ciphertext in resource  │   routed to A  →  │   │   token from backend          │
   │ • signed manifest (integrity)│  BUILD FAILS    │   │ • gated by App Attest/Device- │
   │                           │                   │   │   Check; revocable, scoped    │
   └──────────────────────────┘                   │   └──────────────────────────────┘
                                                   └── the by-design guarantee
```

## Decision 0 — Mandatory classification (the keystone)

Extend the schema so every key **must** declare a classification; sealing fails if any key lacks one.

```json
{
  "version": 2,
  "keys": {
    "MAPS_PUBLISHABLE_KEY": { "classification": "clientBundled" },
    "ANALYTICS_WRITE_KEY":  { "classification": "clientBundled" },
    "STRIPE_SECRET_KEY":    { "classification": "serverOnly" }
  }
}
```

| Class | Meaning | Build behavior |
|-------|---------|----------------|
| `public` | Safe to commit and ship (e.g. a published client ID). | Bundled verbatim, no obfuscation needed. |
| `clientBundled` | Acceptable in a client bundle, must be rotatable/revocable, low blast radius. | Obfuscated and bundled (Tier A). |
| `serverOnly` | A real secret. Must never reach a device. | **`seal` fails** if this key would be written to the bundle. Routed to Tier B config only. |

This single rule is what makes v2 *structurally* safe: a developer who classifies Stripe's secret key
as `serverOnly` cannot accidentally bundle it, because the build refuses. No documentation, no
discipline, no review required — the tool enforces it.

`seal` also emits a **classification report** (key → class, never values) so reviewers can see at a
glance what is being shipped client-side.

## Decision 1 — Tier A: honest obfuscation with key/ciphertext separation

Tier A keeps "raise the cost of casual extraction" but stops pretending to be encryption and fixes
C1/C2 from the [flaw catalog](02-flaw-catalog.md).

**Separate the key from the ciphertext.** Today both live in `Secrets.sealed`. In v2:

- `secretcompiler seal` generates per-build random key material, derives a **per-key** subkey
  (`HKDF` with `info = bundleIdentifier || keyName` for domain separation) and a **fresh per-entry
  nonce** (fixes C2).
- The **ciphertext + per-entry nonce + tag** go into the bundled resource (`Secrets.sealed`).
- The **root key material** is written into a **generated Swift source file** (e.g.
  `GeneratedSecretsKey.swift`) that is compiled into the app's `__TEXT`/`__const`, *not* shipped as a
  readable resource. The codegen runs in the same build phase, before compilation.

Result: extraction goes from "open the JSON" (one step, today) to "disassemble the binary, locate and
reassemble the key bytes, then decrypt" (many steps). **Still extractable — by design, Tier A is only
for `clientBundled` values that tolerate it** — but the "easy" in "prevents easy extraction" is true
again, and the crypto is no longer self-defeating.

Naming becomes honest throughout: the mechanism is *obfuscation*; `protect`, `ProtectedSecret`, and
"seal/encrypt" language is renamed or removed (addresses L1).

> Alternative considered: drop AEAD entirely for a plainly-labeled reversible XOR-with-embedded-
> keystream. Rejected as the default because the AEAD path, once the key is moved into the binary and
> nonces are per-entry, is no worse and gives us a free integrity check per entry. But the *framing*
> must match the XOR honesty: this defeats `strings`, not a reverse engineer.

## Decision 2 — Signed manifest for integrity (the one real use of crypto)

Secrecy of bundled data is impossible; **integrity is not**. Use signing for what signing is for:

- `seal` signs the manifest (the map of key → obfuscated entry, plus metadata) with an **Ed25519
  private key held only in CI / the release pipeline**.
- The app embeds the corresponding **public key** and verifies the signature at load
  ([`SecretsManager.init`](../../Sources/SecretsRuntime/SecretsManager.swift#L13)).
- A swapped, truncated, or hand-edited `Secrets.sealed` now fails verification instead of being
  silently accepted (fixes M4).

This is an honest boundary: "this config was produced by our pipeline and not tampered with after."
It deliberately does **not** claim to hide the config from the app's owner.

## Decision 3 — Tier B: server-mediated secrets (the actual fix for real secrets)

For anything classified `serverOnly`, the secret **never leaves the server**. SecretsKit's job shifts
from "bundle it cleverly" to "make the right thing easy":

- A small runtime client (`SecretsKit.tokenProvider`) exchanges a device assertion for a short-lived,
  scoped token from the app's backend.
- The exchange is gated by **App Attest** (`DCAppAttestService`, iOS 14+) / **DeviceCheck** so the
  backend only issues tokens to genuine, unmodified instances of the real app on real hardware. This
  is the property no bundling scheme can provide. *Platform note:* App Attest is not available on
  watchOS — for a watch-only flow, mediate the token through the paired iPhone app or fall back to a
  DeviceCheck-based assertion, and document the weaker guarantee.
- Tokens are short-lived and revocable: a leaked token expires and can be killed server-side; a
  bundled secret can only be rotated by shipping a new build to every user.

SecretsKit does not have to *implement* the backend to make this sound — but it must **define the
contract** (token-exchange endpoint shape, attestation verification expectations, TTL/rotation
guidance) and ship the client SDK slot, so `serverOnly` keys have a real home instead of being
quietly downgraded to `clientBundled`. Document the patterns; provide a reference backend later.

## Decision 4 — Runtime API that cannot foot-gun

Rework [`SecretsManager`](../../Sources/SecretsRuntime/SecretsManager.swift) and friends:

- **Throwing, typed API.** `func requiredValue(for:) throws -> String` returning
  `SecretsError.secretMissing` / `.secretInvalid` / `.sealedResourceInvalid` instead of `fatalError`
  (fixes H1). Keep a clearly-deprecated convenience shim if needed for migration.
- **No silent substitution.** Remove the debugger → `""` behavior (fixes H2). If a consumer wants
  fail-closed-under-debugger, expose it as an explicit, opt-in policy that *throws a typed error*,
  never one that returns a valid-looking empty string. Drop the no-op `isHooked()`; if anti-tamper is
  offered at all, label it a speed bump and keep it out of the value path.
- **Honest memory story.** Either expose secrets as a caller-owned `Data`/`[UInt8]` the caller can
  scrub, or remove `ProtectedSecret`'s zeroing claim (fixes M1). Document plainly that Swift `String`
  cannot be reliably zeroed and that iOS gives weak memory guarantees regardless.

## Decision 5 — Hardened, default-strict runner

Two profiles, `strict` default in templates (addresses H4):

| | `strict` (default) | `compat` (opt-in, documented as lower assurance) |
|--|--|--|
| Compiler ref | Locked from `Package.resolved`; build fails closed if absent | May fall back to a configured ref |
| Revision check | Verify checkout revision == resolved revision; verify tag signature or pinned commit | Best-effort |
| Ambient binary | `SECRETSKIT_CLI_PATH` / `PATH` accepted **only** if digest matches a pinned value | Accepted |
| `main` fallback | Never | Allowed with a warning |
| Vault transport | HTTPS required; insecure HTTP only via loud explicit flag | Same |

`seal`/`validate` process plaintext secrets, so the binary that does it must be provenance-pinned.

## Decision 6 — Provider hardening

- **Vault:** require HTTPS (H3); build the request path with `URLComponents`/validated segments
  rather than string concatenation; reject path/mount values containing query, fragment, control
  chars, or empty segments; bound the timeout; reject non-string KV values instead of
  `String(describing:)` (M2).
- **File:** either document the `.xcconfig` subset supported or use a stricter parser that rejects
  constructs it does not understand rather than silently misparsing (M3).

## What v2 explicitly does **not** promise

Stated up front in the README and `SecurityNotes`, so nobody over-relies:

- Tier A bundled values are **not secret** from a determined reverse engineer. Only `clientBundled`
  values that tolerate eventual disclosure belong there.
- Anti-debug / anti-hook is **not** a security boundary.
- In-memory secrets **cannot** be reliably scrubbed on iOS.
- The only path that protects a high-value secret is **Tier B (don't bundle it)**.

After v2, the worst a misuse can do is over-trust a `clientBundled` value — and the classification
report plus the `serverOnly` build-failure make that hard to do by accident. The fundamental flaw is
designed out.
