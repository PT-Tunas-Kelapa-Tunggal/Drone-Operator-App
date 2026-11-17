import CloudKit
import Foundation

public final class CloudKitOperatorReviewRepository: OperatorReviewRepository, @unchecked Sendable {
    public static let shared = CloudKitOperatorReviewRepository()
    private static let pollingIntervalNanoseconds: UInt64 = 10 * 60 * 1_000_000_000

    private let containerIdentifier: String
    private let database: CKDatabase
    private let domainMapper = PlantationDomainMapper()
    private let cacheLock = NSLock()
    private var cachedRecords: [String: CKRecord] = [:]

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
        let query = CKQuery(recordType: RecordKeys.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let (matchResults, _) = try await database.records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: nil,
            resultsLimit: 100
        )

        var requests: [PlantationReviewRequest] = []
        var fetchedCache: [String: CKRecord] = [:]

        for result in matchResults {
            do {
                let record = try result.1.get()
                fetchedCache[record.recordID.recordName] = record
                requests.append(domainMapper.toDomain(from: record))
            } catch {
                print(
                    "[CloudKitOperatorReviewRepository] Warning: Failed to fetch record: \(error.localizedDescription)"
                )
            }
        }

        cacheLock.withLock {
            for (key, record) in fetchedCache {
                cachedRecords[key] = record
            }
        }

        return requests.sorted { $0.timeline.submittedAt > $1.timeline.submittedAt }
    }

    public func fetchRequest(recordName: String) async throws -> PlantationReviewRequest? {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await database.record(for: recordID)
            cacheLock.withLock {
                cachedRecords[recordName] = record
            }
            return domainMapper.toDomain(from: record)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    public func dispatchCompletedReview(_ payload: ReviewDispatchPayload) async throws
        -> PlantationReviewRequest
    {
        let recordID = CKRecord.ID(recordName: payload.recordName)

        // Always fetch the latest server record first to preserve all iOS-owned fields & change tag;
        // fall back to cached record if offline read fails transiently after prior fetch.
        let existingRecord: CKRecord
        if let fresh = try? await database.record(for: recordID) {
            existingRecord = fresh
        } else if let cached = cacheLock.withLock({ cachedRecords[payload.recordName] }) {
            existingRecord = cached
        } else {
            existingRecord = try await database.record(for: recordID)
        }

        guard let plainZoneURL = payload.writer.variPlainZoneOverlayImageURL else {
            throw CloudKitDispatchBuildError.missingVariImage("oil_palm_zones_plain_with_separator.jpg")
        }
        guard let treeQuartileURL = payload.writer.variTreeQuartileOverlayImageURL else {
            throw CloudKitDispatchBuildError.missingVariImage("oil_palm_field_tree_vari_quartiles.jpg")
        }

        let plainZoneAsset = try CloudKitVARIImageCompressor.prepareForUpload(at: plainZoneURL)
        defer { plainZoneAsset.removeTemporaryFile() }
        let treeQuartileAsset = try CloudKitVARIImageCompressor.prepareForUpload(at: treeQuartileURL)
        defer { treeQuartileAsset.removeTemporaryFile() }

        var writer = payload.writer
        writer.variPlainZoneOverlayImageURL = plainZoneAsset.fileURL
        writer.variTreeQuartileOverlayImageURL = treeQuartileAsset.fileURL
        let recordToSave = try writer.buildRecord(existing: existingRecord)
        let savedRecord = try await MacOSScanRequestRecordWriter.save(record: recordToSave, to: database)

        cacheLock.withLock {
            cachedRecords[savedRecord.recordID.recordName] = savedRecord
        }

        var updatedRequest = domainMapper.toDomain(from: savedRecord)
        // Keep the original local URLs in the UI after temporary upload files are removed.
        updatedRequest.result = payload.summaryResult
        return updatedRequest
    }

    public func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let requests = try? await self.fetchAllRequests() {
                        continuation.yield(requests)
                    }
                    try? await Task.sleep(nanoseconds: Self.pollingIntervalNanoseconds)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
