import SwiftUI

private enum MissionMapTool: String, CaseIterable, Identifiable {
    case inspect, boundary, home, waypoint, move
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inspect: return "Pilih"
        case .boundary: return "Batas area"
        case .home: return "Home"
        case .waypoint: return "+ Waypoint"
        case .move: return "Pindah WP"
        }
    }
    var flightMode: FlightMapEditMode {
        switch self {
        case .home: return .home
        case .waypoint, .move: return .waypoint
        case .inspect, .boundary: return .inspect
        }
    }
}

struct MissionWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    var openPlanner: () -> Void
    @State private var tool = MissionMapTool.home
    @State private var focusOperator = false
    @State private var manualLatitude: Double?
    @State private var manualLongitude: Double?
    private var area: FarmArea? { model.selectedMission?.area }
    private var routeMatchesMission: Bool {
        model.selectedMissionID != nil && planner.draft.missionID == model.selectedMissionID
    }
    private var locked: Bool {
        model.editingLocked || model.selectedMission?.preparationRequested == true
    }
    private var canEditRoute: Bool { !locked && routeMatchesMission }
    private var routes: [FlightRoute] {
        planner.routes.filter { $0.missionID == model.selectedMissionID }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button("Semua misi", systemImage: "chevron.left") { model.showMissionList() }
                        .buttonStyle(.plain).foregroundStyle(KropsStyle.accent)
                    MissionView(model: model, link: link)
                    waypointPanel
                    MissionAreaView(
                        model: model, farms: farms, drawing: tool == .boundary,
                        drawBoundary: { tool = tool == .boundary ? .inspect : .boundary },
                        fitArea: fitMap)
                }.padding(.bottom, 8)
            }.frame(width: 350).scrollIndicators(.hidden)
            planningMap
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(KropsStyle.border))
        }
        .onAppear {
            guard let mission = model.selectedMission else { return }
            planner.open(
                farm: area, name: "Rute " + mission.plan.name,
                altitude: model.geometry.heightAGL, speed: model.geometry.speed, missionID: mission.id)
            tool = planner.draft.home == nil ? .home : .inspect
        }
        .onChange(of: model.geometry.heightAGL) { _, altitude in
            if canEditRoute { planner.draft.defaultAltitude = altitude }
        }
        .onChange(of: model.geometry.speed) { _, speed in
            if canEditRoute { planner.draft.speed = speed }
        }
        .onChange(of: location.focusRequest) { _, _ in
            focusOperator = true
            planner.fitRoute()
        }
    }
    private var planningMap: some View {
        WaypointMap(
            route: routeMatchesMission ? planner.draft : FlightRoute(), farm: area,
            operatorLocation: location.sample, mode: locked ? .inspect : tool.flightMode,
            fitRequest: planner.fitRequest, selectedWaypoint: $planner.selectedWaypointID,
            onClick: mapClick,
            onMove: { id, coordinate in
                editRoute { planner.moveWaypoint(id, to: coordinate) }
            },
            drawingBoundary: tool == .boundary && !locked,
            editingEnabled: !locked && (routeMatchesMission || tool == .boundary),
            focusOperator: focusOperator,
            onBoundaryClick: addBoundaryPoint,
            onBoundaryMove: moveBoundaryPoint,
            onHomeMove: { coordinate in
                editRoute { planner.draft.home = coordinate }
            }
        )
        .overlay(alignment: .topLeading) {
            Picker("Mode peta misi", selection: $tool) {
                ForEach(MissionMapTool.allCases) { tool in Text(tool.title).tag(tool) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 400, height: 28)
                .disabled(locked)
                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button {
                    location.request()
                } label: {
                    Image(systemName: "location")
                }
                .help("Lokasi saya")
                Button(action: fitMap) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Tampilkan seluruh area dan rute")
            }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(14)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Label(mapAdvice, systemImage: "cursorarrow.click").font(.callout)
                HStack(spacing: 16) {
                    Label(
                        "\(routeMatchesMission ? planner.draft.waypoints.count : 0) waypoint",
                        systemImage: "mappin.and.ellipse")
                    if routeMatchesMission {
                        Text(String(format: "%.0f m rute", planner.draft.distance))
                    }
                    if let area { Text("\(area.points.count) titik batas") }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(14).padding(.bottom, 25).padding(.trailing, 70)
        }
    }
    private var mapAdvice: String {
        if locked { return "Rencana tersimpan · pengeditan dikunci selama operasi misi." }
        switch tool {
        case .inspect: return "Klik waypoint untuk memilih. Geser penanda untuk mengubah posisi."
        case .boundary: return "Klik peta untuk menambah titik batas area."
        case .home: return "Klik lokasi lepas landas untuk menentukan Home."
        case .waypoint: return "Klik peta untuk menambah waypoint berurutan."
        case .move: return "Pilih waypoint, lalu klik lokasi barunya pada peta."
        }
    }
    private var waypointPanel: some View {
        ControlPanel("Rute waypoint", state: nil) {
            if let error = planner.storageError ?? planner.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                if planner.storageError != nil {
                    Button("Coba simpan rute lagi") { planner.retrySaving() }
                }
            }
            if routes.count > 1 {
                Picker(
                    "Rute",
                    selection: Binding(
                        get: { planner.draft.id },
                        set: {
                            let id = $0
                            editRoute { planner.select(id) }
                            tool = planner.draft.home == nil ? .home : .inspect
                        })
                ) {
                    ForEach(routes) { route in Text(route.name).tag(route.id) }
                }.disabled(locked)
            }
            HStack {
                Label(
                    routeMatchesMission && planner.draft.home != nil ? "Home tersimpan" : "Home belum diatur",
                    systemImage: "house"
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Tentukan home") { tool = .home }.disabled(!canEditRoute)
            }
            Button("Tambah waypoint di peta") { tool = .waypoint }
                .kropsPrimaryAction().disabled(!canEditRoute)
            Text(
                String(
                    format: "Titik baru memakai tinggi %.0f m relatif home.", planner.draft.defaultAltitude)
            )
            .font(.caption).foregroundStyle(.secondary)
            if routeMatchesMission && !planner.draft.waypoints.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(planner.draft.waypoints.enumerated()), id: \.element.id) { index, point in
                        HStack {
                            Button {
                                planner.selectedWaypointID = point.id
                                tool = .inspect
                            } label: {
                                HStack {
                                    Text("WP \(index + 1)").font(.callout.weight(.medium))
                                    Spacer()
                                    Text(String(format: "%.0f m", point.altitude)).font(.caption)
                                }.padding(8).foregroundStyle(
                                    planner.selectedWaypointID == point.id
                                        ? KropsStyle.accent : Color.primary
                                )
                                .background(
                                    planner.selectedWaypointID == point.id
                                        ? KropsStyle.accent.opacity(0.1) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                            Button {
                                editRoute { planner.removeWaypoint(point.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain).help("Hapus WP \(index + 1)").disabled(!canEditRoute)
                        }
                    }
                }
            } else {
                Text("Belum ada waypoint. Pilih + Waypoint, lalu klik peta di kanan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if routeMatchesMission, let selected = planner.selectedWaypoint {
                selectedWaypointFields(selected)
            }
            HStack {
                Button("Urungkan") { editRoute { planner.undo() } }.disabled(
                    !canEditRoute || planner.undoStack.isEmpty)
                Spacer()
                Button("Detail & ekspor .plan", action: openPlanner).disabled(!canEditRoute)
            }
            DisclosureGroup("Koordinat waypoint manual") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "Latitude", value: $manualLatitude,
                        format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(
                            .fractionLength(0...7)))
                    TextField(
                        "Longitude", value: $manualLongitude,
                        format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(
                            .fractionLength(0...7)))
                    Button(planner.draft.home == nil ? "Tentukan home" : "Tambah waypoint") {
                        guard let manualLatitude, let manualLongitude else { return }
                        tool = planner.draft.home == nil ? .home : .waypoint
                        mapClick(MapCoordinate(latitude: manualLatitude, longitude: manualLongitude))
                        fitMap()
                    }.disabled(!canEditRoute || manualLatitude == nil || manualLongitude == nil)
                }.textFieldStyle(.roundedBorder).padding(.top, 8)
            }.font(.caption)
        }
    }
    private func selectedWaypointFields(_ point: FlightWaypoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Waypoint dipilih").font(.caption.bold())
            Text(String(format: "%.6f, %.6f", point.coordinate.latitude, point.coordinate.longitude))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            ControlField("Tinggi relatif home") {
                NumberField(
                    Binding(
                        get: { planner.selectedWaypoint?.altitude ?? point.altitude },
                        set: { altitude in editRoute { planner.updateAltitude(point.id, to: altitude) } }),
                    unit: "m")
            }
            Button("Pindahkan di peta") { tool = .move }
            HStack {
                Button("Naik urutan") { editRoute { planner.reorder(point.id, offset: -1) } }
                Button("Turun urutan") { editRoute { planner.reorder(point.id, offset: 1) } }
            }.controlSize(.small)
        }.disabled(!canEditRoute)
    }
    private func fitMap() {
        focusOperator = false
        planner.fitRoute()
    }
    private func mapClick(_ coordinate: MapCoordinate) {
        guard canEditRoute, coordinate.isValid else { return }
        if tool == .move {
            guard let id = planner.selectedWaypointID else {
                model.errorMessage = "Pilih waypoint yang ingin dipindahkan terlebih dahulu."
                return
            }
            editRoute { planner.moveWaypoint(id, to: coordinate) }
            tool = .inspect
            return
        }
        planner.mode = tool.flightMode
        editRoute { planner.mapClick(coordinate) }
        if tool == .home { tool = .waypoint }
    }
    private func editRoute(_ change: () -> Void) {
        guard canEditRoute else { return }
        let previous = planner.draft
        change()
        if planner.draft != previous { model.geometry.reviewed = false }
    }
    private func addBoundaryPoint(_ coordinate: MapCoordinate) {
        guard !locked, coordinate.isValid else { return }
        var updated = area ?? FarmArea(name: "Area " + model.plan.name, points: [])
        updated.points.append(FarmArea.Point(latitude: coordinate.latitude, longitude: coordinate.longitude))
        model.setMissionArea(updated)
    }
    private func moveBoundaryPoint(_ index: Int, _ coordinate: MapCoordinate) {
        guard !locked, coordinate.isValid, var updated = area, updated.points.indices.contains(index) else {
            return
        }
        updated.points[index] = FarmArea.Point(latitude: coordinate.latitude, longitude: coordinate.longitude)
        model.setMissionArea(updated)
    }
}
