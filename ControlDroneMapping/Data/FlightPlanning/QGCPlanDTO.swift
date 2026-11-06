import Foundation

struct QGCSurveyRequestDTO: Encodable {
    struct CoordinateDTO: Encodable {
        let latitude: Double
        let longitude: Double
    }

    struct ParametersDTO: Encodable {
        let altitude: Double
        let speed: Double
        let ascentSpeed: Double
        let descentSpeed: Double
        let holdSeconds: Double
        let gridAngle: Double
        let spacing: Double?
        let triggerDistance: Double?
        let turnaroundDistance: Double
        let hoverAndCapture: Bool
        let useCameraOverlap: Bool
        let frontalOverlap: Double
        let sideOverlap: Double
        let cameraBrand: String
        let cameraSpec: CameraOpticalSpec?
        let firmwareType: Int
        let vehicleType: Int
        let entryLocation: Int
    }

    struct GeofenceDTO: Encodable {
        let enabled: Bool
        let type: String
        let bufferMeters: Double
        let radiusMeters: Double
        let ceilingMeters: Double
        let breachAction: String
    }

    let boundary: [CoordinateDTO]
    let home: CoordinateDTO?
    let returnToHome: Bool
    let parameters: ParametersDTO
    let geofence: GeofenceDTO

    init(boundary: [MapCoordinate], parameters: SurveyScanParameters) {
        self.boundary = boundary.map { CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude) }
        if let home = parameters.home, home.isValid {
            self.home = CoordinateDTO(latitude: home.latitude, longitude: home.longitude)
        } else {
            self.home = nil
        }
        self.returnToHome = parameters.returnToHome
        self.parameters = ParametersDTO(
            altitude: parameters.altitude,
            speed: parameters.speed,
            ascentSpeed: parameters.ascentSpeed,
            descentSpeed: parameters.descentSpeed,
            holdSeconds: parameters.holdSeconds,
            gridAngle: parameters.gridAngle,
            spacing: parameters.spacing,
            triggerDistance: parameters.triggerDistance,
            turnaroundDistance: parameters.turnaroundDistance,
            hoverAndCapture: parameters.hoverAndCapture,
            useCameraOverlap: parameters.useCameraOverlap,
            frontalOverlap: parameters.frontalOverlap,
            sideOverlap: parameters.sideOverlap,
            cameraBrand: parameters.cameraBrand,
            cameraSpec: parameters.cameraSpec,
            firmwareType: parameters.firmware.mavAutopilot,
            vehicleType: parameters.vehicleType,
            entryLocation: parameters.entryLocation
        )
        self.geofence = GeofenceDTO(
            enabled: parameters.geofence.enabled,
            type: parameters.geofence.type.rawValue,
            bufferMeters: parameters.geofence.bufferMeters,
            radiusMeters: parameters.geofence.radiusMeters,
            ceilingMeters: parameters.geofence.ceilingMeters,
            breachAction: parameters.geofence.breachAction.rawValue
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
                transectCount: s["transectCount"] as? Int ?? 0,
                waypointCount: s["waypointCount"] as? Int ?? 0,
                holdTimeSeconds: s["holdTimeSeconds"] as? Double ?? 0.0,
                maxMissionAltitude: s["maxMissionAltitude"] as? Double ?? 0.0,
                calculatedLineSpacing: s["calculatedLineSpacing"] as? Double ?? 0.0,
                calculatedTriggerDistance: s["calculatedTriggerDistance"] as? Double ?? 0.0,
                groundResolutionCmPerPx: s["groundResolutionCmPerPx"] as? Double ?? 0.0
            )
        }

        // Parse safety / geofence validation result from QGC
        var safetyResult: SurveySafetyResult? = nil
        if let sf = json["safety"] as? [String: Any] {
            let enabled = sf["enabled"] as? Bool ?? false
            let typeStr = sf["type"] as? String ?? "polygon"
            let gfType = GeofenceType(rawValue: typeStr) ?? .polygon
            let actionStr = sf["breachAction"] as? String ?? "rtl"
            let gfAction = GeofenceBreachAction(rawValue: actionStr) ?? .rtl

            var polyCoords: [MapCoordinate] = []
            if let polyArr = sf["polygon"] as? [[String: Any]] {
                for pt in polyArr {
                    if let lat = pt["latitude"] as? Double, let lon = pt["longitude"] as? Double {
                        polyCoords.append(MapCoordinate(latitude: lat, longitude: lon))
                    }
                }
            }

            var circleCenter: MapCoordinate? = nil
            var circleRadius: Double = sf["radiusMeters"] as? Double ?? 0.0
            if let circleObj = sf["circle"] as? [String: Any] {
                if let cObj = circleObj["center"] as? [String: Any],
                   let lat = cObj["latitude"] as? Double,
                   let lon = cObj["longitude"] as? Double {
                    circleCenter = MapCoordinate(latitude: lat, longitude: lon)
                }
                if let r = circleObj["radiusMeters"] as? Double {
                    circleRadius = r
                }
            }

            var brPoint: MapCoordinate? = nil
            var brAlt: Double = 0.0
            if let brObj = sf["breachReturnPoint"] as? [String: Any],
               let lat = brObj["latitude"] as? Double,
               let lon = brObj["longitude"] as? Double {
                brPoint = MapCoordinate(latitude: lat, longitude: lon)
                brAlt = brObj["altitude"] as? Double ?? 0.0
            }

            var issues: [SafetyIssue] = []
            if let rawIssues = sf["issues"] as? [[String: Any]] {
                for item in rawIssues {
                    if let code = item["code"] as? String, let message = item["message"] as? String {
                        issues.append(SafetyIssue(code: code, message: message))
                    }
                }
            }

            safetyResult = SurveySafetyResult(
                enabled: enabled,
                type: gfType,
                bufferMeters: sf["bufferMeters"] as? Double ?? 0.0,
                radiusMeters: circleRadius,
                ceilingMeters: sf["ceilingMeters"] as? Double ?? 0.0,
                breachAction: gfAction,
                coversMission: sf["coversMission"] as? Bool ?? false,
                homeInside: sf["homeInside"] as? Bool ?? false,
                uncoveredPointCount: sf["uncoveredPointCount"] as? Int ?? 0,
                ceilingOk: sf["ceilingOk"] as? Bool ?? false,
                polygonCoordinates: polyCoords,
                circleCenter: circleCenter,
                circleRadiusMeters: circleRadius,
                breachReturnPoint: brPoint,
                breachReturnAltitude: brAlt,
                issues: issues
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
            safety: safetyResult,
            rawPlanData: rawPlan
        )
    }
}
