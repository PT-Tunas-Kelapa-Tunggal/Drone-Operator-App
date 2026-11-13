import Foundation

/// Errors emitted when converting an unrecognized string into `ContractFertilizerType`.
nonisolated public enum ContractFertilizerTypeError: LocalizedError, Equatable, Sendable {
    case unknownFertilizerType(String)

    public var errorDescription: String? {
        switch self {
        case .unknownFertilizerType(let rawValue):
            let allowed = ContractFertilizerType.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown fertilizer type '\(rawValue)'. Allowed values: \(allowed)."
        }
    }
}

/// Known fertilizer classifications across the plantation contract.
/// Unrecognized values are rejected with an error rather than stored as arbitrary strings.
nonisolated public enum ContractFertilizerType: RawRepresentable, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case npk
    case npk15_15_15
    case npk12_6_22_3
    case npk13_6_27_4
    case npk13_8_27_4
    case npk16_16_16
    case dolomite
    case urea
    case sp36
    case kcl
    case kieserite
    case za
    case tsp
    case borat
    case pupukKandang
    case pupukOrganik
    case lainnya

    public var rawValue: String {
        switch self {
        case .npk: return "NPK"
        case .npk15_15_15: return "NPK-15-15-15"
        case .npk12_6_22_3: return "NPK-12-6-22-3"
        case .npk13_6_27_4: return "NPK-13-6-27-4"
        case .npk13_8_27_4: return "NPK-13-8-27-4"
        case .npk16_16_16: return "NPK-16-16-16"
        case .dolomite: return "Dolomite"
        case .urea: return "Urea"
        case .sp36: return "SP-36"
        case .kcl: return "KCl"
        case .kieserite: return "Kieserite"
        case .za: return "ZA"
        case .tsp: return "TSP"
        case .borat: return "Borat"
        case .pupukKandang: return "Pupuk Kandang"
        case .pupukOrganik: return "Pupuk Organik"
        case .lainnya: return "Lainnya"
        }
    }

    /// Failable raw-value initializer normalizing known aliases; returns `nil` when unrecognized.
    public init?(rawValue: String) {
        guard let matched = Self.match(rawValue) else {
            return nil
        }
        self = matched
    }

    /// Strictly casts a string to `ContractFertilizerType`, throwing `ContractFertilizerTypeError` if unknown.
    public init(_ rawValue: String) throws {
        guard let matched = Self.match(rawValue) else {
            throw ContractFertilizerTypeError.unknownFertilizerType(rawValue)
        }
        self = matched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        do {
            try self.init(raw)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func match(_ rawValue: String) -> ContractFertilizerType? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "npk":
            return .npk
        case "npk-15-15-15":
            return .npk15_15_15
        case "npk-12-6-22-3":
            return .npk12_6_22_3
        case "npk-13-6-27-4":
            return .npk13_6_27_4
        case "npk-13-8-27-4":
            return .npk13_8_27_4
        case "npk-16-16-16":
            return .npk16_16_16
        case "dolomite", "dolomit":
            return .dolomite
        case "urea":
            return .urea
        case "sp-36", "sp36", "sp 36":
            return .sp36
        case "kcl", "mop", "kcl (mop)", "kcl/mop":
            return .kcl
        case "kieserite", "kieserit":
            return .kieserite
        case "za":
            return .za
        case "tsp":
            return .tsp
        case "borat", "borate":
            return .borat
        case "pupuk kandang", "pupuk_kandang":
            return .pupukKandang
        case "pupuk organik", "pupuk_organik":
            return .pupukOrganik
        case "lainnya", "other":
            return .lainnya
        default:
            return nil
        }
    }
}
