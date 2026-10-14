import AVFoundation
import Combine
import SwiftUI

final class CameraViewModel: ObservableObject {
    @Published private(set) var telemetry = Telemetry()
    @Published private(set) var plan = MissionPlan()
    @Published private(set) var message = "Mulai dengan menyiapkan kamera"
    @Published private(set) var records: [MissionRecord] = []
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
            self.telemetry = status
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIApplication.shared.isIdleTimerDisabled = [.capturing, .countdown].contains(status.phase)
            // Telemetry is best effort. Transport failure cannot change camera state or timing.
            if self.link.connected { try? self.link.send(Packet(telemetry: status)) }
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
            try? self.link.send(
                Packet(
                    preview: self.lastPreview, telemetry: self.telemetry, missions: self.link.store.records())
            )
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.engine.health(battery: UIDevice.current.batteryLevel)
        }
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
        // Temporary inactivity (e.g. Control Center) is not a request to pause a mission.
        // Actual camera interruptions are handled independently by CameraEngine.
        if phase == .background {
            engine.backgrounded()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    deinit { heartbeat?.invalidate() }
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
