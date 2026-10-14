import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum FlightMapEditMode: String, CaseIterable, Identifiable {
    case inspect, home, waypoint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inspect: return "Pilih"
        case .home: return "Home"
        case .waypoint: return "+ Waypoint"
        }
    }
}

final class FlightPlannerViewModel: ObservableObject {
    @Published private(set) var routes: [FlightRoute] = []
    @Published var draft = FlightRoute() {
        didSet {
            guard !switching, oldValue != draft else { return }
            if !undoing {
                undoStack.append(oldValue)
                if undoStack.count > 50 { undoStack.removeFirst() }
            }
            reviewed = false
            exportedURL = nil
            persist()
        }
    }
    @Published var mode: FlightMapEditMode = .home
    @Published var selectedWaypointID: UUID?
    @Published var reviewed = false
    @Published private(set) var error: String?
    @Published private(set) var storageError: String?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var fitRequest = UUID()
    @Published private(set) var undoStack: [FlightRoute] = []
    private let repository: any FlightRouteRepository
    private var switching = false
    private var undoing = false
    private var storageReady = false

    init(repository: any FlightRouteRepository) {
        self.repository = repository
        do {
            routes = try repository.load()
            storageReady = true
            if let last = routes.last { draft = last }
        } catch { storageError = "Rute tersimpan belum dapat dibaca: " + error.localizedDescription }
    }
    private var missionScope: UUID?
    func open(
        farm: FarmArea?, name: String = "Rute baru", altitude: Double = 80, speed: Double = 5,
        missionID: UUID? = nil
    ) {
        missionScope = missionID
        if let saved = routes.last(where: {
            $0.missionID == missionID && (missionID != nil || $0.farmID == farm?.id)
        }) {
            select(saved.id)
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
        switching = true
        draft = FlightRoute(
            name: name, farmID: farm?.id, missionID: missionScope,
            defaultAltitude: altitude.isFinite && altitude > 0 ? altitude : 80,
            speed: speed.isFinite && speed > 0 ? speed : 5)
        switching = false
        selectedWaypointID = nil
        mode = .home
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
    func mapClick(_ coordinate: MapCoordinate) {
        guard coordinate.isValid else { return }
        switch mode {
        case .inspect: break
        case .home:
            draft.home = coordinate
            mode = .waypoint
        case .waypoint: addWaypoint(coordinate)
        }
    }
    func addWaypoint(_ coordinate: MapCoordinate) {
        guard coordinate.isValid, draft.waypoints.count < 500 else {
            error = "Koordinat tidak valid atau batas 500 waypoint tercapai."
            return
        }
        let point = FlightWaypoint(coordinate: coordinate, altitude: draft.defaultAltitude)
        draft.waypoints.append(point)
        selectedWaypointID = point.id
    }
    func moveWaypoint(_ id: UUID, to coordinate: MapCoordinate) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }) else {
            return
        }
        draft.waypoints[index].coordinate = coordinate
    }
    func updateAltitude(_ id: UUID, to value: Double) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }) else { return }
        draft.waypoints[index].altitude = value
    }
    func removeWaypoint(_ id: UUID) {
        draft.waypoints.removeAll { $0.id == id }
        if selectedWaypointID == id { selectedWaypointID = nil }
    }
    func reorder(_ id: UUID, offset: Int) {
        guard let index = draft.waypoints.firstIndex(where: { $0.id == id }),
            draft.waypoints.indices.contains(index + offset)
        else { return }
        draft.waypoints.swapAt(index, index + offset)
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
        guard let previous = undoStack.popLast() else { return }
        undoing = true
        draft = previous
        undoing = false
        if !draft.waypoints.contains(where: { $0.id == selectedWaypointID }) { selectedWaypointID = nil }
    }
    func fitRoute() { fitRequest = UUID() }
    var exportBlocker: String? {
        if let storageError { return storageError }
        do { try draft.validateForExport() } catch { return error.localizedDescription }
        return reviewed
            ? nil : "Periksa home, rute, tinggi dan profil drone, lalu tandai rute sudah diperiksa."
    }
    var selectedWaypoint: FlightWaypoint? { draft.waypoints.first { $0.id == selectedWaypointID } }
    func retrySaving() {
        if !storageReady {
            do {
                routes = try repository.load()
                storageReady = true
            } catch {
                storageError = "Rute tersimpan belum dapat dibaca: " + error.localizedDescription
                return
            }
        }
        persist()
    }
    private func persist() {
        guard storageReady else { return }
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
        } catch { storageError = "Draft belum tersimpan: " + error.localizedDescription }
    }
    func export(to url: URL) {
        guard exportBlocker == nil else {
            error = exportBlocker
            return
        }
        do {
            let data = try QGCPlanExporter.data(for: draft)
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
