import Foundation

public enum ReviewStatus: Int, CaseIterable, Codable, Sendable {
    case submitted = 0
    case scheduled = 1
    case inReview = 2
    case completed = 3

    public var title: String {
        switch self {
        case .submitted: return "Permintaan Baru"
        case .scheduled: return "Dijadwalkan"
        case .inReview: return "Peninjauan Berlangsung"
        case .completed: return "Selesai"
        }
    }
}
