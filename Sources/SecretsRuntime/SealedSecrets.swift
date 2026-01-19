import Foundation

public struct SealedSecrets: Codable {
    public let version: Int
    public let format: String
    public let obfuscation: SecretObfuscationMaterial
    public let secrets: [String: String]

    public init(version: Int, format: String, obfuscation: SecretObfuscationMaterial, secrets: [String: String]) {
        self.version = version
        self.format = format
        self.obfuscation = obfuscation
        self.secrets = secrets
    }
}
