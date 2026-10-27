import Foundation

struct QGCSurveyRequestDTO: Encodable {
    struct CoordinateDTO: Encodable {
        let latitude: Double
        let longitude: Double
    }

    struct ParametersDTO: Encodable {
        let altitude: Double
        let speed: Double
        let gridAngle: Double
        let spacing: Double?
        let triggerDistance: Double?
        let turnaroundDistance: Double
        let hoverAndCapture: Bool
        let useCameraOverlap: Bool
        let frontalOverlap: Double
        let sideOverlap: Double
        let cameraBrand: String
        let firmwareType: Int
        let vehicleType: Int
        let entryLocation: Int
    }

    let boundary: [CoordinateDTO]
    let parameters: ParametersDTO

    init(boundary: [MapCoordinate], parameters: SurveyScanParameters) {
        self.boundary = boundary.map { CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude) }
        self.parameters = ParametersDTO(
            altitude: parameters.altitude,
            speed: parameters.speed,
            gridAngle: parameters.gridAngle,
            spacing: parameters.spacing,
            triggerDistance: parameters.triggerDistance,
            turnaroundDistance: parameters.turnaroundDistance,
            hoverAndCapture: parameters.hoverAndCapture,
            useCameraOverlap: parameters.useCameraOverlap,
            frontalOverlap: parameters.frontalOverlap,
            sideOverlap: parameters.sideOverlap,
            cameraBrand: parameters.cameraBrand,
            firmwareType: parameters.firmware.mavAutopilot,
            vehicleType: parameters.vehicleType,
            entryLocation: parameters.entryLocation
        )
    }
}

enum QGCSurveyResponseParser {
    static func parse(data: Data) throws -> SurveyScanResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalid("Respon dari QGC bukan JSON yang valid.")
        }

        guard let status = json["status"] as? String, status == "ok" else {
            let msg = json["message"] as? String ?? "Terjadi kesalahan pada mesin QGC."
            throw MappingError.invalid(msg)
        }

        // Parse visual transect coordinates
        var coordinates: [MapCoordinate] = []
        if let points = json["visualTransectPoints"] as? [[String: Any]] {
            for pt in points {
                if let lat = pt["latitude"] as? Double, let lon = pt["longitude"] as? Double {
                    coordinates.append(MapCoordinate(latitude: lat, longitude: lon))
                }
            }
        }

        // Parse statistics
        var stats = SurveyScanStatistics()
        if let s = json["statistics"] as? [String: Any] {
            stats = SurveyScanStatistics(
                totalDistanceMeters: s["totalDistanceMeters"] as? Double ?? 0.0,
                flightTimeSeconds: s["flightTimeSeconds"] as? Double ?? 0.0,
                coveredAreaSquareMeters: s["coveredAreaSquareMeters"] as? Double ?? 0.0,
                photoCount: s["photoCount"] as? Int ?? 0,
                transectCount: s["transectCount"] as? Int ?? 0
            )
        }

        // Extract raw plan data
        var rawPlan = Data()
        if let plan = json["plan"] as? [String: Any] {
            rawPlan = (try? JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        }

        return SurveyScanResult(
            visualTransectPoints: coordinates,
            statistics: stats,
            rawPlanData: rawPlan
        )
    }
}
