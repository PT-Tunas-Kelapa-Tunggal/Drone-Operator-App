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
    var onStartFlight: (() -> Void)? = nil
    @State private var focusOperator = false
    @State private var requestedLocation = false
    @State private var inspectorVisible = true
    @State private var summaryVisible = true
    @State private var inspectorContentHeight: CGFloat = 400
    @State private var keyMonitor: Any?
    @State private var replanPending = false
    @State private var replanDebounceTask: Task<Void, Never>? = nil

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
    private var canProceedToFlight: Bool { boundaryReady && planner.isAreaConfirmed }
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
                editRoute {
                    planner.draft.home = coordinate
                    replanDebounced()
                }
            },
            onEntryMove: { coordinate in
                editRoute {
                    planner.moveEntry(to: coordinate)
                    replanDebounced()
                }
            },
            onInsertBoundary: { index, coordinate in
                editRoute { planner.addWaypoint(coordinate, at: index) }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                if inspectorVisible {
                    inspector.transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    // Same spot as the toggle inside the panel header.
                    panelToggle(.leading).padding(5).kropsFloatingControl(in: Capsule())
                        .padding(.leading, 11).padding(.top, 9)
                }
                ViewThatFits(in: .horizontal) {
                    centerIslands(compact: false)
                    centerIslands(compact: true)
                }
                .frame(maxWidth: .infinity)
                if summaryVisible {
                    summaryPanel.transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    panelToggle(.trailing).padding(5).kropsFloatingControl(in: Capsule())
                        .padding(.trailing, 11).padding(.top, 11)
                }
            }
            .padding(14)
            .padding(.bottom, 56)  // Keeps the inspector clear of the hint pill.
        }
        .overlay(alignment: .bottom) { hint.padding(.bottom, 18) }
        .animation(.snappy(duration: 0.22), value: inspectorVisible)
        .animation(.snappy(duration: 0.22), value: summaryVisible)
        .onAppear {
            guard let mission = model.selectedMission else { return }
            planner.open(
                farm: mission.area, name: "Rute " + mission.plan.name,
                altitude: model.geometry.heightAGL, speed: model.geometry.speed, missionID: mission.id)
            // Default to inspect (Pilih) mode so operator can pan and select without accidental point additions.
            planner.mode = .inspect
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: planner.selectedWaypointID) { _, id in
            if id != nil && planner.planningStep == .boundary {
                planner.planningStep = .boundary
            }
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

    /// Tools, history and view controls sit together between the panels; tool labels
    /// drop away when the map is too narrow for them.
    private func centerIslands(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            toolPalette(compact: compact)
            historyIsland
            HStack(spacing: 2) {
                PlanIconButton(systemImage: "location", help: "Ke lokasi saya") {
                    requestedLocation = true
                    location.request()
                }
                PlanIconButton(
                    systemImage: "arrow.up.left.and.arrow.down.right", help: "Tampilkan seluruh rute"
                ) {
                    focusOperator = false
                    planner.fitRoute()
                }
            }
            .padding(5)
            .kropsFloatingControl(in: Capsule())
        }
        .fixedSize()
    }

    private func panelToggle(_ edge: HorizontalEdge) -> some View {
        let left = edge == .leading
        let visible = left ? inspectorVisible : summaryVisible
        return PlanIconButton(
            systemImage: left ? "sidebar.left" : "sidebar.right",
            help: (visible ? "Sembunyikan " : "Tampilkan ") + (left ? "panel pengaturan" : "ringkasan"),
            selected: visible
        ) {
            if left { inspectorVisible.toggle() } else { summaryVisible.toggle() }
        }
    }

    private var historyIsland: some View {
        HStack(spacing: 2) {
            PlanIconButton(systemImage: "arrow.uturn.backward", help: "Urungkan (⌘Z)") {
                editRoute { planner.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canEditRoute || !planner.canUndo)
            PlanIconButton(systemImage: "arrow.uturn.forward", help: "Ulangi (⇧⌘Z)") {
                editRoute { planner.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!canEditRoute || !planner.canRedo)
        }
        .padding(5)
        .kropsFloatingControl(in: Capsule())
    }

    private func toolPalette(compact: Bool) -> some View {
        HStack(spacing: 2) {
            Group {
                if planner.planningStep == .boundary {
                    PlanToolButton(
                        title: "Pilih", compact: compact, systemImage: "cursorarrow", shortcut: "V",
                        selected: planner.mode == .inspect,
                        help: "Pilih & geser pin"
                    ) { selectTool(.inspect) }
                    PlanToolButton(
                        title: "Titik", compact: compact, systemImage: "pencil.and.outline", shortcut: "P",
                        selected: planner.mode == .waypoint,
                        help: "Tambah titik batas (klik dekat garis untuk menyisipkan)",
                        tint: .orange
                    ) { selectTool(.waypoint) }
                } else {
                    PlanToolButton(
                        title: "Home", compact: compact, systemImage: "house", shortcut: "H",
                        selected: planner.mode == .home,
                        help: "Taruh titik lepas landas & mendarat", tint: .green
                    ) { selectTool(.home) }
                    PlanToolButton(
                        title: "Entry", compact: compact, systemImage: "arrow.right.to.line", shortcut: "E",
                        selected: planner.mode == .entry,
                        help: "Taruh titik masuk survei di garis batas", tint: .cyan
                    ) { selectTool(.entry) }
                }
            }
            .disabled(!canEditRoute)
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
                .background(
                    GeometryReader { proxy in
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
            HStack(spacing: 8) {
                panelToggle(.leading)
                Picker("Lapisan", selection: Binding(get: { planner.planningStep }, set: { setLayer($0) })) {
                    Text("Area").tag(FlightPlanningStep.boundary)
                    Text("Jalur").tag(FlightPlanningStep.flight)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.extraLarge)
                .frame(maxWidth: .infinity)
                .help(
                    canProceedToFlight
                        ? "Pindah antara batas area dan jalur terbang"
                        : "Konfirmasi batas area terlebih dahulu untuk membuka langkah Jalur"
                )
            }
            HStack {
                Text(planner.planningStep == .boundary ? "Batas area" : "Jalur terbang")
                    .font(KropsTypography.sectionTitle)
                Spacer()
                if !canEditRoute {
                    Label("Hanya baca", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                } else if planner.planningStep == .flight && model.geometry.reviewed {
                    Label("Diperiksa", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(
                        .green)
                }
            }
            Text(
                planner.planningStep == .boundary
                    ? "Sesuaikan titik sudut agar sama dengan batas kebun di lapangan."
                    : "Atur parameter lalu hitung jalur. Taruh Home (H) dan Entry (E) di peta."
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var boundaryInspector: some View {
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

        if boundaryReady {
            Toggle(isOn: $planner.isAreaConfirmed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Konfirmasi batas area kebun").font(.body.weight(.medium))
                    Text("Batas perkebunan sudah sesuai dengan kondisi lapangan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!canEditRoute)
        }

        Button {
            setLayer(.flight)
        } label: {
            Label("Lanjut ke jalur terbang", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .kropsPrimaryAction(size: .large)
        .disabled(!canProceedToFlight)
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
            PlanSectionTitle("Kamera & Parameter")

            // Camera Header & Resolution (iPhone 17)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Kamera", systemImage: "camera")
                        .font(KropsTypography.supporting)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("iPhone 17")
                        .font(.callout.weight(.medium))
                }
                Picker(
                    "Resolusi",
                    selection: Binding(
                        get: { planner.draft.cameraResolution },
                        set: { res in
                            guard canEditRoute else { return }
                            planner.draft.cameraResolution = res
                            model.geometry.reviewed = false
                            replanLive()
                        }
                    )
                ) {
                    ForEach(CameraOpticalSpec.Resolution.allCases) { res in
                        Text(res.rawValue).tag(res)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                ControlField("Tinggi") {
                    NumberField(
                        Binding(
                            get: { model.geometry.heightAGL },
                            set: { val in
                                model.geometry.heightAGL = val
                                planner.draft.defaultAltitude = val
                                if planner.draft.geofence.ceilingMeters <= val {
                                    planner.draft.geofence.ceilingMeters = min(120.0, val + 20.0)
                                }
                                planner.resetChecklist()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        unit: "m"
                    )
                }
                .help("Tinggi kamera di atas tanah (AGL), bukan altitude GPS.")

                ControlField("Kecepatan") {
                    NumberField(
                        Binding(
                            get: { model.geometry.speed },
                            set: { val in
                                model.geometry.speed = val
                                planner.draft.speed = val
                                planner.resetChecklist()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        unit: "m/s"
                    )
                }
                .help("Kecepatan terbang horizontal sepanjang lintasan survei.")
            }

            HStack(spacing: 10) {
                ControlField("Kecepatan Naik") {
                    NumberField(
                        Binding(
                            get: { planner.draft.ascentSpeed },
                            set: { val in
                                guard canEditRoute else { return }
                                planner.draft.ascentSpeed = max(0.5, val)
                                planner.resetChecklist()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        unit: "m/s"
                    )
                }
                .help("Kecepatan vertikal saat lepas landas dan naik ke ketinggian misi (default 2.5 m/s).")

                ControlField("Kecepatan Turun") {
                    NumberField(
                        Binding(
                            get: { planner.draft.descentSpeed },
                            set: { val in
                                guard canEditRoute else { return }
                                planner.draft.descentSpeed = max(0.5, val)
                                planner.resetChecklist()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        unit: "m/s"
                    )
                }
                .help("Kecepatan vertikal saat turun dan mendarat (default 1.5 m/s).")
            }

            // Overlap Sliders
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Side Overlap").font(KropsTypography.supporting).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(planner.draft.sideOverlap.rounded()))%")
                            .font(.callout.weight(.semibold).monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { planner.draft.sideOverlap },
                            set: { val in
                                guard canEditRoute else { return }
                                planner.draft.sideOverlap = val.rounded()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        in: 30...85,
                        step: 1
                    )
                    .help(
                        "Persentase tumpang tindih antar jalur foto sejajar (rekomendasi kebun sawit: 70%).")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Frontal Overlap").font(KropsTypography.supporting).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(planner.draft.frontalOverlap.rounded()))%")
                            .font(.callout.weight(.semibold).monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { planner.draft.frontalOverlap },
                            set: { val in
                                guard canEditRoute else { return }
                                planner.draft.frontalOverlap = val.rounded()
                                model.geometry.reviewed = false
                                replanDebounced()
                            }
                        ),
                        in: 30...85,
                        step: 1
                    )
                    .help(
                        "Persentase tumpang tindih antar foto berturutan di sepanjang lintasan (rekomendasi kebun sawit: 75%)."
                    )
                }
            }

            calculatedMetricsBox

            angleSlider
            Toggle(
                "Kembali ke Home setelah selesai (RTL)",
                isOn: Binding(
                    get: { planner.draft.returnToHome },
                    set: { val in
                        guard canEditRoute else { return }
                        planner.draft.returnToHome = val
                        planner.resetChecklist()
                        model.geometry.reviewed = false
                        replanDebounced()
                    }
                )
            )
            .font(.callout)

            GeofenceInspectorSection(
                geofence: $planner.draft.geofence,
                safetyResult: planner.draft.safetyResult,
                canEdit: canEditRoute,
                onParameterChanged: {
                    planner.resetChecklist()
                    model.geometry.reviewed = false
                    replanDebounced()
                }
            )

            DisclosureGroup("Lanjutan") {
                HStack(spacing: 10) {
                    ControlField("Jarak putar") {
                        NumberField(
                            Binding(
                                get: { planner.draft.turnaroundDistance },
                                set: { val in
                                    guard canEditRoute else { return }
                                    let clamped = max(0, val)
                                    planner.draft.turnaroundDistance = clamped
                                    if planner.draft.geofence.bufferMeters < clamped + 10 {
                                        planner.draft.geofence.bufferMeters = clamped + 10
                                    }
                                    planner.resetChecklist()
                                    model.geometry.reviewed = false
                                    replanDebounced()
                                }
                            ),
                            unit: "m"
                        )
                    }
                    .help("Jarak manuver putar balik di luar batas kebun.")

                    ControlField("Jeda titik") {
                        NumberField(
                            Binding(
                                get: { planner.draft.holdSeconds },
                                set: { val in
                                    guard canEditRoute else { return }
                                    planner.draft.holdSeconds = min(60, max(0, val))
                                    planner.resetChecklist()
                                    model.geometry.reviewed = false
                                    replanDebounced()
                                }
                            ),
                            unit: "dtk"
                        )
                    }
                    .help("Durasi berhenti (hold) umum pada setiap titik waypoint survei (0–60 detik).")
                }
                .padding(.top, 8)
            }
            .font(.callout)
        }
        .disabled(model.editingLocked)

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
    }

    private var calculatedMetricsBox: some View {
        let stats = planner.draft.surveyStatistics
        let spacingText = stats.map { String(format: "%.1f m", $0.calculatedLineSpacing) } ?? "—"
        let triggerText = stats.map { String(format: "%.1f m", $0.calculatedTriggerDistance) } ?? "—"
        let gsdText = stats.map { String(format: "%.2f cm/px", $0.groundResolutionCmPerPx) } ?? "—"

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarak Jalur").font(.caption2).foregroundStyle(.secondary)
                Text(spacingText).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarak Foto").font(.caption2).foregroundStyle(.secondary)
                Text(triggerText).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("GSD Tanah").font(.caption2).foregroundStyle(.secondary)
                Text(gsdText).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

    /// Debounced trigger for smooth live planning when editing sliders or typing fields.
    private func replanDebounced() {
        guard canEditRoute, boundaryReady else { return }
        replanDebounceTask?.cancel()
        replanDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            replanLive()
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
            sideOverlap: planner.draft.sideOverlap,
            frontalOverlap: planner.draft.frontalOverlap,
            cameraResolution: planner.draft.cameraResolution,
            lineSpacing: planner.draft.lineSpacing,
            triggerDistance: planner.draft.triggerDistance,
            turnaroundDistance: planner.draft.turnaroundDistance,
            entryLocation: planner.draft.entryLocation,
            fitsRoute: fitsRoute
        )
    }

    // MARK: - Summary

    /// Read-only overview of the plan; the SOP checklist must be completed before the final review checkbox unlocks.
    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ringkasan rencana").font(KropsTypography.sectionTitle)
                Spacer()
                if model.geometry.reviewed && planner.isSOPChecklistComplete {
                    Label("Diperiksa", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                panelToggle(.trailing)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        PlanSectionTitle("Area")
                        PlanSummaryRow("Luas", String(format: "%.2f ha", planner.boundaryAreaHectares))
                        PlanSummaryRow("Keliling", String(format: "%.0f m", planner.boundaryPerimeterMeters))
                        PlanSummaryRow("Titik batas", "\(planner.draft.waypoints.count)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        PlanSectionTitle("Lepas landas & masuk")
                        PlanStatusRow(
                            "Home", glyph: "H", color: .green, placed: planner.draft.home != nil,
                            status: planner.draft.home == nil ? "Belum · tekan H" : "Sudah ditaruh")
                        PlanStatusRow(
                            "Entry", glyph: "E", color: .cyan, placed: planner.draft.surveyEntry != nil,
                            status: planner.draft.surveyEntry == nil ? "Belum · tekan E" : "Sudah ditaruh")
                        PlanSummaryRow("Kembali ke Home", planner.draft.returnToHome ? "Ya" : "Tidak")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        PlanSectionTitle("Jalur")
                        if let stats = planner.draft.surveyStatistics, stats.totalDistanceMeters > 0 {
                            PlanSummaryRow("Foto", "\(stats.photoCount)")
                            PlanSummaryRow(
                                "Jarak terbang", String(format: "%.0f m", stats.totalDistanceMeters))
                            PlanSummaryRow("Durasi", Self.formattedDuration(stats.flightTimeSeconds))
                            PlanSummaryRow("Lintasan", "\(stats.transectCount)")
                            PlanSummaryRow(
                                "Kecepatan (H/↑/↓)",
                                String(
                                    format: "%.1f / %.1f / %.1f m/s", planner.draft.speed,
                                    planner.draft.ascentSpeed, planner.draft.descentSpeed)
                            )
                            PlanSummaryRow(
                                "Jeda titik", String(format: "%.0f dtk", planner.draft.holdSeconds))
                        } else {
                            Text("Belum dihitung").font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        PlanSectionTitle("Geofence & keamanan")
                        if let safety = planner.draft.safetyResult, safety.enabled {
                            PlanSummaryRow("Tipe", safety.type.title)
                            if safety.type == .polygon {
                                PlanSummaryRow("Buffer", String(format: "%.0f m", safety.bufferMeters))
                            } else {
                                PlanSummaryRow("Radius", String(format: "%.0f m", safety.circleRadiusMeters))
                            }
                            PlanSummaryRow("Ceiling", String(format: "%.0f m", safety.ceilingMeters))
                            PlanSummaryRow("Aksi", safety.breachAction.title)
                            PlanSummaryRow(
                                "Cakupan QGC",
                                safety.coversMission && safety.ceilingOk ? "Aman" : "Perlu dicek")
                        } else {
                            Text(planner.draft.geofence.enabled ? "Menunggu QGC" : "Nonaktif")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    if pathReady {
                        Divider()
                        PreflightChecklistView(
                            planner: planner,
                            canEdit: canEditRoute && !model.editingLocked,
                            onChecklistChanged: {
                                if !planner.isSOPChecklistComplete {
                                    model.geometry.reviewed = false
                                }
                            }
                        )

                        Divider()
                        Toggle(
                            isOn: Binding(
                                get: { model.geometry.reviewed && planner.isSOPChecklistComplete },
                                set: { val in
                                    guard planner.isSOPChecklistComplete else {
                                        model.geometry.reviewed = false
                                        return
                                    }
                                    model.geometry.reviewed = val
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rencana sudah diperiksa").font(.body.weight(.medium))
                                Text(
                                    planner.isSOPChecklistComplete
                                        ? "Seluruh checklist SOP telah diverifikasi."
                                        : "Selesaikan seluruh 11 item checklist SOP di atas untuk mengaktifkan."
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(model.editingLocked || !canEditRoute || !planner.isSOPChecklistComplete)

                        if model.geometry.reviewed && planner.isSOPChecklistComplete {
                            Button {
                                onStartFlight?()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "airplane.departure")
                                    Text("Lanjut ke Penerbangan")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .kropsPrimaryAction(size: .large)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 290)
        .kropsFloatingPanel()
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
            return (
                "pencil.and.outline",
                "Klik peta untuk menambah titik · klik dekat garis untuk menyisipkan · Esc selesai"
            )
        case .home:
            return ("house", "Klik peta untuk menaruh Home · Esc batal")
        case .entry:
            return ("arrow.right.to.line", "Klik dekat garis batas untuk menaruh Entry · Esc batal")
        case .inspect:
            if planner.planningStep == .boundary {
                if let selected = planner.selectedWaypoint,
                    let index = planner.draft.waypoints.firstIndex(where: { $0.id == selected.id })
                {
                    return (
                        "cursorarrow",
                        "Titik \(index + 1) terpilih · geser untuk memindah · Delete hapus · Esc batal pilih"
                    )
                }
                if !boundaryReady {
                    return ("pencil.and.outline", "Tekan P lalu klik peta untuk menggambar batas kebun")
                }
                return (
                    "cursorarrow",
                    "Geser pin untuk memindah · klik pin untuk memilih · seret peta untuk menggeser"
                )
            } else {
                return ("cursorarrow", "Taruh Home (H) dan Entry (E) · geser peta untuk navigasi")
            }
        }
    }

    // MARK: - Actions

    private func setLayer(_ step: FlightPlanningStep) {
        guard planner.planningStep != step else { return }
        if step == .flight {
            guard canProceedToFlight else { return }
            planner.planningStep = .flight
            planner.selectedWaypointID = nil
            if planner.mode == .waypoint { planner.mode = .inspect }
        } else {
            planner.planningStep = .boundary
            if planner.mode == .home || planner.mode == .entry { planner.mode = .inspect }
        }
    }

    /// Tools behave like a design app: Titik stays active for repeated clicks,
    /// Home and Entry place once and return to Pilih.
    private func selectTool(_ mode: FlightMapEditMode) {
        guard canEditRoute || mode == .inspect else { return }
        if planner.planningStep == .boundary {
            guard mode == .inspect || mode == .waypoint else { return }
        } else {
            guard mode == .inspect || mode == .home || mode == .entry else { return }
        }
        planner.mode = mode
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
                replanDebounced()
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
        case "v":
            selectTool(.inspect)
        case "p", "b":
            if planner.planningStep == .boundary { selectTool(.waypoint) }
        case "h":
            if planner.planningStep == .flight { selectTool(.home) }
        case "e":
            if planner.planningStep == .flight { selectTool(.entry) }
        default:
            return false
        }
        return true
    }

    private func editRoute(_ change: () -> Void) {
        guard canEditRoute else { return }
        let previous = planner.draft
        change()
        if planner.draft != previous {
            planner.resetChecklist()
            model.geometry.reviewed = false
        }
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
    var compact = false
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
                if !compact { Text(title) }
                Text(shortcut)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(
                        (selected ? Color.white : Color.primary).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 4))
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
        .accessibilityLabel(title)
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

private struct PlanSummaryRow: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.callout)
    }
}

private struct PlanStatusRow: View {
    let title: String
    let glyph: String
    let color: Color
    let placed: Bool
    let status: String
    init(_ title: String, glyph: String, color: Color, placed: Bool, status: String) {
        self.title = title
        self.glyph = glyph
        self.color = color
        self.placed = placed
        self.status = status
    }
    var body: some View {
        HStack(spacing: 8) {
            Text(glyph)
                .font(.caption2.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(placed ? color : Color.secondary.opacity(0.4), in: Circle())
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(status).fontWeight(.semibold).foregroundStyle(placed ? Color.primary : Color.secondary)
        }
        .font(.callout)
    }
}
