import Foundation

enum SecretCompilerError: Error {
    case missingSchema
    case missingSource
    case missingOutput
    case unsupportedProvider(String)
    case missingRequiredKey(String)
    case invalidPlaceholder(String)
    case fileReadFailed(String)
    case invalidJson(String)
}

protocol SecretsProvider {
    func loadSecrets(for keys: [String]) throws -> [String: String]
    var name: String { get }
}

struct FileSecretsProvider: SecretsProvider {
    let sourcePath: String

    var name: String { "file" }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        let url = URL(fileURLWithPath: sourcePath)
        let data = try Data(contentsOf: url)
        if sourcePath.lowercased().hasSuffix(".json") {
            return try parseJson(data: data, keys: keys)
        }
        if let contents = String(data: data, encoding: .utf8) {
            return parseXcconfig(contents: contents, keys: keys)
        }
        throw SecretCompilerError.fileReadFailed(sourcePath)
    }

    private func parseJson(data: Data, keys: [String]) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw SecretCompilerError.invalidJson(sourcePath)
        }
        var secrets: [String: String] = [:]
        for key in keys {
            if let value = dict[key] as? String {
                secrets[key] = value
            }
        }
        return secrets
    }

    private func parseXcconfig(contents: String, keys: [String]) -> [String: String] {
        var secrets: [String: String] = [:]
        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if keys.contains(key) {
                secrets[key] = value
            }
        }
        return secrets
    }
}

struct EnvSecretsProvider: SecretsProvider {
    let environment: [String: String]

    var name: String { "env" }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        var secrets: [String: String] = [:]
        for key in keys {
            if let value = environment[key] {
                secrets[key] = value
            }
        }
        return secrets
    }
}

struct VaultSecretsProvider: SecretsProvider {
    var name: String { "vault" }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        throw SecretCompilerError.unsupportedProvider("vault")
    }
}
