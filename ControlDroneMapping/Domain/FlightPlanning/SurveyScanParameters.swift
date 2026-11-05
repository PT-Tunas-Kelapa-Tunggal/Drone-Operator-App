import Foundation

/// Optical specs for camera sensor and lens.
struct CameraOpticalSpec: Codable, Equatable, Sendable {
    var name: String = "iPhone 17"
    var sensorWidth: Double = 8.19
    var sensorHeight: Double = 6.14
    var focalLength: Double = 6.86
    var imageWidth: Int = 5712
    var imageHeight: Int = 4284
    var landscape: Bool = true

    enum Resolution: String, CaseIterable, Identifiable, Codable, Sendable {
        case res24MP = "24 MP"
        case res48MP = "48 MP"
        case res12MP = "12 MP"

        var id: String { rawValue }

        var dimensions: (width: Int, height: Int) {
            switch self {
            case .res24MP: return (5712, 4284)
            case .res48MP: return (8064, 6048)
            case .res12MP: return (4032, 3024)
            }
        }
    }

    static let iphone17 = CameraOpticalSpec(
        name: "iPhone 17",
        sensorWidth: 8.19,
        sensorHeight: 6.14,
        focalLength: 6.86,
        imageWidth: 5712,
        imageHeight: 4284,
        landscape: true
    )

    mutating func setResolution(_ resolution: Resolution) {
        let dims = resolution.dimensions
        imageWidth = dims.width
        imageHeight = dims.height
    }

    /// Instant client-side estimates for immediate UI slider feedback.
    func estimatedLineSpacing(altitude: Double, sideOverlapPercent: Double) -> Double {
        guard focalLength > 0, altitude > 0 else { return 0 }
        let footprintSide = (altitude * sensorWidth) / focalLength
        return footprintSide * max(0, min(1.0, (1.0 - sideOverlapPercent / 100.0)))
    }

    func estimatedTriggerDistance(altitude: Double, frontalOverlapPercent: Double) -> Double {
        guard focalLength > 0, altitude > 0 else { return 0 }
        let footprintFrontal = (altitude * sensorHeight) / focalLength
        return footprintFrontal * max(0, min(1.0, (1.0 - frontalOverlapPercent / 100.0)))
    }

    func estimatedGSDcm(altitude: Double) -> Double {
        guard focalLength > 0, imageWidth > 0, altitude > 0 else { return 0 }
        return (altitude * sensorWidth * 100.0) / (Double(imageWidth) * focalLength)
    }
}

/// Parameters controlling autonomous survey grid generation.
/// All fields map directly to native flight engine facts and calculations.
struct SurveyScanParameters: Codable, Equatable, Sendable {
    var altitude: Double = 30.0
    var speed: Double = 5.0
    var gridAngle: Double = 0.0
    var spacing: Double? = nil
    var triggerDistance: Double? = nil
    var turnaroundDistance: Double = 10.0
    var hoverAndCapture: Bool = false
    var useCameraOverlap: Bool = true
    var frontalOverlap: Double = 0.75
    var sideOverlap: Double = 0.70
    var cameraBrand: String = "Custom Camera"
    var cameraSpec: CameraOpticalSpec? = .iphone17
    var firmware: FlightFirmware = .ardupilot
    var vehicleType: Int = 2
    var entryLocation: Int = 0

    init(
        altitude: Double = 30.0,
        speed: Double = 5.0,
        gridAngle: Double = 0.0,
        spacing: Double? = nil,
        triggerDistance: Double? = nil,
        turnaroundDistance: Double = 10.0,
        hoverAndCapture: Bool = false,
        useCameraOverlap: Bool = true,
        frontalOverlap: Double = 0.75,
        sideOverlap: Double = 0.70,
        cameraBrand: String = "Custom Camera",
        cameraSpec: CameraOpticalSpec? = .iphone17,
        firmware: FlightFirmware = .ardupilot,
        vehicleType: Int = 2,
        entryLocation: Int = 0
    ) {
        self.altitude = altitude
        self.speed = speed
        self.gridAngle = gridAngle
        self.spacing = spacing
        self.triggerDistance = triggerDistance
        self.turnaroundDistance = turnaroundDistance
        self.hoverAndCapture = hoverAndCapture
        self.useCameraOverlap = useCameraOverlap
        self.frontalOverlap = frontalOverlap
        self.sideOverlap = sideOverlap
        self.cameraBrand = cameraBrand
        self.cameraSpec = cameraSpec
        self.firmware = firmware
        self.vehicleType = vehicleType
        self.entryLocation = entryLocation
    }
}
