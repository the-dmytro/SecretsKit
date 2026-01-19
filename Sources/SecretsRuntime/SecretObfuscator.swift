import CryptoKit
import Foundation
import Security

public enum SecretObfuscator {
    public static func obfuscate(_ value: String, material: SecretObfuscationMaterial) throws -> String {
        guard !value.isEmpty else { return "" }
        let nonce = try material.nonce()
        let key = try material.hkdfKey()
        let sealed = try ChaChaPoly.seal(Data(value.utf8), using: key, nonce: nonce)

        let reversedCipher = sealed.ciphertext.reversed().map { $0 ^ material.xorMask }
        var payload = Data(reversedCipher + sealed.tag)
        payload.append(contentsOf: randomPadding(count: 4))

        return "OBF2::" + payload.base64EncodedString()
    }

    @inline(__always)
    public static func deobfuscate(_ obfuscated: String, material: SecretObfuscationMaterial) -> String {
        guard obfuscated.hasPrefix("OBF2::"),
              let data = Data(base64Encoded: obfuscated.replacingOccurrences(of: "OBF2::", with: "")),
              data.count > 20 else {
            return ""
        }

        let trimmed = data.dropLast(4)
        let tagRangeStart = trimmed.count - 16
        let cipherSlice = trimmed.prefix(tagRangeStart)
        let tagSlice = trimmed.suffix(16)

        let restoredCipher = cipherSlice.map { $0 ^ material.xorMask }.reversed()
        do {
            let nonce = try material.nonce()
            let key = try material.hkdfKey()
            let sealedBox = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: Data(restoredCipher),
                tag: Data(tagSlice)
            )
            let opened = try ChaChaPoly.open(sealedBox, using: key)
            return String(decoding: opened, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func randomPadding(count: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        return buffer
    }
}
