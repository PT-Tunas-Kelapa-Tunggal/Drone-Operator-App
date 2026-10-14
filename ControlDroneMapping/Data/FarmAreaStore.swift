import CoreLocation
import Foundation
import MapKit

final class FarmAreaStore: FarmAreaRepository {
    private(set) var areas: [FarmArea] = []
    private let url: URL
    init(url: URL? = nil) {
        self.url =
            url
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl/farm-areas.json")
        if let data = try? Data(contentsOf: self.url),
            let saved = try? JSONDecoder().decode([FarmArea].self, from: data)
        {
            areas = saved
        }
    }
    func importFile(_ input: URL) throws {
        guard (try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else {
            throw MappingError.invalid("Batas kebun maksimal 5 MB")
        }
        let data = try Data(contentsOf: input)
        guard data.count <= 5_000_000 else { throw MappingError.invalid("Batas kebun maksimal 5 MB") }
        let features = try MKGeoJSONDecoder().decode(data)
        var added = [FarmArea]()
        func append(_ polygon: MKPolygon, name: String) throws {
            guard polygon.interiorPolygons?.isEmpty != false else {
                throw MappingError.invalid(
                    "Polygon dengan area pengecualian belum didukung. Gunakan batas luar sederhana.")
            }
            guard (3...20000).contains(polygon.pointCount) else {
                throw MappingError.invalid("Jumlah titik batas kebun tidak valid")
            }
            let vertices = (0..<polygon.pointCount).map { polygon.points()[$0].coordinate }
            guard
                vertices.allSatisfy({
                    $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude)
                        && (-180...180).contains($0.longitude)
                })
            else { throw MappingError.invalid("Koordinat kebun tidak valid") }
            added.append(
                FarmArea(
                    name: name,
                    points: vertices.map { FarmArea.Point(latitude: $0.latitude, longitude: $0.longitude) }))
        }
        for object in features {
            if let feature = object as? MKGeoJSONFeature {
                let properties = feature.properties.flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                let name = (properties?["name"] as? String) ?? input.deletingPathExtension().lastPathComponent
                for geometry in feature.geometry {
                    if let polygon = geometry as? MKPolygon {
                        try append(polygon, name: name)
                    } else if let multi = geometry as? MKMultiPolygon {
                        for (i, polygon) in multi.polygons.enumerated() {
                            try append(polygon, name: name + " · \(i + 1)")
                        }
                    }
                }
            } else if let polygon = object as? MKPolygon {
                try append(polygon, name: input.deletingPathExtension().lastPathComponent)
            }
        }
        guard !added.isEmpty else {
            throw MappingError.invalid("Pilih GeoJSON Polygon atau MultiPolygon batas kebun")
        }
        let updated = areas + added
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        areas = updated
    }
}
