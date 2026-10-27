import Foundation

struct MapCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
    func distance(to other: MapCoordinate) -> Double {
        let radians = Double.pi / 180
        let dLat = (other.latitude - latitude) * radians
        let dLon = (other.longitude - longitude) * radians
        let a =
            pow(sin(dLat / 2), 2) + cos(latitude * radians) * cos(other.latitude * radians)
            * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }

    /// Projects this coordinate to the closest point along the perimeter segments of a polygon.
    func closestPointOnPolygonPerimeter(_ polygon: [MapCoordinate]) -> MapCoordinate {
        guard !polygon.isEmpty else { return self }
        guard polygon.count >= 2 else { return polygon[0] }

        var bestCoord = polygon[0]
        var minDistanceMeters = Double.infinity

        let latRad = latitude * .pi / 180.0
        let cosLat = cos(latRad)
        let metersPerDegLat = 111_132.954 - 559.822 * cos(2 * latRad) + 1.175 * cos(4 * latRad)
        let metersPerDegLon = 111_412.84 * cosLat - 93.5 * cos(3 * latRad)

        func toMeters(_ c: MapCoordinate) -> (x: Double, y: Double) {
            (
                x: (c.longitude - longitude) * metersPerDegLon,
                y: (c.latitude - latitude) * metersPerDegLat
            )
        }

        func toCoord(x: Double, y: Double) -> MapCoordinate {
            MapCoordinate(
                latitude: latitude + (y / metersPerDegLat),
                longitude: longitude + (x / metersPerDegLon)
            )
        }

        let p = (x: 0.0, y: 0.0)
        let count = polygon.count
        for i in 0..<count {
            let p1 = toMeters(polygon[i])
            let p2 = toMeters(polygon[(i + 1) % count])

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy

            let projX: Double
            let projY: Double
            if lenSq < 1e-9 {
                projX = p1.x
                projY = p1.y
            } else {
                let t = max(0.0, min(1.0, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
                projX = p1.x + t * dx
                projY = p1.y + t * dy
            }

            let dist = hypot(projX - p.x, projY - p.y)
            if dist < minDistanceMeters {
                minDistanceMeters = dist
                bestCoord = toCoord(x: projX, y: projY)
            }
        }

        return bestCoord
    }
}

extension Array where Element == MapCoordinate {
    var perimeterMeters: Double {
        guard count >= 2 else { return 0 }
        let closed = self + [self[0]]
        return zip(closed, closed.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    var areaSquareMeters: Double {
        guard count >= 3 else { return 0 }
        let centerLat = reduce(0.0) { $0 + $1.latitude } / Double(count)
        let latRad = centerLat * .pi / 180.0
        let metersPerLat = 111_132.95
        let metersPerLon = 111_412.84 * cos(latRad)

        var area: Double = 0
        for i in 0..<count {
            let j = (i + 1) % count
            let xi = (self[i].longitude) * metersPerLon
            let yi = (self[i].latitude) * metersPerLat
            let xj = (self[j].longitude) * metersPerLon
            let yj = (self[j].latitude) * metersPerLat
            area += (xi * yj - xj * yi)
        }
        return abs(area) * 0.5
    }

    var areaHectares: Double {
        areaSquareMeters / 10_000.0
    }
}

enum FlightFirmware: String, Codable, CaseIterable, Identifiable {
    case ardupilot, px4
    var id: String { rawValue }
    var title: String { self == .ardupilot ? "ArduPilot Copter" : "PX4 Multicopter" }
    var mavAutopilot: Int { self == .ardupilot ? 3 : 12 }
}

struct FlightWaypoint: Codable, Equatable, Identifiable {
    var id = UUID()
    var coordinate: MapCoordinate
    var altitude: Double
}

/// Flight routes are independent of the iPhone acquisition MissionPlan.
struct FlightRoute: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "Rute baru"
    var farmID: UUID?
    var missionID: UUID?
    var createdAt = Date()
    var firmware: FlightFirmware?
    var home: MapCoordinate?
    var homeAltitudeAMSL: Double?
    var surveyEntry: MapCoordinate?
    var defaultAltitude = 80.0
    var takeoffAltitude = 20.0
    var speed = 5.0
    var returnToHome = true
    var waypoints: [FlightWaypoint] = []
    var gridAngle = 0.0
    var lineSpacing = 20.0
    var triggerDistance = 15.0
    var turnaroundDistance = 10.0
    var entryLocation = 0
    var visualTransects: [MapCoordinate] = []
    var surveyStatistics: SurveyScanStatistics? = nil
    var rawPlanJSON: Data? = nil

    func validateForExport() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100 else {
            throw MappingError.invalid("Beri nama rute, maksimal 100 karakter.")
        }
        guard firmware != nil else {
            throw MappingError.invalid("Pilih profil firmware multicopter sesuai QGroundControl.")
        }
        guard let home, home.isValid else {
            throw MappingError.invalid("Tentukan home pada peta: lokasi lepas landas drone.")
        }
        guard let homeAltitudeAMSL, homeAltitudeAMSL.isFinite, (-500...9000).contains(homeAltitudeAMSL) else {
            throw MappingError.invalid(
                "Isi elevasi home AMSL yang telah diperiksa; lokasi Mac tidak menentukan elevasi drone.")
        }
        guard (1...500).contains(waypoints.count), Set(waypoints.map(\.id)).count == waypoints.count else {
            throw MappingError.invalid("Tambahkan 1–500 waypoint dengan identitas unik.")
        }
        guard speed.isFinite, (0.5...20).contains(speed), defaultAltitude.isFinite,
            (1...500).contains(defaultAltitude), takeoffAltitude.isFinite, (1...500).contains(takeoffAltitude)
        else {
            throw MappingError.invalid(
                "Periksa kecepatan dan tinggi rute/takeoff. Batas input bukan izin operasional penerbangan.")
        }
        for point in waypoints {
            guard point.coordinate.isValid, point.altitude.isFinite, (1...500).contains(point.altitude) else {
                throw MappingError.invalid("Koordinat atau tinggi waypoint tidak valid.")
            }
        }
    }
    var distance: Double {
        let points =
            (home.map { [$0] } ?? []) + waypoints.map(\.coordinate)
            + (returnToHome ? home.map { [$0] } ?? [] : [])
        let valid = points.filter(\.isValid)
        return zip(valid, valid.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    init(
        id: UUID = UUID(),
        name: String = "Rute baru",
        farmID: UUID? = nil,
        missionID: UUID? = nil,
        createdAt: Date = Date(),
        firmware: FlightFirmware? = nil,
        home: MapCoordinate? = nil,
        homeAltitudeAMSL: Double? = nil,
        surveyEntry: MapCoordinate? = nil,
        defaultAltitude: Double = 80.0,
        takeoffAltitude: Double = 20.0,
        speed: Double = 5.0,
        returnToHome: Bool = true,
        waypoints: [FlightWaypoint] = [],
        gridAngle: Double = 0.0,
        lineSpacing: Double = 20.0,
        triggerDistance: Double = 15.0,
        turnaroundDistance: Double = 10.0,
        entryLocation: Int = 0,
        visualTransects: [MapCoordinate] = [],
        surveyStatistics: SurveyScanStatistics? = nil,
        rawPlanJSON: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.farmID = farmID
        self.missionID = missionID
        self.createdAt = createdAt
        self.firmware = firmware
        self.home = home
        self.homeAltitudeAMSL = homeAltitudeAMSL
        self.surveyEntry = surveyEntry
        self.defaultAltitude = defaultAltitude
        self.takeoffAltitude = takeoffAltitude
        self.speed = speed
        self.returnToHome = returnToHome
        self.waypoints = waypoints
        self.gridAngle = gridAngle
        self.lineSpacing = lineSpacing
        self.triggerDistance = triggerDistance
        self.turnaroundDistance = turnaroundDistance
        self.entryLocation = entryLocation
        self.visualTransects = visualTransects
        self.surveyStatistics = surveyStatistics
        self.rawPlanJSON = rawPlanJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Rute baru"
        farmID = try container.decodeIfPresent(UUID.self, forKey: .farmID)
        missionID = try container.decodeIfPresent(UUID.self, forKey: .missionID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        firmware = try container.decodeIfPresent(FlightFirmware.self, forKey: .firmware)
        home = try container.decodeIfPresent(MapCoordinate.self, forKey: .home)
        homeAltitudeAMSL = try container.decodeIfPresent(Double.self, forKey: .homeAltitudeAMSL)
        surveyEntry = try container.decodeIfPresent(MapCoordinate.self, forKey: .surveyEntry)
        defaultAltitude = try container.decodeIfPresent(Double.self, forKey: .defaultAltitude) ?? 80.0
        takeoffAltitude = try container.decodeIfPresent(Double.self, forKey: .takeoffAltitude) ?? 20.0
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 5.0
        returnToHome = try container.decodeIfPresent(Bool.self, forKey: .returnToHome) ?? true
        waypoints = try container.decodeIfPresent([FlightWaypoint].self, forKey: .waypoints) ?? []
        gridAngle = try container.decodeIfPresent(Double.self, forKey: .gridAngle) ?? 0.0
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 20.0
        triggerDistance = try container.decodeIfPresent(Double.self, forKey: .triggerDistance) ?? 15.0
        turnaroundDistance = try container.decodeIfPresent(Double.self, forKey: .turnaroundDistance) ?? 10.0
        entryLocation = try container.decodeIfPresent(Int.self, forKey: .entryLocation) ?? 0
        visualTransects = try container.decodeIfPresent([MapCoordinate].self, forKey: .visualTransects) ?? []
        surveyStatistics = try container.decodeIfPresent(SurveyScanStatistics.self, forKey: .surveyStatistics)
        rawPlanJSON = try container.decodeIfPresent(Data.self, forKey: .rawPlanJSON)
    }
}

protocol FlightRouteRepository {
    func load() throws -> [FlightRoute]
    func save(_ routes: [FlightRoute]) throws
}

final class InMemoryFlightRouteRepository: FlightRouteRepository {
    private var routes: [FlightRoute]
    init(routes: [FlightRoute] = []) { self.routes = routes }
    func load() throws -> [FlightRoute] { routes }
    func save(_ routes: [FlightRoute]) throws { self.routes = routes }
}

struct SurveyScanStatistics: Codable, Equatable, Sendable {
    var totalDistanceMeters: Double = 0.0
    var flightTimeSeconds: Double = 0.0
    var coveredAreaSquareMeters: Double = 0.0
    var photoCount: Int = 0
    var transectCount: Int = 0
}

struct SurveyScanResult: Sendable {
    var visualTransectPoints: [MapCoordinate] = []
    var statistics: SurveyScanStatistics = SurveyScanStatistics()
    var rawPlanData: Data = Data()
}
