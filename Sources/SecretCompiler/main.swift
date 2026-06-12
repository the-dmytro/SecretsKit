#if os(macOS)
import Foundation
import SecretsRuntime

private let defaultPlaceholderPattern = "(YOUR_.*|__.*__|PLACEHOLDER|REPLACE_ME)"

private func parseCsv(_ value: String) -> [String] {
    return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

private func placeholderRegex(from value: String?) -> NSRegularExpression {
    let pattern = value ?? defaultPlaceholderPattern
    return (try? NSRegularExpression(pattern: pattern, options: [])) ?? (try? NSRegularExpression(pattern: defaultPlaceholderPattern, options: []))!
}

private func isPlaceholder(_ value: String, regex: NSRegularExpression) -> Bool {
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
    let timeoutSeconds = Double(env["SECRETS_VAULT_TIMEOUT"] ?? "") ?? vaultConfig?.timeoutSeconds ?? 10

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

    let trimmedMount = mount.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let requestPath: String
    if trimmedMount.isEmpty {
        requestPath = trimmedPath
    } else if trimmedPath.hasPrefix(trimmedMount + "/") {
        requestPath = trimmedPath
    } else if kvVersion == 2 {
        requestPath = "\(trimmedMount)/data/\(trimmedPath)"
    } else {
        requestPath = "\(trimmedMount)/\(trimmedPath)"
    }

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

private func runValidate(args: CLIArguments, env: [String: String]) throws -> Int32 {
    let config = try loadConfig(from: args, env: env)
    let schema = try loadSchema(from: args, env: env, config: config)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let keys = requiredKeys(schema: schema, override: requiredOverride)
    if keys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    let provider = try makeProvider(from: args, env: env, config: config, requiredKeys: keys)
    let secrets = try provider.loadSecrets(for: keys)

    let regex = placeholderRegex(from: args.option("placeholder-regex") ?? env["SECRETS_PLACEHOLDER_REGEX"])

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

private func runSeal(args: CLIArguments, env: [String: String]) throws -> Int32 {
    let config = try loadConfig(from: args, env: env)
    let schema = try loadSchema(from: args, env: env, config: config)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let keys = allKeys(schema: schema, requiredOverride: requiredOverride)
    if keys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    guard let outputPath = args.option("output") ?? env["SECRETS_OUTPUT_PATH"] else {
        throw SecretCompilerError.missingOutput
    }

    let required = requiredKeys(schema: schema, override: requiredOverride)
    let provider = try makeProvider(from: args, env: env, config: config, requiredKeys: required)
    let secrets = try provider.loadSecrets(for: keys)
    let regex = placeholderRegex(from: args.option("placeholder-regex") ?? env["SECRETS_PLACEHOLDER_REGEX"])

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

    let material = try SecretObfuscationMaterial.generate()
    var sealedMap: [String: String] = [:]
    for key in keys {
        guard let value = secrets[key], !value.isEmpty else {
            printError("Missing secret: \(key)")
            hasErrors = true
            continue
        }
        let shouldObfuscate = schema?.shouldObfuscate(key) ?? true
        if shouldObfuscate {
            let obfuscated = try SecretObfuscator.obfuscate(value, material: material)
            sealedMap[key] = obfuscated
        } else {
            sealedMap[key] = value
        }
    }

    if hasErrors {
        return 1
    }

    let sealed = SealedSecrets(version: 1, format: "OBF2", obfuscation: material, secrets: sealedMap)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(sealed)

    let outputURL = URL(fileURLWithPath: outputPath)
    let outputDir = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
    try data.write(to: outputURL, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)

    print("Secrets sealed to \(outputURL.path)")
    return 0
}

private func printUsage() {
    let message = """
    Usage:
      secretcompiler validate --config <path> --schema <path> --provider <file|env|vault|auto> --source <path>
      secretcompiler seal --config <path> --schema <path> --provider <file|env|vault|auto> --source <path> --output <path>
      secretcompiler version [--json]

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
