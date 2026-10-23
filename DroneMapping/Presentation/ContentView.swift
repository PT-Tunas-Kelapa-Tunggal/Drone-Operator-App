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
                    ZStack {
                        CameraPreview(session: model.previewSession, active: model.isPreviewActive)
                        if !model.isPreviewActive {
                            Color.black.opacity(0.92)
                            VStack(spacing: 10) {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                Text("Mode hemat daya & suhu aktif saat terbang")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Preview layar dijeda agar sensor & CPU tetap dingin selama pemotretan.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Tampilkan preview sementara") {
                                    model.savePowerInFlight = false
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }
                            .padding()
                        }
                    }
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) {
                            Label(model.telemetry.phase.rawValue.uppercased(), systemImage: "record.circle")
                                .font(.caption.bold()).padding(10).background(
                                    .ultraThinMaterial, in: Capsule())
                            if let accuracy = model.telemetry.gpsHorizontalAccuracy {
                                Label(
                                    String(format: "GNSS ±%.0fm", accuracy),
                                    systemImage: accuracy <= 10 ? "location.fill" : "location"
                                )
                                .font(.caption.bold()).padding(10).background(
                                    .ultraThinMaterial, in: Capsule())
                            }
                            if let attitude = model.telemetry.attitude {
                                Label(
                                    String(format: "Nadir %.0f°", attitude.tiltFromNadirDegrees),
                                    systemImage: attitude.isOblique
                                        ? "exclamationmark.triangle.fill" : "level.fill"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(attitude.isOblique ? .orange : .primary)
                                .padding(10).background(.ultraThinMaterial, in: Capsule())
                            }
                        }.padding()
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if model.telemetry.phase == .capturing && !model.savePowerInFlight {
                            Button("Hemat daya preview") {
                                model.savePowerInFlight = true
                            }
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding()
                        }
                    }

                    if model.canPauseLocally || model.canResumeLocally || model.canFinishLocally {
                        GroupBox("Kontrol darurat di iPhone") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Gunakan jika Mac terputus di lapangan untuk menjeda, melanjutkan, atau menutup misi."
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    if model.canPauseLocally {
                                        Button("Jeda misi", systemImage: "pause.circle") {
                                            model.pauseMissionLocally()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if model.canResumeLocally {
                                        Button("Lanjutkan", systemImage: "play.circle") {
                                            model.resumeMissionLocally()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    if model.canFinishLocally {
                                        Button("Selesaikan misi", systemImage: "checkmark.circle") {
                                            model.finishMissionLocally()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Transfer & penyimpanan di iPhone") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(link.transferStatus).font(.caption).foregroundStyle(.secondary)
                            if !link.connected {
                                Text(
                                    "Buka DroneControl di Mac, pilih Hubungkan iPhone di tab Foto, lalu setujui koneksi di sini."
                                )
                                .font(.caption)
                                Button("Cari koneksi Mac lagi") { link.refreshDiscovery() }
                            }
                            ForEach(model.records.filter { $0.saved > 0 }) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.plan.name).font(.headline)
                                    Text("\(record.saved) foto tersimpan • \(record.phase.rawValue)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 12) {
                                        Button("Transfer ke Mac", systemImage: "arrow.up.doc") {
                                            model.transferToMac(record.id)
                                        }
                                        .disabled(!model.canTransfer)
                                        if model.canDeleteDataset(record.id) {
                                            Button(
                                                "Hapus lokal", systemImage: "trash", role: .destructive
                                            ) {
                                                model.deleteDataset(record.id)
                                            }
                                            .font(.caption)
                                        }
                                    }
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
                                LabeledContent(
                                    "Fokus manual", value: String(format: "%.2f", settings.lensPosition))
                                LabeledContent("Format", value: settings.raw ? "RAW + JPEG" : "JPEG (sRGB)")
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
