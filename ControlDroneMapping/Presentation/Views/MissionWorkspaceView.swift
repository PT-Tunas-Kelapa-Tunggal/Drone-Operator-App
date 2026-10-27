import AppKit
import SwiftUI

/// Map-first planning canvas: the map fills the tab, native tools float above it and
/// a grouped-form inspector follows the active layer (boundary area or flight path).
struct MissionWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    @State private var focusOperator = false
    @State private var requestedLocation = false
    @State private var inspectorVisible = true
    @State private var keyMonitor: Any?

    private let inspectorWidth: CGFloat = 320
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
    private var boundaryReady: Bool { planner.draft.waypoints.count >= 3 }
    private var pathReady: Bool { !planner.draft.visualTransects.isEmpty }
    /// Leaves room for the inspector so centered overlays sit over the visible map.
    private var mapInset: CGFloat { inspectorVisible ? inspectorWidth + 12 : 0 }

    var body: some View {
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
            },
            canvas: true,
            onInsertBoundary: { index, coordinate in
                editRoute { planner.addWaypoint(coordinate, at: index) }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .leading) {
            if inspectorVisible {
                inspector
                    .padding([.leading, .vertical], 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) { topBar.padding(12).padding(.leading, mapInset) }
        .overlay(alignment: .bottom) { hint.padding(.bottom, 18).padding(.leading, mapInset) }
        .animation(.snappy(duration: 0.22), value: inspectorVisible)
        .onAppear {
            guard let mission = model.selectedMission else { return }
            planner.open(
                farm: mission.area, name: "Rute " + mission.plan.name,
                altitude: model.geometry.heightAGL, speed: model.geometry.speed, missionID: mission.id)
            planner.mode = .inspect
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: planner.selectedWaypointID) { _, id in
            if id != nil { planner.planningStep = .boundary }
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

    // MARK: - Floating toolbar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(inspectorVisible ? "Sembunyikan panel" : "Tampilkan panel", systemImage: "sidebar.left") {
                inspectorVisible.toggle()
            }
            .labelStyle(.iconOnly)
            .kropsToolbarAction()
            .help(inspectorVisible ? "Sembunyikan panel" : "Tampilkan panel")

            Spacer(minLength: 0)

            Picker("Alat", selection: toolBinding) {
                Label("Pilih", systemImage: "cursorarrow").tag(FlightMapEditMode.inspect)
                Label("Titik", systemImage: "pencil.and.outline").tag(FlightMapEditMode.waypoint)
                Label("Home", systemImage: "house").tag(FlightMapEditMode.home)
                Label("Entry", systemImage: "arrow.right.to.line").tag(FlightMapEditMode.entry)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!canEditRoute)
            .help("Pilih (V) · Titik (P) · Home (H) · Entry (E) · Esc kembali ke Pilih")

            Button("Urungkan", systemImage: "arrow.uturn.backward") { editRoute { planner.undo() } }
                .labelStyle(.iconOnly)
                .kropsToolbarAction()
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canEditRoute || !planner.canUndo)
                .help("Urungkan (⌘Z)")

            Spacer(minLength: 0)

            ControlGroup {
                Button("Ke lokasi saya", systemImage: "location") {
                    requestedLocation = true
                    location.request()
                }
                .help("Ke lokasi saya")
                Button("Tampilkan seluruh rute", systemImage: "arrow.up.left.and.arrow.down.right") {
                    focusOperator = false
                    planner.fitRoute()
                }
                .help("Tampilkan seluruh rute")
            }
            .labelStyle(.iconOnly)
            .fixedSize()
        }
    }

    private var toolBinding: Binding<FlightMapEditMode> {
        Binding(get: { planner.mode }, set: { selectTool($0) })
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Lapisan", selection: Binding(get: { planner.planningStep }, set: { setLayer($0) })) {
                Text("Area").tag(FlightPlanningStep.boundary)
                Text("Jalur").tag(FlightPlanningStep.flight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 12)

            Form {
                if !canEditRoute {
                    Section {
                        Label("Rute hanya baca selama operasi atau setelah misi selesai.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if planner.planningStep == .boundary {
                    boundarySections
                } else {
                    flightSections
                }
                if planner.error != nil || planner.storageError != nil {
                    Section {
                        ForEach([planner.error, planner.storageError].compactMap { $0 }, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            primaryAction.padding(12)
        }
        .frame(width: inspectorWidth)
        .frame(maxHeight: .infinity)
        .kropsFloatingPanel()
    }

    @ViewBuilder
    private var boundarySections: some View {
        Section {
            LabeledContent("Luas", value: String(format: "%.2f ha", planner.boundaryAreaHectares))
            LabeledContent("Keliling", value: String(format: "%.0f m", planner.boundaryPerimeterMeters))
        } header: {
            Text("Batas area")
        } footer: {
            Text("Sesuaikan titik sudut agar sama dengan batas kebun di lapangan.")
        }

        Section {
            if planner.draft.waypoints.isEmpty {
                Text("Tekan P lalu klik peta untuk menggambar batas.").foregroundStyle(.secondary)
            }
            ForEach(Array(planner.draft.waypoints.enumerated()), id: \.element.id) { index, point in
                boundaryRow(index: index, point: point)
            }
            if planner.canResetToFarm {
                Button("Kembalikan ke batas petani", systemImage: "arrow.counterclockwise") {
                    editRoute { planner.resetToFarm() }
                }
            }
        } header: {
            Text("Titik sudut · \(planner.draft.waypoints.count)")
        } footer: {
            if boundaryReady {
                Text("Klik kanan titik untuk mengubah urutan atau menghapusnya.")
            } else {
                Label("Minimal 3 titik untuk membentuk area survei.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .disabled(!canEditRoute)
    }

    private func boundaryRow(index: Int, point: FlightWaypoint) -> some View {
        let selected = planner.selectedWaypointID == point.id
        let total = planner.draft.waypoints.count
        return LabeledContent {
            if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
        } label: {
            Label {
                Text(String(format: "%.5f, %.5f", point.coordinate.latitude, point.coordinate.longitude))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "\(index + 1).circle.fill")
                    .foregroundStyle(selected ? Color.accentColor : Color.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { planner.selectedWaypointID = selected ? nil : point.id }
        .contextMenu {
            Button("Pindah ke urutan sebelumnya", systemImage: "arrow.up") {
                editRoute { planner.moveWaypointOrder(point.id, toIndex: index - 1) }
            }
            .disabled(index == 0)
            Button("Pindah ke urutan berikutnya", systemImage: "arrow.down") {
                editRoute { planner.moveWaypointOrder(point.id, toIndex: index + 1) }
            }
            .disabled(index >= total - 1)
            Divider()
            Button("Hapus titik", systemImage: "trash", role: .destructive) {
                editRoute { planner.removeWaypoint(point.id) }
            }
            .disabled(total <= 3)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var flightSections: some View {
        Section("Parameter terbang") {
            numberRow("Tinggi terbang", $model.geometry.heightAGL, unit: "m", step: 5, range: 10...500)
                .help("Tinggi kamera di atas tanah (AGL), bukan altitude GPS.")
            numberRow("Kecepatan", $model.geometry.speed, unit: "m/s", step: 0.5, range: 0.5...20)
            numberRow("Jarak antar jalur", $planner.draft.lineSpacing, unit: "m", step: 1, range: 1...200)
                .help("Jarak antar lintasan sejajar drone.")
            numberRow("Sudut jalur", $planner.draft.gridAngle, unit: "°", step: 5, range: 0...359)
                .help("Arah lintasan terhadap utara.")
            DisclosureGroup("Lanjutan") {
                numberRow("Jarak antar foto", $planner.draft.triggerDistance, unit: "m", step: 1, range: 1...200)
                numberRow("Jarak putar balik", $planner.draft.turnaroundDistance, unit: "m", step: 1, range: 0...100)
            }
        }
        .disabled(!canEditRoute || model.editingLocked)

        Section("Lepas landas & masuk") {
            pointRow(
                "Home", systemImage: "h.circle.fill", color: .green, mode: .home,
                detail: planner.draft.home == nil ? "Belum ditentukan" : "Lepas landas & mendarat",
                placed: planner.draft.home != nil)
            pointRow(
                "Entry", systemImage: "e.circle.fill", color: .cyan, mode: .entry,
                detail: planner.draft.surveyEntry == nil ? "Otomatis dari jalur" : "Titik masuk di garis batas",
                placed: planner.draft.surveyEntry != nil)
            Toggle("Kembali ke Home (RTL)", isOn: $planner.draft.returnToHome)
                .toggleStyle(.switch)
        }
        .disabled(!canEditRoute)

        if let stats = planner.draft.surveyStatistics, stats.totalDistanceMeters > 0 {
            Section("Hasil jalur") {
                LabeledContent("Foto", value: "\(stats.photoCount)")
                LabeledContent("Jarak terbang", value: String(format: "%.0f m", stats.totalDistanceMeters))
                if stats.flightTimeSeconds > 0 {
                    LabeledContent("Estimasi durasi", value: Self.formattedDuration(stats.flightTimeSeconds))
                }
                LabeledContent("Lintasan", value: "\(stats.transectCount)")
            }
            Section {
                Toggle("Rencana sudah diperiksa", isOn: $model.geometry.reviewed)
                    .toggleStyle(.switch)
            } footer: {
                Text("Pastikan Home, Entry, dan jalur sesuai kondisi lapangan.")
            }
            .disabled(model.editingLocked)
        }
    }

    private func numberRow(
        _ title: String, _ value: Binding<Double>, unit: String, step: Double, range: ClosedRange<Double>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(unit).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                Stepper(title, value: value, in: range, step: step).labelsHidden()
            }
        }
    }

    private func pointRow(
        _ title: String, systemImage: String, color: Color, mode: FlightMapEditMode, detail: String, placed: Bool
    ) -> some View {
        let active = planner.mode == mode
        return LabeledContent {
            Button(active ? "Batal" : (placed ? "Pindah" : "Taruh")) {
                selectTool(active ? .inspect : mode)
            }
        } label: {
            Label {
                Text(title)
                Text(active ? "Klik pada peta…" : detail)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(placed ? color : Color.secondary)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if planner.planningStep == .boundary {
            Button {
                setLayer(.flight)
            } label: {
                Label("Lanjut ke jalur terbang", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }
            .kropsPrimaryAction(size: .large)
            .disabled(!boundaryReady)
        } else {
            Button {
                Task {
                    await planner.generateSurveyWaypoints(
                        altitude: model.geometry.heightAGL,
                        speed: model.geometry.speed,
                        gridAngle: planner.draft.gridAngle,
                        lineSpacing: planner.draft.lineSpacing,
                        triggerDistance: planner.draft.triggerDistance,
                        turnaroundDistance: planner.draft.turnaroundDistance,
                        entryLocation: planner.draft.entryLocation
                    )
                }
            } label: {
                HStack {
                    if planner.isGeneratingWaypoints {
                        ProgressView().controlSize(.small)
                        Text("Menghitung di QGC…")
                    } else {
                        Label(
                            pathReady ? "Hitung ulang jalur" : "Hitung jalur survei",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .kropsPrimaryAction(size: .large)
            .disabled(!canEditRoute || planner.isGeneratingWaypoints || !boundaryReady)
        }
    }

    // MARK: - Hint

    private var hint: some View {
        let (icon, text) = mapAdvice
        return Label(text, systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .kropsFloatingControl(in: Capsule())
            .animation(nil, value: text)
    }

    private var mapAdvice: (String, String) {
        if requestedLocation && location.sample == nil { return ("location", location.status) }
        if !canEditRoute {
            return ("lock.fill", "Rute hanya baca selama operasi misi atau setelah misi selesai.")
        }
        switch planner.mode {
        case .waypoint:
            return ("pencil.and.outline", "Klik peta untuk menambah titik · klik dekat garis untuk menyisipkan · Esc selesai")
        case .home:
            return ("house", "Klik peta untuk menaruh Home · Esc batal")
        case .entry:
            return ("arrow.right.to.line", "Klik dekat garis batas untuk menaruh Entry · Esc batal")
        case .inspect:
            if let selected = planner.selectedWaypoint,
                let index = planner.draft.waypoints.firstIndex(where: { $0.id == selected.id })
            {
                return ("cursorarrow", "Titik \(index + 1) terpilih · geser untuk memindah · Delete hapus · Esc batal pilih")
            }
            if !boundaryReady { return ("pencil.and.outline", "Tekan P lalu klik peta untuk menggambar batas kebun") }
            return ("cursorarrow", "Geser pin untuk memindah · klik pin untuk memilih · seret peta untuk menggeser")
        }
    }

    // MARK: - Actions

    private func setLayer(_ step: FlightPlanningStep) {
        guard planner.planningStep != step else { return }
        planner.planningStep = step
        if step == .flight { planner.selectedWaypointID = nil }
    }

    /// Tools behave like a design app: Titik stays active for repeated clicks,
    /// Home and Entry place once and return to Pilih.
    private func selectTool(_ mode: FlightMapEditMode) {
        guard canEditRoute || mode == .inspect else { return }
        if (mode == .home || mode == .entry) && !boundaryReady { return }
        planner.mode = mode
        switch mode {
        case .waypoint: setLayer(.boundary)
        case .home, .entry: setLayer(.flight)
        case .inspect: break
        }
    }

    private func addPoint(_ coordinate: MapCoordinate) {
        guard canEditRoute, coordinate.isValid else { return }
        switch planner.mode {
        case .waypoint:
            editRoute { planner.addWaypoint(coordinate) }
        case .home, .entry:
            editRoute {
                planner.mapClick(coordinate)
                planner.mode = .inspect
            }
        case .inspect:
            break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    /// Single-key tool shortcuts. Ignored while a text field is being edited.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window?.isKeyWindow == true, event.window?.attachedSheet == nil,
            !(event.window?.firstResponder is NSText),
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        switch event.keyCode {
        case 53:  // Escape
            if planner.mode != .inspect {
                planner.mode = .inspect
            } else if planner.selectedWaypointID != nil {
                planner.selectedWaypointID = nil
            } else {
                return false
            }
            return true
        case 51, 117:  // Delete, Forward delete
            guard let id = planner.selectedWaypointID, canEditRoute, planner.draft.waypoints.count > 3
            else { return false }
            editRoute { planner.removeWaypoint(id) }
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": selectTool(.inspect)
        case "p", "b": selectTool(.waypoint)
        case "h": selectTool(.home)
        case "e": selectTool(.entry)
        default: return false
        }
        return true
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
