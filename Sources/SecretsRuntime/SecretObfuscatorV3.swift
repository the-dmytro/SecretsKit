import CryptoKit
import Foundation
import Security

/// The `OBF3` obfuscation transform.
///
/// Each value is sealed with ChaChaPoly under a per-key subkey derived from the externally-supplied
/// `SecretsObfuscationKey` via HKDF with key-name domain separation, and a fresh per-entry nonce.
/// This fixes the two fatal `OBF2` problems: the key no longer ships beside the ciphertext, and no
/// nonce/key pair is reused across entries. The naming stays "obfuscation" deliberately — the key is
/// recoverable from the app binary, so this is not a secrecy boundary.
public enum SecretObfuscatorV3 {
    private static let infoPrefix = "secretskit-obfuscation:"

    /// Derives the per-key subkey. `keyName` provides domain separation so each secret uses a
    /// distinct subkey even though they share one root `SecretsObfuscationKey`.
    public static func subkey(for keyName: String, using key: SecretsObfuscationKey) -> SymmetricKey {
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(key.seed)),
            salt: Data(key.salt),
            info: Data((infoPrefix + keyName).utf8),
            outputByteCount: 32
        )
    }

    public static func seal(_ value: String, keyName: String, using key: SecretsObfuscationKey) throws -> SealedEntry {
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        guard SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes) == errSecSuccess else {
            throw SecretsError.randomGenerationFailed
        }
        let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))
        let box = try ChaChaPoly.seal(Data(value.utf8), using: subkey(for: keyName, using: key), nonce: nonce)
        return SealedEntry(
            obfuscated: true,
            value: nil,
            ciphertext: box.ciphertext.base64EncodedString(),
            nonce: Data(nonceBytes).base64EncodedString(),
            tag: box.tag.base64EncodedString()
        )
    }

    public static func open(_ entry: SealedEntry, keyName: String, using key: SecretsObfuscationKey) throws -> String {
        guard let ciphertextB64 = entry.ciphertext,
              let nonceB64 = entry.nonce,
              let tagB64 = entry.tag,
              let ciphertext = Data(base64Encoded: ciphertextB64),
              let nonceData = Data(base64Encoded: nonceB64),
              let tag = Data(base64Encoded: tagB64) else {
            throw SecretsError.secretInvalid(keyName)
        }

        do {
            let nonce = try ChaChaPoly.Nonce(data: nonceData)
            let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let opened = try ChaChaPoly.open(box, using: subkey(for: keyName, using: key))
            return String(decoding: opened, as: UTF8.self)
        } catch {
            throw SecretsError.secretInvalid(keyName)
        }
    }
}
