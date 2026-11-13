import Foundation

/// Decoupled submission contract for the Iteration 2 VARI & Fertilizer Engine.
/// This matches the exact JSON schema required by `krops_vari` (`--user-request-submission-json`),
/// while remaining decoupled from ongoing CloudKit schema migrations.
public struct VariEngineSubmissionRequest: Codable, Sendable, Equatable {
    public struct FarmProfileInput: Codable, Sendable, Equatable {
        public var name: String
        public var areaHa: Double
        public var perimeterM: Double?
        public var year: Int?
        public var soil: String?
        public var latitude: Double?
        public var longitude: Double?
        public var plantingMonth: Int?

        public init(
            name: String,
            areaHa: Double,
            perimeterM: Double? = nil,
            year: Int? = nil,
            soil: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            plantingMonth: Int? = nil
        ) {
            self.name = name
            self.areaHa = areaHa
            self.perimeterM = perimeterM
            self.year = year
            self.soil = soil
            self.latitude = latitude
            self.longitude = longitude
            self.plantingMonth = plantingMonth
        }
    }

    public struct NPKCompositionInput: Codable, Sendable, Equatable {
        public var N: Double
        public var P: Double
        public var K: Double
        public var Mg: Double?

        public init(N: Double, P: Double, K: Double, Mg: Double? = nil) {
            self.N = N
            self.P = P
            self.K = K
            self.Mg = Mg
        }
    }

    public struct FertilizerItemInput: Codable, Sendable, Equatable {
        public var name: String
        public var bagKg: Double?
        public var id: String?
        public var dosePerTree: Double?
        public var composition: NPKCompositionInput?

        public init(
            name: String,
            bagKg: Double? = nil,
            id: String? = nil,
            dosePerTree: Double? = nil,
            composition: NPKCompositionInput? = nil
        ) {
            self.name = name
            self.bagKg = bagKg
            self.id = id
            self.dosePerTree = dosePerTree
            self.composition = composition
        }
    }

    public struct FertilizerHistoryInput: Codable, Sendable, Equatable {
        public var freq: Int?
        public var fertilizers: [FertilizerItemInput]

        public init(freq: Int? = nil, fertilizers: [FertilizerItemInput] = []) {
            self.freq = freq
            self.fertilizers = fertilizers
        }
    }

    public struct HarvestYieldInput: Codable, Sendable, Equatable {
        public var freq: Int?
        public var weightKg: Double?

        public init(freq: Int? = nil, weightKg: Double? = nil) {
            self.freq = freq
            self.weightKg = weightKg
        }
    }

    public var farm: FarmProfileInput
    public var month: Int?
    public var fertilizerHistory: FertilizerHistoryInput?
    public var harvest: HarvestYieldInput?
    public var fertilizerBudgetRp: Double?

    public init(
        farm: FarmProfileInput,
        month: Int? = nil,
        fertilizerHistory: FertilizerHistoryInput? = nil,
        harvest: HarvestYieldInput? = nil,
        fertilizerBudgetRp: Double? = nil
    ) {
        self.farm = farm
        self.month = month
        self.fertilizerHistory = fertilizerHistory
        self.harvest = harvest
        self.fertilizerBudgetRp = fertilizerBudgetRp
    }

    /// Deprecated test-only default request generator; production callers must use `VariSubmissionBuilder.makeSubmission(from:)`.
    @available(*, deprecated, message: "Gunakan VariSubmissionBuilder.makeSubmission(from:) agar seluruh input agronomi & anggaran berasal dari CloudKit.")
    public static func defaultSample(
        farmName: String = "Kebun Kelapa Sawit",
        areaHa: Double = 1.0,
        budgetRp: Double = 5_000_000
    ) -> VariEngineSubmissionRequest {
        VariEngineSubmissionRequest(
            farm: FarmProfileInput(
                name: farmName,
                areaHa: max(0.1, areaHa),
                perimeterM: 800,
                year: 2016,
                soil: "Mineral",
                latitude: nil,
                longitude: nil,
                plantingMonth: 5
            ),
            month: Calendar.current.component(.month, from: Date()),
            fertilizerHistory: FertilizerHistoryInput(
                freq: 2,
                fertilizers: [
                    FertilizerItemInput(
                        name: "Dolomite",
                        bagKg: 50,
                        id: UUID().uuidString,
                        dosePerTree: 1.0
                    ),
                    FertilizerItemInput(
                        name: "NPK",
                        bagKg: 50,
                        id: UUID().uuidString,
                        dosePerTree: 0.5,
                        composition: NPKCompositionInput(N: 15, P: 15, K: 15, Mg: 0)
                    )
                ]
            ),
            harvest: HarvestYieldInput(
                freq: 2,
                weightKg: 800
            ),
            fertilizerBudgetRp: budgetRp
        )
    }

    /// Serializes this request into the exact JSON format expected by `--user-request-submission-json`.
    public func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MappingError.invalid("Gagal mengonversi submission request ke UTF-8 string.")
        }
        return string
    }
}
