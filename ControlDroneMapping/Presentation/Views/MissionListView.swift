import MapKit
import SwiftUI

struct MissionListView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var planner: FlightPlannerViewModel
    @ObservedObject var processing: OrthomosaicViewModel
    var search: String
    @State private var renaming: SavedMission?
    @State private var deleting: SavedMission?
    @State private var name = ""

    private var missions: [SavedMission] {
        model.savedMissions(search: search, filter: model.missionFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.missionFilter.title).font(.title3.weight(.semibold))
                Text("\(missions.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if model.missionFilter != .all {
                    Button("Hapus filter") { model.showMissionList() }
                }
            }
            if model.errorMessage?.hasPrefix("Sisa misi terhapus") == true {
                Button("Coba bersihkan sisa misi lagi") {
                    model.cleanDeletedMissionFiles(legacyIDs: processing.legacyDeletedFileIDs(liveIDs: model.liveMissionFileIDs, hiddenIDs: model.missionLibrary.hiddenRemoteIDs)) { ids in
                        try processing.removeMissionFiles(ids)
                        planner.removeMissionRoutes(ids)
                    }
                }.disabled(processing.busy)
            }
            if let error = model.missionStorageError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Coba simpan lagi") { model.retryMissionSaving() }
            }
            if missions.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "Belum ada misi di daftar ini" : "Misi tidak ditemukan",
                    systemImage: search.isEmpty ? "map" : "magnifyingglass",
                    description: Text(search.isEmpty
                        ? "Gunakan Misi baru di kanan atas untuk mulai merencanakan rute."
                        : "Coba nama atau ID misi lain."))
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(missions) { mission in
                        missionRow(mission)
                    }
                }
            }
        }
        .sheet(item: $renaming) { mission in
            VStack(alignment: .leading, spacing: 16) {
                Text("Ubah nama misi").font(KropsTypography.sectionTitle)
                TextField("Nama misi", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Batal") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Simpan") {
                        model.renameMission(mission.id, name: name)
                        renaming = nil
                    }
                    .kropsPrimaryAction().keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 70)
                }
            }.padding(24).frame(width: 420)
        }
        .alert(
            "Hapus misi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Batal", role: .cancel) { deleting = nil }
            Button("Hapus", role: .destructive) {
                if let deleting {
                    model.deleteMission(deleting.id) { ids in
                        try processing.removeMissionFiles(ids)
                        planner.removeMissionRoutes(ids)
                    }
                }
                deleting = nil
            }
        } message: {
            Text(
                "Misi \(deleting?.plan.name ?? "") beserta foto lokal, rute, hasil orthomosaic, dan cache pengolahannya akan dihapus permanen dari Mac. Foto sumber impor di luar aplikasi dan foto di iPhone tetap ada."
            )
        }
    }

    private func missionRow(_ mission: SavedMission) -> some View {
        let route = planner.routes.last { $0.missionID == mission.id }
        return HStack(spacing: 20) {
            MissionRouteThumbnail(route: route)
                .frame(width: 148, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                Text(mission.plan.name).font(.headline).lineLimit(1)
                    .help(mission.plan.name)
                if let route, !route.waypoints.isEmpty {
                    Text(String(format: "%d waypoint · %.0f m rute", route.waypoints.count, route.distance))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(planner.storageError == nil ? "Belum ada waypoint" : "Rute belum tersedia")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(mission.createdAt.formatted(
                    .dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "id_ID"))))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Text(mission.phase == .idle ? "Draft" : mission.phase.dashboardTitle)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(KropsStyle.canvas, in: Capsule())
            Button(mission.phase == .completed ? "Buka" : "Lanjutkan") {
                model.openMission(mission.id)
            }.controlSize(.large)
            Menu {
                Button("Salin ID misi") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mission.id.uuidString, forType: .string)
                }
                if let id = mission.remoteID, mission.saved > 0 {
                    Button("Lihat hasil") { model.showDatasets(missionID: id) }
                }
                Divider()
                Button("Ubah nama") {
                    name = mission.plan.name
                    renaming = mission
                }.disabled(model.editingLocked || processing.busy)
                Button("Hapus misi", role: .destructive) { deleting = mission }
                    .disabled(model.editingLocked)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 24).accessibilityLabel("Opsi misi " + mission.plan.name)
        }
        .padding(16)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
    }
}

/// A schematic of the saved route, without network requests or interactive maps in each row.
private struct MissionRouteThumbnail: View {
    let route: FlightRoute?

    private var coordinates: [MapCoordinate] {
        guard let route else { return [] }
        return ((route.home.map { [$0] } ?? []) + route.waypoints.map(\.coordinate)).filter(\.isValid)
    }

    var body: some View {
        Group {
            if coordinates.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.title2)
                }.foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Canvas { context, size in
                    let points = coordinates.map { MKMapPoint($0.clCoordinate) }
                    let minX = points.map(\.x).min() ?? 0
                    let maxX = points.map(\.x).max() ?? 0
                    let minY = points.map(\.y).min() ?? 0
                    let maxY = points.map(\.y).max() ?? 0
                    let scale = min((size.width - 28) / max(maxX - minX, 1),
                                    (size.height - 28) / max(maxY - minY, 1))
                    let projected = points.map {
                        CGPoint(x: size.width / 2 + ($0.x - (minX + maxX) / 2) * scale,
                                y: size.height / 2 + ($0.y - (minY + maxY) / 2) * scale)
                    }
                    if let first = projected.first {
                        var path = Path()
                        path.move(to: first)
                        for point in projected.dropFirst() { path.addLine(to: point) }
                        if route?.returnToHome == true && route?.home != nil { path.closeSubpath() }
                        context.stroke(path, with: .color(KropsStyle.accent), lineWidth: 2)
                    }
                    for (index, point) in projected.enumerated() {
                        let isHome = index == 0 && route?.home?.isValid == true
                        let dot = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                        context.fill(dot, with: .color(isHome ? KropsStyle.accent : .orange))
                        context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                    }
                }
                .accessibilityLabel("Sketsa rute dengan \(route?.waypoints.count ?? 0) waypoint")
                .help("Sketsa rute tersimpan; titik hijau adalah Home.")
            }
        }
        .background(KropsStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
}
