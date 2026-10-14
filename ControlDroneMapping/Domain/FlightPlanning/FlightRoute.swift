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
    var defaultAltitude = 80.0
    var takeoffAltitude = 20.0
    var speed = 5.0
    var returnToHome = true
    var waypoints: [FlightWaypoint] = []

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
}

protocol FlightRouteRepository {
    func load() throws -> [FlightRoute]
    func save(_ routes: [FlightRoute]) throws
}
