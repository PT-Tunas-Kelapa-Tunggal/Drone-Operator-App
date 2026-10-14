import AppKit
import Foundation

/// Explicit simulation; never opens discovery or sends a hardware command.
final class DemoCameraSimulator {
    typealias Snapshot = (plan: MissionPlan, telemetry: Telemetry, records: [MissionRecord])
    private let state: () -> Snapshot
    private let emit: (Packet) -> Void
    private let updateRecords: ([MissionRecord]) -> Void
    init(
        state: @escaping () -> Snapshot, emit: @escaping (Packet) -> Void,
        updateRecords: @escaping ([MissionRecord]) -> Void
    ) {
        self.state = state
        self.emit = emit
        self.updateRecords = updateRecords
    }
    func perform(_ command: Command, referenceCommandID: UUID? = nil) {
        let snapshot = state()
        let plan = snapshot.plan
        var status = snapshot.telemetry
        switch command.action {
        case .prepare:
            status.phase = .ready
            status.battery = 0.88
            status.thermal = "Normal"
            status.freeBytes = 40_000_000_000
            status.capabilities = CameraCapabilities(
                model: "Kamera demo", minISO: 32, maxISO: 1600, minShutter: 0.0001, maxShutter: 1,
                width: 4032, height: 3024, bayerRAW: true, manualExposure: true, manualFocus: true,
                manualWB: true, nominalFieldOfView: 65)
        case .createMission:
            var record = MissionRecord(plan: command.plan ?? plan)
            status.missionID = record.id
            status.saved = 0
            status.missed = 0
            status.phase = .ready
            record.phase = .ready
            var records = snapshot.records
            records.insert(record, at: 0)
            updateRecords(records)
        case .apply:
            status.settings = plan.camera
            status.exposureCalibration = nil
        case .grayCard, .grayCardReference:
            var settings = plan.camera
            settings.whiteBalanceGains = [1.8, 1, 1.5]
            if command.action == .grayCardReference, plan.guidedMode == true {
                settings.iso = 160
                status.exposureCalibration = ExposureCalibration(
                    measuredAt: Date(), meteredISO: 80, meteredShutter: settings.shutterSeconds * 2,
                    selectedISO: settings.iso, selectedShutter: settings.shutterSeconds)
            }
            status.settings = settings
            if command.action == .grayCardReference {
                emit(
                    Packet(
                        reply: Reply(commandID: command.id, accepted: true, message: "Demo: warna terkunci"),
                        telemetry: status))
                perform(
                    Command(id: command.id, action: .calibrationBefore, plan: plan),
                    referenceCommandID: command.id)
                return
            }
        case .testCapture, .calibrationBefore, .calibrationAfter:
            if command.action == .testCapture, plan.guidedMode == true {
                var focused = plan.camera
                focused.lensPosition = 0.72
                status.settings = focused
                status.focusCalibration = FocusCalibration(
                    measuredAt: Date(), lensPosition: focused.lensPosition)
                emit(
                    Packet(
                        reply: Reply(
                            commandID: command.id, accepted: true,
                            message: "Demo: fokus ditemukan dan dikunci"), telemetry: status))
            }
            let capturePlan = state().plan
            let id = status.missionID ?? UUID()
            status.missionID = id
            let kind =
                command.action == .testCapture
                ? "quality-test"
                : command.action == .calibrationBefore ? "calibration-before" : "calibration-after"
            let image = NSImage(size: NSSize(width: 1000, height: 700))
            image.lockFocus()
            NSColor.darkGray.setFill()
            NSRect(x: 0, y: 0, width: 1000, height: 700).fill()
            for x in 0..<10 {
                for y in 0..<7 where (x + y) % 2 == 0 {
                    NSColor.gray.setFill()
                    NSRect(x: x * 100, y: y * 100, width: 100, height: 100).fill()
                }
            }
            NSString(string: "DEMO • BUKAN FOTO IPHONE").draw(
                at: NSPoint(x: 160, y: 325),
                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 32), .foregroundColor: NSColor.white])
            image.unlockFocus()
            let data =
                image.tiffRepresentation.flatMap {
                    NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [:])
                } ?? Data()
            emit(
                Packet(
                    preview: CapturePreview(
                        captureID: UUID(), missionID: id, kind: kind, settings: capturePlan.camera,
                        imageData: data,
                        captureSeconds: 0.6, savedAt: Date(), width: 4032, height: 3024,
                        referenceCommandID: command.action == .testCapture ? command.id : referenceCommandID,
                        assessment: PreviewAssessment.image(data),
                        sharpness: SharpnessAssessment(
                            scores: [100, 100, 100, 100, 100], texturedPatches: 5),
                        actualExposure: CapturedExposure(
                            iso: Double(capturePlan.camera.iso),
                            shutterSeconds: capturePlan.camera.shutterSeconds),
                        storedBytes: capturePlan.camera.raw ? 30_000_000 : 5_000_000)))
        case .start, .resume:
            var records = snapshot.records
            if let index = records.firstIndex(where: { $0.id == status.missionID }) {
                records[index].plan = command.plan ?? plan
            }
            updateRecords(records)
            status.phase = .capturing
        case .pause: status.phase = .paused
        case .finish: status.phase = .completed
        default: break
        }
        status.message = "Operasi demo selesai"
        status.captureBusy = false
        emit(
            Packet(
                reply: Reply(
                    commandID: command.id, accepted: true, message: "Demo: \(command.action.userTitle)"),
                telemetry: status))
    }
}
