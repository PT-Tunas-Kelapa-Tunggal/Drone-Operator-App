import AppKit
import Foundation
import UniformTypeIdentifiers

enum VariFilePanels {
    static func saveJSON(from sourceURL: URL, suggestedName: String? = nil) {
        saveFile(from: sourceURL, suggestedName: suggestedName ?? "vari_result.json", contentTypes: [.json])
    }

    static func saveCSV(from sourceURL: URL, suggestedName: String? = nil) {
        saveFile(from: sourceURL, suggestedName: suggestedName ?? "vari_summary.csv", contentTypes: [.commaSeparatedText])
    }

    static func saveFile(
        from sourceURL: URL,
        suggestedName: String,
        contentTypes: [UTType]
    ) {
        let panel = NSSavePanel()
        panel.title = "Simpan Berkas Analisis"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = contentTypes
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
