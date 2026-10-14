import Foundation

struct SurveyGeometry: Codable, Equatable {
    var heightAGL = 80.0
    var speed = 5.0
    var targetGSDcm = 3.0
    var forwardOverlap = 0.8
    var sideOverlap = 0.75
    var calibratedFocalPixels = 0.0
    var reviewed = false
    var useGrayCard = true
    // Photo geometry cannot be guaranteed from video FOV. This is an explicit estimate.
    func estimate(capabilities: CameraCapabilities?) -> SurveyEstimate? {
        guard let c = capabilities, c.width > 0, c.height > 0,
            [heightAGL, speed, targetGSDcm].allSatisfy({ $0.isFinite && $0 > 0 }),
            calibratedFocalPixels.isFinite, calibratedFocalPixels >= 0,
            (0.6...0.95).contains(forwardOverlap), (0.6...0.95).contains(sideOverlap)
        else { return nil }
        let focal: Double
        if calibratedFocalPixels > 0 {
            focal = calibratedFocalPixels
        } else if let fov = c.nominalFieldOfView, fov.isFinite, (1...179).contains(fov) {
            focal = Double(c.width) / (2 * tan(fov * .pi / 360))
        } else {
            return nil
        }
        guard
            let result = try? MappingEstimate.calculate(
                heightAGL: heightAGL, focalPixels: focal,
                alongPixels: Double(c.height), speed: speed, overlap: forwardOverlap)
        else { return nil }
        guard
            [result.gsd, result.maximumInterval, result.maximumShutter].allSatisfy({ $0.isFinite && $0 > 0 })
        else { return nil }
        return SurveyEstimate(
            gsd: result.gsd, maximumInterval: result.maximumInterval,
            maximumShutter: result.maximumShutter,
            sideSpacing: result.gsd * Double(c.width) * (1 - sideOverlap),
            recommendedHeight: targetGSDcm / 100 * focal, calibrated: calibratedFocalPixels > 0)
    }
}
struct SurveyEstimate {
    var gsd: Double
    var maximumInterval: Double
    var maximumShutter: Double
    var sideSpacing: Double
    var recommendedHeight: Double
    var calibrated: Bool
}
struct CapturePreview: Codable {
    var captureID: UUID
    var missionID: UUID
    var kind: String
    var settings: CameraSettings
    var imageData: Data
    var captureSeconds: Double
    var savedAt: Date
    var width: Int
    var height: Int
    var referenceCommandID: UUID? = nil
    var assessment: PreviewAssessment? = nil
    var sharpness: SharpnessAssessment? = nil
    var actualExposure: CapturedExposure? = nil
    var storedBytes: Int64? = nil
}
struct CapturedExposure: Codable {
    var iso: Double
    var shutterSeconds: Double
    init(iso: Double, shutterSeconds: Double) {
        self.iso = iso
        self.shutterSeconds = shutterSeconds
    }
    func matches(_ requested: CameraSettings) -> Bool {
        guard iso.isFinite, shutterSeconds.isFinite, iso > 0, shutterSeconds > 0,
            requested.iso.isFinite, requested.iso > 0, requested.shutterSeconds.isFinite,
            requested.shutterSeconds > 0
        else { return false }
        // Allow EXIF quantization; compare ISO and duration separately so equal EV
        // cannot conceal a slower shutter and increased motion blur.
        return abs(log2(iso / Double(requested.iso))) <= 1.0 / 3
            && abs(log2(shutterSeconds / requested.shutterSeconds)) <= 1.0 / 6
    }
}
enum MissionStorage {
    static func requiredBytes(sampleBytes: Int64?, photoCount: Int) -> Int64? {
        guard let bytes = sampleBytes, bytes > 0, (1...100000).contains(photoCount) else { return nil }
        let estimate = ceil(Double(bytes) * Double(photoCount) * 1.3) + 512 * 1024 * 1024
        guard estimate.isFinite, estimate < Double(Int64.max) else { return nil }
        return Int64(estimate)
    }
}
enum CaptureCadence {
    static func minimumInterval(for sample: CapturePreview) -> Double? {
        guard sample.captureSeconds.isFinite, sample.captureSeconds > 0 else { return nil }
        let value = ceil(sample.captureSeconds * 1.25 * 10) / 10
        return value.isFinite ? max(1, value) : nil
    }
}
struct QualityReview {
    var sharp = false
    var highlights = false
    var focus = false
    var mounted = false
    var endurance = false
    var controlPoints = false
    var complete: Bool { sharp && highlights && focus && mounted && endurance && controlPoints }
}
struct StartReadiness {
    var blockers: [String]
    var canStart: Bool { blockers.isEmpty }
    static func evaluate(
        plan: MissionPlan, geometry: SurveyGeometry, telemetry: Telemetry,
        connected: Bool, lastReceived: Date?, now: Date, pending: Bool,
        appliedSettings: CameraSettings?, sample: CapturePreview?, review: QualityReview,
        grayLocked: Bool, referenceSaved: Bool
    ) -> StartReadiness {
        var errors: [String] = []
        if !connected { errors.append("Hubungkan kembali iPhone") }
        if lastReceived.map({ now.timeIntervalSince($0) < 0 || now.timeIntervalSince($0) > 6 }) ?? true {
            errors.append("Tunggu status terbaru dari iPhone")
        }
        if pending || telemetry.captureBusy == true {
            errors.append("Tunggu operasi atau penyimpanan foto selesai")
        }
        if telemetry.phase != .ready || telemetry.missionID == nil {
            errors.append("Buat misi baru, atau selesaikan misi aktif terlebih dahulu")
        }
        do { try plan.validate() } catch { errors.append(error.localizedDescription) }
        if let c = telemetry.capabilities {
            if !c.manualExposure || !c.manualFocus || !c.manualWB {
                errors.append("Kamera ini belum mendukung seluruh kontrol manual")
            }
            if !c.minISO.isFinite || !c.maxISO.isFinite || c.minISO <= 0 || c.maxISO < c.minISO
                || plan.camera.iso < c.minISO || plan.camera.iso > c.maxISO
            {
                errors.append("ISO di luar rentang iPhone")
            }
            if !c.minShutter.isFinite || !c.maxShutter.isFinite || c.minShutter <= 0
                || c.maxShutter < c.minShutter || plan.camera.shutterSeconds < c.minShutter
                || plan.camera.shutterSeconds > c.maxShutter
            {
                errors.append("Shutter di luar rentang iPhone")
            }
            if plan.camera.raw && !c.bayerRAW { errors.append("RAW tidak tersedia pada kamera ini") }
        } else {
            errors.append("Siapkan kamera untuk membaca kemampuan perangkat")
        }
        if appliedSettings != plan.camera || telemetry.settings != plan.camera {
            errors.append(
                plan.guidedMode == true
                    ? "Klik Siapkan kamera otomatis dan tunggu konfirmasi iPhone"
                    : "Terapkan pengaturan sekarang dan tunggu konfirmasi iPhone")
        }
        if let estimate = geometry.estimate(capabilities: telemetry.capabilities) {
            if estimate.gsd * 100 > geometry.targetGSDcm * 1.001 {
                errors.append("Turunkan tinggi agar perkiraan GSD memenuhi target")
            }
            if plan.interval > estimate.maximumInterval {
                errors.append("Perpendek interval atau turunkan kecepatan untuk menjaga overlap")
            }
            if plan.camera.shutterSeconds > estimate.maximumShutter {
                errors.append("Percepat shutter untuk membatasi motion blur")
            }
        } else {
            errors.append("Lengkapi geometri penerbangan yang valid")
        }
        if plan.guidedMode == true && (plan.focusCalibration?.lensPosition != plan.camera.lensPosition) {
            errors.append("Cari fokus pada objek di jarak kerja, lalu periksa foto uji")
        }
        if plan.guidedMode == true && plan.exposureCalibration == nil {
            errors.append("Ukur cahaya dengan gray card sebelum mulai")
        }
        if !geometry.reviewed { errors.append("Tinjau tinggi, jalur, dan estimasi GSD") }
        if geometry.useGrayCard && !grayLocked {
            errors.append("Ambil referensi gray card 18% untuk mengunci warna")
        } else if geometry.useGrayCard && !referenceSaved {
            errors.append("Tunggu foto referensi gray card tersimpan di iPhone")
        }
        if let sample, sample.settings == plan.camera, sample.kind == "quality-test",
            sample.missionID == telemetry.missionID
        {
            if let exposure = sample.actualExposure {
                if !exposure.matches(plan.camera) {
                    errors.append(
                        "Exposure foto asli berbeda dari pengaturan; siapkan kamera dan ambil foto uji ulang")
                }
                if let estimate = geometry.estimate(capabilities: telemetry.capabilities),
                    exposure.shutterSeconds > estimate.maximumShutter
                {
                    errors.append("Shutter foto asli terlalu lambat untuk kecepatan terbang ini")
                }
            } else {
                errors.append("EXIF exposure belum tersedia; perbarui DroneCam dan ambil foto uji ulang")
            }
            if let required = MissionStorage.requiredBytes(
                sampleBytes: sample.storedBytes, photoCount: plan.photoLimit)
            {
                if telemetry.freeBytes < required {
                    errors.append(
                        "Ruang misi diperkirakan perlu "
                            + ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                            + "; kurangi jumlah foto atau kosongkan penyimpanan")
                }
            } else {
                errors.append(
                    "Ukuran foto belum tersedia; ambil foto uji ulang untuk memperkirakan ruang misi")
            }
            if plan.guidedMode == true && sample.sharpness == nil {
                errors.append("Analisis detail belum tersedia; ulangi foto uji")
            }
            if let blocker = sample.assessment?.blocker { errors.append(blocker) }
            if plan.guidedMode == true && sample.assessment == nil {
                errors.append("Pemeriksaan exposure belum tersedia; ambil foto uji kembali")
            }
            if let minimum = CaptureCadence.minimumInterval(for: sample) {
                if sample.captureSeconds * 1.25 > plan.interval {
                    if let estimate = geometry.estimate(capabilities: telemetry.capabilities),
                        minimum <= estimate.maximumInterval, minimum <= 3600
                    {
                        errors.append(
                            String(
                                format:
                                    "Foto uji %.2f s: naikkan interval ke %.1f s, lalu uji cadence kembali",
                                sample.captureSeconds, minimum))
                    } else {
                        errors.append(
                            String(
                                format:
                                    "Kamera memerlukan interval ≥ %.1f s; turunkan kecepatan agar overlap tetap tercapai",
                                minimum))
                    }
                }
            } else {
                errors.append("Waktu foto uji tidak valid; ambil foto uji kembali")
            }
        } else {
            errors.append("Ambil foto uji dengan pengaturan saat ini")
        }
        if !review.complete {
            errors.append("Selesaikan pemeriksaan ketajaman, exposure, dan kesiapan lapangan")
        }
        if telemetry.freeBytes < 512 * 1024 * 1024 {
            errors.append("Sediakan minimal 512 MB ruang bebas pada iPhone")
        }
        if telemetry.battery < 0 {
            errors.append("Tunggu pembacaan baterai iPhone")
        } else if telemetry.battery < 0.2 {
            errors.append("Isi baterai iPhone sebelum mulai (kurang dari 20%)")
        }
        if ["Panas", "Kritis", "unknown"].contains(telemetry.thermal) {
            errors.append("Tunggu suhu perangkat kembali aman")
        }
        return StartReadiness(blockers: errors)
    }
}

// Baseline acquisition policy; margins and ISO ceiling need device/flight validation.
struct ExposureCalibration: Codable, Equatable {
    var method = "center-weighted-device-meter-gray-card"
    var measuredAt: Date
    var meteredISO: Float
    var meteredShutter: Double
    var selectedISO: Float
    var selectedShutter: Double
}
enum GuidedAcquisition {
    static func plan(_ draft: MissionPlan, geometry: SurveyGeometry, capabilities c: CameraCapabilities)
        throws -> MissionPlan
    {
        guard let e = geometry.estimate(capabilities: c) else {
            throw MappingError.invalid("Isi tinggi, kecepatan dan overlap yang valid")
        }
        guard e.gsd * 100 <= geometry.targetGSDcm * 1.001 else {
            throw MappingError.invalid(
                String(
                    format: "Turunkan tinggi ke sekitar %.0f m untuk mencapai detail yang diminta",
                    e.recommendedHeight))
        }
        let shutter = min(c.maxShutter, 0.001, e.maximumShutter * 0.8)
        let interval = floor(min(3600, e.maximumInterval * 0.8) * 10) / 10
        guard shutter >= c.minShutter, interval >= 1 else {
            throw MappingError.invalid(
                "Kurangi kecepatan: kamera belum mampu memenuhi overlap dan batas blur")
        }
        let duration = draft.durationSeconds ?? 600
        guard duration.isFinite, (10...86400).contains(duration) else {
            throw MappingError.invalid("Durasi harus 10 detik hingga 24 jam")
        }
        var result = draft
        result.camera.shutterSeconds = shutter
        result.camera.iso = c.minISO
        result.camera.whiteBalanceGains = nil
        result.focusCalibration = nil
        result.interval = interval
        result.photoLimit = Int(ceil(duration / interval))
        result.exposureCalibration = nil
        result.survey = geometry
        try result.validate()
        return result
    }
    static func exposure(
        meteredISO: Float, meteredShutter: Double, preferredShutter: Double,
        minISO: Float, maxISO: Float, minShutter: Double
    ) throws -> (iso: Float, shutter: Double) {
        guard
            [
                Double(meteredISO), meteredShutter, preferredShutter, Double(minISO), Double(maxISO),
                minShutter,
            ].allSatisfy({ $0.isFinite && $0 > 0 }), maxISO >= minISO, preferredShutter >= minShutter
        else { throw MappingError.invalid("Pengukuran cahaya tidak valid; ulangi referensi") }
        let product = Double(meteredISO) * meteredShutter
        let requiredISO = product / preferredShutter
        guard requiredISO <= Double(maxISO) else {
            throw MappingError.invalid(
                "Cahaya terlalu redup untuk batas ketajaman. Kurangi kecepatan lalu siapkan kamera ulang, atau tunggu cahaya membaik"
            )
        }
        let iso = max(Double(minISO), requiredISO)
        let shutter = product / iso
        guard shutter.isFinite, shutter >= minShutter else {
            throw MappingError.invalid(
                "Cahaya terlalu terang untuk rentang kamera; ulangi referensi atau gunakan filter ND yang telah diuji"
            )
        }
        return (Float(iso), min(preferredShutter, shutter))
    }
}

struct PreviewAssessment: Codable {
    var darkFraction: Double
    var clippedFraction: Double
    var meanBrightness: Double
    var blocker: String? {
        if darkFraction > 0.98 {
            return "Foto uji hampir seluruhnya gelap. Periksa lensa dan ulangi pengukuran cahaya"
        }
        if clippedFraction > 0.98 {
            return "Foto uji hampir seluruhnya jenuh. Ulangi pengukuran cahaya dan foto uji"
        }
        return nil
    }
    var advice: String {
        if let blocker { return blocker }
        if clippedFraction > 0.02 {
            return "Ada area berisiko highlight terpotong; periksa foto asli sebelum menyetujui exposure"
        }
        if meanBrightness < 0.08 { return "Preview terlihat redup; periksa detail bayangan pada foto asli" }
        return "Pemeriksaan exposure dasar lolos. Periksa ketajaman dan highlight pada foto asli"
    }
    static func pixels(_ rgba: [UInt8]) -> PreviewAssessment? {
        guard !rgba.isEmpty, rgba.count % 4 == 0 else { return nil }
        var dark = 0.0
        var clipped = 0.0
        var brightness = 0.0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let r = Double(rgba[i])
            let g = Double(rgba[i + 1])
            let b = Double(rgba[i + 2])
            if max(r, g, b) <= 4 { dark += 1 }
            if max(r, g, b) >= 254 { clipped += 1 }
            brightness += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        let count = Double(rgba.count / 4)
        return PreviewAssessment(
            darkFraction: dark / count, clippedFraction: clipped / count, meanBrightness: brightness / count)
    }

}

struct FocusCalibration: Codable, Equatable {
    var measuredAt: Date
    var lensPosition: Float
    var method = "single-autofocus-center-then-lock"
}
struct SharpnessAssessment: Codable {
    var scores: [Double]
    var texturedPatches: Int
    var advice: String {
        texturedPatches < 2
            ? "Detail bertekstur belum cukup untuk menilai fokus; arahkan ke objek bertekstur dan ulangi foto uji"
            : "Detail pusat dan tepi dianalisis. Periksa foto asli pada 100% sebelum menyetujui fokus"
    }
    // Tenengrad on native-resolution crops, without a universal pass/fail threshold.
    static func score(_ pixels: [UInt8], width: Int, height: Int) -> (energy: Double, contrast: Double)? {
        guard width >= 3, height >= 3, pixels.count == width * height else { return nil }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(pixels.count)
        var energy = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let gx = Double(
                    Int(pixels[i - width + 1]) + 2 * Int(pixels[i + 1]) + Int(pixels[i + width + 1])
                        - Int(pixels[i - width - 1]) - 2 * Int(pixels[i - 1]) - Int(pixels[i + width - 1]))
                let gy = Double(
                    Int(pixels[i + width - 1]) + 2 * Int(pixels[i + width]) + Int(pixels[i + width + 1])
                        - Int(pixels[i - width - 1]) - 2 * Int(pixels[i - width]) - Int(pixels[i - width + 1])
                )
                energy += gx * gx + gy * gy
            }
        }
        return (energy / Double((width - 2) * (height - 2)), sqrt(variance))
    }

}
