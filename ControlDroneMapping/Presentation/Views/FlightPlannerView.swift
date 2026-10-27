import SwiftUI

struct FlightPlannerView: View {
    @ObservedObject var model: FlightPlannerViewModel
    @ObservedObject var farms: FarmAreaViewModel
    @ObservedObject var location: OperatorLocationViewModel
    var missionID: UUID? = nil
    var missionFarm: FarmArea? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var manualLatitude: Double?
    @State private var manualLongitude: Double?
    private var farm: FarmArea? { missionFarm ?? farms.areas.first { $0.id == model.draft.farmID } }
    private var visibleRoutes: [FlightRoute] { model.routes.filter { $0.missionID == missionID } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rute penerbangan").font(KropsTypography.pageTitle)
                    Text("Draft lokal → ekspor .plan → periksa di QGroundControl").font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !visibleRoutes.isEmpty {
                    Picker("Draft", selection: Binding(get: { model.draft.id }, set: { model.select($0) })) {
                        ForEach(visibleRoutes) { route in Text(route.name).tag(route.id) }
                    }.labelsHidden().frame(width: 200)
                }
                Button("Rute baru", systemImage: "plus") {
                    model.newRoute(
                        farm: farm, name: farm.map { "Rute " + $0.name } ?? "Rute baru",
                        altitude: model.draft.defaultAltitude, speed: model.draft.speed)
                }
                Button("Tutup") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            HStack(spacing: 0) {
                WaypointMap(
                    route: model.draft, farm: farm, operatorLocation: location.sample, mode: model.mode,
                    fitRequest: model.fitRequest, selectedWaypoint: $model.selectedWaypointID,
                    onClick: { model.mapClick($0) },
                    onMove: { model.moveWaypoint($0, to: $1) },
                    onHomeMove: { model.draft.home = $0 },
                    onEntryMove: { model.moveEntry(to: $0) }
                )
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 10) {
                        Picker("Mode peta", selection: $model.mode) {
                            ForEach(FlightMapEditMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.segmented).frame(width: 330)
                        Button {
                            model.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }.help("Urungkan perubahan terakhir").disabled(model.undoStack.isEmpty)
                        Button {
                            model.fitRoute()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }.help("Tampilkan seluruh rute")
                    }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(14)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(
                        model.mode == .home
                            ? "Klik lokasi lepas landas untuk menentukan Home."
                            : model.mode == .waypoint
                                ? "Klik peta untuk menambah waypoint berurutan."
                                : "Pilih atau geser waypoint untuk mengubah posisinya."
                    )
                    .font(.callout).padding(12).background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 10)
                    ).padding(14).padding(.bottom, 25)
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        configuration
                        Divider()
                        waypoints
                        Divider()
                        DisclosureGroup("Koordinat manual / tanpa citra peta") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(
                                    "Latitude", value: $manualLatitude,
                                    format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                                        .precision(.fractionLength(0...7)))
                                TextField(
                                    "Longitude", value: $manualLongitude,
                                    format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                                        .precision(.fractionLength(0...7)))
                                HStack {
                                    Button("Set home") {
                                        if let point = manualCoordinate {
                                            model.mode = .home
                                            model.mapClick(point)
                                        }
                                    }.disabled(manualCoordinate == nil)
                                    Button("Tambah WP") {
                                        if let point = manualCoordinate { model.addWaypoint(point) }
                                    }.disabled(manualCoordinate == nil)
                                }
                                Text(
                                    "Koordinat WGS84 memakai titik desimal (contoh 1.05, 104.45). Input manual tersedia jika citra peta belum termuat."
                                ).font(.caption).foregroundStyle(.secondary)
                            }.textFieldStyle(.roundedBorder).padding(.top, 8)
                        }
                        Toggle(
                            "Home, rute, tinggi, dan profil drone sudah saya periksa", isOn: $model.reviewed)
                        Text(
                            "Tinggi waypoint relatif terhadap home, bukan AGL. Elevasi medan, hambatan, kemampuan drone, dan pengaturan RTL tetap diperiksa di QGC."
                        ).font(.caption).foregroundStyle(.secondary)
                        if let error = model.error { Text(error).font(.callout).foregroundStyle(.orange) }
                    }.padding(20)
                }.frame(width: 340)
            }
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        String(
                            format: "%d waypoint • %.0f m rute", model.draft.waypoints.count,
                            model.draft.distance)
                    ).font(.callout.weight(.semibold))
                    Text(
                        model.exportedURL == nil
                            ? model.exportBlocker ?? "Draft tersimpan. Siap diekspor untuk pemeriksaan QGC."
                            : "File siap. QGC: Plan → Open, lalu pilih file .plan ini."
                    )
                    .font(.caption).foregroundStyle(
                        model.exportBlocker == nil ? Color.secondary : Color.orange
                    ).lineLimit(2)
                }
                Spacer()
                if model.exportedURL != nil {
                    Button("Lihat file") { model.revealExport() }
                    Text("Buka QGroundControl melalui panel Perangkat untuk setup drone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Ekspor .plan") { model.chooseExportDestination() }.kropsPrimaryAction(size: .large)
                    .disabled(model.exportBlocker != nil)
            }.padding(18).background(KropsStyle.surface)
        }.frame(width: 1180, height: 790).background(KropsStyle.canvas)
    }
    private var manualCoordinate: MapCoordinate? {
        guard let latitude = manualLatitude, let longitude = manualLongitude else { return nil }
        let point = MapCoordinate(latitude: latitude, longitude: longitude)
        return point.isValid ? point : nil
    }
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlField("Nama rute") {
                TextField("Nama", text: $model.draft.name).textFieldStyle(.roundedBorder)
            }
            Picker("Kebun", selection: $model.draft.farmID) {
                Text("Area manual").tag(Optional<UUID>.none)
                ForEach(farms.areas) { area in Text(area.name).tag(Optional(area.id)) }
            }.onChange(of: model.draft.farmID) { _, _ in model.fitRoute() }
            Picker("Profil multicopter", selection: $model.draft.firmware) {
                Text("Pilih firmware di QGC").tag(Optional<FlightFirmware>.none)
                ForEach(FlightFirmware.allCases) { firmware in Text(firmware.title).tag(Optional(firmware)) }
            }
            HStack {
                ControlField("Tinggi WP baru") { NumberField($model.draft.defaultAltitude, unit: "m") }
                ControlField("Kecepatan") { NumberField($model.draft.speed, unit: "m/s") }
            }
            Button("Samakan tinggi semua waypoint") { model.applyAltitudeToAll() }.disabled(
                model.draft.waypoints.isEmpty)
            VStack(alignment: .leading, spacing: 8) {
                Text("Home · lokasi lepas landas").font(.headline)
                if let home = model.draft.home {
                    Text(String(format: "%.6f, %.6f", home.latitude, home.longitude)).font(
                        .caption.monospacedDigit())
                } else {
                    Text("Pilih Home, lalu klik peta.").font(.callout).foregroundStyle(.orange)
                }
                ControlField("Elevasi home (AMSL)") {
                    HStack {
                        TextField(
                            "Belum diketahui", value: $model.draft.homeAltitudeAMSL,
                            format: .number.precision(.fractionLength(0...1))
                        ).textFieldStyle(.roundedBorder)
                        Text("m").foregroundStyle(.secondary)
                    }
                }
                Text("Isi dari data lapangan/QGC. Lokasi Mac tidak mengisi elevasi home drone.").font(
                    .caption
                ).foregroundStyle(.secondary)
            }
            DisclosureGroup("Takeoff dan akhir rute") {
                VStack(alignment: .leading, spacing: 12) {
                    ControlField("Takeoff relatif home") {
                        NumberField($model.draft.takeoffAltitude, unit: "m")
                    }
                    Toggle("Return to home (RTL) di akhir", isOn: $model.draft.returnToHome)
                    Text("Perilaku dan tinggi RTL mengikuti konfigurasi autopilot di QGC.").font(.caption)
                        .foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }
    }
    private var waypoints: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Urutan waypoint").font(.headline)
            if model.draft.waypoints.isEmpty {
                Text("Set home, lalu tambahkan titik pada peta.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(model.draft.waypoints.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 6) {
                    Button {
                        model.selectedWaypointID = point.id
                        model.mode = .inspect
                    } label: {
                        Text("WP \(index + 1)").font(.callout.weight(.semibold)).frame(
                            maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Text(String(format: "%.0f m", point.altitude)).font(.caption.monospacedDigit())
                    Button {
                        model.reorder(point.id, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }.help("Pindahkan ke urutan sebelumnya").disabled(index == 0)
                    Button {
                        model.reorder(point.id, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }.help("Pindahkan ke urutan berikutnya").disabled(
                        index == model.draft.waypoints.count - 1)
                    Button {
                        model.removeWaypoint(point.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }.help("Hapus waypoint; dapat diurungkan")
                }.padding(8).background(
                    model.selectedWaypointID == point.id ? KropsStyle.accent.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
            }
            if let selected = model.selectedWaypoint {
                VStack(spacing: 10) {
                    TextField(
                        "Latitude",
                        value: Binding(
                            get: {
                                model.selectedWaypoint?.coordinate.latitude ?? selected.coordinate.latitude
                            },
                            set: { value in
                                var coordinate = selected.coordinate
                                coordinate.longitude =
                                    model.selectedWaypoint?.coordinate.longitude ?? coordinate.longitude
                                coordinate.latitude = value
                                model.moveWaypoint(selected.id, to: coordinate)
                            }),
                        format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(
                            .fractionLength(0...7)))
                    TextField(
                        "Longitude",
                        value: Binding(
                            get: {
                                model.selectedWaypoint?.coordinate.longitude ?? selected.coordinate.longitude
                            },
                            set: { value in
                                var coordinate = selected.coordinate
                                coordinate.latitude =
                                    model.selectedWaypoint?.coordinate.latitude ?? coordinate.latitude
                                coordinate.longitude = value
                                model.moveWaypoint(selected.id, to: coordinate)
                            }),
                        format: .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(
                            .fractionLength(0...7)))
                    NumberField(
                        Binding(
                            get: { model.selectedWaypoint?.altitude ?? selected.altitude },
                            set: { model.updateAltitude(selected.id, to: $0) }), unit: "m relatif home")
                }.textFieldStyle(.roundedBorder)
            }
        }
    }
}
