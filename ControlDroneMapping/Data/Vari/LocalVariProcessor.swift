import Foundation
import ImageIO

/// Executes the bundled VariEngine to process an image into VARI and nutrient analysis.
public struct LocalVariProcessor: VariProcessing {
    public init() {}

    public func checkEngine() async throws -> String {
        try BundledVariEngine.check()
    }

    public func process(
        photoURL: URL,
        submission: VariEngineSubmissionRequest? = nil,
        outputFolder: URL? = nil
    ) async throws -> VariScanResult {
        try BundledVariEngine.validateEmbedded()
        guard let helper = BundledVariEngine.helperExecutable else {
            throw MappingError.invalid("Helper binary VariPython tidak ditemukan.")
        }

        let destinationFolder =
            outputFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("VariScans")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        guard photoURL.isFileURL, FileManager.default.fileExists(atPath: photoURL.path) else {
            throw MappingError.invalid("Berkas citra tidak ditemukan di: \(photoURL.path)")
        }

        let effectiveImageURL: URL
        let ext = photoURL.pathExtension.lowercased()
        if ext == "tif" || ext == "tiff" {
            let targetJPEGURL = photoURL.deletingPathExtension().appendingPathExtension("jpeg")
            effectiveImageURL = try TIFFToJPEGConverter.convert(
                from: photoURL,
                to: targetJPEGURL,
                quality: 0.5 // somehow this value is the closest and produce best result
            )
        } else if ext == "jpeg" || ext == "jpg" {
            guard let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0 else {
                throw MappingError.invalid("Berkas JPEG rusak atau tidak dapat dibaca: \(photoURL.lastPathComponent)")
            }
            effectiveImageURL = photoURL
        } else {
            throw MappingError.invalid(
                "Format citra '.\(photoURL.pathExtension)' tidak didukung untuk analisis VARI. Harap sediakan citra TIFF (.tif/.tiff) atau JPEG (.jpg/.jpeg)."
            )
        }

        let req = submission ?? VariEngineSubmissionRequest.defaultSample()
        let jsonString = try req.toJSONString()

        let process = Process()
        process.executableURL = helper
        let args = [
            "-m", "krops_vari.main",
            "--image", effectiveImageURL.path,
            "--user-request-submission-json", jsonString,
            "--output-dir", destinationFolder.path,
        ]
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw MappingError.invalid(
                "Pengolahan VARI gagal (exit code \(process.terminationStatus)): \(errMsg)")
        }

        let outputJSONURL = destinationFolder.appendingPathComponent("vari_result.json")
        guard FileManager.default.fileExists(atPath: outputJSONURL.path) else {
            let fallbackJSONURL = destinationFolder.appendingPathComponent("oil_palm_zones_vari.json")
            if FileManager.default.fileExists(atPath: fallbackJSONURL.path) {
                return try parseScanResult(from: fallbackJSONURL, in: destinationFolder)
            }
            throw MappingError.invalid("Berkas hasil VARI tidak ditemukan di \(outputJSONURL.path)")
        }

        return try parseScanResult(from: outputJSONURL, in: destinationFolder)
    }

    public func loadCachedResult(from folder: URL) throws -> VariScanResult? {
        let cachedURL = folder.appendingPathComponent("vari_result.json")
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return try parseScanResult(from: cachedURL, in: folder)
        }
        let fallbackURL = folder.appendingPathComponent("oil_palm_zones_vari.json")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return try parseScanResult(from: fallbackURL, in: folder)
        }
        return nil
    }

    private func parseScanResult(from url: URL, in folder: URL) throws -> VariScanResult {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalid("Hasil VARI bukan format JSON yang valid.")
        }

        // Image & tree count
        let imageInfo = json["image"] as? [String: Any]
        let metadata = json["metadata"] as? [String: Any]
        let treeCount = imageInfo?["trees"] as? Int
            ?? metadata?["detected_tree_count"] as? Int
            ?? 0

        // Summary
        let summaryDict = json["summary"] as? [String: Any]
        let refMean = summaryDict?["reference_zone_mean_vari"] as? Double
            ?? (metadata?["reference_zone_mean_vari"] as? Double)
        let overallConfidence = (metadata?["overall_field_confidence"] as? Double)

        let summary = VariSummary(
            referenceZoneIDs: summaryDict?["reference_zone_ids"] as? [Int] ?? (metadata?["reference_zone_ids"] as? [Int] ?? []),
            referenceFallbackAllZones: summaryDict?["reference_fallback_all_zones"] as? Bool ?? false,
            p25ZoneMeanVari: summaryDict?["p25_zone_mean_vari"] as? Double,
            referenceZoneMeanVari: refMean,
            p95P25VariGap: summaryDict?["p95_p25_vari_gap"] as? Double,
            boostMode: summaryDict?["boost_mode"] as? String ?? (metadata?["zone_boost_mode"] as? String),
            blanketVariGapCutoff: summaryDict?["blanket_vari_gap_cutoff"] as? Double,
            overallFieldConfidence: overallConfidence
        )

        // Zones
        let rawZones = json["zones"] as? [[String: Any]] ?? []
        var zones: [VariZoneDetail] = []
        for z in rawZones {
            let zoneID = z["zone_id"] as? Int ?? (zones.count + 1)
            let approxRow = z["approx_row"] as? Int
            let zTreeCount = z["tree_count"] as? Int ?? 0

            let variStats = z["vari"] as? [String: Any]
            let meanVari = variStats?["mean_vari"] as? Double
            let medianVari = variStats?["median_vari"] as? Double
            let minVari = variStats?["min_vari"] as? Double
            let maxVari = variStats?["max_vari"] as? Double
            let stdVari = variStats?["std_vari"] as? Double

            let rec = z["recommendation"] as? [String: Any]
            let conf = rec?["overall_field_confidence"] as? Double
            let bMode = rec?["boost_mode"] as? String
            let areaHa = rec?["zone_area_ha"] as? Double

            let fert = rec?["fertilizers"] as? [String: Any]
            let mgKg = (fert?["kieserite_Mg_expensive"] as? [String: Any])?["annual_total_kg"] as? Double
            let nKg = (fert?["urea_N_expensive"] as? [String: Any])?["annual_total_kg"] as? Double

            let zonePad = String(format: "%02d", zoneID)
            let baseCrop = folder.appendingPathComponent("oil_palm_zone_base_crops/zone_\(zonePad).jpg")
            let exgCrop = folder.appendingPathComponent("oil_palm_zone_exg_crops/zone_\(zonePad).jpg")

            zones.append(
                VariZoneDetail(
                    zoneID: zoneID,
                    approxRow: approxRow,
                    treeCount: zTreeCount,
                    meanVari: meanVari,
                    medianVari: medianVari,
                    minVari: minVari,
                    maxVari: maxVari,
                    stdVari: stdVari,
                    confidence: conf ?? overallConfidence,
                    boostMode: bMode,
                    areaHa: areaHa,
                    mgSupplementKg: mgKg,
                    nSupplementKg: nKg,
                    baseImageCropURL: FileManager.default.fileExists(atPath: baseCrop.path) ? baseCrop : nil,
                    exgImageCropURL: FileManager.default.fileExists(atPath: exgCrop.path) ? exgCrop : nil
                )
            )
        }

        // Product mass and bag rows
        // Source: vari_result.json → fertilizer_product_mass_conversions (one row per zone_id × product)
        var products: [VariProductRow] = []
        let rawProducts = json["fertilizer_product_mass_conversions"] as? [[String: Any]] ?? []
        for (idx, p) in rawProducts.enumerated() {
            let zoneID = p["zone_id"] as? Int
            let zoneLabel = zoneID.map { "Z\($0)" } ?? "-"
            let prodName = p["product"] as? String ?? ""
            let nutrient = p["nutrient"] as? String
            // Suplemen VARI (kg)   ← product_kg_per_zone_per_year        (null → 0)
            let supp = p["product_kg_per_zone_per_year"] as? Double ?? 0.0
            // Dosis Dasar (kg)     ← base_product_kg_per_zone_per_year   (null → 0, e.g. N products)
            let base = p["base_product_kg_per_zone_per_year"] as? Double ?? 0.0
            // Total Gabungan (kg)  ← supplement + base
            let comb = supp + base
            let estBags = comb / 50.0
            let fullBags = Int(ceil(estBags))

            products.append(
                VariProductRow(
                    id: "\(zoneLabel)_\(prodName)_\(idx)",
                    zoneID: zoneID,
                    zoneLabel: zoneLabel,
                    productName: prodName,
                    nutrientType: nutrient,
                    supplementKg: supp,
                    baseProductKg: base,
                    combinedKg: comb,
                    estimatedBags: estBags,
                    fullBagsNeeded: fullBags
                )
            )
        }

        // Budget Matching
        var budgetSummary: VariBudgetSummary?
        if let combinedCalc = json["combined_fertilizer_calculations"] as? [String: Any],
           let npkAnalysis = combinedCalc["field_wide_npk_baseline_comparison"] as? [String: Any] {
            let rankingDict = npkAnalysis["closest_to_budget_ranking"] as? [String: Any]
            let rankingTargetBudget = (rankingDict?["annual_budget_rp"] as? NSNumber)?.doubleValue
            let rankingTopupCost = (rankingDict?["selected_zone_mg_urea_whole_bag_cost_farm_year_rp"] as? NSNumber)?.doubleValue
            let rankingClosestOpt = rankingDict?["closest_blend_option"] as? String

            var targetBudget = (npkAnalysis["target_annual_budget_idr"] as? NSNumber)?.doubleValue ?? rankingTargetBudget
            var topupCost = (npkAnalysis["selected_zone_topup_cost_idr"] as? NSNumber)?.doubleValue ?? rankingTopupCost
            let closestOpt = npkAnalysis["closest_option"] as? String ?? rankingClosestOpt

            var candidates: [VariBudgetCandidate] = []

            if let estimateList = npkAnalysis["blend_purchase_price_estimates"] as? [[String: Any]], !estimateList.isEmpty {
                for (idx, item) in estimateList.enumerated() {
                    let blend = item["blend_option"] as? String ?? "Option \(idx + 1)"

                    // Label ratio e.g. "15.0-15.0-15.0-0.0"
                    let ratio: String
                    if let labelDict = item["label_percent_n_p2o5_k2o_mgo"] as? [String: Any] {
                        let n = (labelDict["N"] as? NSNumber)?.doubleValue ?? 0.0
                        let p = (labelDict["P2O5"] as? NSNumber)?.doubleValue ?? 0.0
                        let k = (labelDict["K2O"] as? NSNumber)?.doubleValue ?? 0.0
                        let mg = (labelDict["MgO"] as? NSNumber)?.doubleValue ?? 0.0
                        ratio = String(format: "%.1f-%.1f-%.1f-%.1f", n, p, k, mg)
                    } else if let ratioStr = item["label_ratio"] as? String {
                        ratio = ratioStr
                    } else {
                        ratio = "-"
                    }

                    let ageCap = item["age_budget_cap"] as? [String: Any]
                    let capBudget = (ageCap?["budget_rp"] as? NSNumber)?.doubleValue
                    let capZoneCost = (ageCap?["fixed_zone_boost_cost_rp"] as? NSNumber)?.doubleValue

                    if targetBudget == nil, let capBudget {
                        targetBudget = capBudget
                    }
                    if topupCost == nil, let capZoneCost {
                        topupCost = capZoneCost
                    }

                    // Full bags: age-adjusted -> estimated_npk_full_bags_for_farm -> baseline
                    let fullBags = (item["age_adjusted_full_bags_per_ha_year"] as? NSNumber)?.intValue
                        ?? (ageCap?["estimated_npk_full_bags_for_farm"] as? NSNumber)?.intValue
                        ?? (ageCap?["baseline_full_bags_for_farm_year"] as? NSNumber)?.intValue
                        ?? (item["baseline_full_bags_per_ha_year"] as? NSNumber)?.intValue
                        ?? 0

                    // NPK Cost: age-adjusted -> baseline
                    let npkCost = (item["age_adjusted_full_bag_cost_rp_per_ha_year"] as? NSNumber)?.doubleValue
                        ?? (item["baseline_full_bag_cost_rp_per_ha_year"] as? NSNumber)?.doubleValue
                        ?? 0.0

                    // Zone Mg/Urea Cost
                    let zoneCost = capZoneCost ?? topupCost ?? 0.0

                    // Combined Cost: estimated_combined_whole_bag_cost_rp -> baseline_combined_whole_bag_cost_rp -> (npkCost + zoneCost)
                    let combinedCost = (ageCap?["estimated_combined_whole_bag_cost_rp"] as? NSNumber)?.doubleValue
                        ?? (ageCap?["baseline_combined_whole_bag_cost_rp"] as? NSNumber)?.doubleValue
                        ?? (npkCost + zoneCost)

                    let effectiveTarget = capBudget ?? targetBudget ?? 0.0
                    let delta = combinedCost - effectiveTarget
                    let isClose = (closestOpt == blend)

                    candidates.append(
                        VariBudgetCandidate(
                            id: "\(blend)_\(idx)",
                            blendOption: blend,
                            labelRatio: ratio,
                            npkFullBags: fullBags,
                            npkCostRp: npkCost,
                            zoneTopupCostRp: zoneCost,
                            combinedCostRp: combinedCost,
                            budgetTargetRp: effectiveTarget,
                            budgetDifferenceRp: delta,
                            isClosest: isClose
                        )
                    )
                }
            } else if let candidateList = npkAnalysis["candidate_comparison_table"] as? [[String: Any]] {
                for (cIdx, c) in candidateList.enumerated() {
                    let blend = c["blend_option"] as? String ?? c["blendOption"] as? String ?? "Option \(cIdx + 1)"
                    let ratio = c["label_ratio"] as? String ?? c["labelRatio"] as? String ?? ""
                    let fullBags = (c["npk_full_bags"] as? NSNumber)?.intValue ?? 0
                    let npkCost = (c["npk_cost_rp"] as? NSNumber)?.doubleValue ?? 0.0
                    let topup = (c["zone_topup_cost_rp"] as? NSNumber)?.doubleValue ?? (topupCost ?? 0.0)
                    let combinedCost = (c["combined_cost_rp"] as? NSNumber)?.doubleValue ?? (npkCost + topup)
                    let target = (c["budget_target_rp"] as? NSNumber)?.doubleValue ?? (targetBudget ?? 0.0)
                    let delta = (c["budget_difference_rp"] as? NSNumber)?.doubleValue ?? (combinedCost - target)
                    let isClose = (c["is_closest"] as? Bool) ?? (closestOpt == blend)

                    candidates.append(
                        VariBudgetCandidate(
                            id: "\(blend)_\(cIdx)",
                            blendOption: blend,
                            labelRatio: ratio,
                            npkFullBags: fullBags,
                            npkCostRp: npkCost,
                            zoneTopupCostRp: topup,
                            combinedCostRp: combinedCost,
                            budgetTargetRp: target,
                            budgetDifferenceRp: delta,
                            isClosest: isClose
                        )
                    )
                }
            }

            budgetSummary = VariBudgetSummary(
                targetBudgetRp: targetBudget,
                zoneTopupCostRp: topupCost,
                closestOption: closestOpt,
                candidates: candidates
            )
        }

        // Asset URLs
        func assetIfPresent(_ filename: String) -> URL? {
            let fileURL = folder.appendingPathComponent(filename)
            return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
        }

        let assets = VariAssetURLs(
            annotatedMapURL: assetIfPresent("oil_palm_zones_annotated.jpg"),
            whiteSeparatorsWithNumbersURL: assetIfPresent("oil_palm_zones_white_separators_with_zone_numbers.jpg"),
            quartilesMapURL: assetIfPresent("oil_palm_field_tree_vari_quartiles.jpg"),
            heatmapMontageURL: assetIfPresent("oil_palm_tree_vari_heatmap_montage.png"),
            pipelinePlotURL: assetIfPresent("oil_palm_pipeline_stages.jpg"),
            variDistributionPlotURL: assetIfPresent("oil_palm_vari_distribution.png"),
            zoneSummaryCSVURL: assetIfPresent("oil_palm_zone_vari_summary.csv"),
            fertilizerMassCSVURL: assetIfPresent("oil_palm_zone_fertilizer_product_mass.csv"),
            oilPalmZonesJSONURL: assetIfPresent("oil_palm_zones_vari.json")
        )

        return VariScanResult(
            resultJSONURL: url,
            treeCount: treeCount,
            zoneCount: zones.count,
            referenceMeanVari: refMean,
            createdAt: Date(),
            summary: summary,
            zones: zones,
            products: products,
            budget: budgetSummary,
            assets: assets
        )
    }
}
