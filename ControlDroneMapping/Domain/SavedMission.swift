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
}

protocol MissionLibraryRepository {
    func load() throws -> MissionLibrary
    func save(_ library: MissionLibrary) throws
}
