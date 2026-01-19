import Foundation

public final class SecretsManager {
    private let sealed: SealedSecrets

    public convenience init(bundle: Bundle = .main, resourceName: String = "Secrets", fileExtension: String = "sealed") throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: fileExtension) else {
            throw SecretsError.sealedResourceNotFound
        }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let sealed = try? decoder.decode(SealedSecrets.self, from: data) else {
            throw SecretsError.sealedResourceInvalid
        }
        self.sealed = sealed
    }

    public func value(for key: String, obfuscated: Bool = true) -> String {
        guard let rawValue = sealed.secrets[key] else {
            fatalError("Secret '\(key)' missing from sealed secrets")
        }

        if obfuscated && rawValue.hasPrefix("OBF2::") {
            let resolved = SecretObfuscator.deobfuscate(rawValue, material: sealed.obfuscation)
            if resolved.isEmpty {
                fatalError("Secret '\(key)' failed to deobfuscate")
            }
            return SecretProtection.protect(resolved)
        }

        if rawValue.isEmpty {
            fatalError("Secret '\(key)' is empty")
        }

        return SecretProtection.protect(rawValue)
    }

    public func validate(requiredKeys: [String]) {
        #if DEBUG
        for key in requiredKeys {
            let value = value(for: key)
            if value.isEmpty || value.contains("YOUR_") || value.contains("__") || value.contains("PLACEHOLDER") {
                assertionFailure("Invalid secret for \(key)")
            }
        }
        #endif
    }

    public func protectedValue(for key: String, obfuscated: Bool = true) -> ProtectedSecret {
        let secret = value(for: key, obfuscated: obfuscated)
        return ProtectedSecret(secret)
    }
}
