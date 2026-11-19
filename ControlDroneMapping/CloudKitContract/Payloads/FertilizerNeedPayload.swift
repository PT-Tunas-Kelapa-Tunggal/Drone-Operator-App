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
    /// Annual zone amount; general NPK entries retain the farm-wide annual amount.
    public let recommendedDosagePerZonePerYear: Double
    /// Annual amount per tree in the zone, when reported by VARI.
    public let recommendedDosagePerTreePerZonePerYear: Double?
    public let dosageUnit: String
    public let currentDosage: Double
    public let zoneId: Int64?

    enum CodingKeys: String, CodingKey {
        case fertilizerApplicationType = "fertilizer_application_type"
        case fertilizerType = "fertilizer_type"
        case recommendedDosagePerZonePerYear = "recommended_dosage"
        case recommendedDosagePerTreePerZonePerYear = "recommended_dosage_per_tree_per_zone_per_year"
        case dosageUnit = "dosage_unit"
        case currentDosage = "current_dosage"
        case zoneId = "zone_id"
    }

    public init(
        fertilizerApplicationType: FertilizerApplicationType,
        fertilizerType: ContractFertilizerType,
        recommendedDosagePerZonePerYear: Double,
        recommendedDosagePerTreePerZonePerYear: Double? = nil,
        dosageUnit: String,
        currentDosage: Double,
        zoneId: Int64? = nil
    ) {
        self.fertilizerApplicationType = fertilizerApplicationType
        self.fertilizerType = fertilizerType
        self.recommendedDosagePerZonePerYear = recommendedDosagePerZonePerYear
        self.recommendedDosagePerTreePerZonePerYear = recommendedDosagePerTreePerZonePerYear
        self.dosageUnit = dosageUnit
        self.currentDosage = currentDosage
        self.zoneId = zoneId
    }
}
