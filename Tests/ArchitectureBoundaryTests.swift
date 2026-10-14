import AVFoundation
import AppKit
import Combine
import Foundation

private final class TestTransport: LocalTransport {
    var connected = true { didSet { changes.send(connected) } }
    var status = "Test transport"
    var sending = false
    var receiving = false
    let store: any DatasetRepository
    var onPacket: ((Packet) -> Void)?
    var onConnect: (() -> Void)?
    private let changes = CurrentValueSubject<Bool, Never>(true)
    var connectionChanges: AnyPublisher<Bool, Never> { changes.eraseToAnyPublisher() }
    var sent: [Packet] = []
    var exports: [UUID] = []
    init(store: any DatasetRepository) { self.store = store }
    func send(_ packet: Packet) throws {
        guard connected else { throw MappingError.invalid("Offline") }
        sent.append(packet)
    }
    func export(_ id: UUID) throws { exports.append(id) }
}

private final class TestCamera: CameraService {
    let session = AVCaptureSession()  // Never configured or started.
    var onStatus: ((Telemetry) -> Void)?
    var onPreview: ((CapturePreview) -> Void)?
    var actions: [CommandAction] = []
    var starts: [MissionPlan] = []
    var delayed: ((Result<String, Error>) -> Void)?
    var deferCompletion = false
    func perform(_ command: Command, completion: @escaping (Result<String, Error>) -> Void) {
        actions.append(command.action)
        if deferCompletion { delayed = completion } else { completion(.success("Test completed")) }
    }
    func startPrepared(_ plan: MissionPlan, completion: @escaping (Result<String, Error>) -> Void) {
        starts.append(plan)
        completion(.success("Test started"))
    }
    func updateLocation(_ value: GeoSample?) {}
    func health(battery: Float) {}
    func backgrounded() {}
}

private final class TestDrafts: MissionDraftRepository {
    var saved: Command?
    var failSaving = false
    func load() throws -> Command? { saved }
    func save(_ command: Command) throws {
        if failSaving { throw MappingError.invalid("Test disk failure") }
        saved = command
    }
    func clear() throws { saved = nil }
}

private final class TestExporter: WebODMExportService {
    let output: URL
    var failExport = false
    private let lock = NSLock()
    private var callCount = 0
    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
    init(output: URL) { self.output = output }
    func photos(_ id: UUID) throws -> [ExportPhoto] { [] }
    func export(
        id: UUID, referenceID: UUID?, patch: GrayPatch, confirmed: Bool,
        overlap: Bool, progress: (Int, Int) -> Void
    ) throws -> ExportResult {
        lock.lock()
        callCount += 1
        lock.unlock()
        if failExport { throw MappingError.invalid("Test export failure") }
        progress(1, 2)
        progress(2, 2)
        return ExportResult(folder: output, count: 2, warnings: [])
    }
}

@main enum ArchitectureBoundaryTests {
    static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            checks += 1
        }
        func waitUntil(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            precondition(condition(), "Asynchronous operation did not complete")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mvvm-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DatasetStore(root: folder)
        var mission = MissionRecord(plan: MissionPlan())
        mission.phase = .ready
        try store.write(mission)
        let transport = TestTransport(store: store)
        let camera = TestCamera()
        var status = Telemetry()
        status.missionID = mission.id
        status.phase = .ready
        var foreground = true
        let router = CameraCommandRouter(
            engine: camera, transport: transport, state: { (status, mission.plan, foreground) })
        let command = Command(action: .apply, plan: mission.plan)
        camera.deferCompletion = true
        router.receive(Packet(command: command))
        router.receive(Packet(command: command))
        check(camera.actions == [.apply], "A pending duplicate invokes the camera only once")
        camera.delayed?(.success("Applied"))
        camera.deferCompletion = false
        router.receive(Packet(command: command))
        check(
            camera.actions == [.apply] && transport.sent.last?.reply?.accepted == true,
            "An acknowledged duplicate returns the cached reply")
        router.receive(Packet(replyRequestID: command.id))
        check(
            camera.actions.count == 1 && transport.sent.last?.reply?.commandID == command.id,
            "Reconnect status lookup never executes the command")
        router.receive(Packet(command: Command(action: .start, plan: mission.plan, missionID: UUID())))
        check(
            camera.starts.isEmpty && transport.sent.last?.reply?.accepted == false,
            "A stale mission ID cannot start acquisition")
        foreground = false
        router.receive(Packet(command: Command(action: .start, plan: mission.plan, missionID: mission.id)))
        check(
            camera.starts.isEmpty && transport.sent.last?.reply?.accepted == false,
            "Background command is rejected before reaching the engine")
        foreground = true
        router.receive(Packet(command: Command(action: .start, plan: mission.plan, missionID: mission.id)))
        check(camera.starts.count == 1, "The current ready mission reaches startPrepared")
        status.phase = .capturing
        transport.connected = false
        router.receive(Packet(replyRequestID: command.id))
        check(
            status.phase == .capturing && camera.actions == [.apply],
            "Transport loss cannot issue pause or alter capture state")
        transport.connected = true
        router.receive(Packet(command: Command(action: .pause, missionID: UUID())))
        check(camera.actions == [.apply], "An unrelated mission cannot be paused")
        router.receive(Packet(command: Command(action: .download, missionID: mission.id)))
        check(
            transport.exports == [mission.id],
            "Valid download delegates to the transport after camera approval")

        let drafts = TestDrafts()
        let macTransport = TestTransport(store: DatasetStore(root: folder.appendingPathComponent("mac")))
        macTransport.connected = false
        let control = ControlViewModel(transport: macTransport, drafts: drafts)
        control.createMission(name: "Mission without radio")
        control.openMission(control.selectedMissionID!)
        control.prepareSelectedMission()
        let draftID = drafts.saved?.id
        check(
            drafts.saved?.plan?.name == "Mission without radio" && macTransport.sent.isEmpty,
            "Offline creation uses the injected draft repository")
        let restored = ControlViewModel(transport: macTransport, drafts: drafts)
        check(
            restored.hasLocalDraft && restored.plan.name == "Mission without radio",
            "ViewModel restores injected persistence without global paths")
        macTransport.connected = true
        var ready = status
        ready.phase = .ready
        ready.capabilities = CameraCapabilities(
            model: "Test", minISO: 32, maxISO: 1600, minShutter: 0.0001, maxShutter: 1, width: 4032,
            height: 3024, bayerRAW: true, manualExposure: true, manualFocus: true, manualWB: true)
        macTransport.onPacket?(Packet(telemetry: ready))
        check(restored.pending?.id == draftID, "Synchronizing retains the persisted command identity")
        restored.retry()
        check(
            macTransport.sent.suffix(2).allSatisfy { $0.command?.id == draftID },
            "Unknown outcome retry retains its command identity")
        macTransport.onPacket?(Packet(reply: Reply(commandID: UUID(), accepted: true, message: "Unrelated")))
        check(
            restored.hasLocalDraft && restored.pending?.id == draftID,
            "Unrelated acknowledgement cannot clear a draft")
        macTransport.onPacket?(
            Packet(reply: Reply(commandID: draftID!, accepted: true, message: "Created"), telemetry: ready))
        check(
            !restored.hasLocalDraft && drafts.saved == nil,
            "Only a matching accepted reply clears persistence")
        drafts.failSaving = true
        macTransport.connected = false
        restored.createMission(name: "Disk failure")
        restored.openMission(restored.selectedMissionID!)
        restored.prepareSelectedMission()
        check(
            restored.errorMessage?.contains("Test disk failure") == true,
            "Persistence failure is visible to the operator")

        let exporter = TestExporter(output: folder.appendingPathComponent("export"))
        let export = WebODMExportViewModel(record: mission, service: exporter)
        export.corrected = true
        export.export()
        check(
            !export.working && exporter.calls == 0,
            "Correction requires explicit reference confirmation at the ViewModel boundary")
        export.referenceID = UUID()
        export.confirmed = true
        export.movePatch(x: 2, y: -1)
        check(
            !export.confirmed && export.patch.x == 0.8 && export.patch.y == 0,
            "Changing the bounded card region invalidates confirmation")
        export.corrected = false
        export.export()
        export.export()
        check(export.working, "Export exposes progress state immediately")
        waitUntil { !export.working }
        check(
            exporter.calls == 1 && export.result?.count == 2 && export.completed == 2,
            "Repeated click cannot start a second simultaneous export")
        exporter.failExport = true
        export.export()
        waitUntil { !export.working }
        check(
            export.result == nil && export.error?.contains("Test export failure") == true,
            "Export failure returns to an editable error state")
        print("PASS: \(checks) architecture boundary assertions (no radio or camera capture)")
    }
}
