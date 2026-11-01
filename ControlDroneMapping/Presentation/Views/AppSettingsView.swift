import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject private var qgcEngine = QGCEngineManager.shared
    @AppStorage("dashboardAppearance") private var appearance = "light"

    private var qgcStatusColor: Color {
        switch qgcEngine.status {
        case .healthy: return .green
        case .starting: return .orange
        case .skipped: return .secondary
        case .stopped, .failed: return .red
        }
    }

    private var qgcStatusText: String {
        switch qgcEngine.status {
        case .healthy(let port, _): return "Aktif (Port \(port))"
        case .starting: return "Memulai…"
        case .skipped: return "Dilewati (UI Mode)"
        case .stopped: return "Berhenti"
        case .failed: return "Gagal"
        }
    }

    var body: some View {
        Form {
            Section("Tampilan") {
                Picker("Tema", selection: $appearance) {
                    Text("Terang").tag("light")
                    Text("Gelap").tag("dark")
                    Text("Ikuti sistem").tag("system")
                }
            }
            Section("Penyimpanan Mac") {
                Text(model.link.store.root.path).textSelection(.enabled).font(.caption)
                Button("Buka folder dataset") {
                    model.openDatasetFolder()
                }
                Text("Foto asli dan hasil ekspor disimpan per misi.").font(.caption).foregroundStyle(
                    .secondary)
            }
            Section("QGroundControl") {
                Text(QGroundControlLauncher.installedURL?.path ?? "Aplikasi belum dipilih").font(.caption)
                    .textSelection(.enabled)
                Button("Buka / pilih QGroundControl") { model.openQGroundControl() }
                Text("Kontrol penerbangan tetap dilakukan melalui aplikasi QGroundControl.").font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Circle()
                        .fill(qgcStatusColor)
                        .frame(width: 8, height: 8)
                    Text("Companion Engine: \(qgcStatusText)")
                    Spacer()
                    if let pid = qgcEngine.pid {
                        Text("PID: \(pid)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if case .failed(let reason) = qgcEngine.status {
                    Text(reason).font(.caption).foregroundStyle(.red)
                }

                Button(qgcEngine.status == .stopped ? "Mulai Companion Engine" : "Mulai ulang Companion Engine") {
                    qgcEngine.restartEngine()
                }
                .disabled(qgcEngine.status == .starting)
            }
            Section("Kamera dan kalibrasi") {
                Text("Tinggi, kecepatan, exposure, gray card, dan foto uji diatur pada halaman Misi.")
                Button("Buka pengaturan misi") { model.step = .mission }
            }
            Section("Informasi Build & CloudKit") {
                LabeledContent("Versi") {
                    Text("\(AppConfiguration.current.shortVersion) (\(AppConfiguration.current.buildNumber))")
                        .font(.caption.monospaced())
                }
                LabeledContent("Lingkungan") {
                    Text(AppConfiguration.current.environment.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppConfiguration.current.isProduction ? .green : .orange)
                }
                LabeledContent("CloudKit Container") {
                    Text(AppConfiguration.current.cloudKitContainerIdentifier)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }.formStyle(.grouped).frame(maxWidth: 760)
    }
}
