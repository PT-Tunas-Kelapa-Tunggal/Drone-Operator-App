import SwiftUI

struct QGCEngineStatusBadge: View {
    @ObservedObject var engineManager = QGCEngineManager.shared
    @State private var showingDetails = false
    var compact = false

    private var statusColor: Color {
        if let drone = engineManager.activeVehicle, drone.communicationLost {
            return .red
        }
        switch engineManager.status {
        case .healthy:
            return .green
        case .starting:
            return .orange
        case .skipped:
            return .secondary
        case .stopped, .failed:
            return .red
        }
    }

    private var badgeText: String {
        if let drone = engineManager.activeVehicle {
            if drone.communicationLost {
                return compact ? "Lost" : "Drone #\(drone.id) · Terputus"
            }
            return compact ? "\(drone.flightMode)" : "Drone #\(drone.id) · \(drone.flightMode)"
        }
        return compact ? "QGC" : "QGC Engine"
    }

    private var statusTooltip: String {
        switch engineManager.status {
        case .healthy(let port, let pid):
            let pidStr = pid.map { " (PID: \($0))" } ?? ""
            let droneStr =
                engineManager.vehicles.isEmpty
                ? " · Tidak ada drone"
                : " · \(engineManager.vehicles.count) drone terhubung"
            return "QGC Engine siap di port \(port)\(pidStr)\(droneStr)"
        case .starting:
            return "Memulai QGC Engine..."
        case .skipped(let reason):
            return "QGC Engine dilewati: \(reason)"
        case .stopped:
            return "QGC Engine berhenti"
        case .failed(let reason):
            return "QGC Engine gagal: \(reason)"
        }
    }

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(badgeText)
                    .font(.caption.weight(.medium))
                if let drone = engineManager.activeVehicle {
                    Text(String(format: "%.0f%%", drone.battery.percent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(KropsStyle.surface, in: Capsule())
            .overlay(Capsule().stroke(KropsStyle.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(statusTooltip)
        .popover(isPresented: $showingDetails) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("QGroundControl Engine")
                    .font(KropsTypography.sectionTitle)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(statusSummary)
                        .fontWeight(.medium)
                }
                .font(.caption)

                HStack {
                    Text("Endpoint:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("127.0.0.1:18080/healthz")
                        .textSelection(.enabled)
                }
                .font(.caption)

                HStack {
                    Text("PID:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let pid = engineManager.pid {
                        Text("\(pid)")
                    } else if case .healthy = engineManager.status {
                        Text("Aktif")
                    } else {
                        Text("-")
                    }
                }
                .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Drone Terhubung:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if engineManager.vehicles.isEmpty {
                    Text("Belum ada drone terhubung (menunggu telemetry di UDP 14550).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engineManager.vehicles) { drone in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle()
                                    .fill(drone.communicationLost ? Color.red : Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Drone #\(drone.id) (\(drone.firmwareType))")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text(drone.communicationLost ? "Terputus" : drone.flightMode)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(drone.communicationLost ? Color.red : KropsStyle.accent)
                            }
                            HStack {
                                Label(
                                    "\(drone.gps.satellites) Sats",
                                    systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                Label(
                                    String(
                                        format: "%.1fV (%.0f%%)", drone.battery.voltage, drone.battery.percent
                                    ), systemImage: "battery.100")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(
                            drone.communicationLost ? Color.red.opacity(0.08) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                }
            }

            if case .skipped(let reason) = engineManager.status {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else if case .failed(let reason) = engineManager.status {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            HStack {
                Spacer()
                Button(engineManager.status == .stopped ? "Mulai Engine" : "Mulai ulang Engine") {
                    engineManager.restartEngine()
                }
                .kropsToolbarAction()
                .disabled(engineManager.status == .starting)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var statusSummary: String {
        switch engineManager.status {
        case .healthy:
            return "Aktif (Sehat)"
        case .starting:
            return "Memulai…"
        case .skipped:
            return "Dilewati (UI Mode)"
        case .stopped:
            return "Berhenti"
        case .failed:
            return "Gagal"
        }
    }
}
