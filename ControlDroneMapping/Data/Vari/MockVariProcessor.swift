import Foundation

/// Mock implementation of VariProcessing for SwiftUI previews and demo mode.
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
            let xOffset = Double((idx - 1) % 3) * 600.0
            let yOffset = Double((idx - 1) / 3) * 800.0
            let trees: [VariTreeDetection] = (1...2).map { treeIdx in
                let tx = xOffset + 40.0 + Double(treeIdx - 1) * 160.0
                let ty = yOffset + 40.0
                return VariTreeDetection(
                    id: (idx - 1) * 10 + treeIdx,
                    zoneID: idx,
                    boundingBox: VariPixelBox(x1: tx, y1: ty, x2: tx + 140.0, y2: ty + 140.0)
                )
            }
            return VariZoneDetail(
                zoneID: idx,
                approxRow: (idx - 1) / 3 + 1,
                treeCount: trees.count,
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
                boundingBox: VariPixelBox(
                    x1: xOffset + 10.0,
                    y1: yOffset + 10.0,
                    x2: xOffset + 550.0,
                    y2: yOffset + 750.0
                ),
                trees: trees,
                baseImageCropURL: nil,
                exgImageCropURL: nil
            )
        }

        let sampleProducts: [VariProductRow] = [
            VariProductRow(
                id: "z1_dolomite",
                zoneID: 1,
                zoneLabel: "Z1",
                productName: "dolomite_Mg_cheaper",
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
                productName: "urea_N_expensive",
                nutrientType: "N",
                supplementKg: 4.2,
                baseProductKg: 0.0,
                combinedKg: 4.2,
                estimatedBags: 0.08,
                fullBagsNeeded: 1
            ),
        ]

        let sampleCandidates: [VariBudgetCandidate] = [
            VariBudgetCandidate(
                id: "opt_1",
                blendOption: "Reference-style 13-6-27-4",
                labelRatio: "13.0-6.0-27.0-4.0",
                labelRatioValues: VariNPKRatio(n: 13, p2o5: 6, k2o: 27, mgo: 4),
                npkFullBags: 9,
                bagSizeKg: 50.0,
                ageAdjustedExactBagsFarmYear: 9.0,
                ageAdjustedExactKgFarmYear: 450.0,
                npkCostRp: 4_950_000,
                zoneTopupCostRp: 600_000,
                combinedCostRp: 5_550_000,
                budgetTargetRp: 5_000_000,
                budgetDifferenceRp: 550_000,
                isClosest: true
            ),
            VariBudgetCandidate(
                id: "opt_2",
                blendOption: "Current blend",
                labelRatio: "15.0-15.0-15.0-0.0",
                labelRatioValues: VariNPKRatio(n: 15, p2o5: 15, k2o: 15, mgo: 0),
                npkFullBags: 9,
                bagSizeKg: 50.0,
                ageAdjustedExactBagsFarmYear: 8.67,
                ageAdjustedExactKgFarmYear: 433.5,
                npkCostRp: 6_660_000,
                zoneTopupCostRp: 600_000,
                combinedCostRp: 7_260_000,
                budgetTargetRp: 5_000_000,
                budgetDifferenceRp: 2_260_000,
                isClosest: false
            ),
        ]

        return VariScanResult(
            resultJSONURL: url,
            treeCount: 12,
            zoneCount: 6,
            referenceMeanVari: 0.48,
            imageWidthPx: 1950,
            imageHeightPx: 1664,
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
            userBlend: VariUserBlendSummary(
                ratio: VariNPKRatio(n: 15, p2o5: 15, k2o: 15, mgo: 0),
                bagSizeKg: 50.0,
                farmAreaHaUsed: 1.0,
                npkProductKgFarmPerYear: 45.0,
                dosePerTreeKgPerApplication: 0.5,
                applicationsPerYear: 2.0
            ),
            budget: VariBudgetSummary(
                targetBudgetRp: 5_000_000,
                zoneTopupCostRp: 600_000,
                closestOption: "Reference-style 13-6-27-4",
                candidates: sampleCandidates
            ),
            assets: VariAssetURLs()
        )
    }
}
