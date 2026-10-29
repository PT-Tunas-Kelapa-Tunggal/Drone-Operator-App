import SwiftUI

struct QGCEngineStatusBadge: View {
    @ObservedObject var engineManager = QGCEngineManager.shared
    @State private var showingDetails = false
    var compact = false

    private var statusColor: Color {
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

    private var statusTooltip: String {
        switch engineManager.status {
        case .healthy(let port, let pid):
            let pidStr = pid.map { " (PID: \($0))" } ?? ""
            return "QGC Engine siap di port \(port)\(pidStr)"
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
                Text(compact ? "QGC" : "QGC Engine")
                    .font(.caption.weight(.medium))
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
