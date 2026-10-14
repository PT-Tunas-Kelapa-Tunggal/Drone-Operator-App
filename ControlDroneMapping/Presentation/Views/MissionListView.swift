import SwiftUI

struct MissionListView: View {
    @ObservedObject var model: ControlViewModel
    var search: String
    var createMission: () -> Void
    @State private var renaming: SavedMission?
    @State private var deleting: SavedMission?
    @State private var name = ""

    var body: some View {
        ControlPanel("Misi tersimpan", state: nil) {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "Buka misi untuk mengatur area scan dan rencana survei. Setup kamera ada di panel Perangkat. Perubahan disimpan otomatis di Mac."
                )
                .foregroundStyle(.secondary)
                HStack {
                    Text(model.missionFilter == .all ? "Semua misi" : model.missionFilter.title)
                        .font(.caption).foregroundStyle(.secondary)
                    if model.missionFilter != .all {
                        Button("Tampilkan semua") { model.showMissionList() }.buttonStyle(.plain)
                    }
                }
                if let error = model.missionStorageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Coba simpan lagi") { model.retryMissionSaving() }
                }
                if model.savedMissions(search: search, filter: model.missionFilter).isEmpty {
                    Text(search.isEmpty ? "Belum ada misi tersimpan." : "Tidak ada misi yang cocok.")
                        .foregroundStyle(.secondary).padding(.vertical, 24)
                }
                ForEach(model.savedMissions(search: search, filter: model.missionFilter)) { mission in
                    HStack(spacing: 16) {
                        Image(systemName: "map").foregroundStyle(KropsStyle.accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mission.plan.name).font(KropsTypography.sectionTitle)
                            Text(mission.area.map { "Area: " + $0.name } ?? "Area scan belum diatur")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(
                                "\(mission.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(mission.phase == .idle ? "Tersimpan di Mac" : mission.phase.dashboardTitle)"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let id = mission.remoteID, mission.saved > 0 {
                            Button("Hasil") { model.showDatasets(missionID: id) }
                        }
                        Button("Buka misi") { model.openMission(mission.id) }
                        Menu {
                            Button("Ubah nama") {
                                name = mission.plan.name
                                renaming = mission
                            }
                            Button("Hapus misi", role: .destructive) { deleting = mission }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton).frame(width: 24).disabled(model.editingLocked)
                    }.padding(14).background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Buat misi", action: createMission).kropsPrimaryAction()
                    .disabled(model.editingLocked || model.missionStorageError != nil)
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
                if let deleting { model.deleteMission(deleting.id) }
                deleting = nil
            }
        } message: {
            Text(
                "Misi \(deleting?.plan.name ?? "") dan pengaturan area dihapus dari daftar Mac. Foto hasil pengambilan tetap tersedia di Hasil."
            )
        }
    }
}
