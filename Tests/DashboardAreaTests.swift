import Foundation

@main enum DashboardAreaTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "farm-area-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("area.geojson")
        let saved = folder.appendingPathComponent("saved.json")
        let polygon = """
            {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"Area uji"},"geometry":{"type":"Polygon","coordinates":[[[104.45,1.05],[104.452,1.05],[104.452,1.052],[104.45,1.052],[104.45,1.05]]]}}]}
            """
        try polygon.write(to: file, atomically: true, encoding: .utf8)
        let store = FarmAreaStore(url: saved)
        try store.importFile(file)
        precondition(
            store.areas.count == 1 && store.areas[0].name == "Area uji", "Valid named GeoJSON imported")
        precondition(
            abs(store.areas[0].points[0].latitude - 1.05) < 0.000001
                && abs(store.areas[0].points[0].longitude - 104.45) < 0.000001,
            "GeoJSON longitude/latitude order preserved")
        precondition(
            FarmAreaStore(url: saved).areas[0].id == store.areas[0].id,
            "Boundaries restored with stable identity")
        try "{\"type\":\"Point\",\"coordinates\":[104.45,1.05]}".write(
            to: file, atomically: true, encoding: .utf8)
        do {
            try store.importFile(file)
            preconditionFailure("Point must not become a field boundary")
        } catch {}
        precondition(
            store.areas.count == 1 && FarmAreaStore(url: saved).areas.count == 1,
            "Failed import preserves existing boundaries")
        let viewModel = FarmAreaViewModel(repository: FarmAreaStore(url: saved))
        precondition(
            viewModel.areas.count == 1 && viewModel.selectedArea == nil,
            "ViewModel restores repository snapshot without selecting a field")
        viewModel.importArea(.success(file))
        precondition(
            viewModel.error != nil && viewModel.areas.count == 1,
            "Invalid file preserves ViewModel areas and exposes the repository error")
        try polygon.write(to: file, atomically: true, encoding: .utf8)
        viewModel.importArea(.success(file))
        precondition(
            viewModel.error == nil && viewModel.areas.count == 2
                && viewModel.selectedArea == viewModel.areas.last?.id,
            "Successful import updates state and selects the added area")
        print("PASS: 7 boundary import and ViewModel checks")
    }
}
