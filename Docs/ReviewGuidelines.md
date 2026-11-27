# Review guide

Start with the [package manifest](../Package.swift) and the [security boundaries](SecurityNotes.md).
Review changes at the boundary they affect and update the consumer guide when that contract changes.

| Area | What to check |
| --- | --- |
| [Compiler](../Sources/SecretCompiler) | Classification and explicit required-key overrides agree across validate and seal. Output keeps owner-only permissions. Diagnostics identify keys and failures without printing values. |
| [Runtime](../Sources/SecretsRuntime) | Compiler output can be read by the runtime. Check keyless plaintext, obfuscated entries, and legacy read compatibility when changing the format or accessors. |
| [Runner](../IntegrationTemplates/Scripts/SecretsKit) | Check explicit path, PATH and cached compiler selection. Review digest checks across resolve and bootstrap, and confirm the example config and guides describe the same policy. |
| [Providers](../Sources/SecretCompiler/SecretsProvider.swift) | Check how required keys affect selection and merging. Review HashiCorp Vault transport, KV paths, and tokens together. For 1Password, check requested-key isolation, bounded subprocess handling, and redaction. For `exec`, check the child argument boundary, required-key environment, and exit behavior. |

## Verification

Run `swift test` from the repository root on macOS. The package has two XCTest targets.
[Compiler tests](../Tests/SecretCompilerTests) cover classification, placeholder handling,
sealed formats and file permissions, HashiCorp Vault paths and transport, fake `op` lookups,
`exec` handoff, and runner policy.
[Runtime tests](../Tests/SecretsRuntimeTests) cover sealed-resource loading and value access.
The compiler tests use temporary fixtures and subprocesses for local CLI and runner behavior.

Use synthetic values in test fixtures. For changes to consumer setup, also check the affected
Xcode build phase or CI wrapper with synthetic inputs. The package suite exercises the local
compiler and runtime. Live HashiCorp Vault or 1Password access and a consuming Xcode project require separate checks.
For documentation-only changes, check links, example paths and commands, and `git diff --check`.
