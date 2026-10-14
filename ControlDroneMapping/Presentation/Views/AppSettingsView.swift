import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: ControlViewModel
    @AppStorage("dashboardAppearance") private var appearance = "light"
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
            }
            Section("Kamera dan kalibrasi") {
                Text("Tinggi, kecepatan, exposure, gray card, dan foto uji diatur pada halaman Misi.")
                Button("Buka pengaturan misi") { model.step = .mission }
            }
        }.formStyle(.grouped).frame(maxWidth: 760)
    }
}
