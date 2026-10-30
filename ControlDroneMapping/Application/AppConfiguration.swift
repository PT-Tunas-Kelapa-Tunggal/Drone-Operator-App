import Foundation

/// Centralized, typed runtime configuration for ControlDroneMapping.
///
/// Validates that all required build-time settings were supplied via `Config/Developer.xcconfig`
/// without any silent fallback defaults.
public struct AppConfiguration: Sendable {
    public let bundleIdentifier: String
    public let cloudKitContainerIdentifier: String
    public let orthomosaicHelperIdentifier: String
    public let variHelperIdentifier: String

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

        return AppConfiguration(
            bundleIdentifier: bundleID,
            cloudKitContainerIdentifier: containerID,
            orthomosaicHelperIdentifier: "\(bundleID).engine.python",
            variHelperIdentifier: "\(bundleID).engine.vari"
        )
    }()
}

