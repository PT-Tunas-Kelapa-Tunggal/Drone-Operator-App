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
                    if model.step == .mission && model.hasMissionDetail {
                        MissionWorkspaceView(
                            model: model, link: link, farms: farms, location: location,
                            planner: planner, openPlanner: { openPlanner(farm: model.selectedMission?.area) }
                        )
                        .id(model.selectedMissionID)
                        .padding(.horizontal, 22).padding(.bottom, 18)
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
                                    MissionListView(model: model, search: search) {
                                        missionName = ""
                                        newMission = true
                                    }
                                }
                            }.padding(22).frame(maxWidth: 1540).frame(maxWidth: .infinity)
                        }
                    }
                    if (model.step == .mission && model.hasMissionDetail
                        && model.selectedMission?.phase != .completed) || showingResults
                    {
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
        .onChange(of: model.step) { _, _ in search = "" }
        .onChange(of: model.selectedDatasetID) { _, _ in search = "" }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            KropsBrand().padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 20)
            ForEach(ControlScreen.allCases.filter { $0 != .settings }) { screen in navigation(screen) }
            Spacer()
            navigation(.settings)
            Divider().padding(.vertical, 10)
            Label("Operator", systemImage: "person.crop.circle.fill").font(.callout).foregroundStyle(
                .secondary
            ).padding(12)
        }.padding(12).frame(width: 176).frame(maxHeight: .infinity).background(.ultraThinMaterial)
            .overlay(alignment: .trailing) { Rectangle().fill(KropsStyle.border).frame(width: 1) }
    }
    private func navigation(_ screen: ControlScreen) -> some View {
        Button {
            model.navigate(screen)
        } label: {
            Label {
                Text(screen.title).font(.body.weight(model.step == screen ? .semibold : .regular))
            } icon: {
                Image(systemName: screen.icon).font(.system(size: 16)).frame(width: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(model.step == screen ? Color.white : Color.primary)
            .background(
                model.step == screen ? KropsStyle.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(screen.title)
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
            }.kropsToolbarAction().disabled(model.editingLocked)
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
                }.kropsPrimaryAction().disabled(model.editingLocked)
            }.frame(maxWidth: .infinity).padding(.vertical, 70)
        }
    }
    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Misi dapat dibuat tanpa iPhone. Koneksi dan persiapan kamera tersedia di panel Perangkat.")
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
