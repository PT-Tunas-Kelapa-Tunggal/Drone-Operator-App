import Foundation

struct DatasetLayoutTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label)
            count += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DatasetStore(root: root)
        var plan = MissionPlan()
        plan.name = "Kebun / utara: pagi"
        var mission = MissionRecord(plan: plan)
        try store.write(mission)
        check(
            store.directory(mission.id).lastPathComponent.hasPrefix("Kebun - utara- pagi_"),
            "Named folder is sanitized")
        let second = MissionRecord(plan: plan)
        try store.write(second)
        check(
            store.directory(mission.id) != store.directory(second.id),
            "Identical names never overwrite missions")
        func fixture(kind: String, raw: Bool = false) throws -> (URL, CaptureRecord) {
            let id = UUID()
            let staging = store.directory(mission.id).appendingPathComponent("." + id.uuidString + ".pending")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let names = raw ? ["image.jpg", "image.dng"] : ["image.jpg"]
            var hashes: [String: String] = [:]
            for name in names {
                let data = Data((id.uuidString + name).utf8)
                try data.write(to: staging.appendingPathComponent(name))
                try Data("metadata".utf8).write(to: staging.appendingPathComponent(name + ".metadata.plist"))
                hashes[name] = DatasetStore.hash(data)
            }
            var camera = CameraSettings()
            camera.raw = raw
            let capture = CaptureRecord(
                id: id, missionID: mission.id, sequence: 1, kind: kind, requestedAt: Date(),
                photoHostTimeSeconds: 1,
                settings: camera, files: names, sha256: hashes)
            try store.encode(capture).write(to: staging.appendingPathComponent("capture.json"))
            return (staging, capture)
        }
        let (staging, capture) = try fixture(kind: "mapping", raw: true)
        let committed = try store.commit(staging: staging, capture: capture)
        check(committed.layoutVersion == 2, "Flat layout is versioned")
        check(
            committed.files.contains(where: { !$0.contains("/") && $0.hasSuffix(".jpg") }),
            "Mapping JPEG directly in mission folder")
        check(
            committed.files.contains(where: { $0.hasPrefix("RAW/") }), "RAW separated from WebODM JPEG input")
        check(!FileManager.default.fileExists(atPath: staging.path), "Journal removed after commit")
        let (refStage, ref) = try fixture(kind: "calibration-before")
        let reference = try store.commit(staging: refStage, capture: ref)
        check(
            reference.files.allSatisfy { $0.hasPrefix("Calibration/") },
            "References excluded from main image folder")
        let (testStage, test) = try fixture(kind: "quality-test")
        let quality = try store.commit(staging: testStage, capture: test)
        check(
            quality.files.allSatisfy { $0.hasPrefix("Calibration/") },
            "Quality test excluded from mapping input")
        mission.saved = 1
        try store.write(mission)
        try store.verify(mission.id)
        let files = try store.files(mission.id)
        check(files.last?.lastPathComponent == "mission.json", "Manifest transferred last")
        let orphan = store.directory(mission.id).appendingPathComponent("orphan.jpg")
        try Data().write(to: orphan)
        check(!(try store.files(mission.id)).contains(orphan), "Uncommitted image never exported")
        let (crashStage, crashCapture) = try fixture(kind: "mapping", raw: true)
        let jpg = store.directory(mission.id).appendingPathComponent(
            DatasetStore.imagePath(crashCapture, raw: false))
        try FileManager.default.moveItem(at: crashStage.appendingPathComponent("image.jpg"), to: jpg)
        try store.recoverInterrupted()
        check(
            store.records().first(where: { $0.id == mission.id })?.saved == 2,
            "Recovery completes interrupted flat RAW/JPEG transaction")
        check(
            !FileManager.default.fileExists(atPath: crashStage.path), "Recovery commits and removes journal")
        check(
            store.records().first(where: { $0.id == mission.id })?.phase == .paused,
            "Recovery never restarts capture")
        let transfer =
            "\(mission.id)|\(DatasetStore.hash(Data()))|\(committed.files[0])|\(store.directory(mission.id).lastPathComponent)"
        let (destination, _) = try DatasetStore.destination(resource: transfer, root: root)
        check(
            destination.deletingLastPathComponent() == store.directory(mission.id),
            "Named transfer preserves mission directory")
        do {
            _ = try DatasetStore.destination(resource: transfer + "/outside", root: root)
            preconditionFailure("Unsafe folder accepted")
        } catch { count += 1 }
        let legacyRoot = root.appendingPathComponent("legacy")
        let legacyStore = DatasetStore(root: legacyRoot)
        var oldMission = MissionRecord(plan: plan)
        oldMission.saved = 1
        oldMission.phase = .completed
        let oldFolder = legacyRoot.appendingPathComponent(oldMission.id.uuidString)
        let oldID = UUID()
        let captureFolder = oldFolder.appendingPathComponent(oldID.uuidString)
        try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
        let data = Data("unchanged original".utf8)
        try data.write(to: captureFolder.appendingPathComponent("image.jpg"))
        try Data("metadata".utf8).write(to: captureFolder.appendingPathComponent("image.jpg.metadata.plist"))
        let oldCapture = CaptureRecord(
            id: oldID, missionID: oldMission.id, sequence: 1, kind: "mapping", requestedAt: Date(),
            photoHostTimeSeconds: 1,
            settings: CameraSettings(), files: ["image.jpg"], sha256: ["image.jpg": DatasetStore.hash(data)])
        try legacyStore.encode(oldCapture).write(to: captureFolder.appendingPathComponent("capture.json"))
        try legacyStore.encode(oldMission).write(to: oldFolder.appendingPathComponent("mission.json"))
        try legacyStore.migrateLegacy()
        try legacyStore.verify(oldMission.id)
        check(
            legacyStore.directory(oldMission.id).lastPathComponent.hasPrefix("Kebun"),
            "Legacy mission gets readable name")
        let migrated = try legacyStore.files(oldMission.id).first { $0.pathExtension == "jpg" }!
        check(try Data(contentsOf: migrated) == data, "Migration preserves original bytes")
        check(
            !FileManager.default.fileExists(
                atPath: legacyStore.directory(oldMission.id).appendingPathComponent(oldID.uuidString).path),
            "Legacy per-photo directory replaced after verified commit")
        try legacyStore.migrateLegacy()
        check(try legacyStore.captureIndexes(oldMission.id).count == 1, "Migration is idempotent")
        let badID = UUID()
        let badFolder = legacyStore.directory(oldMission.id).appendingPathComponent(badID.uuidString)
        try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
        try data.write(to: badFolder.appendingPathComponent("image.jpg"))
        try Data("metadata".utf8).write(to: badFolder.appendingPathComponent("image.jpg.metadata.plist"))
        var bad = oldCapture
        bad.id = badID
        bad.settings.raw = true
        try legacyStore.encode(bad).write(to: badFolder.appendingPathComponent("capture.json"))
        do {
            try legacyStore.migrateLegacy()
            preconditionFailure("Incomplete RAW migration accepted")
        } catch { count += 1 }
        check(
            try Data(contentsOf: badFolder.appendingPathComponent("image.jpg")) == data,
            "Failed migration preserves source originals")
        return count
    }
}
