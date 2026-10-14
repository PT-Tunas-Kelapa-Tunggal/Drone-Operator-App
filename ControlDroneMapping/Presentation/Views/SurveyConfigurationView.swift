import AppKit
import SwiftUI

struct SurveyConfigurationView: View {
    @ObservedObject var model: ControlViewModel
    var body: some View {
        ControlPanel("Survei", state: model.geometry.reviewed ? "Ditinjau" : nil) {
            HStack(spacing: 12) {
                ControlField("Tinggi terbang") { NumberField($model.geometry.heightAGL, unit: "m") }
                    .help("Tinggi kamera di atas tanah (AGL), bukan altitude GPS.")
                ControlField("Kecepatan") { NumberField($model.geometry.speed, unit: "m/s") }
            }
            DisclosureGroup("Pengaturan lanjutan") {
                VStack(alignment: .leading, spacing: 12) {
                    ControlField("Target detail tanah (GSD)") {
                        NumberField($model.geometry.targetGSDcm, unit: "cm/px")
                    }
                    .help(
                        "Ukuran tanah yang diwakili satu pixel. Nilai lebih kecil berarti target detail lebih tinggi, bukan jaminan akurasi koordinat."
                    )
                    HStack(spacing: 12) {
                        ControlField("Overlap depan") {
                            NumberField(percent($model.geometry.forwardOverlap), unit: "%")
                        }
                        ControlField("Overlap samping") {
                            NumberField(percent($model.geometry.sideOverlap), unit: "%")
                        }
                    }
                    ControlField("Focal length terkalibrasi") {
                        NumberField($model.geometry.calibratedFocalPixels, unit: "px")
                    }
                    Text("Isi 0 untuk memakai estimasi kamera. Overlap harus sesuai jalur penerbangan.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let e = model.estimate {
                        Text(
                            String(
                                format: "GSD ≈ %.2f cm/px   •   Antarjalur %.1f m", e.gsd * 100, e.sideSpacing
                            )
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .help(
                            "Estimasi nadir, tanah datar dan sisi pendek foto searah terbang. FOV format aktif belum menggantikan kalibrasi geometrik foto."
                        )
                    }
                }.padding(.top, 8)
            }.font(.caption)
            HStack {
                Toggle("Rencana terbang sudah diperiksa", isOn: $model.geometry.reviewed).font(.body)
                Spacer()
            }
        }.disabled(model.editingLocked)
    }
    private func percent(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 })
    }
}
