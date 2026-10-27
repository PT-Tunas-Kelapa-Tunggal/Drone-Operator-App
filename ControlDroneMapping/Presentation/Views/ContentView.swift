import AppKit
import MultipeerConnectivity
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject private var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    @StateObject private var orthomosaic: OrthomosaicViewModel
    @State private var showingPlanner = false
    @State private var plannerMissionID: UUID?
    @State private var plannerFarm: FarmArea?
    @State private var search = ""
    @State private var exportMission: MissionRecord?
    @State private var newMission = false
    @State private var missionName = ""
    @State private var deviceDetails = false

    init(
        model: ControlViewModel, link: LocalLink, farms: FarmAreaViewModel,
        location: OperatorLocationViewModel, planner: FlightPlannerViewModel
    ) {
        self.model = model
        self.link = link
        self.farms = farms
        self.location = location
        self.planner = planner
        _orthomosaic = StateObject(
            wrappedValue: ControlDependencies.orthomosaicViewModel(store: link.store, demo: model.isDemo))
    }
    private func openPlanner(farm: FarmArea? = nil) {
        let mission = model.hasMissionDetail ? model.selectedMission : nil
        plannerMissionID = mission?.id
        plannerFarm = mission?.area ?? farm
        if mission == nil || planner.draft.missionID != mission?.id {
            planner.open(
                farm: plannerFarm, name: mission.map { "Rute " + $0.plan.name } ?? "Rute baru",
                altitude: model.geometry.heightAGL, speed: model.geometry.speed, missionID: mission?.id)
        }
        showingPlanner = true
    }
    private var showingResults: Bool { model.step == .datasets }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    header
                    if selectedSection == .settings {
                        sectionNavigation
                    }
                    if let error = model.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                            Spacer()
                            if model.missionStorageError != nil {
                                Button("Coba simpan lagi") { model.retryMissionSaving() }
                            }
                            Button("Tutup") { model.errorMessage = nil }
                        }
                        .font(.callout).foregroundStyle(.orange).padding(12).background(
                            Color.orange.opacity(0.1))
                    }
                    if selectedSection == .review {
                        ReviewWorkspaceView(
                            model: model, link: link, farms: farms, location: location,
                            planner: planner, processing: orthomosaic, search: search,
                            openPlanner: { openPlanner(farm: model.selectedMission?.area) },
                            createMission: {
                                missionName = ""
                                newMission = true
                            },
                            export: { exportMission = $0 })
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                switch model.step {
                                case .dashboard:
                                    DashboardView(
                                        model: model, link: link, farms: farms, location: location,
                                        search: search, openPlanner: { openPlanner(farm: $0) }
                                    ) {
                                        name in
                                        missionName = name
                                        newMission = true
                                    }
                                case .requests:
                                    requestsPage
                                case .devices:
                                    DevicesView(model: model, link: link)
                                case .settings:
                                    AppSettingsView(model: model)
                                case .datasets:
                                    DatasetListView(
                                        model: model, link: link, processing: orthomosaic, search: search,
                                        resetSearch: { search = "" }
                                    ) {
                                        exportMission = $0
                                    }
                                case .mission:
                                    MissionListView(model: model, planner: planner, processing: orthomosaic, search: search)
                                }
                            }.padding(22).frame(maxWidth: 1540).frame(maxWidth: .infinity)
                        }
                    }
                    if showingResults {
                        MissionFooterView(model: model, link: link)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(KropsStyle.canvas)
                .frame(minWidth: 1240, minHeight: 760)
                .overlay {
                    MissionCountdownOverlay(
                        remaining: link.connected && model.freshness(now: context.date)
                            ? model.telemetry.countdownRemaining : nil)
                }
        }
        .sheet(item: $exportMission) { record in
            WebODMExportView(model: ControlDependencies.exportViewModel(record: record, store: link.store))
        }
        .sheet(isPresented: $orthomosaic.showingEditor) {
            OrthomosaicView(model: orthomosaic)
        }
        .sheet(isPresented: $showingPlanner) {
            FlightPlannerView(
                model: planner, farms: farms, location: location, missionID: plannerMissionID,
                missionFarm: plannerFarm)
        }
        .sheet(isPresented: $newMission) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Misi baru").font(KropsTypography.pageTitle)
                createForm
                Button("Batal") { newMission = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 420)
        }
        .task(id: cleanupDeferred) {
            // Startup engine checks share the busy state with imports. Wait quietly,
            // then retry once the app becomes idle instead of presenting a false error.
            guard !model.isDemo, !cleanupDeferred else { return }
            model.cleanDeletedMissionFiles(
                legacyIDs: orthomosaic.legacyDeletedFileIDs(
                    liveIDs: model.liveMissionFileIDs,
                    hiddenIDs: model.missionLibrary.hiddenRemoteIDs)
            ) { ids in
                try orthomosaic.removeMissionFiles(ids)
                planner.removeMissionRoutes(ids)
            }
        }
        .onChange(of: link.receivedMissionID) { _, id in
            if id != nil { model.refreshLocalDatasets() }
        }
        .onChange(of: model.step) { _, _ in search = "" }
        .onChange(of: model.selectedDatasetID) { _, _ in search = "" }
    }
    private var cleanupDeferred: Bool {
        orthomosaic.busy || orthomosaic.workingID != nil || orthomosaic.engineInstalling
            || model.editingLocked
    }

    private var selectedSection: ControlPanelSection {
        ControlPanelSection(screen: model.step)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Image("logokrops")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityLabel("Krops")
                .padding(.top, 24)
                .padding(.bottom, 48)

            VStack(spacing: 28) {
                navigation(.home)
                navigation(.review)
                navigation(.notifications)
            }

            Spacer(minLength: 40)
            navigation(.settings)
                .padding(.bottom, 24)
        }
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background(KropsStyle.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(KropsStyle.border).frame(width: 1)
        }
    }

    private func navigation(_ section: ControlPanelSection) -> some View {
        SidebarIconButton(section: section, isSelected: selectedSection == section) {
            guard selectedSection != section else { return }
            model.navigate(section.defaultScreen)
        }
    }

    private var sectionNavigation: some View {
        HStack(spacing: 8) {
            ForEach(selectedSection.screens) { screen in
                Button {
                    guard model.step != screen else { return }
                    model.navigate(screen)
                } label: {
                    Text(screen.title)
                        .font(.body.weight(model.step == screen ? .semibold : .regular))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .foregroundStyle(model.step == screen ? KropsStyle.accent : Color.secondary)
                        .background(
                            model.step == screen ? KropsStyle.accent.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.step == screen ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.step.title).font(KropsTypography.pageTitle)
                Text(
                    Date().formatted(
                        .dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "id_ID"))
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isDemo { Text("DEMO").font(.caption.bold()).foregroundStyle(.orange) }
            QGCEngineStatusBadge()
            if model.step == .dashboard || model.step == .datasets
                || (model.step == .mission && !model.hasMissionDetail)
            {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cari misi atau ID", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7).frame(width: 200).background(
                    KropsStyle.surface, in: RoundedRectangle(cornerRadius: 9)
                ).overlay(RoundedRectangle(cornerRadius: 9).stroke(KropsStyle.border))
            } else if model.step == .mission {
                Label(
                    model.iphoneCaptureStatus,
                    systemImage: model.iphoneReadyForCapture ? "checkmark.circle.fill" : "iphone"
                )
                .foregroundStyle(model.iphoneReadyForCapture ? Color.green : Color.orange)
            } else {
                Button {
                    deviceDetails.toggle()
                } label: {
                    Label(
                        link.connected
                            ? model.freshness() ? "iPhone terhubung" : "Sinkronisasi…" : "iPhone terputus",
                        systemImage: link.connected ? "wifi" : "wifi.slash"
                    )
                    .foregroundStyle(link.connected && model.freshness() ? Color.green : Color.orange)
                }.buttonStyle(.plain).popover(isPresented: $deviceDetails) {
                    DeviceStatusPopover(model: model, link: link)
                }
            }
            if model.step == .mission && model.hasMissionDetail {
                Button {
                    openPlanner(farm: model.selectedMission?.area)
                } label: {
                    Label("Ekspor rute", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }.kropsToolbarAction().disabled(model.editingLocked)
            }
            Button {
                missionName = ""
                newMission = true
            } label: {
                Label("Misi baru", systemImage: "plus")
            }.kropsToolbarAction().disabled(true)
        }.padding(.horizontal, 22).padding(.vertical, 14)
    }
    private var requestsPage: some View {
        ControlPanel("Permintaan petani", state: nil) {
            VStack(spacing: 16) {
                Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Permintaan petani belum tersedia").font(.title3.bold())
                Text("Sementara itu, buat misi langsung untuk area yang akan dipetakan.").foregroundStyle(
                    .secondary)
                Button("Buat misi manual") {
                    missionName = ""
                    newMission = true
                }.kropsPrimaryAction().disabled(true)
            }.frame(maxWidth: .infinity).padding(.vertical, 70)
        }
    }
    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mulai dengan nama dan rencana area. Lanjutkan ke Kamera & uji, Capture, lalu Foto dan Hasil dalam misi yang sama. Misi tersimpan otomatis di Mac.")
                .font(
                    .caption
                ).foregroundStyle(.secondary)
            TextField("Nama misi", text: $missionName).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Buat misi") {
                    model.createMission(name: missionName)
                    if model.errorMessage == nil { newMission = false }
                }
                .keyboardShortcut(.defaultAction).kropsPrimaryAction().tint(KropsStyle.accent)
                .disabled(
                    missionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || missionName.count > 70 || model.editingLocked)
            }
        }
    }
}

#Preview("Navigasi Krops") {
    let dependencies = ControlDependencies(demo: true)
    ContentView(
        model: dependencies.viewModel, link: dependencies.link, farms: dependencies.farms,
        location: dependencies.location, planner: dependencies.planner)
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.light)
}

private struct SidebarIconButton: View {
    let section: ControlPanelSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: section.icon)
                .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(Color.primary)
                .frame(width: 56, height: 56)
                .background(
                    Color.primary.opacity(isSelected ? 0.08 : isHovered ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Daftar misi") {
    let dependencies = ControlDependencies(demo: true)
    let _ = dependencies.viewModel.showMissionList()
    ContentView(
        model: dependencies.viewModel, link: dependencies.link, farms: dependencies.farms,
        location: dependencies.location, planner: dependencies.planner)
        .frame(width: 1280, height: 800)
        .preferredColorScheme(.light)
}
