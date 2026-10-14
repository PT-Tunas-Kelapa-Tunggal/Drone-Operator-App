import Combine
import Foundation

/// Commands and snapshots are independent from the Multipeer implementation.
/// Callbacks and observable transport state are delivered on the main queue.
protocol LocalTransport: AnyObject {
    var connected: Bool { get set }
    var status: String { get set }
    var sending: Bool { get }
    var receiving: Bool { get }
    var store: any DatasetRepository { get }
    var onPacket: ((Packet) -> Void)? { get set }
    var onConnect: (() -> Void)? { get set }
    var connectionChanges: AnyPublisher<Bool, Never> { get }
    func send(_ packet: Packet) throws
    func export(_ id: UUID) throws
}
