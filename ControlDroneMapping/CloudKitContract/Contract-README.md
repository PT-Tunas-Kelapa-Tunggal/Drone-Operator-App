# CloudKitContract

Self-contained contract defining the schema, codecs, readers, and writers for CloudKit synchronization between the **PalmOilFarmer (iOS)** app and the **Drone Operator (macOS)** app.

## Rules & Principles

1. **Self-Contained**:
   - Only imports `Foundation`, `CloudKit`, and `CoreLocation`.
   - Never reference app-specific types (Models, ViewModels, Views, DI).
   - This entire folder is designed to be copied byte-identical between the iOS and macOS repositories.

2. **Contract Versioning**:
   - `ContractInfo.version` must be incremented on **every** change.
   - Every writer stamps `schemaVersion = ContractInfo.version`.
   - Log changes in `CHANGELOG.md`.

3. **Fault-Tolerant Readers**:
   - Every getter returns `Result<T, FieldError>`.
   - Readers **never** throw unhandled exceptions, panic, or choose silent defaults.
   - The calling site (repository / presentation mapper) is the sole place where fallback values or fallback UI (e.g., error badges) are decided.

4. **Versioned JSON Envelopes**:
   - Complex nested payloads stored as JSON strings must be wrapped in:
     ```json
     {
       "version": "1.0.0",
       "payload": { ... }
     }
     ```
   - JSON payload evolution is additive-only.

5. **Safe Concurrency & Field Ownership**:
   - Writers strictly save with `savePolicy = .changedKeys`.
   - Never use `.allKeys` (which overwrites the other app's fields).
   - Never rely on default `.ifServerRecordUnchanged` (fails when the other app saved concurrently).
   - `ScanRequestRecordWriter` (iOS) writes **only** iOS-owned fields; `MacOSScanRequestRecordWriter` (macOS) writes **only** macOS-owned fields.
   - Exception by design: `fertilizationScheduling` is initiated by macOS, and iOS updates step `done_at` timestamps afterward via `ScanRequestRecordWriter.saveFertilizationScheduling(_:on:to:)`.

## Fertilizer cost predictions

`PlantationScanRequest.fertilizer_cost_predictions` is a macOS-owned String containing a
`JSONEnvelope<FertilizerCostPredictions>`. The payload is an object keyed by
`ContractFertilizerType.rawValue` (for example, `NPK-12-6-22-3`), with annual whole-farm bag counts,
purchase mass in kg, and prices in IDR, stored as `total_bags_needed`, `total_kg`, and `total_cost`.
This field uses envelope version `1.0.0` and only the current entry names; no legacy aliases are decoded.
For NPK, the ML sources for `total_kg` and `total_cost` are `total_kg` and `npk_full_bag_cost_farm_year_rp`.
Dolomite and Urea come from `annual_npk_budget_matching.selected_zone_mg_urea_cost_breakdown`:
bags use `full_bags_to_buy`, kg is bags × `bag_size_kg`, and cost uses `full_bag_purchase_cost_rp`.
`FertilizerCostPredictions.byFertilizer` exposes typed enum keys;
the custom codec writes a JSON object rather than a dictionary pair array.

Read it with `ScanRequestRecord.fertilizerCostPredictions()` and write it with
`MacOSScanRequestRecordWriter.fertilizerCostPredictions`. Mass and price may be null when the ML prediction
is unavailable. Missing fields on older records are expected; choose the fallback at the call site.
Deploy the new STRING field before uploading results and copy this folder to the iOS repository.

## CloudKit schema snapshots

`schema.ckdb` records the live CloudKit schema that the branch expects. Copy the
snapshot together with the Swift contract into the corresponding
branch in the other repository. Development and production branches can carry
different snapshots during a rollout.

CI uses `cktool export-schema` to compare the snapshot with the partition the
workflow selects. The check reports drift in records, fields, types, indexes,
roles, and grants. To resolve drift, review the difference in CloudKit Console:

- When the live schema is correct, export it to a temporary file, review the
  diff, and replace the snapshot on both matching branches.
- When a release partition is behind, apply the reviewed changes to the
  target container's Development partition and choose **Deploy Schema Changes**
  in CloudKit Console. Rerun the release once its Production partition matches.
  CloudKit promotes within one container. Copy intended changes from staging to
  the production container explicitly and preserve deployed production fields,
  indexes, and grants.

To export manually, first save your management token to your local Keychain with
`xcrun cktool save-token --type management`. Then run the following command with
the target team, container, and partition. Use `production` for either container's
release build.

```sh
xcrun cktool export-schema --team-id TEAM_ID --container-id CONTAINER_ID \
  --environment development --output-file /tmp/contract-schema.ckdb
```

## Copy Procedure Between Repositories

1. Update the contract in one repo and update `CHANGELOG.md`; keep the current development version unchanged.
2. Diff: `diff -r <repoA>/CloudKitContract <repoB>/CloudKitContract` to verify only intended changes exist.
3. Replace the entire `CloudKitContract/` folder in the second repo.
4. Run tests and build both targets.
5. Reference `Contract vN` in both commit messages.
