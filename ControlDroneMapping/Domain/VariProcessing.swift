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

/// A commercial NPK blend candidate compared against the farmer's entered budget.
public struct VariBudgetCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let blendOption: String
    public let labelRatio: String
    public let npkFullBags: Int
    public let npkCostRp: Double
    public let zoneTopupCostRp: Double
    public let combinedCostRp: Double
    public let budgetTargetRp: Double
    public let budgetDifferenceRp: Double
    public let isClosest: Bool

    public init(
        id: String,
        blendOption: String,
        labelRatio: String,
        npkFullBags: Int,
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
        self.npkFullBags = npkFullBags
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
    public let createdAt: Date

    // Rich domain models for Iteration 2
    public let summary: VariSummary?
    public let zones: [VariZoneDetail]
    public let products: [VariProductRow]
    public let budget: VariBudgetSummary?
    public let assets: VariAssetURLs

    public init(
        id: UUID = UUID(),
        resultJSONURL: URL,
        treeCount: Int,
        zoneCount: Int,
        referenceMeanVari: Double? = nil,
        createdAt: Date = Date(),
        summary: VariSummary? = nil,
        zones: [VariZoneDetail] = [],
        products: [VariProductRow] = [],
        budget: VariBudgetSummary? = nil,
        assets: VariAssetURLs = VariAssetURLs()
    ) {
        self.id = id
        self.resultJSONURL = resultJSONURL
        self.treeCount = treeCount
        self.zoneCount = zoneCount
        self.referenceMeanVari = referenceMeanVari
        self.createdAt = createdAt
        self.summary = summary
        self.zones = zones
        self.products = products
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

    /// Legacy overload for backward compatibility with existing tests and previews.
    func process(
        photoURL: URL,
        plotID: String?,
        outputFolder: URL?
    ) async throws -> VariScanResult

    /// Loads a previously cached VARI scan result from an orthomosaic project output folder, if present.
    func loadCachedResult(from folder: URL) throws -> VariScanResult?
}

extension VariProcessing {
    public func process(
        photoURL: URL,
        plotID: String?,
        outputFolder: URL?
    ) async throws -> VariScanResult {
        try await process(
            photoURL: photoURL,
            submission: VariEngineSubmissionRequest.defaultSample(farmName: plotID ?? "Kebun Kelapa Sawit"),
            outputFolder: outputFolder
        )
    }
}
