import Foundation

public final class SecretsManager {
    private enum Storage {
        /// `OBF3`: keyless ciphertext; the obfuscation key is supplied externally.
        case v3(SealedSecretsV2)
        /// Legacy `OBF2`: the obfuscation material is embedded in the file. Read-only, for migration.
        case legacy(SealedSecrets)
    }

    private let storage: Storage
    private let obfuscationKey: SecretsObfuscationKey?

    public convenience init(
        bundle: Bundle = .main,
        resourceName: String = "Secrets",
        fileExtension: String = "sealed",
        obfuscationKey: SecretsObfuscationKey? = nil
    ) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: fileExtension) else {
            throw SecretsError.sealedResourceNotFound
        }
        try self.init(url: url, obfuscationKey: obfuscationKey)
    }

    /// - Parameter obfuscationKey: required to read obfuscated `OBF3` entries (generate it with
    ///   `secretcompiler generate-key` and compile it into the app). Not needed for legacy `OBF2`
    ///   files or for non-obfuscated entries.
    public init(url: URL, obfuscationKey: SecretsObfuscationKey? = nil) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SecretsError.sealedResourceUnreadable
        }

        self.obfuscationKey = obfuscationKey

        let decoder = JSONDecoder()
        if let v2 = try? decoder.decode(SealedSecretsV2.self, from: data), v2.format == "OBF3" {
            self.storage = .v3(v2)
        } else if let legacy = try? decoder.decode(SealedSecrets.self, from: data) {
            self.storage = .legacy(legacy)
        } else {
            throw SecretsError.sealedResourceInvalid
        }
    }

    /// Returns the secret for `key`.
    ///
    /// - Parameter obfuscated: only consulted for legacy `OBF2` files; in `OBF3` the entry records
    ///   whether it was obfuscated.
    /// - Throws: `SecretsError.secretMissing` if absent, `.secretInvalid` if empty or undecodable,
    ///   or `.obfuscationKeyRequired` if an `OBF3` entry is obfuscated but no key was provided.
    public func requiredValue(for key: String, obfuscated: Bool = true) throws -> String {
        switch storage {
        case .v3(let sealed):
            guard let entry = sealed.entries[key] else {
                throw SecretsError.secretMissing(key)
            }
            if entry.obfuscated {
                guard let obfuscationKey else {
                    throw SecretsError.obfuscationKeyRequired
                }
                let resolved = try SecretObfuscatorV3.open(entry, keyName: key, using: obfuscationKey)
                guard !resolved.isEmpty else {
                    throw SecretsError.secretInvalid(key)
                }
                return resolved
            }
            guard let value = entry.value, !value.isEmpty else {
                throw SecretsError.secretInvalid(key)
            }
            return value

        case .legacy(let sealed):
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
    }

    /// Returns the secret for `key`, or `nil` if it is missing, empty, undecodable, or needs a key
    /// that was not provided.
    public func optionalValue(for key: String, obfuscated: Bool = true) -> String? {
        return try? requiredValue(for: key, obfuscated: obfuscated)
    }

    /// Returns the secret for `key` wrapped in a `ProtectedSecret` whose bytes are zeroed when released.
    public func requiredProtectedValue(for key: String, obfuscated: Bool = true) throws -> ProtectedSecret {
        return ProtectedSecret(try requiredValue(for: key, obfuscated: obfuscated))
    }

    /// Validates that each required key resolves to a non-empty secret, in every build config.
    ///
    /// Placeholder / format checks are the build-time CLI's responsibility (`secretcompiler validate`).
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
