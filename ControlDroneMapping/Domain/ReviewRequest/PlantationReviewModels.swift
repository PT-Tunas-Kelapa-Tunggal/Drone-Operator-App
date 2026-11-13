import CryptoKit
import Foundation

// MARK: - Domain: PlantationReviewRequest

public struct PlantationReviewRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordName: String
    public let schemaVersion: Int64
    public let farmer: FarmerContact
    public let garden: GardenSummary
    public let boundary: [CoordinatePoint]
    public let agronomy: AgronomicProfile
    public var status: ReviewStatus
    public var progressionEvents: [ReviewProgressionEvent]
    public var timeline: ReviewTimeline
    public var operatorNotes: String?
    /// Per-field contract decode/validation errors keyed by CloudKit record key.
    public var fieldErrors: [String: String]
    public var result: PlantationReviewResult?

    public init(
        id: UUID? = nil,
        recordName: String = UUID().uuidString,
        schemaVersion: Int64 = ContractInfo.version,
        farmer: FarmerContact,
        garden: GardenSummary,
        boundary: [CoordinatePoint],
        agronomy: AgronomicProfile,
        status: ReviewStatus = .sent,
        progressionEvents: [ReviewProgressionEvent] = [],
        timeline: ReviewTimeline = ReviewTimeline(),
        operatorNotes: String? = nil,
        fieldErrors: [String: String] = [:],
        result: PlantationReviewResult? = nil
    ) {
        self.id = id ?? Self.stableUUID(forRecordName: recordName)
        self.recordName = recordName
        self.schemaVersion = schemaVersion
        self.farmer = farmer
        self.garden = garden
        self.boundary = boundary
        self.agronomy = agronomy
        self.status = status
        self.progressionEvents = progressionEvents
        self.timeline = timeline
        self.operatorNotes = operatorNotes
        self.fieldErrors = fieldErrors
        self.result = result
    }

    public var hasFieldErrors: Bool { !fieldErrors.isEmpty }

    public var totalBudgetRp: Double {
        Double(agronomy.fertilizationBudgetPerHa) * garden.areaHectares
    }

    public var centroidCoordinate: CoordinatePoint? {
        guard !boundary.isEmpty else { return nil }
        let count = Double(boundary.count)
        let lat = boundary.reduce(0.0) { $0 + $1.latitude } / count
        let lon = boundary.reduce(0.0) { $0 + $1.longitude } / count
        guard lat.isFinite, lon.isFinite else { return nil }
        return CoordinatePoint(latitude: lat, longitude: lon)
    }

    /// Resolves a UUID from `recordName` when formatted as UUID, otherwise derives a deterministic UUID.
    public static func stableUUID(forRecordName recordName: String) -> UUID {
        if let parsed = UUID(uuidString: recordName) {
            return parsed
        }
        let digest = SHA256.hash(data: Data(recordName.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

public struct FarmerContact: Sendable, Equatable {
    public let name: String
    public let phone: String
    public let address: String

    public init(name: String, phone: String, address: String) {
        self.name = name
        self.phone = phone
        self.address = address
    }
}

public struct GardenSummary: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let locationName: String
    public let areaHectares: Double
    public let circumferenceMeters: Double

    public init(
        id: UUID,
        name: String,
        locationName: String,
        areaHectares: Double,
        circumferenceMeters: Double = 0
    ) {
        self.id = id
        self.name = name
        self.locationName = locationName
        self.areaHectares = areaHectares
        self.circumferenceMeters = circumferenceMeters
    }
}

public struct CoordinatePoint: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct FertilizerCompositionElement: Codable, Equatable, Sendable {
    public let name: String
    public let value: Double
    public let valueUnit: String

    public init(name: String, value: Double, valueUnit: String = "percent") {
        self.name = name
        self.value = value
        self.valueUnit = valueUnit
    }
}

public struct AgronomicProfile: Sendable, Equatable {
    public let plantingYear: Int
    public let plantingMonth: Int?
    public let soilType: ContractSoilType
    public let fertilizingFrequencyPerYear: Int
    public let fertilizationBudgetPerHa: Int64
    public let fertilizerRecords: [FertilizerUsage]
    public let harvestRecord: HarvestYield?

    public init(
        plantingYear: Int,
        plantingMonth: Int? = nil,
        soilType: ContractSoilType,
        fertilizingFrequencyPerYear: Int,
        fertilizationBudgetPerHa: Int64,
        fertilizerRecords: [FertilizerUsage] = [],
        harvestRecord: HarvestYield? = nil
    ) {
        self.plantingYear = plantingYear
        self.plantingMonth = plantingMonth
        self.soilType = soilType
        self.fertilizingFrequencyPerYear = fertilizingFrequencyPerYear
        self.fertilizationBudgetPerHa = fertilizationBudgetPerHa
        self.fertilizerRecords = fertilizerRecords
        self.harvestRecord = harvestRecord
    }
}

public struct FertilizerUsage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let contractType: ContractFertilizerType
    public let composition: [FertilizerCompositionElement]
    /// Normalized annual per-tree dosage per application in kg.
    public let doseKgPerTree: Double
    public let rawDosageText: String

    public var name: String { contractType.rawValue }

    public init(
        id: UUID = UUID(),
        contractType: ContractFertilizerType,
        composition: [FertilizerCompositionElement] = [],
        doseKgPerTree: Double,
        rawDosageText: String? = nil
    ) {
        self.id = id
        self.contractType = contractType
        self.composition = composition
        self.doseKgPerTree = doseKgPerTree
        self.rawDosageText = rawDosageText ?? String(format: "%.2f kg/pohon", doseKgPerTree)
    }
}

public struct HarvestYield: Sendable, Equatable {
    public let frequencyPerMonth: Int
    public let latestWeightKg: Double

    public init(frequencyPerMonth: Int, latestWeightKg: Double) {
        self.frequencyPerMonth = frequencyPerMonth
        self.latestWeightKg = latestWeightKg
    }
}

// MARK: - Domain: ReviewTimeline

public struct ReviewTimeline: Sendable, Equatable {
    public let submittedAt: Date
    public var plannedOperatorVisitDate: Date?
    public var resultSentAt: Date?

    public init(
        submittedAt: Date = Date(),
        plannedOperatorVisitDate: Date? = nil,
        resultSentAt: Date? = nil
    ) {
        self.submittedAt = submittedAt
        self.plannedOperatorVisitDate = plannedOperatorVisitDate
        self.resultSentAt = resultSentAt
    }
}

// MARK: - Domain: PlantationReviewResult (Contract Snapshot)

/// Real deliverable snapshot synchronized to/from `MacOSScanRequestRecordWriter` keys.
public struct PlantationReviewResult: Sendable, Equatable {
    public let completedAt: Date
    public let orthomosaicImageURL: URL?
    public let zones: [FertilizingZoneItem]
    public let trees: [TreeIdentificationItem]
    public let fertilizerNeeds: [FertilizerNeedItem]
    public let schedulePeriods: [FertilizationSchedulePeriodItem]

    public var zoneCount: Int { zones.count }
    public var treeCount: Int { trees.count }
    public var scheduleRoundCount: Int { schedulePeriods.count }

    public init(
        completedAt: Date = Date(),
        orthomosaicImageURL: URL? = nil,
        zones: [FertilizingZoneItem] = [],
        trees: [TreeIdentificationItem] = [],
        fertilizerNeeds: [FertilizerNeedItem] = [],
        schedulePeriods: [FertilizationSchedulePeriodItem] = []
    ) {
        self.completedAt = completedAt
        self.orthomosaicImageURL = orthomosaicImageURL
        self.zones = zones
        self.trees = trees
        self.fertilizerNeeds = fertilizerNeeds
        self.schedulePeriods = schedulePeriods
    }
}
