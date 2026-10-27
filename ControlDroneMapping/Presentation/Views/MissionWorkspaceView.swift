import AppKit
import SwiftUI

/// Map-first planning canvas: the map fills the tab, tools float above it and a
/// contextual inspector follows the active layer (boundary area or flight path).
struct MissionWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    @State private var focusOperator = false
    @State private var requestedLocation = false
    @State private var inspectorVisible = true
    @State private var inspectorContentHeight: CGFloat = 400
    @State private var keyMonitor: Any?
    @State private var replanPending = false

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
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                if inspectorVisible {
                    inspector.transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(14)
            .padding(.bottom, 56)  // Keeps the inspector clear of the hint pill.
        }
        .overlay(alignment: .bottom) { hint.padding(.bottom, 18) }
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
        HStack(alignment: .top, spacing: 10) {
            PlanIconButton(
                systemImage: "sidebar.left", help: inspectorVisible ? "Sembunyikan panel" : "Tampilkan panel",
                selected: inspectorVisible
            ) { inspectorVisible.toggle() }
            .padding(5)
            .kropsFloatingControl(in: Capsule())

            Spacer(minLength: 0)
            toolPalette
            Spacer(minLength: 0)

            HStack(spacing: 2) {
                PlanIconButton(systemImage: "location", help: "Ke lokasi saya") {
                    requestedLocation = true
                    location.request()
                }
                PlanIconButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Tampilkan seluruh rute") {
                    focusOperator = false
                    planner.fitRoute()
                }
            }
            .padding(5)
            .kropsFloatingControl(in: Capsule())
        }
    }

    private var toolPalette: some View {
        HStack(spacing: 2) {
            Group {
                PlanToolButton(
                    title: "Pilih", systemImage: "cursorarrow", shortcut: "V", selected: planner.mode == .inspect,
                    help: "Pilih & geser pin"
                ) { selectTool(.inspect) }
                PlanToolButton(
                    title: "Titik", systemImage: "pencil.and.outline", shortcut: "P",
                    selected: planner.mode == .waypoint, help: "Tambah titik batas (klik dekat garis untuk menyisipkan)",
                    tint: .orange
                ) { selectTool(.waypoint) }
                PlanToolButton(
                    title: "Home", systemImage: "house", shortcut: "H", selected: planner.mode == .home,
                    help: "Taruh titik lepas landas & mendarat", tint: .green
                ) { selectTool(.home) }
                .disabled(!boundaryReady)
                PlanToolButton(
                    title: "Entry", systemImage: "arrow.right.to.line", shortcut: "E", selected: planner.mode == .entry,
                    help: "Taruh titik masuk survei di garis batas", tint: .cyan
                ) { selectTool(.entry) }
                .disabled(!boundaryReady)
            }
            .disabled(!canEditRoute)

            Divider().frame(height: 22).padding(.horizontal, 6)

            PlanIconButton(systemImage: "arrow.uturn.backward", help: "Urungkan (⌘Z)") {
                editRoute { planner.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canEditRoute || !planner.canUndo)
        }
        .padding(5)
        .kropsFloatingControl(in: Capsule())
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if planner.planningStep == .boundary {
                        boundaryInspector
                    } else {
                        flightInspector
                    }
                    if let error = planner.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if let error = planner.storageError {
                        Label(error, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                .padding(16)
                .disabled(!canEditRoute)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: InspectorHeightKey.self, value: proxy.size.height)
                })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: inspectorContentHeight)
        }
        .frame(width: 320)
        .onPreferenceChange(InspectorHeightKey.self) { inspectorContentHeight = $0 }
        .kropsFloatingPanel()
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Lapisan", selection: Binding(get: { planner.planningStep }, set: { setLayer($0) })) {
                Text("Area").tag(FlightPlanningStep.boundary)
                Text("Jalur").tag(FlightPlanningStep.flight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.extraLarge)
            .frame(maxWidth: .infinity)
            .help(boundaryReady ? "Pindah antara batas area dan jalur terbang" : "Jalur terbuka setelah ada minimal 3 titik batas")
            HStack {
                Text(planner.planningStep == .boundary ? "Batas area" : "Jalur terbang")
                    .font(KropsTypography.sectionTitle)
                Spacer()
                if !canEditRoute {
                    Label("Hanya baca", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                } else if planner.planningStep == .flight && model.geometry.reviewed {
                    Label("Diperiksa", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            }
            Text(
                planner.planningStep == .boundary
                    ? "Sesuaikan titik sudut agar sama dengan batas kebun di lapangan."
                    : "Atur parameter, tentukan Home & Entry, lalu hitung jalur survei."
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var boundaryInspector: some View {
        HStack(spacing: 8) {
            PlanMetric("Luas", String(format: "%.2f ha", planner.boundaryAreaHectares))
            PlanMetric("Keliling", String(format: "%.0f m", planner.boundaryPerimeterMeters))
            PlanMetric("Titik", "\(planner.draft.waypoints.count)")
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PlanSectionTitle("Titik sudut")
                Spacer()
                if planner.canResetToFarm {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        editRoute { planner.resetToFarm() }
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help("Kembalikan ke batas kebun dari data petani")
                }
            }
            Text(cornerSummary)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !boundaryReady {
                Label("Minimal 3 titik untuk membentuk area survei.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }

        Button {
            setLayer(.flight)
        } label: {
            Label("Lanjut ke jalur terbang", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .kropsPrimaryAction(size: .large)
        .disabled(!boundaryReady)
    }

    /// Points are edited on the map; the panel only says how.
    private var cornerSummary: String {
        if planner.draft.waypoints.isEmpty { return "Tekan P, lalu klik peta untuk mulai menggambar batas." }
        if let id = planner.selectedWaypointID,
            let index = planner.draft.waypoints.firstIndex(where: { $0.id == id })
        {
            return "Titik \(index + 1) terpilih · geser di peta · Delete untuk menghapus"
        }
        return "Klik pin di peta untuk memilih · P untuk menambah titik"
    }

    @ViewBuilder
    private var flightInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle("Parameter")
            HStack(spacing: 10) {
                ControlField("Tinggi") { NumberField($model.geometry.heightAGL, unit: "m") }
                    .help("Tinggi kamera di atas tanah (AGL), bukan altitude GPS.")
                ControlField("Kecepatan") { NumberField($model.geometry.speed, unit: "m/s") }
            }
            ControlField("Jarak jalur") { NumberField($planner.draft.lineSpacing, unit: "m") }
                .help("Jarak antar lintasan sejajar drone.")
            angleSlider
            DisclosureGroup("Lanjutan") {
                HStack(spacing: 10) {
                    ControlField("Jarak foto") { NumberField($planner.draft.triggerDistance, unit: "m") }
                        .help("Jarak pemicu kamera antar foto sepanjang lintasan.")
                    ControlField("Jarak putar") { NumberField($planner.draft.turnaroundDistance, unit: "m") }
                        .help("Jarak manuver putar balik di luar batas kebun.")
                }
                .padding(.top, 8)
            }
            .font(.callout)
        }
        .disabled(model.editingLocked)

        VStack(alignment: .leading, spacing: 6) {
            PlanSectionTitle("Lepas landas & masuk")
            PlanPointRow(
                title: "Home", detail: planner.draft.home == nil ? "Belum ditentukan · tekan H" : "Lepas landas & mendarat",
                glyph: "H", color: .green, set: planner.draft.home != nil, active: planner.mode == .home
            ) { selectTool(planner.mode == .home ? .inspect : .home) }
            PlanPointRow(
                title: "Entry",
                detail: planner.draft.surveyEntry == nil ? "Otomatis dari jalur · tekan E" : "Titik masuk di garis batas",
                glyph: "E", color: .cyan, set: planner.draft.surveyEntry != nil, active: planner.mode == .entry
            ) { selectTool(planner.mode == .entry ? .inspect : .entry) }
            Toggle("Kembali ke Home setelah selesai (RTL)", isOn: $planner.draft.returnToHome)
                .font(.callout).padding(.top, 4)
        }

        Button {
            Task { await generateSurvey() }
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
        .disabled(planner.isGeneratingWaypoints || !boundaryReady)

        if let stats = planner.draft.surveyStatistics, stats.totalDistanceMeters > 0 {
            VStack(alignment: .leading, spacing: 8) {
                PlanSectionTitle("Hasil jalur")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    PlanMetric("Foto", "\(stats.photoCount)")
                    PlanMetric("Jarak", String(format: "%.0f m", stats.totalDistanceMeters))
                    if stats.flightTimeSeconds > 0 {
                        PlanMetric("Durasi", Self.formattedDuration(stats.flightTimeSeconds))
                    }
                    PlanMetric("Lintasan", "\(stats.transectCount)")
                }
            }

            Toggle(isOn: $model.geometry.reviewed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rencana sudah diperiksa").font(.body.weight(.medium))
                    Text("Home, Entry, dan jalur sesuai kondisi lapangan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (model.geometry.reviewed ? Color.green : Color.primary).opacity(0.07),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .disabled(model.editingLocked)
        }
    }

    /// Dragging re-plans the survey live; the whole drag is one undo step.
    private var angleSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sudut jalur").font(KropsTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(planner.draft.gridAngle))
                    .foregroundStyle(.secondary)
                Text("\(Int(planner.draft.gridAngle.rounded()))°")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { planner.draft.gridAngle },
                    set: { angle in
                        guard canEditRoute else { return }
                        planner.draft.gridAngle = angle.rounded()
                        model.geometry.reviewed = false
                        replanLive()
                    }),
                in: 0...359
            ) { editing in
                if editing {
                    planner.beginContinuousEdit()
                } else {
                    planner.endContinuousEdit()
                    replanLive()
                }
            }
            .help("Arah lintasan terhadap utara. Jalur dihitung ulang saat digeser.")
        }
    }

    /// Runs one survey at a time; changes made while QGC is busy trigger one more run.
    private func replanLive() {
        guard canEditRoute, boundaryReady else { return }
        if planner.isGeneratingWaypoints {
            replanPending = true
            return
        }
        Task {
            await generateSurvey(fitsRoute: false)
            if replanPending {
                replanPending = false
                replanLive()
            }
        }
    }

    private func generateSurvey(fitsRoute: Bool = true) async {
        await planner.generateSurveyWaypoints(
            altitude: model.geometry.heightAGL,
            speed: model.geometry.speed,
            gridAngle: planner.draft.gridAngle,
            lineSpacing: planner.draft.lineSpacing,
            triggerDistance: planner.draft.triggerDistance,
            turnaroundDistance: planner.draft.turnaroundDistance,
            entryLocation: planner.draft.entryLocation,
            fitsRoute: fitsRoute
        )
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
        guard planner.planningStep != step, step == .boundary || boundaryReady else { return }
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

// MARK: - Canvas controls

private struct InspectorHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PlanIconButton: View {
    let systemImage: String
    let help: String
    var selected = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(selected ? KropsStyle.accent : Color.primary)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PlanToolButton: View {
    let title: String
    let systemImage: String
    let shortcut: String
    let selected: Bool
    let help: String
    var tint: Color = KropsStyle.selection
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                Text(shortcut)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(
                        (selected ? Color.white : Color.primary).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10).frame(height: 30)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? tint : Color.clear, in: Capsule())
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(help) (\(shortcut))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PlanSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

private struct PlanMetric: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlanPointRow: View {
    let title: String
    let detail: String
    let glyph: String
    let color: Color
    let set: Bool
    let active: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(glyph)
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(set ? color : Color.secondary.opacity(0.4), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(
            active ? color.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? color.opacity(0.6) : Color.clear))
    }
}
