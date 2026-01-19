import Foundation

public final class ProtectedSecret {
    private var value: String

    public init(_ value: String) {
        self.value = value
    }

    public func get() -> String {
        return value
    }

    deinit {
        value = String(repeating: " ", count: value.count)
        value = ""
    }
}
