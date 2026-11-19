import Darwin
import Foundation

enum OrthomosaicState: String, Codable {
    case ready, preparing, processing, completed, failed, cancelled
    var title: String {
        switch self {
        case .ready: return "Siap diolah"
        case .preparing: return "Menyiapkan foto"
        case .processing: return "Membuat orthomosaic"
        case .completed: return "Selesai"
        case .failed: return "Pengolahan gagal"
        case .cancelled: return "Dihentikan"
        }
    }
    var isRunning: Bool { self == .preparing || self == .processing }
}

struct OrthomosaicPhoto: Codable, Identifiable {
    var id = UUID()
    var url: URL
    var sha256: String
    var capturedAt: Date?
    var settings: CameraSettings?
    var location: GeoSample?
    var locationAge: Double?
    var attitude: AttitudeSample? = nil
}

struct OrthomosaicOutput: Codable {
    var folder: URL
    var image: URL
    var georeferenced: Bool
    var width: Int
    var height: Int
    var registered: Int
    var total: Int
    var warnings: [String]
    var createdAt = Date()
}

struct OrthomosaicProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var fromMission: Bool
    var datasetID: UUID? = nil
    var createdAt = Date()
    var photos: [OrthomosaicPhoto] = []
    var references: [OrthomosaicPhoto] = []
    var referenceID: UUID?
    var patch = GrayPatch()
    var confirmed = false
    // Optional so projects saved before this setting continue to decode.
    var retainWorkingFiles: Bool? = nil
    var state: OrthomosaicState = .ready
    var message = "Siap diolah. Gray card opsional untuk normalisasi warna."
    var fraction = 0.0
    var outputs: [OrthomosaicOutput] = []
    var reference: OrthomosaicPhoto? { references.first { $0.id == referenceID } }
    var colorPreparationReady: Bool {
        referenceID == nil ? references.isEmpty : reference != nil && confirmed
    }
    var mappingPhotos: [OrthomosaicPhoto] {
        let referenceHashes = Set(references.map(\.sha256))
        return photos.filter { !referenceHashes.contains($0.sha256) }
    }
    var obliqueMappingPhotos: [OrthomosaicPhoto] {
        mappingPhotos.filter { $0.attitude?.isOblique == true }
    }
}

struct OrthomosaicProgress {
    var state: OrthomosaicState
    var fraction: Double
    var message: String
}

protocol OrthomosaicRepository {
    var root: URL { get }
    func load() throws -> [OrthomosaicProject]
    func save(_ project: OrthomosaicProject) throws
    func importPhotos(_ urls: [URL], into project: OrthomosaicProject, reference: Bool) throws
        -> OrthomosaicProject
    func projectDirectory(_ id: UUID) -> URL
}

protocol OrthomosaicProcessing: Sendable {
    func check(runtime: URL, cancellation: OrthomosaicCancellation) throws -> String
    func process(
        project: OrthomosaicProject, folder: URL, runtime: URL,
        cancellation: OrthomosaicCancellation, progress: @escaping (OrthomosaicProgress) -> Void
    ) throws -> OrthomosaicOutput
}

/// Shared by preparation and the child process; launch and cancellation are serialized.
final class OrthomosaicCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    func check() throws {
        lock.lock()
        let stopped = cancelled
        lock.unlock()
        if stopped { throw CancellationError() }
    }
    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
        self.process = process
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let active = process
        if let active, active.isRunning { active.terminate() }
        lock.unlock()
        // Python signal handlers may wait for a long native C++/GPU call to return.
        // Bound cancellation and terminate the worker's isolated child group as well.
        if let active {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard active.isRunning else { return }
                let pid = active.processIdentifier
                if getpgid(pid) == pid { kill(-pid, SIGKILL) } else { kill(pid, SIGKILL) }
            }
        }
    }
}
