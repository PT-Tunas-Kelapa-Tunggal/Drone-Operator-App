import Foundation

/// Whole-farm annual purchase prediction for one fertilizer. Prices are in IDR.
nonisolated public struct FertilizerCostPredictionItem: Codable, Equatable, Sendable {
    public let totalBagsNeeded: Int
    public let totalKg: Double?
    public let totalCost: Double?

    enum CodingKeys: String, CodingKey {
        case totalBagsNeeded = "total_bags_needed"
        case totalKg = "total_kg"
        case totalCost = "total_cost"
    }

    public init(totalBagsNeeded: Int, totalKg: Double?, totalCost: Double?) {
        self.totalBagsNeeded = totalBagsNeeded
        self.totalKg = totalKg
        self.totalCost = totalCost
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalBagsNeeded, forKey: .totalBagsNeeded)
        try container.encode(totalKg, forKey: .totalKg)
        // Preserve an unavailable prediction as null rather than reporting a zero price.
        try container.encode(totalCost, forKey: .totalCost)
    }
}

/// Encodes enum-keyed predictions as a JSON object, never Swift's dictionary pair array.
nonisolated public struct FertilizerCostPredictions: Codable, Equatable, Sendable {
    public let byFertilizer: [ContractFertilizerType: FertilizerCostPredictionItem]

    public init(byFertilizer: [ContractFertilizerType: FertilizerCostPredictionItem] = [:]) {
        self.byFertilizer = byFertilizer
    }

    public init(from decoder: Decoder) throws {
        let raw = try [String: FertilizerCostPredictionItem](from: decoder)
        var predictions: [ContractFertilizerType: FertilizerCostPredictionItem] = [:]
        for (key, value) in raw {
            let type = try ContractFertilizerType(key)
            guard predictions[type] == nil else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Duplicate fertilizer prediction for '\(type.rawValue)'.")
                )
            }
            predictions[type] = value
        }
        byFertilizer = predictions
    }

    public func encode(to encoder: Encoder) throws {
        let raw = Dictionary(uniqueKeysWithValues: byFertilizer.map { ($0.key.rawValue, $0.value) })
        try raw.encode(to: encoder)
    }
}
