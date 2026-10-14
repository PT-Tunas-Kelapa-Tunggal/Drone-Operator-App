import SwiftUI

struct DevicesView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    private var active: Bool { model.isActiveMission }
    private var availableMissions: [SavedMission] {
        model.savedMissions().filter { $0.phase != .completed }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !link.connected { ConnectionView(model: model, link: link) }
            ControlPanel("Kamera iPhone", state: link.connected && model.freshness() ? "Terhubung" : nil) {
                Text(link.status).font(KropsTypography.sectionTitle)
                if let c = model.telemetry.capabilities {
                    Text("\(c.model) · \(c.width) × \(c.height)").foregroundStyle(.secondary)
                }
                if link.connected && model.freshness() {
                    HStack {
                        ControlMetric(
                            "Baterai",
                            model.telemetry.battery >= 0
                                ? String(format: "%.0f%%", model.telemetry.battery * 100) : "—")
                        ControlMetric("Suhu", model.telemetry.thermal)
                        ControlMetric(
                            "Ruang bebas",
                            ByteCountFormatter.string(
                                fromByteCount: model.telemetry.freeBytes, countStyle: .file))
                    }
                } else {
                    Text("Menunggu status perangkat terbaru.").foregroundStyle(.secondary)
                }
                Button("Siapkan ulang kamera") { model.send(.prepare) }
                    .disabled(!link.connected || model.editingLocked)
                Text(
                    "Capture berjalan mandiri di iPhone saat koneksi Mac terputus. DroneCam harus tetap terbuka."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if let pending = model.pending {
                ControlPanel("Operasi perangkat", state: nil) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(pending.action.userTitle + "…")
                        Spacer()
                        if model.pendingSince.map({ Date().timeIntervalSince($0) >= 10 }) == true {
                            Button("Minta status") { model.requestPendingStatus() }
                            Button("Tutup penantian") { model.dismissPending() }
                        }
                    }
                }
            }
            ControlPanel("Persiapan capture", state: model.iphoneReadyForCapture ? "Siap" : nil) {
                Text(
                    "Pilih misi yang akan memakai iPhone. Pengaturan kamera dan kalibrasi tetap mengikuti masing-masing misi."
                )
                .font(.callout).foregroundStyle(.secondary)
                Picker(
                    "Misi untuk persiapan",
                    selection: Binding<UUID?>(
                        get: { model.selectedMissionID },
                        set: { if let id = $0 { model.selectMissionForDeviceSetup(id) } })
                ) {
                    Text("Pilih misi").tag(Optional<UUID>.none)
                    ForEach(availableMissions) { mission in
                        Text(mission.plan.name).tag(Optional(mission.id))
                    }
                    if let mission = model.selectedMission, mission.phase == .completed {
                        Text(mission.plan.name + " · selesai").tag(Optional(mission.id))
                    }
                }.disabled(model.pending != nil || link.sending || link.receiving)
                if let mission = model.selectedMission, mission.phase != .completed {
                    HStack {
                        Label(
                            model.iphoneCaptureStatus,
                            systemImage: model.iphoneReadyForCapture
                                ? "checkmark.circle.fill" : "iphone"
                        )
                        .foregroundStyle(model.iphoneReadyForCapture ? Color.green : Color.orange)
                        Spacer()
                        if !model.selectedMissionIsCurrent || model.hasLocalDraft {
                            if model.draftNeedsRetry {
                                Button("Coba siapkan misi") { model.retryDraft() }
                                    .disabled(!model.canOperate || model.editingLocked)
                            } else {
                                Button("Siapkan misi di iPhone") { model.prepareSelectedMission() }
                                    .kropsPrimaryAction().disabled(
                                        !model.canOperate || model.editingLocked
                                            || model.missionStorageError != nil)
                            }
                        }
                    }
                    if model.selectedMissionIsCurrent && !model.hasLocalDraft {
                        Text(
                            active
                                ? "Capture sedang berlangsung; pengaturan perangkat dikunci."
                                : model.operatorStage.title
                        ).font(.caption).foregroundStyle(.secondary)
                        if !active && !model.guidedMode {
                            Button("Isi rekomendasi kamera dari survei") { model.recommend() }
                                .disabled(model.editingLocked || model.estimate == nil)
                        }
                    } else {
                        Text(
                            mission.preparationRequested
                                ? "Menunggu misi diterima iPhone."
                                : "Hubungkan iPhone, lalu siapkan misi yang dipilih."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        availableMissions.isEmpty
                            ? "Buat misi dan atur area serta rencana survei di panel Misi terlebih dahulu."
                            : "Pilih misi untuk menyiapkan kamera dan kalibrasi."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            if model.selectedMission != nil, model.selectedMission?.phase != .completed,
                model.selectedMissionIsCurrent, !model.hasLocalDraft
            {
                HStack(alignment: .top, spacing: 16) {
                    CameraConfigurationView(model: model).frame(width: 410)
                    PhotoQualityView(model: model).frame(maxWidth: .infinity)
                }
            }
            ControlPanel("Drone & penerbangan", state: nil) {
                Text("Setup, koneksi, dan kontrol penerbangan drone tersedia melalui QGroundControl.")
                    .foregroundStyle(.secondary)
                Button("Buka QGroundControl") { model.openQGroundControl() }.kropsPrimaryAction()
            }
        }
    }
}
