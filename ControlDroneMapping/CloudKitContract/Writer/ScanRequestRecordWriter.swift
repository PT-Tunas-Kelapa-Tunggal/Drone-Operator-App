import CloudKit
import CoreLocation
import Foundation

/// Writer for the iOS PalmOilFarmer application.
/// Enforces field ownership by only writing iOS-owned fields and saving with `savePolicy = .changedKeys`.
nonisolated public struct ScanRequestRecordWriter: Sendable {
    public var recordName: String?
    public var farmBoundary: [CLLocation]?
    public var farmSize: Double?
    public var farmCircumference: Double?
    public var submittedAt: Date?
    public var farmName: String?
    public var farmAddress: String?
    public var plantingMonthAndYear: Date?
    public var soilType: ContractSoilType?
    public var fertilizingFrequencyPerYear: Int64?
    public var fertilizersCompositions: [FertilizerCompositionItem]?
    public var harvestFrequencyPerMonth: Int64?
    public var averageHarvestWeightKg: Double?
    public var farmerContactName: String?
    public var farmerPhoneNumber: String?
    public var farmerHomeAddress: String?
    public var fertilizationBudgetPerHa: Int64?

    public init(
        recordName: String? = nil,
        farmBoundary: [CLLocation]? = nil,
        farmSize: Double? = nil,
        farmCircumference: Double? = nil,
        submittedAt: Date? = nil,
        farmName: String? = nil,
        farmAddress: String? = nil,
        plantingMonthAndYear: Date? = nil,
        soilType: ContractSoilType? = nil,
        fertilizingFrequencyPerYear: Int64? = nil,
        fertilizersCompositions: [FertilizerCompositionItem]? = nil,
        harvestFrequencyPerMonth: Int64? = nil,
        averageHarvestWeightKg: Double? = nil,
        farmerContactName: String? = nil,
        farmerPhoneNumber: String? = nil,
        farmerHomeAddress: String? = nil,
        fertilizationBudgetPerHa: Int64? = nil
    ) {
        self.recordName = recordName
        self.farmBoundary = farmBoundary
        self.farmSize = farmSize
        self.farmCircumference = farmCircumference
        self.submittedAt = submittedAt
        self.farmName = farmName
        self.farmAddress = farmAddress
        self.plantingMonthAndYear = plantingMonthAndYear
        self.soilType = soilType
        self.fertilizingFrequencyPerYear = fertilizingFrequencyPerYear
        self.fertilizersCompositions = fertilizersCompositions
        self.harvestFrequencyPerMonth = harvestFrequencyPerMonth
        self.averageHarvestWeightKg = averageHarvestWeightKg
        self.farmerContactName = farmerContactName
        self.farmerPhoneNumber = farmerPhoneNumber
        self.farmerHomeAddress = farmerHomeAddress
        self.fertilizationBudgetPerHa = fertilizationBudgetPerHa
    }

    /// Mutates or creates a CKRecord applying ONLY fields owned by iOS.
    public func applyToRecord(_ record: CKRecord) throws {
        // Stamp current contract schema version
        record[RecordKeys.schemaVersion] = ContractInfo.version as CKRecordValue

        if let farmBoundary {
            record[RecordKeys.iOSOwned.farmBoundary] = farmBoundary as CKRecordValue
        }
        if let farmSize {
            record[RecordKeys.iOSOwned.farmSize] = farmSize as CKRecordValue
        }
        if let farmCircumference {
            record[RecordKeys.iOSOwned.farmCircumference] = farmCircumference as CKRecordValue
        }
        if let submittedAt {
            record[RecordKeys.iOSOwned.submittedAt] = submittedAt as CKRecordValue
        }
        if let farmName {
            record[RecordKeys.iOSOwned.farmName] = farmName as CKRecordValue
        }
        if let farmAddress {
            record[RecordKeys.iOSOwned.farmAddress] = farmAddress as CKRecordValue
        }
        if let plantingMonthAndYear {
            record[RecordKeys.iOSOwned.plantingMonthAndYear] = plantingMonthAndYear as CKRecordValue
        }
        if let soilType {
            record[RecordKeys.iOSOwned.soilType] = soilType.rawValue as CKRecordValue
        }
        if let fertilizingFrequencyPerYear {
            record[RecordKeys.iOSOwned.fertilizingFrequencyPerYear] = fertilizingFrequencyPerYear as CKRecordValue
        }
        if let fertilizersCompositions {
            let jsonString = try JSONEnvelope.encodeToString(fertilizersCompositions)
            record[RecordKeys.iOSOwned.fertilizersCompositions] = jsonString as CKRecordValue
        }
        if let harvestFrequencyPerMonth {
            record[RecordKeys.iOSOwned.harvestFrequencyPerMonth] = harvestFrequencyPerMonth as CKRecordValue
        }
        if let averageHarvestWeightKg {
            record[RecordKeys.iOSOwned.averageHarvestWeightKg] = averageHarvestWeightKg as CKRecordValue
        }
        if let farmerContactName {
            record[RecordKeys.iOSOwned.farmerContactName] = farmerContactName as CKRecordValue
        }
        if let farmerPhoneNumber {
            record[RecordKeys.iOSOwned.farmerPhoneNumber] = farmerPhoneNumber as CKRecordValue
        }
        if let farmerHomeAddress {
            record[RecordKeys.iOSOwned.farmerHomeAddress] = farmerHomeAddress as CKRecordValue
        }
        if let fertilizationBudgetPerHa {
            record[RecordKeys.iOSOwned.fertilizationBudgetPerHa] = fertilizationBudgetPerHa as CKRecordValue
        }

        // Initialize progression status if creating a fresh record without an existing status
        if record[RecordKeys.MacOSOwned.progressionStatus] == nil {
            record[RecordKeys.MacOSOwned.progressionStatus] = ProgressionStatus.sent.rawValue as CKRecordValue
        }
        if record[RecordKeys.MacOSOwned.progressionStatusDetail] == nil {
            let initialEvent = ProgressionStatusDetailEvent(
                dateTime: submittedAt ?? Date(),
                title: ProgressionStatus.sent.rawValue,
                desc: "Permintaan peninjauan telah diajukan."
            )
            let jsonString = try JSONEnvelope.encodeToString([initialEvent])
            record[RecordKeys.MacOSOwned.progressionStatusDetail] = jsonString as CKRecordValue
        }
    }

    /// Constructs a CKRecord with the iOS-owned values applied.
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

    /// Updates only `fertilizationScheduling` and `schemaVersion` on an existing `CKRecord`
    /// so iOS can mark step `done_at` timestamps without touching other iOS or macOS fields.
    public static func applyFertilizationScheduling(
        _ periods: [FertilizationSchedulePeriodItem],
        to record: CKRecord
    ) throws {
        record[RecordKeys.schemaVersion] = ContractInfo.version as CKRecordValue
        let jsonString = try JSONEnvelope.encodeToString(periods)
        record[RecordKeys.MacOSOwned.fertilizationScheduling] = jsonString as CKRecordValue
    }

    /// Applies `fertilizationScheduling` updates to an existing `CKRecord` and saves using `.changedKeys`.
    @discardableResult
    public static func saveFertilizationScheduling(
        _ periods: [FertilizationSchedulePeriodItem],
        on record: CKRecord,
        to database: CKDatabase
    ) async throws -> CKRecord {
        try applyFertilizationScheduling(periods, to: record)
        return try await save(record: record, to: database)
    }

    /// Saves the record using `savePolicy = .changedKeys` to prevent overwriting macOS-owned fields.
    @discardableResult
    public static func save(
        record: CKRecord,
        to database: CKDatabase
    ) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: record)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}

