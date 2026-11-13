import Foundation

struct ControlDependencies {
    let link: LocalLink
    let viewModel: ControlViewModel
    let farms: FarmAreaViewModel
    let location: OperatorLocationViewModel
    let planner: FlightPlannerViewModel
    let reviews: any OperatorReviewRepository
    let variProcessor: any VariProcessing
    let timingProcessor: any VariTimingProcessing

    private static func storageDirectory(under base: URL, demo: Bool) -> URL {
        guard !demo, let scope = AppConfiguration.bundleStorageScope else {
            return base
        }
        return scope.directory(under: base)
    }

    init(demo: Bool) {
        farms = FarmAreaViewModel(repository: FarmAreaStore())
        location = OperatorLocationViewModel(service: MacLocationService())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl", isDirectory: true)
        let scopedSupport = Self.storageDirectory(under: support, demo: demo)
        let documentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneMapping", isDirectory: true)
        let scopedDocuments = Self.storageDirectory(under: documentsRoot, demo: demo)
        let storageScope = demo ? nil : AppConfiguration.bundleStorageScope

        let waypointGenerator: any WaypointGenerator =
            demo
            ? MockWaypointGenerator()
            : QGCWaypointGenerator(baseURL: BundledQGCEngine.baseURL)
        planner = FlightPlannerViewModel(
            repository: FileFlightRouteRepository(
                url: scopedSupport.appendingPathComponent(demo ? "demo-flight-routes.json" : "flight-routes.json")
            ),
            trailRepository: FileFlightTrailRepository(
                url: scopedSupport.appendingPathComponent(demo ? "demo-flight-trails.json" : "flight-trails.json")
            ),
            waypointGenerator: waypointGenerator
        )
        let repository = DatasetStore(root: demo ? nil : scopedDocuments)
        let link = LocalLink(camera: false, enabled: !demo, store: repository)
        self.link = link
        let reviewRepository: any OperatorReviewRepository =
            demo
            ? InMemoryOperatorReviewRepository(initialRequests: InMemoryOperatorReviewRepository.demoRequests)
            : CloudKitOperatorReviewRepository.shared
        self.reviews = reviewRepository
        viewModel = ControlViewModel(
            demo: demo, transport: link,
            drafts: FileMissionDraftRepository(
                url: demo ? nil : scopedSupport.appendingPathComponent("mission-draft.json")),
            missions: FileMissionLibraryRepository(
                url: scopedSupport.appendingPathComponent(demo ? "demo-missions.json" : "missions.json")),
            reviewRepository: reviewRepository,
            storageScope: storageScope)
        self.variProcessor = demo ? MockVariProcessor() : LocalVariProcessor()
        self.timingProcessor = demo ? MockVariTimingProcessor() : LocalVariTimingProcessor()
    }

    static func exportViewModel(record: MissionRecord, store: any DatasetRepository) -> WebODMExportViewModel
    {
        WebODMExportViewModel(record: record, service: WebODMExporter(store: store))
    }

    static func orthomosaicViewModel(store: any DatasetRepository, demo: Bool) -> OrthomosaicViewModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroneControl", isDirectory: true)
        let scopedSupport = storageDirectory(under: support, demo: demo)
        return OrthomosaicViewModel(
            repository: FileOrthomosaicRepository(
                root: scopedSupport.appendingPathComponent(demo ? "DemoOrthomosaics" : "Orthomosaics")),
            service: LocalOrthomosaicProcessor(
                worker: Bundle.main.url(forResource: "orthomosaic_worker", withExtension: "py")
                    ?? support.appendingPathComponent("missing-orthomosaic-worker.py")),
            datasets: store, runtimeAccess: OrthomosaicRuntimeAccess(defaults: .standard),
            installer: LocalOrthomosaicEngineInstaller(
                directory: LocalOrthomosaicEngineInstaller.defaultDirectory))
    }

    static func variProcessor(demo: Bool) -> any VariProcessing {
        demo ? MockVariProcessor() : LocalVariProcessor()
    }

    static func timingProcessor(demo: Bool) -> any VariTimingProcessing {
        demo ? MockVariTimingProcessor() : LocalVariTimingProcessor()
    }
}
