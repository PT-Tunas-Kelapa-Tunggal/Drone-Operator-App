import AppKit
import Foundation
import UniformTypeIdentifiers

enum VariFilePanels {
    static func saveJSON(from sourceURL: URL, suggestedName: String? = nil) {
        let panel = NSSavePanel()
        panel.title = "Simpan Hasil Analisis VARI"
        panel.nameFieldStringValue = suggestedName ?? "vari_result.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Gagal Menyimpan Berkas"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
