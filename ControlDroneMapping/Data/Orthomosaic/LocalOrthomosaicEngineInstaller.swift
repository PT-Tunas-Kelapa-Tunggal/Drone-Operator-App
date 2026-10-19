import Darwin
import Foundation

/// Installs into one permanent, app-owned prefix. Conda environments cannot be moved after building.
struct LocalOrthomosaicEngineInstaller: OrthomosaicEngineInstalling {
    /// Conda compiler activation embeds unquoted prefix flags; Application Support breaks compilation.
    /// Downloadable runtimes belong in Caches and must be rebuilt in place if the cache is removed.
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/Engines/OpenSfM-packaged-v1")
    }
    let directory: URL
    var session: URLSession = .shared
    private let bootstrapVersion = "2.9.0-0"
    private let bootstrapHash = "ec2a072f028e1a7cf20f3e2e74d5a8127cf5a5f27636375b5359811565f4e5be"

    private struct Source: Codable {
        let commit: String
        var pybind: String?
    }

    func install(progress: @escaping (EngineInstallationProgress) -> Void) async throws -> URL {
        do {
            return try await performInstallation(progress: progress)
        } catch {
            let log = directory.appendingPathComponent("installation.log")
            if let handle = try? FileHandle(forWritingTo: log) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                let failure = error as NSError
                let message =
                    "\n\(Date()) · \(failure.domain) (\(failure.code)): \(failure.localizedDescription)\n"
                try? handle.write(contentsOf: Data(message.utf8))
                if let download = error as? EngineDownloadFailure {
                    let detail =
                        "URL: \(download.url.absoluteString)\nNetwork: \(NSURLErrorDomain) (\(download.cause.code.rawValue))\n"
                    try? handle.write(contentsOf: Data(detail.utf8))
                }
            }
            throw error
        }
    }

    private func performInstallation(progress: @escaping (EngineInstallationProgress) -> Void) async throws
        -> URL
    {
        #if !arch(arm64)
            throw MappingError.invalid("Pemasangan otomatis membutuhkan Mac Apple Silicon.")
        #else
            let fm = FileManager.default
            try Task.checkCancellation()
            if let runtime = BundledOrthomosaicEngine.embeddedDirectory {
                progress(.init(message: "Memeriksa engine bawaan aplikasi…"))
                try BundledOrthomosaicEngine.validateEmbedded()
                return runtime
            }
            guard !BundledOrthomosaicEngine.isSandboxed else {
                throw MappingError.invalid(
                    "Build aplikasi belum menyertakan engine bawaan. Siapkan paket engine lalu build ulang aplikasi.")
            }
            guard !directory.path.contains(where: { $0.isWhitespace }) else {
                throw MappingError.invalid(
                    "Lokasi engine mengandung spasi yang tidak didukung alat kompilasi. Gunakan lokasi engine bawaan aplikasi."
                )
            }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // An OS lock also protects this prefix against a second app instance and dies with the app.
            let lockURL = directory.appendingPathComponent("installation.lock")
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw MappingError.invalid("Folder pemasangan tidak dapat dibuka.") }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw MappingError.invalid("Pemasangan engine masih berjalan di jendela aplikasi lain.")
            }
            defer { flock(descriptor, LOCK_UN) }
            let log = directory.appendingPathComponent("installation.log")
            if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
            if let package = BundledOrthomosaicEngine.available {
                try await package.install(at: directory, log: log, progress: progress)
                return directory
            }
            guard !BundledOrthomosaicEngine.isSandboxed else {
                throw MappingError.invalid(
                    "Build aplikasi belum menyertakan paket engine siap pakai. Siapkan paket engine lalu build ulang aplikasi."
                )
            }
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Memasang engine orthomosaic")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let downloads = directory.appendingPathComponent("Downloads")
            let temporary = directory.appendingPathComponent("Temporary")
            try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
            try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
            var environment = ProcessInfo.processInfo.environment
            environment["MAMBA_ROOT_PREFIX"] = directory.appendingPathComponent("Packages").path
            environment["XDG_CACHE_HOME"] = directory.appendingPathComponent("Cache").path
            environment["TMPDIR"] = temporary.path + "/"
            environment["PIP_CACHE_DIR"] = directory.appendingPathComponent("Cache/pip").path
            environment["PIP_CONFIG_FILE"] = "/dev/null"
            environment["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
            environment["PYTHONNOUSERSITE"] = "1"
            environment["CMAKE_BUILD_PARALLEL_LEVEL"] = "2"
            environment["PROJ_NETWORK"] = "OFF"

            progress(.init(message: "Memeriksa alat pengolahan Apple…"))
            do {
                try await run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", "clang"], environment, log)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw MappingError.invalid(
                    "Apple Command Line Tools belum siap. Pasang melalui Xcode lalu coba lagi.")
            }

            let manager = directory.appendingPathComponent("micromamba")
            if (try? DatasetStore.hashFile(manager)) != bootstrapHash {
                try? fm.removeItem(at: manager)
                try await download(
                    "https://github.com/mamba-org/micromamba-releases/releases/download/\(bootstrapVersion)/micromamba-osx-arm64",
                    to: manager, message: "Mengunduh pemasang engine…", progress: progress)
            }
            guard try DatasetStore.hashFile(manager) == bootstrapHash else {
                try? fm.removeItem(at: manager)
                throw MappingError.invalid("Unduhan pemasang tidak lolos pemeriksaan. Coba unduh kembali.")
            }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: manager.path)
            progress(.init(message: "Menyiapkan sumber engine…"))
            let sourceURL = directory.appendingPathComponent("source.json")
            var source: Source
            if fm.fileExists(atPath: sourceURL.path) {
                source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: sourceURL))
            } else {
                let commitInfo = try await metadata(
                    "https://api.github.com/repos/OpenSfM/OpenSfM/commits/master")
                let commit = try Self.commit(commitInfo["sha"])
                source = Source(commit: commit)
                try JSONEncoder().encode(source).write(to: sourceURL, options: .atomic)
            }
            _ = try Self.commit(source.commit)
            if let pybind = source.pybind { _ = try Self.commit(pybind) }
            let engine = directory.appendingPathComponent("OpenSfM")
            try await unpack(
                repository: "OpenSfM/OpenSfM", commit: source.commit, archiveName: "OpenSfM",
                destination: engine, downloads: downloads, environment: environment, log: log,
                progress: progress)
            let pybindDirectory = engine.appendingPathComponent("opensfm/src/lib/third_party/pybind11")
            // Some OpenSfM commits vendor pybind11 directly; their contents API returns an array.
            // Preserve those sources and only fetch a submodule when the archive actually needs one.
            if !Self.hasBundledPybind(in: engine) {
                if source.pybind == nil {
                    let submodule = try await metadata(
                        "https://api.github.com/repos/OpenSfM/OpenSfM/contents/opensfm/src/lib/third_party/pybind11?ref=\(source.commit)"
                    )
                    source.pybind = try Self.commit(submodule["sha"])
                    try JSONEncoder().encode(source).write(to: sourceURL, options: .atomic)
                }
                try await unpack(
                    repository: "pybind/pybind11", commit: source.pybind!, archiveName: "pybind11",
                    destination: pybindDirectory, downloads: downloads, environment: environment,
                    log: log, progress: progress)
            }
            let lockFile = engine.appendingPathComponent("conda-osx-arm64.lock")
            guard fm.fileExists(atPath: lockFile.path) else {
                throw MappingError.invalid("Sumber engine tidak menyediakan dependensi Apple Silicon.")
            }
            let prefix = directory.appendingPathComponent("environment")
            let existing = fm.fileExists(atPath: prefix.appendingPathComponent("conda-meta/history").path)
            if !existing, fm.fileExists(atPath: prefix.path) { try fm.removeItem(at: prefix) }
            progress(
                .init(
                    message: "Mengunduh & memasang dependensi…",
                    detail: "Tahap ini dapat memakan waktu. Aplikasi tetap bisa digunakan."))
            try await run(
                manager,
                [
                    "--no-rc", existing ? "install" : "create", "--prefix", prefix.path,
                    "--file", lockFile.path, "--yes",
                ], environment, log)
            // The Python 3.10 PyPI SciPy wheel has invalid Mach-O zero-fill offsets on newer
            // macOS. This conda-forge build satisfies OpenSfM and loads without patching binaries.
            progress(.init(message: "Memasang pustaka numerik untuk macOS…"))
            let records = try fm.contentsOfDirectory(atPath: prefix.appendingPathComponent("conda-meta").path)
            if !records.contains(where: { $0.hasPrefix("scipy-") && $0.hasSuffix(".json") }) {
                // Repair earlier installs that already pulled the incompatible PyPI wheel.
                try await run(
                    manager,
                    [
                        "--no-rc", "run", "--prefix", prefix.path, "python", "-m", "pip", "uninstall",
                        "--yes", "scipy",
                    ],
                    environment, log)
            }
            try await run(
                manager,
                [
                    "--no-rc", "install", "--prefix", prefix.path, "--channel", "conda-forge",
                    "--freeze-installed", "scipy=1.15.2", "--yes",
                ], environment, log)
            progress(
                .init(
                    message: "Membangun engine foto…",
                    detail: "Sedang menyiapkan komponen pengolahan untuk Mac ini."))
            try await run(
                manager,
                ["--no-rc", "run", "--prefix", prefix.path, "/usr/bin/env"]
                    + Self.appleBuildEnvironment(prefix: prefix)
                    + ["python", "-m", "pip", "install", "-e", engine.path, "scipy==1.15.2"], environment, log
            )
            progress(.init(message: "Memasang dukungan TIFF & GeoTIFF…"))
            try await run(
                manager,
                [
                    "--no-rc", "run", "--prefix", prefix.path, "python", "-m", "pip", "install", "rasterio",
                    "Pillow",
                ], environment, log)
            try Task.checkCancellation()
            try JSONSerialization.data(
                withJSONObject: [
                    "repository": "https://github.com/OpenSfM/OpenSfM", "commit": source.commit,
                    "pybindCommit": source.pybind ?? "bundled", "installer": "micromamba-" + bootstrapVersion,
                ], options: [.prettyPrinted, .sortedKeys]
            ).write(to: directory.appendingPathComponent("engine.json"), options: .atomic)
            return directory
        #endif
    }

    static func hasBundledPybind(in engine: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: engine.appendingPathComponent(
                "opensfm/src/lib/third_party/pybind11/CMakeLists.txt"
            ).path)
    }

    private static func appleBuildEnvironment(prefix: URL) -> [String] {
        // The conda linker cannot read newer Apple SDK .tbd architectures. Use the Mac's
        // matching compiler/linker after conda activation while keeping all dependency paths.
        let path = prefix.path
        return [
            "CC=/usr/bin/clang", "CXX=/usr/bin/clang++", "LD=/usr/bin/ld",
            "CFLAGS=-O2 -fPIC -I\(path)/include",
            "CXXFLAGS=-O2 -fPIC -stdlib=libc++ -I\(path)/include",
            "LDFLAGS=-L\(path)/lib -Wl,-rpath,\(path)/lib -fuse-ld=/usr/bin/ld",
            "CMAKE_ARGS=-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_LINKER=/usr/bin/ld -DCMAKE_AR=/usr/bin/ar -DCMAKE_RANLIB=/usr/bin/ranlib -DCMAKE_PREFIX_PATH=\(path) -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0",
        ]
    }

    private static func commit(_ value: Any?) throws -> String {
        guard let value = value as? String, value.count == 40,
            value.allSatisfy({ "0123456789abcdef".contains($0) })
        else {
            throw MappingError.invalid("Informasi versi engine tidak valid. Coba lagi nanti.")
        }
        return value
    }

    private func metadata(_ address: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: address)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DroneMapping-EngineInstaller", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch let failure as URLError
            where failure.code != .cancelled
        {
            throw EngineDownloadFailure(url: request.url!, cause: failure)
        }
        try Self.validate(response)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalid("Informasi unduhan engine tidak dapat dibaca.")
        }
        return result
    }

    private func download(
        _ address: String, to destination: URL, message: String,
        progress: @escaping (EngineInstallationProgress) -> Void
    ) async throws {
        progress(.init(message: message))
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 120
        request.setValue("DroneMapping-EngineInstaller", forHTTPHeaderField: "User-Agent")
        let delegate = EngineDownloadProgress(message: message, progress: progress)
        let (temporary, response): (URL, URLResponse)
        do { (temporary, response) = try await session.download(for: request, delegate: delegate) } catch let
            failure as URLError where failure.code != .cancelled
        {
            throw EngineDownloadFailure(url: request.url!, cause: failure)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validate(response)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MappingError.invalid(
                code == 403 || code == 429
                    ? "Layanan unduhan sedang membatasi akses. Coba lagi nanti."
                    : "Unduhan engine gagal (HTTP \(code)). Coba lagi.")
        }
    }

    private func unpack(
        repository: String, commit: String, archiveName: String, destination: URL,
        downloads: URL, environment: [String: String], log: URL,
        progress: @escaping (EngineInstallationProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        let marker = destination.appendingPathComponent(".drone-source-ready")
        if fm.fileExists(atPath: marker.path) { return }
        // Only delete this installer's incomplete source, never a user-selected runtime.
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        let archive = downloads.appendingPathComponent(archiveName + ".zip")
        try await download(
            "https://codeload.github.com/\(repository)/zip/\(commit)", to: archive,
            message: "Mengunduh komponen \(archiveName)…", progress: progress)
        let expanded = downloads.appendingPathComponent(archiveName + "-unpacked")
        if fm.fileExists(atPath: expanded.path) { try fm.removeItem(at: expanded) }
        try fm.createDirectory(at: expanded, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: expanded)
            try? fm.removeItem(at: archive)
        }
        progress(.init(message: "Membuka komponen \(archiveName)…"))
        try await run(
            URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, expanded.path], environment,
            log)
        let source = expanded.appendingPathComponent(archiveName + "-" + commit)
        guard fm.fileExists(atPath: source.path) else {
            throw MappingError.invalid("Arsip engine tidak memiliki struktur yang diharapkan.")
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: destination)
        try Data(commit.utf8).write(to: marker, options: .atomic)
    }

    private func run(_ executable: URL, _ arguments: [String], _ environment: [String: String], _ log: URL)
        async throws
    {
        try Task.checkCancellation()
        try await EngineInstallProcess().run(
            executable, arguments: arguments, environment: environment, log: log)
        try Task.checkCancellation()
    }
}

private final class EngineDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let message: String
    let progress: (EngineInstallationProgress) -> Void
    private var lastUpdate = Date.distantPast
    init(message: String, progress: @escaping (EngineInstallationProgress) -> Void) {
        self.message = message
        self.progress = progress
    }
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {}
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard Date().timeIntervalSince(lastUpdate) > 0.15 || totalBytesWritten == totalBytesExpectedToWrite
        else { return }
        lastUpdate = Date()
        let received = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let total =
            totalBytesExpectedToWrite > 0
            ? ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file) : nil
        progress(
            .init(
                message: message,
                fraction: totalBytesExpectedToWrite > 0
                    ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil,
                detail: total.map { "\(received) dari \($0)" } ?? received))
    }
}
