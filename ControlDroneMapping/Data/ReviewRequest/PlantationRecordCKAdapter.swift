import CloudKit
import Foundation

public struct PlantationRecordCKAdapter {
    public static let recordType = "PlantationScanRequest"

    public enum Field {
        public static let farmerName = "farmerName"
        public static let farmerPhone = "farmerPhone"
        public static let farmerAddress = "farmerAddress"
        public static let gardenID = "gardenID"
        public static let gardenName = "gardenName"
        public static let locationName = "locationName"
        public static let areaHectares = "areaHectares"
        public static let boundaryJSON = "boundaryJSON"
        public static let agronomicJSON = "agronomicJSON"
        public static let statusCode = "statusCode"
        public static let submittedAt = "submittedAt"
        public static let scheduledFor = "scheduledFor"
        public static let inReviewAt = "inReviewAt"
        public static let completedAt = "completedAt"
        public static let operatorNotes = "operatorNotes"
        public static let resultJSON = "resultJSON"
        public static let orthomosaicAsset = "orthomosaicAsset"
    }

    public static func toCKRecord(from dto: PlantationScanRequestRecordDTO, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: dto.recordName))
        record[Field.farmerName] = dto.farmerName as CKRecordValue
        record[Field.farmerPhone] = dto.farmerPhone as CKRecordValue
        record[Field.farmerAddress] = dto.farmerAddress as CKRecordValue
        record[Field.gardenID] = dto.gardenID as CKRecordValue
        record[Field.gardenName] = dto.gardenName as CKRecordValue
        record[Field.locationName] = dto.locationName as CKRecordValue
        record[Field.areaHectares] = dto.areaHectares as CKRecordValue
        record[Field.boundaryJSON] = dto.boundaryJSON as CKRecordValue
        record[Field.agronomicJSON] = dto.agronomicJSON as CKRecordValue
        record[Field.statusCode] = dto.statusCode as CKRecordValue
        record[Field.submittedAt] = dto.submittedAt as CKRecordValue
        record[Field.scheduledFor] = dto.scheduledFor as CKRecordValue?
        record[Field.inReviewAt] = dto.inReviewAt as CKRecordValue?
        record[Field.completedAt] = dto.completedAt as CKRecordValue?
        record[Field.operatorNotes] = dto.operatorNotes as CKRecordValue?
        record[Field.resultJSON] = dto.resultJSON as CKRecordValue?

        if let assetURL = dto.orthomosaicAssetURL {
            record[Field.orthomosaicAsset] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    public static func toDTO(from record: CKRecord) throws -> PlantationScanRequestRecordDTO {
        guard let farmerName = record[Field.farmerName] as? String,
              let farmerPhone = record[Field.farmerPhone] as? String,
              let farmerAddress = record[Field.farmerAddress] as? String,
              let gardenID = record[Field.gardenID] as? String,
              let gardenName = record[Field.gardenName] as? String,
              let locationName = record[Field.locationName] as? String,
              let boundaryJSON = record[Field.boundaryJSON] as? String,
              let agronomicJSON = record[Field.agronomicJSON] as? String,
              let statusCode = record[Field.statusCode] as? Int,
              let submittedAt = record[Field.submittedAt] as? Date
        else {
            throw CKAdapterError.missingRequiredFields
        }

        let areaHectares = record[Field.areaHectares] as? Double ?? 0.0
        let asset = record[Field.orthomosaicAsset] as? CKAsset

        return PlantationScanRequestRecordDTO(
            recordName: record.recordID.recordName,
            farmerName: farmerName,
            farmerPhone: farmerPhone,
            farmerAddress: farmerAddress,
            gardenID: gardenID,
            gardenName: gardenName,
            locationName: locationName,
            areaHectares: areaHectares,
            boundaryJSON: boundaryJSON,
            agronomicJSON: agronomicJSON,
            statusCode: statusCode,
            submittedAt: submittedAt,
            scheduledFor: record[Field.scheduledFor] as? Date,
            inReviewAt: record[Field.inReviewAt] as? Date,
            completedAt: record[Field.completedAt] as? Date,
            operatorNotes: record[Field.operatorNotes] as? String,
            resultJSON: record[Field.resultJSON] as? String,
            orthomosaicAssetURL: asset?.fileURL
        )
    }
}

public enum CKAdapterError: LocalizedError {
    case missingRequiredFields

    public var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return "Data peninjauan dari server tidak lengkap."
        }
    }
}
