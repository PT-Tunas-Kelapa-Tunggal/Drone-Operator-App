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


extension DatasetRepository {
    /// Remove only direct, UUID-owned dataset folders, including their exports and staging files.
    func removeLocalMissionFiles(_ ids: Set<UUID>) throws {
        let fm = FileManager.default
        guard !ids.isEmpty, fm.fileExists(atPath: root.path) else { return }
        let names = Set(ids.map(\.uuidString))
        for folder in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let name = folder.lastPathComponent
            if names.contains(name) || names.contains(where: { name.hasSuffix("_" + $0) }) {
                try fm.removeItem(at: folder)
            }
        }
    }
}
