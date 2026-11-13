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

## Copy Procedure Between Repositories

1. Update the contract in one repo, bump `ContractInfo.version`, update `CHANGELOG.md`.
2. Diff: `diff -r <repoA>/CloudKitContract <repoB>/CloudKitContract` to verify only intended changes exist.
3. Replace the entire `CloudKitContract/` folder in the second repo.
4. Run tests and build both targets.
5. Reference `Contract vN` in both commit messages.

