#if os(macOS)
import Foundation
import XCTest
@testable import SecretCompiler
import SecretsRuntime

final class SealFormatTests: XCTestCase {
    func testSealWithoutKeyMaterialRequiresExplicitLegacyOptIn() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let args = sealArgs(schema: fixture.schema, source: fixture.source, output: fixture.output)

        XCTAssertThrowsError(try runSeal(args: args, env: [:])) { error in
            guard case SecretCompilerError.legacyOBF2RequiresExplicitOptIn = error else {
                return XCTFail("expected legacyOBF2RequiresExplicitOptIn, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    func testExplicitLegacyOptInStillWritesOBF2ForMigration() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let args = sealArgs(
            schema: fixture.schema,
            source: fixture.source,
            output: fixture.output,
            extraOptions: ["legacy-obf2": "true"]
        )

        XCTAssertEqual(try runSeal(args: args, env: [:]), 0)

        let data = try Data(contentsOf: fixture.output)
        let sealed = try JSONDecoder().decode(SealedSecrets.self, from: data)
        XCTAssertEqual(sealed.format, "OBF2")
    }

    func testSealWithKeyMaterialWritesOBF3WithOwnerOnlyPermissions() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let materialURL = fixture.directory.appendingPathComponent("AppObfKey.material")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(try ObfuscationKeyMaterial.generate()).write(to: materialURL)

        let args = sealArgs(
            schema: fixture.schema,
            source: fixture.source,
            output: fixture.output,
            extraOptions: ["key-material": materialURL.path]
        )

        XCTAssertEqual(try runSeal(args: args, env: [:]), 0)

        let sealed = try JSONDecoder().decode(SealedSecretsV2.self, from: try Data(contentsOf: fixture.output))
        XCTAssertEqual(sealed.format, "OBF3")
        XCTAssertEqual(sealed.entries["API_KEY"]?.obfuscated, true)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.output.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testWriteSealedDataCreatesFileWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("Secrets.sealed")

        try writeSealedData(Data("{}".utf8), to: output.path)

        XCTAssertEqual(try Data(contentsOf: output), Data("{}".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    private func makeFixture() throws -> (directory: URL, schema: URL, source: URL, output: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let schema = directory.appendingPathComponent("Secrets.schema.json")
        let source = directory.appendingPathComponent("Secrets.json")
        let output = directory.appendingPathComponent("Secrets.sealed")

        try Data("""
        {
          "version": 1,
          "keys": {
            "API_KEY": { "required": true, "obfuscate": true }
          }
        }
        """.utf8).write(to: schema)

        try Data("""
        { "API_KEY": "secret-value" }
        """.utf8).write(to: source)

        return (directory, schema, source, output)
    }

    private func sealArgs(schema: URL, source: URL, output: URL, extraOptions: [String: String] = [:]) -> CLIArguments {
        var options = [
            "schema": schema.path,
            "source": source.path,
            "provider": "file",
            "output": output.path
        ]
        for (key, value) in extraOptions {
            options[key] = value
        }
        return CLIArguments(command: "seal", options: options)
    }
}
#endif
