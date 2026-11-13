import CloudKit
import Foundation

/// Writer for the macOS Drone Operator application.
/// Enforces field ownership by only writing macOS-owned fields and saving with `savePolicy = .changedKeys`.
nonisolated public struct MacOSScanRequestRecordWriter: Sendable {
    public var recordName: String?
    public var progressionStatus: ProgressionStatus?
    public var progressionStatusDetail: [ProgressionStatusDetailEvent]?
    public var orthomosaicImageURL: URL?
    public var fertilizingZone: [FertilizingZoneItem]?
    public var fertilizerNeedPerZone: [FertilizerNeedItem]?
    public var treeIdentification: [TreeIdentificationItem]?
    public var plannedOperatorVisitDate: Date?
    public var resultSentAt: Date?
    public var fertilizationScheduling: [FertilizationSchedulePeriodItem]?

    public init(
        recordName: String? = nil,
        progressionStatus: ProgressionStatus? = nil,
        progressionStatusDetail: [ProgressionStatusDetailEvent]? = nil,
        orthomosaicImageURL: URL? = nil,
        fertilizingZone: [FertilizingZoneItem]? = nil,
        fertilizerNeedPerZone: [FertilizerNeedItem]? = nil,
        treeIdentification: [TreeIdentificationItem]? = nil,
        plannedOperatorVisitDate: Date? = nil,
        resultSentAt: Date? = nil,
        fertilizationScheduling: [FertilizationSchedulePeriodItem]? = nil
    ) {
        self.recordName = recordName
        self.progressionStatus = progressionStatus
        self.progressionStatusDetail = progressionStatusDetail
        self.orthomosaicImageURL = orthomosaicImageURL
        self.fertilizingZone = fertilizingZone
        self.fertilizerNeedPerZone = fertilizerNeedPerZone
        self.treeIdentification = treeIdentification
        self.plannedOperatorVisitDate = plannedOperatorVisitDate
        self.resultSentAt = resultSentAt
        self.fertilizationScheduling = fertilizationScheduling
    }

    /// Mutates a `CKRecord` applying ONLY non-nil fields owned by macOS.
    public func applyToRecord(_ record: CKRecord) throws {
        record[RecordKeys.schemaVersion] = ContractInfo.version as CKRecordValue

        if let progressionStatus {
            record[RecordKeys.MacOSOwned.progressionStatus] = progressionStatus.rawValue as CKRecordValue
        }
        try encodeEnvelope(progressionStatusDetail, forKey: RecordKeys.MacOSOwned.progressionStatusDetail, into: record)
        if let orthomosaicImageURL {
            record[RecordKeys.MacOSOwned.orthomosaicImage] = CKAsset(fileURL: orthomosaicImageURL)
        }
        try encodeEnvelope(fertilizingZone, forKey: RecordKeys.MacOSOwned.fertilizingZone, into: record)
        try encodeEnvelope(fertilizerNeedPerZone, forKey: RecordKeys.MacOSOwned.fertilizerNeedPerZone, into: record)
        try encodeEnvelope(treeIdentification, forKey: RecordKeys.MacOSOwned.treeIdentification, into: record)
        if let plannedOperatorVisitDate {
            record[RecordKeys.MacOSOwned.plannedOperatorVisitDate] = plannedOperatorVisitDate as CKRecordValue
        }
        if let resultSentAt {
            record[RecordKeys.MacOSOwned.resultSentAt] = resultSentAt as CKRecordValue
        }
        try encodeEnvelope(fertilizationScheduling, forKey: RecordKeys.MacOSOwned.fertilizationScheduling, into: record)
    }

    /// Constructs or updates a `CKRecord` with the macOS-owned values applied.
    public func buildRecord(existing: CKRecord? = nil) throws -> CKRecord {
        let record: CKRecord
        if let existing {
            record = existing
        } else if let recordName {
            record = CKRecord(recordType: RecordKeys.recordType, recordID: CKRecord.ID(recordName: recordName))
        } else {
            record = CKRecord(recordType: RecordKeys.recordType)
        }

        try applyToRecord(record)
        return record
    }

    /// Saves the record using `savePolicy = .changedKeys` to preserve iOS-owned fields.
    @discardableResult
    public static func save(
        record: CKRecord,
        to database: CKDatabase
    ) async throws -> CKRecord {
        try await ScanRequestRecordWriter.save(record: record, to: database)
    }

    private func encodeEnvelope<Payload: Codable & Sendable>(
        _ payload: Payload?,
        forKey key: String,
        into record: CKRecord
    ) throws {
        guard let payload else { return }
        let jsonString = try JSONEnvelope.encodeToString(payload)
        record[key] = jsonString as CKRecordValue
    }
}
