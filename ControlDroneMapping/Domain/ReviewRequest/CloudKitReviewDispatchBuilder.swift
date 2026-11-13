import CoreGraphics
import Foundation
import ImageIO

public enum CloudKitDispatchBuildError: LocalizedError, Equatable, Sendable {
    case missingOrthomosaicJPEG(String)
    case unreadableOrthomosaicJPEG(String)
    case pixelDimensionMismatch(imageW: Int, imageH: Int, variW: Int, variH: Int)
    case missingZones
    case missingZoneBoundingBox(zoneID: Int)
    case boundingBoxOutOfBounds(label: String, width: Int, height: Int)
    case missingTrees
    case noFertilizerNeedsProduced
    case noScheduleRoundsProduced
    case invalidScheduleDate(String)
    case unmappableScheduleFertilizer(displayName: String, fertilizerID: String?)
    case forbiddenGenericNPKDetected

    public var errorDescription: String? {
        switch self {
        case .missingOrthomosaicJPEG(let path):
            return "File orthomosaic.jpeg tidak ditemukan di: \(path)"
        case .unreadableOrthomosaicJPEG(let path):
            return "File orthomosaic.jpeg rusak atau bukan JPEG valid: \(path)"
        case .pixelDimensionMismatch(let imageW, let imageH, let variW, let variH):
            return "Dimensi orthomosaic.jpeg (\(imageW)×\(imageH)) berbeda dengan hasil VARI (\(variW)×\(variH))."
        case .missingZones:
            return "Hasil VARI tidak memiliki zona pemupukan."
        case .missingZoneBoundingBox(let zoneID):
            return "Zona \(zoneID) tidak memiliki bounding box piksel di vari_result.json."
        case .boundingBoxOutOfBounds(let label, let width, let height):
            return "Bounding box '\(label)' keluar dari batas piksel orthomosaic (\(width)×\(height))."
        case .missingTrees:
            return "Hasil VARI tidak memiliki deteksi pohon individu di dalam zona."
        case .noFertilizerNeedsProduced:
            return "Tidak ada kebutuhan pupuk yang valid untuk dikirim ke CloudKit."
        case .noScheduleRoundsProduced:
            return "Hasil Jadwal Pemupukan tidak memiliki putaran aktif."
        case .invalidScheduleDate(let rawDate):
            return "Format tanggal Jadwal Pemupukan tidak valid: '\(rawDate)'."
        case .unmappableScheduleFertilizer(let displayName, let fertilizerID):
            return "Pupuk pada jadwal ('\(displayName)', id='\(fertilizerID ?? "-")') tidak dapat dipetakan ke enum kontrak CloudKit."
        case .forbiddenGenericNPKDetected:
            return "Kesalahan kontrak: macOS dilarang menulis tipe generik .npk ke CloudKit."
        }
    }
}

/// Pure builder converting verified Orthomosaic (`orthomosaic.jpeg`), VARI & HARA (`VariScanResult`),
/// and Jadwal Pemupukan (`VariTimingExecutionResult`) into a contract-compliant `ReviewDispatchPayload`.
public enum CloudKitReviewDispatchBuilder {
    private static let jakartaTimeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current

    public static func makeDispatchPayload(
        request: PlantationReviewRequest,
        orthomosaicJPEGURL: URL,
        variResult: VariScanResult,
        timingResult: VariTimingExecutionResult,
        fertilizerIDLookup: [String: ContractFertilizerType] = [:],
        preferredNPKForFallback: ContractFertilizerType? = nil,
        sentAt: Date = Date()
    ) throws -> ReviewDispatchPayload {
        // 1. Validate orthomosaic.jpeg exists, is JPEG, and matches VARI pixel dimensions
        let (imgWidth, imgHeight) = try validateOrthomosaicJPEG(
            at: orthomosaicJPEGURL,
            variResult: variResult
        )

        // 2. Map fertilizingZone & treeIdentification in pixel coordinates matching orthomosaic.jpeg
        let sortedZones = variResult.zones.sorted { $0.zoneID < $1.zoneID }
        guard !sortedZones.isEmpty else {
            throw CloudKitDispatchBuildError.missingZones
        }

        var zoneItems: [FertilizingZoneItem] = []
        var treeItems: [TreeIdentificationItem] = []

        for zone in sortedZones {
            guard let zoneBox = zone.boundingBox else {
                throw CloudKitDispatchBuildError.missingZoneBoundingBox(zoneID: zone.zoneID)
            }
            guard zoneBox.isValid(withinWidth: imgWidth, height: imgHeight) else {
                throw CloudKitDispatchBuildError.boundingBoxOutOfBounds(
                    label: "Zona \(zone.zoneID)",
                    width: imgWidth,
                    height: imgHeight
                )
            }

            zoneItems.append(
                FertilizingZoneItem(
                    id: Int64(zone.zoneID),
                    treeCount: Int64(zone.treeCount),
                    boundingBox: zoneBox.corners
                )
            )

            for tree in zone.trees.sorted(by: { $0.id < $1.id }) {
                guard tree.boundingBox.isValid(withinWidth: imgWidth, height: imgHeight) else {
                    throw CloudKitDispatchBuildError.boundingBoxOutOfBounds(
                        label: "Pohon \(tree.id) (Zona \(zone.zoneID))",
                        width: imgWidth,
                        height: imgHeight
                    )
                }
                // HELD OFF: ML tree-health label is not yet available; emit temporary `.unknown`.
                treeItems.append(
                    TreeIdentificationItem(
                        id: Int64(tree.id),
                        boundingBox: tree.boundingBox.corners,
                        zoneId: Int64(zone.zoneID),
                        healthynessLabel: .unknown
                    )
                )
            }
        }

        guard !treeItems.isEmpty else {
            throw CloudKitDispatchBuildError.missingTrees
        }

        // 3. Map fertilizerNeedPerZone (.general NPK options + .zoneSpecific Dolomite/Urea only)
        let fertilizerNeeds = try buildFertilizerNeeds(
            request: request,
            variResult: variResult,
            zones: sortedZones
        )

        // 4. Map fertilizationScheduling preserving explicit NPK enum via deterministic lookup
        let schedulePeriods = try buildSchedulePeriods(
            timingResult: timingResult,
            fertilizerIDLookup: fertilizerIDLookup,
            preferredNPKForFallback: preferredNPKForFallback ?? variResult.budget.flatMap {
                VariTimingBuilder.resolveSelectedNPKCandidate(from: $0.candidates)?.explicitNPKType
            }
        )

        // 5. Preserve existing progression events and append completion event (straight to .finished)
        var events = request.progressionEvents.map(\.contractEvent)
        let summaryDesc =
            "Orthomosaic, analisis VARI & HARA (\(zoneItems.count) zona, \(treeItems.count) pohon), "
            + "dan jadwal pemupukan (\(schedulePeriods.count) putaran) telah selesai dan dikirim."
        events.append(
            ProgressionStatusDetailEvent(
                dateTime: sentAt,
                title: "Analisis Selesai",
                desc: summaryDesc
            )
        )

        let writer = MacOSScanRequestRecordWriter(
            recordName: request.recordName,
            progressionStatus: .finished,
            progressionStatusDetail: events,
            orthomosaicImageURL: orthomosaicJPEGURL,
            fertilizingZone: zoneItems,
            fertilizerNeedPerZone: fertilizerNeeds,
            treeIdentification: treeItems,
            plannedOperatorVisitDate: nil,
            resultSentAt: sentAt,
            fertilizationScheduling: schedulePeriods
        )

        let summaryResult = PlantationReviewResult(
            completedAt: sentAt,
            orthomosaicImageURL: orthomosaicJPEGURL,
            zones: zoneItems,
            trees: treeItems,
            fertilizerNeeds: fertilizerNeeds,
            schedulePeriods: schedulePeriods
        )

        return ReviewDispatchPayload(
            requestID: request.id,
            recordName: request.recordName,
            writer: writer,
            summaryResult: summaryResult
        )
    }

    // MARK: - Helpers

    private static func validateOrthomosaicJPEG(
        at url: URL,
        variResult: VariScanResult
    ) throws -> (Int, Int) {
        let fm = FileManager.default
        guard url.isFileURL, fm.fileExists(atPath: url.path) else {
            throw CloudKitDispatchBuildError.missingOrthomosaicJPEG(url.path)
        }
        let ext = url.pathExtension.lowercased()
        guard ext == "jpeg" || ext == "jpg" else {
            throw CloudKitDispatchBuildError.unreadableOrthomosaicJPEG(url.path)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0
        else {
            throw CloudKitDispatchBuildError.unreadableOrthomosaicJPEG(url.path)
        }

        if let variW = variResult.imageWidthPx, let variH = variResult.imageHeightPx,
           variW != pixelWidth || variH != pixelHeight
        {
            throw CloudKitDispatchBuildError.pixelDimensionMismatch(
                imageW: pixelWidth,
                imageH: pixelHeight,
                variW: variW,
                variH: variH
            )
        }

        return (pixelWidth, pixelHeight)
    }

    private static func buildFertilizerNeeds(
        request: PlantationReviewRequest,
        variResult: VariScanResult,
        zones: [VariZoneDetail]
    ) throws -> [FertilizerNeedItem] {
        var needs: [FertilizerNeedItem] = []
        let freq = Double(max(1, request.agronomy.fertilizingFrequencyPerYear))
        let detectedTotalTrees = Double(max(variResult.treeCount, zones.reduce(0) { $0 + $1.treeCount }))

        // (A) General (plantation-wide) NPK options
        var seenNPKTypes: Set<ContractFertilizerType> = []
        let candidates = variResult.budget?.candidates ?? []
        let userMatchedNPKType = variResult.userBlend?.ratio?.toExplicitContractNPKType()

        for candidate in candidates {
            guard let explicitType = candidate.explicitNPKType,
                  !explicitType.isGenericNPKSentinel,
                  !seenNPKTypes.contains(explicitType),
                  let recommendedKg = candidate.recommendedAnnualKgFarm,
                  recommendedKg > 0
            else {
                continue
            }
            seenNPKTypes.insert(explicitType)

            let currentDosageKg: Double
            if let userMatchedNPKType, userMatchedNPKType == explicitType,
               let userNPKKg = variResult.userBlend?.npkProductKgFarmPerYear
            {
                currentDosageKg = max(0.0, userNPKKg)
            } else {
                let matchingFarmerNPK = request.agronomy.fertilizerRecords.filter { usage in
                    usage.contractType == explicitType
                        || usage.effectiveNPKRatio()?.toExplicitContractNPKType() == explicitType
                }
                if matchingFarmerNPK.isEmpty {
                    currentDosageKg = 0.0
                } else {
                    currentDosageKg = matchingFarmerNPK.reduce(0.0) { partial, usage in
                        partial + usage.doseKgPerTree * freq * detectedTotalTrees
                    }
                }
            }

            needs.append(
                FertilizerNeedItem(
                    fertilizerApplicationType: .general,
                    fertilizerType: explicitType,
                    recommendedDosage: recommendedKg,
                    dosageUnit: "kg",
                    currentDosage: currentDosageKg,
                    zoneId: nil
                )
            )
        }

        // (B) Zone-specific Dolomite & Urea ONLY (exclude Kieserite & ZA)
        let treeCountByZone = Dictionary(uniqueKeysWithValues: zones.map { ($0.zoneID, $0.treeCount) })
        let sortedProducts = variResult.products
            .filter { $0.zoneID != nil }
            .sorted { lhs, rhs in
                if lhs.zoneID != rhs.zoneID {
                    return (lhs.zoneID ?? 0) < (rhs.zoneID ?? 0)
                }
                return lhs.productName < rhs.productName
            }

        for row in sortedProducts {
            guard let zoneID = row.zoneID else { continue }
            let contractType: ContractFertilizerType
            if VariTimingBuilder.isDolomiteProduct(row.productName) {
                contractType = .dolomite
            } else if VariTimingBuilder.isUreaProduct(row.productName) {
                contractType = .urea
            } else {
                continue
            }

            let zoneTrees = Double(max(0, treeCountByZone[zoneID] ?? 0))
            let farmerAnnualDose = request.agronomy.fertilizerRecords
                .filter { $0.contractType == contractType }
                .reduce(0.0) { $0 + ($1.doseKgPerTree * freq * zoneTrees) }

            needs.append(
                FertilizerNeedItem(
                    fertilizerApplicationType: .zoneSpecific,
                    fertilizerType: contractType,
                    recommendedDosage: row.roundedCombinedKg,
                    dosageUnit: "kg",
                    currentDosage: farmerAnnualDose,
                    zoneId: Int64(zoneID)
                )
            )
        }

        if needs.contains(where: { $0.fertilizerType.isGenericNPKSentinel }) {
            throw CloudKitDispatchBuildError.forbiddenGenericNPKDetected
        }
        guard !needs.isEmpty else {
            throw CloudKitDispatchBuildError.noFertilizerNeedsProduced
        }
        return needs
    }

    private static func buildSchedulePeriods(
        timingResult: VariTimingExecutionResult,
        fertilizerIDLookup: [String: ContractFertilizerType],
        preferredNPKForFallback: ContractFertilizerType?
    ) throws -> [FertilizationSchedulePeriodItem] {
        let rounds = timingResult.schedule.rounds.sorted { $0.round < $1.round }
        guard !rounds.isEmpty else {
            throw CloudKitDispatchBuildError.noScheduleRoundsProduced
        }

        let roundsCount = Double(max(1, timingResult.schedule.roundsPerYear))
        var periods: [FertilizationSchedulePeriodItem] = []

        for round in rounds {
            let startDate = try parseScheduleDate(round.startDate)
            let endDate = try parseScheduleDate(round.endDate)

            var items: [FertilizationScheduleFertilizerItem] = []
            for step in round.steps.sorted(by: { $0.step < $1.step }) {
                let contractType = try resolveScheduleStepFertilizerType(
                    step: step,
                    requestFertilizers: timingResult.request.fertilizers,
                    fertilizerIDLookup: fertilizerIDLookup,
                    preferredNPKForFallback: preferredNPKForFallback
                )
                if contractType.isGenericNPKSentinel {
                    throw CloudKitDispatchBuildError.forbiddenGenericNPKDetected
                }

                let amountPerRound = step.doseKg ?? ((step.annualDoseKg ?? 0.0) / roundsCount)
                items.append(
                    FertilizationScheduleFertilizerItem(
                        fertilizerType: contractType,
                        step: step.step,
                        amountPerRoundKg: amountPerRound,
                        doneAt: nil
                    )
                )
            }

            periods.append(
                FertilizationSchedulePeriodItem(
                    order: round.round,
                    startDate: startDate,
                    endDate: endDate,
                    fertilizers: items
                )
            )
        }

        return periods
    }

    private static func resolveScheduleStepFertilizerType(
        step: VariTimingStep,
        requestFertilizers: [VariTimingRequest.FertilizerInput],
        fertilizerIDLookup: [String: ContractFertilizerType],
        preferredNPKForFallback: ContractFertilizerType?
    ) throws -> ContractFertilizerType {
        // 1. Direct lookup table passed by VariTimingBuilder
        if let stepID = step.fertilizerId, let mapped = fertilizerIDLookup[stepID], !mapped.isGenericNPKSentinel {
            return mapped
        }

        // 2. Deterministic `"krops-..."` ID embedded in cached request/result JSON
        if let stepID = step.fertilizerId, let mapped = VariTimingBuilder.resolveContractType(fromID: stepID) {
            return mapped
        }

        // 3. Match input fertilizer by `id` or `name` and resolve NPK via `composition`
        if let inputMatch = requestFertilizers.first(where: {
            ($0.id != nil && $0.id == step.fertilizerId)
                || $0.name.caseInsensitiveCompare(step.name ?? "") == .orderedSame
        }) {
            if let id = inputMatch.id, let byID = VariTimingBuilder.resolveContractType(fromID: id) {
                return byID
            }
            if inputMatch.name.caseInsensitiveCompare("NPK") == .orderedSame {
                if let comp = inputMatch.composition,
                   let explicit = VariNPKRatio(
                       n: comp.n,
                       p2o5: comp.p,
                       k2o: comp.k,
                       mgo: comp.mg ?? 0
                   ).toExplicitContractNPKType()
                {
                    return explicit
                }
                if let fallback = preferredNPKForFallback, !fallback.isGenericNPKSentinel {
                    return fallback
                }
            }
        }

        // 4. Direct non-NPK name normalization
        let candidateName = step.name ?? step.displayName
        let trimmedLower = candidateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedLower == "npk" || trimmedLower.hasPrefix("npk") {
            if let fallback = preferredNPKForFallback, !fallback.isGenericNPKSentinel {
                return fallback
            }
            if let ratioParsed = parseNPKRatioFromDisplayName(candidateName)?.toExplicitContractNPKType() {
                return ratioParsed
            }
        } else if let direct = ContractFertilizerType(rawValue: candidateName), !direct.isGenericNPKSentinel {
            return direct
        }

        throw CloudKitDispatchBuildError.unmappableScheduleFertilizer(
            displayName: step.displayName,
            fertilizerID: step.fertilizerId
        )
    }

    private static func parseNPKRatioFromDisplayName(_ text: String) -> VariNPKRatio? {
        let cleaned = text
            .replacingOccurrences(of: "NPK", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-")))
        let parts = cleaned.split(separator: "-").compactMap { Double($0) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        return VariNPKRatio(
            n: parts[0],
            p2o5: parts[1],
            k2o: parts[2],
            mgo: parts.count == 4 ? parts[3] : 0
        )
    }

    private static func parseScheduleDate(_ raw: String) throws -> Date {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw CloudKitDispatchBuildError.invalidScheduleDate(raw)
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = jakartaTimeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        components.minute = 0
        components.second = 0
        guard let date = components.date else {
            throw CloudKitDispatchBuildError.invalidScheduleDate(raw)
        }
        return date
    }
}
