import CloudKit
import Foundation

public final class CloudKitOperatorReviewRepository: OperatorReviewRepository, @unchecked Sendable {
    public static let shared = CloudKitOperatorReviewRepository()

    private let containerIdentifier: String
    private let database: CKDatabase
    private let domainMapper = PlantationDomainMapper()
    private let jsonEncoder = JSONEncoder()

    public init(database: CKDatabase? = nil, containerIdentifier: String? = nil) {
        let resolvedID = containerIdentifier ?? AppConfiguration.current.cloudKitContainerIdentifier
        self.containerIdentifier = resolvedID
        if let database {
            self.database = database
        } else {
            let container = CKContainer(identifier: resolvedID)
            self.database = container.publicCloudDatabase
        }
    }

    public func fetchAllRequests() async throws -> [PlantationReviewRequest] {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: PlantationRecordCKAdapter.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let (matchResults, _) = try await database.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100)
        var requests: [PlantationReviewRequest] = []
        for result in matchResults {
            if let record = try? result.1.get(),
               let dto = try? PlantationRecordCKAdapter.toDTO(from: record),
               let domain = try? domainMapper.toDomain(from: dto) {
                requests.append(domain)
            }
        }
        return requests
    }

    public func fetchRequest(id: UUID) async throws -> PlantationReviewRequest? {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = try await database.record(for: recordID)
        let dto = try PlantationRecordCKAdapter.toDTO(from: record)
        return try domainMapper.toDomain(from: dto)
    }

    public func dispatchResult(requestID: UUID, result: PlantationReviewResult, previewAssetURL: URL?) async throws {
        let recordID = CKRecord.ID(recordName: requestID.uuidString)
        let record = try await database.record(for: recordID)

        let resultDTO = PlantationReviewResultDTO(
            completedAt: result.completedAt,
            nutrients: result.nutrients.map { NutrientMetricDTO(name: $0.name, current: $0.current, target: $0.target) },
            costs: result.costs.map { CostEstimateDTO(name: $0.name, quantity: $0.quantity, cost: $0.cost) },
            totalCostFormatted: result.totalCostFormatted,
            areas: result.allocationAreas.map { area in
                AreaPlanDTO(
                    areaID: area.id,
                    periods: area.periods.map { period in
                        PeriodPlanDTO(
                            title: period.title,
                            dateRange: period.dateRange,
                            lines: period.lines.map {
                                DoseLineDTO(name: $0.name, total: $0.total, dosage: $0.dosage)
                            }
                        )
                    }
                )
            }
        )

        let resultData = try jsonEncoder.encode(resultDTO)
        let resultJSON = String(decoding: resultData, as: UTF8.self)

        record[PlantationRecordCKAdapter.Field.resultJSON] = resultJSON as CKRecordValue
        record[PlantationRecordCKAdapter.Field.statusCode] = ReviewStatus.completed.rawValue as CKRecordValue
        record[PlantationRecordCKAdapter.Field.completedAt] = result.completedAt as CKRecordValue

        if let assetURL = previewAssetURL ?? result.orthomosaicImageURL {
            record[PlantationRecordCKAdapter.Field.orthomosaicAsset] = CKAsset(fileURL: assetURL)
        }

        _ = try await database.save(record)
    }

    public func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let requests = try? await self.fetchAllRequests() {
                        continuation.yield(requests)
                    }
                    try? await Task.sleep(nanoseconds: 8_000_000_000) // Poll every 8s
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
