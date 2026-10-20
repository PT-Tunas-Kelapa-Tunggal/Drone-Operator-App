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

    private var filtered: [SavedMission] { model.savedMissions(search: search) }
    private var fresh: Bool { link.connected && model.freshness() }
    private var selectedArea: FarmArea? { farms.areas.first { $0.id == farms.selectedArea } }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 24)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    summary
                    missionTable
                    operationStatus
                }
                .frame(width: availableWidth * 0.65)

                mapPanel
                    .frame(width: availableWidth * 0.35, height: 700)
            }
        }
        .frame(height: max(700, 420 + CGFloat(max(3, filtered.count)) * 76))
        .fileImporter(
            isPresented: $importingArea,
            allowedContentTypes: [UTType(filenameExtension: "geojson") ?? .json, .json]
        ) { result in
            farms.importArea(result)
            if let error = farms.error { model.errorMessage = error }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            DashboardSummaryCard(
                title: "Perlu tindakan", value: model.dashboardAttentionCount, detail: "misi",
                icon: "exclamationmark.circle", colors: [
                    Color(red: 0.64, green: 0.40, blue: 0.87),
                    Color(red: 0.49, green: 0.28, blue: 0.75)
                ]
            ) { model.showMissionList(filter: .attention) }

            DashboardSummaryCard(
                title: "Dibuat hari ini", value: model.dashboardTodayCount, detail: "misi",
                icon: "sun.max", colors: [
                    Color(red: 1, green: 0.82, blue: 0.18),
                    Color(red: 0.96, green: 0.64, blue: 0.02)
                ], foreground: Color(red: 0.25, green: 0.16, blue: 0.02)
            ) { model.showMissionList(filter: .today) }

            DashboardSummaryCard(
                title: "Hasil tersedia", value: model.dashboardAvailableCount, detail: "dataset",
                icon: "photo.stack", colors: [
                    Color(red: 0.35, green: 0.49, blue: 0.88),
                    Color(red: 0.22, green: 0.35, blue: 0.74)
                ]
            ) { model.showDatasets(filter: .withPhotos) }
        }
    }

    private var missionTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Aktivitas pemetaan").font(.title3.weight(.semibold))
                    Text("Pantau kebun dan progres misi terbaru.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.showMissionList()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .frame(width: 32, height: 32)
                        .background(KropsStyle.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Lihat semua misi")
                .accessibilityLabel("Lihat semua misi")
            }
            .padding(20)

            GeometryReader { geometry in
                let width = max(0, geometry.size.width - 40)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableCell("Kebun / Misi", width: width * 0.30)
                        tableCell("Lokasi", width: width * 0.23)
                        tableCell("Foto", width: width * 0.10)
                        tableCell("Status", width: width * 0.22)
                        tableCell("Dibuat", width: width * 0.15)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(KropsStyle.canvas.opacity(0.65))

                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: search.isEmpty ? "leaf" : "magnifyingglass")
                                .font(.system(size: 28)).foregroundStyle(KropsStyle.accent)
                            Text(search.isEmpty ? "Mulai pemetaan pertamamu" : "Misi tidak ditemukan")
                                .font(.headline)
                            Text(search.isEmpty
                                ? "Buat misi untuk mulai memetakan kebun."
                                : "Coba nama misi atau ID yang lain.")
                                .font(.callout).foregroundStyle(.secondary)
                            if search.isEmpty {
                                Button("Buat misi") { createMission("") }
                                    .kropsPrimaryAction()
                                    .disabled(model.editingLocked || model.missionStorageError != nil)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 228)
                    } else {
                        ForEach(filtered) { mission in
                            Button { model.openMission(mission.id) } label: {
                                missionRow(mission, width: width)
                            }
                            .buttonStyle(.plain)
                            .help("Buka misi " + mission.plan.name)
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
            }
            .frame(height: 42 + CGFloat(max(3, filtered.count)) * 76)

            HStack {
                Text("\(filtered.count) misi").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Lihat semua misi") { model.showMissionList() }
                    .font(.callout.weight(.medium)).foregroundStyle(KropsStyle.accent)
                    .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(KropsStyle.border))
    }

    private func tableCell(_ text: String, width: CGFloat) -> some View {
        Text(text).lineLimit(1).frame(width: width, alignment: .leading)
    }

    private func missionRow(_ mission: SavedMission, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(mission.plan.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(mission.area?.name ?? "Area belum dipilih")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: width * 0.30, alignment: .leading)

            Text(mission.area?.name ?? "Belum diatur")
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .frame(width: width * 0.23, alignment: .leading)
            tableCell(mission.saved.formatted(), width: width * 0.10)
                .font(.callout.monospacedDigit())
            Text(mission.phase.dashboardTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(mission.phase))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(statusColor(mission.phase).opacity(0.10), in: Capsule())
                .lineLimit(1)
                .frame(width: width * 0.22, alignment: .leading)
            Text(mission.createdAt, format: .dateTime.day().month(.abbreviated))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: width * 0.15, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(height: 75)
        .contentShape(Rectangle())
    }

    private func statusColor(_ phase: MissionPhase) -> Color {
        switch phase {
        case .completed: return KropsStyle.accent
        case .failed, .paused: return .orange
        case .capturing, .countdown, .ready: return .blue
        case .idle: return .secondary
        }
    }

    private var operationStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Kesiapan perangkat").font(.callout.weight(.semibold))
                Text(fresh ? "iPhone terhubung dan siap diperiksa" : "Hubungkan iPhone untuk menyiapkan capture")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Circle().fill(fresh ? Color.green : Color.orange).frame(width: 7, height: 7)
            Button("Perangkat") { model.navigate(.devices) }
                .buttonStyle(.plain).font(.callout.weight(.medium))
                .foregroundStyle(KropsStyle.accent)
        }
        .padding(18)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jelajahi kebun").font(.title3.weight(.semibold))
                    Text("\(nearbyAreas.count) kebun di sekitar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { importingArea = true } label: {
                    Image(systemName: "plus").frame(width: 32, height: 32)
                        .background(KropsStyle.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Impor batas kebun GeoJSON")
                .accessibilityLabel("Impor batas kebun GeoJSON")
            }
            .padding(18)

            HStack(spacing: 8) {
                Picker("Radius", selection: $radiusKm) {
                    Text("5 km").tag(5.0)
                    Text("10 km").tag(10.0)
                    Text("25 km").tag(25.0)
                    Text("Semua").tag(0.0)
                }
                .labelsHidden().frame(width: 90)
                .disabled(location.sample == nil)
                .help("Radius kebun dari lokasi Mac")
                Spacer(minLength: 0)
                Button { location.request() } label: {
                    Label("Lokasi saya", systemImage: "location")
                }
                .help("Pusatkan peta pada perkiraan lokasi Mac")
                Button { openPlanner(selectedArea) } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .help("Rencanakan waypoint")
                .accessibilityLabel("Rencanakan waypoint")
            }
            .padding(.horizontal, 18).padding(.bottom, 14)

            FarmMap(
                areas: nearbyAreas, selected: $farms.selectedArea,
                operatorLocation: location.sample, focusRequest: location.focusRequest)
                .overlay(alignment: .bottomLeading) {
                    if let area = selectedArea {
                        mapSelection(area)
                    } else if farms.areas.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kebunmu muncul di sini").font(.headline)
                            Text("Impor batas GeoJSON untuk mulai menjelajahi area pemetaan.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Impor GeoJSON") { importingArea = true }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.leading, 14).padding(.trailing, 64).padding(.bottom, 20)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 8)

            Label(location.status, systemImage: "location.circle")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .padding(14)
            if !farms.areas.isEmpty && nearbyAreas.isEmpty {
                Text("Tidak ada kebun dalam radius ini.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(KropsStyle.border))
    }

    private func mapSelection(_ area: FarmArea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(area.name).font(.headline).lineLimit(2)
                Spacer()
                Button { farms.selectedArea = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Tutup detail kebun")
            }
            Button("Rencanakan waypoint") { openPlanner(area) }
            Button("Buat misi untuk kebun ini") { createMission(area.name) }
                .disabled(model.editingLocked)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.leading, 14).padding(.trailing, 64).padding(.bottom, 20)
    }
}

private struct DashboardSummaryCard: View {
    let title: String
    let value: Int
    let detail: String
    let icon: String
    let colors: [Color]
    var foreground: Color = .white
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: icon).font(.system(size: 24, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(foreground.opacity(0.16), in: Circle())
                }
                Spacer(minLength: 20)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value.formatted()).font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text(detail).font(.caption.weight(.medium)).opacity(0.85)
                }
                Text(title).font(.system(size: 15, weight: .semibold))
                    .lineLimit(2).frame(height: 38, alignment: .top)
            }
            .foregroundStyle(foreground)
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(height: 196)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30).fill(.white.opacity(isHovered ? 0.08 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title), \(value) \(detail)")
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
