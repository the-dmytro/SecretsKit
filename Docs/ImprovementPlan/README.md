# SecretsKit Improvement Plan

Status: proposal · Author: analysis pass 2026-06-12 · Scope: whole package

This package is a forward-looking plan. It is distinct from [`Docs/SecurityAudit.md`](../SecurityAudit.md)
(a fix list for the current implementation) and goes further: it states the threat model
honestly, catalogs every concrete flaw found in the code (including several the audit missed),
and proposes a **v2 architecture that is free from the fundamental flaw by design** — plus a
phased roadmap so you can get there incrementally.

## The one-paragraph verdict

SecretsKit today has a **fatal cryptographic design flaw and several runtime foot-guns**, but its
*stated goal* also contains an **irreducible contradiction** that no amount of fixing can remove:
"include secrets in the bundle in a way that prevents easy extraction" is achievable only for the
word *easy*. Any symmetric secret shipped inside a client app is recoverable by whoever holds the
app, because the app must be able to recover it unaided — and so can an attacker with the same
bytes. The current code makes this worse by shipping the decryption key **inside the same file as
the ciphertext**, so "extraction" is not even hard: it is a ten-line script. The path to a robust
SecretsKit is therefore not "stronger crypto." It is **(1) be honest about what is bundled, (2) make
the design refuse to bundle things that must stay secret, and (3) provide a real server-mediated
path for the secrets that matter.**

## What to read

| Doc | What it answers |
|-----|-----------------|
| [01-threat-model.md](01-threat-model.md) | What are we actually defending against? Why the stated goal is partly impossible, and what "robust" can honestly mean. |
| [02-flaw-catalog.md](02-flaw-catalog.md) | Every concrete flaw, severity-ranked, with `file:line` references and which are new vs. already in the audit. |
| [03-target-architecture-v2.md](03-target-architecture-v2.md) | The redesign that removes the fundamental flaw *by construction*: tiered classification, key/ciphertext separation, signed manifest, server-mediated tier, honest API. |
| [04-roadmap.md](04-roadmap.md) | Phased execution: cheap correctness fixes now → v1 hardening → v2 redesign. Effort estimates and a decision gate. |

## The recommendation in brief

Do **both**, in order — they are not mutually exclusive:

1. **Phase 0 — stop the bleeding (days).** Fix the runtime foot-guns that can corrupt or crash a
   shipping app *regardless of the crypto question*: the `fatalError` crashes, the
   silent-empty-string-on-debugger behavior, the ineffective memory zeroing, the Vault-over-HTTP
   hole. These are pure wins with no design debate.

2. **Phase 1 — make the obfuscation honest and the build trustworthy (1–2 weeks).** Separate the
   key from the ciphertext (compile the key into the binary, ship only ciphertext as a resource),
   fix the nonce reuse, add per-key domain separation, sign the manifest for integrity, and harden
   the runner's compiler provenance. This does not make bundled secrets *secure* — nothing can — but
   it makes the "easy extraction" claim true again and removes the misleading crypto theater.

3. **Phase 2 — the by-design fix (project-sized).** Introduce a mandatory `classification` per key.
   `serverOnly` keys **fail the build if routed into the bundle**. Add the server-mediated tier
   (short-lived tokens gated by App Attest / DeviceCheck) as the sanctioned home for high-value
   secrets. After this, the product *cannot* be misused to bundle a true secret — the fundamental
   flaw is gone by construction, not by documentation.

If you only ever do Phase 0, the app is safe to run. If you do Phase 0+1, the tool stops lying about
what it provides. Phase 2 is what makes the design itself sound.
