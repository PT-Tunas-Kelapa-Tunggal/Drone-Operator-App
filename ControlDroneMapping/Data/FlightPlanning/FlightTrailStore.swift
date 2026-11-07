import Foundation

protocol FlightTrailRepository {
    func load() throws -> [UUID: [MapCoordinate]]
    func save(_ trails: [UUID: [MapCoordinate]]) throws
}

final class InMemoryFlightTrailRepository: FlightTrailRepository {
    private var trails: [UUID: [MapCoordinate]]
    init(trails: [UUID: [MapCoordinate]] = [:]) {
        self.trails = trails
    }
    func load() throws -> [UUID: [MapCoordinate]] { trails }
    func save(_ trails: [UUID: [MapCoordinate]]) throws { self.trails = trails }
}

struct FileFlightTrailRepository: FlightTrailRepository {
    let url: URL?

    init(
        url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/flight-trails.json")
    ) {
        self.url = url
    }

    func load() throws -> [UUID: [MapCoordinate]] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            return try JSONDecoder().decode([UUID: [MapCoordinate]].self, from: Data(contentsOf: url))
        } catch {
            return [:]
        }
    }

    func save(_ trails: [UUID: [MapCoordinate]]) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(trails)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
