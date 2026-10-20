import SwiftUI

struct MissionWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    var openPlanner: () -> Void
    @State private var addingPoints = true
    @State private var focusOperator = false
    @State private var requestedLocation = false

    private var routeMatchesMission: Bool {
        model.selectedMissionID != nil && planner.draft.missionID == model.selectedMissionID
    }
    private var canEditRoute: Bool {
        routeMatchesMission && !model.editingLocked
            && model.selectedMission?.preparationRequested != true
            && model.selectedMission?.phase != .completed
    }
    private var mapMode: FlightMapEditMode {
        guard canEditRoute && addingPoints else { return .inspect }
        return planner.draft.home == nil ? .home : .waypoint
    }
    private var routes: [FlightRoute] {
        planner.routes.filter { $0.missionID == model.selectedMissionID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SurveyConfigurationView(model: model).disabled(!canEditRoute)
                    if routes.count > 1 {
                        Picker("Rute", selection: Binding(
                            get: { planner.draft.id },
                            set: { id in
                                guard canEditRoute else { return }
                                editRoute { planner.select(id) }
                                addingPoints = planner.draft.waypoints.isEmpty
                            })
                        ) {
                            ForEach(routes) { route in Text(route.name).tag(route.id) }
                        }.disabled(!canEditRoute)
                    }
                    if routeMatchesMission, let point = planner.selectedWaypoint {
                        waypointInspector(point)
                    }
                    if let error = planner.storageError ?? planner.error {
                        Text(error).font(.callout).foregroundStyle(.orange)
                        if planner.storageError != nil {
                            Button("Coba simpan rute lagi") { planner.retrySaving() }
                        }
                    }
                }.padding(.bottom, 8)
            }
            .frame(width: 280)
            VStack(spacing: 0) {
                mapToolbar
                WaypointMap(
                    route: routeMatchesMission ? planner.draft : FlightRoute(),
                    farm: nil, operatorLocation: location.sample, mode: mapMode,
                    fitRequest: planner.fitRequest, selectedWaypoint: $planner.selectedWaypointID,
                    onClick: addPoint,
                    onMove: { id, coordinate in
                        editRoute { planner.moveWaypoint(id, to: coordinate) }
                    },
                    editingEnabled: canEditRoute,
                    dragWhileAdding: true,
                    focusOperator: focusOperator,
                    onHomeMove: { coordinate in
                        editRoute { planner.draft.home = coordinate }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text(mapAdvice).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.top, 8)
                if requestedLocation && location.sample == nil {
                    Text(location.status).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard let mission = model.selectedMission else { return }
            planner.open(
                farm: mission.area, name: "Rute " + mission.plan.name,
                altitude: model.geometry.heightAGL, speed: model.geometry.speed, missionID: mission.id)
            addingPoints = planner.draft.waypoints.isEmpty
        }
        .onChange(of: model.geometry.heightAGL) { _, altitude in
            if canEditRoute { planner.draft.defaultAltitude = altitude }
        }
        .onChange(of: model.geometry.speed) { _, speed in
            if canEditRoute { planner.draft.speed = speed }
        }
        .onChange(of: location.focusRequest) { _, _ in
            guard requestedLocation else { return }
            focusOperator = true
            planner.fitRoute()
        }
    }

    private var mapToolbar: some View {
        HStack(spacing: 10) {
            Button {
                addingPoints.toggle()
            } label: {
                Label(addingPoints ? "Selesai menambah" : "Tambah titik",
                      systemImage: addingPoints ? "checkmark" : "plus")
            }
            .kropsPrimaryAction()
            .disabled(!canEditRoute)
            Button {
                editRoute { planner.undo() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Urungkan perubahan rute terakhir")
            .accessibilityLabel("Urungkan perubahan rute terakhir")
            .disabled(!canEditRoute || planner.undoStack.isEmpty)
            Spacer(minLength: 8)
            if routeMatchesMission && !planner.draft.waypoints.isEmpty {
                Text(String(format: "%d titik · %.0f m",
                            planner.draft.waypoints.count, planner.draft.distance))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                requestedLocation = true
                location.request()
            } label: {
                Image(systemName: "location")
            }.help("Ke lokasi saya").accessibilityLabel("Ke lokasi saya")
            Button {
                focusOperator = false
                planner.fitRoute()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Tampilkan seluruh rute").accessibilityLabel("Tampilkan seluruh rute")
        }.padding(.bottom, 10)
    }

    private var mapAdvice: String {
        if !canEditRoute { return "Rute hanya baca selama operasi misi atau setelah misi selesai." }
        if addingPoints {
            return planner.draft.home == nil
                ? "Klik lokasi lepas landas untuk Home, lalu klik titik-titik rute."
                : "Klik peta untuk menambah titik. Geser marker untuk mengoreksi posisinya."
        }
        return "Geser marker untuk mengubah posisi. Pilih waypoint untuk mengatur tinggi dan urutannya."
    }

    private func waypointInspector(_ point: FlightWaypoint) -> some View {
        let index = planner.draft.waypoints.firstIndex(where: { $0.id == point.id }) ?? 0
        return ControlPanel("Waypoint \(index + 1)", state: nil) {
            ControlField("Tinggi relatif Home") {
                NumberField(
                    Binding(
                        get: { planner.selectedWaypoint?.altitude ?? point.altitude },
                        set: { altitude in editRoute { planner.updateAltitude(point.id, to: altitude) } }),
                    unit: "m")
            }
            HStack {
                Button("Naik urutan") { editRoute { planner.reorder(point.id, offset: -1) } }
                    .disabled(index == 0)
                Button("Turun urutan") { editRoute { planner.reorder(point.id, offset: 1) } }
                    .disabled(index == planner.draft.waypoints.count - 1)
            }.controlSize(.small)
            Button("Hapus waypoint", role: .destructive) {
                editRoute { planner.removeWaypoint(point.id) }
            }
        }.disabled(!canEditRoute)
    }

    private func addPoint(_ coordinate: MapCoordinate) {
        guard canEditRoute, addingPoints, coordinate.isValid else { return }
        planner.mode = planner.draft.home == nil ? .home : .waypoint
        editRoute { planner.mapClick(coordinate) }
    }

    private func editRoute(_ change: () -> Void) {
        guard canEditRoute else { return }
        let previous = planner.draft
        change()
        if planner.draft != previous { model.geometry.reviewed = false }
    }
}
