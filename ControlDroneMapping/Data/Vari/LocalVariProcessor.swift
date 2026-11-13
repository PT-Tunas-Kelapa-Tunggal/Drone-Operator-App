import Foundation
import ImageIO

/// Executes the bundled VariEngine to process an orthomosaic into VARI and HARA analysis.
public struct LocalVariProcessor: VariProcessing {
    public static let canonicalJPEGFileName = "orthomosaic.jpeg"

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
        guard let submission else {
            throw MappingError.invalid(
                "Parameter agronomi VARI (VariEngineSubmissionRequest) wajib tersedia dari data CloudKit."
            )
        }

        let fm = FileManager.default
        let destinationFolder =
            outputFolder ?? fm.temporaryDirectory.appendingPathComponent("VariScans")
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        guard photoURL.isFileURL, fm.fileExists(atPath: photoURL.path) else {
            throw MappingError.invalid("Berkas citra tidak ditemukan di: \(photoURL.path)")
        }

        let targetJPEGURL = destinationFolder.appendingPathComponent(Self.canonicalJPEGFileName)
        let effectiveImageURL: URL
        let ext = photoURL.pathExtension.lowercased()
        if ext == "tif" || ext == "tiff" {
            effectiveImageURL = try TIFFToJPEGConverter.convert(
                from: photoURL,
                to: targetJPEGURL,
                quality: 0.5
            )
        } else if ext == "jpeg" || ext == "jpg" {
            guard let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0
            else {
                throw MappingError.invalid("Berkas JPEG rusak atau tidak dapat dibaca: \(photoURL.lastPathComponent)")
            }
            if photoURL.standardizedFileURL != targetJPEGURL.standardizedFileURL {
                if fm.fileExists(atPath: targetJPEGURL.path) {
                    try fm.removeItem(at: targetJPEGURL)
                }
                try fm.copyItem(at: photoURL, to: targetJPEGURL)
            }
            effectiveImageURL = targetJPEGURL
        } else {
            throw MappingError.invalid(
                "Format citra '.\(photoURL.pathExtension)' tidak didukung untuk analisis VARI. Harap sediakan citra TIFF (.tif/.tiff) atau JPEG (.jpg/.jpeg)."
            )
        }

        let jsonString = try submission.toJSONString()

        let process = Process()
        process.executableURL = helper
        process.arguments = [
            "-m", "krops_vari.main",
            "--image", effectiveImageURL.path,
            "--user-request-submission-json", jsonString,
            "--output-dir", destinationFolder.path,
        ]

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
        guard fm.fileExists(atPath: outputJSONURL.path) else {
            let fallbackJSONURL = destinationFolder.appendingPathComponent("oil_palm_zones_vari.json")
            if fm.fileExists(atPath: fallbackJSONURL.path) {
                return try Self.parseScanResult(from: fallbackJSONURL, in: destinationFolder)
            }
            throw MappingError.invalid("Berkas hasil VARI tidak ditemukan di \(outputJSONURL.path)")
        }

        return try Self.parseScanResult(from: outputJSONURL, in: destinationFolder)
    }

    public func loadCachedResult(from folder: URL) throws -> VariScanResult? {
        let cachedURL = folder.appendingPathComponent("vari_result.json")
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return try Self.parseScanResult(from: cachedURL, in: folder)
        }
        let fallbackURL = folder.appendingPathComponent("oil_palm_zones_vari.json")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return try Self.parseScanResult(from: fallbackURL, in: folder)
        }
        return nil
    }

    // MARK: - JSON Parsing

    public static func parseScanResult(from url: URL, in folder: URL) throws -> VariScanResult {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalid("Hasil VARI bukan format JSON yang valid.")
        }

        let imageInfo = json["image"] as? [String: Any]
        let metadata = json["metadata"] as? [String: Any]
        let treeCount = (imageInfo?["trees"] as? NSNumber)?.intValue
            ?? (metadata?["detected_tree_count"] as? NSNumber)?.intValue
            ?? 0
        let imageWidthPx = (imageInfo?["width"] as? NSNumber)?.intValue
            ?? (metadata?["image_width_px"] as? NSNumber)?.intValue
        let imageHeightPx = (imageInfo?["height"] as? NSNumber)?.intValue
            ?? (metadata?["image_height_px"] as? NSNumber)?.intValue

        // Summary
        let summaryDict = json["summary"] as? [String: Any]
        let refMean = (summaryDict?["reference_zone_mean_vari"] as? NSNumber)?.doubleValue
            ?? (metadata?["reference_zone_mean_vari"] as? NSNumber)?.doubleValue
        let overallConfidence = (metadata?["overall_field_confidence"] as? NSNumber)?.doubleValue

        let summary = VariSummary(
            referenceZoneIDs: summaryDict?["reference_zone_ids"] as? [Int]
                ?? (metadata?["reference_zone_ids"] as? [Int] ?? []),
            referenceFallbackAllZones: summaryDict?["reference_fallback_all_zones"] as? Bool ?? false,
            p25ZoneMeanVari: (summaryDict?["p25_zone_mean_vari"] as? NSNumber)?.doubleValue
                ?? (metadata?["p25_zone_mean_vari"] as? NSNumber)?.doubleValue,
            referenceZoneMeanVari: refMean,
            p95P25VariGap: (summaryDict?["p95_p25_vari_gap"] as? NSNumber)?.doubleValue
                ?? (metadata?["p95_p25_vari_gap"] as? NSNumber)?.doubleValue,
            boostMode: summaryDict?["boost_mode"] as? String ?? (metadata?["zone_boost_mode"] as? String),
            blanketVariGapCutoff: (summaryDict?["blanket_vari_gap_cutoff"] as? NSNumber)?.doubleValue
                ?? (metadata?["minimum_p95_p25_gap_for_blanket_boost"] as? NSNumber)?.doubleValue,
            overallFieldConfidence: overallConfidence
        )

        // Zones & Trees
        let rawZones = json["zones"] as? [[String: Any]] ?? []
        var zones: [VariZoneDetail] = []
        for z in rawZones {
            let zoneID = (z["zone_id"] as? NSNumber)?.intValue ?? (zones.count + 1)
            let approxRow = (z["approx_row"] as? NSNumber)?.intValue
            let zTreeCount = (z["tree_count"] as? NSNumber)?.intValue ?? 0

            let variStats = z["vari"] as? [String: Any]
            let meanVari = (variStats?["mean_vari"] as? NSNumber)?.doubleValue
            let medianVari = (variStats?["median_vari"] as? NSNumber)?.doubleValue
            let minVari = (variStats?["min_vari"] as? NSNumber)?.doubleValue
            let maxVari = (variStats?["max_vari"] as? NSNumber)?.doubleValue
            let stdVari = (variStats?["std_vari"] as? NSNumber)?.doubleValue

            let rec = z["recommendation"] as? [String: Any]
            let conf = (rec?["overall_field_confidence"] as? NSNumber)?.doubleValue
            let bMode = rec?["boost_mode"] as? String
            let areaHa = (rec?["zone_area_ha"] as? NSNumber)?.doubleValue

            let fert = rec?["fertilizers"] as? [String: Any]
            let mgKg = (fert?["dolomite_Mg_cheaper"] as? [String: Any])?["annual_total_kg"] as? Double
                ?? (fert?["kieserite_Mg_expensive"] as? [String: Any])?["annual_total_kg"] as? Double
            let nKg = (fert?["urea_N_expensive"] as? [String: Any])?["annual_total_kg"] as? Double

            let zoneBox = parsePixelBox(z["bbox"] as? [String: Any])

            let rawTrees = z["trees"] as? [[String: Any]] ?? []
            var trees: [VariTreeDetection] = []
            trees.reserveCapacity(rawTrees.count)
            for (tIdx, t) in rawTrees.enumerated() {
                let treeID = (t["tree_id"] as? NSNumber)?.intValue ?? (tIdx + 1)
                if let treeBox = parsePixelBox(t["bbox"] as? [String: Any])
                    ?? parsePixelBox(t["bounding_box_pixels"] as? [String: Any])
                {
                    trees.append(VariTreeDetection(id: treeID, zoneID: zoneID, boundingBox: treeBox))
                }
            }

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
                    boundingBox: zoneBox,
                    trees: trees,
                    baseImageCropURL: FileManager.default.fileExists(atPath: baseCrop.path) ? baseCrop : nil,
                    exgImageCropURL: FileManager.default.fileExists(atPath: exgCrop.path) ? exgCrop : nil
                )
            )
        }

        // Product mass conversions
        var products: [VariProductRow] = []
        let rawProducts = json["fertilizer_product_mass_conversions"] as? [[String: Any]] ?? []
        for (idx, p) in rawProducts.enumerated() {
            let zoneID = (p["zone_id"] as? NSNumber)?.intValue
            let zoneLabel = zoneID.map { "Z\($0)" } ?? "-"
            let prodName = p["product"] as? String ?? ""
            let nutrient = p["nutrient"] as? String
            let supp = (p["product_kg_per_zone_per_year"] as? NSNumber)?.doubleValue ?? 0.0
            let base = (p["base_product_kg_per_zone_per_year"] as? NSNumber)?.doubleValue ?? 0.0
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

        // NPK Baseline, User Blend, and Budget Ranking
        var userBlendSummary: VariUserBlendSummary?
        var budgetSummary: VariBudgetSummary?

        if let combinedCalc = json["combined_fertilizer_calculations"] as? [String: Any],
           let npkAnalysis = combinedCalc["field_wide_npk_baseline_comparison"] as? [String: Any]
        {
            if let userBlendDict = npkAnalysis["user_blend"] as? [String: Any] {
                let ratio = parseNPKRatio(userBlendDict["label_percent"] as? [String: Any])
                let bagSize = (userBlendDict["bag_size_kg"] as? NSNumber)?.doubleValue ?? 50.0
                let areaHaUsed = (userBlendDict["farm_area_ha_used"] as? NSNumber)?.doubleValue
                let npkFarmKg = (userBlendDict["npk_product_kg_farm_per_year"] as? NSNumber)?.doubleValue ?? 0.0
                let dosePerTree = (userBlendDict["dose_per_tree_kg_per_application"] as? NSNumber)?.doubleValue
                let appFreq = (userBlendDict["fertilizer_applications_per_year"] as? NSNumber)?.doubleValue

                userBlendSummary = VariUserBlendSummary(
                    ratio: ratio,
                    bagSizeKg: bagSize,
                    farmAreaHaUsed: areaHaUsed,
                    npkProductKgFarmPerYear: npkFarmKg,
                    dosePerTreeKgPerApplication: dosePerTree,
                    applicationsPerYear: appFreq
                )
            }

            let bagSizeKg = userBlendSummary?.bagSizeKg ?? 50.0
            let farmAreaHa = userBlendSummary?.farmAreaHaUsed ?? 1.0

            let rankingDict = npkAnalysis["closest_to_budget_ranking"] as? [String: Any]
            let rankingTargetBudget = (rankingDict?["annual_budget_rp"] as? NSNumber)?.doubleValue
            let rankingTopupCost = (rankingDict?["selected_zone_mg_urea_whole_bag_cost_farm_year_rp"] as? NSNumber)?
                .doubleValue
            let rankingClosestOpt = rankingDict?["closest_blend_option"] as? String

            var rankedByOption: [String: [String: Any]] = [:]
            if let rankedOptions = rankingDict?["ranked_options"] as? [[String: Any]] {
                for opt in rankedOptions {
                    if let key = opt["blend_option"] as? String {
                        rankedByOption[key] = opt
                    }
                }
            }

            var targetBudget = (npkAnalysis["target_annual_budget_idr"] as? NSNumber)?.doubleValue
                ?? rankingTargetBudget
            var topupCost = (npkAnalysis["selected_zone_topup_cost_idr"] as? NSNumber)?.doubleValue
                ?? rankingTopupCost
            let closestOpt = npkAnalysis["closest_option"] as? String ?? rankingClosestOpt

            var candidates: [VariBudgetCandidate] = []

            if let estimateList = npkAnalysis["blend_purchase_price_estimates"] as? [[String: Any]],
               !estimateList.isEmpty
            {
                for (idx, item) in estimateList.enumerated() {
                    let blend = item["blend_option"] as? String ?? "Option \(idx + 1)"
                    let ranked = rankedByOption[blend]

                    let parsedRatio = parseNPKRatio(item["label_percent_n_p2o5_k2o_mgo"] as? [String: Any])
                        ?? parseNPKRatio(ranked?["composition_label_percent_n_p2o5_k2o_mgo"] as? [String: Any])
                    let ratioLabel: String
                    if let parsedRatio {
                        ratioLabel = String(
                            format: "%.1f-%.1f-%.1f-%.1f",
                            parsedRatio.n, parsedRatio.p2o5, parsedRatio.k2o, parsedRatio.mgo
                        )
                    } else if let ratioStr = item["label_ratio"] as? String {
                        ratioLabel = ratioStr
                    } else {
                        ratioLabel = "-"
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

                    let perHaExactBags = (item["age_adjusted_exact_bags_per_ha_year"] as? NSNumber)?.doubleValue
                        ?? (item["baseline_exact_bags_per_ha_year"] as? NSNumber)?.doubleValue
                    let exactBagsFarm = (ranked?["age_adjusted_exact_bags_farm_year"] as? NSNumber)?.doubleValue
                        ?? perHaExactBags.map { $0 * farmAreaHa }
                    let exactKgFarm = exactBagsFarm.map { $0 * bagSizeKg }

                    let fullBagsFarm = (ranked?["age_adjusted_full_bags_farm_year"] as? NSNumber)?.intValue
                        ?? (ageCap?["estimated_npk_full_bags_for_farm"] as? NSNumber)?.intValue
                        ?? (ageCap?["baseline_full_bags_for_farm_year"] as? NSNumber)?.intValue
                        ?? exactBagsFarm.map { Int(ceil($0)) }
                        ?? (item["age_adjusted_full_bags_per_ha_year"] as? NSNumber)?.intValue
                        ?? (item["baseline_full_bags_per_ha_year"] as? NSNumber)?.intValue
                        ?? 0

                    let npkCostFarm = (ranked?["npk_full_bag_cost_farm_year_rp"] as? NSNumber)?.doubleValue
                        ?? (item["age_adjusted_full_bag_cost_rp_per_ha_year"] as? NSNumber).map {
                            $0.doubleValue * farmAreaHa
                        }
                        ?? (item["baseline_full_bag_cost_rp_per_ha_year"] as? NSNumber).map {
                            $0.doubleValue * farmAreaHa
                        }
                        ?? 0.0

                    let zoneCost = (ranked?["selected_zone_mg_urea_whole_bag_cost_farm_year_rp"] as? NSNumber)?
                        .doubleValue
                        ?? capZoneCost
                        ?? topupCost
                        ?? 0.0

                    let combinedCost = (ranked?["combined_estimated_cost_farm_year_rp"] as? NSNumber)?.doubleValue
                        ?? (ageCap?["estimated_combined_whole_bag_cost_rp"] as? NSNumber)?.doubleValue
                        ?? (ageCap?["baseline_combined_whole_bag_cost_rp"] as? NSNumber)?.doubleValue
                        ?? (npkCostFarm + zoneCost)

                    let effectiveTarget = capBudget ?? targetBudget ?? 0.0
                    let delta = (ranked?["budget_difference_rp"] as? NSNumber)?.doubleValue
                        ?? (combinedCost - effectiveTarget)
                    let isClose = (ranked?["closest_to_budget"] as? Bool) ?? (closestOpt == blend)

                    candidates.append(
                        VariBudgetCandidate(
                            id: "\(blend)_\(idx)",
                            blendOption: blend,
                            labelRatio: ratioLabel,
                            labelRatioValues: parsedRatio,
                            npkFullBags: fullBagsFarm,
                            bagSizeKg: bagSizeKg,
                            ageAdjustedExactBagsFarmYear: exactBagsFarm,
                            ageAdjustedExactKgFarmYear: exactKgFarm,
                            npkCostRp: npkCostFarm,
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
                    let parsedRatio = parseRatioString(ratio)

                    candidates.append(
                        VariBudgetCandidate(
                            id: "\(blend)_\(cIdx)",
                            blendOption: blend,
                            labelRatio: ratio,
                            labelRatioValues: parsedRatio,
                            npkFullBags: fullBags,
                            bagSizeKg: bagSizeKg,
                            ageAdjustedExactBagsFarmYear: Double(fullBags),
                            ageAdjustedExactKgFarmYear: Double(fullBags) * bagSizeKg,
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

        let sourceImageURL: URL? = assetIfPresent(Self.canonicalJPEGFileName) ?? {
            guard let rawPath = metadata?["source_image"] as? String else { return nil }
            let metaURL = URL(fileURLWithPath: rawPath)
            return FileManager.default.fileExists(atPath: metaURL.path) ? metaURL : nil
        }()

        let assets = VariAssetURLs(
            sourceImageURL: sourceImageURL,
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
            imageWidthPx: imageWidthPx,
            imageHeightPx: imageHeightPx,
            createdAt: Date(),
            summary: summary,
            zones: zones,
            products: products,
            userBlend: userBlendSummary,
            budget: budgetSummary,
            assets: assets
        )
    }

    private static func parsePixelBox(_ dict: [String: Any]?) -> VariPixelBox? {
        guard let dict,
              let x1 = (dict["x1"] as? NSNumber)?.doubleValue,
              let y1 = (dict["y1"] as? NSNumber)?.doubleValue,
              let x2 = (dict["x2"] as? NSNumber)?.doubleValue,
              let y2 = (dict["y2"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        return VariPixelBox(x1: x1, y1: y1, x2: x2, y2: y2)
    }

    private static func parseNPKRatio(_ dict: [String: Any]?) -> VariNPKRatio? {
        guard let dict else { return nil }
        guard let n = (dict["N"] as? NSNumber)?.doubleValue,
              let p = (dict["P2O5"] as? NSNumber)?.doubleValue,
              let k = (dict["K2O"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        let mg = (dict["MgO"] as? NSNumber)?.doubleValue ?? 0.0
        return VariNPKRatio(n: n, p2o5: p, k2o: k, mgo: mg)
    }

    private static func parseRatioString(_ raw: String) -> VariNPKRatio? {
        let parts = raw.split(separator: "-").compactMap { Double($0) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        return VariNPKRatio(
            n: parts[0],
            p2o5: parts[1],
            k2o: parts[2],
            mgo: parts.count == 4 ? parts[3] : 0.0
        )
    }
}
