import Foundation

public enum BundledQGCEngine {
    public static let healthURL = URL(string: "http://127.0.0.1:18080/healthz")!

    /// Resolves the embedded QGroundControl.app bundle URL.
    public static var embeddedAppURL: URL? {
        // 1. Inside packaged application bundle: Contents/Helpers/QGroundControl.app
        let directHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QGroundControl.app")
        if FileManager.default.fileExists(atPath: directHelper.path) {
            return directHelper
        }

        if let bundleHelper = Bundle.main.url(
            forResource: "QGroundControl",
            withExtension: "app",
            subdirectory: "Contents/Helpers"
        ), FileManager.default.fileExists(atPath: bundleHelper.path) {
            return bundleHelper
        }

        // 2. Local staging fallback location (used during CLI self-tests)
        let localCandidate = URL(fileURLWithPath: ".build/QGroundControl.app")
        if FileManager.default.fileExists(atPath: localCandidate.path) {
            return localCandidate
        }

        return nil
    }

    /// Resolves the executable binary within the QGroundControl.app bundle.
    public static var executableURL: URL? {
        guard let appURL = embeddedAppURL else { return nil }
        let binary = appURL.appendingPathComponent("Contents/MacOS/QGroundControl")
        return FileManager.default.isExecutableFile(atPath: binary.path) ? binary : nil
    }

    /// Performs the self-check used by --check-qgc-engine.
    /// Launches the engine in headless mode, polls the /healthz endpoint until healthy,
    /// then terminates the child process and returns a success message.
    public static func check(timeout: TimeInterval = 10.0) throws -> String {
        guard let executable = executableURL else {
            throw MappingError.invalid("Engine QGroundControl belum tersedia atau belum dapat dieksekusi.")
        }

        let process = Process()
        process.executableURL = executable
        process.environment = [
            "QGC_HEADLESS": "1"
        ]

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                usleep(500_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        let start = Date()
        var healthy = false

        while Date().timeIntervalSince(start) < timeout {
            if !process.isRunning {
                let code = process.terminationStatus
                throw MappingError.invalid("Proses QGroundControl berhenti sebelum siap (exit code \(code)).")
            }

            if let data = try? Data(contentsOf: healthURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                healthy = true
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        guard healthy else {
            throw MappingError.invalid("QGC health check timeout: 127.0.0.1:18080/healthz tidak merespons.")
        }

        return "QGC embedded engine siap (127.0.0.1:18080)."
    }
}
