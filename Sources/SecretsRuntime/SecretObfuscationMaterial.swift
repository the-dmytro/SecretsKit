import CryptoKit
import Foundation
import Security

public struct SecretObfuscationMaterial: Codable {
    public let hkdfSaltHex: String
    public let hkdfSeedHex: String
    public let nonceBase64: String
    public let xorMask: UInt8

    public init(hkdfSaltHex: String, hkdfSeedHex: String, nonceBase64: String, xorMask: UInt8) {
        self.hkdfSaltHex = hkdfSaltHex
        self.hkdfSeedHex = hkdfSeedHex
        self.nonceBase64 = nonceBase64
        self.xorMask = xorMask
    }

    public static func generate() throws -> SecretObfuscationMaterial {
        let salt = try randomBytesHex(count: 32)
        let seed = try randomBytesHex(count: 32)
        let nonce = try randomBytesBase64(count: 12)
        let mask = try randomByte()
        return SecretObfuscationMaterial(hkdfSaltHex: salt, hkdfSeedHex: seed, nonceBase64: nonce, xorMask: mask)
    }

    public func hkdfKey() throws -> SymmetricKey {
        guard let salt = Data(hexString: hkdfSaltHex),
              let seed = Data(hexString: hkdfSeedHex) else {
            throw SecretsError.invalidObfuscationMaterial
        }

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: seed),
            salt: salt,
            info: Data("secretskit-obfuscation".utf8),
            outputByteCount: 32
        )
    }

    public func nonce() throws -> ChaChaPoly.Nonce {
        guard let data = Data(base64Encoded: nonceBase64) else {
            throw SecretsError.invalidObfuscationMaterial
        }
        return try ChaChaPoly.Nonce(data: data)
    }

    private static func randomBytesHex(count: Int) throws -> String {
        let bytes = try randomBytes(count: count)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomBytesBase64(count: Int) throws -> String {
        let bytes = try randomBytes(count: count)
        return Data(bytes).base64EncodedString()
    }

    private static func randomByte() throws -> UInt8 {
        var value: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &value)
        guard status == errSecSuccess else {
            throw SecretsError.randomGenerationFailed
        }
        return value
    }

    private static func randomBytes(count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        guard status == errSecSuccess else {
            throw SecretsError.randomGenerationFailed
        }
        return buffer
    }
}

extension Data {
    public init?(hexString: String) {
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard nextIndex <= clean.endIndex else { return nil }
            let byteString = clean[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
