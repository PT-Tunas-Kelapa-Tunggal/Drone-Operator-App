import CloudKit
import Foundation

extension CKRecord {
    /// Safe, fault-tolerant field reader matching the contract specification verbatim.
    nonisolated public func read<T>(_ key: String, as type: T.Type = T.self) -> Result<T, FieldError> {
        guard let rawValue = self[key] else {
            return .failure(.missing(key: key))
        }

        if let typed = rawValue as? T {
            return .success(typed)
        }

        // Support automatic integer promotion (Int -> Int64)
        if T.self == Int64.self, let intVal = rawValue as? Int {
            return .success(Int64(intVal) as! T)
        }
        if T.self == Double.self, let num = rawValue as? NSNumber {
            return .success(num.doubleValue as! T)
        }

        return .failure(.typeMismatch(
            key: key,
            expected: String(describing: T.self),
            actual: String(describing: Swift.type(of: rawValue))
        ))
    }
}

