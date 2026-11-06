import Foundation

public struct DroneTelemetry: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let altitudeRelative: Double
    public let altitudeAMSL: Double
    public let groundSpeed: Double
    public let climbRate: Double
    public let heading: Double
    public let roll: Double
    public let pitch: Double
    public let distanceToHome: Double
    public let missionCurrentSeq: Int

    public init(
        latitude: Double = 0,
        longitude: Double = 0,
        altitudeRelative: Double = 0,
        altitudeAMSL: Double = 0,
        groundSpeed: Double = 0,
        climbRate: Double = 0,
        heading: Double = 0,
        roll: Double = 0,
        pitch: Double = 0,
        distanceToHome: Double = 0,
        missionCurrentSeq: Int = 0
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeRelative = altitudeRelative
        self.altitudeAMSL = altitudeAMSL
        self.groundSpeed = groundSpeed
        self.climbRate = climbRate
        self.heading = heading
        self.roll = roll
        self.pitch = pitch
        self.distanceToHome = distanceToHome
        self.missionCurrentSeq = missionCurrentSeq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.latitude = (try? c.decodeIfPresent(Double.self, forKey: .latitude)) ?? 0.0
        self.longitude = (try? c.decodeIfPresent(Double.self, forKey: .longitude)) ?? 0.0
        self.altitudeRelative = (try? c.decodeIfPresent(Double.self, forKey: .altitudeRelative)) ?? 0.0
        self.altitudeAMSL = (try? c.decodeIfPresent(Double.self, forKey: .altitudeAMSL)) ?? 0.0
        self.groundSpeed = (try? c.decodeIfPresent(Double.self, forKey: .groundSpeed)) ?? 0.0
        self.climbRate = (try? c.decodeIfPresent(Double.self, forKey: .climbRate)) ?? 0.0
        self.heading = (try? c.decodeIfPresent(Double.self, forKey: .heading)) ?? 0.0
        self.roll = (try? c.decodeIfPresent(Double.self, forKey: .roll)) ?? 0.0
        self.pitch = (try? c.decodeIfPresent(Double.self, forKey: .pitch)) ?? 0.0
        self.distanceToHome = (try? c.decodeIfPresent(Double.self, forKey: .distanceToHome)) ?? 0.0
        self.missionCurrentSeq = (try? c.decodeIfPresent(Int.self, forKey: .missionCurrentSeq)) ?? 0
    }
}

public struct DroneBatteryInfo: Codable, Equatable {
    public let percent: Double
    public let voltage: Double
    public let current: Double
    public let temperature: Double

    public init(percent: Double = 0, voltage: Double = 0, current: Double = 0, temperature: Double = 0) {
        self.percent = percent
        self.voltage = voltage
        self.current = current
        self.temperature = temperature
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.percent = (try? c.decodeIfPresent(Double.self, forKey: .percent)) ?? 0.0
        self.voltage = (try? c.decodeIfPresent(Double.self, forKey: .voltage)) ?? 0.0
        self.current = (try? c.decodeIfPresent(Double.self, forKey: .current)) ?? 0.0
        self.temperature = (try? c.decodeIfPresent(Double.self, forKey: .temperature)) ?? 0.0
    }
}

public struct DroneGPSInfo: Codable, Equatable {
    public let satellites: Int
    public let lock: Int
    public let hdop: Double

    public init(satellites: Int = 0, lock: Int = 0, hdop: Double = 0) {
        self.satellites = satellites
        self.lock = lock
        self.hdop = hdop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.satellites = (try? c.decodeIfPresent(Int.self, forKey: .satellites)) ?? 0
        self.lock = (try? c.decodeIfPresent(Int.self, forKey: .lock)) ?? 0
        self.hdop = (try? c.decodeIfPresent(Double.self, forKey: .hdop)) ?? 0.0
    }

    public var hasFix: Bool { lock >= 3 }
}

public struct DroneLinkInfo: Codable, Equatable {
    public let rcRSSI: Double

    public init(rcRSSI: Double = 0) {
        self.rcRSSI = rcRSSI
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rcRSSI = (try? c.decodeIfPresent(Double.self, forKey: .rcRSSI)) ?? 0.0
    }
}

public struct ConnectedDrone: Identifiable, Codable, Equatable {
    public let id: Int
    public let active: Bool
    public let firmwareType: String
    public let vehicleType: String
    public let armed: Bool
    public let flying: Bool
    public let landing: Bool
    public let guidedMode: Bool
    public let flightMode: String
    public let flightModes: [String]
    public let readyToFly: Bool
    public let readyToFlyAvailable: Bool
    public let allSensorsHealthy: Bool
    public let canArm: Bool
    public let communicationLost: Bool
    public let sensorNames: [String]
    public let sensorStatus: [String]
    public let telemetry: DroneTelemetry
    public let battery: DroneBatteryInfo
    public let gps: DroneGPSInfo
    public let link: DroneLinkInfo

    public init(
        id: Int,
        active: Bool = false,
        firmwareType: String = "Unknown",
        vehicleType: String = "Generic",
        armed: Bool = false,
        flying: Bool = false,
        landing: Bool = false,
        guidedMode: Bool = false,
        flightMode: String = "UNKNOWN",
        flightModes: [String] = [],
        readyToFly: Bool = false,
        readyToFlyAvailable: Bool = false,
        allSensorsHealthy: Bool = false,
        canArm: Bool = false,
        communicationLost: Bool = false,
        sensorNames: [String] = [],
        sensorStatus: [String] = [],
        telemetry: DroneTelemetry = DroneTelemetry(),
        battery: DroneBatteryInfo = DroneBatteryInfo(),
        gps: DroneGPSInfo = DroneGPSInfo(),
        link: DroneLinkInfo = DroneLinkInfo()
    ) {
        self.id = id
        self.active = active
        self.firmwareType = firmwareType
        self.vehicleType = vehicleType
        self.armed = armed
        self.flying = flying
        self.landing = landing
        self.guidedMode = guidedMode
        self.flightMode = flightMode
        self.flightModes = flightModes
        self.readyToFly = readyToFly
        self.readyToFlyAvailable = readyToFlyAvailable
        self.allSensorsHealthy = allSensorsHealthy
        self.canArm = canArm
        self.communicationLost = communicationLost
        self.sensorNames = sensorNames
        self.sensorStatus = sensorStatus
        self.telemetry = telemetry
        self.battery = battery
        self.gps = gps
        self.link = link
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 1
        self.active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        self.firmwareType = (try? c.decodeIfPresent(String.self, forKey: .firmwareType)) ?? "Unknown"
        self.vehicleType = (try? c.decodeIfPresent(String.self, forKey: .vehicleType)) ?? "Generic"
        self.armed = (try? c.decodeIfPresent(Bool.self, forKey: .armed)) ?? false
        self.flying = (try? c.decodeIfPresent(Bool.self, forKey: .flying)) ?? false
        self.landing = (try? c.decodeIfPresent(Bool.self, forKey: .landing)) ?? false
        self.guidedMode = (try? c.decodeIfPresent(Bool.self, forKey: .guidedMode)) ?? false
        self.flightMode = (try? c.decodeIfPresent(String.self, forKey: .flightMode)) ?? "UNKNOWN"
        self.flightModes = (try? c.decodeIfPresent([String].self, forKey: .flightModes)) ?? []
        self.readyToFly = (try? c.decodeIfPresent(Bool.self, forKey: .readyToFly)) ?? false
        self.readyToFlyAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .readyToFlyAvailable)) ?? false
        self.allSensorsHealthy = (try? c.decodeIfPresent(Bool.self, forKey: .allSensorsHealthy)) ?? false
        self.canArm = (try? c.decodeIfPresent(Bool.self, forKey: .canArm)) ?? false
        self.communicationLost = (try? c.decodeIfPresent(Bool.self, forKey: .communicationLost)) ?? false
        self.sensorNames = (try? c.decodeIfPresent([String].self, forKey: .sensorNames)) ?? []
        self.sensorStatus = (try? c.decodeIfPresent([String].self, forKey: .sensorStatus)) ?? []
        self.telemetry = (try? c.decodeIfPresent(DroneTelemetry.self, forKey: .telemetry)) ?? DroneTelemetry()
        self.battery = (try? c.decodeIfPresent(DroneBatteryInfo.self, forKey: .battery)) ?? DroneBatteryInfo()
        self.gps = (try? c.decodeIfPresent(DroneGPSInfo.self, forKey: .gps)) ?? DroneGPSInfo()
        self.link = (try? c.decodeIfPresent(DroneLinkInfo.self, forKey: .link)) ?? DroneLinkInfo()
    }

    public var displayTitle: String {
        "Drone #\(id) (\(firmwareType) \(vehicleType))"
    }

    public var isReachable: Bool {
        !communicationLost
    }

    public var isReadyToArm: Bool {
        canArm && isReachable
    }
}

public struct VehiclesResponse: Codable {
    public let status: String
    public let count: Int
    public let vehicles: [ConnectedDrone]

    public init(status: String = "ok", count: Int = 0, vehicles: [ConnectedDrone] = []) {
        self.status = status
        self.count = count
        self.vehicles = vehicles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "ok"
        self.count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        self.vehicles = (try? c.decodeIfPresent([ConnectedDrone].self, forKey: .vehicles)) ?? []
    }
}

public enum DroneFlightCommand: String, Codable {
    case arm
    case disarm
    case setMode = "set_mode"
    case takeoff
    case rtl
    case pause
    case land
    case startMission = "start_mission"
    case emergencyStop = "emergency_stop"
    case setActive = "set_active"
}
