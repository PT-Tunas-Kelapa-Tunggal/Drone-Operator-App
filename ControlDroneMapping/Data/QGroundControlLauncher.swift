import AppKit
import UniformTypeIdentifiers

enum QGroundControlLauncher {
    static var installedURL: URL? {
        if let embedded = BundledQGCEngine.embeddedAppURL { return embedded }
        let path = UserDefaults.standard.string(forKey: "qgcAppPath") ?? ""
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        let candidates = [
            "/Applications/QGroundControl.app", NSHomeDirectory() + "/Applications/QGroundControl.app",
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }).map {
            URL(fileURLWithPath: $0)
        }
    }
    static func open(error: @escaping (String) -> Void) {
        var url = installedURL
        if url == nil {
            let panel = NSOpenPanel()
            panel.title = "Pilih aplikasi QGroundControl"
            panel.allowedContentTypes = [.applicationBundle]
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            guard selected.lastPathComponent.localizedCaseInsensitiveContains("qgroundcontrol") else {
                error("Pilih aplikasi QGroundControl yang terpasang.")
                return
            }
            UserDefaults.standard.set(selected.path, forKey: "qgcAppPath")
            url = selected
        }
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
            _, failure in
            if let failure { DispatchQueue.main.async { error(failure.localizedDescription) } }
        }
    }
}
