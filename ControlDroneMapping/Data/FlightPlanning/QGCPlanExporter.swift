import Foundation

/// Plan v1 / mission v2, SimpleItems only. Never uploads or arms a vehicle.
/// Optional altitude UI fields are omitted: QGC derives relative altitude from MAV_FRAME=3.
struct QGCPlanExporter {
    static func data(for route: FlightRoute) throws -> Data {
        try route.validateForExport()
        guard let home = route.home, let elevation = route.homeAltitudeAMSL, let firmware = route.firmware
        else { throw MappingError.invalid("Home belum lengkap") }
        func item(command: Int, frame: Int, params: [Any], index: Int) -> [String: Any] {
            [
                "type": "SimpleItem", "command": command, "frame": frame, "autoContinue": true,
                "doJumpId": index, "params": params,
            ]
        }
        // A takeoff followed by explicit ground-speed selection for the supported multicopter profiles.
        var items = [
            item(
                command: 22, frame: 3,
                params: [0, 0, 0, NSNull(), home.latitude, home.longitude, route.takeoffAltitude], index: 1),
            item(command: 178, frame: 2, params: [1, route.speed, -1, 0, 0, 0, 0], index: 2),
        ]
        for point in route.waypoints {
            items.append(
                item(
                    command: 16, frame: 3,
                    params: [
                        0, 0, 0, NSNull(), point.coordinate.latitude, point.coordinate.longitude,
                        point.altitude,
                    ], index: items.count + 1))
        }
        if route.returnToHome {
            items.append(item(command: 20, frame: 2, params: [0, 0, 0, 0, 0, 0, 0], index: items.count + 1))
        }
        let document: [String: Any] = [
            "fileType": "Plan", "groundStation": "QGroundControl", "version": 1,
            "geoFence": ["circles": [], "polygons": [], "version": 2] as [String: Any],
            "rallyPoints": ["points": [], "version": 2] as [String: Any],
            "mission": [
                "version": 2, "firmwareType": firmware.mavAutopilot, "vehicleType": 2,
                "globalPlanAltitudeMode": 1, "cruiseSpeed": route.speed, "hoverSpeed": route.speed,
                "plannedHomePosition": [home.latitude, home.longitude, elevation], "items": items,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }
}
