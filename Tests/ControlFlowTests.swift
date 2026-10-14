import AppKit
import Foundation

@main enum ControlFlowTests {
    static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name)
            checks += 1
        }
        let draftFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "offline-mission-" + UUID().uuidString)
        let draftURL = draftFolder.appendingPathComponent("draft.json")
        defer { try? FileManager.default.removeItem(at: draftFolder) }
        let offline = ControlViewModel(demo: true, draftURL: draftURL)
        offline.createMission(name: "  Kebun offline  ")
        offline.openMission(offline.selectedMissionID!)
        offline.prepareSelectedMission()
        check(
            offline.hasLocalDraft && offline.plan.name == "Kebun offline"
                && offline.telemetry.missionID == nil && offline.pending == nil,
            "Offline creation saves a local draft without a radio command")
        check(FileManager.default.fileExists(atPath: draftURL.path), "Offline draft survives app shutdown")
        offline.geometry.heightAGL = 65
        offline.plan.durationSeconds = 900
        let restored = ControlViewModel(demo: true, draftURL: draftURL)
        check(
            restored.hasLocalDraft && restored.plan.name == "Kebun offline"
                && restored.geometry.heightAGL == 65 && restored.plan.durationSeconds == 900,
            "Draft name and edits restored before connection")
        check(
            !restored.readiness().canStart && !restored.settingsApplied,
            "Local draft cannot claim an applied camera or start offline")
        restored.createMission(name: " ")
        check(
            restored.hasLocalDraft && restored.plan.name == "Kebun offline",
            "Invalid name cannot erase saved draft")
        restored.connectDemo()
        check(
            !restored.hasLocalDraft && restored.telemetry.missionID != nil
                && restored.plan.name == "Kebun offline" && restored.geometry.heightAGL == 65,
            "Fresh prepared connection automatically creates the named draft on iPhone")
        check(
            !FileManager.default.fileExists(atPath: draftURL.path),
            "Acknowledged draft removed from local pending storage")
        let synchronizedID = restored.telemetry.missionID
        restored.link.onPacket?(Packet(telemetry: restored.telemetry))
        check(
            restored.telemetry.missionID == synchronizedID,
            "Later telemetry does not recreate an acknowledged draft")
        let busy = ControlViewModel(demo: true)
        busy.createMission(name: "Draft menunggu")
        busy.openMission(busy.selectedMissionID!)
        busy.prepareSelectedMission()
        busy.link.connected = true
        var activeStatus = restored.telemetry
        activeStatus.phase = .capturing
        busy.link.onPacket?(Packet(telemetry: activeStatus))
        check(
            busy.hasLocalDraft && busy.pending == nil && busy.telemetry.missionID == synchronizedID,
            "Offline draft never replaces a mission that is already flying")
        busy.createMission(name: "Tidak boleh mengganti")
        check(
            busy.plan.name == "Draft menunggu",
            "Active mission protection still applies to new mission creation")
        activeStatus.phase = .ready
        busy.link.onPacket?(Packet(telemetry: activeStatus))
        check(
            !busy.hasLocalDraft && busy.plan.name == "Draft menunggu",
            "Draft synchronizes once camera becomes ready")
        let retryURL = draftFolder.appendingPathComponent("retry.json")
        let retryModel = ControlViewModel(demo: true, draftURL: retryURL)
        retryModel.createMission(name: "Ditolak sementara")
        retryModel.openMission(retryModel.selectedMissionID!)
        retryModel.prepareSelectedMission()
        let firstAttempt = try! JSONDecoder().decode(Command.self, from: Data(contentsOf: retryURL))
        retryModel.pending = firstAttempt
        retryModel.link.onPacket?(
            Packet(reply: Reply(commandID: firstAttempt.id, accepted: false, message: "Kamera belum siap")))
        let nextAttempt = retryModel.selectedMission!.commandID
        check(
            retryModel.hasLocalDraft && retryModel.draftNeedsRetry && retryModel.pending == nil
                && nextAttempt != firstAttempt.id,
            "A rejected draft retains its data and persists a fresh command identity")
        retryModel.link.connected = true
        retryModel.link.onPacket?(Packet(telemetry: activeStatus))
        check(
            retryModel.hasLocalDraft && retryModel.draftNeedsRetry && retryModel.pending == nil,
            "Heartbeats do not endlessly resend a rejected draft")
        retryModel.link.onPacket?(
            Packet(reply: Reply(commandID: firstAttempt.id, accepted: false, message: "Penolakan lama")))
        retryModel.retryDraft()
        check(
            !retryModel.hasLocalDraft && !retryModel.draftNeedsRetry
                && retryModel.plan.name == "Ditolak sementara",
            "Explicit retry can create mission after correcting readiness")
        let model = ControlViewModel(demo: true)
        model.send(.start)
        check(model.telemetry.phase == .idle && model.pending == nil, "Disconnected start must not execute")
        model.connectDemo()
        check(
            model.telemetry.phase == .ready && model.telemetry.capabilities != nil,
            "Connection prepares camera")
        model.send(.start)
        check(model.telemetry.phase == .ready, "Unreviewed start blocked")
        model.createMission(name: "Kebun utara")
        model.openMission(model.selectedMissionID!)
        model.prepareSelectedMission()
        check(
            model.plan.name == "Kebun utara" && model.telemetry.missionID != nil && model.step == .mission,
            "Named mission created on unified mission screen")
        model.setGuidedMode(false)
        model.geometry.reviewed = true
        model.recommend()
        model.send(.apply)
        check(model.settingsApplied, "Apply acknowledged")
        check(
            model.readiness().blockers.first == "Ambil referensi gray card 18% untuk mengunci warna",
            "Calibration is guided before test capture")
        model.send(.grayCard)
        check(model.grayLocked && model.settingsApplied, "Gray gains acknowledged and retained")
        check(
            model.readiness().blockers.first == "Tunggu foto referensi gray card tersimpan di iPhone",
            "Reference is guided before test capture")
        model.send(.calibrationBefore)
        check(model.referenceSaved, "Reference marked only after saved preview")
        model.send(.testCapture)
        check(model.sample != nil && model.sample?.kind == "quality-test", "Test received")
        check(model.telemetry.saved == 0, "Test/reference do not increment mapping counter")
        model.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        check(model.readiness().canStart, "Reviewed complete flow is ready")
        model.plan.camera.iso = 200
        check(
            !model.readiness().canStart && !model.review.complete && !model.referenceSaved,
            "Camera edit invalidates test review and reference")
        model.send(.apply)
        model.send(.grayCardReference)
        check(
            model.grayLocked && model.referenceSaved && model.settingsApplied && model.sample == nil,
            "Single reference action locks WB, saves reference and requires a fresh test")
        check(
            model.displayedPreview?.kind == "calibration-before",
            "Reference is separated from mapping and test captures")
        let reference = model.displayedPreview!
        check(
            reference.referenceCommandID != nil,
            "Saved reference is correlated to the command across reconnect")
        let exposure = model.plan.camera
        model.referenceSaved = false
        var stale = reference
        stale.referenceCommandID = UUID()
        model.link.onPacket?(Packet(preview: stale))
        check(!model.referenceSaved, "An earlier or unrelated reference cannot complete a new calibration")
        stale = reference
        stale.missionID = UUID()
        model.link.onPacket?(Packet(preview: stale))
        check(!model.referenceSaved, "A reference from another mission cannot satisfy readiness")
        model.plan.camera.whiteBalanceGains = nil
        let command = Command(id: reference.referenceCommandID!, action: .grayCardReference, plan: model.plan)
        model.pending = command
        model.link.onPacket?(Packet(preview: reference))
        check(
            !model.referenceSaved,
            "Preview arriving before WB acknowledgement does not bypass settings matching")
        var acknowledged = model.telemetry
        acknowledged.settings = reference.settings
        model.link.onPacket?(
            Packet(
                reply: Reply(commandID: command.id, accepted: true, message: "Warna terkunci"),
                telemetry: acknowledged))
        check(
            model.referenceSaved && model.grayLocked && model.settingsApplied,
            "Reconnect restores saved reference when preview arrives before ACK")
        check(
            model.plan.camera.iso == exposure.iso
                && model.plan.camera.shutterSeconds == exposure.shutterSeconds,
            "Gray card keeps flight exposure unchanged")
        model.send(.testCapture)
        model.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        check(model.readiness().canStart, "Recheck after edit restores readiness")
        model.sample?.captureSeconds = 1.05
        model.plan.interval = 1.1
        check(model.suggestedCaptureInterval == 1.4, "Controller suggests cadence correction")
        model.review.endurance = true
        model.adjustCaptureInterval()
        check(
            model.plan.interval == 1.4 && !model.review.endurance,
            "Correction resets cadence review without claiming a test")
        check(model.settingsApplied, "Interval correction preserves camera ACK")
        model.review.endurance = true
        model.plan.interval += 0.1
        check(!model.review.endurance, "Interval edit invalidates cadence check")
        model.review.endurance = true
        model.send(.start)
        check(model.telemetry.phase == .capturing, "Start only after all checks")
        let missionID = model.telemetry.missionID
        model.link.connected = false
        model.send(.pause)
        check(model.telemetry.phase == .capturing, "Offline control cannot pause autonomous mission")
        model.link.onConnect?()
        model.connectDemo()
        check(
            model.telemetry.phase == .capturing && model.telemetry.missionID == missionID,
            "Reconnect preserves mission")
        model.send(.pause)
        check(model.telemetry.phase == .paused, "Explicit connected pause")
        model.send(.resume)
        check(model.telemetry.phase == .capturing, "Explicit resume")
        model.send(.finish)
        check(model.telemetry.phase == .completed, "Explicit finish")
        check(
            !model.review.complete && model.sample == nil && !model.readiness().canStart,
            "Completed mission requires a fresh quality review")
        check(model.step == .datasets, "Completion guides operator to datasets")
        let guided = ControlViewModel(demo: true)
        guided.connectDemo()
        guided.createMission(name: "Panduan")
        guided.openMission(guided.selectedMissionID!)
        guided.prepareSelectedMission()
        check(guided.guidedMode, "New operators default to guided mode")
        guided.geometry.reviewed = true
        guided.prepareGuided()
        check(
            guided.settingsApplied && guided.plan.photoLimit == Int(ceil(600 / guided.plan.interval)),
            "Guided setup applies settings and derives count from duration")
        check(
            guided.plan.exposureCalibration == nil && !guided.readiness().canStart,
            "Guided flight requires a meter reading")
        guided.send(.grayCardReference)
        check(
            guided.plan.exposureCalibration != nil && guided.referenceSaved && guided.settingsApplied,
            "Guided gray card synchronizes measured exposure and saved reference")
        guided.send(.testCapture)
        guided.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        check(guided.readiness().canStart, "Guided flow becomes ready after checks")
        check(
            guided.plan.camera.lensPosition == 0.72 && guided.plan.focusCalibration?.lensPosition == 0.72,
            "Measured AF position replaces the fixed far endpoint")
        check(
            guided.referenceSaved && guided.grayLocked && guided.plan.exposureCalibration != nil,
            "Focusing preserves exposure and gray-card calibration")
        check(
            guided.sample?.sharpness?.scores.count == 5, "Test includes center and edge sharpness diagnostics"
        )
        let acceptedTest = guided.sample!
        guided.sample = nil
        var earlierTest = acceptedTest
        earlierTest.referenceCommandID = UUID()
        guided.link.onPacket?(Packet(preview: earlierTest))
        check(guided.sample == nil, "Late earlier test cannot complete the current focus check")
        guided.link.onPacket?(Packet(preview: acceptedTest))
        guided.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        let correctMission = guided.sample?.missionID
        guided.sample?.missionID = UUID()
        check(!guided.readiness().canStart, "Another mission's test cannot satisfy readiness")
        guided.sample?.missionID = correctMission!
        let detail = guided.sample?.sharpness
        guided.sample?.sharpness = nil
        check(!guided.readiness().canStart, "Missing detail analysis requires a new test")
        guided.sample?.sharpness = detail
        let originalAssessment = guided.sample?.assessment
        guided.sample?.assessment = PreviewAssessment(darkFraction: 1, clippedFraction: 0, meanBrightness: 0)
        check(!guided.readiness().canStart, "Black test cannot be approved by checkboxes")
        guided.sample?.assessment = nil
        check(!guided.readiness().canStart, "Guided flow requires a basic exposure assessment")
        guided.sample?.assessment = originalAssessment
        guided.plan.interval = 1.1
        guided.sample?.captureSeconds = 1.05
        guided.adjustCaptureInterval()
        check(
            guided.plan.photoLimit == Int(ceil(600 / guided.plan.interval)),
            "Cadence correction preserves requested duration")
        guided.plan.camera.iso += 10
        check(
            !guided.referenceSaved && !guided.readiness().canStart,
            "Editing exposure invalidates guided reference")
        checks += OperatorFlowTests.run()
        checks += DevicePanelFlowTests.run()
        checks += MissionLibraryTests.run()
        print("PASS: \(checks) controller flow assertions (simulated hardware)")
    }
}
