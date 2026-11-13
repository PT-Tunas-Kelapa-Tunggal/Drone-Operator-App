import Foundation

public enum VariSubmissionBuildError: LocalizedError, Equatable, Sendable {
    case invalidSchemaVersion(found: Int64, expected: Int64)
    case contractFieldError(field: String, detail: String)
    case invalidFarmArea(Double)
    case invalidFertilizingFrequency(Int)
    case negativeBudget(Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion(let found, let expected):
            return "Versi kontrak CloudKit tidak kompatibel (ditemukan v\(found), diharapkan v\(expected))."
        case .contractFieldError(let field, let detail):
            return "Data CloudKit pada field '\(field)' bermasalah: \(detail)"
        case .invalidFarmArea(let area):
            return "Luas kebun dari CloudKit tidak valid (\(area) ha)."
        case .invalidFertilizingFrequency(let freq):
            return "Frekuensi pemupukan per tahun dari CloudKit tidak valid (\(freq)x/tahun)."
        case .negativeBudget(let budget):
            return "Anggaran pemupukan per hektare dari CloudKit tidak valid (Rp \(budget))."
        }
    }
}

public extension ContractFertilizerType {
    /// True for generic `.npk` and all explicit NPK formulation variants.
    var isNPKGroup: Bool {
        switch self {
        case .npk, .npk15_15_15, .npk12_6_22_3, .npk13_6_27_4, .npk13_8_27_4, .npk16_16_16:
            return true
        default:
            return false
        }
    }

    /// True only for the legacy untyped `.npk` sentinel (which macOS must never write to CloudKit).
    var isGenericNPKSentinel: Bool {
        self == .npk
    }

    /// Name format expected by `krops_vari.main` (`v2_engine.py`) fertilizer history parser.
    var variHistoryProductName: String {
        isNPKGroup ? "NPK" : rawValue
    }
}

public extension FertilizerUsage {
    /// Extracts N-P2O5-K2O-MgO ratio either from farmer composition elements or explicit NPK enum case.
    func effectiveNPKRatio() -> VariNPKRatio? {
        if !composition.isEmpty {
            var n: Double = 0
            var p: Double = 0
            var k: Double = 0
            var mg: Double = 0
            var foundAny = false
            for element in composition {
                let key = element.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                switch key {
                case "n", "nitrogen":
                    n = element.value
                    foundAny = true
                case "p", "p2o5", "fosfor", "phosphorus":
                    p = element.value
                    foundAny = true
                case "k", "k2o", "kalium", "potassium":
                    k = element.value
                    foundAny = true
                case "mg", "mgo", "magnesium":
                    mg = element.value
                    foundAny = true
                default:
                    break
                }
            }
            if foundAny {
                return VariNPKRatio(n: n, p2o5: p, k2o: k, mgo: mg)
            }
        }
        return VariNPKRatio(contractType: contractType)
    }

    func toVariCompositionInput() -> VariEngineSubmissionRequest.NPKCompositionInput? {
        guard contractType.isNPKGroup, let ratio = effectiveNPKRatio() else {
            return nil
        }
        return VariEngineSubmissionRequest.NPKCompositionInput(
            N: ratio.n,
            P: ratio.p2o5,
            K: ratio.k2o,
            Mg: ratio.mgo
        )
    }
}

/// Pure mapper transforming CloudKit-synced `PlantationReviewRequest` into `VariEngineSubmissionRequest`
/// (`krops_vari.main --user-request-submission-json`).
public enum VariSubmissionBuilder {
    private static let requiredCloudKitFields = [
        RecordKeys.iOSOwned.farmName,
        RecordKeys.iOSOwned.farmSize,
        RecordKeys.iOSOwned.plantingMonthAndYear,
        RecordKeys.iOSOwned.soilType,
        RecordKeys.iOSOwned.fertilizingFrequencyPerYear,
        RecordKeys.iOSOwned.fertilizersCompositions,
        RecordKeys.iOSOwned.fertilizationBudgetPerHa,
    ]

    public static func makeSubmission(
        from request: PlantationReviewRequest,
        referenceDate: Date = Date()
    ) throws -> VariEngineSubmissionRequest {
        if request.schemaVersion != ContractInfo.version {
            throw VariSubmissionBuildError.invalidSchemaVersion(
                found: request.schemaVersion,
                expected: ContractInfo.version
            )
        }

        for field in requiredCloudKitFields {
            if let errorMessage = request.fieldErrors[field] {
                throw VariSubmissionBuildError.contractFieldError(field: field, detail: errorMessage)
            }
        }

        guard request.garden.areaHectares > 0 else {
            throw VariSubmissionBuildError.invalidFarmArea(request.garden.areaHectares)
        }
        guard request.agronomy.fertilizingFrequencyPerYear > 0 else {
            throw VariSubmissionBuildError.invalidFertilizingFrequency(
                request.agronomy.fertilizingFrequencyPerYear
            )
        }
        guard request.agronomy.fertilizationBudgetPerHa >= 0 else {
            throw VariSubmissionBuildError.negativeBudget(request.agronomy.fertilizationBudgetPerHa)
        }

        let centroid = request.centroidCoordinate
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = calendar.component(.month, from: referenceDate)

        let historyItems: [VariEngineSubmissionRequest.FertilizerItemInput] = request.agronomy.fertilizerRecords
            .map { usage in
                VariEngineSubmissionRequest.FertilizerItemInput(
                    name: usage.contractType.variHistoryProductName,
                    bagKg: 50.0,
                    id: usage.id.uuidString,
                    dosePerTree: usage.doseKgPerTree,
                    composition: usage.toVariCompositionInput()
                )
            }

        let farmProfile = VariEngineSubmissionRequest.FarmProfileInput(
            name: request.garden.name,
            areaHa: request.garden.areaHectares,
            perimeterM: request.garden.circumferenceMeters > 0 ? request.garden.circumferenceMeters : nil,
            year: request.agronomy.plantingYear,
            soil: request.agronomy.soilType.rawValue,
            latitude: centroid?.latitude,
            longitude: centroid?.longitude,
            plantingMonth: request.agronomy.plantingMonth
        )

        let history = VariEngineSubmissionRequest.FertilizerHistoryInput(
            freq: request.agronomy.fertilizingFrequencyPerYear,
            fertilizers: historyItems
        )

        let harvest = request.agronomy.harvestRecord.map {
            VariEngineSubmissionRequest.HarvestYieldInput(
                freq: $0.frequencyPerMonth,
                weightKg: $0.latestWeightKg
            )
        }

        return VariEngineSubmissionRequest(
            farm: farmProfile,
            month: currentMonth,
            fertilizerHistory: history,
            harvest: harvest,
            fertilizerBudgetRp: request.totalBudgetRp
        )
    }
}
