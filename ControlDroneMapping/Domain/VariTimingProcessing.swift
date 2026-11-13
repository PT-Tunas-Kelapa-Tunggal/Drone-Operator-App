import Foundation

// MARK: - CLI Input Request Contract

/// Input payload matching `krops_vari.timing --request <path>`.
public struct VariTimingRequest: Codable, Sendable, Equatable {
    public struct Coordinate: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct Composition: Codable, Sendable, Equatable {
        public let n: Double
        public let p: Double
        public let k: Double
        public let mg: Double?

        enum CodingKeys: String, CodingKey {
            case n = "N"
            case p = "P"
            case k = "K"
            case mg = "Mg"
        }

        public init(n: Double, p: Double, k: Double, mg: Double? = nil) {
            self.n = n
            self.p = p
            self.k = k
            self.mg = mg
        }
    }

    public struct FertilizerInput: Codable, Sendable, Equatable {
        public let id: String?
        public let name: String
        public let overallDoseWeightInKg: Double
        public let composition: Composition?
        public let bagKg: Double?

        public init(
            id: String?,
            name: String,
            overallDoseWeightInKg: Double,
            composition: Composition? = nil,
            bagKg: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.overallDoseWeightInKg = overallDoseWeightInKg
            self.composition = composition
            self.bagKg = bagKg
        }
    }

    public struct ApplicationRecord: Codable, Sendable, Equatable {
        public let fertilizerId: String
        public let date: String

        public init(fertilizerId: String, date: String) {
            self.fertilizerId = fertilizerId
            self.date = date
        }
    }

    public let latitude: Double
    public let longitude: Double
    public let fertilizerFreq: Int
    public let fertilizers: [FertilizerInput]
    public let applications: [ApplicationRecord]?

    public init(
        latitude: Double,
        longitude: Double,
        fertilizerFreq: Int,
        fertilizers: [FertilizerInput],
        applications: [ApplicationRecord]? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.fertilizerFreq = fertilizerFreq
        self.fertilizers = fertilizers
        self.applications = applications
    }

    /// Resolves polygon centroid if non-empty.
    static func centroid(of points: [FarmArea.Point]?) -> Coordinate? {
        guard let points, !points.isEmpty else { return nil }
        let count = Double(points.count)
        let lat = points.reduce(0.0) { $0 + $1.latitude } / count
        let lon = points.reduce(0.0) { $0 + $1.longitude } / count
        guard lat.isFinite, lon.isFinite else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Pre-CloudKit placeholder request builder.
    ///
    /// TODO: Replace all hardcoded dummy fields (`fertilizerFreq`, `fertilizers`,
    /// `applications`, and fallback Batam coordinates) once CloudKit farm data synchronization
    /// per `data-structure-synchronization.md` is implemented.
    public static func placeholderTemplate(coordinate: Coordinate? = nil) -> VariTimingRequest {
        // Fallback coordinates match the pre-seeded Batam cell `n1.000_e104.3750`
        // so offline/first-run validation succeeds without network dependency.
        let effectiveLat = coordinate?.latitude ?? 1.0
        let effectiveLon = coordinate?.longitude ?? 104.375

        // TODO: Replace after CloudKit integration — read `Fertilizing Frequency per Year`,
        // `Fertilizers Compositions` + VARI dose totals, and farmer `applications[]` from CloudKit.
        return VariTimingRequest(
            latitude: effectiveLat,
            longitude: effectiveLon,
            fertilizerFreq: 3,
            fertilizers: [
                FertilizerInput(
                    id: "A01C2E47-5D6B-4B95-9D31-6A1C8217D045",
                    name: "Dolomite",
                    overallDoseWeightInKg: 1200.0,
                    composition: nil,
                    bagKg: 50.0
                ),
                FertilizerInput(
                    id: "D828E19B-7B72-4E11-A35D-B1B7D2F9C304",
                    name: "NPK",
                    overallDoseWeightInKg: 360.0,
                    composition: Composition(n: 15, p: 15, k: 15, mg: 0),
                    bagKg: 50.0
                ),
                FertilizerInput(
                    id: "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8",
                    name: "Urea",
                    overallDoseWeightInKg: 300.0,
                    composition: nil,
                    bagKg: 50.0
                ),
            ],
            applications: []
        )
    }
}

// MARK: - Output Schedule Contract (Schema 1.0)

/// Root output JSON decoded from `krops_vari.timing`.
public struct VariTimingSchedule: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let planYear: Int
    public let today: String
    public let roundsPerYear: Int
    public let rounds: [VariTimingRound]
    public let weatherBasis: VariTimingWeatherBasis
    public let flags: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case planYear = "plan_year"
        case today
        case roundsPerYear = "rounds_per_year"
        case rounds
        case weatherBasis = "weather_basis"
        case flags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        planYear = try c.decode(Int.self, forKey: .planYear)
        today = try c.decode(String.self, forKey: .today)
        roundsPerYear = try c.decode(Int.self, forKey: .roundsPerYear)
        rounds = try c.decode([VariTimingRound].self, forKey: .rounds)
        weatherBasis = try c.decode(VariTimingWeatherBasis.self, forKey: .weatherBasis)
        flags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
    }
}

public struct VariTimingRound: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { round }

    public let round: Int
    public let startMonth: Int
    public let startMonthName: String
    public let endMonth: Int
    public let endMonthName: String
    public let startDate: String
    public let endDate: String
    public let status: String
    public let daysUntilStart: Int?
    public let dayOfRound: Int?
    public let totalDays: Int
    public let card: VariTimingRoundCard
    public let daily: VariTimingDailyAssessment?
    public let steps: [VariTimingStep]

    enum CodingKeys: String, CodingKey {
        case round
        case startMonth = "start_month"
        case startMonthName = "start_month_name"
        case endMonth = "end_month"
        case endMonthName = "end_month_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case status
        case daysUntilStart = "days_until_start"
        case dayOfRound = "day_of_round"
        case totalDays = "total_days"
        case card
        case daily
        case steps
    }
}

public struct VariTimingRoundCard: Codable, Sendable, Equatable {
    /// Expected values: `"upcoming"`, `"ongoing"`, `"started"`, `"period_passed"`, `"completed"`.
    public let state: String
    public let daysUntilStart: Int?
    public let dayOfRound: Int?
    public let totalDays: Int?
    public let startedOn: String?
    public let periodEnd: String?
    public let completedOn: String?

    enum CodingKeys: String, CodingKey {
        case state
        case daysUntilStart = "days_until_start"
        case dayOfRound = "day_of_round"
        case totalDays = "total_days"
        case startedOn = "started_on"
        case periodEnd = "period_end"
        case completedOn = "completed_on"
    }
}

public struct VariTimingDailyAssessment: Codable, Sendable, Equatable {
    public let checkedOn: String
    public let referenceDay: String
    public let l5: VariTimingL5Assessment?
    public let l8: VariTimingL8Assessment
    public let wait: String?

    enum CodingKeys: String, CodingKey {
        case checkedOn = "checked_on"
        case referenceDay = "reference_day"
        case l5
        case l8
        case wait
    }
}

public struct VariTimingL5Assessment: Codable, Sendable, Equatable {
    public let p30Mm: Double?
    public let p30StartDate: String?
    public let p30EndDate: String?
    public let p30Source: String?
    public let waterStress: Bool?
    public let p30Quality: String?
    public let p30MissingDays: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case p30Mm = "p30_mm"
        case p30StartDate = "p30_start_date"
        case p30EndDate = "p30_end_date"
        case p30Source = "p30_source"
        case waterStress = "water_stress"
        case p30Quality = "p30_quality"
        case p30MissingDays = "p30_missing_days"
    }
}

public struct VariTimingL8Assessment: Codable, Sendable, Equatable {
    /// Expected values: `"tunda"`, `"cek"`, `"cek_hujan"`, `"jendela_tabur"`.
    public let state: String
    public let monthGate: VariTimingMonthGate
    public let safeDays: [String]
    public let removed: VariTimingRemovedDays

    enum CodingKeys: String, CodingKey {
        case state
        case monthGate = "month_gate"
        case safeDays = "safe_days"
        case removed
    }
}

public struct VariTimingMonthGate: Codable, Sendable, Equatable {
    public let month: Int
    public let avgMm: Double
    public let gate: String

    enum CodingKeys: String, CodingKey {
        case month
        case avgMm = "avg_mm"
        case gate
    }
}

public struct VariTimingRemovedDays: Codable, Sendable, Equatable {
    public let heavy: [String]
    public let dayBeforeHeavy: [String]
    public let lastCached: [String]

    enum CodingKeys: String, CodingKey {
        case heavy
        case dayBeforeHeavy = "day_before_heavy"
        case lastCached = "last_cached"
    }

    public init(heavy: [String] = [], dayBeforeHeavy: [String] = [], lastCached: [String] = []) {
        self.heavy = heavy
        self.dayBeforeHeavy = dayBeforeHeavy
        self.lastCached = lastCached
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heavy = try c.decodeIfPresent([String].self, forKey: .heavy) ?? []
        dayBeforeHeavy = try c.decodeIfPresent([String].self, forKey: .dayBeforeHeavy) ?? []
        lastCached = try c.decodeIfPresent([String].self, forKey: .lastCached) ?? []
    }

    public var isEmpty: Bool {
        heavy.isEmpty && dayBeforeHeavy.isEmpty && lastCached.isEmpty
    }

    public var totalCount: Int {
        heavy.count + dayBeforeHeavy.count + lastCached.count
    }
}

public struct VariTimingStep: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { step }

    public let step: Int
    public let fertilizerId: String?
    public let name: String?
    public let displayName: String
    public let doseKg: Double?
    public let annualDoseKg: Double?
    public let bagKg: Double?
    public let waitAfterDays: VariTimingWaitWindow?
    public let card: VariTimingStepCard
    public let schedule: VariTimingStepSchedule?

    enum CodingKeys: String, CodingKey {
        case step
        case fertilizerId = "fertilizer_id"
        case name
        case displayName = "display_name"
        case doseKg = "dose_kg"
        case annualDoseKg = "annual_dose_kg"
        case bagKg = "bag_kg"
        case waitAfterDays = "wait_after_days"
        case card
        case schedule
    }
}

public struct VariTimingWaitWindow: Codable, Sendable, Equatable {
    public let min: Int
    public let max: Int?
    /// Expected values: `"idle"`, `"counting"`, `"done"`.
    public let state: String
    public let until: String?
}

public struct VariTimingStepCard: Codable, Sendable, Equatable {
    /// Expected values: `"locked"`, `"ready"`, `"waiting"`, `"done"`, `"overdue"`.
    public let state: String
    public let availableFrom: String?
    public let deadline: String?
    public let doneOn: String?
    public let overdueSince: String?

    enum CodingKeys: String, CodingKey {
        case state
        case availableFrom = "available_from"
        case deadline
        case doneOn = "done_on"
        case overdueSince = "overdue_since"
    }
}

public struct VariTimingStepSchedule: Codable, Sendable, Equatable {
    /// Expected values: `"done"`, `"planned"`, `"not_before"`, `"wait"`.
    public let status: String
    public let date: String?
    public let notBefore: String?
    public let wait: String?

    enum CodingKeys: String, CodingKey {
        case status
        case date
        case notBefore = "not_before"
        case wait
    }
}

public struct VariTimingWeatherBasis: Codable, Sendable, Equatable {
    public let rule: String
    public let period: [Int]?
    public let months: [String: VariTimingMonthlyClimate]
    public let candidateSets: [VariTimingCandidateSet]
    public let note: String

    enum CodingKeys: String, CodingKey {
        case rule
        case period
        case months
        case candidateSets = "candidate_sets"
        case note
    }
}

public struct VariTimingMonthlyClimate: Codable, Sendable, Equatable {
    public let name: String
    public let avgMm: Double
    public let inBandShare: Double
    public let gate: String

    enum CodingKeys: String, CodingKey {
        case name
        case avgMm = "avg_mm"
        case inBandShare = "in_band_share"
        case gate
    }
}

public struct VariTimingCandidateSet: Codable, Sendable, Equatable, Identifiable {
    public var id: String { months.joined(separator: "-") }

    public let months: [String]
    public let inBandShare: Double

    enum CodingKeys: String, CodingKey {
        case months
        case inBandShare = "in_band_share"
    }
}

// MARK: - Execution Options, Result & Processor Protocol

public struct WeatherKitCredentials: Sendable, Equatable {
    public let teamID: String
    public let keyID: String
    public let serviceID: String
    public let keyFileURL: URL

    public init(teamID: String, keyID: String, serviceID: String, keyFileURL: URL) {
        self.teamID = teamID
        self.keyID = keyID
        self.serviceID = serviceID
        self.keyFileURL = keyFileURL
    }
}

public struct VariTimingRunOptions: Sendable, Equatable {
    public let skipDaily: Bool
    /// Reserved optional CLI overrides (`--today YYYY-MM-DD`, `--year INT`).
    /// Currently always nil in normal app flows unless explicitly supplied by future caller.
    public let todayOverride: String?
    public let yearOverride: Int?
    public let weatherKit: WeatherKitCredentials?

    public init(
        skipDaily: Bool = false,
        todayOverride: String? = nil,
        yearOverride: Int? = nil,
        weatherKit: WeatherKitCredentials? = nil
    ) {
        self.skipDaily = skipDaily
        self.todayOverride = todayOverride
        self.yearOverride = yearOverride
        self.weatherKit = weatherKit
    }
}

public struct VariTimingExecutionResult: Sendable, Equatable {
    public let request: VariTimingRequest
    public let schedule: VariTimingSchedule
    public let requestJSONURL: URL
    public let resultJSONURL: URL
    public let cacheDirectoryURL: URL
    public let ranAt: Date

    public init(
        request: VariTimingRequest,
        schedule: VariTimingSchedule,
        requestJSONURL: URL,
        resultJSONURL: URL,
        cacheDirectoryURL: URL,
        ranAt: Date
    ) {
        self.request = request
        self.schedule = schedule
        self.requestJSONURL = requestJSONURL
        self.resultJSONURL = resultJSONURL
        self.cacheDirectoryURL = cacheDirectoryURL
        self.ranAt = ranAt
    }
}

public enum VariTimingError: LocalizedError, Sendable {
    case missingPythonHelper
    case executionFailed(code: Int32, detail: String)
    case missingOutputFile(URL)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingPythonHelper:
            return "Helper binary VariPython belum disertakan atau belum dapat dieksekusi."
        case .executionFailed(let code, let detail):
            return "Analisis jadwal pemupukan gagal (exit code \(code)): \(detail)"
        case .missingOutputFile(let url):
            return "Berkas output jadwal tidak ditemukan di \(url.path)."
        case .invalidJSON(let message):
            return "Format JSON jadwal pemupukan tidak valid: \(message)"
        }
    }
}

public protocol VariTimingProcessing: Sendable {
    func runTiming(
        request: VariTimingRequest,
        options: VariTimingRunOptions,
        outputFolder: URL
    ) async throws -> VariTimingExecutionResult

    func loadCachedResult(in outputFolder: URL) -> VariTimingExecutionResult?
}
