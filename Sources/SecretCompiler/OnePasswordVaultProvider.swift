#if os(macOS)
import Darwin
import Dispatch
import Foundation

struct OnePasswordVaultProvider: SecretsProvider {
    let references: [String: String]
    let environment: [String: String]
    let timeoutSeconds: Double

    var name: String { "vault (1Password)" }

    func loadSecrets(for keys: [String]) throws -> [String: String] {
        let requested = keys.compactMap { key in references[key].map { (key, $0) } }
        guard !requested.isEmpty else { return [:] }
        let path = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
        guard let executable = path.split(separator: ":")
            .map({ URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("op") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw SecretCompilerError.vaultRequestFailed("1Password CLI (op) is missing. Install it and enable 1Password desktop CLI integration.")
        }

        var values: [String: String] = [:]
        for (key, reference) in requested {
            // Named fields and IDs use the same syntax. Allow a section and literal spaces.
            let pattern = #"\Aop://[A-Za-z0-9_. -]+/[A-Za-z0-9_. -]+(/[A-Za-z0-9_. -]+){1,2}\z"#
            guard reference.range(of: pattern, options: .regularExpression) != nil else {
                throw SecretCompilerError.vaultRequestFailed("Invalid 1Password field reference for \(key).")
            }
            values[key] = try read(reference: reference, for: key, executable: executable)
        }
        return values
    }

    private func read(reference: String, for key: String, executable: URL) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["read", "--no-newline", reference]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output
        let reader = output.fileHandleForReading
        defer { try? reader.close() }

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        let deadline = DispatchTime.now() + timeoutSeconds
        do {
            try process.run()
        } catch {
            throw SecretCompilerError.vaultRequestFailed("Could not launch 1Password CLI for \(key).")
        }
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let timedOut = SecretCompilerError.vaultRequestFailed("1Password lookup for \(key) timed out. Unlock or authorize 1Password and retry.")
        let data = try readOutput(reader.fileDescriptor, before: deadline, for: key, timeoutError: timedOut)
        guard terminated.wait(timeout: deadline) == .success else { throw timedOut }
        guard process.terminationStatus == 0 else {
            throw SecretCompilerError.vaultRequestFailed(
                "1Password could not read \(key). Unlock or authorize the CLI and check access to the configured field (exit \(process.terminationStatus))."
            )
        }
        guard let value = String(data: data, encoding: .utf8),
              !value.contains("\0"),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecretCompilerError.vaultInvalidResponse("1Password returned a blank or invalid value for \(key).")
        }
        return value
    }

    private func readOutput(
        _ descriptor: Int32,
        before deadline: DispatchTime,
        for key: String,
        timeoutError: SecretCompilerError
    ) throws -> Data {
        let maximumBytes = 1_048_576
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var source = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else { throw timeoutError }
            let remainingMilliseconds = (deadline.uptimeNanoseconds - now + 999_999) / 1_000_000
            let ready = poll(&source, 1, Int32(remainingMilliseconds))
            if ready == 0 { throw timeoutError }
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else {
                throw SecretCompilerError.vaultInvalidResponse("Could not read 1Password CLI output for \(key).")
            }

            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 && errno == EINTR { continue }
            guard count > 0, data.count + count <= maximumBytes else {
                throw SecretCompilerError.vaultInvalidResponse("1Password CLI output for \(key) could not be read or exceeded the size limit.")
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
#endif
