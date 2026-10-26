import Foundation

// MARK: - Repository Transfer DTO (CloudKit record representation)
public struct PlantationScanRequestRecordDTO: Sendable {
    public let recordName: String              // Request UUID
    public let farmerName: String
    public let farmerPhone: String
    public let farmerAddress: String
    public let gardenID: String                // Garden UUID
    public let gardenName: String
    public let locationName: String
    public let areaHectares: Double

    // Serialized Data Blobs (Stored as Strings in CloudKit)
    public let boundaryJSON: String            // Encoded [CoordinatePointDTO]
    public let agronomicJSON: String           // Encoded AgronomicProfileDTO
    public let resultJSON: String?             // Encoded PlantationReviewResultDTO

    // Status Code & Milestones
    public let statusCode: Int                 // 0: submitted, 1: scheduled, 2: inReview, 3: completed
    public let submittedAt: Date
    public let scheduledFor: Date?
    public let inReviewAt: Date?
    public let completedAt: Date?
    public let operatorNotes: String?
    public let orthomosaicAssetURL: URL?       // Managed via CKAsset

    public init(
        recordName: String,
        farmerName: String,
        farmerPhone: String,
        farmerAddress: String,
        gardenID: String,
        gardenName: String,
        locationName: String,
        areaHectares: Double,
        boundaryJSON: String,
        agronomicJSON: String,
        statusCode: Int,
        submittedAt: Date,
        scheduledFor: Date? = nil,
        inReviewAt: Date? = nil,
        completedAt: Date? = nil,
        operatorNotes: String? = nil,
        resultJSON: String? = nil,
        orthomosaicAssetURL: URL? = nil
    ) {
        self.recordName = recordName
        self.farmerName = farmerName
        self.farmerPhone = farmerPhone
        self.farmerAddress = farmerAddress
        self.gardenID = gardenID
        self.gardenName = gardenName
        self.locationName = locationName
        self.areaHectares = areaHectares
        self.boundaryJSON = boundaryJSON
        self.agronomicJSON = agronomicJSON
        self.statusCode = statusCode
        self.submittedAt = submittedAt
        self.scheduledFor = scheduledFor
        self.inReviewAt = inReviewAt
        self.completedAt = completedAt
        self.operatorNotes = operatorNotes
        self.resultJSON = resultJSON
        self.orthomosaicAssetURL = orthomosaicAssetURL
    }
}

// MARK: - JSON Serialization DTOs
public struct CoordinatePointDTO: Codable, Sendable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public struct AgronomicProfileDTO: Codable, Sendable {
    public let year: Int
    public let month: Int?
    public let soil: String
    public let fertilizers: [FertilizerUsageDTO]
    public let harvest: HarvestYieldDTO?

    public init(year: Int, month: Int?, soil: String, fertilizers: [FertilizerUsageDTO], harvest: HarvestYieldDTO?) {
        self.year = year
        self.month = month
        self.soil = soil
        self.fertilizers = fertilizers
        self.harvest = harvest
    }
}

public struct FertilizerUsageDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let bagKg: Double
    public let bags: Int
    public let dosePerTree: Double

    public init(id: String, name: String, bagKg: Double, bags: Int, dosePerTree: Double) {
        self.id = id
        self.name = name
        self.bagKg = bagKg
        self.bags = bags
        self.dosePerTree = dosePerTree
    }
}

public struct HarvestYieldDTO: Codable, Sendable {
    public let freq: Int
    public let weightKg: Double

    public init(freq: Int, weightKg: Double) {
        self.freq = freq
        self.weightKg = weightKg
    }
}

public struct PlantationReviewResultDTO: Codable, Sendable {
    public let completedAt: Date
    public let nutrients: [NutrientMetricDTO]
    public let costs: [CostEstimateDTO]
    public let totalCostFormatted: String
    public let areas: [AreaPlanDTO]

    public init(
        completedAt: Date,
        nutrients: [NutrientMetricDTO],
        costs: [CostEstimateDTO],
        totalCostFormatted: String,
        areas: [AreaPlanDTO]
    ) {
        self.completedAt = completedAt
        self.nutrients = nutrients
        self.costs = costs
        self.totalCostFormatted = totalCostFormatted
        self.areas = areas
    }
}

public struct NutrientMetricDTO: Codable, Sendable {
    public let name: String
    public let current: Double
    public let target: Double

    public init(name: String, current: Double, target: Double) {
        self.name = name
        self.current = current
        self.target = target
    }
}

public struct CostEstimateDTO: Codable, Sendable {
    public let name: String
    public let quantity: String
    public let cost: String

    public init(name: String, quantity: String, cost: String) {
        self.name = name
        self.quantity = quantity
        self.cost = cost
    }
}

public struct AreaPlanDTO: Codable, Sendable {
    public let areaID: String
    public let periods: [PeriodPlanDTO]

    public init(areaID: String, periods: [PeriodPlanDTO]) {
        self.areaID = areaID
        self.periods = periods
    }
}

public struct PeriodPlanDTO: Codable, Sendable {
    public let title: String
    public let dateRange: String
    public let lines: [DoseLineDTO]

    public init(title: String, dateRange: String, lines: [DoseLineDTO]) {
        self.title = title
        self.dateRange = dateRange
        self.lines = lines
    }
}

public struct DoseLineDTO: Codable, Sendable {
    public let name: String
    public let total: String
    public let dosage: String

    public init(name: String, total: String, dosage: String) {
        self.name = name
        self.total = total
        self.dosage = dosage
    }
}
