import Foundation

/// Health classification label for an identified tree.
nonisolated public enum TreeHealthLabel: String, Codable, Equatable, Sendable {
    case normal = "Normal"
    case terindikasi = "Terindikasi"
    case defisiensi = "Defisiensi"
    case tidakWajar = "Tidak Wajar"
    case unknown = "Unknown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "normal": self = .normal
        case "terindikasi": self = .terindikasi
        case "defisiensi": self = .defisiensi
        case "tidak wajar", "tidakwajar": self = .tidakWajar
        default: self = .unknown
        }
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
