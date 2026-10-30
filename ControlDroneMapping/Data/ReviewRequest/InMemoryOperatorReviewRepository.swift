import Foundation

public final class InMemoryOperatorReviewRepository: OperatorReviewRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PlantationReviewRequest]

    public init(initialRequests: [PlantationReviewRequest] = []) {
        self.requests = initialRequests
    }

    public func fetchAllRequests() async throws -> [PlantationReviewRequest] {
        lock.withLock {
            requests
        }
    }

    public func fetchRequest(id: UUID) async throws -> PlantationReviewRequest? {
        lock.withLock {
            requests.first { $0.id == id }
        }
    }

    public func dispatchResult(requestID: UUID, result: PlantationReviewResult, previewAssetURL: URL?) async throws {
        lock.withLock {
            guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
            requests[index].status = .completed
            requests[index].timeline.completedAt = result.completedAt
            requests[index].result = result
        }
    }

    public func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]> {
        AsyncStream { continuation in
            continuation.yield(self.currentRequests())
        }
    }

    private func currentRequests() -> [PlantationReviewRequest] {
        lock.withLock {
            requests
        }
    }
}
