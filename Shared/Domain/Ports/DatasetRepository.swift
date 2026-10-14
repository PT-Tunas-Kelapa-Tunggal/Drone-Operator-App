import Foundation

/// Storage contract shared by acquisition, transfer and export. No UI or camera dependencies.
protocol DatasetRepository: AnyObject {
    var root: URL { get }
    func directory(_ id: UUID) -> URL
    func records() -> [MissionRecord]
    func write(_ record: MissionRecord) throws
    func migrateLegacy() throws
    func recoverInterrupted() throws
    func commit(staging: URL, capture: CaptureRecord) throws -> CaptureRecord
    func files(_ id: UUID) throws -> [URL]
    func verify(_ id: UUID) throws
    func captureIndexes(_ id: UUID) throws -> [URL]
    func encode<T: Encodable>(_ value: T) throws -> Data
}
