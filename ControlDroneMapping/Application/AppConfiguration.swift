import Foundation

/// Centralized, typed runtime configuration for ControlDroneMapping.
///
/// Validates that all required build-time settings were supplied via `Config/Developer.xcconfig`
/// without any silent fallback defaults.
public struct AppConfiguration: Sendable {
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

    public static let current: AppConfiguration = {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            fatalError("AppConfiguration Error: Bundle.main.bundleIdentifier is missing or empty.")
        }

        guard let containerID = Bundle.main.object(forInfoDictionaryKey: "ICloudContainerIdentifier") as? String,
              !containerID.isEmpty,
              !containerID.contains("$(") else {
            fatalError(
                "AppConfiguration Error: ICloudContainerIdentifier is not properly configured in Info.plist. " +
                "Ensure Config/Developer.xcconfig defines a valid ICLOUD_CONTAINER_NAME."
            )
        }

        guard let rawEnv = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String,
              !rawEnv.isEmpty,
              !rawEnv.contains("$("),
              let environment = BuildEnvironment(rawValue: rawEnv.lowercased()) else {
            fatalError(
                "AppConfiguration Error: AppEnvironment is missing or invalid in Info.plist. " +
                "Ensure Config/Developer.xcconfig defines APP_ENVIRONMENT (development | staging | production)."
            )
        }

        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
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

