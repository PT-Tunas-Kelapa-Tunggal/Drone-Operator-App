import SwiftUI

struct MissionWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
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
        canEditRoute ? planner.mode : .inspect
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepSelector

                    if planner.planningStep == .boundary {
                        boundaryConfigurationSection
                    } else {
                        SurveyConfigurationView(model: model, planner: planner).disabled(!canEditRoute)
                    }

                    if let error = planner.error {
                        Text(error).font(.callout).foregroundStyle(.orange)
                    }
                }.padding(.bottom, 8)
            }
            .frame(width: 300)
            VStack(spacing: 0) {
                mapToolbar
                WaypointMap(
                    route: routeMatchesMission ? planner.draft : FlightRoute(),
                    farm: model.selectedMission?.area, operatorLocation: location.sample, mode: mapMode,
                    fitRequest: planner.fitRequest, selectedWaypoint: $planner.selectedWaypointID,
                    onClick: addPoint,
                    onMove: { id, coordinate in
                        editRoute { planner.moveWaypoint(id, to: coordinate) }
                    },
                    editingEnabled: canEditRoute,
                    dragWhileAdding: true,
                    focusOperator: focusOperator,
                    planningStep: planner.planningStep,
                    onHomeMove: { coordinate in
                        editRoute { planner.draft.home = coordinate }
                    },
                    onEntryMove: { coordinate in
                        editRoute { planner.moveEntry(to: coordinate) }
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

    private var stepSelector: some View {
        Picker("Tahap", selection: $planner.planningStep) {
            Text("1. Batas Area").tag(FlightPlanningStep.boundary)
            Text("2. Jalur Terbang").tag(FlightPlanningStep.flight)
        }
        .pickerStyle(.segmented)
        .disabled(!canEditRoute)
        .onChange(of: planner.planningStep) { _, newStep in
            if newStep == .boundary {
                if planner.mode == .home || planner.mode == .entry {
                    planner.mode = .inspect
                }
            } else {
                if planner.mode == .waypoint {
                    planner.mode = .inspect
                }
                planner.selectedWaypointID = nil
            }
        }
    }

    private var boundaryConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlPanel("Batas Area Survei", state: "\(planner.draft.waypoints.count) titik") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Periksa dan sesuaikan titik batas kebun petani agar sesuai dengan kondisi lapangan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimasi Luas").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.2f ha", planner.boundaryAreaHectares))
                                .font(.callout.bold())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(KropsStyle.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keliling").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.0f m", planner.boundaryPerimeterMeters))
                                .font(.callout.bold())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(KropsStyle.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let selected = planner.selectedWaypoint {
                        let index = planner.draft.waypoints.firstIndex(where: { $0.id == selected.id }) ?? 0
                        let total = planner.draft.waypoints.count
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Titik Batas \(index + 1) dari \(total)")
                                    .font(.caption.bold())
                                Spacer()
                                Button(role: .destructive) {
                                    editRoute {
                                        planner.removeWaypoint(selected.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .help("Hapus titik sudut ini")
                                .controlSize(.small)
                                .disabled(total <= 3)
                            }

                            HStack(spacing: 6) {
                                Text("Urutan:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker("Urutan titik", selection: Binding(
                                    get: { index + 1 },
                                    set: { newPos in
                                        editRoute {
                                            planner.moveWaypointOrder(selected.id, toIndex: newPos - 1)
                                        }
                                    }
                                )) {
                                    ForEach(1...total, id: \.self) { num in
                                        Text("Nomor \(num)").tag(num)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 95)

                                Button {
                                    editRoute { planner.moveWaypointOrder(selected.id, toIndex: index - 1) }
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .help("Pindahkan urutan lebih awal (sebelumnya)")
                                .controlSize(.small)
                                .disabled(index == 0)

                                Button {
                                    editRoute { planner.moveWaypointOrder(selected.id, toIndex: index + 1) }
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .help("Pindahkan urutan lebih akhir (berikutnya)")
                                .controlSize(.small)
                                .disabled(index >= total - 1)
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if !planner.draft.waypoints.isEmpty {
                        Text("Klik pin angka pada peta untuk mengubah nomor urutan atau menghapusnya.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if planner.canResetToFarm {
                        Button {
                            editRoute {
                                planner.resetToFarm()
                            }
                        } label: {
                            Label("Reset ke Batas Petani", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    if planner.draft.waypoints.count < 3 {
                        Text("Minimal 3 titik batas untuk membentuk poligon survei.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(!canEditRoute)

            Button {
                planner.planningStep = .flight
            } label: {
                HStack {
                    Text("Lanjut ke Parameter Terbang")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .kropsPrimaryAction(size: .large)
            .disabled(!canEditRoute || planner.draft.waypoints.count < 3)
        }
    }

    private var mapToolbar: some View {
        HStack(spacing: 8) {
            if planner.planningStep == .boundary {
                Picker("Mode", selection: $planner.mode) {
                    Label("Pilih", systemImage: "arrow.up.left.and.point.at.bounding.box").tag(FlightMapEditMode.inspect)
                    Label("+ Batas", systemImage: "plus").tag(FlightMapEditMode.waypoint)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(!canEditRoute)
            } else {
                Picker("Mode", selection: $planner.mode) {
                    Label("Pilih", systemImage: "arrow.up.left.and.point.at.bounding.box").tag(FlightMapEditMode.inspect)
                    Label("Home", systemImage: "house.fill").tag(FlightMapEditMode.home)
                    Label("Entry", systemImage: "arrow.right.to.line").tag(FlightMapEditMode.entry)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .disabled(!canEditRoute)
            }

            Button {
                editRoute { planner.undo() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Urungkan perubahan rute terakhir")
            .accessibilityLabel("Urungkan perubahan rute terakhir")
            .disabled(!canEditRoute || !planner.canUndo)

            Spacer(minLength: 8)

            if planner.planningStep == .boundary {
                Text("\(planner.draft.waypoints.count) titik batas · \(String(format: "%.2f ha", planner.boundaryAreaHectares))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if routeMatchesMission {
                if let stats = planner.draft.surveyStatistics, stats.totalDistanceMeters > 0 {
                    let durationText = stats.flightTimeSeconds > 0 ? " · \(Self.formattedDuration(stats.flightTimeSeconds))" : ""
                    Text(String(format: "%d foto · %.0f m%@",
                                stats.photoCount, stats.totalDistanceMeters, durationText))
                        .font(.caption).foregroundStyle(.secondary)
                } else if !planner.draft.visualTransects.isEmpty {
                    Text(String(format: "%d titik · %.0f m",
                                planner.draft.visualTransects.count, planner.draft.distance))
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        if planner.planningStep == .boundary {
            switch planner.mode {
            case .waypoint:
                return "Klik pada peta untuk menambah titik sudut batas kebun."
            case .inspect, .home, .entry:
                return "Geser pin angka (1, 2, 3...) untuk menyesuaikan bentuk batas kebun."
            }
        } else {
            switch planner.mode {
            case .home:
                return "Klik di mana saja pada peta untuk menentukan posisi Home (lepas landas/mendarat)."
            case .entry:
                return "Klik pada garis batas kebun untuk menentukan titik masuk survei (Entry)."
            case .inspect, .waypoint:
                return "Geser pin Home (H) atau Entry (E) pada peta untuk menyesuaikan posisinya."
            }
        }
    }

    private func addPoint(_ coordinate: MapCoordinate) {
        guard canEditRoute, planner.mode != .inspect, coordinate.isValid else { return }
        if planner.planningStep == .boundary {
            guard planner.mode == .waypoint else { return }
            editRoute {
                planner.addWaypoint(coordinate)
            }
        } else {
            guard planner.mode == .home || planner.mode == .entry else { return }
            let currentMode = planner.mode
            editRoute {
                planner.mapClick(coordinate)
                if currentMode == .home || currentMode == .entry {
                    planner.mode = .inspect
                }
            }
        }
    }

    private func editRoute(_ change: () -> Void) {
        guard canEditRoute else { return }
        let previous = planner.draft
        change()
        if planner.draft != previous { model.geometry.reviewed = false }
    }

    static func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let secs = total % 60
            return "\(hours) jam \(minutes) mnt \(secs) dtk"
        } else if total >= 60 {
            let minutes = total / 60
            let secs = total % 60
            return "\(minutes) mnt \(secs) dtk"
        } else {
            return "\(total) dtk"
        }
    }
}
