import Foundation

/// Summary of reference zone baseline and VARI gap calculations across the plantation.
public struct VariSummary: Sendable, Equatable {
    public let referenceZoneIDs: [Int]
    public let referenceFallbackAllZones: Bool
    public let p25ZoneMeanVari: Double?
    public let referenceZoneMeanVari: Double?
    public let p95P25VariGap: Double?
    public let boostMode: String?
    public let blanketVariGapCutoff: Double?
    public let overallFieldConfidence: Double?

    public init(
        referenceZoneIDs: [Int] = [],
        referenceFallbackAllZones: Bool = false,
        p25ZoneMeanVari: Double? = nil,
        referenceZoneMeanVari: Double? = nil,
        p95P25VariGap: Double? = nil,
        boostMode: String? = nil,
        blanketVariGapCutoff: Double? = nil,
        overallFieldConfidence: Double? = nil
    ) {
        self.referenceZoneIDs = referenceZoneIDs
        self.referenceFallbackAllZones = referenceFallbackAllZones
        self.p25ZoneMeanVari = p25ZoneMeanVari
        self.referenceZoneMeanVari = referenceZoneMeanVari
        self.p95P25VariGap = p95P25VariGap
        self.boostMode = boostMode
        self.blanketVariGapCutoff = blanketVariGapCutoff
        self.overallFieldConfidence = overallFieldConfidence
    }
}

/// 2D bounding box in orthomosaic image pixel coordinates.
public struct VariPixelBox: Sendable, Equatable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public var corners: [PixelPoint] {
        [
            PixelPoint(x: x1, y: y1),
            PixelPoint(x: x2, y: y1),
            PixelPoint(x: x2, y: y2),
            PixelPoint(x: x1, y: y2),
        ]
    }

    public func isValid(withinWidth width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let maxW = Double(width)
        let maxH = Double(height)
        return x1.isFinite && y1.isFinite && x2.isFinite && y2.isFinite
            && x1 >= 0 && y1 >= 0 && x2 >= x1 && y2 >= y1
            && x2 <= maxW + 1.0 && y2 <= maxH + 1.0
    }
}

/// Detected palm tree geometry attached to a VARI management zone.
public struct VariTreeDetection: Identifiable, Sendable, Equatable {
    public let id: Int
    public let zoneID: Int
    public let boundingBox: VariPixelBox

    public init(id: Int, zoneID: Int, boundingBox: VariPixelBox) {
        self.id = id
        self.zoneID = zoneID
        self.boundingBox = boundingBox
    }
}

/// Detailed metrics, vegetation statistics, and crop previews for a single agricultural zone.
public struct VariZoneDetail: Identifiable, Sendable, Equatable {
    public var id: Int { zoneID }
    public let zoneID: Int
    public let approxRow: Int?
    public let treeCount: Int
    public let meanVari: Double?
    public let medianVari: Double?
    public let minVari: Double?
    public let maxVari: Double?
    public let stdVari: Double?
    public let confidence: Double?
    public let boostMode: String?
    public let areaHa: Double?
    public let mgSupplementKg: Double?
    public let nSupplementKg: Double?
    public let boundingBox: VariPixelBox?
    public let trees: [VariTreeDetection]
    public let baseImageCropURL: URL?
    public let exgImageCropURL: URL?

    public init(
        zoneID: Int,
        approxRow: Int? = nil,
        treeCount: Int,
        meanVari: Double? = nil,
        medianVari: Double? = nil,
        minVari: Double? = nil,
        maxVari: Double? = nil,
        stdVari: Double? = nil,
        confidence: Double? = nil,
        boostMode: String? = nil,
        areaHa: Double? = nil,
        mgSupplementKg: Double? = nil,
        nSupplementKg: Double? = nil,
        boundingBox: VariPixelBox? = nil,
        trees: [VariTreeDetection] = [],
        baseImageCropURL: URL? = nil,
        exgImageCropURL: URL? = nil
    ) {
        self.zoneID = zoneID
        self.approxRow = approxRow
        self.treeCount = treeCount
        self.meanVari = meanVari
        self.medianVari = medianVari
        self.minVari = minVari
        self.maxVari = maxVari
        self.stdVari = stdVari
        self.confidence = confidence
        self.boostMode = boostMode
        self.areaHa = areaHa
        self.mgSupplementKg = mgSupplementKg
        self.nSupplementKg = nSupplementKg
        self.boundingBox = boundingBox
        self.trees = trees
        self.baseImageCropURL = baseImageCropURL
        self.exgImageCropURL = exgImageCropURL
    }
}

/// Fertilizer product mass conversion and bag count row (e.g., Dolomite, Kieserite, Urea).
public struct VariProductRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let zoneID: Int?
    public let zoneLabel: String
    public let productName: String
    public let nutrientType: String?
    public let supplementKg: Double
    public let baseProductKg: Double
    public let combinedKg: Double
    public let estimatedBags: Double
    public let fullBagsNeeded: Int

    public init(
        id: String,
        zoneID: Int? = nil,
        zoneLabel: String,
        productName: String,
        nutrientType: String? = nil,
        supplementKg: Double,
        baseProductKg: Double,
        combinedKg: Double,
        estimatedBags: Double,
        fullBagsNeeded: Int
    ) {
        self.id = id
        self.zoneID = zoneID
        self.zoneLabel = zoneLabel
        self.productName = productName
        self.nutrientType = nutrientType
        self.supplementKg = supplementKg
        self.baseProductKg = baseProductKg
        self.combinedKg = combinedKg
        self.estimatedBags = estimatedBags
        self.fullBagsNeeded = fullBagsNeeded
    }
}

/// Commercial N-P2O5-K2O-MgO ratio breakdown parsed from VARI outputs or explicit contract enums.
public struct VariNPKRatio: Sendable, Equatable {
    public let n: Double
    public let p2o5: Double
    public let k2o: Double
    public let mgo: Double

    public init(n: Double, p2o5: Double, k2o: Double, mgo: Double = 0.0) {
        self.n = n
        self.p2o5 = p2o5
        self.k2o = k2o
        self.mgo = mgo
    }

    public init?(contractType: ContractFertilizerType) {
        switch contractType {
        case .npk15_15_15: self.init(n: 15, p2o5: 15, k2o: 15, mgo: 0)
        case .npk12_6_22_3: self.init(n: 12, p2o5: 6, k2o: 22, mgo: 3)
        case .npk13_6_27_4: self.init(n: 13, p2o5: 6, k2o: 27, mgo: 4)
        case .npk13_8_27_4: self.init(n: 13, p2o5: 8, k2o: 27, mgo: 4)
        case .npk16_16_16: self.init(n: 16, p2o5: 16, k2o: 16, mgo: 0)
        default: return nil
        }
    }

    /// Maps strictly to explicit NPK variants supported by `CloudKitContract` (never `.npk`).
    public func toExplicitContractNPKType() -> ContractFertilizerType? {
        let key = (
            Int(n.rounded()),
            Int(p2o5.rounded()),
            Int(k2o.rounded()),
            Int(mgo.rounded())
        )
        switch key {
        case (15, 15, 15, 0): return .npk15_15_15
        case (12, 6, 22, 3): return .npk12_6_22_3
        case (13, 6, 27, 4): return .npk13_6_27_4
        case (13, 8, 27, 4): return .npk13_8_27_4
        case (16, 16, 16, 0): return .npk16_16_16
        default: return nil
        }
    }
}

/// Farmer's historical NPK baseline summary decoded from `user_blend` inside `vari_result.json`.
public struct VariUserBlendSummary: Sendable, Equatable {
    public let ratio: VariNPKRatio?
    public let bagSizeKg: Double
    public let farmAreaHaUsed: Double?
    public let npkProductKgFarmPerYear: Double
    public let dosePerTreeKgPerApplication: Double?
    public let applicationsPerYear: Double?

    public init(
        ratio: VariNPKRatio? = nil,
        bagSizeKg: Double = 50.0,
        farmAreaHaUsed: Double? = nil,
        npkProductKgFarmPerYear: Double = 0.0,
        dosePerTreeKgPerApplication: Double? = nil,
        applicationsPerYear: Double? = nil
    ) {
        self.ratio = ratio
        self.bagSizeKg = bagSizeKg
        self.farmAreaHaUsed = farmAreaHaUsed
        self.npkProductKgFarmPerYear = npkProductKgFarmPerYear
        self.dosePerTreeKgPerApplication = dosePerTreeKgPerApplication
        self.applicationsPerYear = applicationsPerYear
    }
}

/// A commercial NPK blend candidate compared against the farmer's entered budget.
public struct VariBudgetCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let blendOption: String
    public let labelRatio: String
    public let labelRatioValues: VariNPKRatio?
    public let npkFullBags: Int
    public let bagSizeKg: Double
    public let ageAdjustedExactBagsFarmYear: Double?
    public let ageAdjustedExactKgFarmYear: Double?
    public let npkCostRp: Double
    public let zoneTopupCostRp: Double
    public let combinedCostRp: Double
    public let budgetTargetRp: Double
    public let budgetDifferenceRp: Double
    public let isClosest: Bool

    public var explicitNPKType: ContractFertilizerType? {
        labelRatioValues?.toExplicitContractNPKType()
    }

    /// Plantation-wide annual recommended NPK mass (kg), rounded to the nearest 0.5 kg.
    public var recommendedAnnualKgFarm: Double? {
        if let exactKg = ageAdjustedExactKgFarmYear, exactKg.isFinite, exactKg > 0 {
            return VariDoseRounding.roundToHalfKg(exactKg)
        }
        if npkFullBags > 0, bagSizeKg > 0 {
            return Double(npkFullBags) * bagSizeKg
        }
        return nil
    }

    public init(
        id: String,
        blendOption: String,
        labelRatio: String,
        labelRatioValues: VariNPKRatio? = nil,
        npkFullBags: Int,
        bagSizeKg: Double = 50.0,
        ageAdjustedExactBagsFarmYear: Double? = nil,
        ageAdjustedExactKgFarmYear: Double? = nil,
        npkCostRp: Double,
        zoneTopupCostRp: Double,
        combinedCostRp: Double,
        budgetTargetRp: Double,
        budgetDifferenceRp: Double,
        isClosest: Bool
    ) {
        self.id = id
        self.blendOption = blendOption
        self.labelRatio = labelRatio
        self.labelRatioValues = labelRatioValues
        self.npkFullBags = npkFullBags
        self.bagSizeKg = bagSizeKg
        self.ageAdjustedExactBagsFarmYear = ageAdjustedExactBagsFarmYear
        self.ageAdjustedExactKgFarmYear = ageAdjustedExactKgFarmYear
        self.npkCostRp = npkCostRp
        self.zoneTopupCostRp = zoneTopupCostRp
        self.combinedCostRp = combinedCostRp
        self.budgetTargetRp = budgetTargetRp
        self.budgetDifferenceRp = budgetDifferenceRp
        self.isClosest = isClosest
    }
}

/// Comprehensive budget recap matching commercial NPK blends and zone Mg/Urea top-ups.
public struct VariBudgetSummary: Sendable, Equatable {
    public let targetBudgetRp: Double?
    public let zoneTopupCostRp: Double?
    public let closestOption: String?
    public let candidates: [VariBudgetCandidate]

    public init(
        targetBudgetRp: Double? = nil,
        zoneTopupCostRp: Double? = nil,
        closestOption: String? = nil,
        candidates: [VariBudgetCandidate] = []
    ) {
        self.targetBudgetRp = targetBudgetRp
        self.zoneTopupCostRp = zoneTopupCostRp
        self.closestOption = closestOption
        self.candidates = candidates
    }
}

/// File URLs for all generated visual maps, CSVs, plots, and JSON payloads.
public struct VariAssetURLs: Sendable, Equatable {
    public let sourceImageURL: URL?
    public let annotatedMapURL: URL?
    public let whiteSeparatorsWithNumbersURL: URL?
    public let quartilesMapURL: URL?
    public let heatmapMontageURL: URL?
    public let pipelinePlotURL: URL?
    public let variDistributionPlotURL: URL?
    public let zoneSummaryCSVURL: URL?
    public let fertilizerMassCSVURL: URL?
    public let oilPalmZonesJSONURL: URL?

    public init(
        sourceImageURL: URL? = nil,
        annotatedMapURL: URL? = nil,
        whiteSeparatorsWithNumbersURL: URL? = nil,
        quartilesMapURL: URL? = nil,
        heatmapMontageURL: URL? = nil,
        pipelinePlotURL: URL? = nil,
        variDistributionPlotURL: URL? = nil,
        zoneSummaryCSVURL: URL? = nil,
        fertilizerMassCSVURL: URL? = nil,
        oilPalmZonesJSONURL: URL? = nil
    ) {
        self.sourceImageURL = sourceImageURL
        self.annotatedMapURL = annotatedMapURL
        self.whiteSeparatorsWithNumbersURL = whiteSeparatorsWithNumbersURL
        self.quartilesMapURL = quartilesMapURL
        self.heatmapMontageURL = heatmapMontageURL
        self.pipelinePlotURL = pipelinePlotURL
        self.variDistributionPlotURL = variDistributionPlotURL
        self.zoneSummaryCSVURL = zoneSummaryCSVURL
        self.fertilizerMassCSVURL = fertilizerMassCSVURL
        self.oilPalmZonesJSONURL = oilPalmZonesJSONURL
    }
}

/// Represents the business domain result of a VARI & vegetation health analysis.
public struct VariScanResult: Sendable, Identifiable {
    public let id: UUID
    public let resultJSONURL: URL
    public let treeCount: Int
    public let zoneCount: Int
    public let referenceMeanVari: Double?
    public let imageWidthPx: Int?
    public let imageHeightPx: Int?
    public let createdAt: Date

    // Rich domain models for Iteration 2
    public let summary: VariSummary?
    public let zones: [VariZoneDetail]
    public let products: [VariProductRow]
    public let userBlend: VariUserBlendSummary?
    public let budget: VariBudgetSummary?
    public let assets: VariAssetURLs

    public init(
        id: UUID = UUID(),
        resultJSONURL: URL,
        treeCount: Int,
        zoneCount: Int,
        referenceMeanVari: Double? = nil,
        imageWidthPx: Int? = nil,
        imageHeightPx: Int? = nil,
        createdAt: Date = Date(),
        summary: VariSummary? = nil,
        zones: [VariZoneDetail] = [],
        products: [VariProductRow] = [],
        userBlend: VariUserBlendSummary? = nil,
        budget: VariBudgetSummary? = nil,
        assets: VariAssetURLs = VariAssetURLs()
    ) {
        self.id = id
        self.resultJSONURL = resultJSONURL
        self.treeCount = treeCount
        self.zoneCount = zoneCount
        self.referenceMeanVari = referenceMeanVari
        self.imageWidthPx = imageWidthPx
        self.imageHeightPx = imageHeightPx
        self.createdAt = createdAt
        self.summary = summary
        self.zones = zones
        self.products = products
        self.userBlend = userBlend
        self.budget = budget
        self.assets = assets
    }
}

/// Abstract contract for performing and managing VARI analyses.
/// Decouples UI and business workflows from underlying subprocesses, Python helpers, or file formats.
public protocol VariProcessing: Sendable {
    /// Verifies whether the embedded VARI engine is installed and operational.
    func checkEngine() async throws -> String

    /// Processes an orthomosaic or aerial photo and yields a domain result.
    func process(
        photoURL: URL,
        submission: VariEngineSubmissionRequest?,
        outputFolder: URL?
    ) async throws -> VariScanResult

    /// Loads a previously cached VARI scan result from an orthomosaic project output folder, if present.
    func loadCachedResult(from folder: URL) throws -> VariScanResult?
}
