import Foundation

struct CameraDependencies {
    let link: LocalLink
    let viewModel: CameraViewModel
    init() {
        let repository = DatasetStore()
        let engine = CameraEngine(store: repository)
        let link = LocalLink(camera: true, store: repository)
        self.link = link
        viewModel = CameraViewModel(engine: engine, transport: link)
    }
}
