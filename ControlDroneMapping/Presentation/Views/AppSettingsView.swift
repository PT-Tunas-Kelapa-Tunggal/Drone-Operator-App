import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject private var qgcEngine = QGCEngineManager.shared
    @AppStorage("dashboardAppearance") private var appearance = "light"
    @AppStorage(VariTimingWeatherSettings.noDailyKey) private var timingSkipDaily = false
    @AppStorage(VariTimingWeatherSettings.teamIDKey) private var weatherKitTeamID = ""
    @AppStorage(VariTimingWeatherSettings.keyIDKey) private var weatherKitKeyID = ""
    @AppStorage(VariTimingWeatherSettings.serviceIDKey) private var weatherKitServiceID = ""
    @AppStorage(VariTimingWeatherSettings.importedKeyNameKey) private var weatherKitKeyFileName = ""
    @State private var weatherKitHasKeyFile = VariTimingWeatherSettings.hasImportedKeyFile()
    @State private var weatherKitError: String?

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

                Button(
                    qgcEngine.status == .stopped ? "Mulai Companion Engine" : "Mulai ulang Companion Engine"
                ) {
                    qgcEngine.restartEngine()
                }
                .disabled(qgcEngine.status == .starting)
            }
            Section("Kamera dan kalibrasi") {
                Text("Tinggi, kecepatan, exposure, gray card, dan foto uji diatur pada halaman Misi.")
                Button("Buka pengaturan misi") { model.step = .mission }
            }
            timingWeatherSection
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

    private var timingWeatherSection: some View {
        let trimmedTeam = weatherKitTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = weatherKitKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedService = weatherKitServiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyWeatherKit =
            !trimmedTeam.isEmpty || !trimmedKey.isEmpty || !trimmedService.isEmpty
            || weatherKitHasKeyFile
        let isWeatherKitComplete =
            !trimmedTeam.isEmpty && !trimmedKey.isEmpty && !trimmedService.isEmpty
            && weatherKitHasKeyFile

        return Section("Jadwal Pemupukan & Cuaca") {
            Toggle("Lewati prakiraan harian (--no-daily)", isOn: $timingSkipDaily)
            Text(
                "Jika aktif, engine hanya memakai basis iklim bulanan NASA POWER (tanpa prakiraan 10 hari dan P30 harian)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            TextField("WeatherKit Team ID (WK_TEAM_ID)", text: $weatherKitTeamID)
            TextField("WeatherKit Key ID (WK_KEY_ID)", text: $weatherKitKeyID)
            TextField("WeatherKit Service ID (WK_SERVICE_ID)", text: $weatherKitServiceID)

            LabeledContent("Kunci Privat (.p8)") {
                HStack(spacing: 8) {
                    if weatherKitHasKeyFile {
                        Text(weatherKitKeyFileName.isEmpty ? "AuthKey.p8" : weatherKitKeyFileName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("Ganti…") { pickWeatherKitKeyFile() }
                        Button("Hapus") { clearWeatherKitKeyFile() }
                    } else {
                        Text("Belum dipilih")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Pilih Berkas .p8…") { pickWeatherKitKeyFile() }
                    }
                }
            }

            if let weatherKitError {
                Text(weatherKitError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isWeatherKitComplete {
                Label("Kredensial WeatherKit lengkap dan siap dipakai.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if hasAnyWeatherKit {
                Label(
                    "Lengkapi Team ID, Key ID, Service ID, dan berkas .p8 untuk mengaktifkan WeatherKit.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text(
                    "Opsional. Jika kosong, engine tetap memakai basis iklim & curah hujan 30-hari NASA POWER."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            weatherKitHasKeyFile = VariTimingWeatherSettings.hasImportedKeyFile()
        }
    }

    private func pickWeatherKitKeyFile() {
        weatherKitError = nil
        let panel = NSOpenPanel()
        panel.title = "Pilih Kunci Privat WeatherKit (.p8)"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let p8Type = UTType(filenameExtension: "p8") {
            panel.allowedContentTypes = [p8Type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try VariTimingWeatherSettings.importWeatherKitKey(from: url)
            weatherKitKeyFileName = name
            weatherKitHasKeyFile = true
        } catch {
            weatherKitError = error.localizedDescription
        }
    }

    private func clearWeatherKitKeyFile() {
        weatherKitError = nil
        do {
            try VariTimingWeatherSettings.removeWeatherKitKey()
            weatherKitHasKeyFile = false
        } catch {
            weatherKitError = error.localizedDescription
        }
    }
}
