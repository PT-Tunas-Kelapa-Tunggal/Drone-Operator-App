import Foundation

struct ControlDependencies {
    let link: LocalLink
    let viewModel: ControlViewModel
    let farms: FarmAreaViewModel
    let location: OperatorLocationViewModel
    let planner: FlightPlannerViewModel

    init(demo: Bool) {
        farms = FarmAreaViewModel(repository: FarmAreaStore())
        location = OperatorLocationViewModel(service: MacLocationService())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl")
        planner = FlightPlannerViewModel(
            repository: FileFlightRouteRepository(
                url: support.appendingPathComponent(demo ? "demo-flight-routes.json" : "flight-routes.json")))
        let repository = DatasetStore()
        let link = LocalLink(camera: false, enabled: !demo, store: repository)
        self.link = link
        viewModel = ControlViewModel(
            demo: demo, transport: link,
            drafts: FileMissionDraftRepository(url: demo ? nil : FileMissionDraftRepository.defaultURL),
            missions: FileMissionLibraryRepository(
                url: support.appendingPathComponent(demo ? "demo-missions.json" : "missions.json")))
    }
    static func exportViewModel(record: MissionRecord, store: any DatasetRepository) -> WebODMExportViewModel
    {
        WebODMExportViewModel(record: record, service: WebODMExporter(store: store))
    }
}
