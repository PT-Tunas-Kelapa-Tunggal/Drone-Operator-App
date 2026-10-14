import Foundation

struct FarmArea: Codable, Equatable, Identifiable {
    struct Point: Codable, Equatable {
        var latitude: Double
        var longitude: Double
    }
    var id = UUID()
    var name: String
    var points: [Point]
}
