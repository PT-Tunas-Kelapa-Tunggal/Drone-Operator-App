import AppKit
import MapKit
import MultipeerConnectivity
import SwiftUI

enum ReviewTab: String, CaseIterable, Identifiable {
    case overview = "Ringkasan"
    case mission = "1. Rencana"
    case camera = "2. Kamera & uji"
    case capture = "3. Capture"
    case imagery = "4. Foto"
    case results = "5. Hasil"
    var id: String { rawValue }
}

private enum ReviewResultLayer: String, CaseIterable, Identifiable {
    case orthomosaic = "Orthomosaic"
    case vari = "VARI"
    case nutrients = "HARA"
    case rainfall = "Curah Hujan"
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
    let search: String
    let openPlanner: () -> Void
    let createMission: () -> Void
    let export: (MissionRecord) -> Void
    private let initialTab: ReviewTab?
    @State private var tab: ReviewTab
    @State private var resultLayer = ReviewResultLayer.orthomosaic
    @State private var importedProjectID: UUID?
    @State private var mapFocus = UUID()

    init(
        model: ControlViewModel, link: LocalLink, farms: FarmAreaViewModel,
        location: OperatorLocationViewModel, planner: FlightPlannerViewModel,
        processing: OrthomosaicViewModel, search: String,
        openPlanner: @escaping () -> Void, createMission: @escaping () -> Void,
        export: @escaping (MissionRecord) -> Void, tab: ReviewTab? = nil
    ) {
        self.model = model
        self.link = link
        self.farms = farms
        self.location = location
        self.planner = planner
        self.processing = processing
        self.search = search
        self.openPlanner = openPlanner
        self.createMission = createMission
        self.export = export
        initialTab = tab
        _tab = State(initialValue: tab ?? .mission)
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
            if model.step == .mission && model.hasMissionDetail && mission?.phase != .completed && [.camera, .capture].contains(tab) {
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
            if step == .datasets { tab = .imagery }
            else if step == .mission { tab = landingTab }
        }
        .onChange(of: model.selectedMissionID) { _, _ in
            tab = landingTab
            mapFocus = UUID()
        }
        .onChange(of: model.missionDetailVisible) { _, visible in
            if visible { tab = landingTab }
        }
        .onChange(of: model.telemetry.phase) { _, phase in
            guard model.hasMissionDetail, model.step == .mission, model.selectedMissionIsCurrent else { return }
            if [.capturing, .countdown, .paused].contains(phase) { tab = .capture }
            if phase == .completed { tab = .imagery }
        }
        .onChange(of: processing.selectedID) { _, _ in resolveImportedProject() }
        .onChange(of: link.receivedMissionID) { _, id in
            guard let id, record?.id == id else { return }
            model.refreshLocalDatasets()
            guard let transferred = model.records.first(where: { $0.id == id }),
                !processing.busy, processing.storageError == nil else { return }
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
                    planner: planner)
                    .id(model.selectedMissionID)
            } else {
                missionList
            }
        case .camera:
            if model.hasMissionDetail && model.step == .mission {
                ScrollView {
                    DevicesView(model: model, link: link, missionContext: true).padding(20)
                }
            } else { missionList }
        case .capture:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Capture foto misi").font(.title2.bold())
                    Text("Tombol Mulai capture ada di kanan bawah. Penerbangan dijalankan melalui QGroundControl.")
                        .foregroundStyle(.secondary)
                    if model.selectedMissionIsCurrent && model.isActiveMission {
                        CaptureProgressView(model: model, link: link)
                    } else if let mission, [.completed, .failed].contains(mission.phase) {
                        Text(mission.phase == .completed
                             ? "Capture selesai. Lanjutkan ke Foto untuk transfer dan pemeriksaan."
                             : "Capture gagal. Periksa foto yang tersimpan atau buat percobaan baru.")
                        HStack(spacing: 12) {
                            Button("Buka foto") { tab = .imagery }
                            Button("Ulangi capture", systemImage: "arrow.clockwise") {
                                if model.repeatCapture(copyRoutes: { sourceID, destinationID in
                                    try planner.copyMissionRoutes(from: sourceID, to: destinationID)
                                }) {
                                    tab = .mission
                                }
                            }
                            .kropsPrimaryAction()
                            .disabled(!model.canRepeatCapture)
                        }
                        Text("Ulangi capture membuat misi baru dengan salinan area, rute, dan pengaturan. Foto sebelumnya tetap tersimpan. Periksa rencana, lalu siapkan kamera dan ambil foto uji lagi.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ControlPanel("Kesiapan capture", state: model.iphoneReadyForCapture ? "Siap" : nil) {
                            if model.iphoneReadyForCapture {
                                Label("Semua pemeriksaan terpenuhi", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                ForEach(model.readiness().blockers, id: \.self) { blocker in
                                    Label(blocker, systemImage: "circle").foregroundStyle(.secondary)
                                }
                                Button(continueTitle) { tab = nextTab }.kropsPrimaryAction()
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .imagery:
            imagery
        case .results:
            results
        }
    }

    private var landingTab: ReviewTab {
        if model.step == .datasets || mission?.phase == .completed { return .imagery }
        if model.selectedMissionIsCurrent && model.isActiveMission { return .capture }
        return model.geometry.reviewed ? .camera : .mission
    }

    private var nextTab: ReviewTab {
        if !model.geometry.reviewed { return .mission }
        return model.iphoneReadyForCapture ? .capture : .camera
    }

    private var continueTitle: String {
        switch nextTab {
        case .mission: return "Periksa rencana"
        case .capture: return "Lanjut ke capture"
        default: return "Lanjut ke kamera & uji"
        }
    }

    private var tabs: some View {
        Picker("Tahap misi", selection: Binding(get: { tab }, set: { selectTab($0) })) {
            ForEach(ReviewTab.allCases.filter { $0 != .overview }) { item in
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
                        Text(model.missionStorageError == nil ? mission.phase.dashboardTitle : "Perubahan belum tersimpan")
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

    /// Engine and iPhone state as quiet indicators; details live in their tooltips.
    private var missionStatus: some View {
        HStack(spacing: 10) {
            QGCEngineStatusBadge(compact: true)
            Button { tab = .camera } label: {
                Image(systemName: model.iphoneReadyForCapture ? "iphone.gen3" : "iphone.gen3.slash")
                    .foregroundStyle(model.iphoneReadyForCapture ? Color.green : Color.orange)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(model.iphoneCaptureStatus + " · buka Kamera & uji")
            .accessibilityLabel(model.iphoneCaptureStatus)
            Button("Ekspor rute", systemImage: "square.and.arrow.up", action: openPlanner)
                .kropsToolbarAction(size: .large)
                .disabled(model.editingLocked)
                .help("Ekspor rute .plan untuk QGroundControl")
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
                location: location.sample, addPoint: { _ in }, movePoint: { _, _ in })
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
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mission.plan.name).font(.system(size: 28, weight: .semibold))
                        Text(mission.area?.name ?? "Lokasi kebun belum diatur")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    detail("Status misi", value: mission.phase.dashboardTitle)
                    detail("Area pemetaan", value: mission.area.map { "\($0.points.count) titik batas" } ?? "—")
                    detail("Foto tersimpan", value: "\(mission.saved) foto")
                    detail("Dibuat", value: mission.createdAt.formatted(date: .long, time: .omitted))
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
                        Button(model.hasLocalDataset(record.id) ? "Transfer ulang foto" : "Transfer foto dari iPhone") {
                            model.send(.download, missionID: record.id)
                        }
                        .disabled(!model.canTransferDatasets || processing.busy
                            || model.missionLibrary.hiddenRemoteIDs.contains(record.id)
                            || record.saved == 0 || !model.records.contains(where: { $0.id == record.id }))
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
                            Text("Belum ada foto capture untuk ditransfer. Kamu juga dapat mengimpor foto dari Finder.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if !link.connected {
                            Text("Hubungkan iPhone untuk mentransfer foto misi ini.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.hasLocalDataset(record.id) {
                            if project != nil {
                                Button("Muat ulang foto transfer") {
                                    processing.prepareMission(record, projectID: mission?.id ?? record.id, refresh: true)
                                }
                                .disabled(processing.busy || link.receiving || link.sending || model.isActiveMission)
                            }
                            Button("Buka folder foto") { model.openDatasetFolder(missionID: record.id) }
                            Button("Siapkan WebODM…") { export(record) }
                                .disabled(link.receiving || link.sending || record.saved == 0)
                        }
                    }
                    Divider()
                    Button { importPhotos() } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 30, weight: .light))
                            Text("Impor foto dari Finder").font(.headline)
                            Text("JPEG, HEIC, PNG, TIFF").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                        .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
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

    private var results: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ReviewResultLayer.allCases) { layer in
                    Button { resultLayer = layer } label: {
                        HStack {
                            Text(layer.rawValue).font(.body.weight(resultLayer == layer ? .semibold : .regular))
                            Spacer()
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
            }
            .padding(18).frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(resultLayer.rawValue).font(.headline)
                    Spacer()
                    if resultLayer == .orthomosaic, let output {
                        Button {
                            Task {
                                await model.dispatchReviewResult(for: mission, output: output)
                            }
                        } label: {
                            Label(model.isDispatchingReview ? "Mengirim..." : "Kirim", systemImage: "paperplane")
                        }
                        .disabled(model.isDispatchingReview || processing.busy)

                        Button("Simpan TIFF") {
                            OrthomosaicFilePanels.save(output: output, model: processing)
                        }.disabled(processing.busy)
                    } else {
                        Button {} label: { Label("Kirim", systemImage: "paperplane") }.disabled(true)
                    }
                }
                .padding(20)
                Divider()
                if resultLayer == .orthomosaic, let output {
                    ReviewOutputPreview(url: output.folder.appendingPathComponent("preview.png"))
                        .id(output.folder)
                    HStack {
                        Text("\(output.width) × \(output.height) px · \(output.registered)/\(output.total) foto")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Buka hasil") { processing.showOutput(output) }
                    }.padding(16)
                } else {
                    ContentUnavailableView(
                        resultLayer == .orthomosaic ? "Belum ada orthomosaic" : "Belum ada data " + resultLayer.rawValue,
                        systemImage: resultLayer == .orthomosaic ? "square.3.layers.3d" : "chart.xyaxis.line",
                        description: Text(resultLayer == .orthomosaic
                            ? "Impor dan olah foto melalui tab Citra."
                            : "Hasil analisis akan ditampilkan di sini."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resolveImportedProject() {
        guard mission == nil, record == nil else { return }
        if let selectedID = processing.selectedID { importedProjectID = selectedID }
        else if importedProjectID == nil { importedProjectID = processing.projects.first?.id }
    }

    private func prepareOrthomosaic() {
        guard canPrepare else { return }
        if let project { processing.open(project.id) }
        else if let record { processing.prepareMission(record, projectID: mission?.id ?? record.id) }
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
            search: "", openPlanner: {}, createMission: {}, export: { _ in }, tab: tab)
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
        .mapControls { MapCompass(); MapZoomStepper(); MapScaleView() }
        .overlay {
            if photos.isEmpty {
                ContentUnavailableView(
                    "Posisi pengambilan foto",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Foto dengan koordinat GPS akan muncul di peta ini."))
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
