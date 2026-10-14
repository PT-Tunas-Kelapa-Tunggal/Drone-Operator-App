import SwiftUI
import UniformTypeIdentifiers

struct MissionAreaView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var farms: FarmAreaViewModel
    var drawing: Bool
    var drawBoundary: () -> Void
    var fitArea: () -> Void
    @State private var importing = false
    @State private var latitude: Double?
    @State private var longitude: Double?
    private var area: FarmArea? { model.selectedMission?.area }
    private var locked: Bool { model.editingLocked || model.selectedMission?.preparationRequested == true }
    var body: some View {
        ControlPanel("Area scan misi ini", state: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text(area?.name ?? "Area belum diatur").font(.callout.bold())
                Text("\(area?.points.count ?? 0) titik batas").font(.caption).foregroundStyle(.secondary)
                HStack {
                    if !farms.areas.isEmpty {
                        Menu("Pilih kebun") {
                            ForEach(farms.areas) { farm in
                                Button(farm.name) {
                                    model.setMissionArea(farm)
                                    fitArea()
                                }
                            }
                        }.disabled(locked)
                    }
                    Button("Impor GeoJSON") { importing = true }.disabled(locked)
                    Button("Tampilkan") { fitArea() }.disabled(area == nil)
                }
                Button(drawing ? "Selesai gambar batas" : "Gambar batas di peta", action: drawBoundary)
                    .disabled(locked)
                Text(
                    drawing
                        ? "Klik peta di kanan mengikuti batas area. Minimal 3 titik; geser titik untuk mengedit."
                        : "Batas area dan waypoint dapat diatur langsung pada peta di kanan."
                )
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Hapus titik terakhir") {
                        guard var area, !area.points.isEmpty else { return }
                        area.points.removeLast()
                        model.setMissionArea(area.points.isEmpty ? nil : area)
                    }.disabled(locked || area?.points.isEmpty != false)
                    Button("Hapus area", role: .destructive) { model.setMissionArea(nil) }
                        .disabled(locked || area == nil)
                }
                if let area, area.points.count < 3 {
                    Text("Batas belum lengkap. Tambahkan minimal 3 titik.").font(.caption).foregroundStyle(
                        .orange)
                }
                DisclosureGroup("Koordinat manual") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            "Latitude", value: $latitude,
                            format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                                .precision(.fractionLength(0...7)))
                        TextField(
                            "Longitude", value: $longitude,
                            format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                                .precision(.fractionLength(0...7)))
                        Button("Tambah titik") {
                            if let latitude, let longitude {
                                addPoint(MapCoordinate(latitude: latitude, longitude: longitude))
                            }
                        }.disabled(locked || latitude == nil || longitude == nil)
                    }.textFieldStyle(.roundedBorder).padding(.top, 8)
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [UTType(filenameExtension: "geojson") ?? .json, .json]
        ) { result in
            farms.importArea(result)
            if let error = farms.error {
                model.errorMessage = error
            } else if let farm = farms.areas.first(where: { $0.id == farms.selectedArea }) {
                model.setMissionArea(farm)
                fitArea()
            }
        }
    }
    private func addPoint(_ point: MapCoordinate) {
        guard !locked, point.isValid else {
            model.errorMessage = "Koordinat area tidak valid."
            return
        }
        var updated = area ?? FarmArea(name: "Area " + model.plan.name, points: [])
        updated.points.append(FarmArea.Point(latitude: point.latitude, longitude: point.longitude))
        model.setMissionArea(updated)
    }
    private func movePoint(_ index: Int, _ coordinate: MapCoordinate) {
        guard !locked, coordinate.isValid, var updated = area, updated.points.indices.contains(index) else {
            return
        }
        updated.points[index] = FarmArea.Point(latitude: coordinate.latitude, longitude: coordinate.longitude)
        model.setMissionArea(updated)
    }
}
