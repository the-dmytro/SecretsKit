import Foundation

/// The obfuscation key material used to seal and open `OBF3` entries.
///
/// In `OBF3` this material is **not** stored in `Secrets.sealed`. It is generated once with
/// `secretcompiler generate-key`, compiled into the app binary, and handed to `SecretsManager` at
/// runtime. This separates the key from the ciphertext: recovering secrets now requires
/// disassembling the binary to reconstruct the key, rather than reading one bundled JSON file.
///
/// It is still **obfuscation, not encryption** — a determined reverse engineer can recover the key
/// from the binary. Only bundle values that are safe to be client-visible.
public struct SecretsObfuscationKey {
    public let seed: [UInt8]
    public let salt: [UInt8]

    public init(seed: [UInt8], salt: [UInt8]) {
        self.seed = seed
        self.salt = salt
    }
}
