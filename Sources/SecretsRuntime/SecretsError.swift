import Foundation

public enum SecretsError: Error {
    case sealedResourceNotFound
    case sealedResourceUnreadable
    case sealedResourceInvalid
    case secretMissing(String)
    case secretInvalid(String)
    case invalidObfuscationMaterial
    case randomGenerationFailed
    case unsupportedPlatform
    /// An `OBF3` entry is obfuscated but no `SecretsObfuscationKey` was provided to `SecretsManager`.
    case obfuscationKeyRequired
    /// The sealed resource declares a format this runtime does not understand.
    case unsupportedFormat(String)
}
