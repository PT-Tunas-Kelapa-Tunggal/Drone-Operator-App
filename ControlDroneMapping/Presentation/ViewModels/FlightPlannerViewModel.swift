import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum FlightMapEditMode: String, CaseIterable, Identifiable {
    case inspect, home, entry, waypoint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inspect: return "Pilih"
        case .home: return "Home"
        case .entry: return "Entry"
        case .waypoint: return "+ Batas"
        }
    }
}

enum FlightPlanningStep: String, CaseIterable, Identifiable {
    case boundary = "Batas Area"
    case flight = "Parameter Terbang"
    var id: String { rawValue }
}

final class FlightPlannerViewModel: ObservableObject {
    @Published private(set) var routes: [FlightRoute] = []
    @Published var draft = FlightRoute() {
        didSet {
            guard !switching, oldValue != draft else { return }
            if !undoing && !continuousEdit {
                undoStack.append(oldValue)
                if undoStack.count > 50 { undoStack.removeFirst() }
            }
            reviewed = false
            exportedURL = nil
            if !continuousEdit { persist() }
        }
    }
    @Published var planningStep: FlightPlanningStep = .boundary
    @Published var mode: FlightMapEditMode = .inspect
    @Published var selectedWaypointID: UUID?
    @Published var reviewed = false
    @Published private(set) var error: String?
    @Published private(set) var storageError: String?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var fitRequest = UUID()
    @Published private(set) var undoStack: [FlightRoute] = []
    @Published public private(set) var isGeneratingWaypoints = false
    private let repository: any FlightRouteRepository
    private let waypointGenerator: any WaypointGenerator
    private var switching = false
    private var continuousEdit = false
    private var undoing = false
    private var storageReady = false

    init(
        repository: any FlightRouteRepository = InMemoryFlightRouteRepository(),
        waypointGenerator: any WaypointGenerator = MockWaypointGenerator()
    ) {
        self.repository = repository
        self.waypointGenerator = waypointGenerator
        routes = (try? repository.load()) ?? []
        storageReady = true
        if let last = routes.last { draft = last }
    }
    private var missionScope: UUID?
    @Published private(set) var currentFarm: FarmArea?

    static func defaultHomeLocation(for points: [FarmArea.Point]) -> MapCoordinate {
        guard let first = points.first else { return MapCoordinate(latitude: 0, longitude: 0) }
        // Offset ~30 meters south-west (-0.00025) so Home doesn't overlap boundary corner 1
        return MapCoordinate(latitude: first.latitude - 0.00025, longitude: first.longitude - 0.00025)
    }

    var baselineRoute: FlightRoute? {
        guard let farm = currentFarm, farm.points.count >= 2 else { return nil }
        var route = FlightRoute(
            id: draft.id,
            name: draft.name,
            farmID: farm.id,
            missionID: missionScope,
            defaultAltitude: draft.defaultAltitude.isFinite && draft.defaultAltitude > 0 ? draft.defaultAltitude : 80,
            speed: draft.speed.isFinite && draft.speed > 0 ? draft.speed : 5
        )
        let alt = route.defaultAltitude
        route.home = Self.defaultHomeLocation(for: farm.points)
        route.waypoints = farm.points.map {
            FlightWaypoint(
                coordinate: MapCoordinate(latitude: $0.latitude, longitude: $0.longitude),
                altitude: alt
            )
        }
        route.returnToHome = true
        route.firmware = draft.firmware
        route.homeAltitudeAMSL = draft.homeAltitudeAMSL
        return route
    }

    var isAtBaseline: Bool {
        guard let baseline = baselineRoute else { return true }
        guard draft.home == baseline.home else { return false }
        guard draft.waypoints.count == baseline.waypoints.count else { return false }
        for (w1, w2) in zip(draft.waypoints, baseline.waypoints) {
            if w1.coordinate != w2.coordinate { return false }
        }
        return true
    }

    var canUndo: Bool {
        !undoStack.isEmpty || !isAtBaseline
    }

    var boundaryAreaHectares: Double {
        activeBoundaryCoordinates().areaHectares
    }

    var boundaryPerimeterMeters: Double {
        activeBoundaryCoordinates().perimeterMeters
    }

    var canResetToFarm: Bool {
        guard let farm = currentFarm, farm.points.count >= 2 else { return false }
        if draft.waypoints.count != farm.points.count { return true }
        for (wp, fp) in zip(draft.waypoints, farm.points) {
            if wp.coordinate.latitude != fp.latitude || wp.coordinate.longitude != fp.longitude {
                return true
            }
        }
        return false
    }

    func resetToFarm() {
        guard let farm = currentFarm, farm.points.count >= 2 else { return }
        let alt = draft.defaultAltitude > 0 ? draft.defaultAltitude : 80
        draft.waypoints = farm.points.map {
            FlightWaypoint(coordinate: MapCoordinate(latitude: $0.latitude, longitude: $0.longitude), altitude: alt)
        }
        draft.visualTransects = []
        draft.surveyStatistics = nil
        draft.rawPlanJSON = nil
        fitRoute()
    }

    func open(
        farm: FarmArea?, name: String = "Rute baru", altitude: Double = 80, speed: Double = 5,
        missionID: UUID? = nil
    ) {
        missionScope = missionID
        currentFarm = farm
        if let saved = routes.last(where: {
            $0.missionID == missionID && (missionID != nil || $0.farmID == farm?.id)
        }) {
            if let farm, farm.points.count >= 2 {
                let matchesFarmCount = saved.waypoints.count == farm.points.count
                let farmHome = Self.defaultHomeLocation(for: farm.points)
                let isNearFarm = saved.home.map { $0.distance(to: farmHome) < 5_000 } ?? false

                if matchesFarmCount && isNearFarm {
                    select(saved.id)
                } else {
                    newRoute(
                        farm: farm, name: farm.name.isEmpty ? name : "Rute " + farm.name,
                        altitude: altitude, speed: speed)
                }
            } else {
                select(saved.id)
            }
        } else {
            newRoute(
                farm: farm, name: farm.map { "Rute " + $0.name } ?? name, altitude: altitude, speed: speed)
        }
        planningStep = draft.visualTransects.isEmpty ? .boundary : .flight
    }
    func newRoute(farm: FarmArea?, name: String, altitude: Double, speed: Double) {
        guard routes.count < 256 else {
            error = "Batas 256 draft rute telah tercapai."
            return
        }
        currentFarm = farm
        switching = true
        var route = FlightRoute(
            name: name, farmID: farm?.id, missionID: missionScope,
            defaultAltitude: altitude.isFinite && altitude > 0 ? altitude : 80,
            speed: speed.isFinite && speed > 0 ? speed : 5)
        if let farmPoints = farm?.points, farmPoints.count >= 2 {
            let alt = altitude.isFinite && altitude > 0 ? altitude : 80
            route.home = Self.defaultHomeLocation(for: farmPoints)
            route.waypoints = farmPoints.map {
                FlightWaypoint(
                    coordinate: MapCoordinate(latitude: $0.latitude, longitude: $0.longitude),
                    altitude: alt
                )
            }
            route.returnToHome = true
        }
        draft = route
        switching = false
        selectedWaypointID = nil
        mode = draft.home == nil ? .home : .inspect
        reviewed = false
        exportedURL = nil
        undoStack = []
        error = nil
        persist()
        fitRequest = UUID()
    }
    func select(_ id: UUID) {
        guard let route = routes.first(where: { $0.id == id }) else { return }
        switching = true
        draft = route
        switching = false
        selectedWaypointID = nil
        mode = draft.home == nil ? .home : .inspect
        reviewed = false
        exportedURL = nil
        undoStack = []
        error = nil
        fitRequest = UUID()
    }
    func activeBoundaryCoordinates() -> [MapCoordinate] {
        if draft.waypoints.count >= 3 {
            return draft.waypoints.filter { $0.coordinate.isValid }.map(\.coordinate)
        } else if let farm = currentFarm, farm.points.count >= 3 {
            return farm.points.map { MapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
        return []
    }
    func mapClick(_ coordinate: MapCoordinate) {
        guard coordinate.isValid else { return }
        switch mode {
        case .inspect: break
        case .home:
            draft.home = coordinate
            mode = .waypoint
        case .entry:
            let boundary = activeBoundaryCoordinates()
            if !boundary.isEmpty {
                draft.surveyEntry = coordinate.closestPointOnPolygonPerimeter(boundary)
            } else {
                draft.surveyEntry = coordinate
            }
        case .waypoint: addWaypoint(coordinate)
        }
    }
    func moveEntry(to coordinate: MapCoordinate) {
        guard coordinate.isValid else { return }
        let boundary = activeBoundaryCoordinates()
        if !boundary.isEmpty {
            draft.surveyEntry = coordinate.closestPointOnPolygonPerimeter(boundary)
        } else {
            draft.surveyEntry = coordinate
        }
    }
    func addWaypoint(_ coordinate: MapCoordinate, at index: Int? = nil) {
        guard coordinate.isValid, draft.waypoints.count < 500 else {
            error = "Koordinat tidak valid atau batas 500 waypoint tercapai."
            return
        }
        let point = FlightWaypoint(coordinate: coordinate, altitude: draft.defaultAltitude)
        draft.waypoints.insert(point, at: min(max(index ?? draft.waypoints.count, 0), draft.waypoints.count))
        selectedWaypointID = point.id
        if !draft.visualTransects.isEmpty {
            draft.visualTransects = []
            draft.surveyStatistics = nil
            draft.rawPlanJSON = nil
        }
    }
    func moveWaypoint(_ id: UUID, to coordinate: MapCoordinate) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft.waypoints[index].coordinate = coordinate
        if !draft.visualTransects.isEmpty {
            draft.visualTransects = []
            draft.surveyStatistics = nil
            draft.rawPlanJSON = nil
        }
    }
    func updateAltitude(_ id: UUID, to value: Double) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }) else { return }
        draft.waypoints[index].altitude = value
    }
    func removeWaypoint(_ id: UUID) {
        draft.waypoints.removeAll { $0.id == id }
        if selectedWaypointID == id { selectedWaypointID = nil }
        if !draft.visualTransects.isEmpty {
            draft.visualTransects = []
            draft.surveyStatistics = nil
            draft.rawPlanJSON = nil
        }
    }
    func moveWaypointOrder(_ id: UUID, toIndex targetIndex: Int) {
        guard let currentIndex = draft.waypoints.firstIndex(where: { $0.id == id }),
            draft.waypoints.indices.contains(targetIndex),
            currentIndex != targetIndex
        else { return }
        var updated = draft.waypoints
        let item = updated.remove(at: currentIndex)
        updated.insert(item, at: targetIndex)
        draft.waypoints = updated
        selectedWaypointID = item.id
        if !draft.visualTransects.isEmpty {
            draft.visualTransects = []
            draft.surveyStatistics = nil
            draft.rawPlanJSON = nil
        }
    }
    func reorder(_ id: UUID, offset: Int) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }) else { return }
        moveWaypointOrder(id, toIndex: index + offset)
    }
    func applyAltitudeToAll() {
        guard draft.defaultAltitude.isFinite, (1...500).contains(draft.defaultAltitude) else {
            error = "Tinggi waypoint tidak valid."
            return
        }
        draft.waypoints = draft.waypoints.map {
            var point = $0
            point.altitude = draft.defaultAltitude
            return point
        }
    }
    func undo() {
        if let previous = undoStack.popLast() {
            undoing = true
            draft = previous
            undoing = false
            if !draft.waypoints.contains(where: { $0.id == selectedWaypointID }) { selectedWaypointID = nil }
        } else if let baseline = baselineRoute, !isAtBaseline {
            undoing = true
            draft = baseline
            undoing = false
            selectedWaypointID = nil
        }
    }
    func fitRoute() { fitRequest = UUID() }
    /// Groups a slider drag into one undo step and saves once when it ends.
    func beginContinuousEdit() {
        guard !continuousEdit else { return }
        undoStack.append(draft)
        if undoStack.count > 50 { undoStack.removeFirst() }
        continuousEdit = true
    }
    func endContinuousEdit() {
        guard continuousEdit else { return }
        continuousEdit = false
        persist()
    }
    var exportBlocker: String? {
        do { try draft.validateForExport() } catch { return error.localizedDescription }
        return reviewed
            ? nil : "Periksa home, rute, tinggi dan profil drone, lalu tandai rute sudah diperiksa."
    }
    var selectedWaypoint: FlightWaypoint? { draft.waypoints.first { $0.id == selectedWaypointID } }
    func copyMissionRoutes(from sourceID: UUID, to destinationID: UUID) throws {
        let copies = routes.filter { $0.missionID == sourceID }.map { route in
            var copy = route
            copy.id = UUID()
            copy.missionID = destinationID
            return copy
        }
        guard routes.count + copies.count <= 256 else {
            throw MappingError.invalid("Batas 256 draft rute telah tercapai.")
        }
        let updated = routes + copies
        try repository.save(updated)
        routes = updated
    }

    func removeMissionRoutes(_ ids: Set<UUID>) {
        let remaining = routes.filter { $0.missionID.map { !ids.contains($0) } ?? true }
        try? repository.save(remaining)
        routes = remaining
        if draft.missionID.map({ ids.contains($0) }) == true {
            switching = true
            draft = FlightRoute()
            switching = false
            selectedWaypointID = nil
            undoStack = []
        }
    }

    func retrySaving() {
        persist()
    }
    private func persist() {
        var updated = routes
        if let index = updated.firstIndex(where: { $0.id == draft.id }) {
            updated[index] = draft
        } else {
            updated.append(draft)
        }
        do {
            try repository.save(updated)
            routes = updated
            storageError = nil
        } catch {
            storageError = "Draft belum tersimpan: " + error.localizedDescription
        }
    }
    @MainActor
    func generateSurveyWaypoints(
        altitude: Double,
        speed: Double,
        gridAngle: Double,
        lineSpacing: Double = 20.0,
        triggerDistance: Double = 15.0,
        turnaroundDistance: Double = 10.0,
        entryLocation: Int = 0,
        fitsRoute: Bool = true
    ) async {
        let activeBoundary = activeBoundaryCoordinates()
        guard activeBoundary.count >= 3 else {
            error = "Batas survei memerlukan minimal 3 titik."
            return
        }

        isGeneratingWaypoints = true
        error = nil

        let resolvedEntryLocation: Int
        if let entry = draft.surveyEntry {
            let lats = activeBoundary.map(\.latitude)
            let lons = activeBoundary.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0

            let corners = [
                MapCoordinate(latitude: maxLat, longitude: minLon), // 0: TopLeft
                MapCoordinate(latitude: maxLat, longitude: maxLon), // 1: TopRight
                MapCoordinate(latitude: minLat, longitude: minLon), // 2: BottomLeft
                MapCoordinate(latitude: minLat, longitude: maxLon)  // 3: BottomRight
            ]
            let distances = corners.map { $0.distance(to: entry) }
            resolvedEntryLocation = distances.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
        } else {
            resolvedEntryLocation = entryLocation
        }

        let params = SurveyScanParameters(
            altitude: altitude,
            speed: speed,
            gridAngle: gridAngle,
            spacing: lineSpacing,
            triggerDistance: triggerDistance,
            turnaroundDistance: turnaroundDistance,
            hoverAndCapture: false,
            useCameraOverlap: false,
            cameraBrand: "Manual",
            firmware: draft.firmware ?? .ardupilot,
            vehicleType: 2,
            entryLocation: resolvedEntryLocation
        )

        do {
            let result = try await waypointGenerator.generateWaypoints(
                boundary: activeBoundary,
                parameters: params
            )
            draft.visualTransects = result.visualTransectPoints
            draft.surveyStatistics = result.statistics
            draft.rawPlanJSON = result.rawPlanData
            draft.gridAngle = gridAngle
            draft.lineSpacing = lineSpacing
            draft.triggerDistance = triggerDistance
            draft.turnaroundDistance = turnaroundDistance
            draft.entryLocation = resolvedEntryLocation
            if draft.surveyEntry == nil, let first = result.visualTransectPoints.first {
                draft.surveyEntry = first.closestPointOnPolygonPerimeter(activeBoundary)
            }
            reviewed = false
            if fitsRoute { fitRoute() }
        } catch {
            self.error = error.localizedDescription
        }

        isGeneratingWaypoints = false
    }

    func export(to url: URL) {
        guard exportBlocker == nil else {
            error = exportBlocker
            return
        }
        do {
            let data: Data
            if let rawPlan = draft.rawPlanJSON, !rawPlan.isEmpty {
                data = rawPlan
            } else {
                let document: [String: Any] = [
                    "fileType": "Plan",
                    "groundStation": "QGroundControl",
                    "version": 1,
                    "mission": [
                        "version": 2,
                        "firmwareType": draft.firmware?.mavAutopilot ?? 3,
                        "vehicleType": 2,
                        "cruiseSpeed": draft.speed,
                        "hoverSpeed": draft.speed,
                        "items": []
                    ] as [String: Any]
                ]
                data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try data.write(to: url, options: .atomic)
            exportedURL = url
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func chooseExportDestination() {
        guard exportBlocker == nil else {
            error = exportBlocker
            return
        }
        let panel = NSSavePanel()
        panel.title = "Ekspor rute untuk QGroundControl"
        panel.allowedContentTypes = [UTType(importedAs: "org.qgroundcontrol.plan", conformingTo: .json)]
        panel.nameFieldStringValue = DatasetStore.safeName(draft.name) + ".plan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export(to: url)
    }
    func revealExport() {
        if let exportedURL { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) }
    }
    func openQGroundControl() { QGroundControlLauncher.open { [weak self] in self?.error = $0 } }
}
