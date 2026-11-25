# Integration Templates

This folder contains copy-ready templates for consumer projects.

- [`secretskit.sh`](Scripts/SecretsKit/secretskit.sh) is the project-owned runner script.
- [`validate_secrets.sh`](Scripts/SecretsKit/validate_secrets.sh) is an optional build-phase wrapper for validation.
- [`seal_secrets.sh`](Scripts/SecretsKit/seal_secrets.sh) is an optional build-phase wrapper for sealing.

## Keep secrets out of source control

Add these entries to the **consumer project's** `.gitignore`:

```
# Runner cache (cloned SecretsKit checkout + built secretcompiler)
.tools/
# Sealed output and obfuscation key material
*.sealed
*.material
# Local plaintext secrets file
Secrets.xcconfig
```

Commit the runner, wrappers, schema, and config without plaintext values. Add the generated
`AppObfKey.swift` to the consuming target and keep the matching `.material` file available
to the seal step. If you use a plaintext source with a different filename, ignore that
path too. [Xcode setup](../Docs/XcodeIntegration.md) · [Security notes](../Docs/SecurityNotes.md)
