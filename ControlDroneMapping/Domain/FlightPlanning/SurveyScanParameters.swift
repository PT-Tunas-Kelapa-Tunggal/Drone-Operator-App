import Foundation

/// Parameters controlling autonomous survey grid generation.
/// All fields map directly to native flight engine facts and calculations.
struct SurveyScanParameters: Codable, Equatable, Sendable {
    var altitude: Double = 50.0
    var speed: Double = 5.0
    var gridAngle: Double = 0.0
    var spacing: Double? = 20.0
    var triggerDistance: Double? = 15.0
    var turnaroundDistance: Double = 10.0
    var hoverAndCapture: Bool = false
    var useCameraOverlap: Bool = false
    var frontalOverlap: Double = 0.70
    var sideOverlap: Double = 0.70
    var cameraBrand: String = "Manual"
    var firmware: FlightFirmware = .ardupilot
    var vehicleType: Int = 2
    var entryLocation: Int = 0

    init(
        altitude: Double = 50.0,
        speed: Double = 5.0,
        gridAngle: Double = 0.0,
        spacing: Double? = 20.0,
        triggerDistance: Double? = 15.0,
        turnaroundDistance: Double = 10.0,
        hoverAndCapture: Bool = false,
        useCameraOverlap: Bool = false,
        frontalOverlap: Double = 0.70,
        sideOverlap: Double = 0.70,
        cameraBrand: String = "Manual",
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
        self.firmware = firmware
        self.vehicleType = vehicleType
        self.entryLocation = entryLocation
    }
}
