import Foundation

/// Mock implementation of WaypointGenerator used for previews, offline development, and unit testing.
final class MockWaypointGenerator: WaypointGenerator, @unchecked Sendable {
    var shouldThrowError: Error?
    var mockResult: SurveyScanResult?

    init(shouldThrowError: Error? = nil, mockResult: SurveyScanResult? = nil) {
        self.shouldThrowError = shouldThrowError
        self.mockResult = mockResult
    }

    func generateWaypoints(
        boundary: [MapCoordinate],
        parameters: SurveyScanParameters
    ) async throws -> SurveyScanResult {
        if let err = shouldThrowError {
            throw err
        }
        if let res = mockResult {
            return res
        }
        guard boundary.count >= 3 else {
            throw MappingError.invalid("Batas survei memerlukan minimal 3 titik koordinat.")
        }

        let lats = boundary.map(\.latitude)
        let lons = boundary.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0

        var points: [MapCoordinate] = []
        let transectCount = 6
        let latStep = (maxLat - minLat) / Double(transectCount)

        for i in 0..<transectCount {
            let lat = minLat + Double(i) * latStep
            if i % 2 == 0 {
                points.append(MapCoordinate(latitude: lat, longitude: minLon))
                points.append(MapCoordinate(latitude: lat, longitude: maxLon))
            } else {
                points.append(MapCoordinate(latitude: lat, longitude: maxLon))
                points.append(MapCoordinate(latitude: lat, longitude: minLon))
            }
        }

        let distanceMeters = zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
        let wpCount = points.count
        let holdTotal = Double(wpCount) * parameters.holdSeconds
        let climbDescent = (parameters.altitude / max(0.5, parameters.ascentSpeed))
            + (parameters.altitude / max(0.5, parameters.descentSpeed))
        let stats = SurveyScanStatistics(
            totalDistanceMeters: distanceMeters,
            flightTimeSeconds: (distanceMeters / max(1.0, parameters.speed)) + climbDescent + holdTotal,
            coveredAreaSquareMeters: (maxLat - minLat) * 111_000 * (maxLon - minLon) * 111_000,
            photoCount: max(1, Int(distanceMeters / 25.0)),
            transectCount: transectCount,
            waypointCount: wpCount,
            holdTimeSeconds: holdTotal,
            maxMissionAltitude: parameters.altitude
        )

        let centerCoord = parameters.home ?? MapCoordinate(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let resolvedRadius = parameters.geofence.radiusMeters > 0 ? parameters.geofence.radiusMeters : 250.0
        let ceilingOk = parameters.altitude <= parameters.geofence.ceilingMeters
        let safety = SurveySafetyResult(
            enabled: parameters.geofence.enabled,
            type: parameters.geofence.type,
            bufferMeters: parameters.geofence.bufferMeters,
            radiusMeters: resolvedRadius,
            ceilingMeters: parameters.geofence.ceilingMeters,
            breachAction: parameters.geofence.breachAction,
            coversMission: parameters.geofence.enabled,
            homeInside: true,
            uncoveredPointCount: 0,
            ceilingOk: ceilingOk,
            polygonCoordinates: boundary,
            circleCenter: centerCoord,
            circleRadiusMeters: resolvedRadius,
            breachReturnPoint: centerCoord,
            breachReturnAltitude: parameters.altitude,
            issues: ceilingOk ? [] : [SafetyIssue(code: "CEILING_EXCEEDED", message: "Tinggi terbang melebihi batas Ceiling.")]
        )

        return SurveyScanResult(
            visualTransectPoints: points,
            statistics: stats,
            safety: safety,
            rawPlanData: Data()
        )
    }
}
