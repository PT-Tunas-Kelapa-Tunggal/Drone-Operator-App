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
    static func main() throws {
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
        let output = directory.appendingPathComponent("Kebun uji.plan")
        planner.export(to: output)
        check(
            planner.exportedURL == output && FileManager.default.fileExists(atPath: output.path),
            "Export writes a local file without any flight transport")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as! [String: Any]
        let mission = object["mission"] as! [String: Any]
        let items = mission["items"] as! [[String: Any]]
        check(
            object["fileType"] as? String == "Plan" && object["version"] as? Int == 1
                && mission["version"] as? Int == 2, "QGC document and mission versions are correct")
        check(
            mission["firmwareType"] as? Int == 3 && mission["vehicleType"] as? Int == 2,
            "ArduPilot multicopter profile is explicit")
        check(
            mission["plannedHomePosition"] as? [Double] == [1.05, 104.45, 35],
            "Home stores latitude, longitude, then AMSL without coordinate inversion")
        check(
            items.map { $0["command"] as! Int } == [22, 178, 16, 16, 20],
            "Takeoff, speed, ordered waypoints and RTL are exported")
        check(
            items.map { $0["doJumpId"] as! Int } == [1, 2, 3, 4, 5], "Mission sequence IDs remain contiguous")
        let nav = items.filter { [16, 22].contains($0["command"] as! Int) }
        check(
            nav.allSatisfy { $0["frame"] as? Int == 3 && $0["AltitudeMode"] == nil },
            "Navigation frame defines relative altitude without version-dependent UI enum fields")
        check(
            nav.allSatisfy { ($0["params"] as! [Any]).count == 7 && ($0["params"] as! [Any])[3] is NSNull },
            "Navigation keeps seven MAVLink parameters and unspecified yaw as JSON null")
        check(
            (items[1]["params"] as! [Double])[0...2] == [1, 5, -1],
            "Ground speed command has explicit speed and unchanged throttle")
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
        let px4 =
            try JSONSerialization.jsonObject(with: QGCPlanExporter.data(for: planner.draft)) as! [String: Any]
        let px4Mission = px4["mission"] as! [String: Any]
        check(
            px4Mission["firmwareType"] as? Int == 12 && (px4Mission["items"] as! [[String: Any]]).count == 4,
            "PX4 profile and optional RTL serialize without hidden defaults")
        var invalid = planner.draft
        invalid.firmware = nil
        reject("Missing firmware rejected") { _ = try QGCPlanExporter.data(for: invalid) }
        invalid = planner.draft
        invalid.homeAltitudeAMSL = nil
        reject("Unknown home elevation rejected") { _ = try QGCPlanExporter.data(for: invalid) }
        invalid = planner.draft
        invalid.waypoints[0].coordinate.latitude = 91
        reject("Invalid latitude rejected") { _ = try QGCPlanExporter.data(for: invalid) }
        invalid = planner.draft
        invalid.waypoints[0].altitude = .nan
        reject("Nonfinite waypoint height rejected") { _ = try QGCPlanExporter.data(for: invalid) }
        invalid = planner.draft
        invalid.waypoints[1].id = invalid.waypoints[0].id
        reject("Duplicate waypoint identity rejected") { _ = try QGCPlanExporter.data(for: invalid) }
        invalid = planner.draft
        invalid.speed = .infinity
        reject("Nonfinite speed rejected") { _ = try QGCPlanExporter.data(for: invalid) }
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
        print(
            "PASS: \(checks) flight-planner and operator-location assertions (no QGC upload or physical flight)"
        )
    }
}
