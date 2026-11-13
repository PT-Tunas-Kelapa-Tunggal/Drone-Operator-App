import Foundation

/// Bundled contract writer payload and domain summary snapshot for dispatching completed review deliverables.
public struct ReviewDispatchPayload: Sendable {
    public let requestID: UUID
    public let recordName: String
    public let writer: MacOSScanRequestRecordWriter
    public let summaryResult: PlantationReviewResult

    public init(
        requestID: UUID,
        recordName: String,
        writer: MacOSScanRequestRecordWriter,
        summaryResult: PlantationReviewResult
    ) {
        self.requestID = requestID
        self.recordName = recordName
        self.writer = writer
        self.summaryResult = summaryResult
    }
}

public protocol OperatorReviewRepository: Sendable {
    /// Fetches all incoming/active review requests from CloudKit.
    func fetchAllRequests() async throws -> [PlantationReviewRequest]

    /// Fetches a specific review request by its authoritative CloudKit `recordName`.
    func fetchRequest(recordName: String) async throws -> PlantationReviewRequest?

    /// Saves all macOS-owned CloudKit deliverables using `.changedKeys` and returns the refreshed request.
    func dispatchCompletedReview(_ payload: ReviewDispatchPayload) async throws -> PlantationReviewRequest

    /// Real-time stream of incoming review requests.
    func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]>
}
