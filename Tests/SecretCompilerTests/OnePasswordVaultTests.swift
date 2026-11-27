#if os(macOS)
import Foundation
import XCTest

final class OnePasswordVaultTests: XCTestCase {
    func testValidateAndSealReadOnlyTheRequestedReference() throws {
        let fixture = try Fixture(script: """
        [ "$#" = 3 ] && [ "$1" = read ] && [ "$2" = --no-newline ] &&
          [ "$3" = 'op://Dev/Example Item/api key' ] || exit 41
        printf '%s' 'synthetic-value'
        """)
        let validation = try fixture.run(["validate"])
        XCTAssertEqual(validation.status, 0, validation.output)
        let output = fixture.directory.appendingPathComponent("Secrets.sealed")
        let seal = try fixture.run(["seal", "--legacy-obf2", "--output", output.path])
        XCTAssertEqual(seal.status, 0, seal.output)
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        let secrets = try XCTUnwrap(bundle["secrets"] as? [String: Any])
        XCTAssertEqual(Set(secrets.keys), ["APP_KEY"])
        XCTAssertFalse((validation.output + seal.output).contains("synthetic-value"))
    }

    func testLookupFailureDoesNotPrintEitherOutputStream() throws {
        let fixture = try Fixture(script: """
        printf '%s' synthetic-stdout
        printf '%s' synthetic-stderr >&2
        exit 44
        """)
        let result = try fixture.run(["validate"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("APP_KEY"), result.output)
        XCTAssertTrue(result.output.contains("authorize"), result.output)
        XCTAssertFalse(result.output.contains("synthetic-"))
    }

    func testMissingMalformedAndBlankFieldsFailWithKeyName() throws {
        for reference in [nil, "op://Dev/incomplete", "op://Dev/Item/key?attribute=type", "op://Dev/Item/key"] {
            let fixture = try Fixture(reference: reference, script: "printf '   '")
            let result = try fixture.run(["validate"])
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.output.contains("APP_KEY"), result.output)
        }
    }

    func testLookupHasDeadlineEvenWhenDescendantKeepsOutputOpen() throws {
        let fixture = try Fixture(timeout: 1, script: """
        sleep 6 &
        exit 0
        """)
        let start = Date()
        let result = try fixture.run(["validate"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("timed out"), result.output)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testVaultWithoutBackendStillUsesHashiCorpSettings() throws {
        let fixture = try Fixture(backend: nil, script: "exit 99")
        let result = try fixture.run(["validate"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("VAULT_ADDR"), result.output)
    }

    func testExecPassesServerOnlyValuesAndPreservesChildExitStatus() throws {
        let fixture = try Fixture(classification: "serverOnly", script: "printf '%s' synthetic-value")
        let result = try fixture.run(
            ["exec", "--", "/bin/sh", "-c", "[ \"$APP_KEY\" = synthetic-value ] && [ \"$1\" = --flag ] && exit 37", "child", "--flag"]
        )
        XCTAssertEqual(result.status, 37, result.output)
        XCTAssertFalse(result.output.contains("synthetic-value"))
    }

    private final class Fixture {
        let directory: URL

        init(
            backend: String? = "1password",
            reference: String? = "op://Dev/Example Item/api key",
            timeout: Double = 5,
            classification: String = "clientBundled",
            script: String
        ) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var vault: [String: Any] = ["timeoutSeconds": timeout]
            vault["backend"] = backend
            var references = ["UNRELATED_KEY": "op://Dev/Example Item/unrelated"]
            references["APP_KEY"] = reference
            vault["references"] = references
            try JSONSerialization.data(withJSONObject: [
                "schemaPath": "schema.json", "provider": "vault", "vault": vault
            ]).write(to: directory.appendingPathComponent("config.json"))
            try JSONSerialization.data(withJSONObject: [
                "version": 1,
                "required": ["APP_KEY"],
                "keys": ["APP_KEY": ["required": true, "obfuscate": true, "classification": classification]]
            ]).write(to: directory.appendingPathComponent("schema.json"))

            let op = directory.appendingPathComponent("op")
            try Data("#!/bin/sh\n\(script)\n".utf8).write(to: op)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: op.path)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = Bundle(for: OnePasswordVaultTests.self).bundleURL
                .deletingLastPathComponent().appendingPathComponent("secretcompiler")
            process.arguments = [arguments[0], "--config", directory.appendingPathComponent("config.json").path]
                + arguments.dropFirst()
            process.environment = ["PATH": "\(directory.path):/usr/bin:/bin"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
    }
}
#endif
