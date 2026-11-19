import MultipeerConnectivity
import SwiftUI

struct ConnectionView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    var body: some View {
        HStack(spacing: 14) {
            Label(
                !model.isDemo && !link.isEnabled ? "Koneksi iPhone dinonaktifkan" : "Buka DroneCam di iPhone",
                systemImage: "iphone"
            ).font(.callout.weight(.medium))
            Spacer()
            if model.isDemo {
                Button("Hubungkan demo") { model.connectDemo() }
            } else if !link.isEnabled {
                Button("Buka Pengaturan") { model.step = .settings }
            } else if link.peers.isEmpty {
                Text("Mencari perangkat…").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(link.peers, id: \.self) { peer in
                Button("Hubungkan \(peer.displayName)") { link.connect(peer) }
                    .disabled(!link.isEnabled)
            }
            if !model.isDemo && !link.connected {
                Button("Cari ulang") { link.refreshDiscovery() }
                    .disabled(!link.isEnabled)
            }
        }.padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
