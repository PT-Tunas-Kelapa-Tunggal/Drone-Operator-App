import CloudKit
import CoreLocation
import Foundation

/// Fault-tolerant mapper between `CloudKitContract.ScanRequestRecord` (`CKRecord`)
/// and `PlantationReviewRequest`.
public struct PlantationDomainMapper: Sendable {
    public init() {}

    public func toDomain(from record: CKRecord) -> PlantationReviewRequest {
        toDomain(from: ScanRequestRecord(record))
    }

    public func toDomain(from reader: ScanRequestRecord) -> PlantationReviewRequest {
        var fieldErrors: [String: String] = [:]

        func readField<T>(_ key: String, result: Result<T, FieldError>) -> T? {
            switch result {
            case .success(let value):
                return value
            case .failure(let error):
                fieldErrors[key] = Self.describeFieldError(error)
                return nil
            }
        }

        func readOptionalMacOSField<T>(
            _ key: String,
            result: Result<T, FieldError>,
            expectPresent: Bool
        ) -> T? {
            switch result {
            case .success(let value):
                return value
            case .failure(let error):
                if !error.isMissing || expectPresent {
                    fieldErrors[key] = Self.describeFieldError(error)
                }
                return nil
            }
        }

        let recordName = reader.record.recordID.recordName
        let requestID = PlantationReviewRequest.stableUUID(forRecordName: recordName)
        let schemaVersion = reader.schemaVersion()

        // 1. Farmer Contact (iOS-Owned)
        let farmerName = readField(
            RecordKeys.iOSOwned.farmerContactName, result: reader.farmerContactName()) ?? ""
        let farmerPhone = readField(
            RecordKeys.iOSOwned.farmerPhoneNumber, result: reader.farmerPhoneNumber()) ?? ""
        let farmerAddress = readField(
            RecordKeys.iOSOwned.farmerHomeAddress, result: reader.farmerHomeAddress()) ?? ""

        // 2. Garden Metadata & Boundary (iOS-Owned)
        let farmName = readField(RecordKeys.iOSOwned.farmName, result: reader.farmName()) ?? ""
        let farmAddress = readField(RecordKeys.iOSOwned.farmAddress, result: reader.farmAddress()) ?? ""
        let farmSize = readField(RecordKeys.iOSOwned.farmSize, result: reader.farmSize()) ?? 0.0
        let farmCircumference = readField(
            RecordKeys.iOSOwned.farmCircumference, result: reader.farmCircumference()) ?? 0.0
        let locations = readField(
            RecordKeys.iOSOwned.farmBoundary, result: reader.farmBoundary()) ?? []
        let boundary = locations.map {
            CoordinatePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        // 3. Agronomic Profile (iOS-Owned)
        let submittedAt = readField(
            RecordKeys.iOSOwned.submittedAt, result: reader.submittedAt())
            ?? reader.record.creationDate
            ?? Date()

        let plantingDate = readField(
            RecordKeys.iOSOwned.plantingMonthAndYear, result: reader.plantingMonthAndYear())
        let calendar = Calendar(identifier: .gregorian)
        let plantingYear = plantingDate.map { calendar.component(.year, from: $0) } ?? 0
        let plantingMonth = plantingDate.map { calendar.component(.month, from: $0) }

        let soilType = readField(
            RecordKeys.iOSOwned.soilType, result: reader.soilType()) ?? .unknown("")

        let freqPerYear = readField(
            RecordKeys.iOSOwned.fertilizingFrequencyPerYear,
            result: reader.fertilizingFrequencyPerYear()
        ).map(Int.init) ?? 0

        let budgetPerHa = readField(
            RecordKeys.iOSOwned.fertilizationBudgetPerHa,
            result: reader.fertilizationBudgetPerHa()) ?? 0

        let contractCompositions = readField(
            RecordKeys.iOSOwned.fertilizersCompositions,
            result: reader.fertilizersCompositions()) ?? []
        let fertilizerRecords = contractCompositions.enumerated().compactMap { index, item in
            mapFertilizerUsage(
                item,
                index: index,
                fieldKey: RecordKeys.iOSOwned.fertilizersCompositions,
                fieldErrors: &fieldErrors
            )
        }

        let harvestFreq = readField(
            RecordKeys.iOSOwned.harvestFrequencyPerMonth,
            result: reader.harvestFrequencyPerMonth()
        ).map(Int.init)
        let avgHarvestKg = readField(
            RecordKeys.iOSOwned.averageHarvestWeightKg,
            result: reader.averageHarvestWeightKg())
        let harvestRecord: HarvestYield? =
            if let harvestFreq, let avgHarvestKg {
                HarvestYield(frequencyPerMonth: harvestFreq, latestWeightKg: avgHarvestKg)
            } else {
                nil
            }

        // 4. macOS-Owned Status & Deliverables (optional until finished)
        let contractStatus = readOptionalMacOSField(
            RecordKeys.MacOSOwned.progressionStatus,
            result: reader.progressionStatus(),
            expectPresent: false
        ) ?? .sent
        let status = ReviewStatus(progressionStatus: contractStatus)
        let expectFinishedOutputs = status.isFinished

        let detailEvents = (readOptionalMacOSField(
            RecordKeys.MacOSOwned.progressionStatusDetail,
            result: reader.progressionStatusDetail(),
            expectPresent: false
        ) ?? []).map { ReviewProgressionEvent(contractEvent: $0) }

        let plannedVisitDate = readOptionalMacOSField(
            RecordKeys.MacOSOwned.plannedOperatorVisitDate,
            result: reader.plannedOperatorVisitDate(),
            expectPresent: false
        )
        let resultSentAt = readOptionalMacOSField(
            RecordKeys.MacOSOwned.resultSentAt,
            result: reader.resultSentAt(),
            expectPresent: expectFinishedOutputs
        )

        let orthomosaicAsset = readOptionalMacOSField(
            RecordKeys.MacOSOwned.orthomosaicImage,
            result: reader.orthomosaicImage(),
            expectPresent: expectFinishedOutputs
        )
        let zones = readOptionalMacOSField(
            RecordKeys.MacOSOwned.fertilizingZone,
            result: reader.fertilizingZone(),
            expectPresent: expectFinishedOutputs
        ) ?? []
        let trees = readOptionalMacOSField(
            RecordKeys.MacOSOwned.treeIdentification,
            result: reader.treeIdentification(),
            expectPresent: expectFinishedOutputs
        ) ?? []
        let fertilizerNeeds = readOptionalMacOSField(
            RecordKeys.MacOSOwned.fertilizerNeedPerZone,
            result: reader.fertilizerNeedPerZone(),
            expectPresent: expectFinishedOutputs
        ) ?? []
        let schedulePeriods = readOptionalMacOSField(
            RecordKeys.MacOSOwned.fertilizationScheduling,
            result: reader.fertilizationScheduling(),
            expectPresent: expectFinishedOutputs
        ) ?? []

        let hasAnyResultData =
            resultSentAt != nil
            || orthomosaicAsset != nil
            || !zones.isEmpty
            || !trees.isEmpty
            || !fertilizerNeeds.isEmpty
            || !schedulePeriods.isEmpty

        let reviewResult: PlantationReviewResult? =
            if expectFinishedOutputs || hasAnyResultData {
                PlantationReviewResult(
                    completedAt: resultSentAt ?? reader.record.modificationDate ?? submittedAt,
                    orthomosaicImageURL: orthomosaicAsset?.fileURL,
                    zones: zones,
                    trees: trees,
                    fertilizerNeeds: fertilizerNeeds,
                    schedulePeriods: schedulePeriods
                )
            } else {
                nil
            }

        return PlantationReviewRequest(
            id: requestID,
            recordName: recordName,
            schemaVersion: schemaVersion,
            farmer: FarmerContact(
                name: farmerName,
                phone: farmerPhone,
                address: farmerAddress
            ),
            garden: GardenSummary(
                id: requestID,
                name: farmName.isEmpty ? "Kebun Tanpa Nama" : farmName,
                locationName: farmAddress,
                areaHectares: farmSize,
                circumferenceMeters: farmCircumference
            ),
            boundary: boundary,
            agronomy: AgronomicProfile(
                plantingYear: plantingYear,
                plantingMonth: plantingMonth,
                soilType: soilType,
                fertilizingFrequencyPerYear: freqPerYear,
                fertilizationBudgetPerHa: budgetPerHa,
                fertilizerRecords: fertilizerRecords,
                harvestRecord: harvestRecord
            ),
            status: status,
            progressionEvents: detailEvents,
            timeline: ReviewTimeline(
                submittedAt: submittedAt,
                plannedOperatorVisitDate: plannedVisitDate,
                resultSentAt: resultSentAt
            ),
            operatorNotes: nil,
            fieldErrors: fieldErrors,
            result: reviewResult
        )
    }

    // MARK: - Helpers

    private func mapFertilizerUsage(
        _ item: FertilizerCompositionItem,
        index: Int,
        fieldKey: String,
        fieldErrors: inout [String: String]
    ) -> FertilizerUsage? {
        guard let rawDoseKg = normalizeDoseToKg(
            valueText: item.dosagePerTree.value,
            unitText: item.dosagePerTree.valueUnit
        ) else {
            fieldErrors["\(fieldKey)[\(index)].dosagePerTree"] =
                "Nilai dosis '\(item.dosagePerTree.value) \(item.dosagePerTree.valueUnit)' untuk \(item.fertilizerType.rawValue) tidak valid."
            return nil
        }

        let elements: [FertilizerCompositionElement] = (item.composition ?? []).compactMap { elem in
            guard let numeric = parseLocalizedDouble(elem.value) else {
                fieldErrors["\(fieldKey)[\(index)].composition.\(elem.name)"] =
                    "Nilai komposisi '\(elem.value)' tidak valid."
                return nil
            }
            return FertilizerCompositionElement(
                name: elem.name,
                value: numeric,
                valueUnit: elem.valueUnit
            )
        }

        let rawText = "\(item.dosagePerTree.value) \(item.dosagePerTree.valueUnit)/pohon"
        return FertilizerUsage(
            contractType: item.fertilizerType,
            composition: elements,
            doseKgPerTree: rawDoseKg,
            rawDosageText: rawText
        )
    }

    private func normalizeDoseToKg(valueText: String, unitText: String) -> Double? {
        guard let numeric = parseLocalizedDouble(valueText), numeric.isFinite else { return nil }
        let normalizedUnit = unitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedUnit {
        case "", "kg", "kilogram", "kilograms":
            return numeric
        case "g", "gr", "gram", "grams":
            return numeric / 1000.0
        default:
            return nil
        }
    }

    private func parseLocalizedDouble(_ raw: String) -> Double? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(trimmed)
    }

    public static func describeFieldError(_ error: FieldError) -> String {
        switch error {
        case .missing(let key):
            return "Field '\(key)' belum diisi di CloudKit."
        case .typeMismatch(let key, let expected, let actual):
            return "Tipe field '\(key)' tidak sesuai (diharapkan \(expected), ditemukan \(actual))."
        case .unreadable(let key, let reason):
            return "Nilai field '\(key)' tidak dapat dibaca: \(reason)"
        case .decodingError(let key, let errorDescription):
            return "Gagal mendekode JSON envelope '\(key)': \(errorDescription)"
        }
    }
}
