import Foundation

public enum VariTimingBuildError: LocalizedError, Equatable, Sendable {
    case contractFieldError(field: String, detail: String)
    case missingBoundaryCoordinate
    case invalidFertilizingFrequency(Int)
    case missingValidNPKOption
    case noFertilizersForTiming

    public var errorDescription: String? {
        switch self {
        case .contractFieldError(let field, let detail):
            return "Data CloudKit pada field '\(field)' bermasalah: \(detail)"
        case .missingBoundaryCoordinate:
            return "Batas kebun (farmBoundary) dari CloudKit kosong sehingga koordinat cuaca tidak dapat dihitung."
        case .invalidFertilizingFrequency(let freq):
            return "Frekuensi pemupukan per tahun tidak valid (\(freq)x/tahun)."
        case .missingValidNPKOption:
            return "Tidak ditemukan varian NPK kontrak yang valid dari hasil VARI & HARA."
        case .noFertilizersForTiming:
            return "Tidak ada dosis pupuk (Dolomite, NPK, atau Urea) yang dapat dijadwalkan."
        }
    }
}

/// Real `VariTimingRequest` plus deterministic lookup table back to explicit CloudKit fertilizer enums.
public struct VariTimingBuildOutput: Sendable, Equatable {
    public let request: VariTimingRequest
    public let fertilizerIDLookup: [String: ContractFertilizerType]
    public let selectedNPKType: ContractFertilizerType?
    public let selectedNPKCandidate: VariBudgetCandidate?
    public let dolomiteTotalKg: Double
    public let ureaTotalKg: Double
    public let npkTotalKg: Double

    public init(
        request: VariTimingRequest,
        fertilizerIDLookup: [String: ContractFertilizerType],
        selectedNPKType: ContractFertilizerType?,
        selectedNPKCandidate: VariBudgetCandidate?,
        dolomiteTotalKg: Double,
        ureaTotalKg: Double,
        npkTotalKg: Double
    ) {
        self.request = request
        self.fertilizerIDLookup = fertilizerIDLookup
        self.selectedNPKType = selectedNPKType
        self.selectedNPKCandidate = selectedNPKCandidate
        self.dolomiteTotalKg = dolomiteTotalKg
        self.ureaTotalKg = ureaTotalKg
        self.npkTotalKg = npkTotalKg
    }
}

/// Pure builder converting CloudKit farmer request + `VariScanResult` into `VariTimingRequest`
/// (`krops_vari.timing`).
public enum VariTimingBuilder {
    public static let dolomiteID = "krops-dolomite"
    public static let ureaID = "krops-urea"
    public static let npkIDPrefix = "krops-"

    public static func deterministicID(for type: ContractFertilizerType) -> String {
        switch type {
        case .dolomite: return dolomiteID
        case .urea: return ureaID
        default: return "\(npkIDPrefix)\(type.rawValue.lowercased())"
        }
    }

    /// Parses deterministic ID back to explicit `ContractFertilizerType` (returns nil for `.npk`).
    public static func resolveContractType(fromID id: String) -> ContractFertilizerType? {
        if id == dolomiteID { return .dolomite }
        if id == ureaID { return .urea }
        guard id.hasPrefix(npkIDPrefix) else { return nil }
        let suffix = String(id.dropFirst(npkIDPrefix.count))
        guard let candidate = ContractFertilizerType(rawValue: suffix), !candidate.isGenericNPKSentinel else {
            return nil
        }
        return candidate
    }

    public static func makeRequest(
        from request: PlantationReviewRequest,
        variResult: VariScanResult,
        preferredNPK: ContractFertilizerType? = nil
    ) throws -> VariTimingBuildOutput {
        for field in [
            RecordKeys.iOSOwned.farmBoundary,
            RecordKeys.iOSOwned.fertilizingFrequencyPerYear,
        ] {
            if let detail = request.fieldErrors[field] {
                throw VariTimingBuildError.contractFieldError(field: field, detail: detail)
            }
        }

        guard let centroid = request.centroidCoordinate else {
            throw VariTimingBuildError.missingBoundaryCoordinate
        }
        guard request.agronomy.fertilizingFrequencyPerYear > 0 else {
            throw VariTimingBuildError.invalidFertilizingFrequency(
                request.agronomy.fertilizingFrequencyPerYear
            )
        }

        // Sum zone-level Dolomite and Urea rounded annual totals (excludes Kieserite, ZA, and summary rows).
        let dolomiteTotalKg = VariDoseRounding.roundToHalfKg(
            variResult.products
                .filter { $0.zoneID != nil && isDolomiteProduct($0.productName) }
                .reduce(0.0) { $0 + $1.roundedCombinedKg }
        )

        let ureaTotalKg = VariDoseRounding.roundToHalfKg(
            variResult.products
                .filter { $0.zoneID != nil && isUreaProduct($0.productName) }
                .reduce(0.0) { $0 + $1.roundedCombinedKg }
        )

        let chosenCandidate = resolveSelectedNPKCandidate(
            from: variResult.budget?.candidates ?? [],
            preferredNPK: preferredNPK
        )

        var fertilizers: [VariTimingRequest.FertilizerInput] = []
        var lookup: [String: ContractFertilizerType] = [:]

        if dolomiteTotalKg > 0 {
            fertilizers.append(
                VariTimingRequest.FertilizerInput(
                    id: dolomiteID,
                    name: "Dolomite",
                    overallDoseWeightInKg: dolomiteTotalKg,
                    composition: nil,
                    bagKg: 50.0
                )
            )
            lookup[dolomiteID] = .dolomite
        }

        var selectedNPKType: ContractFertilizerType?
        var npkTotalKg: Double = 0
        if let chosenCandidate,
           let explicitNPK = chosenCandidate.explicitNPKType,
           !explicitNPK.isGenericNPKSentinel,
           let annualKg = chosenCandidate.recommendedAnnualKgFarm,
           annualKg > 0
        {
            let ratio = chosenCandidate.labelRatioValues ?? VariNPKRatio(contractType: explicitNPK)
            let npkID = deterministicID(for: explicitNPK)
            // Always send `"name": "NPK"` to `krops_vari.timing` so Python assigns Group 1 without UNKNOWN_PRODUCT.
            // Deterministic `id` preserves the exact explicit `.npk*` enum for CloudKit dispatch.
            fertilizers.append(
                VariTimingRequest.FertilizerInput(
                    id: npkID,
                    name: "NPK",
                    overallDoseWeightInKg: annualKg,
                    composition: ratio.map {
                        VariTimingRequest.Composition(
                            n: $0.n,
                            p: $0.p2o5,
                            k: $0.k2o,
                            mg: $0.mgo
                        )
                    },
                    bagKg: chosenCandidate.bagSizeKg > 0 ? chosenCandidate.bagSizeKg : 50.0
                )
            )
            lookup[npkID] = explicitNPK
            selectedNPKType = explicitNPK
            npkTotalKg = annualKg
        } else if !(variResult.budget?.candidates ?? []).isEmpty {
            throw VariTimingBuildError.missingValidNPKOption
        }

        if ureaTotalKg > 0 {
            fertilizers.append(
                VariTimingRequest.FertilizerInput(
                    id: ureaID,
                    name: "Urea",
                    overallDoseWeightInKg: ureaTotalKg,
                    composition: nil,
                    bagKg: 50.0
                )
            )
            lookup[ureaID] = .urea
        }

        guard !fertilizers.isEmpty else {
            throw VariTimingBuildError.noFertilizersForTiming
        }

        let timingRequest = VariTimingRequest(
            latitude: centroid.latitude,
            longitude: centroid.longitude,
            fertilizerFreq: request.agronomy.fertilizingFrequencyPerYear,
            fertilizers: fertilizers,
            applications: []
        )

        return VariTimingBuildOutput(
            request: timingRequest,
            fertilizerIDLookup: lookup,
            selectedNPKType: selectedNPKType,
            selectedNPKCandidate: chosenCandidate,
            dolomiteTotalKg: dolomiteTotalKg,
            ureaTotalKg: ureaTotalKg,
            npkTotalKg: npkTotalKg
        )
    }

    public static func isDolomiteProduct(_ productName: String) -> Bool {
        let lower = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "dolomite_mg_cheaper" || lower == "dolomite"
    }

    public static func isUreaProduct(_ productName: String) -> Bool {
        let lower = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "urea_n_expensive" || lower == "urea"
    }

    public static func resolveSelectedNPKCandidate(
        from candidates: [VariBudgetCandidate],
        preferredNPK: ContractFertilizerType? = nil
    ) -> VariBudgetCandidate? {
        let validCandidates = candidates.filter { candidate in
            guard let explicit = candidate.explicitNPKType, !explicit.isGenericNPKSentinel else {
                return false
            }
            return (candidate.recommendedAnnualKgFarm ?? 0) > 0
        }
        if let preferredNPK,
           let matchedPreferred = validCandidates.first(where: { $0.explicitNPKType == preferredNPK })
        {
            return matchedPreferred
        }
        if let closest = validCandidates.first(where: { $0.isClosest }) {
            return closest
        }
        return validCandidates.first
    }
}
