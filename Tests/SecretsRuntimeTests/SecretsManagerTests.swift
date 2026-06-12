import XCTest
@testable import SecretsRuntime

final class SecretsManagerTests: XCTestCase {
    private func writeSealed(secrets: [String: String], material: SecretObfuscationMaterial) throws -> URL {
        let sealed = SealedSecrets(version: 1, format: "OBF2", obfuscation: material, secrets: secrets)
        let data = try JSONEncoder().encode(sealed)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sealed")
        try data.write(to: url)
        return url
    }

    func testRequiredValueReturnsPlainValue() throws {
        let material = try SecretObfuscationMaterial.generate()
        let url = try writeSealed(secrets: ["A": "hello"], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertEqual(try manager.requiredValue(for: "A", obfuscated: false), "hello")
    }

    func testObfuscatedRoundTrip() throws {
        let material = try SecretObfuscationMaterial.generate()
        let obfuscated = try SecretObfuscator.obfuscate("s3cr3t-value", material: material)
        let url = try writeSealed(secrets: ["A": obfuscated], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertEqual(try manager.requiredValue(for: "A"), "s3cr3t-value")
    }

    func testMissingKeyThrowsInsteadOfCrashing() throws {
        let material = try SecretObfuscationMaterial.generate()
        let url = try writeSealed(secrets: ["A": "x"], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertThrowsError(try manager.requiredValue(for: "MISSING")) { error in
            guard case SecretsError.secretMissing(let key) = error else {
                return XCTFail("expected secretMissing, got \(error)")
            }
            XCTAssertEqual(key, "MISSING")
        }
    }

    func testEmptyValueThrows() throws {
        let material = try SecretObfuscationMaterial.generate()
        let url = try writeSealed(secrets: ["A": ""], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertThrowsError(try manager.requiredValue(for: "A", obfuscated: false)) { error in
            guard case SecretsError.secretInvalid = error else {
                return XCTFail("expected secretInvalid, got \(error)")
            }
        }
    }

    func testOptionalValueReturnsNilForMissingAndValueForPresent() throws {
        let material = try SecretObfuscationMaterial.generate()
        let url = try writeSealed(secrets: ["A": "x"], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertNil(manager.optionalValue(for: "MISSING"))
        XCTAssertEqual(manager.optionalValue(for: "A", obfuscated: false), "x")
    }

    func testInvalidSealedFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sealed")
        try Data("not valid json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SecretsManager(url: url)) { error in
            guard case SecretsError.sealedResourceInvalid = error else {
                return XCTFail("expected sealedResourceInvalid, got \(error)")
            }
        }
    }

    func testValidateRequiredKeysThrowsForMissing() throws {
        let material = try SecretObfuscationMaterial.generate()
        let url = try writeSealed(secrets: ["A": "x"], material: material)
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = try SecretsManager(url: url)
        XCTAssertThrowsError(try manager.validateRequiredKeys(["A", "B"]))
    }
}

final class ProtectedSecretTests: XCTestCase {
    func testGetReturnsValueAndBytes() {
        let secret = ProtectedSecret("token-123")
        XCTAssertEqual(secret.get(), "token-123")
        XCTAssertEqual(secret.withBytes { Array($0) }, Array("token-123".utf8))
    }
}
