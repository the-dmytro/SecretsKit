import Dispatch
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
    case missingVaultConfig(String)
    case vaultRequestFailed(String)
    case vaultInvalidResponse(String)
    case vaultInsecureTransport(String)
    case invalidKeyMaterial(String)
    case legacyOBF2RequiresExplicitOptIn
    case autoProviderFailed([AutoProviderAttempt])
}

extension SecretCompilerError: CustomStringConvertible {
    var description: String {
        switch self {
        case .missingSchema:
            return "Missing secrets schema or required keys override"
        case .missingSource:
            return "Missing secrets source path"
        case .missingOutput:
            return "Missing output path"
        case .unsupportedProvider(let name):
            return "Unsupported provider: \(name)"
        case .missingRequiredKey(let key):
            return "Missing required key: \(key)"
        case .invalidPlaceholder(let key):
            return "Invalid placeholder value for: \(key)"
        case .fileReadFailed(let path):
            return "Failed to read file: \(path)"
        case .invalidJson(let path):
            return "Invalid JSON: \(path)"
        case .missingVaultConfig(let name):
            return "Missing Vault configuration: \(name)"
        case .vaultRequestFailed(let message):
            return "Vault request failed: \(message)"
        case .vaultInvalidResponse(let message):
            return "Invalid Vault response: \(message)"
        case .vaultInsecureTransport(let address):
            return "Insecure Vault transport: \(address)"
        case .invalidKeyMaterial(let detail):
            return "Invalid obfuscation key material: \(detail)"
        case .legacyOBF2RequiresExplicitOptIn:
            return "Legacy OBF2 sealing requires explicit opt-in"
        case .autoProviderFailed:
            return "Auto provider failed"
        }
    }
}

protocol SecretsProvider {
    func loadSecrets(for keys: [String]) throws -> [String: String]
    var name: String { get }
}

struct AutoProviderAttempt {
    let provider: String
    let reason: String
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
            let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
            // Strip any `[sdk=...]`-style conditional suffix and warn — we do not evaluate conditionals.
            let key: String
            if let bracket = rawKey.firstIndex(of: "[") {
                key = String(rawKey[..<bracket]).trimmingCharacters(in: .whitespaces)
                FileHandle.standardError.write(Data("warning: xcconfig conditional on '\(rawKey)' is not evaluated; using the value verbatim.\n".utf8))
            } else {
                key = rawKey
            }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if keys.contains(key) {
                if value.contains("$(") {
                    FileHandle.standardError.write(Data("warning: xcconfig value for '\(key)' contains variable interpolation ($(...)) which is not expanded; sealing the literal text.\n".utf8))
                }
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

final class AutoSecretsProvider: SecretsProvider {
    let order: [String]
    let allowMerge: Bool
    let requiredKeys: [String]
    let providerFactory: (String) throws -> SecretsProvider
    private var selectedProvider: SecretsProvider?

    var name: String { "auto" }

    init(order: [String], allowMerge: Bool, requiredKeys: [String], providerFactory: @escaping (String) throws -> SecretsProvider) {
        self.order = order
        self.allowMerge = allowMerge
        self.requiredKeys = requiredKeys
        self.providerFactory = providerFactory
    }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        if allowMerge {
            return try loadMerged(keys: keys)
        }
        if selectedProvider == nil {
            selectedProvider = try selectProvider()
        }
        guard let provider = selectedProvider else {
            throw SecretCompilerError.autoProviderFailed([])
        }
        return try provider.loadSecrets(for: keys)
    }

    private func selectProvider() throws -> SecretsProvider {
        var attempts: [AutoProviderAttempt] = []
        for providerName in order {
            do {
                let provider = try providerFactory(providerName)
                let secrets = try provider.loadSecrets(for: requiredKeys)
                let missing = requiredKeys.filter { secrets[$0]?.isEmpty != false }
                if missing.isEmpty {
                    return provider
                }
                attempts.append(AutoProviderAttempt(provider: provider.name, reason: "Missing required keys: \(missing.joined(separator: ", "))"))
            } catch {
                attempts.append(AutoProviderAttempt(provider: providerName, reason: "\(error)"))
            }
        }
        throw SecretCompilerError.autoProviderFailed(attempts)
    }

    private func loadMerged(keys: [String]) throws -> [String: String] {
        var attempts: [AutoProviderAttempt] = []
        var remaining = Set(keys)
        var secrets: [String: String] = [:]

        for providerName in order {
            do {
                let provider = try providerFactory(providerName)
                let values = try provider.loadSecrets(for: Array(remaining))
                for (key, value) in values where remaining.contains(key) {
                    secrets[key] = value
                    remaining.remove(key)
                }
                if remaining.isEmpty {
                    break
                }
            } catch {
                attempts.append(AutoProviderAttempt(provider: providerName, reason: "\(error)"))
            }
        }

        if !remaining.isEmpty {
            attempts.append(AutoProviderAttempt(provider: "auto", reason: "Missing required keys: \(remaining.sorted().joined(separator: ", "))"))
            throw SecretCompilerError.autoProviderFailed(attempts)
        }

        return secrets
    }
}

/// Validates the Vault address transport. Requires `https` unless `allowInsecureHTTP` is set, in which
/// case `http` is permitted (local development only). Any other scheme — or a missing scheme — is rejected.
func validateVaultTransport(address: String, allowInsecureHTTP: Bool) throws {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() else {
        throw SecretCompilerError.vaultRequestFailed("Invalid Vault address (no URL scheme): \(address)")
    }
    switch scheme {
    case "https":
        return
    case "http":
        guard allowInsecureHTTP else {
            throw SecretCompilerError.vaultInsecureTransport(address)
        }
    default:
        throw SecretCompilerError.vaultRequestFailed("Unsupported Vault scheme '\(scheme)'; use https.")
    }
}

func buildVaultRequestPath(mount: String, path: String, kvVersion: Int) throws -> String {
    let mountSegments = try vaultPathSegments(mount, field: "mount", allowEmpty: true)
    let pathSegments = try vaultPathSegments(path, field: "path", allowEmpty: false)

    let requestSegments: [String]
    if mountSegments.isEmpty {
        requestSegments = pathSegments
    } else if pathSegments.starts(with: mountSegments) {
        requestSegments = pathSegments
    } else if kvVersion == 2 {
        requestSegments = mountSegments + ["data"] + pathSegments
    } else {
        requestSegments = mountSegments + pathSegments
    }

    return try requestSegments.map(percentEncodedVaultPathSegment).joined(separator: "/")
}

func buildVaultURL(address: String, requestPath: String) throws -> URL {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed),
          components.scheme != nil,
          components.host != nil else {
        throw SecretCompilerError.vaultRequestFailed("Invalid Vault address: \(address)")
    }
    guard components.query == nil, components.fragment == nil else {
        throw SecretCompilerError.vaultRequestFailed("Vault address must not contain query or fragment")
    }

    let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let apiPath = basePath.isEmpty ? "v1/\(requestPath)" : "\(basePath)/v1/\(requestPath)"
    components.percentEncodedPath = "/" + apiPath

    guard let url = components.url else {
        throw SecretCompilerError.vaultRequestFailed("Invalid Vault URL")
    }
    return url
}

private func vaultPathSegments(_ raw: String, field: String, allowEmpty: Bool) throws -> [String] {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if trimmed.isEmpty {
        if allowEmpty {
            return []
        }
        throw SecretCompilerError.vaultRequestFailed("Vault \(field) must not be empty")
    }

    let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.contains(where: \.isEmpty) else {
        throw SecretCompilerError.vaultRequestFailed("Vault \(field) must not contain empty path segments")
    }

    for part in parts {
        if part == "." || part == ".." {
            throw SecretCompilerError.vaultRequestFailed("Vault \(field) must not contain relative path segments")
        }
        if part.contains("?") || part.contains("#") {
            throw SecretCompilerError.vaultRequestFailed("Vault \(field) must not contain query or fragment delimiters")
        }
        if part.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            throw SecretCompilerError.vaultRequestFailed("Vault \(field) must not contain control characters")
        }
    }

    return parts
}

private func percentEncodedVaultPathSegment(_ segment: String) throws -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
        throw SecretCompilerError.vaultRequestFailed("Invalid Vault path segment")
    }
    return encoded
}

struct VaultSecretsProvider: SecretsProvider {
    let address: String
    let token: String
    let namespace: String?
    let requestPath: String
    let kvVersion: Int
    let timeoutSeconds: Double

    var name: String { "vault" }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        let url = try buildVaultURL(address: address, requestPath: requestPath)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue(token, forHTTPHeaderField: "X-Vault-Token")
        if let namespace, !namespace.isEmpty {
            request.setValue(namespace, forHTTPHeaderField: "X-Vault-Namespace")
        }

        let data = try fetchData(request: request)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw SecretCompilerError.vaultInvalidResponse("Unexpected response format")
        }

        let payload: [String: Any]
        if kvVersion == 2 {
            guard let dataLevel = dict["data"] as? [String: Any],
                  let inner = dataLevel["data"] as? [String: Any] else {
                throw SecretCompilerError.vaultInvalidResponse("Missing data.data in response")
            }
            payload = inner
        } else {
            guard let inner = dict["data"] as? [String: Any] else {
                throw SecretCompilerError.vaultInvalidResponse("Missing data in response")
            }
            payload = inner
        }

        var secrets: [String: String] = [:]
        for key in keys {
            if let value = payload[key] as? String {
                secrets[key] = value
            } else if payload[key] != nil {
                throw SecretCompilerError.vaultInvalidResponse("Value for key '\(key)' is not a string")
            }
        }

        return secrets
    }

    private func fetchData(request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?
        var resultResponse: URLResponse?

        URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let error = resultError {
            throw SecretCompilerError.vaultRequestFailed("Request failed: \(error.localizedDescription)")
        }

        guard let http = resultResponse as? HTTPURLResponse else {
            throw SecretCompilerError.vaultRequestFailed("No HTTP response from Vault")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SecretCompilerError.vaultRequestFailed("Vault returned HTTP \(http.statusCode)")
        }

        guard let data = resultData else {
            throw SecretCompilerError.vaultRequestFailed("Empty response from Vault")
        }

        return data
    }
}
