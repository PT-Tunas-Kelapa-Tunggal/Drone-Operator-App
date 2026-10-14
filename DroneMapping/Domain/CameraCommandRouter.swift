import Foundation

/// In-process deduplication and identity checks. Disconnection never schedules a pause.
final class CameraCommandRouter {
    typealias Snapshot = (telemetry: Telemetry, plan: MissionPlan, foreground: Bool)
    private let engine: any CameraService
    private let transport: any LocalTransport
    private let state: () -> Snapshot
    private var replies: [UUID: Reply] = [:]
    private var pendingIDs: Set<UUID> = []
    var onResult: ((Command, Reply) -> Void)?

    init(engine: any CameraService, transport: any LocalTransport, state: @escaping () -> Snapshot) {
        self.engine = engine
        self.transport = transport
        self.state = state
    }
    func receive(_ packet: Packet) {
        if let id = packet.replyRequestID {
            // Reconnect reads a result; it never replays a shutter command.
            try? transport.send(
                Packet(reply: replies[id], telemetry: state().telemetry, missions: transport.store.records()))
        }
        if let command = packet.command { execute(command) }
    }
    func execute(_ command: Command) {
        let snapshot = state()
        if let reply = replies[command.id] {
            try? transport.send(Packet(reply: reply))
            return
        }
        guard !pendingIDs.contains(command.id) else { return }
        guard pendingIDs.isEmpty, !transport.sending || command.action == .list else {
            let reply = Reply(
                commandID: command.id, accepted: false, message: "Operasi sebelumnya/transfer masih berjalan")
            onResult?(command, reply)
            try? transport.send(Packet(reply: reply))
            return
        }
        pendingIDs.insert(command.id)
        let finish: (Result<String, Error>) -> Void = { result in
            let reply: Reply
            switch result {
            case .success(let text): reply = Reply(commandID: command.id, accepted: true, message: text)
            case .failure(let error):
                reply = Reply(commandID: command.id, accepted: false, message: error.localizedDescription)
            }
            self.pendingIDs.remove(command.id)
            if self.replies.count >= 256 { self.replies.removeAll() }
            self.replies[command.id] = reply
            self.onResult?(command, reply)
            try? self.transport.send(
                Packet(
                    reply: reply, telemetry: self.state().telemetry, missions: self.transport.store.records())
            )
        }
        guard snapshot.foreground else {
            finish(.failure(MappingError.invalid("DroneCam harus aktif di layar")))
            return
        }
        if [.pause, .resume, .finish].contains(command.action),
            command.missionID == nil || command.missionID != snapshot.telemetry.missionID
        {
            finish(
                .failure(
                    MappingError.invalid(
                        "Misi pada iPhone telah berubah; tunggu sinkronisasi sebelum mengendalikannya")))
            return
        }
        switch command.action {
        case .prepare: engine.perform(command, completion: finish)
        case .list:
            finish(.success("Daftar dataset diperbarui"))
        case .download:
            engine.perform(command) { result in
                do {
                    _ = try result.get()
                    guard let id = command.missionID,
                        self.transport.store.records().contains(where: { $0.id == id })
                    else {
                        throw MappingError.invalid("Dataset tidak ditemukan")
                    }
                    try self.transport.export(id)
                    finish(.success("Transfer dimulai; berkas diverifikasi pada Mac"))
                } catch { finish(.failure(error)) }
            }
        case .start where snapshot.telemetry.phase == .ready && snapshot.telemetry.missionID != nil:
            guard command.missionID == snapshot.telemetry.missionID else {
                finish(
                    .failure(
                        MappingError.invalid(
                            "Misi pada iPhone telah berubah; tunggu sinkronisasi dan mulai ulang dari misi yang benar"
                        )))
                return
            }
            engine.startPrepared(command.plan ?? snapshot.plan, completion: finish)
        default: engine.perform(command, completion: finish)
        }
    }
}
