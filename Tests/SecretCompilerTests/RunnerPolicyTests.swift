#if os(macOS)
import CryptoKit
import Foundation
import XCTest

final class RunnerPolicyTests: XCTestCase {
    func testStrictPolicyRejectsPathCompilerWithoutDigest() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let binDir = fixture.directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try writeFakeCompiler(
            to: binDir.appendingPathComponent("secretcompiler"),
            body: """
            #!/bin/sh
            echo "fake compiler executed" >&2
            exit 0
            """
        )

        let result = try runRunner(
            command: "validate",
            projectRoot: fixture.directory,
            extraEnvironment: ["PATH": "\(binDir.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("strict policy: refusing PATH secretcompiler"), result.stderr)
        XCTAssertFalse(result.stderr.contains("fake compiler executed"), result.stderr)
    }

    func testStrictPolicyAcceptsPathCompilerWithMatchingDigest() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let binDir = fixture.directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let fakeCompiler = binDir.appendingPathComponent("secretcompiler")
        try writeFakeCompiler(
            to: fakeCompiler,
            body: """
            #!/bin/sh
            if [ "$1" = "version" ] && [ "$2" = "--json" ]; then
              echo '{"version":"0.4.1"}'
              exit 0
            fi
            echo "fake compiler $*" >&2
            exit 0
            """
        )

        let digest = sha256Hex(of: try Data(contentsOf: fakeCompiler))
        let result = try runRunner(
            command: "validate",
            projectRoot: fixture.directory,
            extraEnvironment: [
                "PATH": "\(binDir.path):/usr/bin:/bin:/usr/sbin:/sbin",
                "SECRETSKIT_CLI_SHA256": digest
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("fake compiler validate --config"), result.stderr)
    }

    func testRunnerForwardsRequireClassificationFlag() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let binDir = fixture.directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let fakeCompiler = binDir.appendingPathComponent("secretcompiler")
        try writeFakeCompiler(
            to: fakeCompiler,
            body: """
            #!/bin/sh
            if [ "$1" = "version" ] && [ "$2" = "--json" ]; then
              echo '{"version":"0.4.1"}'
              exit 0
            fi
            case " $* " in
              *" --require-classification "*) echo "require classification forwarded" >&2; exit 0 ;;
              *) echo "missing require classification flag: $*" >&2; exit 9 ;;
            esac
            """
        )

        let digest = sha256Hex(of: try Data(contentsOf: fakeCompiler))
        let result = try runRunner(
            command: "seal",
            projectRoot: fixture.directory,
            extraArguments: ["--require-classification"],
            extraEnvironment: [
                "PATH": "\(binDir.path):/usr/bin:/bin:/usr/sbin:/sbin",
                "SECRETSKIT_CLI_SHA256": digest,
                "SECRETS_OUTPUT_PATH": fixture.directory.appendingPathComponent("Secrets.sealed").path
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("require classification forwarded"), result.stderr)
    }

    private struct RunnerResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    func testStrictPolicyRejectsCachedCompilerWithoutDigest() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let cacheDir = fixture.directory.appendingPathComponent("cache", isDirectory: true)
        let cachedBin = cacheDir.appendingPathComponent("0.4.1/secretcompiler")
        try FileManager.default.createDirectory(at: cachedBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFakeCompiler(
            to: cachedBin,
            body: """
            #!/bin/sh
            echo "fake compiler executed" >&2
            exit 0
            """
        )

        let result = try runRunner(
            command: "validate",
            projectRoot: fixture.directory,
            extraEnvironment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "SECRETSKIT_CLI_REF": "0.4.1",
                "SECRETSKIT_CACHE_DIR": cacheDir.path
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("strict policy: refusing cached secretcompiler"), result.stderr)
        XCTAssertFalse(result.stderr.contains("fake compiler executed"), result.stderr)
    }

    func testStrictPolicyAcceptsCachedCompilerWithMatchingDigest() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let cacheDir = fixture.directory.appendingPathComponent("cache", isDirectory: true)
        let cachedBin = cacheDir.appendingPathComponent("0.4.1/secretcompiler")
        try FileManager.default.createDirectory(at: cachedBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFakeCompiler(
            to: cachedBin,
            body: """
            #!/bin/sh
            if [ "$1" = "version" ] && [ "$2" = "--json" ]; then
              echo '{"version":"0.4.1"}'
              exit 0
            fi
            echo "fake compiler $*" >&2
            exit 0
            """
        )

        let digest = sha256Hex(of: try Data(contentsOf: cachedBin))
        let result = try runRunner(
            command: "validate",
            projectRoot: fixture.directory,
            extraEnvironment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "SECRETSKIT_CLI_REF": "0.4.1",
                "SECRETSKIT_CACHE_DIR": cacheDir.path,
                "SECRETSKIT_CLI_SHA256": digest
            ]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("fake compiler validate --config"), result.stderr)
    }

    func testCompatiblePolicyDoesNotUseMainFallbackForSeal() throws {
        let fixture = try makeProjectFixture(policy: "compatible")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let cacheDir = fixture.directory.appendingPathComponent("cache", isDirectory: true)
        let cachedBin = cacheDir.appendingPathComponent("main/secretcompiler")
        try FileManager.default.createDirectory(at: cachedBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFakeCompiler(
            to: cachedBin,
            body: """
            #!/bin/sh
            echo "fake compiler executed" >&2
            exit 0
            """
        )

        let result = try runRunner(
            command: "seal",
            projectRoot: fixture.directory,
            extraEnvironment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "SECRETSKIT_CACHE_DIR": cacheDir.path,
                "SECRETS_OUTPUT_PATH": fixture.directory.appendingPathComponent("Secrets.sealed").path
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("secretcompiler not found"), result.stderr)
        XCTAssertFalse(result.stderr.contains("fake compiler executed"), result.stderr)
    }

    private func makeProjectFixture(policy: String = "strict") throws -> (directory: URL, config: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDir = directory.appendingPathComponent("Config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let config = configDir.appendingPathComponent("SecretsKit.config.json")
        try Data("""
        {
          "cli": {
            "policy": "\(policy)",
            "minVersion": "0.4.1"
          }
        }
        """.utf8).write(to: config)
        return (directory, config)
    }

    private func writeFakeCompiler(to url: URL, body: String) throws {
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runRunner(
        command: String,
        projectRoot: URL,
        extraArguments: [String] = [],
        extraEnvironment: [String: String]
    ) throws -> RunnerResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runnerScript.path, command] + extraArguments

        var environment = ProcessInfo.processInfo.environment
        for key in [
            "SECRETSKIT_AUTO_BOOTSTRAP",
            "SECRETSKIT_CLI_PATH",
            "SECRETSKIT_CLI_POLICY",
            "SECRETSKIT_CLI_REF",
            "SECRETSKIT_CLI_REF_FALLBACK",
            "SECRETSKIT_CLI_SHA256",
            "SECRETSKIT_CACHE_DIR"
        ] {
            environment.removeValue(forKey: key)
        }
        environment["SRCROOT"] = projectRoot.path
        environment["SECRETS_CONFIG_PATH"] = projectRoot.appendingPathComponent("Config/SecretsKit.config.json").path
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return RunnerResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private var runnerScript: URL {
        repoRoot.appendingPathComponent("IntegrationTemplates/Scripts/SecretsKit/secretskit.sh")
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
