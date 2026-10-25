import Foundation

// MARK: - Domain: PlantationReviewRequest
public struct PlantationReviewRequest: Identifiable, Sendable {
    public let id: UUID
    public let farmer: FarmerContact
    public let garden: GardenSummary
    public let boundary: [CoordinatePoint]
    public let agronomy: AgronomicProfile
    public var status: ReviewStatus
    public var timeline: ReviewTimeline
    public var operatorNotes: String?
    public var result: PlantationReviewResult?

    public init(
        id: UUID = UUID(),
        farmer: FarmerContact,
        garden: GardenSummary,
        boundary: [CoordinatePoint],
        agronomy: AgronomicProfile,
        status: ReviewStatus = .submitted,
        timeline: ReviewTimeline = ReviewTimeline(),
        operatorNotes: String? = nil,
        result: PlantationReviewResult? = nil
    ) {
        self.id = id
        self.farmer = farmer
        self.garden = garden
        self.boundary = boundary
        self.agronomy = agronomy
        self.status = status
        self.timeline = timeline
        self.operatorNotes = operatorNotes
        self.result = result
    }
}

public struct FarmerContact: Sendable {
    public let name: String
    public let phone: String
    public let address: String

    public init(name: String, phone: String, address: String) {
        self.name = name
        self.phone = phone
        self.address = address
    }
}

public struct GardenSummary: Sendable {
    public let id: UUID
    public let name: String
    public let locationName: String
    public let areaHectares: Double

    public init(id: UUID, name: String, locationName: String, areaHectares: Double) {
        self.id = id
        self.name = name
        self.locationName = locationName
        self.areaHectares = areaHectares
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

public struct AgronomicProfile: Sendable {
    public let plantingYear: Int
    public let plantingMonth: Int?
    public let soilType: String
    public let fertilizerRecords: [FertilizerUsage]
    public let harvestRecord: HarvestYield?

    public init(
        plantingYear: Int,
        plantingMonth: Int? = nil,
        soilType: String,
        fertilizerRecords: [FertilizerUsage] = [],
        harvestRecord: HarvestYield? = nil
    ) {
        self.plantingYear = plantingYear
        self.plantingMonth = plantingMonth
        self.soilType = soilType
        self.fertilizerRecords = fertilizerRecords
        self.harvestRecord = harvestRecord
    }
}

public struct FertilizerUsage: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let bagWeightKg: Double
    public let bagCount: Int
    public let doseKgPerTree: Double

    public init(
        id: UUID = UUID(),
        name: String,
        bagWeightKg: Double,
        bagCount: Int,
        doseKgPerTree: Double
    ) {
        self.id = id
        self.name = name
        self.bagWeightKg = bagWeightKg
        self.bagCount = bagCount
        self.doseKgPerTree = doseKgPerTree
    }
}

public struct HarvestYield: Sendable {
    public let frequencyPerMonth: Int
    public let latestWeightKg: Double

    public init(frequencyPerMonth: Int, latestWeightKg: Double) {
        self.frequencyPerMonth = frequencyPerMonth
        self.latestWeightKg = latestWeightKg
    }
}

// MARK: - Domain: ReviewTimeline
public struct ReviewTimeline: Sendable {
    public let submittedAt: Date
    public var scheduledFor: Date?
    public var inReviewAt: Date?
    public var completedAt: Date?

    public init(
        submittedAt: Date = Date(),
        scheduledFor: Date? = nil,
        inReviewAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.submittedAt = submittedAt
        self.scheduledFor = scheduledFor
        self.inReviewAt = inReviewAt
        self.completedAt = completedAt
    }
}

// MARK: - Domain: PlantationReviewResult
public struct PlantationReviewResult: Sendable {
    public let completedAt: Date
    public let nutrients: [NutrientMetric]
    public let costs: [CostEstimate]
    public let totalCostFormatted: String
    public let allocationAreas: [FertilizerAreaPlan]
    public let orthomosaicImageURL: URL?

    public init(
        completedAt: Date = Date(),
        nutrients: [NutrientMetric] = [],
        costs: [CostEstimate] = [],
        totalCostFormatted: String = "Rp 0",
        allocationAreas: [FertilizerAreaPlan] = [],
        orthomosaicImageURL: URL? = nil
    ) {
        self.completedAt = completedAt
        self.nutrients = nutrients
        self.costs = costs
        self.totalCostFormatted = totalCostFormatted
        self.allocationAreas = allocationAreas
        self.orthomosaicImageURL = orthomosaicImageURL
    }
    // TODO: implement with actual AI/ML later, this is static placeholder only
    public static func standardRecommendation(
        completedAt: Date = Date(),
        orthomosaicImageURL: URL? = nil
    ) -> PlantationReviewResult {
        PlantationReviewResult(
            completedAt: completedAt,
            nutrients: [
                NutrientMetric(name: "Nitrogen (N)", current: 0.65, target: 0.85),
                NutrientMetric(name: "Fosfor (P)", current: 0.45, target: 0.80),
                NutrientMetric(name: "Kalium (K)", current: 0.55, target: 0.90),
                NutrientMetric(name: "Magnesium (Mg)", current: 0.70, target: 0.85),
                NutrientMetric(name: "Boron (B)", current: 0.60, target: 0.75)
            ],
            costs: [
                CostEstimate(name: "Urea", quantity: "450 kg", cost: "Rp 1.125.000"),
                CostEstimate(name: "Rock Phosphate", quantity: "300 kg", cost: "Rp 750.000"),
                CostEstimate(name: "MOP (KCl)", quantity: "500 kg", cost: "Rp 1.850.000"),
                CostEstimate(name: "Kieserite", quantity: "200 kg", cost: "Rp 600.000")
            ],
            totalCostFormatted: "Rp 4.325.000",
            allocationAreas: [
                FertilizerAreaPlan(
                    id: "A",
                    periods: [
                        FertilizerPeriodPlan(
                            title: "Periode 1",
                            dateRange: "Maret - Mei 2026",
                            lines: [
                                FertilizerDoseLine(name: "Urea", total: "225 kg", dosage: "1.5 kg/pohon"),
                                FertilizerDoseLine(name: "MOP (KCl)", total: "250 kg", dosage: "1.7 kg/pohon")
                            ]
                        ),
                        FertilizerPeriodPlan(
                            title: "Periode 2",
                            dateRange: "September - November 2026",
                            lines: [
                                FertilizerDoseLine(name: "Rock Phosphate", total: "300 kg", dosage: "2.0 kg/pohon"),
                                FertilizerDoseLine(name: "Kieserite", total: "200 kg", dosage: "1.3 kg/pohon")
                            ]
                        )
                    ]
                )
            ],
            orthomosaicImageURL: orthomosaicImageURL
        )
    }
}

public struct NutrientMetric: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let current: Double
    public let target: Double

    public init(name: String, current: Double, target: Double) {
        self.name = name
        self.current = current
        self.target = target
    }
}

public struct CostEstimate: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let quantity: String
    public let cost: String

    public init(name: String, quantity: String, cost: String) {
        self.name = name
        self.quantity = quantity
        self.cost = cost
    }
}

public struct FertilizerAreaPlan: Identifiable, Sendable {
    public let id: String
    public let periods: [FertilizerPeriodPlan]

    public init(id: String, periods: [FertilizerPeriodPlan]) {
        self.id = id
        self.periods = periods
    }
}

public struct FertilizerPeriodPlan: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let dateRange: String
    public let lines: [FertilizerDoseLine]

    public init(title: String, dateRange: String, lines: [FertilizerDoseLine]) {
        self.title = title
        self.dateRange = dateRange
        self.lines = lines
    }
}

public struct FertilizerDoseLine: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let total: String
    public let dosage: String

    public init(name: String, total: String, dosage: String) {
        self.name = name
        self.total = total
        self.dosage = dosage
    }
}
