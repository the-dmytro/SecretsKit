#if os(macOS)
import XCTest
@testable import SecretCompiler
import SecretsRuntime

final class ObfuscationKeyMaterialTests: XCTestCase {
    func testGenerateProducesUsable32ByteKey() throws {
        let material = try ObfuscationKeyMaterial.generate()
        let key = try material.obfuscationKey()
        XCTAssertEqual(key.seed.count, 32)
        XCTAssertEqual(key.salt.count, 32)
    }

    func testGenerateIsRandomEachTime() throws {
        let a = try ObfuscationKeyMaterial.generate()
        let b = try ObfuscationKeyMaterial.generate()
        XCTAssertNotEqual(a.seedHex, b.seedHex)
        XCTAssertNotEqual(a.saltHex, b.saltHex)
    }

    func testSwiftSourceContainsSymbolAndArrays() throws {
        let src = try ObfuscationKeyMaterial.generate().swiftSource(symbol: "MyKey")
        XCTAssertTrue(src.contains("enum MyKey"))
        XCTAssertTrue(src.contains("static let seed: [UInt8]"))
        XCTAssertTrue(src.contains("static let salt: [UInt8]"))
        XCTAssertTrue(src.contains("SecretsObfuscationKey"))
    }

    func testInvalidMaterialThrows() {
        XCTAssertThrowsError(try ObfuscationKeyMaterial(seedHex: "zz", saltHex: "").obfuscationKey()) { error in
            guard case SecretCompilerError.invalidKeyMaterial = error else {
                return XCTFail("expected invalidKeyMaterial, got \(error)")
            }
        }
    }

    func testMaterialRoundTripsThroughRuntimeObfuscator() throws {
        // generate-key material -> key -> seal -> open, as seal+runtime would do across the build boundary.
        let key = try ObfuscationKeyMaterial.generate().obfuscationKey()
        let entry = try SecretObfuscatorV3.seal("xyz-123", keyName: "K", using: key)
        XCTAssertEqual(try SecretObfuscatorV3.open(entry, keyName: "K", using: key), "xyz-123")
    }

    func testLoadFromFile() throws {
        let material = try ObfuscationKeyMaterial.generate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".material")
        try JSONEncoder().encode(material).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ObfuscationKeyMaterial.load(from: url.path)
        XCTAssertEqual(loaded.seedHex, material.seedHex)
        XCTAssertEqual(loaded.saltHex, material.saltHex)
    }
}
#endif
