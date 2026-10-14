import SwiftUI

struct DeviceStatusPopover: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    private var active: Bool { model.isActiveMission }
    private var phaseTitle: String { model.phaseTitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(link.status).font(KropsTypography.sectionTitle)
            if let c = model.telemetry.capabilities {
                Text("\(c.model) • \(c.width) × \(c.height)")
                Text(c.bayerRAW ? "Bayer RAW tersedia" : "JPEG tersedia")
            }
            Text(model.freshness() && link.connected ? phaseTitle : "Status terakhir • menunggu sinkronisasi")
                .foregroundStyle(.secondary)
            if let date = model.lastReceived {
                Text("Diperbarui \(date.formatted(date: .omitted, time: .standard))").font(.caption)
            }
            Text("Capture tetap berjalan saat disconnect. iPhone harus tetap membuka DroneCam.").font(
                .caption
            ).foregroundStyle(.secondary)
        }.padding(20).frame(width: 320)
    }
}
