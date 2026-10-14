import Combine
import Foundation

final class FarmAreaViewModel: ObservableObject {
    @Published private(set) var areas: [FarmArea]
    @Published var selectedArea: UUID?
    @Published private(set) var error: String?
    private let repository: any FarmAreaRepository

    init(repository: any FarmAreaRepository) {
        self.repository = repository
        areas = repository.areas
    }
    func nearbyAreas(center: MapCoordinate?, radiusKm: Double) -> [FarmArea] {
        guard let center, center.isValid, radiusKm.isFinite, radiusKm > 0 else { return areas }
        return areas.filter { area in
            guard !area.points.isEmpty else { return false }
            let latitude = area.points.map(\.latitude).reduce(0, +) / Double(area.points.count)
            let longitude = area.points.map(\.longitude).reduce(0, +) / Double(area.points.count)
            return center.distance(to: MapCoordinate(latitude: latitude, longitude: longitude)) <= radiusKm
                * 1000
        }
    }
    func importArea(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try repository.importFile(url)
            areas = repository.areas
            selectedArea = areas.last?.id
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
