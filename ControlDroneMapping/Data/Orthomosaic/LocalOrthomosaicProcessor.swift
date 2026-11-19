import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ImageIO

/// Native color preparation followed by the bundled OpenSfM adapter, without a shell or WebODM.
struct LocalOrthomosaicProcessor: OrthomosaicProcessing {
    let worker: URL

    static func python(in runtime: URL) -> URL {
        runtime.appendingPathComponent("environment/bin/python3")
    }
    func check(runtime: URL, cancellation: OrthomosaicCancellation) throws -> String {
        try check(runtime: runtime, cancellation: cancellation, features: false)
    }
    func check(runtime: URL, cancellation: OrthomosaicCancellation, features: Bool) throws -> String {
        var message = ""
        try run(
            runtime: runtime, arguments: [features ? "--check-features" : "--check"],
            cancellation: cancellation, log: nil
        ) { event in
            if event["event"] as? String == "ready" { message = event["message"] as? String ?? "Engine siap" }
        }
        guard !message.isEmpty else { throw MappingError.invalid("Engine tidak memberi respons kesiapan.") }
        return message
    }

    func process(
        project: OrthomosaicProject, folder: URL, runtime: URL,
        cancellation: OrthomosaicCancellation, progress: @escaping (OrthomosaicProgress) -> Void
    ) throws -> OrthomosaicOutput {
        try cancellation.check()
        guard project.colorPreparationReady else {
            throw MappingError.invalid(
                "Pilih dan konfirmasi area gray card, atau hapus gray card untuk mengolah tanpa normalisasi.")
        }
        let reference = project.reference
        let photos = project.mappingPhotos
        guard photos.count >= 3 else {
            throw MappingError.invalid("Diperlukan minimal 3 foto pemetaan yang berbeda.")
        }
        if let time = reference?.capturedAt, let first = photos.compactMap(\.capturedAt).min(), time > first {
            throw MappingError.invalid("Gray card harus diambil sebelum foto pemetaan.")
        }
        if let settings = reference?.settings,
            photos.contains(where: { $0.settings.map { !$0.sameRadiometry(as: settings) } ?? false })
        {
            throw MappingError.invalid(
                "Pengaturan kamera berbeda dari gray card. Pisahkan segmen pengambilan.")
        }
        if let reference, try DatasetStore.hashFile(reference.url) != reference.sha256 {
            throw MappingError.invalid("Berkas gray card berubah. Impor ulang referensi.")
        }
        // Validate the engine before spending time or disk space on full-resolution normalization.
        _ = try check(runtime: runtime, cancellation: cancellation)
        let gain = try reference.map { try RGBPreview(url: $0.url).grayGain(patch: project.patch) }
        let fm = FileManager.default
        let runID = UUID().uuidString
        let staging = folder.appendingPathComponent(".run-" + runID)
        let final = folder.appendingPathComponent("Run_" + runID)
        let images = staging.appendingPathComponent("dataset/images")
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        var committed = false
        defer {
            if !committed {
                try? fm.moveItem(at: staging, to: folder.appendingPathComponent("Unfinished_" + runID))
            }
        }
        let context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        ])
        var entries = [[String: Any]]()
        var overrides = [String: Any]()
        var clipping = 0
        var reused = 0
        var inputBytes: Int64 = 0
        var preparedBytes: Int64 = 0
        let preparationStart = ProcessInfo.processInfo.systemUptime
        for (index, photo) in photos.enumerated() {
            try cancellation.check()
            try autoreleasepool {
                guard try DatasetStore.hashFile(photo.url) == photo.sha256 else {
                    throw MappingError.invalid(
                        "Foto berubah atau transfer belum lengkap: " + photo.url.lastPathComponent)
                }
                let prepared = try Self.preparePhoto(
                    photo.url, stem: images.appendingPathComponent(String(format: "image_%05d", index + 1)),
                    gain: gain, context: context)
                let name = prepared.url.lastPathComponent
                let preparedHash = try DatasetStore.hashFile(prepared.url)
                if prepared.reused {
                    guard preparedHash == photo.sha256 else {
                        throw MappingError.invalid(
                            "Salinan foto tidak lengkap: " + photo.url.lastPathComponent)
                    }
                    reused += 1
                }
                inputBytes += Self.fileBytes(photo.url)
                preparedBytes += Self.fileBytes(prepared.url)
                overrides[name] = Self.exifOverride(photo: photo, properties: prepared.properties)
                if let gain, try RGBPreview(url: photo.url).clipping(gain: gain) > 0.01 { clipping += 1 }
                entries.append([
                    "image": name, "source": photo.url.lastPathComponent,
                    "sourceSHA256": photo.sha256,
                    "preparedSHA256": preparedHash,
                    "preparation": prepared.reused ? "original-srgb-jpeg" : "core-image-srgb-png",
                ])
            }
            progress(
                .init(
                    state: .preparing, fraction: 0.2 * Double(index + 1) / Double(photos.count),
                    message: (gain == nil ? "Menyiapkan foto tanpa normalisasi" : "Normalisasi gray card")
                        + " · \(index + 1)/\(photos.count) foto"))
        }
        try Self.writeJSON(
            [
                "seconds": ProcessInfo.processInfo.systemUptime - preparationStart,
                "originalJPEGs": reused, "convertedPNGs": photos.count - reused,
                "sourceBytes": inputBytes, "preparedBytes": preparedBytes,
            ], to: staging.appendingPathComponent("preparation-performance.json"))
        try Self.writeJSON(overrides, to: staging.appendingPathComponent("dataset/exif_overrides.json"))
        var warnings =
            gain == nil
            ? [
                "Tanpa gray card: tidak ada normalisasi warna atau exposure. JPEG sRGB yang kompatibel dipakai tanpa konversi; format lain dikonversi ke PNG sRGB 8-bit. Hasil bukan reflektansi terkalibrasi."
            ]
            : [
                "Normalisasi RGB memakai satu gray card awal; perubahan pencahayaan selama penerbangan tidak diukur.",
                "Foto dinormalisasi ke PNG sRGB 8-bit tanpa kompresi lossy; hasil bukan reflektansi terkalibrasi.",
            ]
        if reference != nil && (reference?.settings == nil || photos.contains(where: { $0.settings == nil }))
        {
            warnings.append(
                "Impor manual: pastikan gray card diambil di awal dengan exposure dan white balance yang sama."
            )
        }
        if clipping > 0 {
            warnings.append("\(clipping) foto memiliki highlight ≥1% pada preview setelah koreksi.")
        }
        let obliqueCount = photos.filter { $0.attitude?.isOblique == true }.count
        if obliqueCount > 0 {
            warnings.append(
                "\(obliqueCount) foto memiliki kemiringan >12° dari nadir (mis. saat drone berbelok).")
        }
        var request: [String: Any] = [
            "version": 2, "missionID": project.id.uuidString, "name": project.name,
            "total": photos.count, "normalization": gain == nil ? "none" : "gray-card",
            "workingFilesPolicy": project.retainWorkingFiles == true ? "retain" : "remove-after-validation",
            "images": entries, "warnings": warnings,
        ]
        if let reference, let gain {
            request["referenceSHA256"] = reference.sha256
            request["grayPatch"] = [
                "x": project.patch.x, "y": project.patch.y,
                "width": project.patch.width, "height": project.patch.height,
            ]
            request["gains"] = gain.values
        }
        try Self.writeJSON(request, to: staging.appendingPathComponent("request.json"))
        try cancellation.check()
        let log = staging.appendingPathComponent("processing.log")
        try run(runtime: runtime, arguments: ["--run", staging.path], cancellation: cancellation, log: log) {
            event in
            guard event["event"] as? String == "progress",
                let fraction = event["fraction"] as? Double, let message = event["message"] as? String
            else { return }
            progress(
                .init(state: .processing, fraction: 0.2 + min(1, max(0, fraction)) * 0.8, message: message))
        }
        try cancellation.check()
        let result = try JSONDecoder().decode(
            WorkerResult.self, from: Data(contentsOf: staging.appendingPathComponent("result.json")))
        let image = staging.appendingPathComponent("orthomosaic.tif")
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            (properties[kCGImagePropertyPixelWidth as String] as? Int) == result.width,
            (properties[kCGImagePropertyPixelHeight as String] as? Int) == result.height,
            result.width > 0, result.height > 0, result.registered == photos.count
        else {
            throw MappingError.invalid(
                "Engine tidak menghasilkan TIFF lengkap yang valid. Periksa processing.log.")
        }
        try cancellation.check()
        try fm.moveItem(at: staging, to: final)
        committed = true
        if project.retainWorkingFiles != true {
            do {
                try Self.compactDataset(in: final)
            } catch {
                warnings.append(
                    "Hasil valid, tetapi sebagian data kerja belum dapat dibersihkan: "
                        + error.localizedDescription)
            }
        }
        for warning in result.warnings where !warnings.contains(warning) { warnings.append(warning) }
        return OrthomosaicOutput(
            folder: final, image: final.appendingPathComponent("orthomosaic.tif"),
            georeferenced: result.georeferenced, width: result.width, height: result.height,
            registered: result.registered, total: photos.count, warnings: warnings)
    }

    private struct WorkerResult: Decodable {
        var georeferenced: Bool
        var width: Int
        var height: Int
        var registered: Int
        var warnings: [String]
    }

    private func run(
        runtime: URL, arguments: [String], cancellation: OrthomosaicCancellation,
        log: URL?, event: ([String: Any]) -> Void
    ) throws {
        let usesEmbeddedEngine = runtime == BundledOrthomosaicEngine.embeddedDirectory
        if usesEmbeddedEngine {
            try BundledOrthomosaicEngine.validateEmbedded()
        } else if BundledOrthomosaicEngine.isSandboxed {
            throw MappingError.invalid(
                "Engine eksternal tidak dapat dijalankan dalam sandbox macOS. Gunakan build aplikasi yang menyertakan engine bawaan."
            )
        }
        let python = Self.python(in: runtime)
        guard FileManager.default.fileExists(atPath: worker.path) else {
            throw MappingError.invalid(
                "Berkas pengolah tidak ditemukan di aplikasi. Build ulang aplikasi dengan orthomosaic_worker.py di Resources."
            )
        }
        guard FileManager.default.fileExists(atPath: python.path) else {
            throw MappingError.invalid(
                "Python engine tidak ditemukan atau tidak dapat diakses: " + python.path)
        }
        let process = Process()
        let helper = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("OrthomosaicPython")
        let embedded = usesEmbeddedEngine ? helper : nil
        process.executableURL = embedded ?? URL(fileURLWithPath: "/usr/bin/env")
        process.arguments =
            (embedded == nil ? [python.path] : [])
            + ["-u", worker.path, "--runtime", runtime.path] + arguments
        process.currentDirectoryURL = runtime
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PROJ_NETWORK"] = "OFF"
        environment["OMP_NUM_THREADS"] = "2"
        environment["OPENBLAS_NUM_THREADS"] = "2"
        environment["CONDA_PREFIX"] = runtime.appendingPathComponent("environment").path
        if embedded != nil {
            environment["PYTHONHOME"] = runtime.appendingPathComponent("environment").path
        } else {
            environment.removeValue(forKey: "PYTHONHOME")
        }
        environment["PYTHONNOUSERSITE"] = "1"
        environment.removeValue(forKey: "PYTHONPATH")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var handle: FileHandle?
        if let log {
            FileManager.default.createFile(atPath: log.path, contents: nil)
            handle = try FileHandle(forWritingTo: log)
        }
        defer { try? handle?.close() }
        try cancellation.launch(process)
        defer {
            if process.isRunning {
                cancellation.cancel()
                process.waitUntilExit()
            }
        }
        var pending = Data()
        var diagnostics = Data()
        var failure: String?
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            try handle?.write(contentsOf: chunk)
            diagnostics.append(chunk)
            if diagnostics.count > 4096 { diagnostics.removeFirst(diagnostics.count - 4096) }
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<end], as: UTF8.self)
                pending.removeSubrange(...end)
                let prefix = "DRONEMAP_EVENT "
                if line.hasPrefix(prefix), let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
                    let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    if value["event"] as? String == "error" { failure = value["message"] as? String }
                    event(value)
                }
            }
            if pending.count > 1_048_576 { pending.removeAll() }
        }
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: diagnostics, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MappingError.invalid(
                failure
                    ?? "Engine berhenti (\(process.terminationStatus)). "
                    + (detail.isEmpty ? "Periksa folder engine dan processing.log." : detail)
            )
        }
    }

    struct PreparedPhoto {
        let url: URL
        let properties: [String: Any]
        let reused: Bool
    }

    static func preparePhoto(
        _ input: URL, stem: URL, gain: ColorGain?, context: CIContext,
        allowOriginalJPEG: Bool = true
    ) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MappingError.invalid("Foto tidak dapat didekode: " + input.lastPathComponent) }
        // OpenCV does not color-manage ICC profiles. Only bypass Core Image for
        // ordinary 8-bit sRGB JPEG; wide-gamut, HDR and unknown profiles stay managed.
        if allowOriginalJPEG, gain == nil,
            CGImageSourceGetCount(source) == 1,
            CGImageSourceGetType(source) as String? == "public.jpeg",
            cg.bitsPerComponent == 8, cg.colorSpace?.model == .rgb,
            cg.colorSpace?.name == CGColorSpace.sRGB
        {
            let output = stem.appendingPathExtension("jpg")
            // APFS clones share unchanged blocks but never alias mutable source bytes.
            // Other filesystems use a regular copy; neither path alters the input.
            if clonefile(input.path, output.path, 0) != 0 {
                try FileManager.default.copyItem(at: input, to: output)
            }
            return PreparedPhoto(url: output, properties: properties, reused: true)
        }
        let output = stem.appendingPathExtension("png")
        try writePreparedImage(cg, to: output, gain: gain, context: context)
        return PreparedPhoto(url: output, properties: properties, reused: false)
    }

    private static func fileBytes(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Called only after final output validation and publication. Failed/cancelled runs keep their workspace.
    static func compactDataset(in run: URL) throws {
        let fm = FileManager.default
        let dataset = run.appendingPathComponent("dataset")
        let attributes = try dataset.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard attributes.isSymbolicLink == false, attributes.isDirectory == true else {
            throw MappingError.invalid("Folder data kerja tidak valid; pembersihan dilewati.")
        }
        let diagnostics = run.appendingPathComponent("diagnostics")
        try fm.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        for name in [
            "config.yaml", "exif_overrides.json", "camera_models.json", "reconstruction.json",
            "reference_lla.json", "profile.log", "reports",
        ] {
            let source = dataset.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: diagnostics.appendingPathComponent(name))
            }
        }
        try fm.removeItem(at: dataset)
    }

    private static func writePreparedImage(
        _ cg: CGImage, to output: URL, gain: ColorGain?, context: CIContext
    )
        throws
    {
        var image = CIImage(cgImage: cg)
        if let gain {
            image = image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: gain.red, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: gain.green, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: gain.blue, w: 0),
                ])
        }
        guard
            let result = context.createCGImage(
                image, from: image.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
            let destination = CGImageDestinationCreateWithURL(
                output as CFURL, "public.png" as CFString, 1, nil)
        else { throw MappingError.invalid("Gagal menyiapkan foto untuk pengolahan.") }
        // Keep physical pixel order; OpenSfM receives the original EXIF orientation through overrides.
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MappingError.invalid("Gagal menyimpan foto untuk pengolahan.")
        }
    }

    static func exifOverride(photo: OrthomosaicPhoto, properties: [String: Any]) -> [String: Any] {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let focal35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.doubleValue
        var value: [String: Any] = [
            "width": width, "height": height,
            "orientation": properties[kCGImagePropertyOrientation as String] as? Int ?? 1,
            "make": tiff[kCGImagePropertyTIFFMake as String] as? String ?? "unknown",
            "model": tiff[kCGImagePropertyTIFFModel as String] as? String ?? "unknown",
        ]
        if let focal35, focal35 > 0 { value["focal_ratio"] = focal35 / 36 }
        if let time = photo.capturedAt { value["capture_time"] = time.timeIntervalSince1970 }
        if let geo = photo.location, let age = photo.locationAge, age.isFinite, (0...10).contains(age),
            validGPS(geo.latitude, geo.longitude), geo.horizontalAccuracy.isFinite,
            geo.horizontalAccuracy >= 0
        {
            var gps: [String: Any] = [
                "latitude": geo.latitude, "longitude": geo.longitude, "dop": max(1, geo.horizontalAccuracy),
            ]
            if geo.altitudeMSL.isFinite, geo.verticalAccuracy.isFinite, geo.verticalAccuracy >= 0 {
                gps["altitude"] = geo.altitudeMSL
            }
            value["gps"] = gps
        } else if photo.settings == nil,
            let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
            let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
            let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue
        {
            let latitude = gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "S" ? -lat : lat
            let longitude = gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W" ? -lon : lon
            if validGPS(latitude, longitude) {
                let rawDop =
                    (gps[kCGImagePropertyGPSHPositioningError as String] as? NSNumber)?.doubleValue
                    ?? (gps[kCGImagePropertyGPSDOP as String] as? NSNumber)?.doubleValue
                let dop = (rawDop != nil && rawDop!.isFinite && rawDop! > 0) ? max(1.0, rawDop!) : 15.0
                var location: [String: Any] = ["latitude": latitude, "longitude": longitude, "dop": dop]
                if let altitude = (gps[kCGImagePropertyGPSAltitude as String] as? NSNumber)?.doubleValue,
                    altitude.isFinite
                {
                    location["altitude"] =
                        (gps[kCGImagePropertyGPSAltitudeRef as String] as? NSNumber)?.intValue == 1
                        ? -altitude : altitude
                }
                value["gps"] = location
            }
        }
        return value
    }
    private static func validGPS(_ lat: Double, _ lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
    private static func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url, options: .atomic)
    }
}
