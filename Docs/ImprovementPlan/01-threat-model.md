# 01 · Threat Model and the Honest Definition of "Robust"

Before any fix list, the project needs an explicit threat model, because the current code, README,
and API quietly imply a guarantee that is **physically impossible to keep**. Robustness starts with
saying out loud what is and is not achievable.

## The irreducible contradiction in the stated goal

The goal as stated is: *"keep secrets out of repos AND include them in bundles in a way that
prevents easy extracting."*

These are two different problems with two different answers:

- **"Keep secrets out of repos and build intermediates."** ✅ **Fully achievable.** Secrets never
  need to be committed, and the sealed artifact can be generated into build products rather than the
  source tree. This is real, durable value and SecretsKit should lean into it.

- **"Include them in the bundle so they can't be easily extracted."** ⚠️ **Only the word *easy* is
  achievable.** This is the *symmetric-key-in-the-client* problem. The app has no external input at
  the moment it needs the secret, so everything required to recover the plaintext must be present on
  the device. An attacker with the IPA (or a jailbroken device, or a debugger, or Frida) has exactly
  the same material the app has. There is no algorithm that lets the app decrypt while a person
  holding the same bytes cannot. Obfuscation only raises the *cost*: it can defeat `strings`, `grep`,
  and a plist dump; it cannot defeat a motivated reverse engineer.

A "robust" SecretsKit cannot mean "unextractable bundled secrets." It must mean: **achievable
properties delivered reliably, and unachievable ones designed out so nobody relies on them.**

## What SecretsKit can honestly provide

| Property | Achievable? | How |
|----------|-------------|-----|
| Secrets absent from source control | ✅ Yes | Providers (env/file/vault) + `.gitignore` discipline; sealed file emitted to build products. |
| No plaintext secrets in DerivedData / normal build logs | ✅ Yes | In-memory provider reads; CLI never prints values. |
| Resistance to *casual* extraction (`strings`, grep, plist dump) | ✅ Yes, bounded | Obfuscation + separating key from ciphertext. Raises cost, never to "secure." |
| Integrity: the app can detect a tampered/swapped bundled config | ✅ Yes | Sign the manifest at seal time; verify with an embedded public key at runtime. |
| **Secrecy of a high-value secret against a device-holding attacker** | ❌ **No, if bundled** | Only achievable by **not bundling it** — server-mediated, short-lived, revocable tokens. |
| Reliable in-memory zeroization of a recovered secret | ❌ Not with Swift `String` | Requires caller-controlled byte buffers; even then iOS gives weak guarantees. |
| Defeating a jailbreak / Frida / debugger attacker | ❌ No | Anti-debug is a speed bump, trivially bypassed; must never be a correctness gate. |

## Actors and what each can do

- **The repo reader / casual teammate.** Should never see a plaintext secret in git history or a
  build log. *Defended today, keep it.*
- **The app user with the shipped IPA.** Can unzip the bundle, run `strings`, and read any resource.
  Today they can read `Secrets.sealed` *and the key beside it* and decrypt everything in one step.
  After Phase 1 they must at least disassemble the binary to find the key. After Phase 2, true
  secrets are not in the bundle at all, so there is nothing to extract.
- **The reverse engineer (jailbreak, Frida, debugger, IDA).** Will recover *any* bundled value,
  period. The only defense is to not bundle the value. This actor is why the server-mediated tier
  exists.
- **The build-host / supply-chain attacker.** Can substitute a malicious `secretcompiler` (PATH or
  `main` fallback) that exfiltrates plaintext during sealing. Defended by provenance pinning
  (Phase 1).
- **The network attacker (Vault path).** Can read a `VAULT_TOKEN` sent over plaintext HTTP, or
  redirect via an unvalidated URL. Defended by HTTPS-only + validated path construction (Phase 1).

## The design principle that follows

> **A client secrets system is only sound if its design refuses to bundle what it cannot protect.**

Everything in the v2 architecture ([03-target-architecture-v2.md](03-target-architecture-v2.md))
follows from this single sentence. Obfuscation quality is a secondary, bounded concern; the primary
correctness property is that a `serverOnly` secret **cannot** end up in the bundle, even by mistake,
because the build fails. That is the difference between "we documented the risk" (today) and "the
risk is structurally impossible" (target).
