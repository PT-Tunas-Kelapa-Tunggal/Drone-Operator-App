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

enum PlanLockState: Equatable {
    case unlocked
    case softLocked(vehicleID: Int)
    case hardLockedActiveFlight(vehicleID: Int)
    case commsLostNeverArmed(vehicleID: Int)
    case commsLostWasArmed(vehicleID: Int)
}

final class FlightPlannerViewModel: ObservableObject {
    @Published private(set) var routes: [FlightRoute] = []
    @Published private(set) var flightTrails: [UUID: [MapCoordinate]] = [:]
    @Published var activeRecoveryMissionID: UUID? = nil
    @Published var lastCheckpointSavedAt: Date? = nil
    @Published var draft = FlightRoute() {
        didSet {
            guard !switching, !syncingMetadata, oldValue != draft else { return }
            let geometryChanged = !oldValue.hasSameFlightPlanGeometry(as: draft)
            if geometryChanged && !undoing && !continuousEdit {
                undoStack.append(oldValue)
                if undoStack.count > 50 { undoStack.removeFirst() }
                redoStack = []
            }
            if oldValue.waypoints != draft.waypoints {
                isAreaConfirmed = false
            }
            if geometryChanged {
                resetChecklist()
                syncingMetadata = true
                draft.isUploadedToDrone = false
                draft.isPlanLocked = false
                draft.checkedSOPItems = []
                draft.isReviewed = false
                draft.isAreaConfirmed = isAreaConfirmed
                syncingMetadata = false
            }
            exportedURL = nil
            if !continuousEdit { persist() }
        }
    }
    @Published var planningStep: FlightPlanningStep = .boundary
    @Published var isAreaConfirmed = false {
        didSet {
            if !isAreaConfirmed {
                checkedSOPItems.removeAll()
                reviewed = false
            }
            guard !switching, !syncingMetadata else { return }
            syncingMetadata = true
            draft.isAreaConfirmed = isAreaConfirmed
            if !isAreaConfirmed {
                draft.checkedSOPItems = []
                draft.isReviewed = false
            }
            syncingMetadata = false
            persist()
        }
    }
    @Published var mode: FlightMapEditMode = .inspect
    @Published var selectedWaypointID: UUID?
    @Published var checkedSOPItems: Set<PreflightChecklistItem> = [] {
        didSet {
            guard !switching, !syncingMetadata, draft.checkedSOPItems != checkedSOPItems else { return }
            syncingMetadata = true
            draft.checkedSOPItems = checkedSOPItems
            syncingMetadata = false
            persist()
        }
    }
    @Published var reviewed = false {
        didSet {
            guard !switching, !syncingMetadata, draft.isReviewed != reviewed else { return }
            syncingMetadata = true
            draft.isReviewed = reviewed
            syncingMetadata = false
            persist()
        }
    }

    func resetChecklist() {
        if !checkedSOPItems.isEmpty {
            checkedSOPItems.removeAll()
        }
        if reviewed {
            reviewed = false
        }
    }

    func precondition(for item: PreflightChecklistItem) -> (met: Bool, blockerReason: String?) {
        item.precondition(isAreaConfirmed: isAreaConfirmed, route: draft)
    }

    var isSOPChecklistComplete: Bool {
        PreflightChecklistItem.allCases.allSatisfy { item in
            checkedSOPItems.contains(item) && precondition(for: item).met
        }
    }
    @Published private(set) var error: String?
    @Published private(set) var storageError: String?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var fitRequest = UUID()
    @Published private(set) var undoStack: [FlightRoute] = []
    @Published private(set) var redoStack: [FlightRoute] = []
    @Published public private(set) var isGeneratingWaypoints = false
    private let repository: any FlightRouteRepository
    private let trailRepository: any FlightTrailRepository
    private let waypointGenerator: any WaypointGenerator
    private var switching = false
    private var syncingMetadata = false
    private var continuousEdit = false
    private var undoing = false
    private var storageReady = false
    private var vehicleCancellable: AnyCancellable?
    private var previouslyArmedVehicleIDs: Set<Int> = []

    init(
        repository: any FlightRouteRepository = InMemoryFlightRouteRepository(),
        trailRepository: any FlightTrailRepository = InMemoryFlightTrailRepository(),
        waypointGenerator: any WaypointGenerator = MockWaypointGenerator()
    ) {
        self.repository = repository
        self.trailRepository = trailRepository
        self.waypointGenerator = waypointGenerator
        routes = (try? repository.load()) ?? []
        flightTrails = (try? trailRepository.load()) ?? [:]
        storageReady = true
        if let last = routes.last {
            switching = true
            draft = last
            isAreaConfirmed = last.isAreaConfirmed || (!last.visualTransects.isEmpty && last.waypoints.count >= 3)
            checkedSOPItems = last.checkedSOPItems
            reviewed = last.isReviewed
            planningStep = (last.visualTransects.isEmpty && !isAreaConfirmed) ? .boundary : .flight
            switching = false
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.vehicleCancellable = QGCEngineManager.shared.$vehicles
                .receive(on: DispatchQueue.main)
                .sink { [weak self] vehicles in
                    self?.observeVehicles(vehicles)
                }
        }
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
            defaultAltitude: draft.defaultAltitude.isFinite && draft.defaultAltitude > 0
                ? draft.defaultAltitude : 80,
            speed: draft.speed.isFinite && draft.speed > 0 ? draft.speed : 5
        )
        let alt = route.defaultAltitude
        route.home = nil
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
            FlightWaypoint(
                coordinate: MapCoordinate(latitude: $0.latitude, longitude: $0.longitude), altitude: alt)
        }
        draft.visualTransects = []
        draft.surveyStatistics = nil
        draft.safetyResult = nil
        draft.rawPlanJSON = nil
        resetChecklist()
        fitRoute()
    }

    func open(
        farm: FarmArea?, name: String = "Rute baru", altitude: Double = 80, speed: Double = 5,
        missionID: UUID? = nil
    ) {
        let sameActiveMission =
            missionID != nil
            && draft.missionID == missionID
            && routes.contains(where: { $0.id == draft.id })
        missionScope = missionID
        currentFarm = farm
        if sameActiveMission {
            if !draft.visualTransects.isEmpty || draft.isAreaConfirmed || isAreaConfirmed {
                planningStep = .flight
            }
            return
        }
        if let saved = routes.last(where: {
            $0.missionID == missionID && (missionID != nil || $0.farmID == farm?.id)
        }) {
            if let farm, farm.points.count >= 2 {
                let farmHome = Self.defaultHomeLocation(for: farm.points)
                let isNearFarm = saved.home.map { $0.distance(to: farmHome) < 5_000 } ?? true
                let hasValidBoundary = saved.waypoints.count >= 2

                if hasValidBoundary && isNearFarm {
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
            route.home = nil
            route.waypoints = farmPoints.map {
                FlightWaypoint(
                    coordinate: MapCoordinate(latitude: $0.latitude, longitude: $0.longitude),
                    altitude: alt
                )
            }
            route.returnToHome = true
        }
        draft = route
        checkedSOPItems.removeAll()
        reviewed = false
        isAreaConfirmed = false
        planningStep = .boundary
        switching = false
        selectedWaypointID = nil
        mode = .inspect
        exportedURL = nil
        undoStack = []
        redoStack = []
        error = nil
        persist()
        fitRequest = UUID()
    }
    func select(_ id: UUID) {
        guard let route = routes.first(where: { $0.id == id }) else { return }
        switching = true
        draft = route
        let restoredConfirmed =
            route.isAreaConfirmed || (!route.visualTransects.isEmpty && route.waypoints.count >= 3)
        isAreaConfirmed = restoredConfirmed
        checkedSOPItems = route.checkedSOPItems
        reviewed = route.isReviewed
        planningStep = (route.visualTransects.isEmpty && !restoredConfirmed) ? .boundary : .flight
        switching = false
        selectedWaypointID = nil
        mode = .inspect
        exportedURL = nil
        undoStack = []
        redoStack = []
        error = nil
        fitRequest = UUID()
    }

    // MARK: - Plan Persistence, Two-Tier Locking & Flight Trail Recovery

    func saveRouteCheckpoint() {
        syncingMetadata = true
        draft.isAreaConfirmed = isAreaConfirmed
        draft.checkedSOPItems = checkedSOPItems
        draft.isReviewed = reviewed
        draft.lastSavedAt = Date()
        syncingMetadata = false
        lastCheckpointSavedAt = draft.lastSavedAt
        persist()
    }

    func markUploadedAndLock(vehicleID: Int) {
        syncingMetadata = true
        draft.isAreaConfirmed = isAreaConfirmed
        draft.checkedSOPItems = checkedSOPItems
        draft.isReviewed = reviewed
        draft.isUploadedToDrone = true
        draft.isPlanLocked = true
        draft.uploadedVehicleID = vehicleID
        draft.wasVehicleArmedSinceUpload = false
        draft.lastSavedAt = Date()
        syncingMetadata = false
        selectedWaypointID = nil
        mode = .inspect
        if let missionID = draft.missionID ?? missionScope {
            clearFlightTrail(for: missionID)
        }
        persist()
    }

    func unlockPlan() {
        syncingMetadata = true
        draft.isPlanLocked = false
        draft.isUploadedToDrone = false
        draft.wasVehicleArmedSinceUpload = false
        syncingMetadata = false
        persist()
    }

    func planLockState(in vehicles: [ConnectedDrone]) -> PlanLockState {
        guard draft.isPlanLocked else { return .unlocked }
        let targetID =
            draft.uploadedVehicleID
            ?? vehicles.first(where: \.active)?.id
            ?? vehicles.first?.id
            ?? 1
        if let drone = vehicles.first(where: { $0.id == targetID }), drone.isReachable {
            if drone.armed || drone.flying {
                return .hardLockedActiveFlight(vehicleID: drone.id)
            } else {
                return .softLocked(vehicleID: drone.id)
            }
        } else {
            if draft.wasVehicleArmedSinceUpload {
                return .commsLostWasArmed(vehicleID: targetID)
            } else {
                return .commsLostNeverArmed(vehicleID: targetID)
            }
        }
    }

    func flightTrail(for missionID: UUID?) -> [MapCoordinate] {
        guard let id = missionID ?? draft.missionID ?? missionScope else { return [] }
        return flightTrails[id] ?? []
    }

    func appendTrailCoordinate(_ coord: MapCoordinate, for missionID: UUID) {
        guard coord.isValid, coord.latitude != 0 || coord.longitude != 0 else { return }
        var current = flightTrails[missionID] ?? []
        if let last = current.last {
            guard last.distance(to: coord) > 1.0 else { return }
        }
        current.append(coord)
        flightTrails[missionID] = current
        try? trailRepository.save(flightTrails)
    }

    func clearFlightTrail(for missionID: UUID) {
        flightTrails.removeValue(forKey: missionID)
        try? trailRepository.save(flightTrails)
    }

    func observeVehicles(_ vehicles: [ConnectedDrone]) {
        var routesChanged = false
        var updatedRoutes = routes

        for drone in vehicles {
            let matchingIndex =
                updatedRoutes.lastIndex(where: {
                    $0.isPlanLocked && $0.uploadedVehicleID == drone.id
                })
                ?? updatedRoutes.lastIndex(where: {
                    $0.isPlanLocked && $0.uploadedVehicleID == nil
                })

            let wasPreviouslyArmed = previouslyArmedVehicleIDs.contains(drone.id)

            if drone.isReachable && (drone.armed || drone.flying) {
                previouslyArmedVehicleIDs.insert(drone.id)
                if let idx = matchingIndex {
                    let routeMissionID = updatedRoutes[idx].missionID
                    if !wasPreviouslyArmed && drone.armed && !updatedRoutes[idx].wasVehicleArmedSinceUpload,
                        let mID = routeMissionID
                    {
                        clearFlightTrail(for: mID)
                    }
                    if !updatedRoutes[idx].wasVehicleArmedSinceUpload {
                        updatedRoutes[idx].wasVehicleArmedSinceUpload = true
                        routesChanged = true
                    }
                    if let mID = routeMissionID {
                        activeRecoveryMissionID = mID
                        if drone.telemetry.latitude != 0 || drone.telemetry.longitude != 0 {
                            appendTrailCoordinate(
                                MapCoordinate(
                                    latitude: drone.telemetry.latitude,
                                    longitude: drone.telemetry.longitude
                                ),
                                for: mID
                            )
                        }
                    }
                } else if let fallbackMissionID = draft.missionID ?? missionScope {
                    activeRecoveryMissionID = fallbackMissionID
                    if drone.telemetry.latitude != 0 || drone.telemetry.longitude != 0 {
                        appendTrailCoordinate(
                            MapCoordinate(
                                latitude: drone.telemetry.latitude,
                                longitude: drone.telemetry.longitude
                            ),
                            for: fallbackMissionID
                        )
                    }
                }
            } else if drone.isReachable && !drone.armed && !drone.flying {
                previouslyArmedVehicleIDs.remove(drone.id)
                if let idx = matchingIndex, updatedRoutes[idx].wasVehicleArmedSinceUpload {
                    updatedRoutes[idx].wasVehicleArmedSinceUpload = false
                    routesChanged = true
                }
            }
        }

        if routesChanged {
            routes = updatedRoutes
            try? repository.save(updatedRoutes)
            if let currentIdx = updatedRoutes.firstIndex(where: { $0.id == draft.id }) {
                syncingMetadata = true
                draft.wasVehicleArmedSinceUpload = updatedRoutes[currentIdx].wasVehicleArmedSinceUpload
                syncingMetadata = false
            }
        }
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
            mode = .inspect
        case .entry:
            let boundary = activeBoundaryCoordinates()
            if !boundary.isEmpty {
                draft.surveyEntry = coordinate.closestPointOnPolygonPerimeter(boundary)
            } else {
                draft.surveyEntry = coordinate
            }
            mode = .inspect
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
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() {
        if let previous = undoStack.popLast() {
            redoStack.append(draft)
            undoing = true
            draft = previous
            undoing = false
            if !draft.waypoints.contains(where: { $0.id == selectedWaypointID }) { selectedWaypointID = nil }
        } else if let baseline = baselineRoute, !isAtBaseline {
            redoStack.append(draft)
            undoing = true
            draft = baseline
            undoing = false
            selectedWaypointID = nil
        }
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        undoing = true
        draft = next
        undoing = false
        if !draft.waypoints.contains(where: { $0.id == selectedWaypointID }) { selectedWaypointID = nil }
    }
    func fitRoute() { fitRequest = UUID() }
    /// Groups a slider drag into one undo step and saves once when it ends.
    func beginContinuousEdit() {
        guard !continuousEdit else { return }
        undoStack.append(draft)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack = []
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
            redoStack = []
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
        sideOverlap: Double? = nil,
        frontalOverlap: Double? = nil,
        cameraResolution: CameraOpticalSpec.Resolution? = nil,
        lineSpacing: Double? = nil,
        triggerDistance: Double? = nil,
        turnaroundDistance: Double = 10.0,
        entryLocation: Int = 0,
        fitsRoute: Bool = true
    ) async {
        let activeBoundary = activeBoundaryCoordinates()
        guard activeBoundary.count >= 3 else {
            error = "Batas survei memerlukan minimal 3 titik."
            return
        }

        if let sideOverlap { draft.sideOverlap = sideOverlap }
        if let frontalOverlap { draft.frontalOverlap = frontalOverlap }
        if let cameraResolution { draft.cameraResolution = cameraResolution }

        isGeneratingWaypoints = true
        error = nil

        draft.surveyEntry = nil
        let resolvedEntryLocation: Int
        if let home = draft.home, home.isValid {
            let lats = activeBoundary.map(\.latitude)
            let lons = activeBoundary.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0

            let corners = [
                MapCoordinate(latitude: maxLat, longitude: minLon),  // 0: TopLeft
                MapCoordinate(latitude: maxLat, longitude: maxLon),  // 1: TopRight
                MapCoordinate(latitude: minLat, longitude: minLon),  // 2: BottomLeft
                MapCoordinate(latitude: minLat, longitude: maxLon),  // 3: BottomRight
            ]
            let distances = corners.map { $0.distance(to: home) }
            resolvedEntryLocation = distances.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
        } else {
            resolvedEntryLocation = entryLocation
        }

        var opticalSpec = CameraOpticalSpec.iphone17
        opticalSpec.setResolution(draft.cameraResolution)

        let params = SurveyScanParameters(
            altitude: altitude,
            speed: speed,
            ascentSpeed: draft.ascentSpeed,
            descentSpeed: draft.descentSpeed,
            holdSeconds: draft.holdSeconds,
            gridAngle: gridAngle,
            spacing: lineSpacing ?? draft.lineSpacing,
            triggerDistance: triggerDistance ?? draft.triggerDistance,
            turnaroundDistance: turnaroundDistance,
            hoverAndCapture: false,
            useCameraOverlap: true,
            frontalOverlap: draft.frontalOverlap / 100.0,
            sideOverlap: draft.sideOverlap / 100.0,
            cameraBrand: "Custom Camera",
            cameraSpec: opticalSpec,
            firmware: draft.firmware ?? .ardupilot,
            vehicleType: 2,
            entryLocation: resolvedEntryLocation,
            home: draft.home,
            returnToHome: draft.returnToHome,
            geofence: draft.geofence
        )

        do {
            let result = try await waypointGenerator.generateWaypoints(
                boundary: activeBoundary,
                parameters: params
            )
            draft.visualTransects = result.visualTransectPoints
            draft.surveyStatistics = result.statistics
            draft.safetyResult = result.safety
            draft.rawPlanJSON = result.rawPlanData
            draft.gridAngle = gridAngle
            if result.statistics.calculatedLineSpacing > 0 {
                draft.lineSpacing = result.statistics.calculatedLineSpacing
                draft.calculatedLineSpacing = result.statistics.calculatedLineSpacing
            } else if let lineSpacing {
                draft.lineSpacing = lineSpacing
            }
            if result.statistics.calculatedTriggerDistance > 0 {
                draft.triggerDistance = result.statistics.calculatedTriggerDistance
                draft.calculatedTriggerDistance = result.statistics.calculatedTriggerDistance
            } else if let triggerDistance {
                draft.triggerDistance = triggerDistance
            }
            if result.statistics.groundResolutionCmPerPx > 0 {
                draft.groundResolutionCmPerPx = result.statistics.groundResolutionCmPerPx
            }
            draft.turnaroundDistance = turnaroundDistance
            draft.entryLocation = resolvedEntryLocation
            resetChecklist()
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
                        "items": [],
                    ] as [String: Any],
                ]
                data = try JSONSerialization.data(
                    withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
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
