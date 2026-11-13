import Foundation

/// Canonical CloudKit Record Type and Field Keys agreed between iOS and macOS.
nonisolated public enum RecordKeys {
    /// Dedicated CloudKit record type name.
    public static let recordType = "PlantationScanRequest"

    // MARK: - Schema Metadata
    /// Contract schema version written by the saving app.
    public static let schemaVersion = "schemaVersion"

    // MARK: - iOS-Owned Fields (Palm Oil Farmer)
    nonisolated public enum iOSOwned {
        /// Sorted boundary coordinates of the plantation ([CLLocation]).
        public static let farmBoundary = "farmBoundary"
        /// Calculated farm size in hectares (Double).
        public static let farmSize = "farmSize"
        /// Calculated farm circumference in meters (Double).
        public static let farmCircumference = "farmCircumference"
        /// Date when scan request was submitted (Date).
        public static let submittedAt = "submittedAt"
        /// Farmer-assigned name for the plantation (String).
        public static let farmName = "farmName"
        /// Full physical address of the plantation (String).
        public static let farmAddress = "farmAddress"
        /// Planting month and year (first day of month date) (Date).
        public static let plantingMonthAndYear = "plantingMonthAndYear"
        /// Soil classification (String).
        public static let soilType = "soilType"
        /// Number of fertilizing sessions per year (Int64).
        public static let fertilizingFrequencyPerYear = "fertilizingFrequencyPerYear"
        /// JSON envelope containing fertilizer compositions and dosages (String).
        public static let fertilizersCompositions = "fertilizersCompositions"
        /// Number of harvest cycles per month (Int64).
        public static let harvestFrequencyPerMonth = "harvestFrequencyPerMonth"
        /// Average weight in kg per harvest cycle (Double).
        public static let averageHarvestWeightKg = "averageHarvestWeightKg"
        /// Name of farmer contact person (String).
        public static let farmerContactName = "farmerContactName"
        /// Phone number of farmer contact person (String).
        public static let farmerPhoneNumber = "farmerPhoneNumber"
        /// Physical home address of the farmer (String).
        public static let farmerHomeAddress = "farmerHomeAddress"
        /// Fertilization budget per hectare in IDR Rupiah (Int64).
        public static let fertilizationBudgetPerHa = "fertilizationBudgetPerHa"

        /// Set of all field keys owned by the iOS application.
        public static let allKeys: Set<String> = [
            farmBoundary, farmSize, farmCircumference, submittedAt,
            farmName, farmAddress, plantingMonthAndYear, soilType,
            fertilizingFrequencyPerYear, fertilizersCompositions,
            harvestFrequencyPerMonth, averageHarvestWeightKg,
            farmerContactName, farmerPhoneNumber, farmerHomeAddress,
            fertilizationBudgetPerHa, RecordKeys.schemaVersion
        ]
    }

    // MARK: - macOS-Owned Fields (Drone Operator)
    nonisolated public enum MacOSOwned {
        /// Overall assessment progress status (String: Sent, Scheduled, In Progress, Finished).
        public static let progressionStatus = "progressionStatus"
        /// JSON envelope containing progression status event log (String).
        public static let progressionStatusDetail = "progressionStatusDetail"
        /// Aerial high-resolution orthomosaic scan result asset (CKAsset).
        public static let orthomosaicImage = "orthomosaicImage"
        /// JSON envelope defining fertilization zones and tree counts (String).
        public static let fertilizingZone = "fertilizingZone"
        /// JSON envelope defining fertilizer requirements per zone or general (String).
        public static let fertilizerNeedPerZone = "fertilizerNeedPerZone"
        /// JSON envelope with tree coordinates and health classification (String).
        public static let treeIdentification = "treeIdentification"
        /// Operator's planned visit schedule date (Date).
        public static let plannedOperatorVisitDate = "plannedOperatorVisitDate"
        /// Date when operator dispatched the final assessment results (Date).
        public static let resultSentAt = "resultSentAt"
        /// JSON envelope defining fertilization schedule periods and steps (String).
        /// Initiated by macOS; step `done_at` timestamps are updated by iOS.
        public static let fertilizationScheduling = "fertilizationScheduling"

        /// Set of all field keys owned by the macOS application.
        public static let allKeys: Set<String> = [
            progressionStatus, progressionStatusDetail, orthomosaicImage,
            fertilizingZone, fertilizerNeedPerZone, treeIdentification,
            plannedOperatorVisitDate, resultSentAt, fertilizationScheduling,
            RecordKeys.schemaVersion
        ]
    }
}

