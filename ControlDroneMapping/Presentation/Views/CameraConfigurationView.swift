import AppKit
import SwiftUI

struct CameraConfigurationView: View {
    @ObservedObject var model: ControlViewModel
    var body: some View {
        ControlPanel("Kamera", state: model.settingsApplied ? "Diterapkan" : nil) {
            Toggle("Mode panduan", isOn: Binding(get: { model.guidedMode }, set: { model.setGuidedMode($0) }))
                .font(.callout)
            if model.guidedMode {
                ControlField("Durasi target") { NumberField(durationMinutes, unit: "menit") }
                Picker("Simpan foto", selection: $model.plan.camera.raw) {
                    Text("JPEG • lebih ringan").tag(false)
                    Text("RAW + JPEG • untuk pengolahan warna").tag(true).disabled(
                        model.telemetry.capabilities?.bayerRAW != true)
                }.font(.caption)
                Text(
                    model.plan.exposureCalibration == nil
                        ? "Aplikasi menghitung jeda foto dan batas gerak. Ukur cahaya dengan gray card untuk menentukan exposure."
                        : "Cahaya terukur; exposure dan warna terkunci untuk misi ini."
                )
                .font(.caption).foregroundStyle(.secondary)
                if model.settingsApplied {
                    Button("Siapkan ulang kamera") { model.prepareGuided() }.controlSize(.small).disabled(
                        !model.canOperate
                    )
                    .help("Menghitung ulang pengaturan; referensi dan foto uji perlu diulang.")
                } else {
                    Button("1. Siapkan kamera otomatis") { model.prepareGuided() }.kropsPrimaryAction()
                        .disabled(!model.canOperate)
                }
                Text(
                    String(
                        format: "Setiap %.1f s • target %d foto", model.plan.interval, model.plan.photoLimit)
                ).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Nilai teknis") {
                    cameraControls.disabled(true)
                    Text("Matikan Mode panduan untuk mengubah nilai secara manual.").font(.caption)
                        .foregroundStyle(.secondary)
                }.font(.caption)
                Text(
                    "Exposure tetap selama terbang. Jika cahaya berubah besar, hasil perlu diperiksa dan dikoreksi saat pengolahan."
                ).font(.caption).foregroundStyle(.secondary)
            } else {
                cameraControls
                Button("Terapkan kamera") { model.send(.apply) }.kropsPrimaryAction()
                    .disabled(!model.canOperate)
            }
        }.disabled(model.editingLocked)
    }
    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ControlField("Shutter: 1 / nilai (detik)") {
                    TextField(
                        "1000", value: shutter, format: .number.grouping(.never).precision(.fractionLength(0))
                    ).textFieldStyle(.roundedBorder)
                }.help("1000 berarti 1/1000 detik.")
                ControlField("ISO") {
                    TextField("ISO", value: $model.plan.camera.iso, format: .number).textFieldStyle(
                        .roundedBorder)
                }
                ControlField("Interval") { NumberField($model.plan.interval, unit: "s") }
            }
            HStack {
                ControlField("Jumlah foto") {
                    TextField("Jumlah", value: $model.plan.photoLimit, format: .number).textFieldStyle(
                        .roundedBorder)
                }
                ControlField("Format") {
                    Picker("Format", selection: $model.plan.camera.raw) {
                        Text("JPEG").tag(false)
                        Text("RAW + JPEG").tag(true).disabled(model.telemetry.capabilities?.bayerRAW != true)
                    }.labelsHidden()
                }
            }
            HStack {
                Text("Fokus").font(.caption)
                Slider(value: $model.plan.camera.lensPosition, in: 0...1)
                Text(String(format: "%.2f", model.plan.camera.lensPosition)).font(.caption.monospacedDigit())
            }
            .help("1 = posisi jauh. Pastikan ketajaman pada jarak kerja di foto asli.")
            DisclosureGroup("White balance manual") {
                HStack {
                    ControlField("Kelvin") {
                        TextField("Kelvin", value: temperature, format: .number).textFieldStyle(
                            .roundedBorder)
                    }
                    ControlField("Tint") {
                        TextField("Tint", value: tint, format: .number).textFieldStyle(.roundedBorder)
                    }
                }
            }.font(.caption)
        }
    }
    private var durationMinutes: Binding<Double> {
        Binding(get: { (model.plan.durationSeconds ?? 600) / 60 }, set: { model.setDurationMinutes($0) })
    }
    private var shutter: Binding<Double> {
        Binding(
            get: { model.plan.camera.shutterSeconds > 0 ? 1 / model.plan.camera.shutterSeconds : 0 },
            set: { model.setShutterDenominator($0) })
    }
    private var temperature: Binding<Float> {
        Binding(get: { model.plan.camera.temperature }, set: { model.setTemperature($0) })
    }
    private var tint: Binding<Float> { Binding(get: { model.plan.camera.tint }, set: { model.setTint($0) }) }
}
