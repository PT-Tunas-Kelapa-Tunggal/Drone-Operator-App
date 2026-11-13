import AppKit
import MapKit
import MultipeerConnectivity
import SwiftUI

enum ReviewTab: String, CaseIterable, Identifiable {
    case overview = "Ringkasan"
    case mission = "1. Rencana"
    case camera = "2. Kamera & uji"
    case capture = "3. Penerbangan"
    case imagery = "4. Foto"
    case results = "5. Hasil"
    var id: String { rawValue }
}

private enum ReviewResultLayer: String, CaseIterable, Identifiable {
    case orthomosaic = "Orthomosaic"
    case variAndHara = "VARI & HARA"
    case fertilizationTiming = "Jadwal Pemupukan"
    var id: String { rawValue }
}

/// Presentation only: capture and orthomosaic actions use the existing workflows.
struct ReviewWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    @ObservedObject var processing: OrthomosaicViewModel
    @ObservedObject private var engineManager = QGCEngineManager.shared
    let search: String
    let openPlanner: () -> Void
    let createMission: () -> Void
    let export: (MissionRecord) -> Void
    private let initialTab: ReviewTab?
    @State private var tab: ReviewTab
    @State private var resultLayer = ReviewResultLayer.orthomosaic
    @State private var importedProjectID: UUID?
    @State private var mapFocus = UUID()
    private let variProcessor: any VariProcessing
    private let timingProcessor: any VariTimingProcessing
    @State private var variResult: VariScanResult?
    @State private var isProcessingVari = false
    @State private var variError: String?
    @State private var timingResult: VariTimingExecutionResult?
    @State private var isProcessingTiming = false
    @State private var timingError: String?
    @State private var timingTask: Task<Void, Never>?
    @State private var selectedTimingNPK: ContractFertilizerType?
    @State private var timingFertilizerIDLookup: [String: ContractFertilizerType] = [:]
    @State private var showSavedConfirmation = false
    @State private var dispatchSuccessAt: Date?

    init(
        model: ControlViewModel, link: LocalLink, farms: FarmAreaViewModel,
        location: OperatorLocationViewModel, planner: FlightPlannerViewModel,
        processing: OrthomosaicViewModel,
        variProcessor: (any VariProcessing)? = nil,
        timingProcessor: (any VariTimingProcessing)? = nil,
        search: String,
        openPlanner: @escaping () -> Void, createMission: @escaping () -> Void,
        export: @escaping (MissionRecord) -> Void, tab: ReviewTab? = nil
    ) {
        self.model = model
        self.link = link
        self.farms = farms
        self.location = location
        self.planner = planner
        self.processing = processing
        self.variProcessor = variProcessor ?? ControlDependencies.variProcessor(demo: model.isDemo)
        self.timingProcessor = timingProcessor ?? ControlDependencies.timingProcessor(demo: model.isDemo)
        self.search = search
        self.openPlanner = openPlanner
        self.createMission = createMission
        self.export = export
        initialTab = tab
        _tab = State(initialValue: tab ?? .mission)
    }

    private var isOrthomosaicReady: Bool {
        guard let output else { return false }
        return FileManager.default.fileExists(atPath: output.image.path)
    }

    private func checkForCachedVariResult() {
        guard let output, isOrthomosaicReady else {
            variResult = nil
            return
        }
        if variResult == nil {
            variResult = try? variProcessor.loadCachedResult(from: output.folder)
        }
    }

    private var activeReviewRequest: PlantationReviewRequest? {
        model.reviewRequest(for: mission, fallbackID: record?.id)
    }

    private var resolvedOrthomosaicJPEGURL: URL? {
        if let url = variResult?.assets.sourceImageURL,
            FileManager.default.fileExists(atPath: url.path)
        {
            return url
        }
        guard let output else { return nil }
        let canonical = output.folder.appendingPathComponent(LocalVariProcessor.canonicalJPEGFileName)
        return FileManager.default.fileExists(atPath: canonical.path) ? canonical : nil
    }

    private var isTimingReadyForDispatch: Bool {
        guard let timingResult else { return false }
        return !timingResult.schedule.rounds.isEmpty
    }

    private var canDispatchCompletedReview: Bool {
        activeReviewRequest != nil
            && resolvedOrthomosaicJPEGURL != nil
            && variResult != nil
            && isTimingReadyForDispatch
            && !model.isDispatchingReview
            && !processing.busy
    }

    private var timingOutputFolder: URL {
        if let output {
            return output.folder
        }
        let fallbackID =
            mission?.id ?? record?.id ?? project?.id
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return VariTimingWeatherSettings.defaultTimingOutputFolder(for: fallbackID, demo: model.isDemo)
    }

    private var timingStorageKey: String {
        "\(timingOutputFolder.path)::\(model.isDemo)"
    }

    private var resolvedTimingCoordinate: VariTimingRequest.Coordinate? {
        if let centroid = activeReviewRequest?.centroidCoordinate {
            return VariTimingRequest.Coordinate(
                latitude: centroid.latitude,
                longitude: centroid.longitude
            )
        }
        return VariTimingRequest.centroid(of: mission?.area?.points)
    }

    private var pendingTimingBuild: VariTimingBuildOutput? {
        guard let request = activeReviewRequest, let variResult else { return nil }
        return try? VariTimingBuilder.makeRequest(
            from: request,
            variResult: variResult,
            preferredNPK: selectedTimingNPK
        )
    }

    private var timingContextSummary: VariTimingContextSummary {
        let blocker: String?
        if activeReviewRequest == nil {
            blocker =
                "Permintaan peninjauan CloudKit untuk misi ini belum tersinkronisasi. Tarik data CloudKit terlebih dahulu."
        } else if resolvedTimingCoordinate == nil {
            blocker = "Batas kebun (farmBoundary) dari CloudKit belum tersedia atau kosong."
        } else if variResult == nil {
            blocker =
                "Jalankan analisis VARI & HARA terlebih dahulu agar kebutuhan Dolomite, Urea, dan NPK komersial tersedia."
        } else if pendingTimingBuild == nil {
            blocker =
                "Data dosis pupuk pada hasil VARI & HARA tidak memenuhi syarat untuk menyusun jadwal pemupukan."
        } else {
            blocker = nil
        }

        let built = pendingTimingBuild
        return VariTimingContextSummary(
            farmName: activeReviewRequest?.garden.name ?? mission?.area?.name,
            coordinate: resolvedTimingCoordinate,
            fertilizingFrequencyPerYear: activeReviewRequest?.agronomy.fertilizingFrequencyPerYear,
            selectedNPKType: built?.selectedNPKType ?? selectedTimingNPK,
            dolomiteTotalKg: built?.dolomiteTotalKg ?? 0,
            ureaTotalKg: built?.ureaTotalKg ?? 0,
            npkTotalKg: built?.npkTotalKg ?? 0,
            blockerReason: blocker
        )
    }

    private func checkForCachedTimingResult() {
        if timingResult == nil {
            let cached = timingProcessor.loadCachedResult(in: timingOutputFolder)
            timingResult = cached
            syncSelectionFromCachedTiming(cached)
        }
    }

    private func syncSelectionFromCachedTiming(_ execution: VariTimingExecutionResult?) {
        guard let execution else { return }
        var resolved: [String: ContractFertilizerType] = [:]
        for item in execution.request.fertilizers {
            if let id = item.id,
                let contract = VariTimingBuilder.resolveContractType(fromID: id)
            {
                resolved[id] = contract
                if selectedTimingNPK == nil, contract != .dolomite, contract != .urea {
                    selectedTimingNPK = contract
                }
            }
        }
        timingFertilizerIDLookup = resolved
    }

    private var mission: SavedMission? {
        if model.step == .datasets {
            guard let id = model.selectedDatasetID else { return nil }
            return model.missionLibrary.missions.first { $0.id == id || $0.remoteID == id }
        }
        return model.hasMissionDetail ? model.selectedMission : nil
    }

    private var record: MissionRecord? {
        if let mission {
            return model.records.first { $0.id == mission.remoteID || $0.id == mission.id }
                ?? MissionRecord(
                    id: mission.remoteID ?? mission.id, createdAt: mission.createdAt,
                    plan: mission.plan, phase: mission.phase, saved: mission.saved)
        }
        guard model.step == .datasets else { return nil }
        return model.records.first { $0.id == model.selectedDatasetID }
    }

    private var project: OrthomosaicProject? {
        if let mission {
            return processing.project(mission.id)
                ?? processing.projects.first { $0.datasetID == (mission.remoteID ?? mission.id) }
        }
        if let record {
            return processing.projects.first { $0.datasetID == record.id || $0.id == record.id }
        }
        return importedProjectID.flatMap { processing.project($0) }
    }

    private var output: OrthomosaicOutput? { project?.outputs.last }
    private var title: String { mission?.plan.name ?? record?.plan.name ?? project?.name ?? "Pilih misi" }
    private var canPrepare: Bool {
        guard processing.storageError == nil else { return false }
        if project != nil { return true }
        guard let record else { return false }
        return !processing.busy && !link.receiving && !link.sending
            && model.hasLocalDataset(record.id)
            && !(model.isActiveMission && model.telemetry.missionID == record.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .mission || model.hasMissionDetail {
                // One compact bar keeps the most vertical space for the map.
                HStack(spacing: 16) {
                    contextHeader
                    Spacer(minLength: 8)
                    if mission != nil || record != nil || model.step == .datasets { tabs }
                    Spacer(minLength: 8)
                    if inMissionDetail { missionStatus }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider()
            }
            Group {
                if model.step == .mission && !model.hasMissionDetail {
                    missionList
                } else {
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.step == .mission && model.hasMissionDetail && mission?.phase != .completed
                && tab == .camera
            {
                MissionFooterView(model: model, link: link, continueTitle: continueTitle) {
                    tab = nextTab
                }
            }
        }
        .background(KropsStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(KropsStyle.border))
        .padding(.horizontal, 14).padding(.bottom, 14)
        .padding(.top, inMissionDetail ? 14 : 0)  // The page header is hidden inside a mission.
        .onAppear {
            tab = initialTab ?? landingTab
            resolveImportedProject()
        }
        .onChange(of: model.step) { _, step in
            if step == .datasets { tab = .imagery } else if step == .mission { tab = landingTab }
        }
        .onChange(of: model.selectedMissionID) { _, _ in
            tab = landingTab
            mapFocus = UUID()
        }
        .onChange(of: model.missionDetailVisible) { _, visible in
            if visible { tab = landingTab }
        }
        .onChange(of: model.telemetry.phase) { _, phase in
            guard model.hasMissionDetail, model.step == .mission, model.selectedMissionIsCurrent else {
                return
            }
            if [.capturing, .countdown, .paused].contains(phase) { tab = .capture }
            if phase == .completed { tab = .imagery }
        }
        .onChange(of: processing.selectedID) { _, _ in resolveImportedProject() }
        .onChange(of: planner.activeRecoveryMissionID) { _, recoveryID in
            guard let recoveryID else { return }
            if model.selectedMissionID != recoveryID || !model.missionDetailVisible {
                model.openMission(recoveryID)
            }
            if isDroneActiveInAir {
                tab = .capture
            }
        }
        .onChange(of: link.receivedMissionID) { _, id in
            guard let id, record?.id == id else { return }
            model.refreshLocalDatasets()
            guard let transferred = model.records.first(where: { $0.id == id }),
                !processing.busy, processing.storageError == nil
            else { return }
            processing.prepareMission(transferred, projectID: mission?.id ?? id, openEditor: false)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .overview:
            if let mission { overview(mission) } else { missionList }
        case .mission:
            if mission != nil && model.hasMissionDetail && model.step == .mission {
                MissionWorkspaceView(
                    model: model, link: link, farms: farms, location: location,
                    planner: planner,
                    onStartFlight: {
                        tab = .capture
                    }
                )
                .id(model.selectedMissionID)
            } else {
                missionList
            }
        case .camera:
            if model.hasMissionDetail && model.step == .mission {
                ScrollView {
                    DevicesView(model: model, link: link, missionContext: true).padding(20)
                }
            } else {
                missionList
            }
        case .capture:
            FlightWorkspaceView(
                model: model,
                link: link,
                planner: planner,
                mission: mission,
                activeTab: $tab
            )
        case .imagery:
            imagery
        case .results:
            results
        }
    }

    private var isDroneActiveInAir: Bool {
        guard let drone = engineManager.activeVehicle else { return false }
        return drone.armed || drone.flying
    }

    private var isFlightUnlocked: Bool {
        planner.draft.isPlanLocked
            || (planner.isSOPChecklistComplete && (model.geometry.reviewed || planner.reviewed))
            || isDroneActiveInAir
    }

    private var landingTab: ReviewTab {
        if model.step == .datasets || mission?.phase == .completed { return .imagery }
        if isDroneActiveInAir || (model.selectedMissionIsCurrent && model.isActiveMission) { return .capture }
        if planner.draft.isPlanLocked { return .capture }
        return model.geometry.reviewed ? .camera : .mission
    }

    private var nextTab: ReviewTab {
        if !model.geometry.reviewed { return .mission }
        return model.iphoneReadyForCapture ? .capture : .camera
    }

    private var continueTitle: String {
        switch nextTab {
        case .mission: return "Periksa rencana"
        case .capture: return "Lanjut ke penerbangan"
        default: return "Lanjut ke kamera & uji"
        }
    }

    private var tabs: some View {
        Picker("Tahap misi", selection: Binding(get: { tab }, set: { selectTab($0) })) {
            ForEach(ReviewTab.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.extraLarge)
        .fixedSize()
    }

    private func selectTab(_ item: ReviewTab) {
        if mission == nil && [.mission, .camera, .capture].contains(item) { return }
        // Return to the existing mission context before showing its editor.
        if [.mission, .camera, .capture].contains(item), model.step == .datasets, let mission {
            model.openMission(mission.id)
        }
        guard ![.camera, .capture].contains(item) || model.hasMissionDetail else { return }
        tab = item
    }

    private var contextHeader: some View {
        HStack(spacing: 10) {
            Button {
                model.showMissionList()
                tab = .overview
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .kropsToolbarAction()
            .buttonBorderShape(.circle)
            .help("Kembali ke semua misi").accessibilityLabel("Semua misi")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
                if let mission {
                    HStack(spacing: 6) {
                        Label(farmName(mission), systemImage: "leaf.fill")
                            .fontWeight(.semibold)
                            .foregroundStyle(mission.area == nil ? Color.orange : KropsStyle.accent)
                        Text("·").foregroundStyle(.tertiary)
                        Text(
                            model.missionStorageError == nil
                                ? mission.phase.dashboardTitle : "Perubahan belum tersimpan"
                        )
                        .foregroundStyle(.secondary)
                    }
                    .font(.callout).lineLimit(1)
                }
            }
            .help(mission.map { "ID misi · " + $0.id.uuidString } ?? "")
            .contextMenu {
                if let mission {
                    Button("Salin ID misi") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mission.id.uuidString, forType: .string)
                    }
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func farmName(_ mission: SavedMission) -> String {
        guard let area = mission.area else { return "Kebun belum diatur" }
        let name = area.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Kebun tanpa nama" : name
    }

    private var inMissionDetail: Bool { model.step == .mission && model.hasMissionDetail }

    private var canSaveRoute: Bool {
        planner.draft.waypoints.count >= 3 && !planner.draft.isPlanLocked
    }

    /// Engine and iPhone state as quiet indicators; details live in their tooltips.
    private var missionStatus: some View {
        HStack(spacing: 10) {
            QGCEngineStatusBadge(compact: true)
            Button {
                tab = .camera
            } label: {
                Image(systemName: model.iphoneReadyForCapture ? "iphone.gen3" : "iphone.gen3.slash")
                    .foregroundStyle(model.iphoneReadyForCapture ? Color.green : Color.orange)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(model.iphoneCaptureStatus + " · buka Kamera & uji")
            .accessibilityLabel(model.iphoneCaptureStatus)
            Button(
                showSavedConfirmation ? "Tersimpan" : "Simpan Rute",
                systemImage: showSavedConfirmation ? "checkmark.circle.fill" : "square.and.arrow.down"
            ) {
                planner.saveRouteCheckpoint()
                model.saveCurrentMissionPlan()
                showSavedConfirmation = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    showSavedConfirmation = false
                }
            }
            .kropsToolbarAction(size: .large)
            .disabled(!canSaveRoute || model.editingLocked)
            .help(
                planner.draft.isPlanLocked
                    ? "Rute sudah disimpan dan dikunci"
                    : (canSaveRoute
                        ? "Simpan konfigurasi rute, parameter terbang, dan checklist misi ini"
                        : "Tentukan batas area kebun (minimal 3 titik) untuk menyimpan rute")
            )
        }
    }

    private var missionList: some View {
        ScrollView {
            MissionListView(model: model, planner: planner, processing: processing, search: search)
                .padding(24)
        }
    }

    private func overview(_ mission: SavedMission) -> some View {
        HStack(spacing: 0) {
            MissionAreaMap(
                points: mission.area?.points ?? [], drawing: false, focus: mapFocus,
                location: location.sample, addPoint: { _ in }, movePoint: { _, _ in }
            )
            .overlay(alignment: .topLeading) {
                if mission.area == nil {
                    Label("Batas area belum ditentukan", systemImage: "map")
                        .font(.callout).padding(12)
                        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mission.plan.name).font(.system(size: 28, weight: .semibold))
                        Text(activeReviewRequest?.garden.locationName ?? mission.area?.name ?? "Lokasi kebun belum diatur")
                            .font(.title3).foregroundStyle(.secondary)
                    }

                    if let request = activeReviewRequest {
                        CloudKitFarmerOverviewCard(request: request)
                    } else {
                        detail("Status misi", value: mission.phase.dashboardTitle)
                        detail(
                            "Area pemetaan",
                            value: mission.area.map { "\($0.points.count) titik batas" } ?? "—"
                        )
                        detail("Foto tersimpan", value: "\(mission.saved) foto")
                        detail("Dibuat", value: mission.createdAt.formatted(date: .long, time: .omitted))
                    }

                    Button("Buka perencanaan misi", systemImage: "arrow.right") {
                        if model.step != .mission { model.openMission(mission.id) }
                        tab = .mission
                    }
                    .kropsPrimaryAction()
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).textSelection(.enabled)
        }
    }

    private var imagery: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !link.connected {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hubungkan iPhone").font(.headline)
                            Text(link.status).font(.caption).foregroundStyle(.secondary)
                            Text("Buka DroneCam dan izinkan Jaringan Lokal pada kedua perangkat.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(link.peers, id: \.self) { peer in
                                Button("Hubungkan \(peer.displayName)") { link.connect(peer) }
                            }
                            Button("Cari iPhone lagi") { link.refreshDiscovery() }
                            if model.isDemo {
                                Button("Hubungkan demo") { model.connectDemo() }
                            }
                        }
                    } else {
                        Label("iPhone terhubung", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Perbarui daftar foto") { model.send(.list) }
                            .disabled(model.pending != nil || link.receiving || link.sending)
                    }
                    if let record {
                        Button(
                            model.hasLocalDataset(record.id)
                                ? "Transfer ulang foto" : "Transfer foto dari iPhone"
                        ) {
                            model.send(.download, missionID: record.id)
                        }
                        .disabled(
                            !model.canTransferDatasets || processing.busy
                                || model.missionLibrary.hiddenRemoteIDs.contains(record.id)
                                || record.saved == 0 || !model.records.contains(where: { $0.id == record.id })
                        )
                        Text(link.receiving ? "Transfer berlangsung…" : link.transferStatus)
                            .font(.caption).foregroundStyle(.secondary)
                        if let pending = model.pending {
                            Text("Menunggu konfirmasi: " + pending.action.userTitle)
                                .font(.caption).foregroundStyle(.orange)
                            Button("Periksa status operasi") { model.requestPendingStatus() }
                            if model.pendingSince.map({ Date().timeIntervalSince($0) > 15 }) == true {
                                Button("Tutup operasi tertunda") { model.dismissPending() }
                            }
                        }
                        if record.saved == 0 {
                            Text(
                                "Belum ada foto capture untuk ditransfer. Kamu juga dapat mengimpor foto dari Finder."
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        } else if !link.connected {
                            Text("Hubungkan iPhone untuk mentransfer foto misi ini.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.hasLocalDataset(record.id) {
                            if project != nil {
                                Button("Muat ulang foto transfer") {
                                    processing.prepareMission(
                                        record, projectID: mission?.id ?? record.id, refresh: true)
                                }
                                .disabled(
                                    processing.busy || link.receiving || link.sending || model.isActiveMission
                                )
                            }
                            Button("Buka folder foto") { model.openDatasetFolder(missionID: record.id) }
                            Button("Siapkan WebODM…") { export(record) }
                                .disabled(link.receiving || link.sending || record.saved == 0)
                        }
                    }
                    Divider()
                    Button {
                        importPhotos()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 30, weight: .light))
                            Text("Impor foto dari Finder").font(.headline)
                            Text("JPEG, HEIC, PNG, TIFF").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                        .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16).strokeBorder(
                                KropsStyle.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                    }
                    .buttonStyle(.plain)
                    .disabled(processing.busy || processing.storageError != nil)

                    if mission == nil && record == nil {
                        Picker("Proyek citra", selection: $importedProjectID) {
                            Text("Pilih proyek").tag(nil as UUID?)
                            ForEach(processing.projects) { item in
                                Text(item.name).tag(Optional(item.id))
                            }
                        }
                    }
                    detail("Foto pemetaan", value: "\(project?.mappingPhotos.count ?? 0) foto")
                    detail("Koordinat foto", value: "\(locatedPhotos.count) foto dengan GPS")
                    detail("Pengolahan", value: project?.state.title ?? "Belum disiapkan")
                    if let project {
                        Text(project.message).font(.caption).foregroundStyle(.secondary)
                        if project.state.isRunning { ProgressView(value: project.fraction) }
                    }
                    if let error = processing.storageError ?? processing.error {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    Button("Pengaturan orthomosaic", action: prepareOrthomosaic)
                        .disabled(!canPrepare)
                    Divider()
                    Text("Foto").font(.headline)
                    ForEach(project?.mappingPhotos ?? []) { photo in
                        Label(photo.url.lastPathComponent, systemImage: "photo")
                            .font(.caption).lineLimit(1)
                    }
                }
                .padding(24)
            }
            .frame(width: 290)
            Divider()
            ReviewPhotoMap(photos: locatedPhotos)
                .overlay(alignment: .topTrailing) {
                    Button("Olah foto", systemImage: "play.fill", action: prepareOrthomosaic)
                        .kropsPrimaryAction(size: .large)
                        .disabled(!canPrepare)
                        .help("Buka persiapan dan jalankan orthomosaic")
                        .padding(20)
                }
        }
    }

    private var locatedPhotos: [OrthomosaicPhoto] {
        (project?.mappingPhotos ?? []).filter { photo in
            guard let location = photo.location else { return false }
            return CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
        }
    }

    private func isResultLayerReady(_ layer: ReviewResultLayer) -> Bool {
        switch layer {
        case .orthomosaic: return resolvedOrthomosaicJPEGURL != nil
        case .variAndHara: return variResult != nil
        case .fertilizationTiming: return isTimingReadyForDispatch
        }
    }

    private var results: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ReviewResultLayer.allCases) { layer in
                    Button {
                        resultLayer = layer
                    } label: {
                        HStack(spacing: 8) {
                            Text(layer.rawValue).font(
                                .body.weight(resultLayer == layer ? .semibold : .regular))
                            Spacer()
                            if isResultLayerReady(layer) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            if resultLayer == layer { Image(systemName: "chevron.right").font(.caption) }
                        }
                        .padding(14)
                        .foregroundStyle(resultLayer == layer ? KropsStyle.accent : Color.secondary)
                        .background(
                            resultLayer == layer ? KropsStyle.accent.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(resultLayer == layer ? .isSelected : [])
                }

                Spacer()

                Divider()

                CloudKitDispatchSidebarPanel(
                    request: activeReviewRequest,
                    isOrthomosaicJPEGReady: resolvedOrthomosaicJPEGURL != nil,
                    isVariReady: variResult != nil,
                    isTimingReady: isTimingReadyForDispatch,
                    canDispatch: canDispatchCompletedReview,
                    isDispatching: model.isDispatchingReview,
                    dispatchSuccessAt: dispatchSuccessAt,
                    onDispatch: {
                        Task { await dispatchCompletedReview() }
                    }
                )
            }
            .padding(18).frame(width: 245)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(resultLayer.rawValue).font(.headline)
                    Spacer()
                    if resultLayer == .orthomosaic, let output {
                        Button("Simpan TIFF") {
                            OrthomosaicFilePanels.save(output: output, model: processing)
                        }.disabled(processing.busy)
                    } else if resultLayer == .variAndHara, let result = variResult {
                        Button {
                            VariFilePanels.saveJSON(
                                from: result.resultJSONURL,
                                suggestedName: "vari_hara_hasil.json"
                            )
                        } label: {
                            Label("Unduh JSON", systemImage: "arrow.down.doc")
                        }
                    } else if resultLayer == .fertilizationTiming, let result = timingResult {
                        Button {
                            runTimingAnalysis()
                        } label: {
                            Label("Jalankan Ulang", systemImage: "arrow.clockwise")
                        }
                        .kropsToolbarAction(size: .regular)
                        .disabled(isProcessingTiming)

                        Menu {
                            Button("Simpan Output JSON…") {
                                VariFilePanels.saveJSON(
                                    from: result.resultJSONURL,
                                    suggestedName: "jadwal_pemupukan_hasil.json"
                                )
                            }
                            Button("Simpan Input Request JSON…") {
                                VariFilePanels.saveJSON(
                                    from: result.requestJSONURL,
                                    suggestedName: "jadwal_pemupukan_request.json"
                                )
                            }
                            Divider()
                            Button("Tampilkan di Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([result.resultJSONURL])
                            }
                        } label: {
                            Label("Unduh", systemImage: "arrow.down.doc")
                        }
                        .kropsToolbarAction(size: .regular)
                    }
                }
                .padding(20)
                Divider()
                if resultLayer == .orthomosaic, let output {
                    ReviewOutputPreview(url: output.folder.appendingPathComponent("preview.png"))
                        .id(output.folder)
                    HStack {
                        Text(
                            "\(output.width) × \(output.height) px · \(output.registered)/\(output.total) foto"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(
                            resolvedOrthomosaicJPEGURL != nil
                                ? "Aset CloudKit: orthomosaic.jpeg siap"
                                : "Aset CloudKit: orthomosaic.jpeg dibuat saat VARI dijalankan"
                        )
                        .font(.caption)
                        .foregroundStyle(resolvedOrthomosaicJPEGURL != nil ? .green : .orange)
                        Spacer()
                        Button("Buka hasil") { processing.showOutput(output) }
                    }.padding(16)
                } else if resultLayer == .variAndHara {
                    variView
                } else if resultLayer == .fertilizationTiming {
                    timingView
                } else {
                    ContentUnavailableView(
                        "Belum ada orthomosaic",
                        systemImage: "square.3.layers.3d",
                        description: Text("Impor dan olah foto melalui tab Citra.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: output?.folder) {
            variResult = nil
            variError = nil
            selectedTimingNPK = nil
            checkForCachedVariResult()
        }
        .task(id: timingStorageKey) {
            timingTask?.cancel()
            timingTask = nil
            isProcessingTiming = false
            timingError = nil
            timingResult = nil
            timingFertilizerIDLookup = [:]
            dispatchSuccessAt = nil
            checkForCachedTimingResult()
        }
        .onChange(of: resultLayer) { _, newLayer in
            if newLayer == .variAndHara {
                checkForCachedVariResult()
            } else if newLayer == .fertilizationTiming {
                checkForCachedTimingResult()
            }
        }
        .onDisappear {
            timingTask?.cancel()
            timingTask = nil
        }
    }

    @ViewBuilder
    private var variView: some View {
        if !isOrthomosaicReady {
            ContentUnavailableView {
                Label("Orthomosaic Belum Tersedia", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } description: {
                Text(
                    "Indeks VARI & HARA memerlukan hasil olah citra orthomosaic gabungan. Silakan selesaikan pengolahan foto pemetaan pada tab Orthomosaic terlebih dahulu."
                )
            } actions: {
                Button("Menuju Tab Orthomosaic") {
                    resultLayer = .orthomosaic
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isProcessingVari {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Menjalankan Analisis VARI & HARA...").font(.headline)
                Text(
                    "Mendeteksi tajuk pohon kelapa sawit, menghitung indeks vegetasi VARI, serta rekomendasi pupuk hara."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = variResult {
            VariReportWorkspaceView(
                result: result,
                initialSection: .vari,
                selectedNPKForTiming: selectedTimingNPK,
                onSelectNPKForTiming: { chosenNPK in
                    selectedTimingNPK = chosenNPK
                },
                onRerun: output.map { out in { runVariScan(on: out.image, outputFolder: out.folder) } }
            )
        } else {
            ContentUnavailableView {
                Label("Analisis VARI & HARA", systemImage: "leaf.fill")
            } description: {
                if let variError {
                    Text("Error: \(variError)").foregroundStyle(.red)
                } else if activeReviewRequest == nil {
                    Text("Menunggu sinkronisasi data permintaan kebun dari CloudKit agar profil agronomi dan anggaran petani tersedia.")
                        .foregroundStyle(.orange)
                } else if let output {
                    Text(
                        "Orthomosaic siap diolah (\(output.width) × \(output.height) px). Mulai proses deteksi tajuk pohon sawit, indeks vegetasi VARI, dan kalkulasi rekomendasi pupuk hara."
                    )
                } else {
                    Text("Belum ada citra orthomosaic yang tersedia untuk dianalisis.")
                }
            } actions: {
                if let output {
                    Button("Jalankan Analisis VARI & HARA") {
                        runVariScan(on: output.image, outputFolder: output.folder)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(activeReviewRequest == nil || isProcessingVari)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var timingView: some View {
        VariTimingWorkspaceView(
            result: timingResult,
            isRunning: isProcessingTiming,
            errorMessage: timingError,
            context: timingContextSummary,
            onRun: runTimingAnalysis,
            onDismissError: { timingError = nil }
        )
    }

    private func dispatchCompletedReview() async {
        guard let output, let variResult, let timingResult else { return }
        let succeeded = await model.dispatchCompletedReview(
            for: mission,
            fallbackID: record?.id ?? activeReviewRequest?.id,
            output: output,
            variResult: variResult,
            timingResult: timingResult,
            fertilizerIDLookup: timingFertilizerIDLookup,
            preferredNPK: selectedTimingNPK
        )
        if succeeded {
            dispatchSuccessAt = Date()
        }
    }

    private func runTimingAnalysis() {
        guard !isProcessingTiming else { return }
        guard let request = activeReviewRequest else {
            timingError = "Data permintaan kebun dari CloudKit belum ditemukan untuk misi ini."
            return
        }
        guard let variResult else {
            timingError =
                "Analisis VARI & HARA harus selesai terlebih dahulu agar dosis pupuk komersial tersedia."
            return
        }

        isProcessingTiming = true
        timingError = nil
        let targetFolder = timingOutputFolder
        let chosenNPK = selectedTimingNPK
        let options = VariTimingWeatherSettings.currentRunOptions()

        timingTask?.cancel()
        timingTask = Task {
            do {
                let buildOutput = try VariTimingBuilder.makeRequest(
                    from: request,
                    variResult: variResult,
                    preferredNPK: chosenNPK
                )
                let result = try await timingProcessor.runTiming(
                    request: buildOutput.request,
                    options: options,
                    outputFolder: targetFolder
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.timingFertilizerIDLookup = buildOutput.fertilizerIDLookup
                    self.selectedTimingNPK = buildOutput.selectedNPKType
                    self.timingResult = result
                    self.isProcessingTiming = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isProcessingTiming = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.timingError = error.localizedDescription
                    self.isProcessingTiming = false
                }
            }
        }
    }

    private func runVariScan(on imageURL: URL, outputFolder: URL) {
        guard !isProcessingVari else { return }
        guard let request = activeReviewRequest else {
            variError = "Data permintaan kebun dari CloudKit belum ditemukan untuk misi ini."
            return
        }
        isProcessingVari = true
        variError = nil
        Task {
            do {
                let submission = try VariSubmissionBuilder.makeSubmission(from: request)
                let result = try await variProcessor.process(
                    photoURL: imageURL,
                    submission: submission,
                    outputFolder: outputFolder
                )
                await MainActor.run {
                    self.variResult = result
                    self.isProcessingVari = false
                }
            } catch {
                await MainActor.run {
                    self.variError = error.localizedDescription
                    self.isProcessingVari = false
                }
            }
        }
    }

    private func resolveImportedProject() {
        guard mission == nil, record == nil else { return }
        if let selectedID = processing.selectedID {
            importedProjectID = selectedID
        } else if importedProjectID == nil {
            importedProjectID = processing.projects.first?.id
        }
    }

    private func prepareOrthomosaic() {
        guard canPrepare else { return }
        if let project {
            processing.open(project.id)
        } else if let record {
            processing.prepareMission(record, projectID: mission?.id ?? record.id)
        }
    }

    private func importPhotos() {
        OrthomosaicFilePanels.photos { urls in
            guard !urls.isEmpty else { return }
            if let record {
                processing.importPhotos(urls, mission: record, projectID: mission?.id ?? record.id)
            } else if let project {
                // The existing importer appends to its selected project.
                processing.open(project.id)
                processing.importPhotos(urls, append: true)
            } else {
                processing.importPhotos(urls)
            }
        }
    }
}

private struct ReviewWorkspacePreview: View {
    let tab: ReviewTab
    private let dependencies: ControlDependencies

    init(tab: ReviewTab) {
        self.tab = tab
        let dependencies = ControlDependencies(demo: true)
        if let mission = dependencies.viewModel.savedMissions().first {
            dependencies.viewModel.openMission(mission.id)
        }
        self.dependencies = dependencies
    }

    var body: some View {
        ReviewWorkspaceView(
            model: dependencies.viewModel, link: dependencies.link,
            farms: dependencies.farms, location: dependencies.location,
            planner: dependencies.planner,
            processing: ControlDependencies.orthomosaicViewModel(
                store: dependencies.link.store, demo: true),
            variProcessor: dependencies.variProcessor,
            timingProcessor: dependencies.timingProcessor,
            search: "", openPlanner: {}, createMission: {}, export: { _ in }, tab: tab
        )
        .frame(width: 1280, height: 720)
        .preferredColorScheme(.light)
    }
}

#Preview("Peninjauan · Overview") {
    ReviewWorkspacePreview(tab: .overview)
}

#Preview("Peninjauan · Misi") {
    ReviewWorkspacePreview(tab: .mission)
}

#Preview("Peninjauan · Citra") {
    ReviewWorkspacePreview(tab: .imagery)
}

#Preview("Peninjauan · Hasil") {
    ReviewWorkspacePreview(tab: .results)
}

private struct ReviewPhotoMap: View {
    let photos: [OrthomosaicPhoto]

    private var coordinates: [CLLocationCoordinate2D] {
        photos.compactMap { photo in
            photo.location.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    var body: some View {
        Map {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates).stroke(.green, lineWidth: 2)
            }
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if let location = photo.location {
                    Annotation(
                        "Foto \(index + 1)",
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.latitude, longitude: location.longitude)
                    ) {
                        Circle().fill(.white).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.green, lineWidth: 3))
                    }
                }
            }
        }
        .mapStyle(.imagery)
        .mapControls {
            MapCompass()
            MapZoomStepper()
            MapScaleView()
        }
        .overlay {
            if photos.isEmpty {
                ContentUnavailableView(
                    "Posisi pengambilan foto",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Foto dengan koordinat GPS akan muncul di peta ini.")
                )
                .padding(24)
                .background(KropsStyle.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
                .padding(40)
            }
        }
    }
}

private struct ReviewOutputPreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(24)
            } else {
                ContentUnavailableView("Pratinjau tidak tersedia", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KropsStyle.canvas)
        .task(id: url) { image = NSImage(contentsOf: url) }
    }
}

private struct CloudKitFarmerOverviewCard: View {
    let request: PlantationReviewRequest

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "id_ID")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if request.hasFieldErrors {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Peringatan Sinkronisasi Field CloudKit", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(request.fieldErrors.sorted(by: { $0.key < $1.key }), id: \.key) { key, message in
                        Text("• \(key): \(message)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3)))
            }

            sectionCard(title: "Status & Jadwal Peninjauan") {
                row("Status CloudKit", request.status.title)
                row("Dikirim petani", request.timeline.submittedAt.formatted(date: .abbreviated, time: .shortened))
                if let visit = request.timeline.plannedOperatorVisitDate {
                    row("Rencana kunjungan", visit.formatted(date: .abbreviated, time: .shortened))
                }
                if let sent = request.timeline.resultSentAt {
                    row("Hasil terkirim", sent.formatted(date: .abbreviated, time: .shortened))
                }
                if !request.progressionEvents.isEmpty {
                    Divider()
                    Text("Riwayat Progres (\(request.progressionEvents.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(request.progressionEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.title) · \(event.dateTime.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.weight(.medium))
                            Text(event.desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            sectionCard(title: "Identitas Petani & Lokasi Kebun") {
                row("Nama petani", request.farmer.name)
                row("Telepon", request.farmer.phone)
                row("Alamat petani", request.farmer.address)
                Divider()
                row("Nama kebun", request.garden.name)
                row("Alamat kebun", request.garden.locationName)
                row("Luas kebun", String(format: "%.2f ha", request.garden.areaHectares))
                row("Keliling batas", String(format: "%.0f m", request.garden.circumferenceMeters))
                row("Titik poligon", "\(request.boundary.count) koordinat")
            }

            sectionCard(title: "Profil Agronomi & Anggaran") {
                row(
                    "Bulan / tahun tanam",
                    request.agronomy.plantingMonth.map { "\($0)/\(request.agronomy.plantingYear)" }
                        ?? "\(request.agronomy.plantingYear)"
                )
                row("Jenis tanah", soilDisplayTitle(request.agronomy.soilType))
                row("Frekuensi pemupukan", "\(request.agronomy.fertilizingFrequencyPerYear)x / tahun")
                row("Anggaran / ha", formatRp(Double(request.agronomy.fertilizationBudgetPerHa)))
                row("Total anggaran kebun", formatRp(request.totalBudgetRp))
                if let harvest = request.agronomy.harvestRecord {
                    row(
                        "Panen terakhir",
                        String(format: "%dx/bulan · %.0f kg", harvest.frequencyPerMonth, harvest.latestWeightKg)
                    )
                }
            }

            sectionCard(title: "Riwayat Pupuk Petani (\(request.agronomy.fertilizerRecords.count))") {
                if request.agronomy.fertilizerRecords.isEmpty {
                    Text("Belum ada catatan pemupukan dari petani.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(request.agronomy.fertilizerRecords) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.contractType.rawValue)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.2f kg/pohon", item.doseKgPerTree))
                                    .font(.caption.monospacedDigit().weight(.medium))
                            }
                            if !item.composition.isEmpty {
                                let ratio = item.composition.map { "\($0.name): \(Int($0.value))%" }.joined(separator: " · ")
                                Text(ratio)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if item.id != request.agronomy.fertilizerRecords.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if let result = request.result {
                sectionCard(title: "Ringkasan Hasil Terkirim") {
                    row("Zona pemupukan", "\(result.zoneCount) zona")
                    row("Identifikasi pohon", "\(result.treeCount) pohon")
                    row("Kebutuhan pupuk", "\(result.fertilizerNeeds.count) baris")
                    row("Putaran jadwal", "\(result.scheduleRoundCount) putaran")
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 135, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func soilDisplayTitle(_ soil: ContractSoilType) -> String {
        switch soil {
        case .unknown(let raw): return raw.isEmpty ? "Tidak diketahui" : raw
        default: return soil.rawValue
        }
    }

    private func formatRp(_ amount: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "Rp \(Int(amount))"
    }
}

private struct CloudKitDispatchSidebarPanel: View {
    let request: PlantationReviewRequest?
    let isOrthomosaicJPEGReady: Bool
    let isVariReady: Bool
    let isTimingReady: Bool
    let canDispatch: Bool
    let isDispatching: Bool
    let dispatchSuccessAt: Date?
    let onDispatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pengiriman CloudKit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            checklistRow("Orthomosaic JPEG", ready: isOrthomosaicJPEGReady)
            checklistRow("VARI & HARA", ready: isVariReady)
            checklistRow("Jadwal Pemupukan", ready: isTimingReady)

            if let sent = dispatchSuccessAt ?? request?.timeline.resultSentAt {
                Label(
                    "Terkirim \(sent.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "checkmark.icloud.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
            } else if request == nil {
                Text("Permintaan CloudKit belum tersedia untuk misi ini.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Button(action: onDispatch) {
                Label(
                    isDispatching ? "Mengirim…" : "Kirim Semua Hasil",
                    systemImage: "paperplane.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .kropsPrimaryAction(size: .regular)
            .disabled(!canDispatch)
        }
        .padding(.top, 4)
    }

    private func checklistRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(ready ? .green : .secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(ready ? .primary : .secondary)
        }
    }
}
