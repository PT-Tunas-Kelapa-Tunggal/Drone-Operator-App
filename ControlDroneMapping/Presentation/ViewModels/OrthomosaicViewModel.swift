import AppKit
import Combine
import Foundation

final class OrthomosaicViewModel: ObservableObject {
    @Published private(set) var projects: [OrthomosaicProject] = []
    @Published private(set) var selectedID: UUID?
    @Published var showingEditor = false
    @Published private(set) var preview: RGBPreview?
    @Published private(set) var busy = false
    @Published private(set) var workingID: UUID?
    @Published private(set) var engineReady = false
    @Published private(set) var engineMessage = "Pasang engine satu kali untuk mengaktifkan pengolahan."
    @Published private(set) var engineInstalling = false
    @Published private(set) var engineInstallFailed = false
    @Published private(set) var engineProgress: EngineInstallationProgress?
    @Published var error: String?
    @Published private(set) var storageError: String?
    private let repository: any OrthomosaicRepository
    private let service: any OrthomosaicProcessing
    private let datasets: any DatasetRepository
    private let runtimeAccess: OrthomosaicRuntimeAccess
    private let installer: (any OrthomosaicEngineInstalling)?
    private var installationTask: Task<Void, Never>?
    private var runtime: URL?
    private var cancellation: OrthomosaicCancellation?
    private let queue = DispatchQueue(label: "mapping.orthomosaic", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "mapping.orthomosaic.preview", qos: .userInitiated)

    init(
        repository: any OrthomosaicRepository, service: any OrthomosaicProcessing,
        datasets: any DatasetRepository, runtimeAccess: OrthomosaicRuntimeAccess,
        installer: (any OrthomosaicEngineInstalling)? = nil
    ) {
        self.repository = repository
        self.service = service
        self.datasets = datasets
        self.runtimeAccess = runtimeAccess
        self.installer = installer
        do { projects = try repository.load() } catch { storageError = error.localizedDescription }
        do {
            if let runtime = BundledOrthomosaicEngine.embeddedDirectory {
                checkRuntime(runtime, remember: false)
            } else if let runtime = try runtimeAccess.resolve() {
                checkRuntime(runtime, remember: false)
            } else if let directory = installer?.directory,
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("engine.json").path)
            {
                checkRuntime(directory, remember: false)
            }
        } catch { engineMessage = "Pilih kembali folder engine: " + error.localizedDescription }
    }
    var selected: OrthomosaicProject? { projects.first { $0.id == selectedID } }
    var canStart: Bool {
        guard let project = selected else { return false }
        return engineReady && !engineInstalling && !busy && storageError == nil
            && project.colorPreparationReady && project.mappingPhotos.count >= 3
    }
    func project(_ id: UUID) -> OrthomosaicProject? { projects.first { $0.id == id } }
    func open(_ id: UUID) {
        guard project(id) != nil else { return }
        selectedID = id
        error = nil
        showingEditor = true
        loadPreview()
    }
    private func replace(_ project: OrthomosaicProject, save: Bool = true) throws {
        if save { try repository.save(project) }
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
    }
    private func edit(_ change: (inout OrthomosaicProject) -> Void) {
        guard !busy, storageError == nil, var project = selected else { return }
        change(&project)
        project.state = .ready
        project.fraction = 0
        project.message = "Siap membuat hasil baru dengan pengaturan ini."
        do { try replace(project) } catch { self.error = error.localizedDescription }
    }
    func setReference(_ id: UUID?) {
        edit {
            $0.referenceID = id
            $0.confirmed = false
            $0.patch = GrayPatch()
        }
        loadPreview()
    }
    func removeGrayCard() {
        edit {
            // A reference imported from the mapping set must never return to stitching.
            $0.photos = $0.mappingPhotos
            $0.references = []
            $0.referenceID = nil
            $0.confirmed = false
        }
        loadPreview()
    }
    func setConfirmed(_ value: Bool) { edit { $0.confirmed = value } }
    func setRetainWorkingFiles(_ value: Bool) { edit { $0.retainWorkingFiles = value } }
    func excludePhoto(_ id: UUID) { edit { $0.photos.removeAll { $0.id == id } } }
    func movePatch(x: Double, y: Double) {
        edit {
            $0.patch.x = min(1 - $0.patch.width, max(0, x - $0.patch.width / 2))
            $0.patch.y = min(1 - $0.patch.height, max(0, y - $0.patch.height / 2))
            $0.confirmed = false
        }
    }
    func setPatchSize(_ size: Double) {
        edit {
            let centerX = $0.patch.x + $0.patch.width / 2
            let centerY = $0.patch.y + $0.patch.height / 2
            $0.patch.width = size
            $0.patch.height = size
            $0.patch.x = min(1 - size, max(0, centerX - size / 2))
            $0.patch.y = min(1 - size, max(0, centerY - size / 2))
            $0.confirmed = false
        }
    }
    func loadPreview() {
        preview = nil
        guard let project = selected,
            let photo = project.references.first(where: { $0.id == project.referenceID })
        else { return }
        let id = project.id
        previewQueue.async { [self] in
            let result = Result { try RGBPreview(url: photo.url) }
            DispatchQueue.main.async { [self] in
                guard selectedID == id, selected?.referenceID == photo.id else { return }
                switch result {
                case .success(let preview): self.preview = preview
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func prepareMission(_ record: MissionRecord, projectID: UUID? = nil, refresh: Bool = false) {
        let id = projectID ?? record.id
        if project(id) != nil && !refresh {
            open(id)
            return
        }
        guard !busy, storageError == nil else { return }
        let existing = project(id)
        busy = true
        error = nil
        queue.async { [self] in
            do {
                try datasets.verify(record.id)
                let photos = try WebODMExporter(store: datasets).photos(record.id)
                var project =
                    existing ?? OrthomosaicProject(id: id, name: record.plan.name, fromMission: true)
                project.datasetID = record.id
                let selectedReferenceHash = project.references.first { $0.id == project.referenceID }?.sha256
                for photo in photos where ["mapping", "calibration-before"].contains(photo.capture.kind) {
                    let capture = photo.capture
                    let input = OrthomosaicPhoto(
                        id: capture.id, url: photo.url, sha256: try DatasetStore.hashFile(photo.url),
                        capturedAt: capture.requestedAt, settings: capture.settings,
                        location: capture.location, locationAge: capture.locationAgeAtRequest)
                    if capture.kind == "mapping" {
                        if let index = project.photos.firstIndex(where: {
                            $0.id == input.id || $0.sha256 == input.sha256
                        }) {
                            project.photos[index] = input
                        } else {
                            project.photos.append(input)
                        }
                    } else {
                        if let index = project.references.firstIndex(where: {
                            $0.id == input.id || $0.sha256 == input.sha256
                        }) {
                            project.references[index] = input
                        } else {
                            project.references.append(input)
                        }
                    }
                }
                project.referenceID =
                    project.references.first { $0.sha256 == selectedReferenceHash }?.id
                    ?? project.references.last?.id
                project.confirmed = false
                project.state = .ready
                project.fraction = 0
                project.message =
                    project.referenceID == nil
                    ? "Foto transfer dimuat. Siap diolah tanpa normalisasi warna."
                    : "Foto transfer dimuat. Konfirmasi kembali area gray card awal."
                try repository.save(project)
                DispatchQueue.main.async { [self] in
                    do {
                        try replace(project, save: false)
                        busy = false
                        open(project.id)
                    } catch { finishWithError(error) }
                }
            } catch { DispatchQueue.main.async { [self] in finishWithError(error) } }
        }
    }

    /// Folder import intentionally reads only its top level, excluding RAW, calibration and prior exports.
    func importPhotos(
        _ urls: [URL], mission: MissionRecord? = nil, projectID: UUID? = nil,
        reference: Bool = false, append: Bool = false
    ) {
        guard !busy, storageError == nil else { return }
        let existing =
            (projectID ?? mission?.id).flatMap { project($0) } ?? (append || reference ? selected : nil)
        let project =
            existing
            ?? OrthomosaicProject(
                id: projectID ?? mission?.id ?? UUID(),
                name: mission?.plan.name ?? urls.first.map {
                    $0.hasDirectoryPath
                        ? $0.lastPathComponent : $0.deletingLastPathComponent().lastPathComponent
                } ?? "Impor foto", fromMission: mission != nil)
        busy = true
        error = nil
        queue.async { [self] in
            let granted = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                for url in granted { url.stopAccessingSecurityScopedResource() }
            }
            do {
                var inputs = [URL]()
                let supported = Set(["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"])
                for url in urls {
                    let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                    let files =
                        isDirectory
                        ? try FileManager.default.contentsOfDirectory(
                            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                        : [url]
                    inputs += files.filter { supported.contains($0.pathExtension.lowercased()) }
                }
                inputs.sort { $0.path < $1.path }
                guard !reference || inputs.count == 1 else {
                    throw MappingError.invalid("Pilih satu foto gray card awal.")
                }
                let updated = try repository.importPhotos(inputs, into: project, reference: reference)
                DispatchQueue.main.async { [self] in
                    do {
                        try replace(updated, save: false)
                        busy = false
                        open(updated.id)
                    } catch { finishWithError(error) }
                }
            } catch { DispatchQueue.main.async { [self] in finishWithError(error) } }
        }
    }

    func checkRuntime(_ url: URL, remember: Bool = true) {
        guard !busy, !engineInstalling else { return }
        busy = true
        engineReady = false
        engineMessage = "Memeriksa engine dan GPU lokal…"
        error = nil
        let token = OrthomosaicCancellation()
        queue.async { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let message = try service.check(runtime: url, cancellation: token)
                if remember { try runtimeAccess.remember(url) }
                DispatchQueue.main.async { [self] in
                    runtime = url
                    engineReady = true
                    engineMessage = message
                    busy = false
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    runtime = nil
                    engineMessage = error.localizedDescription
                    busy = false
                }
            }
        }
    }

    func installEngine() {
        guard !busy, !engineInstalling, !engineReady, let installer else { return }
        engineInstalling = true
        engineInstallFailed = false
        engineProgress = .init(message: "Menyiapkan pemasangan…")
        engineMessage = "Pemasangan berjalan di background."
        installationTask = Task { @MainActor [self] in
            do {
                let directory = try await installer.install { update in
                    DispatchQueue.main.async { [self] in
                        if engineInstalling { engineProgress = update }
                    }
                }
                try Task.checkCancellation()
                engineProgress = .init(message: "Memeriksa engine & GPU lokal…")
                let token = OrthomosaicCancellation()
                let message = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<String, Error>) in
                        queue.async { [service] in
                            continuation.resume(
                                with: Result { try service.check(runtime: directory, cancellation: token) })
                        }
                    }
                } onCancel: {
                    token.cancel()
                }
                try Task.checkCancellation()
                // The app-owned location is rediscovered on launch; no Finder grant is required.
                runtimeAccess.defaults.removeObject(forKey: runtimeAccess.key)
                runtime = directory
                engineReady = true
                engineMessage = message
            } catch {
                let stopped = error is CancellationError || Task.isCancelled
                engineInstallFailed = !stopped
                engineMessage =
                    stopped
                    ? "Pemasangan dihentikan. Klik Pasang engine untuk mencoba lagi."
                    : "Pemasangan belum selesai. " + Self.installationError(error)
            }
            engineInstalling = false
            engineProgress = nil
            installationTask = nil
        }
    }
    func cancelEngineInstallation() {
        engineProgress = .init(message: "Menghentikan pemasangan…")
        installationTask?.cancel()
    }
    var hasEngineInstaller: Bool { installer != nil }
    var allowsExternalEngine: Bool { !BundledOrthomosaicEngine.isSandboxed }
    var engineInstallationLog: URL? {
        guard let log = installer?.directory.appendingPathComponent("installation.log"),
            FileManager.default.fileExists(atPath: log.path)
        else { return nil }
        return log
    }
    private static func installationError(_ error: Error) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .cannotFindHost, .dnsLookupFailed:
                return
                    "Alamat layanan unduhan tidak ditemukan (DNS). Coba koneksi internet lain atau hotspot lalu pasang lagi."
            case .notConnectedToInternet:
                return "Mac belum terhubung ke internet. Sambungkan koneksi lalu pasang lagi."
            case .cannotConnectToHost:
                return "Layanan unduhan tidak dapat dihubungi dari jaringan ini. Coba koneksi internet lain."
            case .timedOut: return "Koneksi unduhan terputus atau terlalu lambat. Coba lagi."
            default: break
            }
        }
        return error.localizedDescription
    }

    func start() {
        guard canStart, var project = selected, let runtime else { return }
        let token = OrthomosaicCancellation()
        cancellation = token
        project.state = .preparing
        project.message = "Memeriksa foto dan engine lokal…"
        project.fraction = 0
        do { try replace(project) } catch {
            self.error = error.localizedDescription
            return
        }
        busy = true
        workingID = project.id
        error = nil
        let snapshot = project
        let folder = repository.projectDirectory(project.id)
        queue.async { [self] in
            let access = runtime.startAccessingSecurityScopedResource()
            defer { if access { runtime.stopAccessingSecurityScopedResource() } }
            do {
                let output = try service.process(
                    project: snapshot, folder: folder, runtime: runtime,
                    cancellation: token
                ) { update in
                    DispatchQueue.main.async { [self] in
                        guard var current = self.project(snapshot.id), workingID == snapshot.id else {
                            return
                        }
                        let changedStage = current.message != update.message
                        current.state = update.state
                        current.message = update.message
                        current.fraction = update.fraction
                        do { try replace(current, save: changedStage) } catch {
                            token.cancel()
                            self.error = error.localizedDescription
                        }
                    }
                }
                DispatchQueue.main.async { [self] in
                    guard var current = self.project(snapshot.id) else {
                        finishWithError(MappingError.invalid("Misi pengolahan hilang."))
                        return
                    }
                    current.outputs.insert(output, at: 0)
                    current.state = .completed
                    current.fraction = 1
                    current.message =
                        output.georeferenced ? "GeoTIFF selesai." : "TIFF selesai · koordinat lokal."
                    do { try replace(current) } catch {
                        self.error =
                            "Hasil dibuat, tetapi riwayat gagal disimpan: " + error.localizedDescription
                    }
                    busy = false
                    workingID = nil
                    cancellation = nil
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    if var current = self.project(snapshot.id) {
                        current.state = error is CancellationError ? .cancelled : .failed
                        current.message =
                            error is CancellationError
                            ? "Pengolahan dihentikan. Foto asli dan hasil sebelumnya tetap tersimpan."
                            : error.localizedDescription
                        do { try replace(current) } catch { self.error = error.localizedDescription }
                    }
                    finishWithError(error)
                }
            }
        }
    }
    func cancel() { cancellation?.cancel() }
    private func finishWithError(_ error: Error) {
        if !(error is CancellationError) { self.error = error.localizedDescription }
        busy = false
        workingID = nil
        cancellation = nil
    }
    func openFolder(_ id: UUID) { NSWorkspace.shared.open(repository.projectDirectory(id)) }
    func showOutput(_ output: OrthomosaicOutput) {
        NSWorkspace.shared.activateFileViewerSelecting([output.image])
    }
    func exportOutput(_ output: OrthomosaicOutput, to destination: URL) {
        guard !busy else { return }
        busy = true
        queue.async { [self] in
            let access = destination.startAccessingSecurityScopedResource()
            defer { if access { destination.stopAccessingSecurityScopedResource() } }
            do {
                // Atomic write keeps an existing destination intact if copying fails.
                try Data(contentsOf: output.image, options: .mappedIfSafe).write(
                    to: destination, options: .atomic)
                DispatchQueue.main.async { [self] in busy = false }
            } catch { DispatchQueue.main.async { [self] in finishWithError(error) } }
        }
    }
}
