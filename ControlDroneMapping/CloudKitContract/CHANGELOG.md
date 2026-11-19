# CloudKitContract Changelog

Document contract changes here. During current development, `ContractInfo.version` remains 1; coordinate future release version changes explicitly.

## 1 — 2026-11-17
- Added macOS-owned `fertilizer_cost_predictions` (String), a JSON envelope whose payload is an object keyed by `ContractFertilizerType.rawValue`.
- Each entry contains `total_bags_needed` (Int), `total_kg` (Double, kg), and `total_cost` (Double, IDR). Values come directly from supported NPK `ranked_options`: `age_adjusted_full_bags_farm_year`, `total_kg`, and `npk_full_bag_cost_farm_year_rp` respectively. Missing or invalid mass/price predictions remain null; mass is not recalculated from the bag count.
- Added `Dolomite` and `Urea` entries from `annual_npk_budget_matching.selected_zone_mg_urea_cost_breakdown`, matching product identifiers `dolomite_Mg_cheaper` and `urea_N_expensive` (`product`, or the engine's `product_key`). Bags copy `full_bags_to_buy`, kg is bags × `bag_size_kg`, and cost copies `full_bag_purchase_cost_rp`. This parsing is independent of NPK analysis and excludes other products.
- Added typed object encoding, reader/writer support, and round-trip mapping into the review result. Unknown fertilizer keys produce a field error. Only the current payload shape is decoded; there are no legacy field-name aliases.
- Contract version remains 1 and envelope version remains `1.0.0` during current development, as requested. No version bump or migration support is introduced.
- Schema deploy: REQUIRED if not already present (add `fertilizer_cost_predictions` as a STRING on `PlantationScanRequest`); sync the contract folder to iOS.

## 1 — 2026-11-17
- Renamed `FertilizerNeedItem.recommendedDosage` to `recommendedDosagePerZonePerYear` in Swift, preserving the `recommended_dosage` JSON key. Zone-specific recommendations now copy VARI's `product_kg_per_zone_per_year` without adding the base amount or rounding; general NPK entries retain their farm-wide annual amount.
- Added optional `recommendedDosagePerTreePerZonePerYear` (`recommended_dosage_per_tree_per_zone_per_year` in JSON), copied from VARI's `product_kg_per_palm_per_year`. Existing records without this key still decode, and general NPK entries omit it.
- No top-level CloudKit fields were added; the new value is inside the existing `fertilizerNeedPerZone` JSON envelope.

## 1 — 2026-11-17
- Integrated the iOS contract's detailed JSON decoding errors, preserving coding paths and missing-key context in diagnostics.
- Documented that tree health decoding accepts both stored labels (`Normal`, `Terindikasi`, `Defisiensi`, `Tidak Wajar`) and VARI quartiles (`q1`–`q4`), preserving unknown values as `Unknown`. The decoding logic was already present in the macOS working tree.
- No CloudKit field or payload shape changes.

## 1 — 2026-11-16
- Added macOS-owned `variPlainZoneOverlayImage` and `variTreeQuartileOverlayImage` CKAsset fields for `oil_palm_zones_plain_with_separator.jpg` and `oil_palm_field_tree_vari_quartiles.jpg`.
- The macOS app uploads each original JPEG when it is at most 5 MiB, otherwise it uploads a temporary compressed JPEG of at most 5 MiB. The originals are kept locally.
- Schema deploy: REQUIRED (add both fields as `ASSET` on `PlantationScanRequest`); copy this contract to the farmer iOS app before reading v2 records.

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
