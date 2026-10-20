import AppKit
import SwiftUI

struct DatasetListView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var processing: OrthomosaicViewModel
    let search: String
    var resetSearch: () -> Void = {}
    let export: (MissionRecord) -> Void
    private var active: Bool { model.isActiveMission }
    private func processingID(_ record: MissionRecord) -> UUID {
        model.missionLibrary.missions.first { $0.remoteID == record.id || $0.id == record.id }?.id
            ?? processing.projects.first { $0.datasetID == record.id }?.id ?? record.id
    }
    private var resultRecords: [MissionRecord] {
        let pending = model.missionLibrary.missions.filter { mission in
            !model.records.contains { $0.id == mission.remoteID || $0.id == mission.id }
        }.map { mission in
            MissionRecord(
                id: mission.remoteID ?? mission.id, createdAt: mission.createdAt,
                plan: mission.plan, phase: mission.phase, saved: mission.saved)
        }
        return (model.records + pending).filter { !model.missionLibrary.hiddenRemoteIDs.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }
    private var visibleRecords: [MissionRecord] {
        resultRecords.filter { record in
            let project = processing.project(processingID(record))
            guard
                model.selectedDatasetID == nil || model.selectedDatasetID == record.id
                    || model.selectedDatasetID == processingID(record),
                search.isEmpty || record.plan.name.localizedCaseInsensitiveContains(search)
                    || record.id.uuidString.localizedCaseInsensitiveContains(search)
                    || processingID(record).uuidString.localizedCaseInsensitiveContains(search)
            else { return false }
            switch model.datasetFilter {
            case .all: return true
            case .attention:
                return [.idle, .paused, .failed].contains(record.phase)
                    || project?.state == .failed || project?.state == .cancelled
            case .today: return Calendar.current.isDateInToday(record.createdAt)
            case .withPhotos: return record.saved > 0 || !(project?.mappingPhotos.isEmpty ?? true)
            }
        }
    }
    private var imported: [OrthomosaicProject] {
        processing.projects.filter { project in
            guard !model.missionLibrary.hiddenRemoteIDs.contains(project.id),
                project.datasetID.map({ !model.missionLibrary.hiddenRemoteIDs.contains($0) }) ?? true,
                !resultRecords.contains(where: { processingID($0) == project.id }),
                model.selectedDatasetID == nil || model.selectedDatasetID == project.id
                    || model.selectedDatasetID == project.datasetID,
                search.isEmpty || project.name.localizedCaseInsensitiveContains(search)
                    || project.id.uuidString.localizedCaseInsensitiveContains(search)
            else { return false }
            switch model.datasetFilter {
            case .all: return true
            case .attention: return project.state == .failed || project.state == .cancelled
            case .today: return Calendar.current.isDateInToday(project.createdAt)
            case .withPhotos: return !project.mappingPhotos.isEmpty
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hasil misi").font(KropsTypography.pageTitle)
                Spacer()
                Menu {
                    Button("Pilih foto pemetaan…") {
                        OrthomosaicFilePanels.photos { urls in
                            resetSearch()
                            model.showDatasets()
                            processing.importPhotos(urls)
                        }
                    }
                    Button("Pilih folder foto…") {
                        OrthomosaicFilePanels.photos(folder: true) { urls in
                            resetSearch()
                            model.showDatasets()
                            processing.importPhotos(urls)
                        }
                    }
                } label: {
                    Label("Impor dari Finder", systemImage: "square.and.arrow.down")
                }
                .disabled(processing.busy || processing.storageError != nil)
                Button("Perbarui") {
                    model.refreshLocalDatasets()
                    if link.connected { model.send(.list) }
                }.disabled(model.pending != nil)
            }
            HStack {
                Picker(
                    "Tampilkan",
                    selection: Binding(get: { model.datasetFilter }, set: { model.showDatasets(filter: $0) })
                ) {
                    ForEach(DatasetFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }.frame(width: 240)
                if model.selectedDatasetID != nil { Button("Semua hasil") { model.showDatasets() } }
                Spacer()
            }
            Text(
                "Olah foto per misi: normalisasi gray card awal, stitching, lalu simpan orthomosaic TIFF/GeoTIFF. Gunakan hasil transfer iPhone atau impor foto dari Finder."
            )
            .font(.callout).foregroundStyle(.secondary)
            if let failure = processing.storageError {
                Text("Riwayat pengolahan belum dapat dibaca: " + failure).foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            if let error = processing.error {
                HStack {
                    Text(error).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer()
                    Button("Tutup") { processing.error = nil }
                }
            }
            if let id = processing.workingID, let project = processing.project(id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Mengolah · " + project.name, systemImage: "gearshape.2")
                        Spacer()
                        Button("Lihat progres") { processing.open(id) }
                        Button("Hentikan") { processing.cancel() }
                    }
                    ProgressView(value: project.fraction)
                    Text(project.message).font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            } else if processing.busy {
                ProgressView("Menyiapkan berkas dan engine lokal…").font(.callout)
            }
            if visibleRecords.isEmpty && imported.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(
                        .secondary)
                    Text(
                        model.selectedDatasetID != nil
                            ? "Belum ada hasil lokal untuk misi ini." : "Belum ada hasil yang sesuai."
                    )
                    .font(.headline)
                    Text("Transfer hasil iPhone atau impor foto dari Finder untuk memulai.").foregroundStyle(
                        .secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(visibleRecords) { record in missionRow(record) }
            ForEach(imported) { project in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "photo.stack.fill").foregroundStyle(KropsStyle.accent).font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name).font(KropsTypography.sectionTitle)
                            Text(
                                "\(project.fromMission ? "Arsip misi" : "Impor Finder") · \(project.mappingPhotos.count) foto · \(project.createdAt.formatted())"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Buka folder") { processing.openFolder(project.id) }
                        Button("Olah foto") { processing.open(project.id) }
                            .kropsPrimaryAction().tint(KropsStyle.accent)
                    }
                    projectStatus(project)
                }.padding(16).background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
            }
            Text(link.transferStatus).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func missionRow(_ record: MissionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill").foregroundStyle(KropsStyle.accent).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.plan.name).font(KropsTypography.sectionTitle)
                    Text(
                        "\(record.createdAt.formatted()) · \(record.saved) foto · \(record.id.uuidString.prefix(8))"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Lainnya") {
                    Button("Buka folder foto asli") { model.openDatasetFolder(missionID: record.id) }
                        .disabled(!model.hasLocalDataset(record.id))
                    Button("Impor foto ke misi ini…") {
                        OrthomosaicFilePanels.photos {
                            processing.importPhotos($0, mission: record, projectID: processingID(record))
                        }
                    }.disabled(processing.busy)
                    if processing.project(processingID(record)) != nil {
                        Button("Muat ulang foto transfer") {
                            processing.prepareMission(record, projectID: processingID(record), refresh: true)
                        }
                        .disabled(
                            processing.busy || link.receiving || link.sending
                                || !model.hasLocalDataset(record.id)
                                || (active && model.telemetry.missionID == record.id))
                    }
                    Button("Siapkan WebODM…") { export(record) }
                        .disabled(
                            link.receiving || link.sending || !model.hasLocalDataset(record.id)
                                || record.saved == 0)
                }
                if !model.hasLocalDataset(record.id) && model.records.contains(where: { $0.id == record.id })
                {
                    Button("Transfer ke Mac") { model.send(.download, missionID: record.id) }
                        .disabled(!model.canOperate || active)
                }
                if !model.hasLocalDataset(record.id) && processing.project(processingID(record)) == nil {
                    Button("Impor foto") {
                        OrthomosaicFilePanels.photos {
                            processing.importPhotos($0, mission: record, projectID: processingID(record))
                        }
                    }.kropsPrimaryAction().tint(KropsStyle.accent).disabled(
                        processing.busy || processing.storageError != nil)
                } else {
                    Button("Olah foto") { processing.prepareMission(record, projectID: processingID(record)) }
                        .kropsPrimaryAction().tint(KropsStyle.accent)
                        .disabled(
                            processing.storageError != nil
                                || (processing.project(processingID(record)) == nil
                                    && (processing.busy || link.receiving || link.sending
                                        || !model.hasLocalDataset(record.id)
                                        || (active && model.telemetry.missionID == record.id)))
                        )
                }
            }
            if let project = processing.project(processingID(record)) {
                projectStatus(project)
            } else {
                Text(
                    model.hasLocalDataset(record.id)
                        ? "Foto tersedia di Mac. Pilih Olah foto untuk memulai."
                        : "Transfer foto atau pilih Lainnya → Impor foto ke misi ini."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
    }
    private func projectStatus(_ project: OrthomosaicProject) -> some View {
        HStack {
            Label(
                project.state.title,
                systemImage: project.state == .completed ? "checkmark.circle.fill" : "square.3.layers.3d"
            )
            .foregroundStyle(project.state == .failed ? Color.orange : Color.secondary)
            Text(project.message).lineLimit(2).foregroundStyle(.secondary)
            Spacer()
            if let output = project.outputs.first {
                Button(output.georeferenced ? "Lihat GeoTIFF" : "Lihat TIFF") {
                    processing.showOutput(output)
                }
            }
        }.font(.caption)
    }
}
