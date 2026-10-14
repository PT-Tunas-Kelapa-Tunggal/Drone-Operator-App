import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision
import simd

struct WebODMExporter: WebODMExportService {
    let store: any DatasetRepository
    func photos(_ id: UUID) throws -> [ExportPhoto] {
        try store.captureIndexes(id).map { index in
            let capture = try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: index))
            guard capture.missionID == id, let name = capture.files.first(where: { $0.hasSuffix(".jpg") })
            else { throw MappingError.invalid("Index foto tidak valid") }
            let base = capture.layoutVersion == 2 ? store.directory(id) : index.deletingLastPathComponent()
            return ExportPhoto(capture: capture, url: base.appendingPathComponent(name))
        }.sorted { $0.capture.requestedAt < $1.capture.requestedAt }
    }
    func export(
        id: UUID, referenceID: UUID?, patch: GrayPatch, confirmed: Bool, overlap: Bool,
        progress: (Int, Int) -> Void = { _, _ in }
    ) throws -> ExportResult {
        try store.verify(id)
        let all = try photos(id)
        let mapping = all.filter { $0.capture.kind == "mapping" }
        guard !mapping.isEmpty else {
            throw MappingError.invalid(
                "Belum ada foto pemetaan. Foto uji dan gray card tidak bisa menjadi dataset orthomosaic.")
        }
        var base = ColorGain.identity
        var reference: ExportPhoto?
        if let referenceID {
            guard confirmed,
                let selected = all.first(where: {
                    $0.id == referenceID && $0.capture.kind == "calibration-before"
                })
            else { throw MappingError.invalid("Pilih dan konfirmasi kartu fisik sebelum penerbangan") }
            guard selected.capture.requestedAt <= mapping[0].capture.requestedAt else {
                throw MappingError.invalid(
                    "Referensi dipotret setelah foto pemetaan. Pilih kartu sebelum penerbangan.")
            }
            guard mapping.allSatisfy({ $0.capture.settings.sameRadiometry(as: selected.capture.settings) })
            else {
                throw MappingError.invalid(
                    "Pengaturan exposure/warna foto berbeda dari referensi. Ekspor asli atau gunakan referensi dari segmen yang sesuai."
                )
            }
            reference = selected
            base = try RGBPreview(url: selected.url).grayGain(patch: patch)
        } else if overlap {
            throw MappingError.invalid("Pilih referensi kartu sebelum koreksi overlap")
        }
        let parent = store.directory(id).appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let runID = UUID().uuidString
        let staging = parent.appendingPathComponent("." + runID + ".pending", isDirectory: true)
        let final = parent.appendingPathComponent("WebODM_" + runID, isDirectory: true)
        let images = staging.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        let context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        ])
        var entries = [ExportEntry]()
        var warnings = [String]()
        var previous: RGBPreview?
        var previousName: String?
        var previousScale = 1.0
        for (i, photo) in mapping.enumerated() {
            try autoreleasepool {
                let preview = try RGBPreview(url: photo.url)
                var scale = 1.0
                var matched: String?
                var warning: String?
                if overlap, let previous {
                    if let factor = OverlapExposure.register(reference: previous, floating: preview),
                        (0.5...2).contains(previousScale * factor)
                    {
                        scale = previousScale * factor
                        matched = previousName
                    } else {
                        warning =
                            "Overlap tidak terverifikasi; hanya koreksi kartu. Segmen exposure dimulai ulang."
                    }
                }
                let gains = base.scaled(scale)
                if preview.clipping(gain: gains) > 0.01 {
                    warning =
                        (warning.map { $0 + " " } ?? "")
                        + "Highlight ≥1% pada preview setelah koreksi; periksa foto asli dan hasil."
                }
                let name = Self.outputName(photo)
                let output = images.appendingPathComponent(name)
                if reference == nil {
                    // Decode check above prevents arbitrary bytes from masquerading as an importable image.
                    try FileManager.default.copyItem(at: photo.url, to: output)
                } else {
                    try Self.render(photo.url, to: output, gains: gains, context: context)
                }
                entries.append(
                    ExportEntry(
                        filename: name, sourceSHA256: try DatasetStore.hashFile(photo.url),
                        outputSHA256: try DatasetStore.hashFile(output), gains: gains,
                        overlapReference: matched, warning: warning))
                previous = preview
                previousName = name
                previousScale = scale
            }
            progress(i + 1, mapping.count)
        }
        if overlap {
            warnings.append(
                "Koreksi overlap eksperimental: model bidang datar, maksimal ±1 EV per pasangan dan terhadap awal segmen. Tidak memperbaiki bayangan lokal atau menjamin warna seragam."
            )
        }
        let unresolved = entries.filter { $0.warning != nil }.count
        if unresolved > 0 {
            warnings.append("\(unresolved) foto memerlukan pemeriksaan; lihat processing-report.json.")
        }
        if let geo = Self.geoText(mapping) {
            try geo.write(to: images.appendingPathComponent("geo.txt"), atomically: true, encoding: .utf8)
            warnings.append(
                "geo.txt memakai GNSS iPhone perkiraan dan altitude MSL; bukan RTK. Validasi datum tinggi dan gunakan GCP/checkpoint untuk akurasi survei."
            )
        } else {
            warnings.append(
                "Lokasi segar/valid belum lengkap untuk semua foto; geo.txt tidak dibuat. Gunakan GCP atau geolokasi yang telah diperiksa."
            )
        }
        if let reference {
            let references = staging.appendingPathComponent("References", isDirectory: true)
            try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: reference.url, to: references.appendingPathComponent(reference.url.lastPathComponent))
        }
        let report = ExportReport(
            missionID: id,
            mode: reference == nil
                ? "original-jpeg" : overlap ? "gray-card-with-overlap-experimental" : "gray-card-baseline",
            referenceID: reference?.id,
            referenceSHA256: try reference.map { try DatasetStore.hashFile($0.url) },
            referencePatch: reference == nil ? nil : patch,
            patchOperatorConfirmed: reference != nil && confirmed, entries: entries, warnings: warnings)
        try store.encode(report).write(
            to: staging.appendingPathComponent("processing-report.json"), options: .atomic)
        let readme =
            "Upload hanya isi Images/ (JPEG dan geo.txt jika tersedia) ke WebODM. References/ tidak diupload. Original tetap di folder misi. Koreksi visual RGB bukan reflectance terkalibrasi. Patch kartu dipetakan ke 0.18 linear sRGB (~118/255), bukan bukti reflektansi 18%. Bandingkan rekonstruksi dengan ekspor original.\n\n"
            + warnings.joined(separator: "\n")
        try readme.write(to: staging.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: staging, to: final)
        committed = true
        return ExportResult(folder: final, count: mapping.count, warnings: warnings)
    }
    static func render(_ input: URL, to output: URL, gains: ColorGain, context: CIContext) throws {
        guard gains.values.allSatisfy({ $0.isFinite && $0 > 0 }),
            let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw MappingError.invalid("JPEG asli tidak dapat didekode") }
        let image = CIImage(cgImage: cg).applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: gains.red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gains.green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gains.blue, w: 0),
            ])
        guard
            let result = context.createCGImage(
                image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
            let destination = CGImageDestinationCreateWithURL(
                output as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw MappingError.invalid("Gagal membuat JPEG hasil koreksi") }
        var metadata = properties
        metadata[kCGImageDestinationLossyCompressionQuality as String] = 0.98
        metadata.removeValue(forKey: kCGImagePropertyProfileName as String)
        metadata.removeValue(forKey: kCGImagePropertyMakerAppleDictionary as String)
        if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifColorSpace as String] = 1
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }
        CGImageDestinationAddImage(destination, result, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MappingError.invalid("JPEG hasil koreksi gagal disimpan")
        }
    }
    static func outputName(_ photo: ExportPhoto) -> String {
        URL(fileURLWithPath: DatasetStore.imagePath(photo.capture, raw: false)).lastPathComponent
    }
    static func geoText(_ photos: [ExportPhoto]) -> String? {
        var lines = ["EPSG:4326"]
        for photo in photos {
            guard let geo = photo.capture.location, let age = photo.capture.locationAgeAtRequest,
                age.isFinite, (0...2).contains(age),
                [geo.latitude, geo.longitude, geo.altitudeMSL, geo.horizontalAccuracy, geo.verticalAccuracy]
                    .allSatisfy({ $0.isFinite }),
                (-90...90).contains(geo.latitude), (-180...180).contains(geo.longitude),
                geo.horizontalAccuracy >= 0, geo.verticalAccuracy >= 0
            else { return nil }
            lines.append(
                "\(outputName(photo)) \(geo.longitude) \(geo.latitude) \(geo.altitudeMSL) 0 0 0 \(max(1,geo.horizontalAccuracy)) \(max(1,geo.verticalAccuracy))"
            )
        }
        return photos.isEmpty ? nil : lines.joined(separator: "\n") + "\n"
    }
}
