import Foundation

/// Soil classification known to the plantation contract.
nonisolated public enum ContractSoilType: Equatable, Sendable {
    case mineral
    case gambut
    case rawa
    case pasir
    case batu
    case lainnya
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .mineral: return "Mineral"
        case .gambut: return "Gambut"
        case .rawa: return "Rawa"
        case .pasir: return "Pasir"
        case .batu: return "Batu"
        case .lainnya: return "Lainnya"
        case .unknown(let raw): return raw
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "mineral": self = .mineral
        case "gambut": self = .gambut
        case "rawa": self = .rawa
        case "pasir": self = .pasir
        case "batu": self = .batu
        case "lainnya": self = .lainnya
        default: self = .unknown(rawValue)
        }
    }
}

public typealias CKSoilType = ContractSoilType
