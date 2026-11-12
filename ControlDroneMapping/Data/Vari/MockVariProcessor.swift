import Foundation

/// Mock implementation of VariProcessing for SwiftUI previews, testing, and offline demo.
public final class MockVariProcessor: VariProcessing, @unchecked Sendable {
    public var shouldThrowError: Error?
    public var mockResult: VariScanResult?

    public init(shouldThrowError: Error? = nil, mockResult: VariScanResult? = nil) {
        self.shouldThrowError = shouldThrowError
        self.mockResult = mockResult
    }

    public func checkEngine() async throws -> String {
        if let shouldThrowError { throw shouldThrowError }
        return "VARI engine siap (Demo Mode)"
    }

    public func process(
        photoURL: URL,
        submission: VariEngineSubmissionRequest? = nil,
        outputFolder: URL? = nil
    ) async throws -> VariScanResult {
        if let shouldThrowError { throw shouldThrowError }
        if let mockResult { return mockResult }

        // Simulate calculation delay
        try await Task.sleep(nanoseconds: 600_000_000)

        let targetDir = outputFolder ?? FileManager.default.temporaryDirectory
        let mockURL = targetDir.appendingPathComponent("vari_result.json")

        return Self.sampleResult(at: mockURL)
    }

    public func loadCachedResult(from folder: URL) throws -> VariScanResult? {
        let cachedURL = folder.appendingPathComponent("vari_result.json")
        guard FileManager.default.fileExists(atPath: cachedURL.path) else {
            return nil
        }
        return mockResult ?? Self.sampleResult(at: cachedURL)
    }

    public static func sampleResult(at url: URL = URL(fileURLWithPath: "/tmp/vari_result.json")) -> VariScanResult {
        let sampleZones: [VariZoneDetail] = (1...6).map { idx in
            VariZoneDetail(
                zoneID: idx,
                approxRow: (idx - 1) / 3 + 1,
                treeCount: 22,
                meanVari: 0.35 + Double(idx) * 0.03,
                medianVari: 0.34 + Double(idx) * 0.03,
                minVari: 0.12,
                maxVari: 0.65,
                stdVari: 0.08,
                confidence: 0.92,
                boostMode: idx <= 2 ? "blanket_p25" : "zone_specific",
                areaHa: 0.18,
                mgSupplementKg: 4.2 * Double(idx),
                nSupplementKg: 2.1 * Double(idx),
                baseImageCropURL: nil,
                exgImageCropURL: nil
            )
        }

        let sampleProducts: [VariProductRow] = [
            VariProductRow(
                id: "z1_dolomite",
                zoneID: 1,
                zoneLabel: "Z1",
                productName: "Dolomite",
                nutrientType: "Mg",
                supplementKg: 8.4,
                baseProductKg: 22.0,
                combinedKg: 30.4,
                estimatedBags: 0.61,
                fullBagsNeeded: 1
            ),
            VariProductRow(
                id: "z1_urea",
                zoneID: 1,
                zoneLabel: "Z1",
                productName: "Urea",
                nutrientType: "N",
                supplementKg: 4.2,
                baseProductKg: 11.0,
                combinedKg: 15.2,
                estimatedBags: 0.30,
                fullBagsNeeded: 1
            ),
            VariProductRow(
                id: "total_dolomite",
                zoneID: nil,
                zoneLabel: "Total Lapangan",
                productName: "Dolomite",
                nutrientType: "Mg",
                supplementKg: 52.8,
                baseProductKg: 132.0,
                combinedKg: 184.8,
                estimatedBags: 3.70,
                fullBagsNeeded: 4
            )
        ]

        let sampleCandidates: [VariBudgetCandidate] = [
            VariBudgetCandidate(
                id: "opt_1",
                blendOption: "13-6-27-4+0.65B",
                labelRatio: "13-6-27-4",
                npkFullBags: 8,
                npkCostRp: 3_200_000,
                zoneTopupCostRp: 1_400_000,
                combinedCostRp: 4_600_000,
                budgetTargetRp: 5_000_000,
                budgetDifferenceRp: -400_000,
                isClosest: true
            ),
            VariBudgetCandidate(
                id: "opt_2",
                blendOption: "12-12-17-2+TE",
                labelRatio: "12-12-17-2",
                npkFullBags: 10,
                npkCostRp: 4_100_000,
                zoneTopupCostRp: 1_400_000,
                combinedCostRp: 5_500_000,
                budgetTargetRp: 5_000_000,
                budgetDifferenceRp: 500_000,
                isClosest: false
            )
        ]

        return VariScanResult(
            resultJSONURL: url,
            treeCount: 132,
            zoneCount: 6,
            referenceMeanVari: 0.48,
            createdAt: Date(),
            summary: VariSummary(
                referenceZoneIDs: [5, 6],
                referenceFallbackAllZones: false,
                p25ZoneMeanVari: 0.38,
                referenceZoneMeanVari: 0.48,
                p95P25VariGap: 0.14,
                boostMode: "zone_specific",
                blanketVariGapCutoff: 0.05,
                overallFieldConfidence: 0.94
            ),
            zones: sampleZones,
            products: sampleProducts,
            budget: VariBudgetSummary(
                targetBudgetRp: 5_000_000,
                zoneTopupCostRp: 1_400_000,
                closestOption: "13-6-27-4+0.65B",
                candidates: sampleCandidates
            ),
            assets: VariAssetURLs()
        )
    }
}
