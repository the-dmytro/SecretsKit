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

private func loadSchema(from args: CLIArguments, env: [String: String]) throws -> SecretsSchema? {
    if let path = args.option("schema") ?? env["SECRETS_SCHEMA_PATH"] {
        return try SecretsSchema.load(from: path)
    }
    return nil
}

private func makeProvider(from args: CLIArguments, env: [String: String]) throws -> SecretsProvider {
    let providerName = (args.option("provider") ?? env["SECRETS_PROVIDER"] ?? "file").lowercased()
    switch providerName {
    case "file":
        guard let source = args.option("source") ?? env["SECRETS_SOURCE_PATH"] else {
            throw SecretCompilerError.missingSource
        }
        return FileSecretsProvider(sourcePath: source)
    case "env":
        return EnvSecretsProvider(environment: env)
    case "vault":
        return VaultSecretsProvider()
    default:
        throw SecretCompilerError.unsupportedProvider(providerName)
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
    let schema = try loadSchema(from: args, env: env)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let keys = requiredKeys(schema: schema, override: requiredOverride)
    if keys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    let provider = try makeProvider(from: args, env: env)
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
    let schema = try loadSchema(from: args, env: env)
    let requiredOverride = args.option("required-keys") ?? env["SECRETS_REQUIRED_KEYS"]
    let keys = allKeys(schema: schema, requiredOverride: requiredOverride)
    if keys.isEmpty {
        throw SecretCompilerError.missingSchema
    }

    guard let outputPath = args.option("output") ?? env["SECRETS_OUTPUT_PATH"] else {
        throw SecretCompilerError.missingOutput
    }

    let provider = try makeProvider(from: args, env: env)
    let secrets = try provider.loadSecrets(for: keys)
    let regex = placeholderRegex(from: args.option("placeholder-regex") ?? env["SECRETS_PLACEHOLDER_REGEX"])

    var hasErrors = false
    let required = requiredKeys(schema: schema, override: requiredOverride)
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
      secretcompiler validate --schema <path> --provider <file|env|vault> --source <path>
      secretcompiler seal --schema <path> --provider <file|env|vault> --source <path> --output <path>

    Environment:
      SECRETS_SCHEMA_PATH
      SECRETS_PROVIDER
      SECRETS_SOURCE_PATH
      SECRETS_OUTPUT_PATH
      SECRETS_REQUIRED_KEYS
      SECRETS_PLACEHOLDER_REGEX
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
