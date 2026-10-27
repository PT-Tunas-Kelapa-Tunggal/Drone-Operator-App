import Foundation

struct ControlDependencies {
    let link: LocalLink
    let viewModel: ControlViewModel
    let farms: FarmAreaViewModel
    let location: OperatorLocationViewModel
    let planner: FlightPlannerViewModel
    let reviews: any OperatorReviewRepository

    init(demo: Bool) {
        farms = FarmAreaViewModel(repository: FarmAreaStore())
        location = OperatorLocationViewModel(service: MacLocationService())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl")
        let waypointGenerator: any WaypointGenerator = demo
            ? MockWaypointGenerator()
            : QGCWaypointGenerator(baseURL: BundledQGCEngine.baseURL)
        planner = FlightPlannerViewModel(
            repository: InMemoryFlightRouteRepository(),
            waypointGenerator: waypointGenerator
        )
        let repository = DatasetStore()
        let link = LocalLink(camera: false, enabled: !demo, store: repository)
        self.link = link
        let reviewRepository: any OperatorReviewRepository = demo
            ? InMemoryOperatorReviewRepository()
            : CloudKitOperatorReviewRepository.shared
        self.reviews = reviewRepository
        viewModel = ControlViewModel(
            demo: demo, transport: link,
            drafts: FileMissionDraftRepository(url: demo ? nil : FileMissionDraftRepository.defaultURL),
            missions: FileMissionLibraryRepository(
                url: support.appendingPathComponent(demo ? "demo-missions.json" : "missions.json")),
            reviewRepository: reviewRepository)
    }
    static func exportViewModel(record: MissionRecord, store: any DatasetRepository) -> WebODMExportViewModel
    {
        WebODMExportViewModel(record: record, service: WebODMExporter(store: store))
    }
    static func orthomosaicViewModel(store: any DatasetRepository, demo: Bool) -> OrthomosaicViewModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl")
        return OrthomosaicViewModel(
            repository: FileOrthomosaicRepository(
                root: support.appendingPathComponent(demo ? "DemoOrthomosaics" : "Orthomosaics")),
            service: LocalOrthomosaicProcessor(
                worker: Bundle.main.url(forResource: "orthomosaic_worker", withExtension: "py")
                    ?? support.appendingPathComponent("missing-orthomosaic-worker.py")),
            datasets: store, runtimeAccess: OrthomosaicRuntimeAccess(defaults: .standard),
            installer: LocalOrthomosaicEngineInstaller(
                directory: LocalOrthomosaicEngineInstaller.defaultDirectory))
    }
}
