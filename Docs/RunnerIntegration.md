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

## Compiler provenance policy

The runner defaults to **`strict`** (set `cli.policy` in the config, or `SECRETSKIT_CLI_POLICY`):

- **`strict`** (default, recommended for builds that process plaintext secrets):
  - Resolves the compiler ref from `Package.resolved`; **no silent `main` fallback** — fails closed if
    no ref is resolvable.
  - Refuses an ambient `SECRETSKIT_CLI_PATH` or `PATH` `secretcompiler` **unless** `SECRETSKIT_CLI_SHA256`
    matches its digest; otherwise builds the pinned ref from source.
  - Verifies the checked-out revision equals the resolved revision after bootstrap.
- **`compatible`** (opt-down, lower assurance): the previous flexible behavior — explicit path, then
  `PATH` binary, then cached source build, with a `main` fallback.

### Tool resolution order
- `strict`: digest-pinned `SECRETSKIT_CLI_PATH` → digest-pinned `PATH` binary → cached/bootstrapped
  build of the locked ref.
- `compatible`: `SECRETSKIT_CLI_PATH` → `PATH` binary → cached source build → `main`.

If none is available, the runner prints actionable instructions.
