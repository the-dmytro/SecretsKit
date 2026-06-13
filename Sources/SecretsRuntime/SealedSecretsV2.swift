import Foundation

/// A single sealed entry in the `OBF3` format.
///
/// Obfuscated entries carry their own per-entry `nonce` (so no nonce is ever reused across keys) and
/// `tag`; the key material lives in the binary, not here. Non-obfuscated entries (schema
/// `obfuscate: false`) carry a plain `value`.
public struct SealedEntry: Codable {
    public let obfuscated: Bool
    public let value: String?
    public let ciphertext: String?
    public let nonce: String?
    public let tag: String?

    public init(obfuscated: Bool, value: String? = nil, ciphertext: String? = nil, nonce: String? = nil, tag: String? = nil) {
        self.obfuscated = obfuscated
        self.value = value
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
    }

    public static func plain(_ value: String) -> SealedEntry {
        SealedEntry(obfuscated: false, value: value)
    }
}

/// The `OBF3` sealed-secrets container. Unlike the legacy `OBF2` `SealedSecrets`, it stores **no key
/// material** — only ciphertext, per-entry nonces, and tags.
public struct SealedSecretsV2: Codable {
    public let version: Int
    public let format: String
    public let entries: [String: SealedEntry]

    public init(version: Int = 2, format: String = "OBF3", entries: [String: SealedEntry]) {
        self.version = version
        self.format = format
        self.entries = entries
    }
}
