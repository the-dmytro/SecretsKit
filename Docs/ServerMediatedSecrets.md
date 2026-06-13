# Server-Mediated Secrets (`serverOnly`)

This is the **optional** home for keys you classify `serverOnly` — secrets that would be a genuine
breach if extracted, *and* for which you control a backend that can hand out access. If you don't have
a backend, or the value is genuinely fine to ship (a publishable key, a local-only credential on an
autonomous device), you do **not** need this — classify the key `public` or `clientBundled` and bundle
it. See the classification guidance in
[`Docs/ImprovementPlan/03-target-architecture-v2.md`](ImprovementPlan/03-target-architecture-v2.md).

## Why bundling cannot protect a real secret

Anything in the app bundle — obfuscated or not — is recoverable by whoever holds the app. The only way
to protect a high-value secret is to **never put it on the device**: keep it on a server and hand the
client a short-lived, scoped, revocable token instead. SecretsKit enforces the boundary at build time
(`seal` refuses to bundle a `serverOnly` key), but issuing tokens is the backend's job.

## What SecretsKit guarantees today

- A key classified `serverOnly` is **never written to `Secrets.sealed`**. `seal` excludes it and lists
  it in the classification report as `NOT bundled`.
- Explicitly routing a `serverOnly` key into the bundle (e.g. naming it in `--required-keys`) **fails
  the build** with a clear error.

That is the structural half. The runtime token-exchange client is **not yet implemented** — the
contract below is what to build (or wire to an existing backend).

## The contract to implement

```
            ┌─────────┐   1. attest device + request token (scope)    ┌──────────────┐
            │  app    │ ────────────────────────────────────────────▶ │  your backend │
            │ (client)│ ◀──────────────────────────────────────────── │              │
            └─────────┘   2. short-lived, scoped token (+ expiry)      └──────┬───────┘
                                                                              │ holds the
                                                                              │ real secret
                                                                       ┌──────▼───────┐
                                                                       │ upstream API │
                                                                       └──────────────┘
```

1. **Attest the client.** Gate token issuance on **App Attest** (`DCAppAttestService`, iOS 14+) or
   **DeviceCheck**, so only genuine, unmodified instances of your app on real hardware get a token.
   This is the property no bundling scheme can provide. *watchOS note:* App Attest is unavailable on
   watchOS — mediate through the paired iPhone app, or accept a weaker DeviceCheck-based assertion and
   document it.
2. **Issue a short-lived, scoped token.** The backend authenticates the attestation, then returns a
   token that (a) expires quickly, (b) is scoped to the minimum needed, and (c) can be revoked
   server-side. A leaked token expires; a bundled secret can only be rotated by shipping a new build to
   every user.
3. **Use and refresh.** The client uses the token for upstream calls and re-runs the exchange when it
   expires. Never cache the underlying secret on device.

### Backend responsibilities

- Verify App Attest/DeviceCheck assertions; reject unknown or replayed attestations.
- Mint least-privilege, short-TTL tokens; support revocation.
- Keep the real secret server-side only; never return it to the client.

### Client responsibilities

- Perform attestation and token exchange; hold only the short-lived token, in memory.
- Treat token-exchange failure as a recoverable error, not a crash.

## Vault note

If the real secret lives in HashiCorp Vault, your **backend** reads it from Vault at request time and
issues the derived token — the build-time `vault` provider in SecretsKit is for `clientBundled` values
only and must never be pointed at a `serverOnly` secret destined for the bundle. Prefer short-lived,
CI-native Vault auth (OIDC/JWT) over long-lived `VAULT_TOKEN`s; see [`VaultProvider.md`](VaultProvider.md).

## Status

Build-time enforcement: **shipped** (0.4.0). Runtime token-exchange client + reference backend:
**planned** — this document defines the contract so `serverOnly` keys have a real destination instead
of being quietly downgraded to `clientBundled`.
