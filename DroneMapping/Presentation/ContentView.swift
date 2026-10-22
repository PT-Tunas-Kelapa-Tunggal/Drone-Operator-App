import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CameraViewModel
    @ObservedObject var link: LocalLink
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CameraLinkPanel(link: link, telemetry: model.telemetry)
                    CameraPreview(session: model.previewSession)
                        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .topLeading) {
                            Label(model.telemetry.phase.rawValue.uppercased(), systemImage: "record.circle")
                                .font(.caption.bold()).padding(10).background(
                                    .ultraThinMaterial, in: Capsule()
                                ).padding()
                        }
                    GroupBox("Transfer foto ke Mac") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(link.transferStatus).font(.caption).foregroundStyle(.secondary)
                            if !link.connected {
                                Text("Buka DroneControl di Mac, pilih Hubungkan iPhone di tab Foto, lalu setujui koneksi di sini.")
                                    .font(.caption)
                                Button("Cari koneksi Mac lagi") { link.refreshDiscovery() }
                            }
                            ForEach(model.records.filter { $0.saved > 0 }) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.plan.name).font(.headline)
                                    Text("\(record.saved) foto tersimpan").font(.caption)
                                    Button("Transfer ke Mac", systemImage: "arrow.up.doc") {
                                        model.transferToMac(record.id)
                                    }
                                    .disabled(!model.canTransfer)
                                }
                            }
                            if !model.records.contains(where: { $0.saved > 0 }) {
                                Text("Foto capture yang tersimpan akan muncul di sini.").font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HealthPanel(telemetry: model.telemetry)
                    Text(model.plan.name).font(.title2.bold())
                    Text(model.telemetry.message).font(.subheadline)
                    Text(model.message).font(.caption).foregroundStyle(.secondary)
                    GroupBox("Konfigurasi dari Mac") {
                        VStack(spacing: 12) {
                            LabeledContent(
                                "Interval", value: String(format: "%.1f detik", model.plan.interval))
                            LabeledContent("Target", value: "\(model.plan.photoLimit) foto")
                            if let settings = model.telemetry.settings {
                                LabeledContent("ISO", value: String(format: "%.0f", settings.iso))
                                LabeledContent(
                                    "Shutter", value: String(format: "%.5f s", settings.shutterSeconds))
                                LabeledContent(
                                    "White balance", value: String(format: "%.0f K", settings.temperature))
                                LabeledContent("Format", value: settings.raw ? "RAW + JPEG" : "JPEG")
                            } else {
                                Text("Menunggu pengaturan kamera dari Mac").foregroundStyle(.secondary)
                            }
                        }.font(.subheadline).padding(.vertical, 8)
                    }
                    Text(
                        "Seluruh kontrol kamera dan misi tersedia di Mac. iPhone menampilkan informasi dan menyimpan foto secara mandiri."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(
                        "Biarkan DroneCam terbuka. Putus koneksi tidak menghentikan misi; mengunci layar atau keluar aplikasi akan menjeda kamera."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("DroneCam")
        }
        .overlay { MissionCountdownOverlay(remaining: model.telemetry.countdownRemaining) }
        .task { model.prepare() }
        .onChange(of: scenePhase) { _, phase in
            model.scene(phase)
            if phase == .active && !link.connected { link.refreshDiscovery() }
        }
        .onChange(of: link.sending) { _, _ in model.updateIdleTimer() }
    }
}
