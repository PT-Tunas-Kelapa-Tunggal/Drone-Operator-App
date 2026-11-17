import Foundation

/// Nutrient components shared by the farmer and drone-operator applications.
nonisolated public enum ContractNutrientType: String, Codable, CaseIterable, Equatable, Sendable {
    case nitrogen = "Nitrogen"
    case phosphorus = "Fospor"
    case potassium = "Kalium"
    case magnesium = "Magnesium"
}

/// ML-reported annual nutrient amounts per hectare (kg/ha/year).
/// The iOS client decides whether current practice meets the recommendation.
nonisolated public struct FarmNutrientComparisonStatusItem: Codable, Equatable, Sendable {
    public let nutrientType: ContractNutrientType
    public let current: Double
    public let recommendation: Double

    enum CodingKeys: String, CodingKey {
        case nutrientType = "nutrient_type"
        case current
        case recommendation
    }

    public init(
        nutrientType: ContractNutrientType,
        current: Double,
        recommendation: Double
    ) {
        self.nutrientType = nutrientType
        self.current = current
        self.recommendation = recommendation
    }
}
