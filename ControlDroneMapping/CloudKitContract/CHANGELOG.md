# CloudKitContract Changelog

Every modification to the `CloudKitContract` folder must be documented here and accompanied by a bump to `ContractInfo.version`.

## 1 — 2026-11-16
- Added the macOS-owned `farmNutrientComparisonStatus` JSON envelope with annual per-hectare (kg/ha/year) current and recommended values for Nitrogen, Fospor, Kalium, and Magnesium. These copy the ML baseline and recorded fertilizer supply; the iOS app chooses its own status label.
- Added typed nutrient values, strict decoding, and reader/writer support. Schema deploy: REQUIRED (add `farmNutrientComparisonStatus` as a `STRING` field on `PlantationScanRequest`).
- Recorded the CloudKit payload change from commit `f8d0265` that was missing from the changelog: tree health labels now map VARI quartiles (`q1`–`q4`) to the contract labels.
- note: this change doesn't increase the version since the app is still in heavy development, thus expect a breaking changes, but this one shouldn't break existing implementation.

## 1 — 2026-11-12
- Initial contract scaffolding for `PlantationScanRequest` synchronization between iOS (Farmer) and macOS (Drone Operator).
- Top-level fields:
  - iOS-owned: `schemaVersion`, `farmBoundary`, `farmSize`, `farmCircumference`, `submittedAt`, `farmName`, `farmAddress`, `plantingMonthAndYear`, `soilType`, `fertilizingFrequencyPerYear`, `fertilizersCompositions`, `harvestFrequencyPerMonth`, `averageHarvestWeightKg`, `farmerContactName`, `farmerPhoneNumber`, `farmerHomeAddress`, `fertilizationBudgetPerHa`.
  - macOS-owned: `progressionStatus`, `progressionStatusDetail`, `orthomosaicImage`, `fertilizingZone`, `fertilizerNeedPerZone`, `treeIdentification`, `plannedOperatorVisitDate`, `resultSentAt`, `fertilizationScheduling` (initiated by macOS; step `done_at` timestamps updated by iOS via `.changedKeys`).
- Versioned JSON envelopes (`version: "1.0.0"`) for:
  - `fertilizersCompositions`
  - `progressionStatusDetail`
  - `fertilizingZone`
  - `fertilizerNeedPerZone`
  - `treeIdentification`
  - `fertilizationScheduling`
- Shared `ContractFertilizerType` enum (`Payloads/FertilizerType.swift`) strictly validating known fertilizer types (`ContractFertilizerTypeError` on unknown string casts and decoding errors on invalid JSON), used directly by `FertilizerCompositionItem`, `FertilizerNeedItem`, and `FertilizationScheduleFertilizerItem`. Includes NPK variants: `NPK`, `NPK-15-15-15`, `NPK-12-6-22-3`, `NPK-13-6-27-4`, `NPK-13-8-27-4`, and `NPK-16-16-16`.
- Fault-tolerant readers returning `Result<T, FieldError>` with field-key-specific JSON decoding errors.
- Writers (`ScanRequestRecordWriter`, `MacOSScanRequestRecordWriter`) enforcing `.changedKeys` save policy and field ownership.
- Schema deploy: REQUIRED (ensure `fertilizationScheduling` `STRING` field is deployed on `PlantationScanRequest`).

