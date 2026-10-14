import Foundation

protocol MissionDraftRepository {
    func load() throws -> Command?
    func save(_ command: Command) throws
    func clear() throws
}
