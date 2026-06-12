import Foundation

/// Holds a secret's bytes and best-effort zeroes them when the instance is released.
///
/// Honesty about the guarantee: `get()` returns a Swift `String`, which copies the bytes into storage
/// this type does not own and **cannot** zero; iOS also offers only weak guarantees about scrubbing
/// process memory, and an optimizer may elide a dead store. This wrapper therefore limits how long the
/// *primary* copy lingers — it is a hygiene measure, not a guarantee of secrecy. Prefer `withBytes(_:)`
/// over `get()` when you can avoid materializing a `String`.
public final class ProtectedSecret {
    private var bytes: [UInt8]

    public init(_ value: String) {
        self.bytes = Array(value.utf8)
    }

    /// The secret as a `String`. The returned copy is the caller's responsibility and cannot be zeroed.
    public func get() -> String {
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Access the raw secret bytes without materializing a `String` copy.
    public func withBytes<R>(_ body: ([UInt8]) throws -> R) rethrows -> R {
        return try body(bytes)
    }

    deinit {
        for index in bytes.indices {
            bytes[index] = 0
        }
    }
}
