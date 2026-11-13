import Foundation

/// Contract version metadata.
/// Bump this integer on EVERY change to the `CloudKitContract` folder.
/// This value is also stamped into each record's `schemaVersion` field by writers.
nonisolated public enum ContractInfo {
    public static let version: Int64 = 1
}

