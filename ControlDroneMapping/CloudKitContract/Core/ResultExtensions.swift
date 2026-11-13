import Foundation

extension Result {
    /// Returns the success value or a caller-chosen fallback.
    nonisolated public func or(_ fallback: Success) -> Success {
        (try? get()) ?? fallback
    }

    /// Returns the success value or `nil` on failure.
    nonisolated public var orNil: Success? {
        try? get()
    }
}

