# Security notes

## What the build protects

SecretsKit reads values at build time so the app source and checked-in config can contain only
key names. Keep plaintext sources and generated artifacts out of version control. Use an
approved compiler and run it on a trusted build host.
[Consumer ignore entries](../IntegrationTemplates/README.md#keep-secrets-out-of-source-control) ·
[Compiler setup](RunnerIntegration.md)

| Classification | What ships |
| --- | --- |
| `public` | A plaintext entry by default |
| `clientBundled` | An obfuscated entry by default. This is also the default classification. |
| `serverOnly` | No entry. An explicit required-keys override selecting the key fails. |

A schema's `obfuscate` setting can override the default for bundled entries. Use only values
you can expose in a client app. The app contains the key needed to read obfuscated `OBF3`
entries. `OBF3` keeps that key out of `Secrets.sealed` and uses a per-entry nonce. Plaintext
entries remain readable in the resource. Legacy `OBF2` bundles carry their own key material
and remain readable for migration. [Runtime usage](../README.md#runtime-usage)

If a privileged credential is accidentally bundled, revoke or rotate it with the provider,
then remove it from the next build. Previously distributed copies still contain their original
values. [Server-mediated secrets](ServerMediatedSecrets.md)

## Vault references and process environments

The 1Password backend keeps field values in the compiler process until they
are sealed or passed to a trusted program through `exec`. Checked-in config
can contain field references. Keep provider authentication credentials in
the build or launch environment. An `exec` program inherits the caller's
environment along with the resolved values, so launch it with only the
ambient credentials it needs.
[1Password settings](VaultProvider.md#1password)

## Deferred work

- Manifest signing for whole-resource integrity. `OBF3` authenticates each obfuscated
  entry during decoding.
- A token-exchange client and reference backend for projects that need server-mediated access.
- Additional local-file guardrails, including a warning for plaintext sources inside the
  consumer repository, and a review of how Vault tokens are provisioned.

The original audit and roadmap describe earlier releases and proposals.
[Security audit and improvement plan at the last pre-cleanup commit](https://github.com/the-dmytro/SecretsKit/tree/cd957f1201e49773c2e5d94cdcf624a86fcf781c/Docs)
