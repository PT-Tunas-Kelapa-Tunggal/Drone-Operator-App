import AppKit
import SwiftUI

struct DatasetListView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    let search: String
    let export: (MissionRecord) -> Void
    private var active: Bool { model.isActiveMission }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(
                    model.selectedDatasetID.flatMap { id in
                        model.records.first(where: { $0.id == id })?.plan.name
                    }.map { "Hasil · " + $0 } ?? "Hasil misi"
                ).font(KropsTypography.pageTitle)
                Spacer()
                Button("Perbarui") { model.send(.list) }.disabled(!link.connected || model.pending != nil)
                Button("Buka Finder") { model.openDatasetFolder(missionID: link.receivedMissionID) }
            }
            HStack {
                Picker(
                    "Tampilkan",
                    selection: Binding(get: { model.datasetFilter }, set: { model.showDatasets(filter: $0) })
                ) { ForEach(DatasetFilter.allCases) { filter in Text(filter.title).tag(filter) } }.frame(
                    width: 240)
                if model.selectedDatasetID != nil { Button("Semua hasil") { model.showDatasets() } }
                Spacer()
            }
            Text(
                "Transfer ke Mac menyertakan foto pemetaan, RAW, metadata, dan gray card. Gunakan Siapkan WebODM setelah transfer selesai."
            ).font(.caption).foregroundStyle(.secondary)
            if model.filteredDatasets(search: search).isEmpty {
                Text(
                    model.selectedDatasetID != nil
                        && !model.records.contains(where: { $0.id == model.selectedDatasetID })
                        ? "Menunggu daftar hasil misi ini. Hubungkan iPhone lalu Perbarui."
                        : model.records.isEmpty
                            ? "Belum ada dataset. Buat misi pada layar Misi."
                            : "Tidak ada misi yang sesuai filter atau pencarian."
                ).foregroundStyle(.secondary).padding(.vertical, 40)
            }
            ForEach(model.filteredDatasets(search: search)) { record in
                HStack(spacing: 18) {
                    Image(systemName: "folder.fill").foregroundStyle(KropsStyle.accent).font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.plan.name).font(KropsTypography.sectionTitle)
                        Text(
                            "\(record.createdAt.formatted()) • \(record.saved) foto • \(record.id.uuidString.prefix(8))"
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Buka folder") { model.openDatasetFolder(missionID: record.id) }.disabled(
                        !model.hasLocalDataset(record.id))
                    if record.saved > 0 {
                        Button("Siapkan WebODM") { export(record) }.disabled(
                            link.receiving || link.sending || !model.hasLocalDataset(record.id))
                    } else {
                        Text("Belum ada foto pemetaan").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Transfer ke Mac") { model.send(.download, missionID: record.id) }
                        .kropsPrimaryAction().tint(KropsStyle.accent).disabled(!model.canOperate || active)
                }.padding(16).background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
            }
            Text(link.transferStatus).font(.caption).foregroundStyle(.secondary)
        }
    }
}
