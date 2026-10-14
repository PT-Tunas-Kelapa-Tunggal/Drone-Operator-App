import Foundation

struct FileMissionLibraryRepository: MissionLibraryRepository {
    let url: URL?
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/missions.json")
    }
    func load() throws -> MissionLibrary {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return MissionLibrary() }
        return try JSONDecoder().decode(MissionLibrary.self, from: Data(contentsOf: url))
    }
    func save(_ library: MissionLibrary) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(library)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
