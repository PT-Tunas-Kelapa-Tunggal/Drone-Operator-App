import CloudKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct FertilizerCostPredictionTests {
    static func check(_ condition: Bool, line: Int = #line) {
        if !condition { fatalError("Failed check at line \(line)") }
    }
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let box: [String: Any] = ["x1": 0, "y1": 0, "x2": 10, "y2": 10]
        let perZone = 0.08504374435229205
        let perTree = 0.021260936088073012
        var ranking: [String: Any] = [
            "blend_option": "Reference-style 12-6-22-3",
            "composition_label_percent_n_p2o5_k2o_mgo": ["N": 12, "P2O5": 6, "K2O": 22, "MgO": 3],
            "age_adjusted_full_bags_farm_year": 24,
            // Different from 24 × 50 so the test detects recalculation instead of copying.
            "total_kg": 1234.5,
            "npk_full_bag_cost_farm_year_rp": 15_120_000,
            "npk_full_bag_cost_farm_per_year": 999,
        ]
        let estimate: [String: Any] = [
            "blend_option": "Reference-style 12-6-22-3",
            "label_percent_n_p2o5_k2o_mgo": ["N": 12, "P2O5": 6, "K2O": 22, "MgO": 3],
            "age_adjusted_full_bag_cost_rp_per_ha_year": 888,
            "baseline_full_bag_cost_rp_per_ha_year": 777,
        ]
        func parse(
            ranked: [String: Any], candidateTable: Bool = false, estimates: Bool = true,
            additionalRanked: [[String: Any]] = [], treeValue: Any? = perTree,
            breakdown: [[String: Any]] = [], includeNPKAnalysis: Bool = true
        ) throws -> VariScanResult {
            var product: [String: Any] = [
                "zone_id": 1, "product": "dolomite_Mg_cheaper", "nutrient": "Mg",
                "base_plus_supplement_product_kg_per_zone_per_year": perZone,
                "base_product_kg_per_zone_per_year": 8.0,
            ]
            product["base_plus_supplement_product_kg_per_palm_per_year"] = treeValue
            var analysis: [String: Any] = [
                "closest_to_budget_ranking": ["ranked_options": [ranked] + additionalRanked],
                "selected_zone_topup_cost_idr": 200,
            ]
            if candidateTable {
                analysis["candidate_comparison_table"] = [
                    [
                        "blend_option": "Reference-style 12-6-22-3", "label_ratio": "12-6-22-3",
                        "npk_full_bags": 24, "npk_cost_rp": 666,
                    ]
                ]
            } else if estimates {
                analysis["blend_purchase_price_estimates"] = [estimate]
            }
            var combinedCalculations: [String: Any] = [
                "annual_npk_budget_matching": ["selected_zone_mg_urea_cost_breakdown": breakdown]
            ]
            if includeNPKAnalysis {
                combinedCalculations["field_wide_npk_baseline_comparison"] = analysis
            }
            let json: [String: Any] = [
                "image": ["trees": 4, "width": 10, "height": 10],
                "zones": [
                    [
                        "zone_id": 1, "tree_count": 4, "bbox": box,
                        "trees": [["tree_id": 1, "bbox": box]],
                    ]
                ],
                "fertilizer_product_mass_conversions": [product],
                "combined_fertilizer_calculations": combinedCalculations,
            ]
            let url = folder.appendingPathComponent("vari_result.json")
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            return try LocalVariProcessor.parseScanResult(from: url, in: folder)
        }

        let context = CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = context.makeImage()!
        for name in [
            "orthomosaic.jpeg", "oil_palm_zones_plain_with_separator.jpg",
            "oil_palm_field_tree_vari_quartiles.jpg",
        ] {
            let destination = CGImageDestinationCreateWithURL(
                folder.appendingPathComponent(name) as CFURL,
                UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            check(CGImageDestinationFinalize(destination))
        }
        let result = try parse(ranked: ranking)
        let dolomite: [String: Any] = [
            "product_key": "dolomite_Mg_cheaper", "full_bags_to_buy": 13,
            "bag_size_kg": 50, "full_bag_purchase_cost_rp": 1_300_000,
            "field_total_product_kg_year": 603.1057,
        ]
        let urea: [String: Any] = [
            "product": "urea_N_expensive", "full_bags_to_buy": 1,
            "bag_size_kg": 25.5, "full_bag_purchase_cost_rp": 500_000,
        ]
        let ignoredProduct: [String: Any] = [
            "product_key": "kieserite_Mg_expensive", "full_bags_to_buy": 99,
            "bag_size_kg": 50, "full_bag_purchase_cost_rp": 999,
        ]
        let withSupplements = try parse(
            ranked: ranking, breakdown: [dolomite, urea, ignoredProduct, dolomite])
        check(withSupplements.fertilizerCostPredictions.count == 3)
        check(withSupplements.fertilizerCostPredictions[.dolomite]!.totalBagsPerYear == 13)
        check(withSupplements.fertilizerCostPredictions[.dolomite]!.totalKgPerYear == 650)
        check(withSupplements.fertilizerCostPredictions[.dolomite]!.totalPricePerYearRp == 1_300_000)
        check(withSupplements.fertilizerCostPredictions[.urea]!.totalKgPerYear == 25.5)
        let supplementsOnly = try parse(
            ranked: ranking, breakdown: [dolomite, urea], includeNPKAnalysis: false)
        check(supplementsOnly.fertilizerCostPredictions.count == 2)
        var invalidSupplement = dolomite
        invalidSupplement["full_bags_to_buy"] = 1.5
        check(
            try parse(ranked: ranking, breakdown: [invalidSupplement]).fertilizerCostPredictions[.dolomite]
                == nil)
        invalidSupplement["full_bags_to_buy"] = -1
        check(
            try parse(ranked: ranking, breakdown: [invalidSupplement]).fertilizerCostPredictions[.dolomite]
                == nil)
        invalidSupplement = dolomite
        invalidSupplement.removeValue(forKey: "bag_size_kg")
        check(
            try parse(ranked: ranking, breakdown: [invalidSupplement]).fertilizerCostPredictions[.dolomite]!
                .totalKgPerYear == nil)
        invalidSupplement["bag_size_kg"] = 0
        check(
            try parse(ranked: ranking, breakdown: [invalidSupplement]).fertilizerCostPredictions[.dolomite]!
                .totalKgPerYear == nil)
        invalidSupplement["full_bag_purchase_cost_rp"] = NSNull()
        check(
            try parse(ranked: ranking, breakdown: [invalidSupplement]).fertilizerCostPredictions[.dolomite]!
                .totalPricePerYearRp == nil)
        check(abs(result.products[0].fertilizerAmountPerTreeKgPerYear! - perTree) < 1e-12)
        check(result.budget!.candidates[0].npkCostRp == 15_120_000)
        check(result.budget!.candidates[0].combinedCostRp == 15_120_200)
        let prediction = result.fertilizerCostPredictions[.npk12_6_22_3]!
        check(prediction.totalBagsPerYear == 24)
        check(prediction.totalKgPerYear == 1234.5)
        check(prediction.totalPricePerYearRp == 15_120_000)
        var missingKg = ranking
        missingKg.removeValue(forKey: "total_kg")
        check(try parse(ranked: missingKg).fertilizerCostPredictions[.npk12_6_22_3]!.totalKgPerYear == nil)
        missingKg["total_kg"] = NSNull()
        check(try parse(ranked: missingKg).fertilizerCostPredictions[.npk12_6_22_3]!.totalKgPerYear == nil)
        missingKg["total_kg"] = -1
        check(try parse(ranked: missingKg).fertilizerCostPredictions[.npk12_6_22_3]!.totalKgPerYear == nil)
        missingKg["total_kg"] = 0
        check(try parse(ranked: missingKg).fertilizerCostPredictions[.npk12_6_22_3]!.totalKgPerYear == 0)
        let rankedOnly = try parse(ranked: ranking, estimates: false)
        check(rankedOnly.budget!.candidates.isEmpty)
        check(rankedOnly.fertilizerCostPredictions == result.fertilizerCostPredictions)
        var secondOption = ranking
        secondOption["blend_option"] = "Reference-style 16-16-16"
        secondOption["composition_label_percent_n_p2o5_k2o_mgo"] = ["N": 16, "P2O5": 16, "K2O": 16, "MgO": 0]
        let multiple = try parse(ranked: ranking, additionalRanked: [secondOption, ranking])
        check(multiple.fertilizerCostPredictions.count == 2)
        var unsupported = ranking
        unsupported["composition_label_percent_n_p2o5_k2o_mgo"] = ["N": 12, "P2O5": 12, "K2O": 12, "MgO": 0]
        check(try parse(ranked: unsupported).fertilizerCostPredictions.isEmpty)
        var invalidBags = ranking
        invalidBags["age_adjusted_full_bags_farm_year"] = 24.5
        check(try parse(ranked: invalidBags).fertilizerCostPredictions.isEmpty)
        invalidBags["age_adjusted_full_bags_farm_year"] = -1
        check(try parse(ranked: invalidBags).fertilizerCostPredictions.isEmpty)
        invalidBags.removeValue(forKey: "age_adjusted_full_bags_farm_year")
        check(try parse(ranked: invalidBags).fertilizerCostPredictions.isEmpty)
        check(try parse(ranked: ranking, candidateTable: true).budget!.candidates[0].npkCostRp == 15_120_000)
        ranking["npk_full_bag_cost_farm_year_rp"] = NSNull()
        check(try parse(ranked: ranking).budget!.candidates[0].npkCostRp == 0)
        let nullPrice = try parse(ranked: ranking)
        check(nullPrice.fertilizerCostPredictions[.npk12_6_22_3]!.totalPricePerYearRp == nil)
        ranking.removeValue(forKey: "npk_full_bag_cost_farm_year_rp")
        check(try parse(ranked: ranking, candidateTable: true).budget!.candidates[0].npkCostRp == 0)
        check(try parse(ranked: ranking).fertilizerCostPredictions[.npk12_6_22_3]!.totalPricePerYearRp == nil)
        ranking["npk_full_bag_cost_farm_year_rp"] = 0
        check(try parse(ranked: ranking).fertilizerCostPredictions[.npk12_6_22_3]!.totalPricePerYearRp == 0)
        ranking["npk_full_bag_cost_farm_year_rp"] = -1
        check(try parse(ranked: ranking).fertilizerCostPredictions[.npk12_6_22_3]!.totalPricePerYearRp == nil)
        check(try parse(ranked: ranking, treeValue: nil).products[0].fertilizerAmountPerTreeKgPerYear == nil)
        check(
            try parse(ranked: ranking, treeValue: NSNull()).products[0].fertilizerAmountPerTreeKgPerYear
                == nil)

        let request = PlantationReviewRequest(
            farmer: FarmerContact(name: "Test", phone: "", address: ""),
            garden: GardenSummary(id: UUID(), name: "Test", locationName: "", areaHectares: 1),
            boundary: [CoordinatePoint(latitude: 1, longitude: 104)],
            agronomy: AgronomicProfile(
                plantingYear: 2020, soilType: .mineral,
                fertilizingFrequencyPerYear: 3, fertilizationBudgetPerHa: 100000)
        )
        let scheduleData = Data(
            """
            {"schema_version":"1.0","plan_year":2026,"today":"2026-11-17","rounds_per_year":1,
             "rounds":[{"round":1,"start_month":11,"start_month_name":"November","end_month":12,
             "end_month_name":"December","start_date":"2026-11-17","end_date":"2026-12-01",
             "status":"active","total_days":15,"card":{"state":"active"},"steps":[]}],
             "weather_basis":{"rule":"test","months":{},"candidate_sets":[],"note":"test"}}
            """.utf8)
        let timing = VariTimingExecutionResult(
            request: VariTimingRequest(latitude: 1, longitude: 104, fertilizerFreq: 1, fertilizers: []),
            schedule: try JSONDecoder().decode(VariTimingSchedule.self, from: scheduleData),
            requestJSONURL: folder, resultJSONURL: folder, cacheDirectoryURL: folder, ranAt: Date()
        )
        let payload = try CloudKitReviewDispatchBuilder.makeDispatchPayload(
            request: request, orthomosaicJPEGURL: folder.appendingPathComponent("orthomosaic.jpeg"),
            variResult: result, timingResult: timing
        )
        let zoneNeed = payload.writer.fertilizerNeedPerZone!.first { $0.zoneId == 1 }!
        check(zoneNeed.recommendedDosagePerZonePerYear == result.products[0].supplementKg)
        check(
            zoneNeed.recommendedDosagePerTreePerZonePerYear
                == result.products[0].fertilizerAmountPerTreeKgPerYear)
        let generalNeed = payload.writer.fertilizerNeedPerZone!.first { $0.zoneId == nil }!
        check(generalNeed.recommendedDosagePerZonePerYear == 1200)
        check(generalNeed.recommendedDosagePerTreePerZonePerYear == nil)
        let record = try payload.writer.buildRecord()
        let costKey = RecordKeys.MacOSOwned.fertilizerCostPredictions
        check(costKey == "fertilizer_cost_predictions")
        check(RecordKeys.MacOSOwned.allKeys.contains(costKey))
        check(!RecordKeys.iOSOwned.allKeys.contains(costKey))
        let costRaw = record[costKey] as! String
        let costEnvelope = try JSONSerialization.jsonObject(with: Data(costRaw.utf8)) as! [String: Any]
        check(costEnvelope["version"] as? String == "1.0.0")
        let costObject = costEnvelope["payload"] as! [String: [String: Any]]
        check(costObject.count == 1)
        check((costObject["NPK-12-6-22-3"]!["total_bags_needed"] as! Int) == 24)
        check((costObject["NPK-12-6-22-3"]!["total_kg"] as! Double) == 1234.5)
        check((costObject["NPK-12-6-22-3"]!["total_cost"] as! Double) == 15_120_000)
        check(costObject["NPK-12-6-22-3"]!["age_adjusted_full_bags_farm_year"] == nil)
        check(costObject["NPK-12-6-22-3"]!["npk_full_bag_cost_farm_year_rp"] == nil)
        let restored = try ScanRequestRecord(record).fertilizerCostPredictions().get()
        check(restored.byFertilizer[.npk12_6_22_3]!.totalKg == 1234.5)
        check(restored == payload.writer.fertilizerCostPredictions!)
        check(payload.summaryResult.fertilizerCostPredictions == restored)
        check(PlantationDomainMapper().toDomain(from: record).result!.fertilizerCostPredictions == restored)
        let supplementsPayload = try CloudKitReviewDispatchBuilder.makeDispatchPayload(
            request: request, orthomosaicJPEGURL: folder.appendingPathComponent("orthomosaic.jpeg"),
            variResult: withSupplements, timingResult: timing
        )
        let supplementsRecord = try supplementsPayload.writer.buildRecord()
        let supplementsRaw = supplementsRecord[costKey] as! String
        let supplementsEnvelope =
            try JSONSerialization.jsonObject(with: Data(supplementsRaw.utf8)) as! [String: Any]
        let supplementsObject = supplementsEnvelope["payload"] as! [String: [String: Any]]
        check(supplementsObject.count == 3)
        for (name, bags, kg, cost) in [("Dolomite", 13, 650.0, 1_300_000.0), ("Urea", 1, 25.5, 500_000.0)] {
            check(supplementsObject[name]!["total_bags_needed"] as? Int == bags)
            check(supplementsObject[name]!["total_kg"] as? Double == kg)
            check(supplementsObject[name]!["total_cost"] as? Double == cost)
        }
        check(
            try ScanRequestRecord(supplementsRecord).fertilizerCostPredictions().get() == supplementsPayload
                .writer.fertilizerCostPredictions!)
        let nullPayload = try CloudKitReviewDispatchBuilder.makeDispatchPayload(
            request: request, orthomosaicJPEGURL: folder.appendingPathComponent("orthomosaic.jpeg"),
            variResult: nullPrice, timingResult: timing
        )
        let nullRecord = try nullPayload.writer.buildRecord()
        let nullRaw = nullRecord[costKey] as! String
        let nullEnvelope = try JSONSerialization.jsonObject(with: Data(nullRaw.utf8)) as! [String: Any]
        let nullObject = nullEnvelope["payload"] as! [String: [String: Any]]
        check(nullObject["NPK-12-6-22-3"]!["total_cost"] is NSNull)
        check(
            try ScanRequestRecord(nullRecord).fertilizerCostPredictions().get().byFertilizer[.npk12_6_22_3]!
                .totalCost == nil)
        let unsupportedShapeRecord = CKRecord(recordType: RecordKeys.recordType)
        unsupportedShapeRecord[costKey] = """
            {"version":"1.0.0","payload":{"NPK-12-6-22-3":{"age_adjusted_full_bags_farm_year":24,"npk_full_bag_cost_farm_year_rp":15120000}}}
            """ as CKRecordValue
        if case .failure = ScanRequestRecord(unsupportedShapeRecord).fertilizerCostPredictions() {
        } else {
            fatalError("ML-oriented CloudKit entry names must not be decoded")
        }
        let raw = record[RecordKeys.MacOSOwned.fertilizerNeedPerZone] as! String
        let envelope = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        let items = envelope["payload"] as! [[String: Any]]
        let encodedZone = items.first { ($0["zone_id"] as? NSNumber)?.intValue == 1 }!
        check(abs((encodedZone["recommended_dosage"] as! Double) - perZone) < 1e-12)
        check(
            abs((encodedZone["recommended_dosage_per_tree_per_zone_per_year"] as! Double) - perTree) < 1e-12)
        check(encodedZone["recommendedDosagePerZonePerYear"] == nil)
        check(encodedZone["recommended_dosage_per_zone_per_year"] == nil)
        let decoded = try JSONDecoder().decode(JSONEnvelope<[FertilizerNeedItem]>.self, from: Data(raw.utf8))
        check(decoded.payload == payload.writer.fertilizerNeedPerZone!)
        let oldData = Data(
            """
            {"fertilizer_application_type":"zone_specific","fertilizer_type":"Dolomite",
             "recommended_dosage":8,"dosage_unit":"kg","current_dosage":0,"zone_id":1}
            """.utf8)
        let oldItem = try JSONDecoder().decode(FertilizerNeedItem.self, from: oldData)
        check(oldItem.recommendedDosagePerZonePerYear == 8)
        check(oldItem.recommendedDosagePerTreePerZonePerYear == nil)
        let oldRecord = CKRecord(recordType: RecordKeys.recordType)
        if case .failure(.missing(let key)) = ScanRequestRecord(oldRecord).fertilizerCostPredictions() {
            check(key == costKey)
        } else {
            fatalError("Expected missing field on old record")
        }
        let oldDomain = PlantationDomainMapper().toDomain(from: oldRecord)
        check(oldDomain.fieldErrors[costKey] == nil)
        record[costKey] = """
            {"version":"1.0.0","payload":{"Unknown fertilizer":{"total_bags_needed":1,"total_cost":10}}}
            """ as CKRecordValue
        if case .failure = ScanRequestRecord(record).fertilizerCostPredictions() {
        } else {
            fatalError("Unknown fertilizer keys must return a field error")
        }
        check(PlantationDomainMapper().toDomain(from: record).fieldErrors[costKey] != nil)
        record[costKey] = costRaw as CKRecordValue
        record[RecordKeys.iOSOwned.farmName] = "Farmer input" as CKRecordValue
        try MacOSScanRequestRecordWriter().applyToRecord(record)
        check(record[costKey] as? String == costRaw)
        try MacOSScanRequestRecordWriter(fertilizerCostPredictions: FertilizerCostPredictions())
            .applyToRecord(record)
        check(try ScanRequestRecord(record).fertilizerCostPredictions().get().byFertilizer.isEmpty)
        check(record[RecordKeys.iOSOwned.farmName] as? String == "Farmer input")
        print(
            "PASS: ML predictions, enum-keyed CloudKit object, null prices, field ownership, old records, and dosage regression"
        )
    }
}
