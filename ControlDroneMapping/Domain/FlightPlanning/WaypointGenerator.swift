import Foundation

/// Defines the contract for generating autonomous survey waypoints.
/// Implementations may communicate with an embedded QGC engine,
/// an external flight service, or provide synthetic/mock transects for testing.
protocol WaypointGenerator: Sendable {
    func generateWaypoints(
        boundary: [MapCoordinate],
        parameters: SurveyScanParameters
    ) async throws -> SurveyScanResult
}
