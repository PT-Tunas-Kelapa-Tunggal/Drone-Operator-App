import Foundation

struct OperatorFlowTests {
    static func run() -> Int {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        let model = ControlViewModel(demo: true)
        check(
            model.operatorStage == .mission,
            "First operator action is create mission; connection is not required")
        model.createMission(name: "Flow lapangan")
        model.openMission(model.selectedMissionID!)
        model.prepareSelectedMission()
        check(model.operatorStage == .connection, "Offline draft points to device setup")
        model.performNextStep()
        check(
            model.step == .devices && model.pending == nil,
            "Connection guidance does not send a camera or start command")
        model.connectDemo()
        check(model.operatorStage == .survey, "After sync, operator must confirm flight geometry")
        model.geometry.reviewed = true
        check(model.operatorStage == .camera, "Camera setup follows checked geometry")
        model.performNextStep()
        check(
            model.operatorStage == .reference && model.settingsApplied,
            "Guided camera acknowledgement moves to card reference")
        model.performNextStep()
        check(
            model.operatorStage == .test && model.referenceSaved,
            "Reference must be saved before test guidance")
        model.performNextStep()
        check(model.operatorStage == .review, "Test does not automatically approve human field checks")
        model.review = QualityReview(
            sharp: true, highlights: true, focus: true, mounted: true, endurance: true, controlPoints: true)
        check(model.operatorStage == .ready, "Ready stage requires all existing readiness checks")
        model.send(.start)
        let id = model.telemetry.missionID
        model.link.connected = false
        model.step = .dashboard
        check(
            model.operatorStage == .capture && model.telemetry.missionID == id,
            "Disconnect/navigation cannot reset capture or lose mission context")
        model.performNextStep()
        check(
            model.telemetry.phase == .capturing && model.pending == nil,
            "Next-step guidance never restarts capture after disconnect")

        var remote = MissionRecord(plan: MissionPlan())
        remote.plan.name = "Misi di udara"
        remote.plan.photoLimit = 777
        remote.plan.interval = 4
        remote.plan.survey = SurveyGeometry(heightAGL: 65)
        remote.phase = .capturing
        remote.saved = 12
        let monitor = ControlViewModel(demo: true)
        monitor.link.connected = true
        var status = Telemetry()
        status.missionID = remote.id
        status.phase = .capturing
        status.saved = 12
        monitor.link.onPacket?(Packet(telemetry: status, missions: [remote]))
        check(
            monitor.plan.name == remote.plan.name && monitor.plan.photoLimit == 777
                && monitor.geometry.heightAGL == 65, "Reopened Mac restores authoritative active mission plan"
        )
        check(
            monitor.recentRecords.isEmpty && monitor.operatorStage == .capture && monitor.pending == nil,
            "Active mission not duplicated in recent list and never restarted")
        status.saved = 13
        monitor.link.onPacket?(Packet(telemetry: status))
        check(
            monitor.records.first?.saved == 13,
            "Heartbeat updates dataset photo count even without a new manifest list")
        status.phase = .ready
        monitor.link.onPacket?(Packet(telemetry: status))
        monitor.plan.interval = 6
        monitor.link.onPacket?(Packet(telemetry: status, missions: [remote]))
        check(monitor.plan.interval == 6, "Same-mission reconnect does not erase operator draft edits")

        var old = MissionRecord(plan: MissionPlan())
        old.plan.name = "Kemarin"
        old.createdAt = Date().addingTimeInterval(-172800)
        old.phase = .completed
        old.saved = 40
        var failed = MissionRecord(plan: MissionPlan())
        failed.plan.name = "Perlu diperiksa"
        failed.phase = .failed
        monitor.records = [remote, old, failed]
        monitor.showDatasets(missionID: old.id)
        check(
            monitor.step == .datasets && monitor.filteredDatasets().map(\.id) == [old.id],
            "Clicking one dataset opens only the exact clicked mission")
        monitor.showDatasets(filter: .attention)
        check(
            monitor.filteredDatasets().map(\.id) == [failed.id],
            "Attention metric opens matching records rather than an unrelated live mission")
        monitor.showDatasets(filter: .today)
        check(
            monitor.filteredDatasets().count == 2
                && !monitor.filteredDatasets().contains(where: { $0.id == old.id }),
            "Today metric excludes older missions")
        monitor.showDatasets(filter: .withPhotos)
        check(monitor.filteredDatasets().count == 2, "Results metric excludes records with no mapping photos")
        monitor.showDatasets(missionID: old.id)
        monitor.navigate(.datasets)
        check(
            monitor.selectedDatasetID == nil && monitor.datasetFilter == .all
                && monitor.filteredDatasets().count == 3,
            "Sidebar returns to all results without a hidden selection filter")
        check(
            monitor.filteredDatasets(search: "tidak ditemukan").isEmpty,
            "No-result search has a distinct empty state")

        let draft = ControlViewModel(demo: true)
        draft.createMission(name: "Draft lokal")
        draft.openMission(draft.selectedMissionID!)
        draft.prepareSelectedMission()
        draft.link.connected = true
        status.phase = .capturing
        draft.link.onPacket?(Packet(telemetry: status, missions: [remote]))
        check(
            draft.monitoringPlan.name == remote.plan.name && draft.monitoringPlan.photoLimit == 777,
            "Monitoring uses the iPhone plan even while a different Mac draft exists")
        check(
            draft.hasLocalDraft && draft.plan.name == "Draft lokal" && draft.pending == nil,
            "Incoming live mission never replaces a named local draft or creates a new mission while flying")
        status.phase = .paused
        draft.link.onPacket?(Packet(telemetry: status, missions: [remote]))
        draft.send(.resume)
        check(
            draft.hasLocalDraft && draft.plan.name == "Draft lokal" && draft.telemetry.phase == .capturing,
            "A waiting local draft does not block explicit resume of the active iPhone mission")
        check(
            draft.monitoringPlan.name == remote.plan.name && draft.monitoringPlan.photoLimit == 777,
            "Resume uses authoritative flight plan, never local draft settings")
        draft.send(.finish)
        check(
            draft.hasLocalDraft && draft.telemetry.phase == .completed
                && draft.selectedDatasetID == remote.id,
            "Operator can finish the correct active mission while retaining a waiting draft")
        monitor.telemetry.phase = .capturing
        monitor.link.connected = false
        monitor.showDatasets(missionID: remote.id)
        monitor.send(.download, missionID: remote.id)
        check(
            monitor.telemetry.phase == .capturing && monitor.pending == nil,
            "Offline dataset action cannot stop autonomous capture")
        return checks
    }
}
