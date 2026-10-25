import Foundation

public protocol OperatorReviewRepository: Sendable {
    /// Fetches all incoming/active review requests from CloudKit.
    func fetchAllRequests() async throws -> [PlantationReviewRequest]

    /// Fetches a specific review request by ID.
    func fetchRequest(id: UUID) async throws -> PlantationReviewRequest?

    /// Uploads the analysis results, attaches the preview asset, and marks the request as completed.
    func dispatchResult(requestID: UUID, result: PlantationReviewResult, previewAssetURL: URL?) async throws

    /// Real-time stream of incoming review requests.
    func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]>
}
