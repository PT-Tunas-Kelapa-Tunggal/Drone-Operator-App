import CoreGraphics
import CoreImage
import Foundation
import ImageIO

private final class GatedEngineInstaller: OrthomosaicEngineInstalling {
    let directory: URL
    var calls = 0
    var released = false
    var failure: Error?
    init(directory: URL) { self.directory = directory }
    func install(progress: @escaping (EngineInstallationProgress) -> Void) async throws -> URL {
        await MainActor.run { calls += 1 }
        progress(.init(message: "Installer fixture", fraction: 0.25))
        while await MainActor.run(body: { !released }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if let failure = await MainActor.run(body: { failure }) { throw failure }
        return directory
    }
}

private final class GatedOrthomosaicProcessor: OrthomosaicProcessing, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    let output: OrthomosaicOutput
    init(output: OrthomosaicOutput) { self.output = output }
    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func check(runtime: URL, cancellation: OrthomosaicCancellation) throws -> String { "Test engine" }
    func process(
        project: OrthomosaicProject, folder: URL, runtime: URL,
        cancellation: OrthomosaicCancellation, progress: @escaping (OrthomosaicProgress) -> Void
    ) throws -> OrthomosaicOutput {
        lock.lock()
        count += 1
        lock.unlock()
        progress(.init(state: .processing, fraction: 0.5, message: "Test in progress"))
        while gate.wait(timeout: .now() + 0.02) == .timedOut { try cancellation.check() }
        try cancellation.check()
        return output
    }
}

@main enum OrthomosaicTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            count += 1
        }
        func rejects(_ label: String, _ work: () throws -> Void) {
            do {
                try work()
                preconditionFailure(label)
            } catch { count += 1 }
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orthomosaic-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func image(
            _ url: URL, linear: [Double], type: String = "public.png",
            colorSpace: CFString = CGColorSpace.sRGB, orientation: Int = 1
        ) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let width = 256
            let height = 192
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for index in 0..<(width * height) {
                for channel in 0..<3 {
                    let value = linear[channel]
                    let encoded = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
                    bytes[index * 4 + channel] = UInt8((max(0, min(1, encoded)) * 255).rounded())
                }
            }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let cg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: colorSpace)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
            CGImageDestinationAddImage(
                destination, cg,
                [
                    kCGImagePropertyExifDictionary: [kCGImagePropertyExifFocalLenIn35mmFilm: 24],
                    kCGImagePropertyOrientation: orientation,
                ] as CFDictionary
            )
            precondition(CGImageDestinationFinalize(destination))
        }
        let a = root.appendingPathComponent("a/same.png")
        let b = root.appendingPathComponent("b/same.png")
        let c = root.appendingPathComponent("c/photo.png")
        let card = root.appendingPathComponent("card.png")
        try image(a, linear: [0.04, 0.06, 0.08])
        try image(b, linear: [0.08, 0.09, 0.10])
        try image(c, linear: [0.12, 0.13, 0.14])
        try image(card, linear: [0.09, 0.09, 0.09])
        let repository = FileOrthomosaicRepository(root: root.appendingPathComponent("projects"))
        var first = OrthomosaicProject(id: UUID(), name: "Misi A", fromMission: false)
        first = try repository.importPhotos([a, b, c, a], into: first, reference: false)
        check(
            first.photos.count == 3,
            "Deduplicate bytes while retaining different images with identical filenames")
        check(Set(first.photos.map(\.url)).count == 3, "Imports have unique paths")
        let originalAHash = try DatasetStore.hashFile(a)
        check(
            try DatasetStore.hashFile(first.photos[0].url) == originalAHash,
            "Manual imports preserve original bytes")
        first = try repository.importPhotos([card], into: first, reference: true)
        check(
            first.references.count == 1 && first.mappingPhotos.count == 3, "Separate calibration from mapping"
        )
        var selectedMapping = try repository.importPhotos([a], into: first, reference: true)
        check(
            selectedMapping.mappingPhotos.count == 2,
            "A gray-card image already in mapping is excluded by content hash")
        first = try repository.importPhotos([card], into: first, reference: true)
        // Duplicate reference selection must select the intended reference, not the most recently appended one.
        first.referenceID = first.references.first { $0.sha256 == (try? DatasetStore.hashFile(card)) }?.id
        first.confirmed = true
        first.retainWorkingFiles = true
        let geo = GeoSample(
            latitude: -6, longitude: 106, altitudeMSL: 80, horizontalAccuracy: 5,
            verticalAccuracy: 8, timestamp: Date())
        first.photos[0].location = geo
        first.photos[0].locationAge = 0.5
        first.photos[0].settings = CameraSettings()
        first.photos[1].location = geo
        first.photos[1].locationAge = 30
        first.photos[1].settings = CameraSettings()
        try repository.save(first)
        let second = OrthomosaicProject(id: UUID(), name: "Misi B", fromMission: false)
        _ = try repository.importPhotos([a], into: second, reference: false)
        check(try repository.load().count == 2, "Mission projects persist independently")
        let invalid = root.appendingPathComponent("not-image.jpg")
        try Data("not an image".utf8).write(to: invalid)
        rejects("Reject invalid image and roll back the entire import") {
            _ = try repository.importPhotos([b, invalid], into: second, reference: false)
        }
        check(
            try repository.load().first { $0.id == second.id }?.photos.count == 1,
            "Failed import leaves previous manifest intact")
        var interrupted = second
        interrupted.state = .processing
        try repository.save(interrupted)
        check(
            try repository.load().first { $0.id == second.id }?.state == .failed,
            "Restart marks an interrupted run as failed")

        // Contract fixture: only tests process I/O and native preparation, never simulates an actual SfM result for the app.
        let runtime = root.appendingPathComponent("runtime")
        try fm.createDirectory(
            at: runtime.appendingPathComponent("environment/bin"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: LocalOrthomosaicProcessor.python(in: runtime),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3"))
        try image(
            runtime.appendingPathComponent("fixture.tif"), linear: [0.1, 0.2, 0.3], type: "public.tiff")
        let worker = root.appendingPathComponent("contract_fixture.py")
        try """
        import json, sys, shutil
        from pathlib import Path
        def emit(**value):
            print('DRONEMAP_EVENT ' + json.dumps(value), flush=True)
        runtime = Path(sys.argv[sys.argv.index('--runtime') + 1])
        if '--check' in sys.argv:
            emit(event='ready', message='Contract fixture only')
        else:
            folder = Path(sys.argv[sys.argv.index('--run') + 1])
            request = json.loads((folder / 'request.json').read_text())
            emit(event='progress', fraction=0.5, message='Contract test')
            mode = (runtime / 'mode').read_text() if (runtime / 'mode').exists() else 'ok'
            if mode == 'error':
                emit(event='error', message='Synthetic engine failure')
                sys.exit(2)
            shutil.copyfile(runtime / 'fixture.tif', folder / 'orthomosaic.tif')
            result = dict(georeferenced=False, width=256, height=192,
                          registered=len(request['images']) - (1 if mode == 'partial' else 0), warnings=[])
            (folder / 'result.json').write_text(json.dumps(result))
        """.write(to: worker, atomically: true, encoding: .utf8)
        let processor = LocalOrthomosaicProcessor(worker: worker)
        let directory = repository.projectDirectory(first.id)
        check(
            try processor.check(runtime: runtime, cancellation: OrthomosaicCancellation())
                == "Contract fixture only", "Runtime checks require a structured readiness response")
        var progress = [OrthomosaicProgress]()
        let output = try processor.process(
            project: first, folder: directory, runtime: runtime,
            cancellation: OrthomosaicCancellation()
        ) { progress.append($0) }
        check(
            fm.fileExists(atPath: output.image.path) && !output.georeferenced,
            "Publish a validated local TIFF")
        check(output.registered == 3 && output.total == 3, "All input images must register")
        check(
            progress.contains { $0.state == .preparing } && progress.contains { $0.state == .processing },
            "Preparation and engine progress are forwarded")
        let normalized = try RGBPreview(
            url: output.folder.appendingPathComponent("dataset/images/image_00001.png"))
        let grayGain = try RGBPreview(url: card).grayGain(patch: GrayPatch())
        let raw = try RGBPreview(url: a).rgb(x: 100, y: 100)
        let rgb = normalized.rgb(x: 100, y: 100)
        check(
            (0..<3).allSatisfy { abs(rgb[$0] - raw[$0] * grayGain.values[$0]) < 0.006 },
            "Normalization applies gray gains in linear RGB")
        check(try DatasetStore.hashFile(a) == originalAHash, "Processing never modifies source photos")
        let request =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: output.folder.appendingPathComponent("request.json")))
            as! [String: Any]
        check((request["images"] as? [[String: Any]])?.count == 3, "Request excludes all gray cards")
        check((request["gains"] as? [Double])?.count == 3, "Color gains are auditable")
        let overrideData = try Data(
            contentsOf: output.folder.appendingPathComponent("dataset/exif_overrides.json"))
        let overrides = try JSONSerialization.jsonObject(with: overrideData) as! [String: [String: Any]]
        check(
            overrides.count == 3 && overrides.values.allSatisfy { $0["width"] as? Int == 256 },
            "Normalized inputs retain camera dimensions")
        check(
            (overrides["image_00001.png"]?["gps"] as? [String: Any])?["latitude"] as? Double == -6,
            "Valid sidecar GPS reaches OpenSfM")
        check(
            overrides["image_00002.png"]?["gps"] == nil && overrides["image_00003.png"]?["gps"] == nil,
            "Stale or missing GPS never becomes a fabricated geolocation")
        var noCard = first
        noCard.references = []
        noCard.referenceID = nil
        noCard.confirmed = false
        check(noCard.colorPreparationReady, "No gray card requires no color confirmation")
        let uncorrected = try processor.process(
            project: noCard, folder: directory, runtime: runtime,
            cancellation: OrthomosaicCancellation()
        ) { _ in }
        let uncorrectedPreview = try RGBPreview(
            url: uncorrected.folder.appendingPathComponent("dataset/images/image_00001.png"))
        let uncorrectedRGB = uncorrectedPreview.rgb(x: 100, y: 100)
        check(
            (0..<3).allSatisfy { abs(uncorrectedRGB[$0] - raw[$0]) < 0.006 },
            "Without gray card, preparation does not apply exposure or RGB gains")
        let uncorrectedRequest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: uncorrected.folder.appendingPathComponent("request.json")))
            as! [String: Any]
        check(
            uncorrectedRequest["normalization"] as? String == "none"
                && uncorrectedRequest["gains"] == nil && uncorrectedRequest["referenceSHA256"] == nil,
            "Report explicitly records no normalization and no invented reference")
        // Actual ImageIO/Core Image paths: compatible JPEGs remain byte-identical,
        // while wide gamut and gray-card correction still use color-managed PNG.
        let jpeg = root.appendingPathComponent("photo.jpg")
        let p3 = root.appendingPathComponent("wide-gamut.jpg")
        try image(jpeg, linear: [0.1, 0.2, 0.3], type: "public.jpeg", orientation: 6)
        try image(p3, linear: [0.1, 0.2, 0.3], type: "public.jpeg", colorSpace: CGColorSpace.displayP3)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        ])
        let copied = try LocalOrthomosaicProcessor.preparePhoto(
            jpeg, stem: root.appendingPathComponent("copied"), gain: nil, context: context)
        check(copied.reused && copied.url.pathExtension == "jpg", "sRGB JPEG skips PNG encoding")
        check(
            copied.properties[kCGImagePropertyOrientation as String] as? Int == 6,
            "Direct JPEG retains orientation metadata without rotating pixels")
        check(
            try DatasetStore.hashFile(copied.url) == DatasetStore.hashFile(jpeg),
            "Direct JPEG preparation is byte-identical")
        let correctedJPEG = try LocalOrthomosaicProcessor.preparePhoto(
            jpeg, stem: root.appendingPathComponent("corrected"), gain: grayGain, context: context)
        check(
            !correctedJPEG.reused && correctedJPEG.url.pathExtension == "png",
            "Gray card always applies color correction")
        let convertedP3 = try LocalOrthomosaicProcessor.preparePhoto(
            p3, stem: root.appendingPathComponent("converted-p3"), gain: nil, context: context)
        check(
            !convertedP3.reused && convertedP3.url.pathExtension == "png",
            "Wide-gamut JPEG retains color-managed conversion")
        let jpegHash = try DatasetStore.hashFile(jpeg)
        try Data("changed clone".utf8).write(to: copied.url)
        check(try DatasetStore.hashFile(jpeg) == jpegHash, "Editing a prepared copy cannot modify its source")

        var compact = noCard
        compact.retainWorkingFiles = nil
        let compactOutput = try processor.process(
            project: compact, folder: root.appendingPathComponent("compact-runs"), runtime: runtime,
            cancellation: OrthomosaicCancellation()
        ) { _ in }
        check(
            !fm.fileExists(atPath: compactOutput.folder.appendingPathComponent("dataset").path),
            "Default successful run discards bulky intermediates")
        check(
            fm.fileExists(atPath: compactOutput.image.path)
                && fm.fileExists(
                    atPath: compactOutput.folder.appendingPathComponent("diagnostics/exif_overrides.json")
                        .path)
                && fm.fileExists(
                    atPath: compactOutput.folder.appendingPathComponent("preparation-performance.json").path),
            "Compaction preserves final image, metadata, and performance report")
        let legacyData = try JSONEncoder().encode(compact)
        check(
            try JSONDecoder().decode(OrthomosaicProject.self, from: legacyData).retainWorkingFiles == nil,
            "Projects without a retention setting remain readable")
        let linkedRun = root.appendingPathComponent("linked-run")
        try fm.createDirectory(at: linkedRun, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: linkedRun.appendingPathComponent("dataset"), withDestinationURL: directory)
        rejects("Cleanup refuses an indirect dataset folder") {
            try LocalOrthomosaicProcessor.compactDataset(in: linkedRun)
        }
        check(fm.fileExists(atPath: output.image.path), "Rejected cleanup leaves other runs intact")
        var missingReference = first
        missingReference.referenceID = UUID()
        check(
            !missingReference.colorPreparationReady,
            "Missing selected gray card must not silently disable normalization")
        var unchecked = first
        unchecked.confirmed = false
        rejects("Gray patch confirmation is mandatory") {
            _ = try processor.process(
                project: unchecked, folder: directory, runtime: runtime,
                cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        selectedMapping.confirmed = true
        rejects("Require at least three distinct mapping photos after gray exclusion") {
            _ = try processor.process(
                project: selectedMapping, folder: directory, runtime: runtime,
                cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        var settingsMismatch = first
        settingsMismatch.references[0].settings = CameraSettings()
        settingsMismatch.referenceID = settingsMismatch.references[0].id
        settingsMismatch.photos[0].settings = CameraSettings(iso: 800)
        rejects("Reject exposure changes relative to reference") {
            _ = try processor.process(
                project: settingsMismatch, folder: directory, runtime: runtime,
                cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        try "partial".write(to: runtime.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        rejects("Reject a worker result with omitted photos") {
            _ = try processor.process(
                project: compact, folder: directory, runtime: runtime, cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        check(fm.fileExists(atPath: output.image.path), "Failed rerun preserves an earlier successful result")
        try "error".write(to: runtime.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        rejects("Propagate worker errors without publishing a result") {
            _ = try processor.process(
                project: compact, folder: directory, runtime: runtime, cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        let folders = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        check(
            folders.filter { $0.lastPathComponent.hasPrefix("Run_") }.count == 2,
            "Publish only validated successful runs")
        check(
            folders.filter { $0.lastPathComponent.hasPrefix("Unfinished_") }.count == 2,
            "Retain diagnostic logs of failed runs")
        check(
            folders.filter { $0.lastPathComponent.hasPrefix("Unfinished_") }.allSatisfy {
                fm.fileExists(atPath: $0.appendingPathComponent("dataset/images").path)
            }, "Failed runs retain working images for diagnosis")
        let token = OrthomosaicCancellation()
        let sleep = Process()
        sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleep.arguments = ["30"]
        try token.launch(sleep)
        token.cancel()
        sleep.waitUntilExit()
        check(!sleep.isRunning, "Cancellation terminates an active worker")
        rejects("Cancellation is visible to preparation") { try token.check() }
        rejects("A cancelled token cannot launch another worker") { try token.launch(Process()) }
        let stubborn = Process()
        let ready = Pipe()
        stubborn.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        stubborn.arguments = [
            "-u", "-c",
            "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('ready'); time.sleep(30)",
        ]
        stubborn.standardOutput = ready
        let bounded = OrthomosaicCancellation()
        try bounded.launch(stubborn)
        _ = ready.fileHandleForReading.availableData
        let stoppedAt = Date()
        bounded.cancel()
        stubborn.waitUntilExit()
        check(
            Date().timeIntervalSince(stoppedAt) < 5,
            "Cancellation is bounded even when a native call ignores SIGTERM")
        // The editor can close or switch missions without losing or misrouting a background run.
        let suite = "orthomosaic-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gated = GatedOrthomosaicProcessor(output: output)
        let manager = OrthomosaicViewModel(
            repository: repository, service: gated,
            datasets: DatasetStore(root: root.appendingPathComponent("datasets")),
            runtimeAccess: OrthomosaicRuntimeAccess(defaults: defaults))
        func waitFor(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(10)
            while !predicate() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(predicate(), "Background operation timed out")
        }
        let installer = GatedEngineInstaller(directory: runtime)
        let setup = OrthomosaicViewModel(
            repository: repository, service: gated,
            datasets: DatasetStore(root: root.appendingPathComponent("setup-datasets")),
            runtimeAccess: OrthomosaicRuntimeAccess(defaults: defaults), installer: installer)
        setup.open(first.id)
        setup.installEngine()
        setup.installEngine()
        waitFor { installer.calls == 1 && setup.engineProgress?.fraction == 0.25 }
        check(!setup.busy && !setup.canStart, "Installation allows editing while processing remains disabled")
        setup.showingEditor = false
        setup.open(second.id)
        setup.cancelEngineInstallation()
        waitFor { !setup.engineInstalling }
        check(
            !setup.engineReady && !setup.engineInstallFailed,
            "Cancellation never marks an engine ready or reports a failure")
        installer.failure = URLError(.cannotFindHost)
        installer.released = true
        setup.installEngine()
        waitFor { !setup.engineInstalling }
        check(
            setup.engineInstallFailed && !setup.engineReady,
            "Download failure remains retryable without enabling processing")
        check(setup.engineMessage.contains("koneksi internet"), "Network failures explain how to retry")
        let failedDownload = EngineDownloadFailure(
            url: URL(string: "https://github.com/example/engine")!, cause: URLError(.cannotFindHost))
        check(
            failedDownload.localizedDescription.contains("github.com")
                && failedDownload.localizedDescription.contains("DNS"),
            "Download errors identify the host and DNS failure instead of blaming generic connectivity")
        let offlineDownload = EngineDownloadFailure(
            url: URL(string: "https://github.com/example/engine")!, cause: URLError(.notConnectedToInternet))
        check(
            !offlineDownload.localizedDescription.contains("DNS"),
            "Offline errors stay distinct from DNS failures")
        let unsupportedPrefix = root.appendingPathComponent("Application Support/Engine")
        var prefixCheckFinished = false
        var prefixRejected = false
        Task { @MainActor in
            do {
                _ = try await LocalOrthomosaicEngineInstaller(directory: unsupportedPrefix).install { _ in }
            } catch { prefixRejected = error.localizedDescription.contains("spasi") }
            prefixCheckFinished = true
        }
        waitFor { prefixCheckFinished }
        check(
            prefixRejected && !fm.fileExists(atPath: unsupportedPrefix.path),
            "Unsupported compiler prefixes fail before any download or environment creation")
        let archive = root.appendingPathComponent("untrusted-engine.zip")
        let manifest = root.appendingPathComponent("untrusted-engine.json")
        try Data("not an engine".utf8).write(to: archive)
        var packageMetadata: [String: Any] = [
            "formatVersion": 1, "sha256": String(repeating: "0", count: 64),
            "folder": "OpenSfM-engine", "architecture": "arm64",
            "teamIdentifier": "ABCDEFGHIJ",
            "pythonIdentifier": "com.hata.ControlDroneMapping.engine.python",
        ]
        try JSONSerialization.data(withJSONObject: packageMetadata).write(to: manifest)
        let packageTarget = root.appendingPathComponent("rejected-package")
        var packageCheckFinished = false
        var packageRejected = false
        Task { @MainActor in
            do {
                try await BundledOrthomosaicEngine(archive: archive, manifest: manifest).install(
                    at: packageTarget, log: packageTarget.appendingPathComponent("installation.log")
                ) { _ in }
            } catch { packageRejected = error.localizedDescription.contains("pemeriksaan") }
            packageCheckFinished = true
        }
        waitFor { packageCheckFinished }
        check(
            packageRejected && !fm.fileExists(atPath: packageTarget.path),
            "A corrupt package is rejected before extraction or changing an installed runtime")
        packageMetadata["sha256"] = try DatasetStore.hashFile(archive)
        try JSONSerialization.data(withJSONObject: packageMetadata).write(to: manifest)
        packageCheckFinished = false
        packageRejected = false
        Task { @MainActor in
            do {
                try await BundledOrthomosaicEngine(archive: archive, manifest: manifest).install(
                    at: packageTarget, log: packageTarget.appendingPathComponent("installation.log")
                ) { _ in }
            } catch { packageRejected = error.localizedDescription.contains("pembuat aplikasi yang sama") }
            packageCheckFinished = true
        }
        waitFor { packageCheckFinished }
        check(
            packageRejected && !fm.fileExists(atPath: packageTarget.path),
            "A package signed by another publisher is rejected before extraction")
        installer.failure = nil
        setup.installEngine()
        waitFor { !setup.engineInstalling }
        check(
            setup.engineReady && installer.calls == 3,
            "Retry automatically validates and selects the installed runtime")
        check(
            setup.selectedID == second.id,
            "Background setup preserves the selected mission after closing and reopening")
        let invalidSetup = OrthomosaicViewModel(
            repository: repository,
            service: LocalOrthomosaicProcessor(worker: root.appendingPathComponent("missing-worker.py")),
            datasets: DatasetStore(root: root.appendingPathComponent("invalid-setup-datasets")),
            runtimeAccess: OrthomosaicRuntimeAccess(defaults: defaults), installer: installer)
        invalidSetup.installEngine()
        waitFor { !invalidSetup.engineInstalling }
        check(
            invalidSetup.engineInstallFailed && !invalidSetup.engineReady,
            "Finishing the download does not enable an engine that fails its runtime check")
        rejects("Reject HTTP error pages instead of treating them as an engine archive") {
            try LocalOrthomosaicEngineInstaller.validate(
                HTTPURLResponse(
                    url: URL(string: "https://example.com/engine")!, statusCode: 404,
                    httpVersion: nil, headerFields: nil)!)
        }
        // Installer commands run as groups so cancellation also stops compiler/package children.
        let processLog = root.appendingPathComponent("installer.log")
        fm.createFile(atPath: processLog.path, contents: nil)
        let heartbeat = root.appendingPathComponent("child-heartbeat")
        let childScript = root.appendingPathComponent("installer-child.py")
        try """
        import signal, subprocess, sys, time
        from pathlib import Path
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if len(sys.argv) == 2:
            subprocess.Popen([sys.executable, __file__, sys.argv[1], 'child'])
            while True: time.sleep(1)
        while True:
            Path(sys.argv[1]).write_text(str(time.time()))
            time.sleep(0.02)
        """.write(to: childScript, atomically: true, encoding: .utf8)
        var installProcessDone = false
        var installProcessCancelled = false
        let installProcessTask = Task { @MainActor in
            do {
                try await EngineInstallProcess().run(
                    URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: [childScript.path, heartbeat.path],
                    environment: ProcessInfo.processInfo.environment, log: processLog)
            } catch { installProcessCancelled = error is CancellationError }
            installProcessDone = true
        }
        waitFor { fm.fileExists(atPath: heartbeat.path) }
        installProcessTask.cancel()
        waitFor { installProcessDone }
        let lastBeat = try Data(contentsOf: heartbeat)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let nextBeat = try Data(contentsOf: heartbeat)
        check(
            installProcessCancelled && nextBeat == lastBeat,
            "Cancelling installer stops a child that ignores SIGTERM before allowing retry")
        manager.checkRuntime(runtime, remember: false)
        waitFor { !manager.busy }
        check(manager.engineReady, "Engine readiness enables processing")
        manager.open(first.id)
        manager.setConfirmed(false)
        check(!manager.canStart, "Uploaded gray card still requires confirmation")
        manager.removeGrayCard()
        check(
            manager.canStart && manager.selected?.references.isEmpty == true,
            "Removing gray card enables processing without normalization")
        manager.open(first.id)
        manager.start()
        manager.start()
        waitFor { gated.calls == 1 }
        manager.showingEditor = false
        manager.open(second.id)
        gated.gate.signal()
        waitFor { !manager.busy }
        check(gated.calls == 1, "Reject duplicate starts while a run is active")
        check(
            manager.project(first.id)?.state == .completed
                && manager.project(second.id)?.outputs.isEmpty == true,
            "A run completes into its original mission even after switching editors")
        check(manager.project(first.id)?.outputs.count == 1, "Completed output history persists")
        manager.open(first.id)
        manager.start()
        waitFor { gated.calls == 2 }
        manager.cancel()
        waitFor { !manager.busy }
        check(
            manager.project(first.id)?.state == .cancelled && manager.project(first.id)?.outputs.count == 1,
            "Cancellation preserves prior results and updates only its mission")
        let localMissionID = UUID()
        let cameraDataset = MissionRecord(plan: MissionPlan(name: "Misi dari Mac"))
        manager.importPhotos([a, b, c], mission: cameraDataset, projectID: localMissionID)
        waitFor { !manager.busy }
        check(
            manager.selectedID == localMissionID && manager.project(cameraDataset.id) == nil,
            "Manual imports use the stable Mac mission identity rather than a camera dataset ID")
        manager.prepareMission(cameraDataset, projectID: localMissionID)
        check(
            manager.selectedID == localMissionID && manager.project(localMissionID)?.mappingPhotos.count == 3,
            "Opening the same linked mission reuses its project")
        let sourceBefore = first.photos[0].url
        try Data("changed".utf8).write(to: sourceBefore)
        rejects("Reject corrupted or changed source bytes before using them") {
            _ = try processor.process(
                project: first, folder: directory, runtime: runtime, cancellation: OrthomosaicCancellation()
            ) { _ in }
        }
        print(
            "PASS: \(count) orthomosaic assertions (native image preparation and a test-only worker contract; no SfM accuracy claim)"
        )
    }
}
