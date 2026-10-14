import AppKit
import SwiftUI

struct PhotoQualityView: View {
    @ObservedObject var model: ControlViewModel
    @State private var reviewExpanded = false
    @State private var zoom = 1.0
    var body: some View {
        ControlPanel(
            "Foto uji & kalibrasi", state: model.sample != nil && model.review.complete ? "Diperiksa" : nil
        ) {
            if let preview = model.displayedPreview, let image = NSImage(data: preview.imageData) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 480 * zoom).padding(4)
                }
                .frame(height: 230).background(.black, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text(preview.kind == "quality-test" ? "Foto uji" : "Referensi").font(.caption)
                    Text(
                        String(
                            format: "%d × %d • %.2f s", preview.width, preview.height, preview.captureSeconds)
                    ).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Slider(value: $zoom, in: 1...3).frame(width: 90).help(
                        "Zoom preview. Periksa foto asli untuk ketajaman pixel.")
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo").font(.largeTitle)
                    Text("Foto uji akan muncul di sini").font(.callout)
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 230).background(
                    Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
            if let sample = model.sample, sample.settings == model.plan.camera {
                if let actual = sample.actualExposure, actual.iso.isFinite, actual.shutterSeconds.isFinite,
                    actual.shutterSeconds > 0
                {
                    Text(
                        String(
                            format: "Foto asli: ISO %.0f • shutter 1/%.0f s", actual.iso,
                            1 / actual.shutterSeconds)
                    )
                    .font(.caption).foregroundStyle(
                        actual.matches(model.plan.camera) ? Color.secondary : Color.orange)
                }
                if let required = MissionStorage.requiredBytes(
                    sampleBytes: sample.storedBytes, photoCount: model.plan.photoLimit)
                {
                    Text(
                        "Perkiraan ruang misi: "
                            + ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                            + " (termasuk margin dan cadangan)"
                    ).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let sample = model.sample, sample.settings == model.plan.camera,
                let assessment = sample.assessment
            {
                Text(assessment.advice).font(.caption).foregroundStyle(
                    assessment.blocker == nil ? Color.secondary : Color.orange)
            }
            if let sample = model.sample, sample.settings == model.plan.camera,
                let sharpness = sample.sharpness
            {
                Text(sharpness.advice).font(.caption).foregroundStyle(.secondary)
            }
            if let interval = model.suggestedCaptureInterval {
                HStack {
                    Text(String(format: "Interval minimal dari foto uji: %.1f s", interval)).font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Sesuaikan interval") { model.adjustCaptureInterval() }.controlSize(.small)
                        .disabled(model.editingLocked)
                }
            }
            Toggle("Gunakan gray card 18%", isOn: $model.geometry.useGrayCard).font(.callout).disabled(
                model.editingLocked || model.guidedMode)
            if model.geometry.useGrayCard {
                Text(
                    model.referenceSaved
                        ? "Referensi tersimpan. Singkirkan kartu, lalu ambil foto uji area survei."
                        : "Letakkan kartu pada cahaya survei, menutupi sebagian besar gambar, termasuk bagian tengah. Hindari bayangan dan silau."
                )
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(
                        model.referenceSaved
                            ? "Ukur ulang kartu"
                            : model.guidedMode
                                ? "2. Ukur cahaya & warna kartu" : "Ambil referensi gray card 18%"
                    ) { model.send(.grayCardReference) }
                    .disabled(!model.canOperate || !model.settingsApplied || model.editingLocked)
                    if model.referenceSaved {
                        Label("Warna terkunci", systemImage: "checkmark.circle.fill").font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                DisclosureGroup("Apa yang dikalibrasi?") {
                    Text(
                        "Mode panduan mengukur exposure lewat metering kamera pada kartu, menentukan ISO dan shutter dalam batas gerak, lalu mengunci exposure dan white balance. Mode manual mempertahankan ISO/shutter yang kamu isi. Foto asli referensi disimpan. Referensi awal/akhir membantu koreksi saat pengolahan; perubahan matahari atau awan selama penerbangan belum dinormalisasi otomatis. Nilai reflektansi 18% bukan target kecerahan 18% pada JPEG."
                    )
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }.font(.caption)
            } else {
                Text(
                    "White balance memakai pengaturan manual di panel Kamera. Periksa warna dan exposure pada foto uji."
                ).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(model.guidedMode ? "3. Cari fokus & ambil foto uji" : "Ambil foto uji") {
                    model.send(.testCapture)
                }.kropsPrimaryAction().tint(KropsStyle.accent)
                    .disabled(
                        !model.canOperate || !model.settingsApplied || model.editingLocked
                            || (model.geometry.useGrayCard && !model.referenceSaved)
                    )
                    .help(
                        "Singkirkan kartu. Arahkan ke objek bertekstur pada jarak kerja; autofocus lalu terkunci. Fokus pada monitor dekat hanya cocok untuk uji meja."
                    )
                Spacer()
                Button("Unduh asli") {
                    if let id = model.displayedPreview?.missionID { model.send(.download, missionID: id) }
                }
                .disabled(!model.canOperate || model.displayedPreview == nil || model.editingLocked)
                Button {
                    model.openDatasetFolder(missionID: model.displayedPreview?.missionID)
                } label: {
                    Image(systemName: "folder")
                }.help("Buka folder foto asli")
            }
            DisclosureGroup("Periksa hasil & kesiapan", isExpanded: $reviewExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Detail asli tajam", isOn: $model.review.sharp)
                    Toggle("Exposure baik, highlight tidak terpotong", isOn: $model.review.highlights)
                    Toggle("Fokus sesuai jarak kerja", isOn: $model.review.focus)
                    Toggle("Mount stabil, kamera nadir, lensa bersih", isOn: $model.review.mounted)
                    Toggle("Interval sudah diuji berulang", isOn: $model.review.endurance)
                    Toggle("GCP / checkpoint disiapkan sesuai proyek", isOn: $model.review.controlPoints)
                    Text("Periksa foto asli. Satu foto uji belum membuktikan cadence atau ketahanan suhu.")
                        .font(.caption).foregroundStyle(.secondary)
                }.font(.body).padding(.top, 8).disabled(model.editingLocked || model.sample == nil)
            }.font(.callout)
        }.onChange(of: model.sample?.captureID) { _, id in if id != nil { reviewExpanded = true } }
    }
}
