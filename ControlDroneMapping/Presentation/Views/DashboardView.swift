import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    var search: String
    var openPlanner: (FarmArea?) -> Void
    var createMission: (String) -> Void
    @State private var importingArea = false
    @State private var radiusKm = 10.0
    private var nearbyAreas: [FarmArea] {
        farms.nearbyAreas(center: location.sample?.coordinate, radiusKm: radiusKm)
    }
    private var availableCount: Int { model.dashboardAvailableCount }
    private var attention: Int { model.dashboardAttentionCount }
    private var today: Int { model.dashboardTodayCount }
    private var filtered: [SavedMission] { model.savedMissions(search: search) }
    private var fresh: Bool { link.connected && model.freshness() }
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                highlight(
                    "Perlu tindakan", value: "\(attention) misi", icon: "exclamationmark.circle",
                    color: .orange
                ) {
                    model.showMissionList(filter: .attention)
                }
                highlight(
                    "Misi dibuat hari ini", value: "\(today) misi", icon: "calendar", color: KropsStyle.accent
                ) { model.showMissionList(filter: .today) }
                highlight(
                    "Hasil tersedia", value: "\(availableCount) dataset", icon: "photo.stack",
                    color: KropsStyle.accent
                ) { model.showDatasets(filter: .withPhotos) }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 16) {
                    card {
                        HStack {
                            Text("Misi terbaru").font(KropsTypography.sectionTitle)
                            Spacer()
                            Button("Lihat misi") { model.showMissionList() }.buttonStyle(.plain)
                                .foregroundStyle(KropsStyle.accent)
                        }
                        ForEach(Array(filtered.prefix(3))) { mission in
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text(mission.plan.name).font(KropsTypography.sectionTitle)
                                Text(mission.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(mission.area.map { "Area: " + $0.name } ?? "Area scan belum diatur")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text(
                                        mission.phase == .idle
                                            ? "Tersimpan di Mac" : mission.phase.dashboardTitle
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Buka misi") { model.openMission(mission.id) }
                                        .buttonStyle(.plain).foregroundStyle(KropsStyle.accent)
                                }
                            }
                        }
                        if filtered.isEmpty {
                            Text(
                                search.isEmpty
                                    ? "Belum ada misi. Mulai dengan nama kebun atau area pemetaan."
                                    : "Tidak ada misi yang cocok."
                            )
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        Button("Buat misi") { createMission("") }
                            .kropsPrimaryAction().disabled(
                                model.editingLocked || model.missionStorageError != nil)
                    }
                    card {
                        Text("Kondisi operasi").font(KropsTypography.sectionTitle)
                        Label("Cuaca belum terhubung", systemImage: "cloud.sun").font(.callout)
                            .foregroundStyle(.secondary)
                        Divider()
                        status("Drone", value: "Dikelola di QGroundControl", icon: "paperplane", online: nil)
                        status(
                            "iPhone",
                            value: link.connected ? fresh ? "Terhubung" : "Sinkronisasi…" : "Terputus",
                            icon: "iphone", online: fresh)
                        status(
                            "Ruang iPhone",
                            value: fresh
                                ? ByteCountFormatter.string(
                                    fromByteCount: model.telemetry.freeBytes, countStyle: .file) + " tersedia"
                                : "Menunggu perangkat", icon: "internaldrive", online: nil)
                        if fresh {
                            status(
                                "Baterai",
                                value: model.telemetry.battery >= 0
                                    ? String(format: "%.0f%%", model.telemetry.battery * 100)
                                    : "Belum tersedia", icon: "battery.75percent", online: nil)
                            status(
                                "Suhu", value: model.telemetry.thermal, icon: "thermometer.medium",
                                online: nil)
                        }
                    }
                }.frame(width: 320)
                mapPanel.frame(maxWidth: .infinity).frame(minHeight: 560)
            }
        }
        .fileImporter(
            isPresented: $importingArea,
            allowedContentTypes: [UTType(filenameExtension: "geojson") ?? .json, .json]
        ) { result in
            farms.importArea(result)
            if let error = farms.error { model.errorMessage = error }
        }
    }
    private var mapPanel: some View {
        FarmMap(
            areas: nearbyAreas, selected: $farms.selectedArea, operatorLocation: location.sample,
            focusRequest: location.focusRequest
        )
        .overlay(alignment: .topLeading) {
            Label("Kebun sekitar · \(nearbyAreas.count)", systemImage: "map").font(
                KropsTypography.sectionTitle
            ).padding(12)
                .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12)).padding(14)
                .padding(.top, 32)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Picker("Radius", selection: $radiusKm) {
                    Text("5 km").tag(5.0)
                    Text("10 km").tag(10.0)
                    Text("25 km").tag(25.0)
                    Text("Semua").tag(0.0)
                }.labelsHidden().frame(width: 95).disabled(location.sample == nil).help(
                    "Radius dari lokasi Mac ke perkiraan pusat kebun yang sudah tersimpan.")
                Button {
                    location.request()
                } label: {
                    Label("Lokasi saya", systemImage: "location")
                }.help("Minta izin lokasi Mac dan pusatkan peta. Lokasi perkiraan, bukan home drone.")
                Button {
                    importArea()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }.help("Impor batas kebun GeoJSON")
                Button {
                    openPlanner(farms.areas.first { $0.id == farms.selectedArea })
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }.help("Buat atau lanjutkan rute waypoint")
            }.padding(10).background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12)).padding(14)
        }
        .overlay(alignment: .bottomLeading) {
            if let area = farms.areas.first(where: { $0.id == farms.selectedArea }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(area.name).font(KropsTypography.sectionTitle)
                        Spacer()
                        Button {
                            farms.selectedArea = nil
                        } label: {
                            Image(systemName: "xmark")
                        }.buttonStyle(.plain)
                    }
                    Label("Batas kebun tersimpan", systemImage: "checkmark.circle.fill").font(.caption)
                        .foregroundStyle(.green)
                    Text("Buat misi, lalu pilih batas area scan di dalam misi tersebut.").font(.caption)
                        .foregroundStyle(
                            .secondary)
                    Button("Rencanakan waypoint") { openPlanner(area) }
                    Button("Buat misi untuk kebun ini") { createMission(area.name) }.disabled(
                        model.editingLocked)
                }.padding(16).frame(width: 260).background(
                    KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14)
                ).padding(14).padding(.bottom, 30)
            } else if farms.areas.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Belum ada kebun tersimpan").font(KropsTypography.sectionTitle)
                    Text(
                        "Impor batas GeoJSON kebun. Aktifkan lokasi Mac untuk melihat kebun tersimpan di sekitar operator."
                    ).font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Impor GeoJSON") { importArea() }
                    Text(
                        "Citra satelit membutuhkan jaringan. Capture iPhone tetap berjalan tanpa internet."
                    ).font(KropsTypography.supporting).foregroundStyle(.secondary)
                }.padding(16).frame(width: 270).background(
                    KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14)
                ).padding(14).padding(.bottom, 30)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(location.status).font(.caption).lineLimit(3)
                if !farms.areas.isEmpty && nearbyAreas.isEmpty {
                    Text("Tidak ada kebun tersimpan dalam radius ini.").font(.caption)
                }
            }.padding(10).frame(maxWidth: 300).background(
                KropsStyle.surface, in: RoundedRectangle(cornerRadius: 10)
            ).padding(.trailing, 75).padding(.bottom, 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KropsStyle.border))
    }
    private func importArea() { importingArea = true }
    private func highlight(
        _ title: String, value: String, icon: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(color).frame(
                    width: 36, height: 36
                ).background(color.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.callout).foregroundStyle(.secondary)
                    Text(value).font(KropsTypography.metric).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 72).background(
                KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14)
            ).overlay(RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
        }.buttonStyle(.plain)
    }
    private func status(_ title: String, value: String, icon: String, online: Bool?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            Text(title)
            Spacer()
            if let online { Circle().fill(online ? Color.green : Color.orange).frame(width: 6, height: 6) }
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.font(KropsTypography.supporting)
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).padding(18).frame(
            maxWidth: .infinity, alignment: .leading
        )
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(
            RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
    }
}

extension MissionPhase {
    var dashboardTitle: String {
        switch self {
        case .idle: return "Belum disiapkan"
        case .ready: return "Siap dikonfigurasi"
        case .countdown: return "Hitung mundur"
        case .capturing: return "Pengambilan berjalan"
        case .paused: return "Dijeda"
        case .completed: return "Selesai"
        case .failed: return "Perlu diperiksa"
        }
    }
}
