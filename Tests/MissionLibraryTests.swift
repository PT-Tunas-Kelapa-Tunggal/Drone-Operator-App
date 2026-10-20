import Foundation

struct MissionLibraryTests {
    static func run() -> Int {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "missions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("missions.json")
        let journal = folder.appendingPathComponent("pending.json")
        let repository = FileMissionLibraryRepository(url: url)
        let model = ControlViewModel(demo: true, draftURL: journal, missions: repository)
        model.createMission(name: "Kebun A")
        let first = model.selectedMissionID!
        check(
            model.step == .dashboard && model.savedMissions().count == 1 && model.pending == nil,
            "Creation appears in dashboard without navigation or device commands")
        model.openMission(first)
        let area = FarmArea(
            name: "Batas A",
            points: [
                .init(latitude: -6, longitude: 106), .init(latitude: -6.001, longitude: 106),
                .init(latitude: -6, longitude: 106.001),
            ])
        model.setMissionArea(area)
        model.geometry.heightAGL = 72
        model.plan.camera.iso = 160
        model.createMission(name: "Kebun B")
        let second = model.selectedMissionID!
        check(
            model.savedMissions().count == 2 && model.selectedMission?.area == nil
                && model.geometry.heightAGL != 72,
            "Each new mission has independent area and survey configuration")
        model.geometry.heightAGL = 93
        model.openMission(first)
        check(
            model.selectedMission?.area == area && model.geometry.heightAGL == 72
                && model.plan.camera.iso == 160,
            "Switching missions restores the selected area's own settings")
        model.renameMission(first, name: "  Kebun Utara  ")
        check(
            model.plan.name == "Kebun Utara" && model.savedMissions(search: "utara").map(\.id) == [first],
            "Rename and mission search use the persisted library")
        model.renameMission(first, name: " ")
        check(model.selectedMission?.plan.name == "Kebun Utara", "Invalid rename preserves existing name")
        let reopened = ControlViewModel(demo: true, draftURL: journal, missions: repository)
        check(
            reopened.savedMissions().count == 2 && !reopened.hasMissionDetail,
            "Restart restores the full mission library and opens the dashboard")
        reopened.openMission(first)
        check(
            reopened.selectedMission?.area == area && reopened.geometry.heightAGL == 72,
            "Area and survey edits survive a new app instance")
        reopened.connectDemo()
        check(
            reopened.telemetry.missionID == nil && reopened.pending == nil,
            "Connecting a camera cannot automatically prepare an unrequested mission")
        reopened.prepareSelectedMission()
        let remoteID = reopened.telemetry.missionID!
        check(
            reopened.selectedMission?.remoteID == remoteID && reopened.savedMissions().count == 2,
            "Camera ACK keeps the original mission identity without duplicate cards")
        reopened.geometry.heightAGL = 78
        let afterACK = ControlViewModel(demo: true, draftURL: journal, missions: repository)
        afterACK.openMission(first)
        check(
            afterACK.selectedMission?.remoteID == remoteID && afterACK.geometry.heightAGL == 78,
            "Acknowledged missions and later edits remain saved across restart")
        afterACK.deleteMission(first) { _ in
            throw MappingError.invalid("Simulated cleanup failure")
        }
        check(afterACK.savedMissions().contains { $0.id == first }, "Failed cleanup retains the mission for retry")
        check(afterACK.missionLibrary.deletedFileIDs?.contains(remoteID) == true,
              "Deletion intent survives a cleanup failure")
        afterACK.deleteMission(first)
        check(afterACK.savedMissions().map(\.id) == [second], "Delete removes only the chosen mission")
        var remote = MissionRecord(id: remoteID, plan: MissionPlan())
        remote.phase = .completed
        afterACK.link.onPacket?(Packet(missions: [remote]))
        check(
            afterACK.savedMissions().map(\.id) == [second] && !afterACK.records.contains { $0.id == remoteID },
            "Deleted missions and datasets remain hidden after reconnect")
        let final = ControlViewModel(demo: true, draftURL: journal, missions: repository)
        final.openMission(second)
        check(
            final.savedMissions().count == 1 && final.geometry.heightAGL == 93,
            "Deletion and the untouched second mission survive restart")
        check(
            final.savedMissions(filter: .today).count == 1
                && final.savedMissions(filter: .attention).count == 1,
            "Mission metrics include locally saved missions with no datasets")
        let active = final.selectedMissionID!
        final.connectDemo()
        final.prepareSelectedMission()
        var status = final.telemetry
        status.phase = .capturing
        final.link.onPacket?(Packet(telemetry: status))
        final.showMissionList()
        final.openMission(active)
        check(
            final.hasMissionDetail && final.selectedMissionIsCurrent,
            "The running mission remains accessible for monitoring from the mission list")
        final.deleteMission(active)
        check(final.savedMissions().count == 1, "An active mission cannot be deleted")
        status.phase = .ready
        final.link.onPacket?(Packet(telemetry: status))
        final.setMissionArea(area)
        final.setMissionArea(nil)
        check(try! repository.load().missions.first?.area == nil, "Area removal is persisted")
        let blockedDirectory = folder.appendingPathComponent("not-a-directory")
        try! Data("file".utf8).write(to: blockedDirectory)
        let unwritable = ControlViewModel(
            demo: true,
            missions: FileMissionLibraryRepository(
                url: blockedDirectory.appendingPathComponent("missions.json")))
        unwritable.createMission(name: "Write failure")
        check(
            unwritable.savedMissions().isEmpty && unwritable.missionStorageError != nil,
            "Creation cannot claim a saved mission when its repository fails to write")
        try! Data("broken".utf8).write(to: url)
        let broken = ControlViewModel(demo: true, draftURL: journal, missions: repository)
        broken.createMission(name: "Cannot overwrite unreadable library")
        check(
            broken.missionStorageError != nil && (try! String(contentsOf: url, encoding: .utf8)) == "broken",
            "An unreadable library reports failure and cannot overwrite existing storage")
        let store = DatasetStore(root: folder.appendingPathComponent("datasets"))
        let deletedID = UUID()
        let keptID = UUID()
        try! store.write(MissionRecord(id: deletedID, plan: MissionPlan()))
        try! store.write(MissionRecord(id: keptID, plan: MissionPlan()))
        let cache = store.directory(deletedID).appendingPathComponent("Exports/.pending")
        try! FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try! Data("cache".utf8).write(to: cache.appendingPathComponent("working.bin"))
        try! store.removeLocalMissionFiles([deletedID])
        try! store.removeLocalMissionFiles([deletedID])
        check(store.records().map(\.id) == [keptID], "Cleanup is idempotent and preserves unrelated datasets")
        check(!FileManager.default.fileExists(atPath: cache.path), "Cleanup removes nested cache and export files")
        return checks
    }
}
