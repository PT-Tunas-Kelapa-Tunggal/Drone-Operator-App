import SwiftUI

struct HealthPanel: View {
    let telemetry: Telemetry
    var body: some View {
        HStack(spacing: 22) {
            metric("TERSIMPAN", "\(telemetry.saved)", "photo.stack")
            metric("TERLEWAT", "\(telemetry.missed)", "clock.badge.exclamationmark")
            metric(
                "BATERAI", telemetry.battery < 0 ? "—" : "\(Int(telemetry.battery * 100))%",
                "battery.75percent")
            metric("SUHU", telemetry.thermal, "thermometer.medium")
        }.frame(maxWidth: .infinity).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(
                .secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }
}

struct ConnectionBadge: View {
    let connected: Bool
    let destination: String
    var body: some View {
        Label(
            connected ? "Terhubung ke \(destination)" : "\(destination) tidak terhubung",
            systemImage: connected ? "checkmark.circle.fill" : "wifi.slash"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(connected ? Color.green : Color.orange)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background((connected ? Color.green : Color.orange).opacity(0.12), in: Capsule())
        .accessibilityLabel(connected ? "Terhubung ke \(destination)" : "Tidak terhubung ke \(destination)")
    }
}

struct MissionCountdownOverlay: View {
    let remaining: Int?
    var body: some View {
        if let remaining {
            ZStack {
                Color.black.opacity(0.88)
                VStack(spacing: 18) {
                    Text(remaining == 0 ? "MISI DIMULAI" : "BERSIAP MENGAMBIL FOTO")
                        .font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
                    Text(remaining == 0 ? "START" : "\(remaining)")
                        .font(.system(size: remaining == 0 ? 72 : 120, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(remaining == 0 ? .green : .white)
                        .contentTransition(.numericText())
                    Text("Kamera berjalan mandiri di iPhone").font(.subheadline).foregroundStyle(.secondary)
                }.padding()
            }.ignoresSafeArea().allowsHitTesting(false)
                .accessibilityLabel(
                    remaining == 0 ? "Start. Misi dimulai" : "Misi dimulai dalam \(remaining)")
        }
    }
}
