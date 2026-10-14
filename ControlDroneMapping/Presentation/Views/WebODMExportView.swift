import AppKit
import SwiftUI

struct WebODMExportView: View {
    @StateObject private var model: WebODMExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> WebODMExportViewModel) {
        _model = StateObject(wrappedValue: model())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Siapkan untuk WebODM").font(KropsTypography.pageTitle)
                Spacer()
                Text(model.record.plan.name).foregroundStyle(.secondary)
            }
            Text(
                "Transfer misi sudah mencakup gray card dan foto asli. Ekspor membuat folder terpisah; hanya foto pemetaan yang masuk Images."
            ).font(.callout)
            Picker("Hasil", selection: $model.corrected) {
                Text("Foto asli (tanpa koreksi)").tag(false)
                Text("Koreksi dengan gray card").tag(true)
            }.pickerStyle(.segmented)
                .disabled(model.working)
            if model.corrected {
                if model.references.isEmpty {
                    Text(
                        "Referensi sebelum penerbangan belum tersedia di Mac. Transfer seluruh misi terlebih dahulu."
                    ).foregroundStyle(.orange)
                } else {
                    Picker("Referensi", selection: $model.referenceID) {
                        ForEach(model.references) { photo in
                            Text(
                                photo.capture.requestedAt.formatted(date: .omitted, time: .standard) + " • "
                                    + String(photo.id.uuidString.prefix(8))
                            ).tag(Optional(photo.id))
                        }
                    }.disabled(model.working)
                    if let preview = model.preview {
                        GeometryReader { geometry in
                            let width = min(
                                geometry.size.width,
                                geometry.size.height * CGFloat(preview.width) / CGFloat(preview.height))
                            let height = width * CGFloat(preview.height) / CGFloat(preview.width)
                            ZStack(alignment: .topLeading) {
                                Image(decorative: preview.image, scale: 1).resizable().frame(
                                    width: width, height: height)
                                Rectangle().stroke(.cyan, lineWidth: 2).background(Color.cyan.opacity(0.08))
                                    .frame(
                                        width: width * model.patch.width, height: height * model.patch.height
                                    )
                                    .offset(x: width * model.patch.x, y: height * model.patch.y)
                            }.frame(width: width, height: height)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0).onChanged { value in
                                        guard !model.working else { return }
                                        model.movePatch(
                                            x: Double(value.location.x / width),
                                            y: Double(value.location.y / height))
                                    })
                        }.frame(height: 230)
                    }
                    Text(
                        "Klik/geser kotak ke bagian tengah kartu. Seluruh kotak harus berisi kartu abu-abu polos, tanpa tepi, tulisan, glare, atau bayangan."
                    ).font(.caption).foregroundStyle(.secondary)
                    Toggle(
                        "Kotak berada pada kartu fisik 18% dengan cahaya lapangan yang sama",
                        isOn: $model.confirmed
                    ).disabled(model.working)
                    DisclosureGroup("Koreksi cahaya antar-foto (eksperimental)") {
                        Toggle(
                            "Cocokkan area overlap untuk mengurangi perbedaan exposure", isOn: $model.overlap
                        ).disabled(model.working)
                        Text(
                            "Pasangan tanpa kecocokan kuat tetap memakai koreksi kartu dan diberi catatan. Tidak menghilangkan bayangan, blur, atau highlight yang sudah putih total."
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(
                    "Koreksi kartu memberi acuan awal; bukan jaminan normalisasi seluruh perubahan matahari. Simpan juga ekspor asli untuk membandingkan hasil WebODM."
                ).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.callout) }
            if model.working {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
                Text("Menyiapkan \(model.completed)/\(model.total) foto…").font(.caption)
            }
            if let result = model.result {
                Text(
                    "\(result.count) foto disiapkan. Upload JPEG dan geo.txt (jika tersedia) dari Images. References tidak diupload."
                ).font(.callout)
                ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Button("Tutup") { dismiss() }.disabled(model.working)
                Spacer()
                if model.result != nil { Button("Buka Images") { model.openImages() } }
                Button("Buat folder WebODM") { model.export() }.kropsPrimaryAction(size: .large).tint(
                    KropsStyle.accent
                )
                .disabled(
                    model.working || (model.corrected && (!model.confirmed || model.referenceID == nil)))
            }
        }.padding(24).frame(width: 680)
            .onAppear { model.load() }
            .onChange(of: model.referenceID) { _, _ in model.loadPreview() }
            .onChange(of: model.corrected) { _, _ in model.invalidateResult() }
    }
}
