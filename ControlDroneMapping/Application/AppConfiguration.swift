import Foundation

/// Centralized, typed runtime configuration for ControlDroneMapping.
///
/// Validates that all required build-time settings were supplied via `Config/Developer.xcconfig`
/// without any silent fallback defaults.
public struct AppConfiguration: Sendable {
    /// CloudKit container + environment tuple used to partition local cached missions and artifacts.
    public struct StorageScope: Hashable, Codable, Sendable {
        public let cloudKitContainerIdentifier: String
        public let environment: String

        public init(cloudKitContainerIdentifier: String, environment: String) {
            self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
            self.environment = environment.lowercased()
        }

        public static func sanitizedPathComponent(_ raw: String) -> String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
            let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
            return cleaned.isEmpty ? "default" : cleaned
        }

        public func directory(under base: URL) -> URL {
            base
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent(Self.sanitizedPathComponent(cloudKitContainerIdentifier), isDirectory: true)
                .appendingPathComponent(Self.sanitizedPathComponent(environment), isDirectory: true)
        }
    }

    public enum BuildEnvironment: String, Sendable {
        case development
        case staging
        case production

        public var displayName: String {
            switch self {
            case .development: return "Development (Lokal)"
            case .staging: return "Staging / Pre-Release"
            case .production: return "Production"
            }
        }

        public var windowBadge: String? {
            switch self {
            case .development: return "DEV"
            case .staging: return "STAGING"
            case .production: return nil
            }
        }
    }

    public let bundleIdentifier: String
    public let cloudKitContainerIdentifier: String
    public let environment: BuildEnvironment
    public let shortVersion: String
    public let buildNumber: String
    public let orthomosaicHelperIdentifier: String
    public let variHelperIdentifier: String

    public var isProduction: Bool {
        environment == .production
    }

    public var storageScope: StorageScope {
        StorageScope(
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            environment: environment.rawValue
        )
    }

    /// Reads the configured CloudKit container & environment from `Bundle.main` when available.
    /// Returns `nil` inside headless test binaries that do not embed an app `Info.plist`.
    public static var bundleStorageScope: StorageScope? {
        guard
            let containerID = (Bundle.main.object(forInfoDictionaryKey: "ICloudContainerIdentifier") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !containerID.isEmpty,
            !containerID.contains("$("),
            let rawEnv = (Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawEnv.isEmpty,
            !rawEnv.contains("$("),
            let env = BuildEnvironment(rawValue: rawEnv.lowercased())
        else {
            return nil
        }
        return StorageScope(
            cloudKitContainerIdentifier: containerID,
            environment: env.rawValue
        )
    }

    public static let current: AppConfiguration = {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            fatalError("AppConfiguration Error: Bundle.main.bundleIdentifier is missing or empty.")
        }

        guard
            let containerID = Bundle.main.object(forInfoDictionaryKey: "ICloudContainerIdentifier")
                as? String,
            !containerID.isEmpty,
            !containerID.contains("$(")
        else {
            fatalError(
                "AppConfiguration Error: ICloudContainerIdentifier is not properly configured in Info.plist. "
                    + "Ensure Config/Developer.xcconfig defines a valid ICLOUD_CONTAINER_NAME."
            )
        }

        guard let rawEnv = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String,
            !rawEnv.isEmpty,
            !rawEnv.contains("$("),
            let environment = BuildEnvironment(rawValue: rawEnv.lowercased())
        else {
            fatalError(
                "AppConfiguration Error: AppEnvironment is missing or invalid in Info.plist. "
                    + "Ensure Config/Developer.xcconfig defines APP_ENVIRONMENT (development | staging | production)."
            )
        }

        let shortVersion =
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"

        return AppConfiguration(
            bundleIdentifier: bundleID,
            cloudKitContainerIdentifier: containerID,
            environment: environment,
            shortVersion: shortVersion,
            buildNumber: buildNumber,
            orthomosaicHelperIdentifier: "\(bundleID).engine.python",
            variHelperIdentifier: "\(bundleID).engine.vari"
        )
    }()
}
