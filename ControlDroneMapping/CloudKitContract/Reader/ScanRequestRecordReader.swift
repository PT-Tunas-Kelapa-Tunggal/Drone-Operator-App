import CloudKit
import CoreLocation
import Foundation

/// Fault-tolerant reader wrapping a CloudKit `CKRecord` for `PlantationScanRequest`.
/// Guarantees that no getter panics or throws unhandled errors; all field reads return `Result<T, FieldError>`.
nonisolated public struct ScanRequestRecord: Sendable {
    public let record: CKRecord

    public init(_ record: CKRecord) {
        self.record = record
    }

    // MARK: - Core Record Reader

    /// Safe typed reader delegating to `CKRecord.read(_:as:)` with integer/numeric promotion.
    public func read<T>(_ key: String, as type: T.Type) -> Result<T, FieldError> {
        record.read(key, as: type)
    }

    private func decodeEnvelope<Payload: Codable & Sendable>(
        _ key: String,
        as payloadType: Payload.Type = Payload.self
    ) -> Result<Payload, FieldError> {
        read(key, as: String.self).flatMap { rawJSON in
            JSONEnvelope<Payload>.decodeFromString(rawJSON, key: key)
        }
    }

    // MARK: - Schema Metadata

    /// The contract version stamped when this record was last saved (0 if missing).
    public func schemaVersion() -> Int64 {
        read(RecordKeys.schemaVersion, as: Int64.self).or(0)
    }

    // MARK: - iOS-Owned Fields

    public func farmBoundary() -> Result<[CLLocation], FieldError> {
        read(RecordKeys.iOSOwned.farmBoundary, as: [CLLocation].self)
    }

    public func farmSize() -> Result<Double, FieldError> {
        read(RecordKeys.iOSOwned.farmSize, as: Double.self)
    }

    public func farmCircumference() -> Result<Double, FieldError> {
        read(RecordKeys.iOSOwned.farmCircumference, as: Double.self)
    }

    public func submittedAt() -> Result<Date, FieldError> {
        read(RecordKeys.iOSOwned.submittedAt, as: Date.self)
    }

    public func farmName() -> Result<String, FieldError> {
        read(RecordKeys.iOSOwned.farmName, as: String.self)
    }

    public func farmAddress() -> Result<String, FieldError> {
        read(RecordKeys.iOSOwned.farmAddress, as: String.self)
    }

    public func plantingMonthAndYear() -> Result<Date, FieldError> {
        read(RecordKeys.iOSOwned.plantingMonthAndYear, as: Date.self)
    }

    public func soilType() -> Result<ContractSoilType, FieldError> {
        read(RecordKeys.iOSOwned.soilType, as: String.self).map { ContractSoilType(rawValue: $0) }
    }

    public func fertilizingFrequencyPerYear() -> Result<Int64, FieldError> {
        read(RecordKeys.iOSOwned.fertilizingFrequencyPerYear, as: Int64.self)
    }

    public func fertilizersCompositions() -> Result<[FertilizerCompositionItem], FieldError> {
        decodeEnvelope(RecordKeys.iOSOwned.fertilizersCompositions)
    }

    public func harvestFrequencyPerMonth() -> Result<Int64, FieldError> {
        read(RecordKeys.iOSOwned.harvestFrequencyPerMonth, as: Int64.self)
    }

    public func averageHarvestWeightKg() -> Result<Double, FieldError> {
        read(RecordKeys.iOSOwned.averageHarvestWeightKg, as: Double.self)
    }

    public func farmerContactName() -> Result<String, FieldError> {
        read(RecordKeys.iOSOwned.farmerContactName, as: String.self)
    }

    public func farmerPhoneNumber() -> Result<String, FieldError> {
        read(RecordKeys.iOSOwned.farmerPhoneNumber, as: String.self)
    }

    public func farmerHomeAddress() -> Result<String, FieldError> {
        read(RecordKeys.iOSOwned.farmerHomeAddress, as: String.self)
    }

    public func fertilizationBudgetPerHa() -> Result<Int64, FieldError> {
        read(RecordKeys.iOSOwned.fertilizationBudgetPerHa, as: Int64.self)
    }

    // MARK: - macOS-Owned Fields

    public func progressionStatus() -> Result<ProgressionStatus, FieldError> {
        read(RecordKeys.MacOSOwned.progressionStatus, as: String.self)
            .map { ProgressionStatus(rawValue: $0) }
    }

    public func progressionStatusDetail() -> Result<[ProgressionStatusDetailEvent], FieldError> {
        decodeEnvelope(RecordKeys.MacOSOwned.progressionStatusDetail)
    }

    public func orthomosaicImage() -> Result<CKAsset, FieldError> {
        read(RecordKeys.MacOSOwned.orthomosaicImage, as: CKAsset.self)
    }

    public func fertilizingZone() -> Result<[FertilizingZoneItem], FieldError> {
        decodeEnvelope(RecordKeys.MacOSOwned.fertilizingZone)
    }

    public func fertilizerNeedPerZone() -> Result<[FertilizerNeedItem], FieldError> {
        decodeEnvelope(RecordKeys.MacOSOwned.fertilizerNeedPerZone)
    }

    public func treeIdentification() -> Result<[TreeIdentificationItem], FieldError> {
        decodeEnvelope(RecordKeys.MacOSOwned.treeIdentification)
    }

    public func plannedOperatorVisitDate() -> Result<Date, FieldError> {
        read(RecordKeys.MacOSOwned.plannedOperatorVisitDate, as: Date.self)
    }

    public func resultSentAt() -> Result<Date, FieldError> {
        read(RecordKeys.MacOSOwned.resultSentAt, as: Date.self)
    }

    public func fertilizationScheduling() -> Result<[FertilizationSchedulePeriodItem], FieldError> {
        decodeEnvelope(RecordKeys.MacOSOwned.fertilizationScheduling)
    }
}

