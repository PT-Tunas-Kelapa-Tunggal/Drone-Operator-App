import Foundation

/// Mac mission identity survives camera acknowledgement and is independent of dataset identity.
struct SavedMission: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var plan: MissionPlan
    var area: FarmArea?
    var remoteID: UUID?
    var phase: MissionPhase = .idle
    var saved = 0
    var commandID = UUID()
    var preparationRequested = false
}

struct MissionLibrary: Codable, Equatable {
    var missions: [SavedMission] = []
    // Deleting a Mac entry must stay deleted when the iPhone sends its manifests again.
    var hiddenRemoteIDs: Set<UUID> = []
    // Optional for compatibility with libraries saved before file cleanup existed.
    var deletedFileIDs: Set<UUID>? = nil
    // Tracks which CloudKit container and build environment own these cached missions.
    var cloudKitContainerIdentifier: String? = nil
    var cloudKitEnvironment: String? = nil

    func matches(_ scope: AppConfiguration.StorageScope) -> Bool {
        cloudKitContainerIdentifier == scope.cloudKitContainerIdentifier
            && cloudKitEnvironment?.lowercased() == scope.environment.lowercased()
    }

    func tagged(with scope: AppConfiguration.StorageScope) -> MissionLibrary {
        var copy = self
        copy.cloudKitContainerIdentifier = scope.cloudKitContainerIdentifier
        copy.cloudKitEnvironment = scope.environment.lowercased()
        return copy
    }
}

protocol MissionLibraryRepository {
    func load() throws -> MissionLibrary
    func save(_ library: MissionLibrary) throws
}
