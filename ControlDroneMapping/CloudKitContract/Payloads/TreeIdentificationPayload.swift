import Foundation

/// Health classification label for an identified tree.
nonisolated public enum TreeHealthLabel: String, Codable, Equatable, Sendable {
    case normal = "Normal"
    case terindikasi = "Terindikasi"
    case defisiensi = "Defisiensi"
    case tidakWajar = "Tidak Wajar"
    case unknown = "Unknown"

    /// Converts a VARI tree quartile into the contract label.
    /// The engine may vary casing and whitespace, so normalize before matching.
    public init(engineValue: String?) {
        let normalized = (engineValue ?? "")
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }

        switch normalized {
        case "q1": self = .tidakWajar
        case "q2": self = .defisiensi
        case "q3": self = .terindikasi
        case "q4": self = .normal
        default: self = .unknown
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(engineValue: try? container.decode(String.self))
    }
}

/// Single identified palm tree in the orthomosaic pixel space.
nonisolated public struct TreeIdentificationItem: Codable, Equatable, Sendable {
    public let id: Int64
    public let boundingBox: [PixelPoint]
    public let zoneId: Int64
    public let healthynessLabel: TreeHealthLabel

    enum CodingKeys: String, CodingKey {
        case id
        case boundingBox = "bounding_box"
        case zoneId = "zone_id"
        case healthynessLabel = "healthyness_label"
    }

    public init(
        id: Int64,
        boundingBox: [PixelPoint],
        zoneId: Int64,
        healthynessLabel: TreeHealthLabel
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.zoneId = zoneId
        self.healthynessLabel = healthynessLabel
    }
}
