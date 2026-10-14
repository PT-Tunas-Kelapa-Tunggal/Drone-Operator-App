import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import simd

@main enum WebODMExportTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        func rejected(_ label: String, _ work: () throws -> Void) {
            do {
                try work()
                preconditionFailure(label)
            } catch { checks += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "export-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DatasetStore(root: root)
        var mission = MissionRecord(plan: MissionPlan())
        mission.plan.name = "Uji warna"
        mission.phase = .completed
        try store.write(mission)
        func jpeg(uniform: Bool, multiplier: Double = 1, shift: Int = 0) throws -> Data {
            let w = 768
            let h = 512
            var bytes = [UInt8](repeating: 255, count: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let base: Double
                    if uniform {
                        base = 0.18
                    } else {
                        let xx = max(0, x + shift)
                        // Textured scene with many local features and a broad linear intensity range.
                        let cell = ((xx / 16) * 193 + (y / 16) * 79 + (xx / 16) * (y / 16) * 23) % 211
                        base = 0.035 + Double(cell) / 211 * 0.28
                    }
                    for c in 0..<3 {
                        let linear = base * multiplier * (uniform ? [1.10, 1, 0.9][c] : 1)
                        let encoded =
                            linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
                        bytes[(y * w + x) * 4 + c] = UInt8(max(0, min(255, (encoded * 255).rounded())))
                    }
                }
            }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
            let data = NSMutableData()
            let out = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(
                out, image,
                [
                    kCGImageDestinationLossyCompressionQuality: 1, kCGImagePropertyOrientation: 1,
                    kCGImagePropertyExifDictionary: [
                        kCGImagePropertyExifExposureTime: 0.001, kCGImagePropertyExifISOSpeedRatings: [100],
                        kCGImagePropertyExifFocalLength: 5.96,
                    ],
                ] as CFDictionary)
            check(CGImageDestinationFinalize(out), "Fixture must be a real encoded JPEG")
            return data as Data
        }
        func capture(_ kind: String, _ data: Data, sequence: Int) throws -> ExportPhoto {
            let id = UUID()
            let folder = store.directory(mission.id).appendingPathComponent("." + id.uuidString + ".pending")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("image.jpg"))
            try PropertyListSerialization.data(fromPropertyList: ["test": true], format: .xml, options: 0)
                .write(to: folder.appendingPathComponent("image.jpg.metadata.plist"))
            let geo = GeoSample(
                latitude: 1.1, longitude: 104.1, altitudeMSL: 80, horizontalAccuracy: 6, verticalAccuracy: 4,
                timestamp: Date())
            var c = CaptureRecord(
                id: id, missionID: mission.id, sequence: sequence, kind: kind,
                requestedAt: Date().addingTimeInterval(Double(sequence)),
                photoHostTimeSeconds: Double(sequence), settings: CameraSettings(), location: geo,
                locationAgeAtRequest: 0.5, files: ["image.jpg"],
                sha256: ["image.jpg": DatasetStore.hash(data)])
            c = try store.commit(staging: folder, capture: c)
            return ExportPhoto(
                capture: c, url: store.directory(mission.id).appendingPathComponent(c.files[0]))
        }
        let reference = try capture("calibration-before", jpeg(uniform: true), sequence: 0)
        _ = try capture("calibration-before", jpeg(uniform: true), sequence: 0)
        _ = try capture("calibration-after", jpeg(uniform: true), sequence: 0)
        _ = try capture("quality-test", jpeg(uniform: false), sequence: 0)
        let a = try capture("mapping", jpeg(uniform: false), sequence: 1)
        let b = try capture("mapping", jpeg(uniform: false, multiplier: 0.65, shift: 48), sequence: 2)
        mission.saved = 2
        try store.write(mission)
        let exporter = WebODMExporter(store: store)
        let oldHash = try DatasetStore.hashFile(a.url)
        rejected("Must confirm a physical gray patch") {
            _ = try exporter.export(
                id: mission.id, referenceID: reference.id, patch: GrayPatch(), confirmed: false,
                overlap: false)
        }
        rejected("Cannot use a mapping photo as gray reference") {
            _ = try exporter.export(
                id: mission.id, referenceID: a.id, patch: GrayPatch(), confirmed: true, overlap: false)
        }
        rejected("Reject invalid ROI") {
            _ = try exporter.export(
                id: mission.id, referenceID: reference.id,
                patch: GrayPatch(x: 0.9, y: 0.9, width: 0.2, height: 0.2), confirmed: true, overlap: false)
        }
        let originals = try exporter.export(
            id: mission.id, referenceID: nil, patch: GrayPatch(), confirmed: false, overlap: false)
        let names = try FileManager.default.contentsOfDirectory(
            atPath: originals.folder.appendingPathComponent("Images").path)
        check(
            names.filter { $0.hasSuffix(".jpg") }.count == 2,
            "References and quality-test excluded from WebODM Images")
        check(
            try DatasetStore.hashFile(
                originals.folder.appendingPathComponent("Images/" + WebODMExporter.outputName(a))) == oldHash,
            "Original export byte-for-byte lossless")
        let geo = try String(
            contentsOf: originals.folder.appendingPathComponent("Images/geo.txt"), encoding: .utf8)
        check(
            geo.hasPrefix("EPSG:4326\n") && geo.contains("104.1 1.1 80.0")
                && geo.contains(WebODMExporter.outputName(a)),
            "Geo longitude/latitude and output filenames follow WebODM format")
        var stale = a
        stale.capture.locationAgeAtRequest = 4
        check(
            WebODMExporter.geoText([a, stale]) == nil,
            "Never generate a partial geo file from stale locations")
        let corrected = try exporter.export(
            id: mission.id, referenceID: reference.id, patch: GrayPatch(), confirmed: true, overlap: false)
        check(
            corrected.folder != originals.folder,
            "Each export is independent and does not overwrite a previous run")
        let output = corrected.folder.appendingPathComponent("Images/" + WebODMExporter.outputName(a))
        let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        check(decoded.width == 768 && decoded.height == 512, "Correction preserves native pixel dimensions")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        let exif = properties[kCGImagePropertyExifDictionary] as! NSDictionary
        check(
            (exif[kCGImagePropertyExifExposureTime] as! NSNumber).doubleValue == 0.001,
            "Camera EXIF exposure retained")
        check(try DatasetStore.hashFile(a.url) == oldHash, "Processing never mutates original")
        check(
            try FileManager.default.contentsOfDirectory(
                atPath: corrected.folder.appendingPathComponent("References").path) == [
                    reference.url.lastPathComponent
                ],
            "Only the selected preflight gray reference is exported; repeated and postflight references stay in original mission"
        )
        let patchPreview = try RGBPreview(url: reference.url)
        let gains = try patchPreview.grayGain(patch: GrayPatch())
        let patchOutput = root.appendingPathComponent("neutralized.jpg")
        try WebODMExporter.render(
            reference.url, to: patchOutput, gains: gains,
            context: CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            ]))
        let neutral = try RGBPreview(url: patchOutput).rgb(x: 384, y: 256)
        check(
            neutral.allSatisfy { abs($0 - 0.18) < 0.012 },
            "Actual encoded correction maps gray patch to neutral 0.18 linear sRGB")
        let av = try RGBPreview(url: a.url)
        let bv = try RGBPreview(url: b.url)
        var transform = matrix_identity_float3x3
        transform.columns.2.x = 48
        let known = OverlapExposure.factor(reference: av, floating: bv, transform: transform)
        check(
            known != nil && abs(known! - 1 / 0.65) < 0.04,
            "Matched same-object overlap recovers known exposure change")
        check(
            OverlapExposure.factor(reference: av, floating: bv, transform: matrix_identity_float3x3) == nil,
            "Incorrect geometry cannot drive an exposure correction")
        check(
            OverlapExposure.factor(
                reference: patchPreview, floating: patchPreview, transform: matrix_identity_float3x3) == nil,
            "Uniform scenes cannot claim a valid overlap match")
        let measured = OverlapExposure.register(reference: av, floating: bv)
        check(
            measured != nil && abs(measured! - 1 / 0.65) < 0.08,
            "Native Vision registration and photometric gate recover translated scene")
        let adaptive = try exporter.export(
            id: mission.id, referenceID: reference.id, patch: GrayPatch(), confirmed: true, overlap: true)
        let report = try JSONDecoder().decode(
            ExportReport.self,
            from: Data(contentsOf: adaptive.folder.appendingPathComponent("processing-report.json")))
        check(
            report.entries[1].overlapReference == WebODMExporter.outputName(a),
            "Export records the overlap reference used for the second photo")
        check(
            report.referenceSHA256 == (try DatasetStore.hashFile(reference.url)) && report.entries.count == 2,
            "Processing report identifies reference and every original/output hash")
        let dim = try capture("mapping", jpeg(uniform: false, multiplier: 0.1), sequence: 3)
        let dimPreview = try RGBPreview(url: dim.url)
        check(
            OverlapExposure.factor(reference: av, floating: dimPreview, transform: matrix_identity_float3x3)
                == nil, "Reject excessive exposure correction instead of forcing a match")
        mission.saved = 3
        try store.write(mission)
        let flagged = try exporter.export(
            id: mission.id, referenceID: reference.id, patch: GrayPatch(), confirmed: true, overlap: true)
        let flaggedReport = try JSONDecoder().decode(
            ExportReport.self,
            from: Data(contentsOf: flagged.folder.appendingPathComponent("processing-report.json")))
        check(
            flaggedReport.entries[2].overlapReference == nil && flaggedReport.entries[2].warning != nil,
            "Unmatched exposure is flagged and falls back to card correction without invented normalization")
        let broken = try capture("mapping", Data("not a JPEG".utf8), sequence: 4)
        mission.saved = 4
        try store.write(mission)
        let exportRoot = store.directory(mission.id).appendingPathComponent("Exports")
        let before = try FileManager.default.contentsOfDirectory(atPath: exportRoot.path)
        rejected("Valid hash of invalid JPEG is not proof of WebODM compatibility") {
            _ = try exporter.export(
                id: mission.id, referenceID: nil, patch: GrayPatch(), confirmed: false, overlap: false)
        }
        check(
            try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).sorted() == before.sorted(),
            "Interrupted processing publishes no partial export and cleans staging")
        _ = broken
        try Data("broken".utf8).write(to: b.url)
        rejected("Corrupt input fails before any export commit") {
            _ = try exporter.export(
                id: mission.id, referenceID: nil, patch: GrayPatch(), confirmed: false, overlap: false)
        }
        print(
            "PASS: \(checks) WebODM export assertions (real encoded synthetic JPEG; no aerial reconstruction)"
        )
    }
}
