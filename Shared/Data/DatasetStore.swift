import CryptoKit
import Foundation

final class DatasetStore: DatasetRepository {
    let root: URL
    init(root: URL? = nil) {
        self.root =
            root
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneMapping", isDirectory: true)
    }
    static func safeName(_ name: String) -> String {
        let cleaned = name.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0) ? String($0) : "-"
        }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Misi" : trimmed).prefix(70))
    }
    static func folderName(_ record: MissionRecord) -> String {
        let date = ISO8601DateFormatter().string(from: record.createdAt).prefix(19).replacingOccurrences(
            of: ":", with: "-")
        return "\(safeName(record.plan.name))_\(date)_\(record.id.uuidString)"
    }
    private func existingDirectory(_ id: UUID) -> URL? {
        let folders =
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.first {
            $0.lastPathComponent == id.uuidString || $0.lastPathComponent.hasSuffix("_" + id.uuidString)
        }
    }
    func directory(_ id: UUID) -> URL {
        existingDirectory(id) ?? root.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    func write(_ record: MissionRecord) throws {
        let folder =
            existingDirectory(record.id)
            ?? root.appendingPathComponent(Self.folderName(record), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encode(record).write(to: folder.appendingPathComponent("mission.json"), options: .atomic)
    }
    func records() -> [MissionRecord] {
        let folders =
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("mission.json")) else {
                return nil
            }
            return try? JSONDecoder().decode(MissionRecord.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    static func imagePath(_ capture: CaptureRecord, raw: Bool) -> String {
        let base = String(format: "IMG_%06d_", capture.sequence) + capture.id.uuidString
        if raw { return "RAW/" + base + ".dng" }
        return (capture.kind == "mapping" ? "" : "Calibration/") + base + ".jpg"
    }
    static func sidecarPath(_ image: String) -> String {
        "Metadata/" + URL(fileURLWithPath: image).lastPathComponent + ".metadata.plist"
    }
    // Images are moved first; the atomic JSON index is the commit marker. A staging journal
    // remains until commit so an interrupted RAW/JPEG move can be completed after restart.
    @discardableResult func commit(staging: URL, capture: CaptureRecord) throws -> CaptureRecord {
        let expected: Set<String> = capture.settings.raw ? ["image.jpg", "image.dng"] : ["image.jpg"]
        guard Set(capture.files) == expected, capture.files.count == expected.count else {
            throw MappingError.invalid("Capture JPEG/RAW belum lengkap")
        }
        let folder = directory(capture.missionID)
        var committed = capture
        committed.layoutVersion = 2
        committed.files = []
        committed.sha256 = [:]
        for old in capture.files {
            guard old == "image.jpg" || old == "image.dng", let hash = capture.sha256[old] else {
                throw MappingError.invalid("Capture tidak valid")
            }
            let name = Self.imagePath(capture, raw: old == "image.dng")
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: staging.appendingPathComponent(old), to: destination)
            }
            guard try Self.hashFile(destination) == hash else {
                throw MappingError.invalid("Checksum foto tidak cocok")
            }
            let sidecar = folder.appendingPathComponent(Self.sidecarPath(name))
            try FileManager.default.createDirectory(
                at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.moveItem(
                    at: staging.appendingPathComponent(old + ".metadata.plist"), to: sidecar)
            }
            committed.files.append(name)
            committed.sha256[name] = hash
        }
        let index = folder.appendingPathComponent("Metadata/" + capture.id.uuidString + ".json")
        try encode(committed).write(to: index, options: .atomic)
        try FileManager.default.removeItem(at: staging)
        return committed
    }
    func captureIndexes(_ id: UUID) throws -> [URL] {
        let folder = directory(id)
        let entries =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let flat =
            (try? FileManager.default.contentsOfDirectory(
                at: folder.appendingPathComponent("Metadata"), includingPropertiesForKeys: nil)) ?? []
        return flat.filter {
            $0.pathExtension == "json"
                && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
        }
            + entries.compactMap {
                guard UUID(uuidString: $0.lastPathComponent) != nil else { return nil }
                let index = $0.appendingPathComponent("capture.json")
                return FileManager.default.fileExists(atPath: index.path) ? index : nil
            }
    }
    // Copy and verify one old capture at a time. Never remove the source before commit.
    func migrateLegacy() throws {
        for record in records() {
            var folder = directory(record.id)
            if folder.lastPathComponent == record.id.uuidString {
                let named = root.appendingPathComponent(Self.folderName(record))
                try FileManager.default.moveItem(at: folder, to: named)
                folder = named
            }
            let entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
            for legacy in entries where UUID(uuidString: legacy.lastPathComponent) != nil {
                let index = legacy.appendingPathComponent("capture.json")
                guard FileManager.default.fileExists(atPath: index.path) else { continue }
                let capture = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: index))
                guard capture.missionID == record.id, capture.id.uuidString == legacy.lastPathComponent else {
                    throw MappingError.invalid("Identitas dataset lama tidak cocok")
                }
                let staging = folder.appendingPathComponent("." + capture.id.uuidString + ".pending")
                if !FileManager.default.fileExists(atPath: staging.path) {
                    try FileManager.default.copyItem(at: legacy, to: staging)
                }
                try commit(staging: staging, capture: capture)
                try FileManager.default.removeItem(at: legacy)
            }
        }
    }
    func recoverInterrupted() throws {
        for record in records() {
            let folder = directory(record.id)
            let entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
            for staging in entries
            where staging.lastPathComponent.hasPrefix(".") && staging.lastPathComponent.hasSuffix(".pending")
            {
                let index = staging.appendingPathComponent("capture.json")
                if let data = try? Data(contentsOf: index) {
                    let capture = try JSONDecoder().decode(CaptureRecord.self, from: data)
                    guard capture.missionID == record.id else {
                        throw MappingError.invalid("Journal misi tidak cocok")
                    }
                    try commit(staging: staging, capture: capture)
                }
            }
        }
        for var record in records() where [.countdown, .capturing, .paused, .ready].contains(record.phase) {
            record.saved = try captureIndexes(record.id).reduce(0) { count, url in
                let capture = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: url))
                return count + (capture.missionID == record.id && capture.kind == "mapping" ? 1 : 0)
            }
            record.phase = .paused
            record.note =
                "Recovered after app restart. Review dataset; create a new mission. Automatic resume is disabled."
            try write(record)
        }
    }
    func files(_ id: UUID) throws -> [URL] {
        let folder = directory(id)
        var result: Set<URL> = []
        for index in try captureIndexes(id) {
            let capture = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: index))
            guard capture.missionID == id else { throw MappingError.invalid("Identitas capture tidak cocok") }
            result.insert(index)
            for name in capture.files {
                let image: URL
                let sidecar: URL
                if capture.layoutVersion == 2 {
                    guard
                        name == Self.imagePath(capture, raw: false)
                            || name == Self.imagePath(capture, raw: true)
                    else { throw MappingError.invalid("Path foto tidak valid") }
                    image = folder.appendingPathComponent(name)
                    sidecar = folder.appendingPathComponent(Self.sidecarPath(name))
                } else {
                    guard name == "image.jpg" || name == "image.dng" else {
                        throw MappingError.invalid("Path foto lama tidak valid")
                    }
                    image = index.deletingLastPathComponent().appendingPathComponent(name)
                    sidecar = image.appendingPathExtension("metadata.plist")
                }
                guard FileManager.default.fileExists(atPath: image.path),
                    FileManager.default.fileExists(atPath: sidecar.path)
                else { throw MappingError.invalid("Dataset belum lengkap") }
                result.insert(image)
                result.insert(sidecar)
            }
        }
        // Manifest arrives last; receiver can audit before declaring completion.
        return result.sorted { $0.path < $1.path } + [folder.appendingPathComponent("mission.json")]
    }
    func verify(_ id: UUID) throws {
        let indexes = try captureIndexes(id)
        guard !indexes.isEmpty else { throw MappingError.invalid("Belum ada foto tersimpan") }
        let record = try JSONDecoder().decode(
            MissionRecord.self, from: Data(contentsOf: directory(id).appendingPathComponent("mission.json")))
        var mapping = 0
        _ = try files(id)
        for index in indexes {
            let capture = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: index))
            if capture.kind == "mapping" { mapping += 1 }
            for name in capture.files {
                let base = capture.layoutVersion == 2 ? directory(id) : index.deletingLastPathComponent()
                guard try Self.hashFile(base.appendingPathComponent(name)) == capture.sha256[name] else {
                    throw MappingError.invalid("Checksum dataset tidak cocok")
                }
            }
        }
        guard mapping == record.saved else {
            throw MappingError.invalid("Jumlah foto belum sesuai manifest; transfer ulang")
        }
    }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func safeFolder(_ name: String) -> String {
        name.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0) ? String($0) : "-"
        }.joined()
    }
    // Resource names are constrained to a mission folder and one subdirectory.
    static func destination(resource: String, root: URL) throws -> (URL, String) {
        let pieces = resource.components(separatedBy: "|")
        guard (3...4).contains(pieces.count), let id = UUID(uuidString: pieces[0]), pieces[1].count == 64,
            pieces[1].allSatisfy({ $0.isHexDigit })
        else { throw MappingError.invalid("Nama transfer tidak valid") }
        let path = pieces[2].components(separatedBy: "/")
        guard (1...2).contains(path.count),
            path.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.contains("\\")
                    && !$0.hasPrefix(".")
            })
        else {
            throw MappingError.invalid("Path transfer ditolak")
        }
        let missionFolder: URL
        if pieces.count == 4 {
            let name = pieces[3]
            guard name.hasSuffix("_" + id.uuidString), name.count <= 150,
                name == Self.safeFolder(name)
            else { throw MappingError.invalid("Nama folder misi ditolak") }
            missionFolder =
                DatasetStore(root: root).existingDirectory(id) ?? root.appendingPathComponent(name)
        } else {
            missionFolder = DatasetStore(root: root).directory(id)
        }
        return (path.reduce(missionFolder) { $0.appendingPathComponent($1) }, pieces[1])
    }
}
