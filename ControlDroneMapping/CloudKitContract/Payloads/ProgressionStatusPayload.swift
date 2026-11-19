import Foundation

/// Progression status levels for a plantation scan request.
nonisolated public enum ProgressionStatus: Equatable, Sendable {
    case sent
    case scheduled
    case inProgress
    case finished
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .sent: return "Sent"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .finished: return "Finished"
        case .unknown(let raw): return raw
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "sent": self = .sent
        case "scheduled": self = .scheduled
        case "in progress", "inprogress": self = .inProgress
        case "finished": self = .finished
        default: self = .unknown(rawValue)
        }
    }
}

/// One event entry inside the progression status detail log.
nonisolated public struct ProgressionStatusDetailEvent: Codable, Equatable, Sendable {
    public let dateTime: Date
    public let title: String
    public let desc: String

    public init(dateTime: Date, title: String, desc: String) {
        self.dateTime = dateTime
        self.title = title
        self.desc = desc
    }
}
