import Foundation
import ImageIO

struct CameraSettings: Codable, Equatable {
    var iso: Float = 100
    var shutterSeconds: Double = 0.001
    var temperature: Float = 5500
    var tint: Float = 0
    var lensPosition: Float = 1
    var raw = false
    var whiteBalanceGains: [Float]? = nil

    func sameRadiometry(as other: CameraSettings) -> Bool {
        var value = self
        value.lensPosition = other.lensPosition
        return value == other
    }
    func validate() throws {
        guard iso.isFinite, iso > 0, shutterSeconds.isFinite, shutterSeconds > 0,
            temperature.isFinite, (2000...12000).contains(temperature),
            tint.isFinite, (-150...150).contains(tint), lensPosition.isFinite,
            (0...1).contains(lensPosition),
            whiteBalanceGains == nil
                || (whiteBalanceGains!.count == 3 && whiteBalanceGains!.allSatisfy { $0.isFinite && $0 >= 1 })
        else {
            throw MappingError.invalid("Parameter kamera tidak valid")
        }
    }
}

struct MissionPlan: Codable, Equatable {
    var name = "Survey udara"
    var interval: Double = 3
    var photoLimit = 200
    var camera = CameraSettings()
    var survey: SurveyGeometry? = nil
    var guidedMode: Bool? = nil
    var durationSeconds: Double? = nil
    var exposureCalibration: ExposureCalibration? = nil
    var focusCalibration: FocusCalibration? = nil
    func validate() throws {
        try camera.validate()
        guard interval.isFinite, (1...3600).contains(interval), (1...100000).contains(photoLimit),
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100
        else {
            throw MappingError.invalid("Interval 1–3600 detik, target 1–100000 foto, dan nama wajib diisi")
        }
    }
}

struct CameraCapabilities: Codable {
    var model: String
    var minISO: Float
    var maxISO: Float
    var minShutter: Double
    var maxShutter: Double
    var width: Int
    var height: Int
    var bayerRAW: Bool
    var manualExposure: Bool
    var manualFocus: Bool
    var manualWB: Bool
    var nominalFieldOfView: Double? = nil
}

struct AttitudeSample: Codable, Equatable {
    var rollDegrees: Double
    var pitchDegrees: Double
    var yawDegrees: Double
    var tiltFromNadirDegrees: Double
    var isOblique: Bool { tiltFromNadirDegrees > 12 }

    static func fromGravity(
        x: Double, y: Double, z: Double, roll: Double, pitch: Double, yaw: Double
    ) -> AttitudeSample {
        let magnitude = max(0.0001, (x * x + y * y + z * z).squareRoot())
        // Back camera points along -Z in device coordinates; flat nadir flight has gravity (0, 0, -1).
        let cosine = min(1.0, max(-1.0, (-z) / magnitude))
        let tilt = acos(cosine) * 180 / .pi
        return AttitudeSample(
            rollDegrees: roll * 180 / .pi,
            pitchDegrees: pitch * 180 / .pi,
            yawDegrees: yaw * 180 / .pi,
            tiltFromNadirDegrees: tilt
        )
    }
}

enum MissionPhase: String, Codable { case idle, ready, countdown, capturing, paused, completed, failed }
struct Telemetry: Codable {
    var phase: MissionPhase = .idle
    var missionID: UUID?
    var countdownRemaining: Int?
    var captureBusy: Bool?
    var saved = 0
    var missed = 0
    var battery: Float = -1
    var thermal = "unknown"
    var freeBytes: Int64 = 0
    var message = "Siapkan kamera untuk memulai"
    var updatedAt = Date()
    var capabilities: CameraCapabilities?
    var settings: CameraSettings?
    var exposureCalibration: ExposureCalibration? = nil
    var focusCalibration: FocusCalibration? = nil
    var gpsHorizontalAccuracy: Double? = nil
    var attitude: AttitudeSample? = nil
}

struct MissionRecord: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var plan: MissionPlan
    var phase: MissionPhase = .ready
    var saved = 0
    var missed = 0
    var note = ""
}

struct GeoSample: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var altitudeMSL: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var timestamp: Date

    /// Clamps sub-second negative clock jitter between CLLocation timestamp and capture request time.
    static func normalizedAge(requestedAt: Date, sampleTimestamp: Date) -> Double {
        let raw = requestedAt.timeIntervalSince(sampleTimestamp)
        return (-1.0..<0.0).contains(raw) ? 0.0 : raw
    }

    var gpsMetadataDictionary: [String: Any] {
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(latitude),
            kCGImagePropertyGPSLatitudeRef as String: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(longitude),
            kCGImagePropertyGPSLongitudeRef as String: longitude >= 0 ? "E" : "W",
        ]
        if altitudeMSL.isFinite {
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitudeMSL)
            gps[kCGImagePropertyGPSAltitudeRef as String] = altitudeMSL < 0 ? 1 : 0
        }
        if horizontalAccuracy.isFinite, horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] = horizontalAccuracy
            gps[kCGImagePropertyGPSDOP as String] = max(1.0, horizontalAccuracy)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: timestamp)
        if let year = parts.year, let month = parts.month, let day = parts.day,
            let hour = parts.hour, let minute = parts.minute, let second = parts.second
        {
            gps[kCGImagePropertyGPSDateStamp as String] = String(
                format: "%04d:%02d:%02d", year, month, day)
            gps[kCGImagePropertyGPSTimeStamp as String] = String(
                format: "%02d:%02d:%02d", hour, minute, second)
        }
        return gps
    }

    /// Embeds EXIF `{GPS}` tags into encoded image data while preserving existing metadata and color profile.
    func embeddingEXIF(into imageData: Data) -> Data {
        guard latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude),
            horizontalAccuracy.isFinite, horizontalAccuracy >= 0,
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let type = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0
        else { return imageData }
        let copyOut = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(copyOut, type, 1, nil) {
            let options: [CFString: Any] = [
                kCGImageDestinationMergeMetadata: true,
                kCGImagePropertyGPSDictionary: gpsMetadataDictionary,
            ]
            if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil),
                copyOut.length > 0,
                let verify = CGImageSourceCreateWithData(copyOut as CFData, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(verify, 0, nil) as? [String: Any],
                props[kCGImagePropertyGPSDictionary as String] != nil
            {
                return copyOut as Data
            }
        }
        let fallbackOut = NSMutableData()
        guard let fallbackDest = CGImageDestinationCreateWithData(fallbackOut, type, 1, nil) else {
            return imageData
        }
        var merged = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        merged[kCGImagePropertyGPSDictionary as String] = gpsMetadataDictionary
        CGImageDestinationAddImageFromSource(fallbackDest, source, 0, merged as CFDictionary)
        guard CGImageDestinationFinalize(fallbackDest), fallbackOut.length > 0 else {
            return imageData
        }
        return fallbackOut as Data
    }
}

struct CaptureRecord: Codable {
    var layoutVersion: Int? = nil
    var id: UUID
    var missionID: UUID
    var sequence: Int
    var kind: String
    var requestedAt: Date
    var photoHostTimeSeconds: Double
    var settings: CameraSettings
    var location: GeoSample?
    var locationAgeAtRequest: Double?
    var attitude: AttitudeSample? = nil
    var files: [String]
    var sha256: [String: String]
    var note =
        "GNSS is an approximate phone location, not RTK or exposure-synchronized. Original EXIF is preserved."
}

enum CommandAction: String, Codable {
    case prepare, createMission, apply, start, pause, resume, finish, testCapture, grayCard,
        grayCardReference, calibrationBefore, calibrationAfter, list, download
}
struct Command: Codable, Identifiable {
    var id = UUID()
    var action: CommandAction
    var plan: MissionPlan?
    var missionID: UUID?
}
struct Reply: Codable {
    var commandID: UUID
    var accepted: Bool
    var message: String
}
struct Packet: Codable {
    var version = 1
    var command: Command?
    var replyRequestID: UUID?
    var preview: CapturePreview?
    var reply: Reply?
    var telemetry: Telemetry?
    var missions: [MissionRecord]?
    var transferError: String? = nil
}

enum MappingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let value): return value
        }
    }
}

// Pinhole estimate: use calibrated focal length in pixels for the chosen photo format.
struct MappingEstimate {
    let gsd: Double
    let footprintAlong: Double
    let maximumInterval: Double
    let maximumShutter: Double
    static func calculate(
        heightAGL: Double, focalPixels: Double, alongPixels: Double,
        speed: Double, overlap: Double, blurPixels: Double = 0.5
    ) throws -> MappingEstimate {
        guard [heightAGL, focalPixels, alongPixels, speed, blurPixels].allSatisfy({ $0.isFinite && $0 > 0 }),
            overlap.isFinite, (0..<1).contains(overlap)
        else { throw MappingError.invalid("Geometri tidak valid") }
        let gsd = heightAGL / focalPixels
        let footprint = gsd * alongPixels
        return MappingEstimate(
            gsd: gsd, footprintAlong: footprint,
            maximumInterval: footprint * (1 - overlap) / speed,
            maximumShutter: blurPixels * gsd / speed)
    }
}

// Skips overdue slots instead of issuing a burst that destroys intended image spacing.
struct CaptureSchedule {
    var next: Double
    let interval: Double
    mutating func consume(now: Double) -> Int? {
        guard now >= next else { return nil }
        let missed = max(0, Int((now - next) / interval))
        next += Double(missed + 1) * interval
        return missed
    }
}

struct StartCountdown {
    let deadline: Double
    init(now: Double) { deadline = now + 3 }
    func remaining(now: Double) -> Int { max(0, min(3, Int(ceil(deadline - now)))) }
}

// Invite attempts are bounded and spaced; discovery events cannot create invite storms.
struct ReconnectPolicy {
    private(set) var attempts = 0
    private(set) var nextAttemptAt: Double = 0
    let invitationTimeout: Double = 10
    func canAttempt(now: Double) -> Bool { now >= nextAttemptAt }
    mutating func didAttempt(now: Double) {
        let delay = min(15.0, pow(2.0, Double(min(attempts + 1, 4))))
        attempts += 1
        nextAttemptAt = now + invitationTimeout + delay
    }
    mutating func didConnect() {
        attempts = 0
        nextAttemptAt = 0
    }
}
