import Foundation

struct OperatorLocationSample: Equatable {
    var coordinate: MapCoordinate
    var accuracy: Double
    var timestamp: Date
    func isUsable(now: Date = Date()) -> Bool {
        coordinate.isValid && accuracy.isFinite && accuracy >= 0
            && (0...120).contains(now.timeIntervalSince(timestamp))
    }
}

enum OperatorLocationState: Equatable {
    case idle, locating, denied
    case unavailable(String)
    case available(OperatorLocationSample)
}

protocol OperatorLocationProviding: AnyObject {
    var onUpdate: ((OperatorLocationState) -> Void)? { get set }
    func request()
}
