import AppKit
import SwiftUI

struct CaptureProgressView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    var body: some View {
        ControlPanel("\(model.telemetry.saved) / \(model.monitoringPlan.photoLimit) foto", state: nil) {
            ProgressView(
                value: Double(model.telemetry.saved), total: Double(max(1, model.monitoringPlan.photoLimit))
            ).tint(KropsStyle.accent)
            HStack {
                ControlMetric("Terlewat", "\(model.telemetry.missed)")
                ControlMetric(
                    "Baterai",
                    model.telemetry.battery >= 0
                        ? String(format: "%.0f%%", model.telemetry.battery * 100) : "—")
                ControlMetric("Suhu", model.telemetry.thermal)
                ControlMetric(
                    "Ruang bebas",
                    ByteCountFormatter.string(fromByteCount: model.telemetry.freeBytes, countStyle: .file))
            }.padding(.vertical, 12)
            Text(
                link.connected && model.freshness()
                    ? model.telemetry.message
                    : "Status terakhir. Foto tetap disimpan di iPhone; menunggu reconnect."
            ).font(.callout)
            if !link.connected || !model.freshness(), let date = model.lastReceived {
                Text("Status terakhir diterima " + date.formatted(date: .omitted, time: .standard)).font(
                    .caption
                ).foregroundStyle(.secondary)
            }
        }
    }
}
