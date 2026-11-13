import Foundation

/// Granular error representing field-level read or parse failures.
nonisolated public enum FieldError: Error, Equatable, Sendable {
    /// The specified field key was not found or was nil on the record.
    case missing(key: String)

    /// The field value was present but had an unexpected type.
    case typeMismatch(key: String, expected: String, actual: String)

    /// The field value could not be parsed into a domain representation (e.g. invalid enum raw value).
    case unreadable(key: String, reason: String)

    /// JSON decoding or envelope parsing failed.
    case decodingError(key: String, errorDescription: String)

    /// Convenience checker for missing field.
    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}

