import XCTest
@testable import SecretsRuntime

final class OBF3Tests: XCTestCase {
    private func makeKey() -> SecretsObfuscationKey {
        SecretsObfuscationKey(
            seed: (0..<32).map { UInt8($0) },
            salt: (32..<64).map { UInt8($0) }
        )
    }

    func testSealOpenRoundTrip() throws {
        let key = makeKey()
        let entry = try SecretObfuscatorV3.seal("hello-world", keyName: "API", using: key)
        XCTAssertTrue(entry.obfuscated)
        XCTAssertNil(entry.value)
        XCTAssertEqual(try SecretObfuscatorV3.open(entry, keyName: "API", using: key), "hello-world")
    }

    func testKeyMaterialNotPresentInSealedFile() throws {
        let key = makeKey()
        let sealed = SealedSecretsV2(entries: ["API": try SecretObfuscatorV3.seal("token", keyName: "API", using: key)])
        let json = String(decoding: try JSONEncoder().encode(sealed), as: UTF8.self)
        // The OBF3 container must carry no seed/salt/key material.
        XCTAssertFalse(json.contains("seed"))
        XCTAssertFalse(json.contains("salt"))
        XCTAssertFalse(json.contains("hkdf"))
    }

    func testPerEntryNonceIsUnique() throws {
        let key = makeKey()
        let a = try SecretObfuscatorV3.seal("same", keyName: "A", using: key)
        let b = try SecretObfuscatorV3.seal("same", keyName: "B", using: key)
        XCTAssertNotNil(a.nonce)
        XCTAssertNotEqual(a.nonce, b.nonce, "different keys must not reuse a nonce")
        // Re-sealing the same key/value must also produce a fresh nonce.
        let a2 = try SecretObfuscatorV3.seal("same", keyName: "A", using: key)
        XCTAssertNotEqual(a.nonce, a2.nonce, "each seal must use a fresh nonce")
    }

    func testDomainSeparationRejectsWrongKeyName() throws {
        let key = makeKey()
        let entry = try SecretObfuscatorV3.seal("secret", keyName: "RIGHT", using: key)
        XCTAssertThrowsError(try SecretObfuscatorV3.open(entry, keyName: "WRONG", using: key)) { error in
            guard case SecretsError.secretInvalid = error else {
                return XCTFail("expected secretInvalid, got \(error)")
            }
        }
    }

    func testManagerReadsOBF3WithKeyAndRejectsWithout() throws {
        let key = makeKey()
        let sealed = SealedSecretsV2(entries: [
            "API": try SecretObfuscatorV3.seal("token", keyName: "API", using: key),
            "PUB": .plain("public-value")
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sealed")
        try JSONEncoder().encode(sealed).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let withKey = try SecretsManager(url: url, obfuscationKey: key)
        XCTAssertEqual(try withKey.requiredValue(for: "API"), "token")
        XCTAssertEqual(try withKey.requiredValue(for: "PUB"), "public-value")

        let withoutKey = try SecretsManager(url: url)
        XCTAssertThrowsError(try withoutKey.requiredValue(for: "API")) { error in
            guard case SecretsError.obfuscationKeyRequired = error else {
                return XCTFail("expected obfuscationKeyRequired, got \(error)")
            }
        }
        // Non-obfuscated entries do not need a key.
        XCTAssertEqual(try withoutKey.requiredValue(for: "PUB"), "public-value")
    }

    func testManagerStillReadsLegacyOBF2() throws {
        let material = try SecretObfuscationMaterial.generate()
        let obf = try SecretObfuscator.obfuscate("legacy-secret", material: material)
        let legacy = SealedSecrets(version: 1, format: "OBF2", obfuscation: material, secrets: ["OLD": obf])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sealed")
        try JSONEncoder().encode(legacy).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertEqual(try manager.requiredValue(for: "OLD"), "legacy-secret")
    }
}
