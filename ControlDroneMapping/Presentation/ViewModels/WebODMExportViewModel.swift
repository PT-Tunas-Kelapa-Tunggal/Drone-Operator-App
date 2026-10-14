import AppKit
import Combine
import Foundation

/// Owns export state and schedules image work away from the main queue.
final class WebODMExportViewModel: ObservableObject {
    let record: MissionRecord
    private let service: any WebODMExportService
    @Published private(set) var references: [ExportPhoto] = []
    @Published var referenceID: UUID?
    @Published private(set) var preview: RGBPreview?
    @Published var patch = GrayPatch()
    @Published var corrected = false
    @Published var confirmed = false
    @Published var overlap = false
    @Published private(set) var working = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var error: String?
    @Published private(set) var result: ExportResult?
    init(record: MissionRecord, service: any WebODMExportService) {
        self.record = record
        self.service = service
    }
    func invalidateResult() {
        result = nil
        error = nil
    }
    func movePatch(x: Double, y: Double) {
        guard !working else { return }
        patch.x = min(1 - patch.width, max(0, x - patch.width / 2))
        patch.y = min(1 - patch.height, max(0, y - patch.height / 2))
        confirmed = false
        result = nil
    }
    func openImages() {
        guard let result else { return }
        NSWorkspace.shared.open(result.folder.appendingPathComponent("Images"))
    }
    func load() {
        do {
            let photos = try service.photos(record.id)
            references = photos.filter { $0.capture.kind == "calibration-before" }
            referenceID = references.last?.id
            total = photos.filter { $0.capture.kind == "mapping" }.count
            loadPreview()
        } catch { self.error = error.localizedDescription }
    }
    func loadPreview() {
        confirmed = false
        result = nil
        patch = GrayPatch()
        preview = nil
        guard let photo = references.first(where: { $0.id == referenceID }) else { return }
        do {
            preview = try RGBPreview(url: photo.url)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func export() {
        guard !working, !corrected || (confirmed && referenceID != nil) else { return }
        let id = record.id
        let selected = corrected ? referenceID : nil
        let area = patch
        let checked = confirmed
        let useOverlap = corrected && overlap
        working = true
        completed = 0
        error = nil
        result = nil
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let output = try service.export(
                    id: id, referenceID: selected, patch: area, confirmed: checked, overlap: useOverlap
                ) { [self] done, count in
                    DispatchQueue.main.async { [self] in
                        completed = done
                        total = count
                    }
                }
                DispatchQueue.main.async { [self] in
                    result = output
                    working = false
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    self.error = error.localizedDescription
                    working = false
                }
            }
        }
    }
}
