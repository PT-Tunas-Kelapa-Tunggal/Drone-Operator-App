import Foundation

/// Application rule for one fertilizer inside a scheduled fertilization window.
nonisolated public struct FertilizationScheduleFertilizerItem: Codable, Equatable, Sendable {
    public let fertilizerType: ContractFertilizerType
    public let step: Int
    public let amountPerRoundKg: Double
    public var doneAt: Date?

    enum CodingKeys: String, CodingKey {
        case fertilizerType = "fertilizer_type"
        case step
        case amountPerRoundKg = "amount_per_round_kg"
        case doneAt = "done_at"
    }

    public init(
        fertilizerType: ContractFertilizerType,
        step: Int,
        amountPerRoundKg: Double,
        doneAt: Date? = nil
    ) {
        self.fertilizerType = fertilizerType
        self.step = step
        self.amountPerRoundKg = amountPerRoundKg
        self.doneAt = doneAt
    }
}

/// One recommended fertilization window containing ordered fertilizer application steps.
nonisolated public struct FertilizationSchedulePeriodItem: Codable, Equatable, Sendable {
    public let order: Int
    public let startDate: Date
    public let endDate: Date
    public var fertilizers: [FertilizationScheduleFertilizerItem]

    enum CodingKeys: String, CodingKey {
        case order
        case startDate = "start_date"
        case endDate = "end_date"
        case fertilizers
    }

    public init(
        order: Int,
        startDate: Date,
        endDate: Date,
        fertilizers: [FertilizationScheduleFertilizerItem]
    ) {
        self.order = order
        self.startDate = startDate
        self.endDate = endDate
        self.fertilizers = fertilizers
    }
}
