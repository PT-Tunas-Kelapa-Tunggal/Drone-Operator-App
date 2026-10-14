import Foundation

struct DevicePanelFlowTests {
    static func run() -> Int {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let model = ControlViewModel(demo: true)
        model.createMission(name: "Persiapan di Perangkat")
        let mission = model.selectedMissionID!
        model.openMission(mission)
        check(
            !model.iphoneReadyForCapture && model.iphoneCaptureStatus == "iPhone terputus",
            "Offline mission exposes an honest readiness indicator")
        model.performNextStep()
        check(
            model.step == .devices && model.pending == nil && !model.selectedMission!.preparationRequested,
            "Mission guidance opens Devices without starting setup")
        model.connectDemo()
        check(
            model.telemetry.missionID == nil && !model.iphoneReadyForCapture,
            "Connected camera is not labelled capture-ready before mission preparation")
        model.geometry.reviewed = true
        model.selectMissionForDeviceSetup(mission)
        model.prepareSelectedMission()
        check(
            model.step == .devices && model.selectedMissionIsCurrent && !model.hasLocalDraft
                && model.geometry.reviewed,
            "Preparing and acknowledging a mission keeps the operator in Devices")
        model.geometry.reviewed = true
        model.openMission(mission)
        model.performNextStep()
        check(
            model.step == .devices && !model.settingsApplied,
            "Camera setup requested from mission guidance routes to Devices before sending commands")
        model.performNextStep()
        model.performNextStep()
        model.performNextStep()
        check(
            model.settingsApplied && model.referenceSaved && model.sample != nil
                && !model.iphoneReadyForCapture,
            "Camera/reference/test preparation does not bypass the human field checks")
        model.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true,
            endurance: true, controlPoints: true)
        check(
            model.iphoneReadyForCapture && model.iphoneCaptureStatus == "iPhone siap capture",
            "Only a fully reviewed prepared mission gets the ready indicator")
        let sample = model.sample?.captureID
        model.openMission(mission)
        check(
            model.step == .mission && model.iphoneReadyForCapture && model.sample?.captureID == sample,
            "Returning to the same mission preserves preparation and permits capture")
        model.navigate(.devices)
        model.selectMissionForDeviceSetup(mission)
        check(
            model.iphoneReadyForCapture && model.review.complete,
            "Opening Devices again cannot erase a valid calibration and review")
        model.lastReceived = Date().addingTimeInterval(-7)
        check(
            !model.iphoneReadyForCapture && model.iphoneCaptureStatus == "iPhone · menunggu status",
            "Stale telemetry removes the ready indicator")
        model.lastReceived = Date()
        model.link.connected = false
        check(!model.iphoneReadyForCapture, "Disconnect prevents a ready claim and starting capture")
        model.link.connected = true
        model.openMission(mission)
        model.send(.start)
        check(
            model.telemetry.phase == .capturing && !model.iphoneReadyForCapture,
            "Mission capture starts after device preparation and exits the ready state")
        model.send(.finish)
        model.createMission(name: "Misi berikutnya")
        model.selectMissionForDeviceSetup(model.selectedMissionID!)
        check(
            !model.iphoneReadyForCapture && model.sample == nil && !model.review.complete,
            "A new mission cannot inherit another mission's device-ready state")
        return checks
    }
}
