import Foundation

/// Persists optional Fertilization Timing execution preferences (`--no-daily` and WeatherKit credentials)
/// and provides a safe App Sandbox copy location for the user-selected `.p8` key file.
public enum VariTimingWeatherSettings {
    public static let noDailyKey = "krops.timing.noDaily"
    public static let teamIDKey = "krops.timing.weatherKit.teamID"
    public static let keyIDKey = "krops.timing.weatherKit.keyID"
    public static let serviceIDKey = "krops.timing.weatherKit.serviceID"
    public static let importedKeyNameKey = "krops.timing.weatherKit.keyFileName"

    public static var appSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl", isDirectory: true)
    }

    /// Writable `--cache-dir` inside Application Support so NASA POWER & WeatherKit can write inside App Sandbox.
    public static func writableWeatherCacheDirectory(demo: Bool = false) -> URL {
        appSupportRoot.appendingPathComponent(demo ? "DemoWeatherCache" : "WeatherCache", isDirectory: true)
    }

    /// Persistent output fallback when a mission has no Orthomosaic output folder yet.
    public static func defaultTimingOutputFolder(for missionID: UUID, demo: Bool = false) -> URL {
        appSupportRoot
            .appendingPathComponent(demo ? "DemoTimingResults" : "TimingResults", isDirectory: true)
            .appendingPathComponent(missionID.uuidString, isDirectory: true)
    }

    public static var managedWeatherKitKeyURL: URL {
        appSupportRoot
            .appendingPathComponent("WeatherKit", isDirectory: true)
            .appendingPathComponent("AuthKey.p8")
    }

    public static func hasImportedKeyFile() -> Bool {
        FileManager.default.fileExists(atPath: managedWeatherKitKeyURL.path)
    }

    /// Copies the picked `.p8` key into the app's private Application Support directory (`0600`)
    /// so the inherited `VariPython` subprocess can read it under App Sandbox across restarts.
    @discardableResult
    public static func importWeatherKitKey(from sourceURL: URL) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let fm = FileManager.default
        let dir = managedWeatherKitKeyURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: managedWeatherKitKeyURL.path) {
            try fm.removeItem(at: managedWeatherKitKeyURL)
        }
        try fm.copyItem(at: sourceURL, to: managedWeatherKitKeyURL)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: managedWeatherKitKeyURL.path)
        let originalName = sourceURL.lastPathComponent
        UserDefaults.standard.set(originalName, forKey: importedKeyNameKey)
        return originalName
    }

    public static func removeWeatherKitKey() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: managedWeatherKitKeyURL.path) {
            try fm.removeItem(at: managedWeatherKitKeyURL)
        }
        UserDefaults.standard.removeObject(forKey: importedKeyNameKey)
    }

    /// Builds an immutable `VariTimingRunOptions` snapshot from current `UserDefaults` & managed `.p8`.
    public static func currentRunOptions() -> VariTimingRunOptions {
        let defaults = UserDefaults.standard
        let skipDaily = defaults.bool(forKey: noDailyKey)
        let teamID =
            defaults.string(forKey: teamIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyID =
            defaults.string(forKey: keyIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serviceID =
            defaults.string(forKey: serviceIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let credentials: WeatherKitCredentials?
        if !teamID.isEmpty, !keyID.isEmpty, !serviceID.isEmpty, hasImportedKeyFile() {
            credentials = WeatherKitCredentials(
                teamID: teamID,
                keyID: keyID,
                serviceID: serviceID,
                keyFileURL: managedWeatherKitKeyURL
            )
        } else {
            credentials = nil
        }

        return VariTimingRunOptions(
            skipDaily: skipDaily,
            todayOverride: nil,
            yearOverride: nil,
            weatherKit: credentials
        )
    }
}
