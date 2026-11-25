# Integration Templates

This folder contains copy-ready templates for consumer projects.

- `Scripts/SecretsKit/secretskit.sh`: project-owned runner script.
- `Scripts/SecretsKit/validate_secrets.sh`: optional build-phase wrapper for validation.
- `Scripts/SecretsKit/seal_secrets.sh`: optional build-phase wrapper for sealing.

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

Only the non-secret files belong in the repo: `secretskit.sh` and the wrappers,
`Config/SecretsKit.config.json`, `Config/Secrets.schema.json`, and the generated
`AppObfKey.swift` (it holds the obfuscation key, not your secrets — see
[`../Docs/SecurityNotes.md`](../Docs/SecurityNotes.md)).
