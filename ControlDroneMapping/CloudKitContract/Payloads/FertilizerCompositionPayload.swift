import Foundation

/// Represents the chemical composition breakdown of a fertilizer (e.g. Nitrogen 15%).
nonisolated public struct CompositionElement: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let valueType: String
    public let valueUnit: String

    public init(name: String, value: String, valueType: String = "int", valueUnit: String = "percent") {
        self.name = name
        self.value = value
        self.valueType = valueType
        self.valueUnit = valueUnit
    }
}

/// Represents the tree dosage rules for a fertilizer.
nonisolated public struct DosagePerTree: Codable, Equatable, Sendable {
    public let value: String
    public let valueType: String
    public let valueUnit: String

    public init(value: String, valueType: String = "int", valueUnit: String = "kg") {
        self.value = value
        self.valueType = valueType
        self.valueUnit = valueUnit
    }
}

/// One fertilizer item with optional composition and required dosage per tree.
nonisolated public struct FertilizerCompositionItem: Codable, Equatable, Sendable {
    public let fertilizerType: ContractFertilizerType
    public let composition: [CompositionElement]?
    public let dosagePerTree: DosagePerTree

    public init(
        fertilizerType: ContractFertilizerType,
        composition: [CompositionElement]? = nil,
        dosagePerTree: DosagePerTree
    ) {
        self.fertilizerType = fertilizerType
        self.composition = composition
        self.dosagePerTree = dosagePerTree
    }
}
