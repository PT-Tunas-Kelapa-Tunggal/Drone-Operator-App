import Foundation

/// Review workflow status aligned with `CloudKitContract.ProgressionStatus`.
public enum ReviewStatus: Equatable, Codable, Sendable {
    case sent
    case scheduled
    case inProgress
    case finished
    case unknown(String)

    public init(progressionStatus: ProgressionStatus) {
        switch progressionStatus {
        case .sent: self = .sent
        case .scheduled: self = .scheduled
        case .inProgress: self = .inProgress
        case .finished: self = .finished
        case .unknown(let raw): self = .unknown(raw)
        }
    }

    public init(rawValue: String) {
        self.init(progressionStatus: ProgressionStatus(rawValue: rawValue))
    }

    public var progressionStatus: ProgressionStatus {
        switch self {
        case .sent: return .sent
        case .scheduled: return .scheduled
        case .inProgress: return .inProgress
        case .finished: return .finished
        case .unknown(let raw): return .unknown(raw)
        }
    }

    public var rawValue: String {
        progressionStatus.rawValue
    }

    public var isFinished: Bool {
        self == .finished
    }

    public var title: String {
        switch self {
        case .sent: return "Menunggu Survei"
        case .scheduled: return "Dijadwalkan"
        case .inProgress: return "Sedang Diproses"
        case .finished: return "Selesai"
        case .unknown(let raw): return raw.isEmpty ? "Tidak Diketahui" : raw
        }
    }
}

/// Progression timeline entry mirrored to/from `CloudKitContract.ProgressionStatusDetailEvent`.
public struct ReviewProgressionEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(dateTime.timeIntervalSince1970)-\(title)" }
    public let dateTime: Date
    public let title: String
    public let desc: String

    public init(dateTime: Date, title: String, desc: String) {
        self.dateTime = dateTime
        self.title = title
        self.desc = desc
    }

    public init(contractEvent: ProgressionStatusDetailEvent) {
        self.dateTime = contractEvent.dateTime
        self.title = contractEvent.title
        self.desc = contractEvent.desc
    }

    public var contractEvent: ProgressionStatusDetailEvent {
        ProgressionStatusDetailEvent(dateTime: dateTime, title: title, desc: desc)
    }
}
