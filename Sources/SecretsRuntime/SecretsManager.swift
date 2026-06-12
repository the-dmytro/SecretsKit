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
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SecretsError.sealedResourceUnreadable
        }
        guard let sealed = try? JSONDecoder().decode(SealedSecrets.self, from: data) else {
            throw SecretsError.sealedResourceInvalid
        }
        self.sealed = sealed
    }

    /// Returns the secret for `key`.
    ///
    /// - Throws: `SecretsError.secretMissing` if the key is absent, or
    ///   `SecretsError.secretInvalid` if the stored value is empty or cannot be deobfuscated.
    public func requiredValue(for key: String, obfuscated: Bool = true) throws -> String {
        guard let rawValue = sealed.secrets[key] else {
            throw SecretsError.secretMissing(key)
        }

        if obfuscated && rawValue.hasPrefix("OBF2::") {
            let resolved = SecretObfuscator.deobfuscate(rawValue, material: sealed.obfuscation)
            guard !resolved.isEmpty else {
                throw SecretsError.secretInvalid(key)
            }
            return resolved
        }

        guard !rawValue.isEmpty else {
            throw SecretsError.secretInvalid(key)
        }
        return rawValue
    }

    /// Returns the secret for `key`, or `nil` if it is missing, empty, or cannot be deobfuscated.
    public func optionalValue(for key: String, obfuscated: Bool = true) -> String? {
        return try? requiredValue(for: key, obfuscated: obfuscated)
    }

    /// Returns the secret for `key` wrapped in a `ProtectedSecret` whose bytes are zeroed when released.
    ///
    /// - Throws: the same errors as `requiredValue(for:obfuscated:)`.
    public func requiredProtectedValue(for key: String, obfuscated: Bool = true) throws -> ProtectedSecret {
        return ProtectedSecret(try requiredValue(for: key, obfuscated: obfuscated))
    }

    /// Validates that each required key resolves to a non-empty secret.
    ///
    /// Placeholder / format checks are the build-time CLI's responsibility (`secretcompiler validate`);
    /// this runtime check only confirms the values are present and decodable, in every build config.
    ///
    /// - Throws: the first `SecretsError` encountered.
    public func validateRequiredKeys(_ keys: [String]) throws {
        for key in keys {
            _ = try requiredValue(for: key)
        }
    }

    // MARK: - Deprecated

    @available(*, deprecated, message: "Crashes on a missing/invalid secret. Use requiredValue(for:) (throws) or optionalValue(for:) (returns nil). Will be removed.")
    public func value(for key: String, obfuscated: Bool = true) -> String {
        do {
            return try requiredValue(for: key, obfuscated: obfuscated)
        } catch {
            fatalError("Secret '\(key)' could not be resolved: \(error)")
        }
    }

    @available(*, deprecated, message: "Crashes on a missing/invalid secret. Use requiredProtectedValue(for:) (throws). Will be removed.")
    public func protectedValue(for key: String, obfuscated: Bool = true) -> ProtectedSecret {
        do {
            return ProtectedSecret(try requiredValue(for: key, obfuscated: obfuscated))
        } catch {
            fatalError("Secret '\(key)' could not be resolved: \(error)")
        }
    }

    @available(*, deprecated, message: "DEBUG-only and over-matches placeholders. Use validateRequiredKeys(_:) which throws in every build. Will be removed.")
    public func validate(requiredKeys: [String]) {
        #if DEBUG
        do {
            try validateRequiredKeys(requiredKeys)
        } catch {
            assertionFailure("Secrets validation failed: \(error)")
        }
        #endif
    }
}
