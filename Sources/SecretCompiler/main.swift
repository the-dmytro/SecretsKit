#if os(macOS)
import Foundation
import SecretsRuntime

private func parseCsv(_ value: String) -> [String] {
    return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

func placeholderRegex(from value: String?) throws -> NSRegularExpression {
    let fallbackPattern = "(YOUR_.*|__.*__|PLACEHOLDER|REPLACE_ME)"
    guard let value, !value.isEmpty else {
        return try NSRegularExpression(pattern: fallbackPattern, options: [])
    }
    do {
        return try NSRegularExpression(pattern: value, options: [])
    } catch {
        throw SecretCompilerError.invalidPlaceholderRegex(value)
    }
}

func isPlaceholder(_ value: String, regex: NSRegularExpression) -> Bool {
    if value.isEmpty { return true }
    let range = NSRange(location: 0, length: value.utf16.count)
    return regex.firstMatch(in: value, options: [], range: range) != nil
}

private func loadConfig(from args: CLIArguments, env: [String: String]) throws -> SecretsKitConfig? {
    if let path = args.option("config") ?? env["SECRETS_CONFIG_PATH"] {
        return try SecretsKitConfig.load(from: path)
    }
    return nil
}

private func loadSchema(from args: CLIArguments, env: [String: String], config: SecretsKitConfig?) throws -> SecretsSchema? {
    if let path = args.option("schema") ?? env["SECRETS_SCHEMA_PATH"] ?? config?.schemaPath {
        return try SecretsSchema.load(from: path)
    }
    return nil
}

private func parseBool(_ value: String?) -> Bool? {
    guard let value else { return nil }
    switch value.lowercased() {
    case "1", "true", "yes", "y":
        return true
    case "0", "false", "no", "n":
        return false
    default:
        return nil
    }
}

private struct VaultSettings {
    let address: String
    let token: String
    let namespace: String?
    let requestPath: String
    let kvVersion: Int
    let timeoutSeconds: Double
}

private func resolveVaultSettings(env: [String: String], config: SecretsKitConfig?) throws -> VaultSettings {
    let vaultConfig = config?.file.vault
    let addrEnv = vaultConfig?.addrEnv ?? "VAULT_ADDR"
    let tokenEnv = vaultConfig?.tokenEnv ?? "VAULT_TOKEN"
    let namespaceEnv = vaultConfig?.namespaceEnv ?? "VAULT_NAMESPACE"
    let mountEnv = vaultConfig?.mountEnv ?? "SECRETS_VAULT_MOUNT"
    let pathEnv = vaultConfig?.pathEnv ?? "SECRETS_VAULT_PATH"

    let address = env[addrEnv] ?? vaultConfig?.addr
    let token = env[tokenEnv]
    let namespace = env[namespaceEnv]
    let mount = env[mountEnv] ?? vaultConfig?.mount ?? "secret"
    let path = env[pathEnv] ?? vaultConfig?.path
    let kvVersion = Int(env["SECRETS_VAULT_KV_VERSION"] ?? "") ?? vaultConfig?.kvVersion ?? 2
    let rawTimeout = Double(env["SECRETS_VAULT_TIMEOUT"] ?? "") ?? vaultConfig?.timeoutSeconds ?? 10
    let timeoutSeconds = min(max(rawTimeout, 1), 60)

    guard let address, !address.isEmpty else {
        throw SecretCompilerError.missingVaultConfig(addrEnv)
    }
    let allowInsecureHTTP = parseBool(env["SECRETS_VAULT_ALLOW_INSECURE_HTTP"]) ?? false
    try validateVaultTransport(address: address, allowInsecureHTTP: allowInsecureHTTP)
    guard let token, !token.isEmpty else {
        throw SecretCompilerError.missingVaultConfig(tokenEnv)
    }
    guard let path, !path.isEmpty else {
        throw SecretCompilerError.missingVaultConfig(pathEnv)
    }

    let requestPath = try buildVaultRequestPath(mount: mount, path: path, kvVersion: kvVersion)

    return VaultSettings(
        address: address,
        token: token,
        namespace: namespace,
        requestPath: requestPath,
        kvVersion: kvVersion,
        timeoutSeconds: timeoutSeconds
    )
}

private func makeProvider(from args: CLIArguments, env: [String: String], config: SecretsKitConfig?, requiredKeys: [String]) throws -> SecretsProvider {
    let providerName = (args.option("provider") ?? env["SECRETS_PROVIDER"] ?? config?.file.provider ?? "file").lowercased()

    let factory: (String) throws -> SecretsProvider = { name in
        switch name.lowercased() {
        case "file":
            guard let source = args.option("source") ?? env["SECRETS_SOURCE_PATH"] ?? config?.fileSourcePath else {
                throw SecretCompilerError.missingSource
            }
            return FileSecretsProvider(sourcePath: source)
        case "env":
            return EnvSecretsProvider(environment: env)
        case "vault":
            let settings = try resolveVaultSettings(env: env, config: config)
            return VaultSecretsProvider(
                address: settings.address,
                token: settings.token,
                namespace: settings.namespace,
                requestPath: settings.requestPath,
                kvVersion: settings.kvVersion,
                timeoutSeconds: settings.timeoutSeconds
            )
        default:
            throw SecretCompilerError.unsupportedProvider(name)
        }
    }

    switch providerName {
    case "auto":
        let orderOverride = env["SECRETS_AUTO_ORDER"].map(parseCsv)
        let order = orderOverride ?? config?.file.auto?.order ?? ["env", "vault", "file"]
        let allowMerge = parseBool(env["SECRETS_AUTO_MERGE"]) ?? config?.file.auto?.allowMerge ?? false
        return AutoSecretsProvider(order: order, allowMerge: allowMerge, requiredKeys: requiredKeys, providerFactory: factory)
    default:
        return try factory(providerName)
    }
}

private func requiredKeys(schema: SecretsSchema?, override: String?) -> [String] {
    if let override = override {
        return parseCsv(override)
    }
    return schema?.requiredKeys() ?? []
}

private func allKeys(schema: SecretsSchema?, requiredOverride: String?) -> [String] {
    if let override = requiredOverride {
        return parseCsv(override)
    }
    return schema?.allKeys() ?? []
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

private func parseClassification(_ raw: String) throws -> SecretClassification {
    guard let classification = SecretClassification(rawValue: raw) else {
        throw SecretCompilerError.invalidClassification(raw)
    }
    return classification
}

private struct ClassifiedKeys {
    let bundle: [String]      // public + clientBundled: eligible for the sealed bundle
    let serverOnly: [String]  // never bundled
    let defaulted: [String]   // no classification declared; treated as clientBundled
}

/// Partitions keys by classification. `serverOnly` keys are excluded from the bundle; if they were
/// explicitly routed in (e.g. a `--required-keys` override naming one), the operation aborts. Keys with
/// no declared classification default to `clientBundled` unless `requireClassification` is set.
private func classifyKeys(
    _ keys: [String],
    schema: SecretsSchema?,
    requireClassification: Bool,
    explicitlyRouted: Bool
) throws -> ClassifiedKeys {
    var bundle: [String] = []
    var serverOnly: [String] = []
    var defaulted: [String] = []
    var missing: [String] = []

    for key in keys.sorted() {
        let classification: SecretClassification
        if let raw = schema?.rawClassification(for: key) {
            classification = try parseClassification(raw)
        } else if requireClassification {
            missing.append(key)
            continue
        } else {
            classification = .clientBundled
            defaulted.append(key)
        }
        switch classification {
        case .serverOnly:
            serverOnly.append(key)
        case .public, .clientBundled:
            bundle.append(key)
        }
    }

    if !missing.isEmpty {
        throw SecretCompilerError.missingClassification(missing)
    }
    if !serverOnly.isEmpty && explicitlyRouted {
        throw SecretCompilerError.serverOnlyKeysRouted(serverOnly)
    }
    return ClassifiedKeys(bundle: bundle, serverOnly: serverOnly, defaulted: defaulted)
}

private func requireClassificationFlag(args: CLIArguments, env: [String: String]) -> Bool {
    return parseBool(args.option("require-classification") ?? env["SECRETSKIT_REQUIRE_CLASSIFICATION"]) ?? false
}

/// Prints a key → classification report to stderr. Never prints secret values.
private func printClassificationReport(_ classified: ClassifiedKeys, schema: SecretsSchema?) {
    var lines = ["SecretsKit classification:"]
    for key in classified.bundle {
        let label = schema?.rawClassification(for: key) ?? "clientBundled (defaulted)"
        lines.append("  \(key): \(label)")
    }
    for key in classified.serverOnly {
        lines.append("  \(key): serverOnly — NOT bundled")
    }
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
}

func writeSealedData(_ data: Data, to outputPath: String) throws {
    try writeDataWithOwnerOnlyPermissions(data, to: outputPath)
    print("Secrets sealed to \(URL(fileURLWithPath: outputPath).path)")
}

private func writeDataWithOwnerOnlyPermissions(_ data: Data, to outputPath: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
        throw SecretCompilerError.fileWriteFailed(outputPath)
    }
    let tempURL = outputURL.deletingLastPathComponent()
        .appendingPathComponent(".\(outputURL.lastPathComponent).tmp-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: tempURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw SecretCompilerError.fileWriteFailed(outputPath)
    }
    do {
        _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL, backupItemName: nil, options: [.usingNewMetadataOnly])
    } catch {
        _ = try? FileManager.default.removeItem(at: tempURL)
        throw SecretCompilerError.fileWriteFailed(outputPath)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
}

private func runValidate(args: CLIArguments, env: [String: String]) throws -> Int32 {
    let config = try loadConfig(from: args, env: env)
    let schema = try loadSchema(from: args, env: env, config: config)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let declaredKeys = requiredKeys(schema: schema, override: requiredOverride)
    if declaredKeys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    let classified = try classifyKeys(
        declaredKeys,
        schema: schema,
        requireClassification: requireClassificationFlag(args: args, env: env),
        explicitlyRouted: requiredOverride != nil
    )
    let keys = classified.bundle
    if keys.isEmpty {
        print("Secrets validation passed (no client-bundled keys to validate)")
        return 0
    }

    let provider = try makeProvider(from: args, env: env, config: config, requiredKeys: keys)
    let secrets = try provider.loadSecrets(for: keys)

    let regex = try placeholderRegex(from: args.option("placeholder-regex") ?? env["SECRETS_PLACEHOLDER_REGEX"])

    var hasErrors = false
    for key in keys {
        guard let value = secrets[key], !value.isEmpty else {
            printError("Missing secret: \(key)")
            hasErrors = true
            continue
        }
        if isPlaceholder(value, regex: regex) {
            printError("Invalid placeholder value for: \(key)")
            hasErrors = true
        }
    }

    if hasErrors {
        return 1
    }

    print("Secrets validation passed")
    return 0
}

func runSeal(args: CLIArguments, env: [String: String]) throws -> Int32 {
    let config = try loadConfig(from: args, env: env)
    let schema = try loadSchema(from: args, env: env, config: config)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let declaredKeys = allKeys(schema: schema, requiredOverride: requiredOverride)
    if declaredKeys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    guard let outputPath = args.option("output") ?? env["SECRETS_OUTPUT_PATH"] else {
        throw SecretCompilerError.missingOutput
    }

    let classified = try classifyKeys(
        declaredKeys,
        schema: schema,
        requireClassification: requireClassificationFlag(args: args, env: env),
        explicitlyRouted: requiredOverride != nil
    )
    printClassificationReport(classified, schema: schema)
    let keys = classified.bundle
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    if keys.isEmpty {
        let data = try encoder.encode(SealedSecretsV2(version: 2, format: "OBF3", entries: [:]))
        try writeSealedData(data, to: outputPath)
        return 0
    }

    let serverOnlySet = Set(classified.serverOnly)
    let required = requiredKeys(schema: schema, override: requiredOverride).filter { !serverOnlySet.contains($0) }
    let provider = try makeProvider(from: args, env: env, config: config, requiredKeys: required)
    let secrets = try provider.loadSecrets(for: keys)
    let regex = try placeholderRegex(from: args.option("placeholder-regex") ?? env["SECRETS_PLACEHOLDER_REGEX"])

    var hasErrors = false
    for key in required {
        guard let value = secrets[key], !value.isEmpty else {
            printError("Missing secret: \(key)")
            hasErrors = true
            continue
        }
        if isPlaceholder(value, regex: regex) {
            printError("Invalid placeholder value for: \(key)")
            hasErrors = true
        }
    }

    if hasErrors {
        return 1
    }

    // Every key must have a non-empty value before we seal.
    for key in keys where (secrets[key]?.isEmpty ?? true) {
        printError("Missing secret: \(key)")
        hasErrors = true
    }
    if hasErrors {
        return 1
    }

    let obfuscatedKeys = keys.filter { schema?.shouldObfuscate($0) ?? true }
    let data: Data
    let keyMaterialPath = args.option("key-material") ?? env["SECRETS_OBF_KEY_MATERIAL"]
    if let keyMaterialPath {
        // OBF3: keyless ciphertext; obfuscation key lives in the app binary.
        let obfuscationKey = try ObfuscationKeyMaterial.load(from: keyMaterialPath).obfuscationKey()
        var entries: [String: SealedEntry] = [:]
        for key in keys {
            let value = secrets[key] ?? ""
            if schema?.shouldObfuscate(key) ?? true {
                entries[key] = try SecretObfuscatorV3.seal(value, keyName: key, using: obfuscationKey)
            } else {
                entries[key] = SealedEntry.plain(value)
            }
        }
        data = try encoder.encode(SealedSecretsV2(version: 2, format: "OBF3", entries: entries))
    } else if obfuscatedKeys.isEmpty {
        var entries: [String: SealedEntry] = [:]
        for key in keys {
            entries[key] = SealedEntry.plain(secrets[key] ?? "")
        }
        data = try encoder.encode(SealedSecretsV2(version: 2, format: "OBF3", entries: entries))
    } else if explicitLegacyOBF2OptIn(args: args, env: env) {
        // Legacy OBF2: obfuscation material embedded in the file. Kept only for explicit migration.
        FileHandle.standardError.write(Data("warning: sealing in legacy OBF2 format (obfuscation key embedded in the bundle). Generate OBF3 key material and pass --key-material as soon as possible.\n".utf8))
        let material = try SecretObfuscationMaterial.generate()
        var sealedMap: [String: String] = [:]
        for key in keys {
            let value = secrets[key] ?? ""
            if schema?.shouldObfuscate(key) ?? true {
                sealedMap[key] = try SecretObfuscator.obfuscate(value, material: material)
            } else {
                sealedMap[key] = value
            }
        }
        data = try encoder.encode(SealedSecrets(version: 1, format: "OBF2", obfuscation: material, secrets: sealedMap))
    } else {
        throw SecretCompilerError.legacyOBF2RequiresExplicitOptIn
    }

    try writeSealedData(data, to: outputPath)
    return 0
}

private func explicitLegacyOBF2OptIn(args: CLIArguments, env: [String: String]) -> Bool {
    return parseBool(args.option("legacy-obf2") ?? env["SECRETSKIT_ALLOW_LEGACY_OBF2"] ?? env["SECRETS_ALLOW_LEGACY_OBF2"]) ?? false
}

private func runGenerateKey(args: CLIArguments, env: [String: String]) throws -> Int32 {
    let symbol = args.option("symbol") ?? env["SECRETS_OBF_KEY_SYMBOL"] ?? "GeneratedSecretsObfuscationKey"

    guard let swiftOutput = args.option("swift-output") ?? env["SECRETS_OBF_KEY_SWIFT_OUTPUT"] else {
        throw SecretCompilerError.missingOutput
    }
    let materialOutput = args.option("material-output")
        ?? env["SECRETS_OBF_KEY_MATERIAL"]
        ?? ((swiftOutput as NSString).deletingPathExtension + ".material")

    let material = try ObfuscationKeyMaterial.generate()

    let swiftURL = URL(fileURLWithPath: swiftOutput)
    try FileManager.default.createDirectory(at: swiftURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    try Data(material.swiftSource(symbol: symbol).utf8).write(to: swiftURL, options: [.atomic])
    print("Obfuscation key (Swift) written to \(swiftURL.path) — compile this into your app target.")

    let materialURL = URL(fileURLWithPath: materialOutput)
    try FileManager.default.createDirectory(at: materialURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try writeDataWithOwnerOnlyPermissions(encoder.encode(material), to: materialURL.path)
    print("Obfuscation key material written to \(materialURL.path) — pass to `seal` via --key-material.")

    return 0
}

private func printUsage() {
    let message = """
    Usage:
      secretcompiler validate --config <path> --schema <path> --provider <file|env|vault|auto> --source <path>
      secretcompiler seal --config <path> --schema <path> --provider <file|env|vault|auto> --source <path> --output <path> --key-material <path>
      secretcompiler seal ... --legacy-obf2   # explicit migration-only fallback
      secretcompiler generate-key --swift-output <path> [--material-output <path>] [--symbol <name>]
      secretcompiler version [--json]

    Notes:
      seal writes keyless OBF3. Obfuscated entries require --key-material; legacy OBF2 requires
      explicit --legacy-obf2 or SECRETSKIT_ALLOW_LEGACY_OBF2=1.
      generate-key produces the obfuscation key once: a Swift file to compile into your app, plus a
      .material sidecar to pass to seal.
      Each key may declare a classification (public | clientBundled | serverOnly). serverOnly keys are
      never bundled. Pass --require-classification to fail on any key without one.

    Environment:
      SECRETS_CONFIG_PATH
      SECRETS_SCHEMA_PATH
      SECRETS_PROVIDER
      SECRETS_SOURCE_PATH
      SECRETS_OUTPUT_PATH
      SECRETS_REQUIRED_KEYS
      SECRETS_PLACEHOLDER_REGEX
      SECRETS_AUTO_ORDER
      SECRETS_AUTO_MERGE
      VAULT_ADDR
      VAULT_TOKEN
      VAULT_NAMESPACE
      SECRETS_VAULT_MOUNT
      SECRETS_VAULT_PATH
      SECRETS_VAULT_KV_VERSION
      SECRETS_VAULT_TIMEOUT
      SECRETS_VAULT_ALLOW_INSECURE_HTTP
      SECRETS_OBF_KEY_MATERIAL
      SECRETSKIT_ALLOW_LEGACY_OBF2
      SECRETS_OBF_KEY_SWIFT_OUTPUT
      SECRETS_OBF_KEY_SYMBOL
      SECRETSKIT_REQUIRE_CLASSIFICATION
    """
    print(message)
}

func main() -> Int32 {
    guard let args = CLIArguments.parse(CommandLine.arguments) else {
        printUsage()
        return 1
    }

    let env = ProcessInfo.processInfo.environment

    do {
        switch args.command {
        case "validate":
            return try runValidate(args: args, env: env)
        case "seal", "obfuscate":
            return try runSeal(args: args, env: env)
        case "generate-key":
            return try runGenerateKey(args: args, env: env)
        case "version", "--version":
            if args.option("json") == "true" {
                let payload = ["version": SecretsKitVersion.current]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                if let output = String(data: data, encoding: .utf8) {
                    print(output)
                }
            } else {
                print("secretcompiler \(SecretsKitVersion.current)")
            }
            return 0
        default:
            printUsage()
            return 1
        }
    } catch SecretCompilerError.missingSchema {
        printError("Missing secrets schema or required keys override")
        return 1
    } catch SecretCompilerError.missingSource {
        printError("Missing secrets source path")
        return 1
    } catch SecretCompilerError.missingOutput {
        printError("Missing output path")
        return 1
    } catch SecretCompilerError.unsupportedProvider(let name) {
        printError("Unsupported provider: \(name)")
        return 1
    } catch SecretCompilerError.missingVaultConfig(let name) {
        printError("Missing Vault configuration: \(name)")
        return 1
    } catch SecretCompilerError.vaultInsecureTransport(let address) {
        printError("Refusing insecure Vault transport for \(address). Use https, or set SECRETS_VAULT_ALLOW_INSECURE_HTTP=1 for local development only.")
        return 1
    } catch SecretCompilerError.vaultRequestFailed(let message) {
        printError("Vault request failed: \(message)")
        return 1
    } catch SecretCompilerError.vaultInvalidResponse(let message) {
        printError("Invalid Vault response: \(message)")
        return 1
    } catch SecretCompilerError.invalidKeyMaterial(let detail) {
        printError("Invalid obfuscation key material: \(detail)")
        return 1
    } catch SecretCompilerError.invalidPlaceholderRegex(let pattern) {
        printError("Invalid placeholder regex '\(pattern)'. Fix --placeholder-regex / SECRETS_PLACEHOLDER_REGEX.")
        return 1
    } catch SecretCompilerError.fileWriteFailed(let path) {
        printError("Failed to write sealed output to \(path)")
        return 1
    } catch SecretCompilerError.legacyOBF2RequiresExplicitOptIn {
        printError("Refusing to seal obfuscated entries in legacy OBF2 by default. Run `secretcompiler generate-key` and pass --key-material for OBF3, or set --legacy-obf2 for migration only.")
        return 1
    } catch SecretCompilerError.missingClassification(let keys) {
        printError("These keys need a classification (public | clientBundled | serverOnly): \(keys.joined(separator: ", "))")
        return 1
    } catch SecretCompilerError.invalidClassification(let raw) {
        printError("Invalid classification '\(raw)'. Use public, clientBundled, or serverOnly.")
        return 1
    } catch SecretCompilerError.serverOnlyKeysRouted(let keys) {
        printError("serverOnly keys must never be bundled: \(keys.joined(separator: ", ")). Remove them from the bundle scope or fetch them via a backend (see Docs/ServerMediatedSecrets.md).")
        return 1
    } catch SecretCompilerError.autoProviderFailed(let attempts) {
        printError("Auto provider failed to satisfy required keys")
        for attempt in attempts {
            printError("Provider \(attempt.provider): \(attempt.reason)")
        }
        return 1
    } catch {
        printError("Unexpected error: \(error)")
        return 1
    }
}

exit(main())
#endif

#if !os(macOS)
import Foundation

fputs("secretcompiler is macOS-only.\n", stderr)
exit(1)
#endif
