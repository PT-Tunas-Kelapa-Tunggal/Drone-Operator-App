import CloudKit
import Combine
import Foundation

final class ControlViewModel: ObservableObject {
    @Published var step: ControlScreen = .dashboard
    @Published var plan = MissionPlan() {
        didSet {
            if oldValue.camera != plan.camera {
                review = QualityReview()
                plan.focusCalibration = nil
                if !oldValue.camera.sameRadiometry(as: plan.camera) {
                    plan.exposureCalibration = nil
                    referenceSaved = false
                    grayLocked = false
                }
            }
            if oldValue.interval != plan.interval { review.endurance = false }
            persistDraft()
        }
    }
    @Published var geometry = SurveyGeometry() {
        didSet {
            if oldValue.heightAGL != geometry.heightAGL || oldValue.speed != geometry.speed
                || oldValue.targetGSDcm != geometry.targetGSDcm
                || oldValue.forwardOverlap != geometry.forwardOverlap
                || oldValue.sideOverlap != geometry.sideOverlap
                || oldValue.calibratedFocalPixels != geometry.calibratedFocalPixels
            {
                geometry.reviewed = false
                review = QualityReview()
            }
            persistDraft()
        }
    }
    @Published var review = QualityReview()
    @Published var telemetry = Telemetry()
    @Published var records: [MissionRecord] = []
    @Published var selectedDatasetID: UUID?
    @Published var datasetFilter: DatasetFilter = .all
    @Published private(set) var missionFilter: DatasetFilter = .all
    private var loadedMissionID: UUID?
    @Published var log: [String] = []
    @Published var pending: Command?
    @Published var lastReceived: Date?
    @Published var sample: CapturePreview?
    @Published var displayedPreview: CapturePreview?
    @Published var appliedSettings: CameraSettings?
    @Published var grayLocked = false
    @Published var referenceSaved = false
    @Published var errorMessage: String?
    @Published var pendingSince: Date?
    @Published private(set) var draftNeedsRetry = false
    @Published private(set) var hasLocalDraft = false
    private var draftCommandID: UUID?
    @Published private(set) var missionLibrary = MissionLibrary()
    @Published private(set) var selectedMissionID: UUID?
    @Published private(set) var missionDetailVisible = false
    @Published private(set) var missionStorageError: String?
    private let libraryRepository: any MissionLibraryRepository
    private var libraryReady = false
    private var switchingMission = false
    private let drafts: any MissionDraftRepository
    let link: any LocalTransport
    let isDemo: Bool
    @Published private(set) var reviewRequests: [PlantationReviewRequest] = []
    @Published var isDispatchingReview = false
    @Published private(set) var isSyncingCloudKit = false
    private let reviewRepository: any OperatorReviewRepository
    private let storageScope: AppConfiguration.StorageScope?
    private var reviewObservationTask: Task<Void, Never>?
    private var expectedTestID: UUID?
    private var expectedReferenceID: UUID?
    private var demoHeartbeat: Timer?
    private var connectionObservation: AnyCancellable?
    init(
        demo: Bool = false, draftURL: URL? = nil,
        transport: (any LocalTransport)? = nil, drafts: (any MissionDraftRepository)? = nil,
        missions: (any MissionLibraryRepository)? = nil,
        reviewRepository: (any OperatorReviewRepository)? = nil,
        storageScope: AppConfiguration.StorageScope? = nil
    ) {
        let resolvedScope = storageScope ?? (demo ? nil : AppConfiguration.bundleStorageScope)
        self.storageScope = resolvedScope
        self.reviewRepository = reviewRepository ?? CloudKitOperatorReviewRepository.shared
        self.drafts =
            drafts
            ?? FileMissionDraftRepository(
                url: draftURL ?? (demo ? nil : FileMissionDraftRepository.defaultURL))
        libraryRepository =
            missions
            ?? FileMissionLibraryRepository(
                url: draftURL.map {
                    $0.deletingLastPathComponent().appendingPathComponent(
                        $0.lastPathComponent + ".missions.json")
                }
                    ?? (demo || drafts != nil || transport != nil
                        ? nil : FileMissionLibraryRepository.defaultURL))
        isDemo = demo
        link = transport ?? LocalLink(camera: false, enabled: !demo)
        plan.guidedMode = true
        plan.durationSeconds = 600
        do {
            let loaded = try libraryRepository.load()
            if !demo, let resolvedScope, !loaded.matches(resolvedScope) {
                // Ignore cached missions saved under a different CloudKit container/environment or legacy unscoped cache.
                missionLibrary = MissionLibrary().tagged(with: resolvedScope)
            } else if let resolvedScope {
                missionLibrary = loaded.tagged(with: resolvedScope)
            } else {
                missionLibrary = loaded
            }
            libraryReady = true
        } catch {
            missionLibrary = resolvedScope.map { MissionLibrary().tagged(with: $0) } ?? MissionLibrary()
            libraryReady = true
            missionStorageError = "Pustaka misi: " + error.localizedDescription
        }
        do {
            if let draft = try self.drafts.load(), let savedPlan = draft.plan {
                plan = savedPlan
                geometry = savedPlan.survey ?? SurveyGeometry()
                draftCommandID = draft.id
                hasLocalDraft = true
                if let existing = missionLibrary.missions.first(where: { $0.commandID == draft.id }) {
                    selectedMissionID = existing.id
                    if existing.remoteID != nil && !existing.preparationRequested {
                        hasLocalDraft = false
                        draftCommandID = nil
                        try self.drafts.clear()
                    }
                }
            }
        } catch { errorMessage = "Draft misi: " + error.localizedDescription }
        if !demo {
            do { try link.store.migrateLegacy() } catch {
                errorMessage = "Migrasi dataset: " + error.localizedDescription
            }
        }
        startReviewRequestsObservation()

        records = link.store.records().filter { !missionLibrary.hiddenRemoteIDs.contains($0.id) }
        connectionObservation = link.connectionChanges.sink { [weak self] _ in self?.objectWillChange.send() }
        link.onConnect = { [weak self] in
            guard let self else { return }
            self.lastReceived = nil
            self.append("Koneksi pulih. Menunggu status terbaru; misi tidak dimulai ulang.")
            if let pending = self.pending { try? self.link.send(Packet(replyRequestID: pending.id)) }
        }
        link.onPacket = { [weak self] packet in self?.receive(packet) }
        if demo {
            demoHeartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, self.link.connected else { return }
                self.lastReceived = Date()
            }
            link.status = "Mode demo • tidak mengendalikan iPhone"
        }
    }
    deinit {
        demoHeartbeat?.invalidate()
        reviewObservationTask?.cancel()
    }
    func freshness(now: Date = Date()) -> Bool {
        lastReceived.map { (0...6).contains(now.timeIntervalSince($0)) } ?? false
    }
    var estimate: SurveyEstimate? { geometry.estimate(capabilities: telemetry.capabilities) }
    func readiness(now: Date = Date()) -> StartReadiness {
        var result = StartReadiness.evaluate(
            plan: plan, geometry: geometry, telemetry: telemetry,
            connected: link.connected, lastReceived: lastReceived, now: now,
            pending: pending != nil || link.sending || link.receiving,
            appliedSettings: appliedSettings, sample: sample, review: review, grayLocked: grayLocked,
            referenceSaved: referenceSaved)
        if let selectedMission, selectedMission.remoteID != telemetry.missionID {
            result.blockers.insert("Siapkan misi yang dipilih pada iPhone", at: 0)
        }
        if hasLocalDraft { result.blockers.insert("Hubungkan iPhone dan tunggu misi disiapkan", at: 0) }
        return result
    }
    var operatorStage: OperatorStage {
        if [.capturing, .countdown, .paused].contains(telemetry.phase) { return .capture }
        if pending != nil || telemetry.captureBusy == true || link.sending || link.receiving {
            return .waiting
        }
        if telemetry.phase == .completed && !hasLocalDraft { return .results }
        if !hasLocalDraft && telemetry.missionID == nil { return .mission }
        if !link.connected || !freshness() || hasLocalDraft { return .connection }
        if !geometry.reviewed { return .survey }
        if !settingsApplied { return .camera }
        if guidedMode && plan.exposureCalibration == nil
            || geometry.useGrayCard && (!grayLocked || !referenceSaved)
        {
            return .reference
        }
        if sample?.missionID != telemetry.missionID || sample?.settings != plan.camera { return .test }
        return readiness().canStart ? .ready : .review
    }
    var monitoringPlan: MissionPlan { records.first(where: { $0.id == telemetry.missionID })?.plan ?? plan }
    var recentRecords: [MissionRecord] { records.filter { $0.id != telemetry.missionID } }
    func showDatasets(filter: DatasetFilter = .all, missionID: UUID? = nil) {
        datasetFilter = filter
        selectedDatasetID = missionID
        step = .datasets
    }
    func navigate(_ screen: ControlScreen) {
        if screen == .datasets {
            showDatasets()
        } else if screen == .mission {
            showMissionList()
        } else {
            step = screen
        }
    }
    func filteredDatasets(search: String = "", now: Date = Date()) -> [MissionRecord] {
        records.filter { record in
            if let selectedDatasetID, record.id != selectedDatasetID { return false }
            switch datasetFilter {
            case .all: break
            case .attention: if ![.paused, .failed].contains(record.phase) { return false }
            case .today: if !Calendar.current.isDate(record.createdAt, inSameDayAs: now) { return false }
            case .withPhotos: if record.saved <= 0 { return false }
            }
            return search.isEmpty || record.plan.name.localizedCaseInsensitiveContains(search)
                || record.id.uuidString.localizedCaseInsensitiveContains(search)
        }
    }
    func performNextStep() {
        if [.connection, .camera, .reference, .test].contains(operatorStage), step != .devices {
            step = .devices
            return
        }
        switch operatorStage {
        case .camera: if guidedMode { prepareGuided() } else { send(.apply) }
        case .reference: send(.grayCardReference)
        case .test: send(.testCapture)
        case .results: showDatasets(missionID: telemetry.missionID)
        case .connection:
            if hasLocalDraft && canOperate { prepareSelectedMission() } else { step = .devices }
        default: break
        }
    }
    var editingLocked: Bool {
        [.capturing, .countdown, .paused].contains(telemetry.phase) || pending != nil
            || telemetry.captureBusy == true || link.sending || link.receiving
    }
    var canOperate: Bool {
        link.connected && freshness() && pending == nil && telemetry.captureBusy != true && !link.sending
            && !link.receiving
    }
    var canTransferDatasets: Bool {
        link.connected && pending == nil && !link.sending && !link.receiving
            && telemetry.captureBusy != true && ![.capturing, .countdown].contains(telemetry.phase)
    }

    var settingsApplied: Bool { appliedSettings == plan.camera && telemetry.settings == plan.camera }
    func createMission(name: String) {
        errorMessage =
            "Pembuatan misi manual dinonaktifkan. Gunakan permintaan pemetaan dari petani via CloudKit."
    }

    func startReviewRequestsObservation() {
        reviewObservationTask?.cancel()
        reviewObservationTask = Task { [weak self] in
            guard let self else { return }
            await self.syncCloudKitRequests()
            for await requests in self.reviewRepository.observeIncomingRequests() {
                guard !Task.isCancelled else { break }
                await self.applyIncomingRequests(requests)
            }
        }
    }

    @MainActor
    func syncCloudKitRequests() async {
        guard !isSyncingCloudKit else { return }
        isSyncingCloudKit = true
        defer { isSyncingCloudKit = false }
        do {
            let requests = try await reviewRepository.fetchAllRequests()
            applyIncomingRequests(requests)
            if errorMessage?.hasPrefix("Gagal memuat permintaan dari CloudKit") == true {
                errorMessage = nil
            }
        } catch {
            let formatted = Self.cloudKitLoadErrorMessage(error, storageScope: storageScope)
            print("[ControlViewModel] Failed to sync CloudKit requests: \(formatted)")
            errorMessage = formatted
        }
    }

    @MainActor
    func syncReviewRequests() async {
        await syncCloudKitRequests()
    }

    static func cloudKitLoadErrorMessage(
        _ error: any Error,
        storageScope: AppConfiguration.StorageScope?
    ) -> String {
        let prefix = "Gagal memuat permintaan dari CloudKit"
        let containerLabel = storageScope?.cloudKitContainerIdentifier ?? "aktif"
        let environmentLabel = storageScope?.environment ?? "development"

        if let ckError = error as? CKError {
            let detail = ckError.localizedDescription
            switch ckError.code {
            case .permissionFailure:
                let bundleID = Bundle.main.bundleIdentifier ?? "unknown-bundle-id"
                return "\(prefix): Bundle ID '\(bundleID)' belum diotorisasi untuk container '\(containerLabel)' (\(detail))."
            case .unknownItem:
                return "\(prefix): Record type CloudKit belum tersedia di container '\(containerLabel)' (\(environmentLabel)): \(detail)."
            case .notAuthenticated:
                return "\(prefix): Akun iCloud pada Mac belum masuk atau akses iCloud tidak tersedia (\(detail))."
            default:
                return "\(prefix) (\(containerLabel)): \(detail)"
            }
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    @MainActor
    func applyIncomingRequests(_ requests: [PlantationReviewRequest]) {
        reviewRequests = requests
        if errorMessage?.hasPrefix("Gagal memuat permintaan dari CloudKit") == true {
            errorMessage = nil
        }
        var newMissions: [SavedMission] = []
        for request in requests {
            if missionLibrary.hiddenRemoteIDs.contains(request.id) {
                continue
            }
            let existing = missionLibrary.missions.first(where: {
                $0.id == request.id || $0.remoteID == request.id
            })
            let areaPoints = request.boundary.map {
                FarmArea.Point(latitude: $0.latitude, longitude: $0.longitude)
            }
            let area = FarmArea(id: request.garden.id, name: request.garden.name, points: areaPoints)
            let phase: MissionPhase = request.status.isFinished ? .completed : (existing?.phase ?? .idle)

            let localRecord = records.first(where: { $0.id == request.id })
            let savedCount = localRecord?.saved ?? existing?.saved ?? 0

            var plan = existing?.plan ?? MissionPlan()
            if existing == nil {
                plan.name = "\(request.garden.name) · \(request.farmer.name)"
                plan.guidedMode = true
                plan.durationSeconds = 600
                if !areaPoints.isEmpty {
                    var geometry = SurveyGeometry()
                    geometry.reviewed = true
                    plan.survey = geometry
                }
            }

            let mission = SavedMission(
                id: request.id,
                createdAt: existing?.createdAt ?? request.timeline.submittedAt,
                plan: plan,
                area: area,
                remoteID: request.id,
                phase: phase,
                saved: savedCount,
                commandID: existing?.commandID ?? UUID(),
                preparationRequested: existing?.preparationRequested ?? false
            )
            newMissions.append(mission)
        }

        newMissions.sort { $0.createdAt > $1.createdAt }

        var updated = missionLibrary
        updated.missions = newMissions
        saveLibrary(updated)

        if let selected = selectedMissionID, !newMissions.contains(where: { $0.id == selected }) {
            selectedMissionID = nil
            missionDetailVisible = false
        }
    }

    func reviewRequest(for mission: SavedMission?, fallbackID: UUID? = nil) -> PlantationReviewRequest? {
        guard let candidateID = mission?.remoteID ?? mission?.id ?? fallbackID else {
            return nil
        }
        return reviewRequests.first { $0.id == candidateID }
    }

    @MainActor
    @discardableResult
    func dispatchCompletedReview(
        for mission: SavedMission?,
        fallbackID: UUID? = nil,
        output: OrthomosaicOutput,
        variResult: VariScanResult,
        timingResult: VariTimingExecutionResult,
        fertilizerIDLookup: [String: ContractFertilizerType] = [:],
        preferredNPK: ContractFertilizerType? = nil
    ) async -> Bool {
        guard !isDispatchingReview else { return false }
        isDispatchingReview = true
        defer { isDispatchingReview = false }

        do {
            guard let targetID = mission?.remoteID ?? mission?.id ?? fallbackID else {
                errorMessage = "ID misi tidak valid untuk pengiriman hasil."
                return false
            }

            let allRequests = (try? await reviewRepository.fetchAllRequests()) ?? reviewRequests
            guard let baseRequest = allRequests.first(where: { $0.id == targetID }) else {
                errorMessage =
                    "Permintaan peninjauan (\(targetID.uuidString)) tidak ditemukan di CloudKit container aktif."
                return false
            }

            // Re-fetch single record to preserve any latest iOS-written fields & progressionStatusDetail events.
            let latestRequest =
                (try? await reviewRepository.fetchRequest(recordName: baseRequest.recordName))
                ?? baseRequest

            let orthomosaicJPEGURL =
                variResult.assets.sourceImageURL
                ?? output.folder.appendingPathComponent(LocalVariProcessor.canonicalJPEGFileName)

            let payload = try CloudKitReviewDispatchBuilder.makeDispatchPayload(
                request: latestRequest,
                orthomosaicJPEGURL: orthomosaicJPEGURL,
                variResult: variResult,
                timingResult: timingResult,
                fertilizerIDLookup: fertilizerIDLookup,
                preferredNPKForFallback: preferredNPK
            )

            let updatedRequest = try await reviewRepository.dispatchCompletedReview(payload)
            if let index = reviewRequests.firstIndex(where: { $0.recordName == updatedRequest.recordName }) {
                reviewRequests[index] = updatedRequest
            } else {
                reviewRequests.append(updatedRequest)
            }

            markMissionCompleted(targetID)
            await syncReviewRequests()
            return true
        } catch {
            errorMessage = "Gagal mengirim hasil: \(error.localizedDescription)"
            return false
        }
    }
    var selectedMission: SavedMission? {
        missionLibrary.missions.first { $0.id == selectedMissionID }
    }
    var hasMissionDetail: Bool { missionDetailVisible && selectedMission != nil }
    var selectedMissionIsCurrent: Bool {
        guard let selectedMission else { return selectedMissionID == nil }
        return selectedMission.remoteID != nil && selectedMission.remoteID == telemetry.missionID
    }
    func savedMissions(search: String = "", filter: DatasetFilter = .all) -> [SavedMission] {
        missionLibrary.missions.filter {
            switch filter {
            case .all: break
            case .today: if !Calendar.current.isDateInToday($0.createdAt) { return false }
            case .attention: if ![.idle, .paused, .failed].contains($0.phase) { return false }
            case .withPhotos: if $0.saved == 0 { return false }
            }
            return search.isEmpty || $0.plan.name.localizedCaseInsensitiveContains(search)
                || $0.id.uuidString.localizedCaseInsensitiveContains(search)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    @discardableResult private func saveLibrary(_ updated: MissionLibrary) -> Bool {
        do {
            let scoped = storageScope.map { updated.tagged(with: $0) } ?? updated
            try libraryRepository.save(scoped)
            missionLibrary = scoped
            missionStorageError = nil
            return true
        } catch {
            missionStorageError = "Pustaka misi belum tersimpan: " + error.localizedDescription
            errorMessage = missionStorageError
            return false
        }
    }

    func saveCurrentMissionPlan() {
        persistDraft()
    }

    func markMissionCompleted(_ id: UUID) {
        guard let index = missionLibrary.missions.firstIndex(where: { $0.id == id || $0.remoteID == id })
        else { return }
        var updated = missionLibrary
        updated.missions[index].phase = .completed
        _ = saveLibrary(updated)
    }

    private func selectMission(_ mission: SavedMission) {
        switchingMission = true
        selectedMissionID = mission.id
        hasLocalDraft = mission.remoteID == nil
        draftCommandID = hasLocalDraft ? mission.commandID : nil
        draftNeedsRetry = false
        plan = mission.plan
        geometry = mission.plan.survey ?? SurveyGeometry()
        loadedMissionID = mission.remoteID
        appliedSettings = nil
        sample = nil
        displayedPreview = nil
        review = QualityReview()
        grayLocked = false
        referenceSaved = false
        expectedReferenceID = nil
        expectedTestID = nil
        switchingMission = false
    }
    func openMission(_ id: UUID) {
        guard let mission = missionLibrary.missions.first(where: { $0.id == id }) else { return }
        if selectedMissionID == id {
            missionDetailVisible = true
            step = .mission
            return
        }
        let openingLiveMission =
            mission.remoteID == telemetry.missionID && mission.remoteID != nil
            && isActiveMission && pending == nil && !link.sending && !link.receiving
        guard
            openingLiveMission
                || (!editingLocked && !(hasLocalDraft && selectedMission?.preparationRequested == true))
        else {
            errorMessage = "Selesaikan operasi misi saat ini sebelum membuka misi lain."
            return
        }
        selectMission(mission)
        missionDetailVisible = true
        step = .mission
    }
    func selectMissionForDeviceSetup(_ id: UUID) {
        openMission(id)
        step = .devices
    }
    func showMissionList(filter: DatasetFilter = .all) {
        missionDetailVisible = false
        missionFilter = filter
        step = .mission
    }
    func renameMission(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 70 else {
            errorMessage = "Nama misi wajib diisi, maksimal 70 karakter."
            return
        }
        guard !editingLocked, !(hasLocalDraft && selectedMission?.preparationRequested == true),
            let index = missionLibrary.missions.firstIndex(where: { $0.id == id })
        else { return }
        var updated = missionLibrary
        updated.missions[index].plan.name = name
        guard saveLibrary(updated) else { return }
        if selectedMissionID == id { plan.name = name }
    }
    func deleteMission(
        _ id: UUID, removeAssociatedFiles: (Set<UUID>) throws -> Void = { _ in }
    ) {
        guard !editingLocked, !(hasLocalDraft && selectedMission?.preparationRequested == true),
            let mission = missionLibrary.missions.first(where: { $0.id == id })
        else { return }
        let ids = Set([mission.id] + (mission.remoteID.map { [$0] } ?? []))
        // Persist the tombstone before deleting files. Keep the card until every cleanup
        // succeeds, so a failed deletion can be retried without losing its identity.
        var updated = missionLibrary
        updated.hiddenRemoteIDs.formUnion(ids)
        updated.deletedFileIDs = (updated.deletedFileIDs ?? []).union(ids)
        guard saveLibrary(updated) else { return }
        do {
            try removeAssociatedFiles(ids)
            try link.store.removeLocalMissionFiles(ids)
            if selectedMissionID == id { try drafts.clear() }
        } catch {
            errorMessage = "Penghapusan belum selesai. Coba hapus misi lagi: " + error.localizedDescription
            return
        }
        updated.missions.removeAll { $0.id == id }
        guard saveLibrary(updated) else { return }
        records.removeAll { ids.contains($0.id) }
        if selectedDatasetID.map({ ids.contains($0) }) == true { selectedDatasetID = nil }
        if selectedMissionID == id {
            switchingMission = true
            selectedMissionID = nil
            missionDetailVisible = false
            hasLocalDraft = false
            draftCommandID = nil
            sample = nil
            displayedPreview = nil
            switchingMission = false
            step = .mission
        }
    }

    var liveMissionFileIDs: Set<UUID> {
        Set(missionLibrary.missions.flatMap { [$0.id] + ($0.remoteID.map { [$0] } ?? []) })
    }

    func cleanDeletedMissionFiles(
        legacyIDs: Set<UUID> = [], removeAssociatedFiles: (Set<UUID>) throws -> Void
    ) {
        guard libraryReady, missionStorageError == nil, !editingLocked else { return }
        let liveIDs = Set(missionLibrary.missions.flatMap { [$0.id] + ($0.remoteID.map { [$0] } ?? []) })
        let deleted = (missionLibrary.deletedFileIDs ?? []).union(legacyIDs).subtracting(liveIDs)
        if !legacyIDs.isEmpty {
            var updated = missionLibrary
            updated.deletedFileIDs = (updated.deletedFileIDs ?? []).union(deleted)
            guard saveLibrary(updated) else { return }
        }
        guard !deleted.isEmpty else { return }
        do {
            try removeAssociatedFiles(deleted)
            try link.store.removeLocalMissionFiles(deleted)
            records.removeAll { deleted.contains($0.id) }
            if errorMessage?.hasPrefix("Sisa misi terhapus") == true { errorMessage = nil }
        } catch {
            errorMessage = "Sisa misi terhapus belum bersih: " + error.localizedDescription
        }
    }

    func setMissionArea(_ area: FarmArea?) {
        guard !editingLocked, !(hasLocalDraft && selectedMission?.preparationRequested == true),
            let index = missionLibrary.missions.firstIndex(where: { $0.id == selectedMissionID })
        else { return }
        var updated = missionLibrary
        updated.missions[index].area = area
        guard saveLibrary(updated) else { return }
        geometry.reviewed = false
    }
    var canRepeatCapture: Bool {
        guard let mission = selectedMission else { return false }
        return [.completed, .failed].contains(mission.phase) && !editingLocked
            && libraryReady && missionStorageError == nil
    }

    @discardableResult
    func repeatCapture(copyRoutes: (UUID, UUID) throws -> Void) -> Bool {
        guard canRepeatCapture, let previous = selectedMission else { return false }
        var newPlan = previous.plan
        let suffix = " · ulang"
        newPlan.name = String(newPlan.name.prefix(70 - suffix.count)) + suffix
        newPlan.focusCalibration = nil
        newPlan.exposureCalibration = nil
        newPlan.camera.whiteBalanceGains = nil
        var survey = newPlan.survey ?? SurveyGeometry()
        survey.reviewed = false
        newPlan.survey = survey
        let mission = SavedMission(plan: newPlan, area: previous.area)
        do {
            // Copy routes before committing the new mission; a route storage failure
            // must leave the operator looking at the original capture.
            try copyRoutes(previous.id, mission.id)
        } catch {
            errorMessage = "Capture ulang belum dibuat: " + error.localizedDescription
            return false
        }
        var updated = missionLibrary
        updated.missions.insert(mission, at: 0)
        guard saveLibrary(updated) else { return false }
        selectMission(mission)
        missionDetailVisible = true
        step = .mission
        errorMessage = nil
        append(
            "Percobaan capture baru dibuat. Periksa rencana dan ulangi persiapan kamera; foto sebelumnya tetap tersimpan."
        )
        return true
    }

    func prepareSelectedMission() {
        guard !editingLocked,
            let index = missionLibrary.missions.firstIndex(where: { $0.id == selectedMissionID }),
            missionLibrary.missions[index].phase != .completed
        else { return }
        if selectedMissionIsCurrent && !hasLocalDraft { return }
        var updated = missionLibrary
        if updated.missions[index].remoteID != nil {
            updated.missions[index].commandID = UUID()
        }
        updated.missions[index].preparationRequested = true
        guard saveLibrary(updated) else { return }
        hasLocalDraft = true
        draftCommandID = updated.missions[index].commandID
        draftNeedsRetry = false
        persistDraft()
        guard missionStorageError == nil else { return }
        synchronizeDraft()
    }
    private func persistDraft() {
        guard !switchingMission else { return }
        if let index = missionLibrary.missions.firstIndex(where: { $0.id == selectedMissionID }) {
            var updated = missionLibrary
            updated.missions[index].plan = plan
            updated.missions[index].plan.survey = geometry
            if let draftCommandID { updated.missions[index].commandID = draftCommandID }
            guard saveLibrary(updated) else { return }
        }
        guard hasLocalDraft, let id = draftCommandID,
            selectedMission?.preparationRequested == true
        else { return }
        do {
            var savedPlan = plan
            savedPlan.survey = geometry
            try drafts.save(Command(id: id, action: .createMission, plan: savedPlan))
        } catch {
            missionStorageError = "Draft misi belum tersimpan: " + error.localizedDescription
            errorMessage = missionStorageError
        }
    }
    private func synchronizeDraft() {
        guard hasLocalDraft, selectedMission?.preparationRequested == true, missionStorageError == nil,
            !draftNeedsRetry, let id = draftCommandID, canOperate, !editingLocked,
            telemetry.capabilities != nil, telemetry.phase == .ready || telemetry.phase == .completed
        else { return }
        var configured = plan
        configured.survey = geometry
        transmit(Command(id: id, action: .createMission, plan: configured))
    }
    private func mergeSavedRecords() {
        // Obsolete: local photo records must not synthesize phantom missions into CloudKit mission list.
    }
    func retryMissionSaving() {
        _ = saveLibrary(missionLibrary)
        if missionStorageError == nil {
            errorMessage = nil
        }
    }
    func retryDraft() {
        guard hasLocalDraft, draftNeedsRetry, canOperate, !editingLocked else { return }
        draftNeedsRetry = false
        if let index = missionLibrary.missions.firstIndex(where: { $0.id == selectedMissionID }) {
            var updated = missionLibrary
            updated.missions[index].preparationRequested = true
            guard saveLibrary(updated) else { return }
        }
        persistDraft()
        synchronizeDraft()
    }
    func recommend() {
        guard !editingLocked, let estimate, let c = telemetry.capabilities else { return }
        let shutter = min(0.001, estimate.maximumShutter * 0.8)
        guard shutter >= c.minShutter, estimate.maximumInterval * 0.8 >= 1 else {
            errorMessage =
                "Kecepatan terlalu tinggi untuk kemampuan kamera. Turunkan kecepatan pada langkah Rencana."
            return
        }
        plan.interval = floor(min(3600, estimate.maximumInterval * 0.8) * 10) / 10
        plan.camera.shutterSeconds = min(c.maxShutter, shutter)
        plan.camera.iso = max(c.minISO, min(100, c.maxISO))
        plan.camera.lensPosition = 1
        append("Usulan interval dan shutter diisi. ISO dan fokus tetap harus diperiksa pada foto uji.")
    }
    var guidedMode: Bool { plan.guidedMode == true }
    func setGuidedMode(_ enabled: Bool) {
        guard !editingLocked else { return }
        plan.guidedMode = enabled
        plan.exposureCalibration = nil
        appliedSettings = nil
        sample = nil
        review = QualityReview()
        grayLocked = false
        referenceSaved = false
        if enabled { geometry.useGrayCard = true }
    }
    func prepareGuided() {
        guard canOperate, !editingLocked, let capabilities = telemetry.capabilities else { return }
        do {
            plan = try GuidedAcquisition.plan(plan, geometry: geometry, capabilities: capabilities)
            geometry.useGrayCard = true
            send(.apply)
        } catch { errorMessage = error.localizedDescription }
    }
    var suggestedCaptureInterval: Double? {
        guard let sample, sample.kind == "quality-test", sample.settings == plan.camera,
            let minimum = CaptureCadence.minimumInterval(for: sample),
            minimum > plan.interval, minimum <= 3600,
            let estimate, minimum <= estimate.maximumInterval
        else { return nil }
        return minimum
    }
    func adjustCaptureInterval() {
        guard !editingLocked, let suggestedCaptureInterval else { return }
        plan.interval = suggestedCaptureInterval
        if guidedMode, let duration = plan.durationSeconds, duration.isFinite {
            plan.photoLimit = Int(min(100000, ceil(duration / plan.interval)))
        }
        append("Interval disesuaikan dengan waktu foto uji. Uji cadence kembali sebelum mulai.")
    }
    func send(_ action: CommandAction, missionID: UUID? = nil) {
        if action == .start, !readiness().canStart {
            errorMessage = readiness().blockers.first
            return
        }
        if selectedMissionID != nil, !selectedMissionIsCurrent,
            ![.prepare, .list, .download, .pause, .resume, .finish].contains(action)
        {
            errorMessage = "Siapkan misi yang dipilih pada iPhone terlebih dahulu."
            return
        }
        guard pending == nil else {
            errorMessage = "Tunggu konfirmasi operasi sebelumnya."
            return
        }
        guard link.connected else {
            errorMessage = "iPhone terputus. Misi yang sudah berjalan tetap disimpan lokal; tunggu reconnect."
            return
        }
        guard freshness() || [.prepare, .list, .download].contains(action) else {
            errorMessage = "Status iPhone belum terbaru. Tunggu sinkronisasi."
            return
        }
        if hasLocalDraft && ![.prepare, .list, .download, .pause, .resume, .finish].contains(action) {
            errorMessage = "Tunggu misi disiapkan pada iPhone sebelum mengendalikan kamera."
            synchronizeDraft()
            return
        }
        if [
            .apply, .grayCard, .grayCardReference, .testCapture, .calibrationBefore, .calibrationAfter,
        ].contains(action), !canOperate || [.capturing, .countdown].contains(telemetry.phase) {
            errorMessage = "Jeda misi dan tunggu foto tersimpan sebelum operasi ini."
            return
        }
        if action == .download, !canTransferDatasets {
            errorMessage = "Tunggu capture atau transfer sebelumnya selesai sebelum mentransfer foto."
            return
        }
        if [.testCapture, .calibrationBefore, .grayCardReference].contains(action), !settingsApplied {
            errorMessage = "Terapkan pengaturan kamera sebelum mengambil foto pemeriksaan."
            return
        }
        if action == .apply {
            do { try plan.validate() } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        if action == .testCapture {
            sample = nil
            review = QualityReview()
            if guidedMode { plan.focusCalibration = nil }
        }
        if action == .grayCardReference {
            guard telemetry.phase == .ready, telemetry.missionID != nil else {
                errorMessage = "Buat misi baru sebelum mengambil referensi."
                return
            }
            referenceSaved = false
            grayLocked = false
            sample = nil
            review = QualityReview()
        }
        let controlsActiveMission = [.pause, .resume, .finish].contains(action)
        var commandPlan = controlsActiveMission ? monitoringPlan : plan
        if !controlsActiveMission { commandPlan.survey = geometry }
        transmit(
            Command(
                action: action, plan: commandPlan,
                missionID: action == .start || controlsActiveMission ? telemetry.missionID : missionID))
    }
    func retry() { if let pending { transmit(pending) } }
    func dismissPending() {
        pending = nil
        pendingSince = nil
        append("Konfirmasi belum diterima. Periksa status iPhone sebelum perintah berikutnya.")
    }
    private func transmit(_ command: Command) {
        do {
            if command.action == .testCapture { expectedTestID = command.id }
            if command.action == .grayCardReference { expectedReferenceID = command.id }
            if command.action == .calibrationBefore { expectedReferenceID = nil }
            if !isDemo { try link.send(Packet(command: command)) }
            pending = command
            pendingSince = Date()
            errorMessage = nil
            append("Mengirim: \(command.action.userTitle)")
            if isDemo { simulate(command) }
        } catch {
            errorMessage = error.localizedDescription
            append(error.localizedDescription)
        }
    }
    private func receive(_ packet: Packet) {
        let prepared =
            pending?.action == .prepare && packet.reply?.commandID == pending?.id
            && packet.reply?.accepted == true
        if let status = packet.telemetry {
            if [.capturing, .countdown, .paused].contains(telemetry.phase), status.phase == .completed {
                review = QualityReview()
                sample = nil
                referenceSaved = false
                grayLocked = false
                showDatasets(missionID: status.missionID)
            }
            telemetry = status
            lastReceived = Date()
        }
        if let records = packet.missions {
            let local = link.store.records().filter { saved in !records.contains(where: { $0.id == saved.id })
            }
            self.records = (records + local).filter { !missionLibrary.hiddenRemoteIDs.contains($0.id) }.sorted
            { $0.createdAt > $1.createdAt }
        }
        // Restore the authoritative mission only once per identity. Never overwrite
        // unsent edits on each heartbeat or a draft that belongs to this Mac.
        if selectedMissionID == nil, !hasLocalDraft, pending == nil, let id = telemetry.missionID,
            loadedMissionID != id,
            let record = records.first(where: { $0.id == id })
        {
            plan = record.plan
            geometry = record.plan.survey ?? SurveyGeometry()
            loadedMissionID = id
            appliedSettings = nil
            sample = nil
            displayedPreview = nil
            review = QualityReview()
            grayLocked = false
            referenceSaved = false
            expectedTestID = nil
            expectedReferenceID = nil
        }
        if let id = telemetry.missionID, let index = records.firstIndex(where: { $0.id == id }) {
            records[index].phase = telemetry.phase
            records[index].saved = telemetry.saved
            records[index].missed = telemetry.missed
        }
        if let id = telemetry.missionID,
            let mIndex = missionLibrary.missions.firstIndex(where: { $0.id == id || $0.remoteID == id })
        {
            missionLibrary.missions[mIndex].saved = telemetry.saved
            missionLibrary.missions[mIndex].phase = telemetry.phase
        }
        if let preview = packet.preview {
            displayedPreview = preview
            if preview.kind == "quality-test", preview.missionID == telemetry.missionID,
                expectedTestID == nil || preview.referenceCommandID == expectedTestID
            {
                sample = preview
                review = QualityReview()
            }
            if preview.kind == "calibration-before", preview.settings == plan.camera,
                preview.missionID == telemetry.missionID,
                expectedReferenceID == nil || preview.referenceCommandID == expectedReferenceID
            {
                referenceSaved = true
            }
        }
        if let reply = packet.reply {
            if let command = pending, command.id == reply.commandID {
                if reply.accepted {
                    if command.action == .createMission {
                        if let index = missionLibrary.missions.firstIndex(where: {
                            $0.id == selectedMissionID
                        }) {
                            var updated = missionLibrary
                            if let oldRemoteID = updated.missions[index].remoteID,
                                oldRemoteID != telemetry.missionID
                            {
                                updated.hiddenRemoteIDs.insert(oldRemoteID)
                            }
                            updated.missions[index].remoteID = telemetry.missionID
                            updated.missions[index].phase = .ready
                            updated.missions[index].preparationRequested = false
                            // Avoid importing a second entry for the same acknowledged dataset.
                            updated.missions.removeAll {
                                $0.id != selectedMissionID && $0.remoteID == telemetry.missionID
                            }
                            guard saveLibrary(updated) else {
                                pending = nil
                                pendingSince = nil
                                return
                            }
                        }
                        hasLocalDraft = false
                        draftCommandID = nil
                        loadedMissionID = telemetry.missionID
                        do { try drafts.clear() } catch {
                            errorMessage =
                                "Gagal menghapus draft yang telah disiapkan: " + error.localizedDescription
                        }
                        expectedReferenceID = nil
                        if let configured = command.plan { plan = configured }
                        appliedSettings = nil
                        sample = nil
                        displayedPreview = nil
                        review = QualityReview()
                        grayLocked = false
                        referenceSaved = false
                    }
                    if command.action == .prepare {
                        appliedSettings = nil
                        sample = nil
                        review = QualityReview()
                        grayLocked = false
                        referenceSaved = false
                    }
                    if [.start, .resume].contains(command.action) { step = .mission }
                    if command.action == .testCapture, guidedMode, let settings = packet.telemetry?.settings {
                        plan.camera = settings
                        appliedSettings = settings
                        plan.focusCalibration = packet.telemetry?.focusCalibration
                    }
                    if command.action == .apply {
                        appliedSettings = command.plan?.camera
                        plan.exposureCalibration = nil
                        plan.focusCalibration = nil
                    }
                    if [.grayCard, .grayCardReference].contains(command.action),
                        let settings = packet.telemetry?.settings
                    {
                        plan.camera = settings
                        plan.exposureCalibration = packet.telemetry?.exposureCalibration
                        appliedSettings = settings
                        grayLocked = true
                        // A reconnect can deliver the saved preview before the original ACK.
                        if let preview = displayedPreview, preview.kind == "calibration-before",
                            preview.settings == settings, preview.missionID == telemetry.missionID,
                            command.action == .grayCard || preview.referenceCommandID == command.id
                        {
                            referenceSaved = true
                        }
                    }
                } else {
                    errorMessage = reply.message
                    if command.action == .createMission, hasLocalDraft {
                        // An explicit rejection is final for this command ID. A new attempt
                        // gets a fresh ID; unknown outcomes still keep their original ID.
                        draftNeedsRetry = true
                        draftCommandID = UUID()
                        if let index = missionLibrary.missions.firstIndex(where: {
                            $0.id == selectedMissionID
                        }) {
                            var updated = missionLibrary
                            updated.missions[index].preparationRequested = false
                            updated.missions[index].commandID = draftCommandID!
                            saveLibrary(updated)
                        }
                        persistDraft()
                        do { try drafts.clear() } catch { errorMessage = error.localizedDescription }
                    }
                }
                pending = nil
                pendingSince = nil
            }
            append(reply.message)
        }
        mergeSavedRecords()
        if packet.telemetry != nil && (packet.reply == nil || prepared) { synchronizeDraft() }
    }
    private func append(_ text: String) {
        log.insert(text, at: 0)
        if log.count > 80 { log.removeLast() }
    }
    private func simulate(_ command: Command) { demoCamera.perform(command) }
    private lazy var demoCamera = DemoCameraSimulator(
        state: { [unowned self] in (self.plan, self.telemetry, self.records) },
        emit: { [weak self] in self?.receive($0) },
        updateRecords: { [weak self] in self?.records = $0 })
    func connectDemo() {
        guard isDemo else { return }
        link.connected = true
        if telemetry.capabilities == nil { send(.prepare) } else { lastReceived = Date() }
    }
}
