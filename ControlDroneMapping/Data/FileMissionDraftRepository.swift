import Foundation

/// Acknowledged drafts are removed. Unknown outcomes retain the command UUID.
struct FileMissionDraftRepository: MissionDraftRepository {
    let url: URL?

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/mission-draft.json")
    }

    func load() throws -> Command? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let command = try JSONDecoder().decode(Command.self, from: Data(contentsOf: url))
        guard command.action == .createMission, command.plan != nil else {
            throw MappingError.invalid("Draft misi tidak valid")
        }
        return command
    }

    func save(_ command: Command) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(command).write(to: url, options: .atomic)
    }

    func clear() throws {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
