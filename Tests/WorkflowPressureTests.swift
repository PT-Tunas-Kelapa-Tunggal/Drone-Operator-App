import Foundation

struct WorkflowPressureTests {
    struct State {
        var plan = MissionPlan()
        var geometry = SurveyGeometry()
        var telemetry = Telemetry()
        var connected = true
        var received: Date? = Date()
        var pending = false
        var applied: CameraSettings? = CameraSettings()
        var sample: CapturePreview?
        var review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        var gray = true
        var reference = true
        init() {
            plan.interval = 2
            geometry.reviewed = true
            telemetry.missionID = UUID()
            telemetry.phase = .ready
            telemetry.battery = 0.8
            telemetry.thermal = "Normal"
            telemetry.freeBytes = 10_000_000_000
            telemetry.settings = plan.camera
            telemetry.capabilities = CameraCapabilities(
                model: "Test", minISO: 32, maxISO: 1600, minShutter: 0.0001, maxShutter: 1,
                width: 4032, height: 3024, bayerRAW: true, manualExposure: true, manualFocus: true,
                manualWB: true, nominalFieldOfView: 65)
            sample = CapturePreview(
                captureID: UUID(), missionID: telemetry.missionID!, kind: "quality-test",
                settings: plan.camera,
                imageData: Data(), captureSeconds: 0.6, savedAt: Date(), width: 4032, height: 3024,
                actualExposure: CapturedExposure(iso: 100, shutterSeconds: 0.001), storedBytes: 5_000_000)
        }
        func result() -> StartReadiness {
            StartReadiness.evaluate(
                plan: plan, geometry: geometry, telemetry: telemetry, connected: connected,
                lastReceived: received, now: Date(), pending: pending, appliedSettings: applied,
                sample: sample,
                review: review, grayLocked: gray, referenceSaved: reference)
        }
    }
    static func run() -> Int {
        var assertions = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label)
            assertions += 1
        }
        check(State().result().canStart, "Valid reviewed baseline must pass")
        let scenarios: [(String, (inout State) -> Void)] = [
            ("disconnect before start", { $0.connected = false }),
            ("no telemetry", { $0.received = nil }),
            ("stale status", { $0.received = Date().addingTimeInterval(-7) }),
            ("future clock", { $0.received = Date().addingTimeInterval(60) }),
            ("pending ACK", { $0.pending = true }),
            ("photo still writing", { $0.telemetry.captureBusy = true }),
            ("countdown underway", { $0.telemetry.phase = .countdown }),
            ("already capturing", { $0.telemetry.phase = .capturing }),
            ("paused mission cannot start another", { $0.telemetry.phase = .paused }),
            ("camera failed", { $0.telemetry.phase = .failed }),
            ("empty mission name", { $0.plan.name = " " }),
            ("negative interval", { $0.plan.interval = -1 }),
            ("nonfinite interval", { $0.plan.interval = .nan }),
            ("zero target", { $0.plan.photoLimit = 0 }),
            ("invalid ISO", { $0.plan.camera.iso = 5000 }),
            ("invalid hardware ISO range", { $0.telemetry.capabilities?.minISO = 2000 }),
            ("invalid hardware shutter range", { $0.telemetry.capabilities?.minShutter = 2 }),
            ("missing capabilities", { $0.telemetry.capabilities = nil }),
            ("no manual focus", { $0.telemetry.capabilities?.manualFocus = false }),
            (
                "unsupported RAW",
                {
                    $0.plan.camera.raw = true
                    $0.telemetry.capabilities?.bayerRAW = false
                }
            ),
            ("settings not acknowledged", { $0.applied = nil }),
            ("phone settings differ", { $0.telemetry.settings?.iso = 200 }),
            ("draft changed after test", { $0.plan.camera.iso = 200 }),
            ("height too high for GSD target", { $0.geometry.heightAGL = 200 }),
            ("zero speed", { $0.geometry.speed = 0 }),
            ("invalid overlap", { $0.geometry.forwardOverlap = 1 }),
            ("unreviewed geometry", { $0.geometry.reviewed = false }),
            ("missing FOV / calibration", { $0.telemetry.capabilities?.nominalFieldOfView = nil }),
            ("invalid photo dimension", { $0.telemetry.capabilities?.width = 0 }),
            ("interval breaks overlap", { $0.plan.interval = 100 }),
            ("slow shutter causes blur", { $0.plan.camera.shutterSeconds = 0.05 }),
            ("no test photo", { $0.sample = nil }),
            ("reference cannot substitute test", { $0.sample?.kind = "calibration-before" }),
            ("test used old settings", { $0.sample?.settings.iso = 200 }),
            ("capture slower than cadence", { $0.sample?.captureSeconds = 3 }),
            ("nonfinite sample time", { $0.sample?.captureSeconds = .nan }),
            ("missing focus check", { $0.review.focus = false }),
            ("missing exposure check", { $0.review.highlights = false }),
            ("missing endurance check", { $0.review.endurance = false }),
            ("missing control points", { $0.review.controlPoints = false }),
            ("gray not locked", { $0.gray = false }),
            ("reference not saved", { $0.reference = false }),
            ("missing actual exposure", { $0.sample?.actualExposure = nil }),
            (
                "actual shutter too slow despite equal exposure product",
                { $0.sample?.actualExposure = CapturedExposure(iso: 50, shutterSeconds: 0.002) }
            ),
            ("nonfinite actual exposure", { $0.sample?.actualExposure?.iso = .nan }),
            ("missing storage sample", { $0.sample?.storedBytes = nil }),
            ("disk fits one image but not entire mission", { $0.telemetry.freeBytes = 600_000_000 }),
            ("storage estimate overflow", { $0.sample?.storedBytes = Int64.max }),
            ("disk low", { $0.telemetry.freeBytes = 100 }),
            ("battery unknown", { $0.telemetry.battery = -1 }),
            ("battery too low", { $0.telemetry.battery = 0.1 }),
            ("thermal serious", { $0.telemetry.thermal = "Panas" }),
            ("thermal critical", { $0.telemetry.thermal = "Kritis" }),
        ]
        for (label, mutate) in scenarios {
            var state = State()
            mutate(&state)
            check(!state.result().canStart, label)
        }
        var rounded = State()
        rounded.plan.camera.iso = 461.4601
        rounded.applied = rounded.plan.camera
        rounded.telemetry.settings = rounded.plan.camera
        rounded.sample?.settings = rounded.plan.camera
        rounded.sample?.actualExposure = CapturedExposure(iso: 500, shutterSeconds: 1 / 1001)
        check(
            rounded.result().canStart,
            "Observed iPhone EXIF rounding is tolerated without permitting a slower shutter")
        check(
            MissionStorage.requiredBytes(sampleBytes: 10_000_000, photoCount: 200) == 3_136_870_912,
            "Mission budget includes all captures, thirty percent margin, and reserve")
        check(
            MissionStorage.requiredBytes(sampleBytes: 0, photoCount: 200) == nil,
            "Zero bytes cannot certify storage")
        let metadata: [String: Any] = [
            "{Exif}": [
                "ISOSpeedRatings": [NSNumber(value: 500)], "ExposureTime": NSNumber(value: 1 / 1001.0),
            ]
        ]
        check(
            CapturedExposure(metadata: metadata)?.matches(rounded.plan.camera) == true,
            "Original EXIF extraction handles numeric metadata")
        check(CapturedExposure(metadata: [:]) == nil, "Missing EXIF never substitutes requested settings")
        var manual = State()
        manual.geometry.useGrayCard = false
        manual.gray = false
        manual.reference = false
        check(manual.result().canStart, "Reviewed manual WB path must not require a gray card")
        var completed = State()
        completed.telemetry.phase = .completed
        check(
            !completed.result().canStart, "Completed mission requires explicit creation of the next mission")
        var calibrated = State()
        calibrated.geometry.calibratedFocalPixels = 3500
        calibrated.telemetry.capabilities?.nominalFieldOfView = nil
        check(calibrated.result().canStart, "Calibrated focal length can replace nominal FOV")
        var screenshot = State()
        screenshot.telemetry.capabilities?.width = 8064
        screenshot.telemetry.capabilities?.height = 6048
        screenshot.geometry.heightAGL = 35
        screenshot.geometry.calibratedFocalPixels = 35 / 0.0059
        screenshot.plan.interval = 1.1
        screenshot.sample?.captureSeconds = 1.05
        check(!screenshot.result().canStart, "Screenshot cadence 1.05s must not pass a 1.1s interval")
        check(
            screenshot.result().blockers.contains { $0.contains("1.4 s") },
            "Actionable interval advice rounds up to 1.4s")
        screenshot.plan.interval = 1.4
        screenshot.plan.camera.shutterSeconds = 1 / 2128.571
        screenshot.sample?.actualExposure = CapturedExposure(
            iso: Double(screenshot.plan.camera.iso), shutterSeconds: screenshot.plan.camera.shutterSeconds)
        screenshot.applied = screenshot.plan.camera
        screenshot.telemetry.settings = screenshot.plan.camera
        screenshot.sample?.settings = screenshot.plan.camera
        check(screenshot.result().canStart, "1.4s fits both measured cadence and screenshot overlap")
        screenshot.geometry.speed = 10
        screenshot.plan.interval = 1.1
        check(
            screenshot.result().blockers.contains { $0.contains("turunkan kecepatan") },
            "Slowing flight only required when cadence cannot fit overlap")
        return assertions
    }
}
