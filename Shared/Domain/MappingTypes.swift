import Foundation

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

struct GeoSample: Codable {
    var latitude: Double
    var longitude: Double
    var altitudeMSL: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var timestamp: Date
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
