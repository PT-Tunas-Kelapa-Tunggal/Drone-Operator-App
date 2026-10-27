import AppKit
import Foundation

private final class FakeLocation: OperatorLocationProviding {
    var onUpdate: ((OperatorLocationState) -> Void)?
    var requests = 0
    func request() {
        requests += 1
        onUpdate?(.locating)
    }
}
private final class FakeFarmRepository: FarmAreaRepository {
    var areas: [FarmArea] = []
    func importFile(_ input: URL) throws {}
}
@main enum FlightPlannerTests {
    static func main() async throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: Bool, _ title: String) {
            precondition(condition, title)
            checks += 1
        }
        func reject(_ title: String, _ body: () throws -> Void) {
            do {
                try body()
                preconditionFailure(title)
            } catch { checks += 1 }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "flight-planner-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileFlightRouteRepository(url: directory.appendingPathComponent("routes.json"))
        let planner = FlightPlannerViewModel(repository: repository)
        check(
            planner.routes.isEmpty && planner.draft.firmware == nil,
            "No invented route or firmware on startup")
        planner.newRoute(farm: nil, name: "Kebun uji", altitude: 80, speed: 5)
        check(
            planner.routes.count == 1 && planner.mode == .home && planner.exportBlocker != nil,
            "Route starts locally without iPhone and cannot export incomplete data")
        planner.mapClick(MapCoordinate(latitude: 1.05, longitude: 104.45))
        check(
            planner.draft.home?.latitude == 1.05 && planner.mode == .waypoint
                && planner.draft.homeAltitudeAMSL == nil, "Manual home does not invent AMSL elevation")
        planner.mapClick(MapCoordinate(latitude: 1.051, longitude: 104.451))
        planner.mapClick(MapCoordinate(latitude: 1.052, longitude: 104.451))
        check(
            planner.draft.waypoints.count == 2 && planner.draft.waypoints.allSatisfy { $0.altitude == 80 },
            "Map click adds ordered waypoints at configured relative height")
        let firstID = planner.draft.waypoints[0].id
        planner.reorder(firstID, offset: 1)
        check(planner.draft.waypoints[1].id == firstID, "Reorder preserves stable waypoint identity")
        planner.undo()
        check(planner.draft.waypoints[0].id == firstID, "Undo restores waypoint order")
        planner.removeWaypoint(firstID)
        planner.undo()
        check(
            planner.draft.waypoints.count == 2 && planner.draft.waypoints[0].id == firstID,
            "Waypoint deletion is reversible")
        planner.draft.firmware = .ardupilot
        planner.draft.homeAltitudeAMSL = 35
        check(planner.exportBlocker != nil, "Valid geometry still requires operator review")
        planner.reviewed = true
        check(planner.exportBlocker == nil, "Review and complete route permit file export")

        // 1. Test MockWaypointGenerator and survey generation
        let mockGenerator = MockWaypointGenerator()
        let scanParams = SurveyScanParameters(altitude: 50, speed: 5, gridAngle: 45)
        let boundary = [
            MapCoordinate(latitude: 1.05, longitude: 104.45),
            MapCoordinate(latitude: 1.055, longitude: 104.45),
            MapCoordinate(latitude: 1.055, longitude: 104.455),
            MapCoordinate(latitude: 1.05, longitude: 104.455),
        ]
        let res = try await mockGenerator.generateWaypoints(boundary: boundary, parameters: scanParams)
        check(!res.visualTransectPoints.isEmpty, "Mock waypoint generator generates transect points")
        check(res.statistics.transectCount > 0, "Mock generator returns transect count")

        // 1b. Test FlightPlannerViewModel survey waypoint generation with line spacing and entry
        let surveyPlanner = FlightPlannerViewModel(repository: repository, waypointGenerator: mockGenerator)
        surveyPlanner.draft.waypoints = boundary.map { FlightWaypoint(coordinate: $0, altitude: 50) }

        // Test manual entry selection in .entry mode snapping to polygon perimeter
        surveyPlanner.mode = .entry
        let clickOutsideWest = MapCoordinate(latitude: 1.052, longitude: 104.44)
        surveyPlanner.mapClick(clickOutsideWest)
        check(surveyPlanner.draft.surveyEntry != nil, "Entry is set on map click in entry mode")
        check(
            abs((surveyPlanner.draft.surveyEntry?.longitude ?? 0) - 104.45) < 0.0001,
            "Entry coordinate snaps to west edge of farm boundary"
        )

        // Test moving entry along the boundary
        let clickNorthEdge = MapCoordinate(latitude: 1.058, longitude: 104.452)
        surveyPlanner.moveEntry(to: clickNorthEdge)
        check(
            abs((surveyPlanner.draft.surveyEntry?.latitude ?? 0) - 1.055) < 0.0001,
            "Moved entry coordinate snaps to north edge of farm boundary"
        )

        await surveyPlanner.generateSurveyWaypoints(
            altitude: 60,
            speed: 6,
            gridAngle: 90,
            lineSpacing: 25,
            triggerDistance: 12,
            turnaroundDistance: 8
        )
        check(!surveyPlanner.draft.visualTransects.isEmpty, "Planner generates visual transects")
        check(surveyPlanner.draft.lineSpacing == 25, "Planner stores lineSpacing")
        check(surveyPlanner.draft.triggerDistance == 12, "Planner stores triggerDistance")
        check(surveyPlanner.draft.turnaroundDistance == 8, "Planner stores turnaroundDistance")
        check(surveyPlanner.draft.surveyEntry != nil, "Planner retains entry on boundary")

        // 2. Test QGCSurveyResponseParser with real JSON
        let sampleQGCJson = """
        {
          "status": "ok",
          "statistics": {
            "totalDistanceMeters": 1500.5,
            "flightTimeSeconds": 300.0,
            "coveredAreaSquareMeters": 25000.0,
            "photoCount": 60,
            "transectCount": 8
          },
          "visualTransectPoints": [
            {"latitude": 1.051, "longitude": 104.451},
            {"latitude": 1.052, "longitude": 104.452}
          ],
          "plan": {
            "fileType": "Plan",
            "groundStation": "QGroundControl",
            "version": 1,
            "mission": {"version": 2, "items": []}
          }
        }
        """
        let parsedResult = try QGCSurveyResponseParser.parse(data: Data(sampleQGCJson.utf8))
        check(parsedResult.visualTransectPoints.count == 2, "Parser extracts visual transect points")
        check(parsedResult.statistics.photoCount == 60, "Parser extracts statistics")
        check(!parsedResult.rawPlanData.isEmpty, "Parser extracts raw plan JSON")

        let output = directory.appendingPathComponent("Kebun uji.plan")
        planner.draft.rawPlanJSON = parsedResult.rawPlanData
        planner.reviewed = true
        planner.export(to: output)
        check(
            planner.exportedURL == output && FileManager.default.fileExists(atPath: output.path),
            "Export writes a local file without any flight transport")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as! [String: Any]
        check(
            object["fileType"] as? String == "Plan" && object["version"] as? Int == 1,
            "QGC document fileType and version are correct")
        check(
            planner.draft.distance > 250 && planner.draft.distance < 2000,
            "Route distance includes return leg")
        let restored = FlightPlannerViewModel(repository: repository)
        check(
            restored.draft.id == planner.draft.id
                && restored.draft.waypoints.map(\.id) == planner.draft.waypoints.map(\.id)
                && !restored.reviewed, "Restart retains route identities and requires fresh operator review")
        planner.moveWaypoint(firstID, to: MapCoordinate(latitude: 1.053, longitude: 104.452))
        check(
            !planner.reviewed && planner.exportedURL == nil,
            "Waypoint movement invalidates review and exported-file status")
        planner.draft.defaultAltitude = 60
        planner.applyAltitudeToAll()
        check(
            planner.draft.waypoints.allSatisfy { $0.altitude == 60 },
            "Explicit altitude update changes all waypoints")
        planner.draft.firmware = .px4
        planner.draft.returnToHome = false
        try planner.draft.validateForExport()
        check(planner.draft.firmware?.mavAutopilot == 12, "PX4 profile firmwareType is 12")
        var invalid = planner.draft
        invalid.firmware = nil
        reject("Missing firmware rejected") { try invalid.validateForExport() }
        invalid = planner.draft
        invalid.homeAltitudeAMSL = nil
        reject("Unknown home elevation rejected") { try invalid.validateForExport() }
        invalid = planner.draft
        invalid.waypoints[0].coordinate.latitude = 91
        reject("Invalid latitude rejected") { try invalid.validateForExport() }
        invalid = planner.draft
        invalid.waypoints[0].altitude = .nan
        reject("Nonfinite waypoint height rejected") { try invalid.validateForExport() }
        invalid = planner.draft
        invalid.waypoints[1].id = invalid.waypoints[0].id
        reject("Duplicate waypoint identity rejected") { try invalid.validateForExport() }
        invalid = planner.draft
        invalid.speed = .infinity
        reject("Nonfinite speed rejected") { try invalid.validateForExport() }
        let previousFile = try Data(contentsOf: repository.url!)
        planner.draft.speed = .nan
        let retainedFile = try Data(contentsOf: repository.url!)
        check(
            planner.storageError != nil && retainedFile == previousFile,
            "Failed JSON encoding preserves the previous atomic draft file")
        planner.draft.speed = 5
        check(planner.storageError == nil, "Correcting invalid values restores persistence")

        let service = FakeLocation()
        let location = OperatorLocationViewModel(service: service)
        check(
            service.requests == 0 && location.sample == nil,
            "Location is not requested at application initialization")
        location.request()
        check(
            service.requests == 1 && location.state == .locating,
            "Only an explicit user action requests location")
        let focus = location.focusRequest
        let sample = OperatorLocationSample(
            coordinate: MapCoordinate(latitude: 1.05, longitude: 104.45), accuracy: 200, timestamp: Date())
        service.onUpdate?(.available(sample))
        check(
            location.sample == sample && location.focusRequest != focus && location.status.contains("200"),
            "Valid fix updates accuracy and issues a one-shot map focus")
        location.expire(now: Date().addingTimeInterval(121))
        check(
            location.sample == nil && service.requests == 1,
            "Expired location publishes an unavailable state without requesting background tracking")
        service.onUpdate?(
            .available(
                OperatorLocationSample(
                    coordinate: sample.coordinate, accuracy: 200, timestamp: Date().addingTimeInterval(-121)))
        )
        check(location.sample == nil, "Stale operator coordinates cannot be treated as current")
        service.onUpdate?(.denied)
        check(
            location.sample == nil && location.status.contains("Izin lokasi ditolak"),
            "Permission denial leaves planning available without a fake position")
        check(
            !OperatorLocationSample(coordinate: sample.coordinate, accuracy: -1, timestamp: Date())
                .isUsable(), "Invalid location accuracy rejected")
        let farms = FakeFarmRepository()
        farms.areas = [
            FarmArea(name: "Dekat", points: [.init(latitude: 1.05, longitude: 104.45)]),
            FarmArea(name: "Jauh", points: [.init(latitude: 2, longitude: 104.45)]),
        ]
        let farmModel = FarmAreaViewModel(repository: farms)
        check(
            farmModel.nearbyAreas(center: sample.coordinate, radiusKm: 10).map(\.name) == ["Dekat"],
            "Nearby filtering uses real persisted fields and operator coordinates")
        check(
            farmModel.nearbyAreas(center: nil, radiusKm: 10).count == 2
                && farmModel.nearbyAreas(center: sample.coordinate, radiusKm: 0).count == 2,
            "Missing location and All filter retain accessible fields")
        let coordinateFormat: FloatingPointFormatStyle<Double> = .number.locale(
            Locale(identifier: "en_US_POSIX")
        ).grouping(
            .never
        ).precision(.fractionLength(0...7))
        let latitude = try coordinateFormat.parseStrategy.parse("1.05")
        let longitude = try coordinateFormat.parseStrategy.parse("104.45")
        check(
            latitude == 1.05 && longitude == 104.45,
            "Decimal coordinate parser never treats the decimal point as a thousands separator")
        planner.moveWaypoint(firstID, to: MapCoordinate(latitude: 91, longitude: 104.45))
        planner.reviewed = true
        check(
            planner.draft.waypoints.first { $0.id == firstID }?.coordinate.latitude == 91
                && planner.exportBlocker != nil,
            "Invalid coordinate edit remains visible and blocks export instead of silently using a previous valid coordinate"
        )
        let firstMission = UUID()
        let secondMission = UUID()
        let sharedFarm = FarmArea(name: "Kebun bersama", points: [])
        planner.open(farm: sharedFarm, name: "Rute A", altitude: 72, missionID: firstMission)
        let firstRoute = planner.draft.id
        planner.draft.home = MapCoordinate(latitude: -6, longitude: 106)
        planner.open(farm: sharedFarm, name: "Rute B", altitude: 93, missionID: secondMission)
        check(
            planner.draft.id != firstRoute && planner.draft.missionID == secondMission
                && planner.draft.home == nil,
            "Two missions in the same farm receive independent routes")
        let missionPlanner = FlightPlannerViewModel(repository: repository)
        missionPlanner.open(farm: sharedFarm, missionID: firstMission)
        check(
            missionPlanner.draft.id == firstRoute && missionPlanner.draft.home?.latitude == -6,
            "Mission route association and edits survive restart")
        planner.open(farm: sharedFarm)
        check(
            planner.draft.missionID == nil && planner.draft.id != firstRoute,
            "Standalone planning cannot accidentally edit a mission's route")

        // 2-step workflow and boundary metrics checks
        let farmBoundary = FarmArea(
            name: "Kebun Polygon",
            points: [
                FarmArea.Point(latitude: -6.000, longitude: 106.000),
                FarmArea.Point(latitude: -6.000, longitude: 106.001),
                FarmArea.Point(latitude: -6.001, longitude: 106.001),
                FarmArea.Point(latitude: -6.001, longitude: 106.000)
            ]
        )
        let stepPlanner = FlightPlannerViewModel(repository: InMemoryFlightRouteRepository())
        stepPlanner.open(farm: farmBoundary)
        check(stepPlanner.planningStep == .boundary, "Opens in boundary step when no survey has been generated")
        check(stepPlanner.draft.waypoints.count == 4, "Initial boundary loaded from farm")
        check(stepPlanner.boundaryAreaHectares > 1.0, "Boundary area calculated in hectares")
        check(stepPlanner.boundaryPerimeterMeters > 300, "Boundary perimeter calculated in meters")
        check(!stepPlanner.canResetToFarm, "Cannot reset when boundary matches farm")

        // Edit boundary and test invalidation, ordering, and reset
        stepPlanner.addWaypoint(MapCoordinate(latitude: -6.0005, longitude: 106.0005))
        check(stepPlanner.draft.waypoints.count == 5, "Added boundary point")
        let newPointID = stepPlanner.draft.waypoints[4].id
        stepPlanner.moveWaypointOrder(newPointID, toIndex: 2)
        check(stepPlanner.draft.waypoints[2].id == newPointID, "Point moved from position 5 to position 3")
        stepPlanner.undo()
        check(stepPlanner.draft.waypoints[4].id == newPointID, "Undo restores point to position 5")
        check(stepPlanner.canResetToFarm, "Can reset to farm after boundary edited")
        stepPlanner.resetToFarm()
        check(stepPlanner.draft.waypoints.count == 4, "Reset restores original 4 boundary points")
        check(!stepPlanner.canResetToFarm, "Cannot reset after reverting")

        print(
            "PASS: \(checks) flight-planner and operator-location assertions (no QGC upload or physical flight)"
        )
    }
}
