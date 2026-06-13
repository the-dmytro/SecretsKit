#if os(macOS)
import Foundation
import XCTest
@testable import SecretCompiler
import SecretsRuntime

final class ClassificationTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let schema: URL
        let source: URL
        let output: URL
        let material: URL
    }

    private func makeFixture(schemaJSON: String, sourceJSON: String) throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schema = dir.appendingPathComponent("Secrets.schema.json")
        let source = dir.appendingPathComponent("Secrets.json")
        let output = dir.appendingPathComponent("Secrets.sealed")
        let material = dir.appendingPathComponent("ObfKey.material")
        try Data(schemaJSON.utf8).write(to: schema)
        try Data(sourceJSON.utf8).write(to: source)
        try JSONEncoder().encode(try ObfuscationKeyMaterial.generate()).write(to: material)
        return Fixture(directory: dir, schema: schema, source: source, output: output, material: material)
    }

    private func sealArgs(_ fixture: Fixture, extra: [String: String] = [:]) -> CLIArguments {
        var options = [
            "schema": fixture.schema.path,
            "source": fixture.source.path,
            "provider": "file",
            "output": fixture.output.path,
            "key-material": fixture.material.path
        ]
        for (key, value) in extra { options[key] = value }
        return CLIArguments(command: "seal", options: options)
    }

    private func decodeOBF3(_ fixture: Fixture) throws -> SealedSecretsV2 {
        try JSONDecoder().decode(SealedSecretsV2.self, from: try Data(contentsOf: fixture.output))
    }

    func testServerOnlyKeyExcludedFromBundle() throws {
        let fixture = try makeFixture(
            schemaJSON: """
            { "version": 1, "keys": {
              "API_KEY": { "classification": "clientBundled" },
              "SERVER_TOKEN": { "required": false, "classification": "serverOnly" }
            } }
            """,
            sourceJSON: #"{ "API_KEY": "abc", "SERVER_TOKEN": "should-not-ship" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertEqual(try runSeal(args: sealArgs(fixture), env: [:]), 0)
        let sealed = try decodeOBF3(fixture)
        XCTAssertNotNil(sealed.entries["API_KEY"])
        XCTAssertNil(sealed.entries["SERVER_TOKEN"], "serverOnly keys must never be bundled")
        let raw = String(decoding: try Data(contentsOf: fixture.output), as: UTF8.self)
        XCTAssertFalse(raw.contains("should-not-ship"))
    }

    func testServerOnlyOnlySchemaDoesNotRequireProviderSource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let schema = dir.appendingPathComponent("Secrets.schema.json")
        let output = dir.appendingPathComponent("Secrets.sealed")
        try Data(#"{ "version": 1, "keys": { "SERVER_TOKEN": { "required": true, "classification": "serverOnly" } } }"#.utf8).write(to: schema)

        let args = CLIArguments(command: "seal", options: [
            "schema": schema.path,
            "provider": "file",
            "output": output.path
        ])

        XCTAssertEqual(try runSeal(args: args, env: [:]), 0)

        let sealed = try JSONDecoder().decode(SealedSecretsV2.self, from: try Data(contentsOf: output))
        XCTAssertEqual(sealed.format, "OBF3")
        XCTAssertTrue(sealed.entries.isEmpty)
    }

    func testServerOnlyRoutedViaOverrideAborts() throws {
        let fixture = try makeFixture(
            schemaJSON: #"{ "version": 1, "keys": { "SERVER_TOKEN": { "classification": "serverOnly" } } }"#,
            sourceJSON: #"{ "SERVER_TOKEN": "x" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(try runSeal(args: sealArgs(fixture, extra: ["required-keys": "SERVER_TOKEN"]), env: [:])) { error in
            guard case SecretCompilerError.serverOnlyKeysRouted = error else {
                return XCTFail("expected serverOnlyKeysRouted, got \(error)")
            }
        }
    }

    func testPublicKeySealedAsPlain() throws {
        let fixture = try makeFixture(
            schemaJSON: #"{ "version": 1, "keys": { "CLIENT_ID": { "classification": "public" } } }"#,
            sourceJSON: #"{ "CLIENT_ID": "pub-123" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertEqual(try runSeal(args: sealArgs(fixture), env: [:]), 0)
        let entry = try XCTUnwrap(try decodeOBF3(fixture).entries["CLIENT_ID"])
        XCTAssertFalse(entry.obfuscated)
        XCTAssertEqual(entry.value, "pub-123")
    }

    func testRequireClassificationFailsOnUnclassified() throws {
        let fixture = try makeFixture(
            schemaJSON: #"{ "version": 1, "keys": { "API_KEY": { "required": true } } }"#,
            sourceJSON: #"{ "API_KEY": "abc" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(try runSeal(args: sealArgs(fixture, extra: ["require-classification": "true"]), env: [:])) { error in
            guard case SecretCompilerError.missingClassification(let keys) = error else {
                return XCTFail("expected missingClassification, got \(error)")
            }
            XCTAssertEqual(keys, ["API_KEY"])
        }
    }

    func testInvalidClassificationThrows() throws {
        let fixture = try makeFixture(
            schemaJSON: #"{ "version": 1, "keys": { "API_KEY": { "classification": "bogus" } } }"#,
            sourceJSON: #"{ "API_KEY": "abc" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(try runSeal(args: sealArgs(fixture), env: [:])) { error in
            guard case SecretCompilerError.invalidClassification = error else {
                return XCTFail("expected invalidClassification, got \(error)")
            }
        }
    }

    func testUnclassifiedDefaultsToClientBundled() throws {
        let fixture = try makeFixture(
            schemaJSON: #"{ "version": 1, "keys": { "API_KEY": { "required": true } } }"#,
            sourceJSON: #"{ "API_KEY": "abc" }"#
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertEqual(try runSeal(args: sealArgs(fixture), env: [:]), 0)
        let entry = try XCTUnwrap(try decodeOBF3(fixture).entries["API_KEY"])
        XCTAssertTrue(entry.obfuscated, "unclassified keys default to clientBundled (obfuscated)")
    }
}
#endif
