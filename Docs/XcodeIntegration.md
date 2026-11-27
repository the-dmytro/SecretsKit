# Xcode integration

1. Add `https://github.com/the-dmytro/SecretsKit.git` as a Swift package dependency and link
   `SecretsRuntime` to each target that reads bundled values.
2. Create `Config/Secrets.schema.json` with key names and classifications. Copy the example config
   to `Config/SecretsKit.config.json` and choose a provider. Paths in the config, including
   `schemaPath` and `file.sourcePath`, are relative to the config directory. Commit both files
   without secret values. [Example schema](../Config/Secrets.schema.json) ·
   [Example config](../Config/SecretsKit.config.json.example)
   For 1Password, use SecretsKit 0.5.0 or later, configure `vault.backend`
   and the field references, and make the authenticated `op` CLI available to
   the build. [1Password setup](VaultProvider.md#1password)

3. Copy the runner and wrappers into `Scripts/SecretsKit/`. From the consumer project root, run
   `chmod +x Scripts/SecretsKit/*.sh`. Provision an approved macOS compiler and make its absolute
   path and approved SHA-256 available to both your shell and Xcode build phases.
   [Templates and ignore entries](../IntegrationTemplates/README.md) ·
   [Compiler setup](RunnerIntegration.md#provision-the-compiler)
4. If you ship obfuscated values, generate the key once from the consumer project root.

   ```sh
   "$SECRETSKIT_CLI_PATH" generate-key \
     --symbol AppObfKey \
     --swift-output Sources/Generated/AppObfKey.swift \
     --material-output Config/AppObfKey.material
   ```

   Add the generated Swift file to the consuming target. Keep the matching `.material` file out
   of source control and make it available wherever you seal. In the seal wrapper, set
   `SECRETS_OBF_KEY_MATERIAL="${SRCROOT}/Config/AppObfKey.material"` and export it.

5. Add a **Validate Secrets** Run Script phase early in the target's build phases. Add a
   **Seal Secrets** phase after **Copy Bundle Resources**.

   ```sh
   "${SRCROOT}/Scripts/SecretsKit/validate_secrets.sh"
   ```

   ```sh
   "${SRCROOT}/Scripts/SecretsKit/seal_secrets.sh"
   ```

   By default, the runner writes to
   `${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.sealed`. If you override the
   path, make sure the resource ends up in the bundle your app passes to `SecretsManager`.
   Run the phase in each target that needs its own resource.

[Runtime usage](../README.md#runtime-usage) · [CI setup](CI.md)
