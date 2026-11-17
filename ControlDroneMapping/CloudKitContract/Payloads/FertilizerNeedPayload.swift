import Foundation

/// Application scope of a recommended fertilizer dose.
nonisolated public enum FertilizerApplicationType: String, Codable, Equatable, Sendable {
    case general = "general"
    case zoneSpecific = "zone_specific"
    case unknown = "unknown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "general": self = .general
        case "zone_specific", "zonespecific": self = .zoneSpecific
        default: self = .unknown
        }
    }
}

/// Fertilizer requirement recommendation for the farm or specific zone.
nonisolated public struct FertilizerNeedItem: Codable, Equatable, Sendable {
    public let fertilizerApplicationType: FertilizerApplicationType
    public let fertilizerType: ContractFertilizerType
    public let recommendedDosage: Double
    public let dosageUnit: String
    public let currentDosage: Double
    public let zoneId: Int64?

    enum CodingKeys: String, CodingKey {
        case fertilizerApplicationType = "fertilizer_application_type"
        case fertilizerType = "fertilizer_type"
        case recommendedDosage = "recommended_dosage"
        case dosageUnit = "dosage_unit"
        case currentDosage = "current_dosage"
        case zoneId = "zone_id"
    }

    public init(
        fertilizerApplicationType: FertilizerApplicationType,
        fertilizerType: ContractFertilizerType,
        recommendedDosage: Double,
        dosageUnit: String,
        currentDosage: Double,
        zoneId: Int64? = nil
    ) {
        self.fertilizerApplicationType = fertilizerApplicationType
        self.fertilizerType = fertilizerType
        self.recommendedDosage = recommendedDosage
        self.dosageUnit = dosageUnit
        self.currentDosage = currentDosage
        self.zoneId = zoneId
    }
}
