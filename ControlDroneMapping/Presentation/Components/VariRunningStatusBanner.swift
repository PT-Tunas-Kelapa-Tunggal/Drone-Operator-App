import AppKit
import SwiftUI

/// Detailed in-workspace card rendered inside the `VARI & HARA` result layer while the active job runs.
struct VariActiveWorkspaceCard: View {
    let activeRun: ActiveVariRun
    let onOpenLog: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasLogFile: Bool {
        FileManager.default.fileExists(atPath: activeRun.logURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                stageIndicator

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        activeRun.isStopping
                            ? "Menghentikan analisis VARI & HARA…"
                            : activeRun.stage.title
                    )
                    .font(.headline)

                    Text(stageSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Label {
                        Text(VariElapsedFormatter.string(since: activeRun.startedAt, now: context.date))
                            .font(.callout.monospacedDigit().weight(.medium))
                    } icon: {
                        Image(systemName: "clock")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KropsStyle.canvas, in: Capsule())
                    .overlay(Capsule().stroke(KropsStyle.border))
                    .accessibilityLabel(
                        "Durasi pemrosesan \(VariElapsedFormatter.string(since: activeRun.startedAt, now: context.date))"
                    )
                }
            }

            Divider()

            HStack(spacing: 12) {
                Label {
                    Text(reassuranceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(
                        systemName: activeRun.hasExistingCachedResult
                            ? "checkmark.shield" : "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(activeRun.hasExistingCachedResult ? .green : KropsStyle.accent)
                }

                Spacer(minLength: 12)

                Button("Buka log", systemImage: "doc.text.magnifyingglass", action: onOpenLog)
                    .kropsToolbarAction(size: .regular)
                    .disabled(!hasLogFile)
                    .help(
                        hasLogFile
                            ? "Buka file log vari_processing.log di Finder atau TextEdit"
                            : "Log proses dibuat setelah tahap mesin Python dimulai"
                    )

                Button(
                    activeRun.isStopping ? "Menghentikan…" : "Hentikan",
                    systemImage: "stop.circle",
                    role: .destructive,
                    action: onCancel
                )
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
                .disabled(activeRun.isStopping)
            }
        }
        .padding(20)
        .frame(maxWidth: 680, alignment: .leading)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
    }

    @ViewBuilder
    private var stageIndicator: some View {
        if reduceMotion {
            Image(systemName: activeRun.isStopping ? "stop.circle" : "hourglass")
                .font(.title3)
                .foregroundStyle(activeRun.isStopping ? .orange : KropsStyle.accent)
                .frame(width: 22, height: 22)
        } else {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 22, height: 22)
        }
    }

    private var stageSubtitle: String {
        if activeRun.isStopping {
            return "Mengirim sinyal berhenti ke proses latar belakang dan membersihkan staging sementara."
        }
        switch activeRun.stage {
        case .validatingEngine:
            return "Memastikan runtime VariEngine dan dependensi Python siap digunakan."
        case .convertingImage:
            return "Mengonversi orthomosaic TIFF resolusi besar per pita memori agar tidak membebani RAM."
        case .copyingImage:
            return "Menyiapkan salinan citra masukan sebelum analisis dimulai."
        case .runningEngine:
            return
                "Menghitung indeks VARI, deteksi pohon sawit, dan rekomendasi HARA di latar belakang. Anda bebas berpindah misi atau layar."
        case .parsingResults:
            return "Memvalidasi dan memuat peta hasil analisis ke ruang kerja."
        }
    }

    private var reassuranceText: String {
        if activeRun.hasExistingCachedResult {
            return "Hasil analisis sebelumnya tetap tersimpan aman jika proses ini dihentikan."
        }
        return
            "Pemrosesan kebun besar dapat berlangsung beberapa menit dan tetap berjalan saat Anda membuka menu lain."
    }
}

/// Non-blocking global activity / completion strip docked above workspace content when navigating elsewhere.
struct VariGlobalActivityStrip: View {
    @ObservedObject var variAnalysis: VariAnalysisViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let activeRun = variAnalysis.activeRun, !variAnalysis.isShowingActiveVariLayer(activeRun) {
            runningStrip(activeRun)
        } else if let notice = variAnalysis.completionNotice {
            completionStrip(notice)
        }
    }

    private func runningStrip(_ run: ActiveVariRun) -> some View {
        HStack(spacing: 12) {
            if reduceMotion {
                Image(systemName: run.isStopping ? "stop.circle" : "hourglass")
                    .font(.callout)
                    .foregroundStyle(run.isStopping ? .orange : KropsStyle.accent)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text("VARI & HARA · \(run.missionName)")
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.secondary)

            Text(run.isStopping ? "Menghentikan…" : run.stage.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                Text(VariElapsedFormatter.string(since: run.startedAt, now: context.date))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Lihat") {
                variAnalysis.requestNavigationToActiveRun()
            }
            .kropsToolbarAction(size: .regular)

            Button(run.isStopping ? "Menghentikan…" : "Hentikan", role: .destructive) {
                variAnalysis.cancelVari()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.regular)
            .disabled(run.isStopping)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(KropsStyle.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KropsStyle.border).frame(height: 1)
        }
    }

    private func completionStrip(_ notice: VariCompletionNotice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notice.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(notice.isFailure ? .orange : .green)

            Text(notice.message)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(notice.isFailure ? "Lihat detail" : "Buka hasil") {
                variAnalysis.requestNavigation(to: notice)
            }
            .kropsToolbarAction(size: .regular)

            Button {
                variAnalysis.dismissCompletionNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Tutup pemberitahuan VARI")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(notice.isFailure ? Color.orange.opacity(0.08) : KropsStyle.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KropsStyle.border).frame(height: 1)
        }
    }
}

private enum VariElapsedFormatter {
    static func string(since startedAt: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
