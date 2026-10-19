import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OrthomosaicView: View {
    @ObservedObject var model: OrthomosaicViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var engineExpanded = false
    @State private var engineLog: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Buat orthomosaic").font(KropsTypography.pageTitle)
                    Text(model.selected?.name ?? "Hasil misi").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutup") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let project = model.selected {
                        Label(
                            "\(project.mappingPhotos.count) foto → Gray card opsional → Stitching → TIFF / GeoTIFF",
                            systemImage: "square.3.layers.3d"
                        ).font(.callout)
                        inputSection(project)
                        grayCardSection(project)
                        engineSection
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(
                                "Simpan data kerja setelah selesai",
                                isOn: Binding(
                                    get: { project.retainWorkingFiles == true },
                                    set: { model.setRetainWorkingFiles($0) }
                                )
                            ).disabled(model.busy)
                            Text(
                                "Biasanya tidak diperlukan dan dapat memakai beberapa GB. Foto asli, hasil, dan laporan tetap disimpan."
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        statusSection(project)
                        if !project.outputs.isEmpty { outputSection(project) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Text("Pengolahan berjalan di Mac. Foto asli tetap tersimpan.").font(.caption).foregroundStyle(
                    .secondary)
                Spacer()
                if model.workingID == model.selectedID {
                    Button("Hentikan") { model.cancel() }
                } else {
                    Button("Buat orthomosaic") { model.start() }
                        .kropsPrimaryAction(size: .large).tint(KropsStyle.accent).disabled(!model.canStart)
                }
            }
        }.padding(24).frame(width: 780, height: 780)
            .onAppear { engineExpanded = !model.engineReady }
    }

    private func inputSection(_ project: OrthomosaicProject) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Foto pemetaan", systemImage: "photo.on.rectangle.angled").font(.headline)
                    Spacer()
                    Button("Tambah foto dari Finder") {
                        OrthomosaicFilePanels.photos { model.importPhotos($0, append: true) }
                    }.disabled(model.busy)
                }
                Text(
                    "JPEG, HEIC, PNG, atau TIFF. Untuk RAW, gunakan JPEG pasangannya atau kembangkan terlebih dahulu."
                )
                .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Lihat \(project.mappingPhotos.count) foto pemetaan") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(project.mappingPhotos) { photo in
                            HStack {
                                Text(photo.url.lastPathComponent).font(.caption).lineLimit(1)
                                Spacer()
                                Button("Keluarkan") { model.excludePhoto(photo.id) }
                                    .font(.caption).disabled(model.busy)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                if project.mappingPhotos.count < 3 {
                    Text("Tambahkan minimal 3 foto berbeda dengan area saling tumpang tindih.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(8)
        }
    }

    private func grayCardSection(_ project: OrthomosaicProject) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Gray card awal (opsional)", systemImage: "circle.lefthalf.filled").font(.headline)
                    Spacer()
                    Button("Pilih dari Finder") {
                        OrthomosaicFilePanels.photos(single: true) { model.importPhotos($0, reference: true) }
                    }.disabled(model.busy)
                }
                if !project.references.isEmpty {
                    HStack {
                        Picker(
                            "Referensi",
                            selection: Binding(get: { project.referenceID }, set: { model.setReference($0) })
                        ) {
                            ForEach(project.references) { reference in
                                Text(reference.url.lastPathComponent).tag(Optional(reference.id))
                            }
                        }.disabled(model.busy)
                        Button(role: .destructive) {
                            model.removeGrayCard()
                        } label: {
                            Label("Hapus gray card", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(model.busy)
                        .help("Hapus semua referensi gray card dari misi dan olah tanpa normalisasi warna.")
                    }
                    Text("Hapus gray card untuk mengolah tanpa normalisasi warna. Foto asli tetap tersimpan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let preview = model.preview {
                    GeometryReader { geometry in
                        let width = min(
                            geometry.size.width,
                            geometry.size.height * CGFloat(preview.width) / CGFloat(preview.height))
                        let height = width * CGFloat(preview.height) / CGFloat(preview.width)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: preview.image, scale: 1).resizable().frame(
                                width: width, height: height)
                            Rectangle().stroke(.cyan, lineWidth: 2).background(Color.cyan.opacity(0.1))
                                .frame(
                                    width: width * project.patch.width, height: height * project.patch.height
                                )
                                .offset(x: width * project.patch.x, y: height * project.patch.y)
                        }.frame(width: width, height: height).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0).onChanged { value in
                                    model.movePatch(
                                        x: Double(value.location.x / width),
                                        y: Double(value.location.y / height))
                                })
                    }.frame(height: 200)
                    HStack {
                        Text("Ukuran area kartu").font(.caption)
                        Slider(
                            value: Binding(get: { project.patch.width }, set: { model.setPatchSize($0) }),
                            in: 0.04...0.5
                        ).frame(width: 200).disabled(model.busy)
                    }
                    Text(
                        "Klik atau geser kotak ke area kartu yang polos, tanpa tepi, bayangan, atau silau. Foto kartu tidak ikut dijahit."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Toggle(
                        "Ini gray card 18% dari awal pengambilan, dengan pengaturan kamera yang sama",
                        isOn: Binding(get: { project.confirmed }, set: { model.setConfirmed($0) })
                    )
                    .disabled(model.busy)
                } else {
                    Text(
                        project.references.isEmpty
                            ? "Tanpa gray card, foto tetap bisa diolah tanpa normalisasi warna. Unggah gray card jika ingin menggunakan normalisasi."
                            : "Memuat foto referensi…"
                    )
                    .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(8)
        }
    }

    private var engineSection: some View {
        DisclosureGroup(isExpanded: $engineExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.engineMessage).font(.caption).foregroundStyle(
                    model.engineReady ? Color.secondary : Color.orange)
                Text(
                    "Engine disertakan dalam aplikasi untuk Mac Apple Silicon. Setelah pemeriksaan selesai, pengolahan berjalan offline."
                )
                .font(.caption).foregroundStyle(.secondary)
                if let progress = model.engineProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.message).font(.callout)
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        if let detail = progress.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Panel ini boleh ditutup. Biarkan aplikasi tetap terbuka sampai selesai.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                HStack {
                    if model.engineInstalling {
                        Button("Batalkan pemasangan") { model.cancelEngineInstallation() }
                    } else if !model.engineReady && model.hasEngineInstaller {
                        Button(model.engineInstallFailed ? "Coba periksa lagi" : "Periksa engine") {
                            model.installEngine()
                        }.kropsPrimaryAction().disabled(model.busy)
                    }
                    if model.allowsExternalEngine {
                        Button("Pilih folder engine") {
                            OrthomosaicFilePanels.runtime { model.checkRuntime($0) }
                        }
                        .disabled(model.busy || model.engineInstalling)
                    }
                    Button("Panduan pemasangan") {
                        if let url = Bundle.main.url(forResource: "ORTHOMOSAIC_ENGINE", withExtension: "md") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if let log = model.engineInstallationLog {
                    Button("Lihat rincian pemasangan") {
                        engineLog =
                            (try? String(contentsOf: log, encoding: .utf8))
                            ?? "Rincian pemasangan belum dapat dibaca."
                    }
                    .font(.caption)
                }
                if let engineLog {
                    HStack {
                        Text("Rincian pemasangan").font(.caption.bold())
                        Spacer()
                        Button("Tutup rincian") { self.engineLog = nil }.font(.caption)
                    }
                    ScrollView {
                        Text(String(engineLog.suffix(16_384))).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 180)
                }
            }.padding(.top, 8)
        } label: {
            Label(
                model.engineReady ? "Engine lokal siap" : "Persiapan engine lokal",
                systemImage: model.engineReady ? "checkmark.circle.fill" : "gearshape")
        }
    }

    private func statusSection(_ project: OrthomosaicProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let id = model.workingID, id != project.id {
                Text(
                    "Misi \(model.project(id)?.name ?? "lain") sedang diolah. Tunggu hingga selesai untuk memulai misi ini."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(project.state.title).font(.headline)
                Spacer()
                Button("Buka folder misi") { model.openFolder(project.id) }
            }
            if project.state.isRunning { ProgressView(value: project.fraction) }
            Text(project.message).font(.callout).textSelection(.enabled)
                .foregroundStyle(project.state == .failed ? Color.orange : Color.secondary)
            if !project.state.isRunning && !project.colorPreparationReady {
                Text("Konfirmasi area gray card untuk mengaktifkan pengolahan.").font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outputSection(_ project: OrthomosaicProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Riwayat hasil misi ini").font(.headline)
            ForEach(project.outputs, id: \.folder) { output in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(output.georeferenced ? "GeoTIFF" : "TIFF · koordinat lokal").font(.headline)
                            Spacer()
                            Text(output.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(
                            "\(output.width) × \(output.height) piksel · \(output.registered)/\(output.total) foto"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        if let preview = NSImage(
                            contentsOf: output.folder.appendingPathComponent("preview.png"))
                        {
                            Image(nsImage: preview).resizable().scaledToFit().frame(maxHeight: 220)
                                .frame(maxWidth: .infinity).background(Color.black.opacity(0.05))
                        }
                        ForEach(Array(output.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Tampilkan di Finder") { model.showOutput(output) }
                            Button("Simpan TIFF ke…") {
                                OrthomosaicFilePanels.save(output: output, model: model)
                            }
                            .disabled(model.busy)
                        }
                    }.padding(8)
                }
            }
        }
    }
}

/// User-selected file grants are handed to the import service and copied before they are released.
enum OrthomosaicFilePanels {
    static func photos(single: Bool = false, folder: Bool = false, completion: ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title =
            single ? "Pilih gray card awal" : folder ? "Pilih folder foto pemetaan" : "Pilih foto pemetaan"
        panel.prompt = "Impor"
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = !single && !folder
        panel.allowedContentTypes = folder ? [.folder] : [.jpeg, .png, .tiff, .heic, .heif]
        if panel.runModal() == .OK { completion(panel.urls) }
    }
    static func runtime(completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Pilih folder engine lokal"
        panel.message = "Pilih folder yang berisi environment dan OpenSfM."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder]
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }
    static func save(output: OrthomosaicOutput, model: OrthomosaicViewModel) {
        let panel = NSSavePanel()
        panel.title = "Simpan orthomosaic"
        panel.nameFieldStringValue = "orthomosaic.tif"
        panel.allowedContentTypes = [.tiff]
        if panel.runModal() == .OK, let url = panel.url { model.exportOutput(output, to: url) }
    }
}
