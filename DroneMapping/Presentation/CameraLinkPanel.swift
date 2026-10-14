import SwiftUI

struct CameraLinkPanel: View {
    @ObservedObject var link: LocalLink
    let telemetry: Telemetry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConnectionBadge(connected: link.connected, destination: "Mac")
            Text(link.status).font(.caption).foregroundStyle(.secondary)
            if !link.connected && [.capturing, .countdown].contains(telemetry.phase) {
                Label("Misi tetap berjalan • foto disimpan di iPhone", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
            if link.sending { Text(link.transferStatus).font(.caption) }
        }.alert(
            "Hubungkan ground station?",
            isPresented: Binding(
                get: { link.invitationName != nil }, set: { if !$0 { link.answerInvitation(false) } })
        ) {
            Button("Tolak", role: .cancel) { link.answerInvitation(false) }
            Button("Hubungkan") { link.answerInvitation(true) }
        } message: {
            Text(
                "\(link.invitationName ?? "Mac") meminta akses kontrol kamera. Setujui hanya perangkat operator."
            )
        }
    }
}
