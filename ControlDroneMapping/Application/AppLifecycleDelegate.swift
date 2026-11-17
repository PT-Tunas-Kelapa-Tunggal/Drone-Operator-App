import AppKit
import Foundation

/// AppKit lifecycle bridge for confirming termination when a long-running VARI job is active
/// and ensuring background subprocesses and companion daemons stop cleanly on exit.
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private weak var variAnalysis: VariAnalysisViewModel?

    func configure(variAnalysis: VariAnalysisViewModel) {
        self.variAnalysis = variAnalysis
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let variAnalysis, let activeRun = variAnalysis.activeRun else {
                variAnalysis?.cancelAllForTermination()
                return .terminateNow
            }

            sender.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Analisis VARI & HARA sedang berjalan"
            if activeRun.hasExistingCachedResult {
                alert.informativeText =
                    "Analisis untuk \"\(activeRun.missionName)\" sedang berlangsung (\(activeRun.stage.title.lowercased())). Jika keluar sekarang, proses ini akan dihentikan, sedangkan hasil analisis sebelumnya tetap tersimpan."
            } else {
                alert.informativeText =
                    "Analisis untuk \"\(activeRun.missionName)\" sedang berlangsung (\(activeRun.stage.title.lowercased())). Jika keluar sekarang, proses ini akan dihentikan sebelum selesai."
            }

            let keepRunningButton = alert.addButton(withTitle: "Tetap Jalankan")
            _ = keepRunningButton

            let stopAndQuitButton = alert.addButton(withTitle: "Hentikan & Keluar")
            stopAndQuitButton.hasDestructiveAction = true
            stopAndQuitButton.keyEquivalent = ""

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                variAnalysis.cancelAllForTermination()
                QGCEngineManager.shared.stopEngine()
                return .terminateNow
            }
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            variAnalysis?.cancelAllForTermination()
            QGCEngineManager.shared.stopEngine()
        }
    }
}
