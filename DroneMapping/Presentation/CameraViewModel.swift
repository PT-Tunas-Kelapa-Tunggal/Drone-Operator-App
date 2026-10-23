import AVFoundation
import Combine
import SwiftUI

final class CameraViewModel: ObservableObject {
    @Published private(set) var telemetry = Telemetry()
    @Published private(set) var plan = MissionPlan()
    @Published private(set) var message = "Mulai dengan menyiapkan kamera"
    @Published private(set) var records: [MissionRecord] = []
    @Published var savePowerInFlight = true
    private let engine: any CameraService
    var previewSession: AVCaptureSession { engine.session }
    let link: any LocalTransport
    private let locations: LocationService
    private var heartbeat: Timer?
    private var lastPreview: CapturePreview?
    private var foreground = true
    private var didRequestPreparation = false

    init(
        engine: any CameraService, transport: any LocalTransport,
        locations: LocationService = LocationService()
    ) {
        self.engine = engine
        self.link = transport
        self.locations = locations
        UIDevice.current.isBatteryMonitoringEnabled = true
        locations.onSample = { [weak engine] in engine?.updateLocation($0) }
        locations.onAttitude = { [weak engine] in engine?.updateAttitude($0) }
        do {
            try link.store.migrateLegacy()
            try link.store.recoverInterrupted()
        } catch { message = "Pemulihan dataset: \(error.localizedDescription)" }
        records = link.store.records()
        if records.contains(where: { $0.phase == .paused }) {
            message = "Misi sebelumnya terinterupsi. Dataset tetap tersedia; tidak dilanjutkan otomatis."
        }
        engine.onStatus = { [weak self] status in
            guard let self else { return }
            let datasetChanged = self.telemetry.missionID != status.missionID
                || self.telemetry.saved != status.saved || self.telemetry.phase != status.phase
            self.telemetry = status
            if datasetChanged { self.records = self.link.store.records() }
            UIDevice.current.isBatteryMonitoringEnabled = true
            self.updateIdleTimer()
            // Publish manifests after capture changes, including automatic completion.
            if self.link.connected {
                try? self.link.send(Packet(telemetry: status, missions: datasetChanged ? self.records : nil))
            }
        }
        engine.onPreview = { [weak self] preview in
            guard let self else { return }
            self.lastPreview = preview
            if self.link.connected { try? self.link.send(Packet(preview: preview)) }
        }
        router.onResult = { [weak self] command, reply in self?.applyResult(command, reply: reply) }
        link.onPacket = { [weak self] packet in self?.router.receive(packet) }
        link.onConnect = { [weak self] in
            guard let self else { return }
            self.refreshDatasets()
            // A large preview must not prevent the dataset list and status from syncing.
            try? self.link.send(Packet(telemetry: self.telemetry, missions: self.records))
            if let preview = self.lastPreview { try? self.link.send(Packet(preview: preview)) }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.engine.health(battery: UIDevice.current.batteryLevel)
        }
    }

    var isPreviewActive: Bool {
        !(telemetry.phase == .capturing && savePowerInFlight)
    }

    var canTransfer: Bool {
        link.connected && !link.sending && !link.receiving && telemetry.captureBusy != true
            && ![.capturing, .countdown].contains(telemetry.phase)
    }

    var canPauseLocally: Bool {
        telemetry.missionID != nil && [.capturing, .countdown].contains(telemetry.phase)
    }

    var canResumeLocally: Bool {
        telemetry.missionID != nil && telemetry.phase == .paused && telemetry.captureBusy != true
    }

    var canFinishLocally: Bool {
        telemetry.missionID != nil && [.capturing, .countdown, .paused].contains(telemetry.phase)
            && telemetry.captureBusy != true
    }

    func canDeleteDataset(_ id: UUID) -> Bool {
        guard !link.sending, !link.receiving, telemetry.captureBusy != true else { return false }
        if telemetry.missionID == id && [.ready, .countdown, .capturing, .paused].contains(telemetry.phase) {
            return false
        }
        return true
    }

    func pauseMissionLocally() {
        guard let missionID = telemetry.missionID else { return }
        router.execute(Command(action: .pause, missionID: missionID))
    }

    func resumeMissionLocally() {
        guard let missionID = telemetry.missionID else { return }
        router.execute(Command(action: .resume, missionID: missionID))
    }

    func finishMissionLocally() {
        guard let missionID = telemetry.missionID else { return }
        router.execute(Command(action: .finish, missionID: missionID))
    }

    func deleteDataset(_ id: UUID) {
        guard canDeleteDataset(id) else {
            message = "Selesaikan misi dan tunggu transfer selesai sebelum menghapus dataset."
            return
        }
        do {
            try link.store.removeLocalMissionFiles([id])
            refreshDatasets()
            message = "Dataset lokal dihapus dari iPhone."
            if link.connected {
                try? link.send(Packet(telemetry: telemetry, missions: records))
            }
        } catch {
            message = "Gagal menghapus dataset: \(error.localizedDescription)"
        }
    }

    func transferToMac(_ id: UUID) {
        guard canTransfer else {
            message = "Hubungkan Mac dan tunggu capture selesai sebelum transfer."
            return
        }
        router.execute(Command(action: .download, missionID: id))
        updateIdleTimer()
    }

    func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            [.ready, .countdown, .capturing, .paused].contains(telemetry.phase) || link.sending
    }

    func refreshDatasets() {
        records = link.store.records()
    }

    func prepare() {
        guard !didRequestPreparation else { return }
        didRequestPreparation = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.message = "Aktifkan izin Kamera di Settings"
                    return
                }
                self.locations.start()
                self.router.execute(Command(action: .prepare))
            }
        }
    }

    func scene(_ phase: ScenePhase) {
        foreground = phase == .active
        if foreground {
            refreshDatasets()
            updateIdleTimer()
        }
        // Temporary inactivity (e.g. Control Center) is not a request to pause a mission.
        // Actual camera interruptions are handled independently by CameraEngine.
        if phase == .background {
            engine.backgrounded()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    deinit {
        heartbeat?.invalidate()
        locations.stop()
    }

    private lazy var router = CameraCommandRouter(
        engine: engine, transport: link,
        state: { [weak self] in
            guard let self else { return (Telemetry(), MissionPlan(), false) }
            return (self.telemetry, self.plan, self.foreground)
        })

    private func applyResult(_ command: Command, reply: Reply) {
        message = reply.message
        if reply.accepted, [.createMission, .apply, .start].contains(command.action),
            let configured = command.plan
        {
            self.plan = configured
        }
        if [.grayCard, .grayCardReference].contains(command.action), reply.accepted,
            let value = self.telemetry.settings
        {
            self.plan.camera = value
            self.plan.exposureCalibration = self.telemetry.exposureCalibration
        }
        if command.action == .testCapture, reply.accepted, let value = self.telemetry.settings {
            self.plan.camera = value
            self.plan.focusCalibration = self.telemetry.focusCalibration
        }
        records = link.store.records()
    }
}
