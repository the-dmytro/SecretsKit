# Runner Integration (Recommended)

This guide describes the project-owned runner approach. The runner is committed in the consumer repo and is the only script called by Xcode build phases.

## Why a runner script
- Avoids relying on DerivedData paths for remote SPM packages.
- Allows teams to choose how `secretcompiler` is provisioned:
  - Homebrew (fast-path),
  - cached source build (default fallback),
  - explicit path override.

## Expected files in the consumer repo
- `Scripts/SecretsKit/secretskit.sh` (runner, committed)
- `Scripts/SecretsKit/validate_secrets.sh` (optional wrapper)
- `Scripts/SecretsKit/seal_secrets.sh` (optional wrapper)
- `Config/SecretsKit.config.json` (non-secret, committed)
- `Config/Secrets.schema.json` (non-secret, committed)

The runner template is available in:
- `IntegrationTemplates/Scripts/SecretsKit/secretskit.sh`
An example config is available in:
- `Config/SecretsKit.config.json.example`

## Install / bootstrap
You can bootstrap the tool once per machine:
```
./Scripts/SecretsKit/secretskit.sh install
```

## Build phases
Call the runner or wrappers from Xcode build phases:
```
${SRCROOT}/Scripts/SecretsKit/validate_secrets.sh
${SRCROOT}/Scripts/SecretsKit/seal_secrets.sh
```

Use `SECRETS_CONFIG_PATH` if the config lives outside `Config/SecretsKit.config.json`.
If you need to export additional `SECRETS_*` values, do it inside the wrapper scripts.

## Tool resolution order (runner)
1) `SECRETSKIT_CLI_PATH` (explicit path)
2) `secretcompiler` on `PATH` (Homebrew or manual install)
3) cached source build (when present)

If none is available, the runner prints actionable instructions.
