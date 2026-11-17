import Combine
import Foundation
import SwiftUI

/// Active long-running VARI & HARA execution metadata exposed across the app.
public struct ActiveVariRun: Equatable, Sendable {
    public let id: UUID
    public let missionID: UUID?
    public let recordID: UUID?
    public let projectID: UUID?
    public let missionName: String
    public let outputFolder: URL
    public var stage: VariProcessingStage
    public let startedAt: Date
    public let hasExistingCachedResult: Bool
    public let logURL: URL
    public var isStopping: Bool
}

/// Non-blocking completion or failure banner notice shown if the operator navigated elsewhere during a run.
public struct VariCompletionNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let missionID: UUID?
    public let recordID: UUID?
    public let projectID: UUID?
    public let missionName: String
    public let outputFolder: URL
    public let isFailure: Bool
    public let message: String
}

/// Navigation target used when the operator clicks "Lihat" / "Buka hasil" on a global VARI banner.
public struct VariNavigationRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let missionID: UUID?
    public let recordID: UUID?
    public let projectID: UUID?
    public let outputFolder: URL
}

/// App-lifetime coordinator for long-running VARI & HARA and Fertilization Timing jobs.
/// Survives view and mission switches so background Python execution never orphans or loses UI state.
@MainActor
public final class VariAnalysisViewModel: ObservableObject {
    @Published public private(set) var activeRun: ActiveVariRun?
    @Published public private(set) var resultsByFolderKey: [String: VariScanResult] = [:]
    @Published public private(set) var errorsByFolderKey: [String: String] = [:]
    @Published public var completionNotice: VariCompletionNotice?
    @Published public var navigationRequest: VariNavigationRequest?
    @Published public private(set) var visibleVariFolderKey: String?

    @Published public private(set) var runningTimingKeys: Set<String> = []
    @Published public private(set) var timingResultsByKey: [String: VariTimingExecutionResult] = [:]
    @Published public private(set) var timingErrorsByKey: [String: String] = [:]
    @Published public private(set) var timingFertilizerLookupByKey:
        [String: [String: ContractFertilizerType]] = [:]
    @Published public var selectedNPKByFolderKey: [String: ContractFertilizerType] = [:]
    @Published public var dispatchSuccessAtByFolderKey: [String: Date] = [:]

    private let variProcessor: any VariProcessing
    private let timingProcessor: any VariTimingProcessing
    private var activeVariTask: Task<Void, Never>?
    private var activeCancellation: VariProcessCancellation?
    private var timingTasks: [String: Task<Void, Never>] = [:]

    public init(
        variProcessor: any VariProcessing,
        timingProcessor: any VariTimingProcessing
    ) {
        self.variProcessor = variProcessor
        self.timingProcessor = timingProcessor
    }

    public var busy: Bool { activeRun != nil }

    public func isRunningVari(in folder: URL?) -> Bool {
        guard let folder, let activeRun else { return false }
        return folderKey(activeRun.outputFolder) == folderKey(folder)
    }

    public func result(for folder: URL?) -> VariScanResult? {
        guard let folder else { return nil }
        return resultsByFolderKey[folderKey(folder)]
    }

    public func error(for folder: URL?) -> String? {
        guard let folder else { return nil }
        return errorsByFolderKey[folderKey(folder)]
    }

    public func logURL(for folder: URL?) -> URL? {
        guard let folder else { return nil }
        let url = folder.appendingPathComponent(LocalVariProcessor.logFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func dismissError(for folder: URL?) {
        guard let folder else { return }
        errorsByFolderKey.removeValue(forKey: folderKey(folder))
    }

    public func setError(_ message: String, for folder: URL?) {
        guard let folder else { return }
        errorsByFolderKey[folderKey(folder)] = message
    }

    public func clearTimingError(for storageKey: String) {
        timingErrorsByKey.removeValue(forKey: storageKey)
    }

    public func setTimingError(_ message: String, storageKey: String) {
        timingErrorsByKey[storageKey] = message
    }

    public func dismissCompletionNotice(for folder: URL? = nil) {
        guard let notice = completionNotice else { return }
        if let folder {
            if folderKey(notice.outputFolder) == folderKey(folder) {
                completionNotice = nil
            }
        } else {
            completionNotice = nil
        }
    }

    public func selectedNPK(for folder: URL?) -> ContractFertilizerType? {
        guard let folder else { return nil }
        return selectedNPKByFolderKey[folderKey(folder)]
    }

    public func setSelectedNPK(_ npk: ContractFertilizerType?, for folder: URL?) {
        guard let folder else { return }
        selectedNPKByFolderKey[folderKey(folder)] = npk
    }

    public func dispatchSuccessAt(for folder: URL?) -> Date? {
        guard let folder else { return nil }
        return dispatchSuccessAtByFolderKey[folderKey(folder)]
    }

    public func markDispatchSucceeded(for folder: URL?) {
        guard let folder else { return }
        dispatchSuccessAtByFolderKey[folderKey(folder)] = Date()
    }

    public func isTimingBusy(storageKey: String) -> Bool {
        runningTimingKeys.contains(storageKey)
    }

    public func timingResult(for storageKey: String) -> VariTimingExecutionResult? {
        timingResultsByKey[storageKey]
    }

    public func timingError(for storageKey: String) -> String? {
        timingErrorsByKey[storageKey]
    }

    public func timingFertilizerLookup(for storageKey: String) -> [String: ContractFertilizerType] {
        timingFertilizerLookupByKey[storageKey] ?? [:]
    }

    public func clearMissionTransientState(for folder: URL?, timingStorageKey: String) {
        if let folder {
            let key = folderKey(folder)
            selectedNPKByFolderKey.removeValue(forKey: key)
            dispatchSuccessAtByFolderKey.removeValue(forKey: key)
        }
        timingErrorsByKey.removeValue(forKey: timingStorageKey)
    }

    public func loadCachedVariIfNeeded(for folder: URL?) {
        guard let folder else { return }
        let key = folderKey(folder)
        if resultsByFolderKey[key] == nil,
            let cached = try? variProcessor.loadCachedResult(from: folder)
        {
            resultsByFolderKey[key] = cached
        }
    }

    public func loadCachedTimingIfNeeded(
        storageKey: String,
        outputFolder: URL,
        resultFolder: URL?
    ) {
        if timingResultsByKey[storageKey] == nil,
            let cached = timingProcessor.loadCachedResult(in: outputFolder)
        {
            timingResultsByKey[storageKey] = cached
            syncSelectionFromCachedTiming(cached, storageKey: storageKey, resultFolder: resultFolder)
        }
    }

    public func startVari(
        missionID: UUID?,
        recordID: UUID?,
        projectID: UUID?,
        missionName: String,
        imageURL: URL,
        outputFolder: URL,
        request: PlantationReviewRequest
    ) {
        guard !busy else { return }
        let key = folderKey(outputFolder)
        errorsByFolderKey.removeValue(forKey: key)
        if let notice = completionNotice, folderKey(notice.outputFolder) == key {
            completionNotice = nil
        }

        let hasCached =
            resultsByFolderKey[key] != nil || (try? variProcessor.loadCachedResult(from: outputFolder)) != nil

        let runID = UUID()
        let cancellation = VariProcessCancellation()
        let logURL = outputFolder.appendingPathComponent(LocalVariProcessor.logFileName)

        activeCancellation = cancellation
        activeRun = ActiveVariRun(
            id: runID,
            missionID: missionID,
            recordID: recordID,
            projectID: projectID,
            missionName: missionName,
            outputFolder: outputFolder,
            stage: .validatingEngine,
            startedAt: Date(),
            hasExistingCachedResult: hasCached,
            logURL: logURL,
            isStopping: false
        )

        activeVariTask = Task { [weak self] in
            guard let self else { return }
            do {
                let submission = try VariSubmissionBuilder.makeSubmission(from: request)
                let result = try await self.variProcessor.process(
                    photoURL: imageURL,
                    submission: submission,
                    outputFolder: outputFolder,
                    cancellation: cancellation,
                    onStage: { [weak self] stage in
                        Task { @MainActor [weak self] in
                            guard let self, var current = self.activeRun, current.id == runID else { return }
                            current.stage = stage
                            self.activeRun = current
                        }
                    }
                )
                self.resultsByFolderKey[key] = result
                self.errorsByFolderKey.removeValue(forKey: key)
                self.completionNotice = VariCompletionNotice(
                    id: UUID(),
                    missionID: missionID,
                    recordID: recordID,
                    projectID: projectID,
                    missionName: missionName,
                    outputFolder: outputFolder,
                    isFailure: false,
                    message: "Analisis VARI & HARA selesai · \(missionName)"
                )
            } catch is CancellationError {
                // Deliberate user stop: keep any pre-existing cached result intact.
            } catch {
                if cancellation.isCancelled {
                    // Treated cleanly as user stop even if subprocess threw after SIGTERM.
                } else {
                    self.errorsByFolderKey[key] = error.localizedDescription
                    self.completionNotice = VariCompletionNotice(
                        id: UUID(),
                        missionID: missionID,
                        recordID: recordID,
                        projectID: projectID,
                        missionName: missionName,
                        outputFolder: outputFolder,
                        isFailure: true,
                        message: "Analisis VARI & HARA gagal · \(missionName)"
                    )
                }
            }

            if self.activeRun?.id == runID {
                self.activeRun = nil
            }
            self.activeCancellation = nil
            self.activeVariTask = nil
        }
    }

    public func cancelVari(waitForExit: Bool = false) {
        if var current = activeRun {
            current.isStopping = true
            activeRun = current
        }
        activeCancellation?.cancel(waitForExit: waitForExit)
        activeVariTask?.cancel()
        if waitForExit {
            activeRun = nil
            activeCancellation = nil
            activeVariTask = nil
        }
    }

    public func cancelAllForTermination() {
        cancelVari(waitForExit: true)
        for (_, task) in timingTasks {
            task.cancel()
        }
        timingTasks.removeAll()
        runningTimingKeys.removeAll()
    }

    public func startTiming(
        storageKey: String,
        outputFolder: URL,
        resultFolder: URL?,
        request: PlantationReviewRequest,
        variResult: VariScanResult,
        preferredNPK: ContractFertilizerType?,
        options: VariTimingRunOptions
    ) {
        guard !runningTimingKeys.contains(storageKey) else { return }
        runningTimingKeys.insert(storageKey)
        timingErrorsByKey.removeValue(forKey: storageKey)
        if let resultFolder {
            dispatchSuccessAtByFolderKey.removeValue(forKey: folderKey(resultFolder))
        }

        timingTasks[storageKey]?.cancel()
        timingTasks[storageKey] = Task { [weak self] in
            guard let self else { return }
            do {
                let buildOutput = try VariTimingBuilder.makeRequest(
                    from: request,
                    variResult: variResult,
                    preferredNPK: preferredNPK
                )
                let result = try await self.timingProcessor.runTiming(
                    request: buildOutput.request,
                    options: options,
                    outputFolder: outputFolder
                )
                guard !Task.isCancelled else {
                    self.finishTiming(storageKey: storageKey)
                    return
                }
                self.timingFertilizerLookupByKey[storageKey] = buildOutput.fertilizerIDLookup
                if let resultFolder {
                    self.selectedNPKByFolderKey[self.folderKey(resultFolder)] = buildOutput.selectedNPKType
                }
                self.timingResultsByKey[storageKey] = result
                self.timingErrorsByKey.removeValue(forKey: storageKey)
            } catch is CancellationError {
                // Leave prior cached timing state untouched.
            } catch {
                if !Task.isCancelled {
                    self.timingErrorsByKey[storageKey] = error.localizedDescription
                }
            }
            self.finishTiming(storageKey: storageKey)
        }
    }

    public func requestNavigationToActiveRun() {
        guard let activeRun else { return }
        navigationRequest = VariNavigationRequest(
            id: UUID(),
            missionID: activeRun.missionID,
            recordID: activeRun.recordID,
            projectID: activeRun.projectID,
            outputFolder: activeRun.outputFolder
        )
    }

    public func requestNavigation(to notice: VariCompletionNotice) {
        navigationRequest = VariNavigationRequest(
            id: UUID(),
            missionID: notice.missionID,
            recordID: notice.recordID,
            projectID: notice.projectID,
            outputFolder: notice.outputFolder
        )
        completionNotice = nil
    }

    public func clearNavigationRequest(_ id: UUID) {
        if navigationRequest?.id == id {
            navigationRequest = nil
        }
    }

    public func setVisibleVariFolder(_ folder: URL?) {
        let key = folder.map(folderKey)
        if visibleVariFolderKey != key {
            visibleVariFolderKey = key
        }
        if let folder {
            dismissCompletionNotice(for: folder)
        }
    }

    public func isShowingActiveVariLayer(_ run: ActiveVariRun) -> Bool {
        visibleVariFolderKey == folderKey(run.outputFolder)
    }

    public func formattedElapsed(since startDate: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func finishTiming(storageKey: String) {
        runningTimingKeys.remove(storageKey)
        timingTasks.removeValue(forKey: storageKey)
    }

    private func syncSelectionFromCachedTiming(
        _ execution: VariTimingExecutionResult,
        storageKey: String,
        resultFolder: URL?
    ) {
        var resolved: [String: ContractFertilizerType] = [:]
        let resultKey = resultFolder.map(folderKey)
        for item in execution.request.fertilizers {
            if let id = item.id,
                let contract = VariTimingBuilder.resolveContractType(fromID: id)
            {
                resolved[id] = contract
                if let resultKey,
                    selectedNPKByFolderKey[resultKey] == nil,
                    contract != .dolomite, contract != .urea
                {
                    selectedNPKByFolderKey[resultKey] = contract
                }
            }
        }
        timingFertilizerLookupByKey[storageKey] = resolved
    }

    private func folderKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
