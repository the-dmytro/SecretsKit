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
}
