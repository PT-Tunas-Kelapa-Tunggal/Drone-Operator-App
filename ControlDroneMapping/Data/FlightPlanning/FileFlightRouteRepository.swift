import Foundation

struct FileFlightRouteRepository: FlightRouteRepository {
    let url: URL?
    init(
        url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/flight-routes.json")
    ) { self.url = url }
    func load() throws -> [FlightRoute] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([FlightRoute].self, from: Data(contentsOf: url))
    }
    func save(_ routes: [FlightRoute]) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(routes)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
