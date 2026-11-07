import Foundation

/// Standard Operating Procedure (SOP) pre-flight checklist items that the drone operator
/// must verify and check before "Rencana sudah diperiksa" can be enabled.
///
/// State for these items is strictly transient in-memory and never persisted to disk.
/// Any modification to flight, boundary, or geofence parameters revokes all checked items.
enum PreflightChecklistItem: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case boundaryConfirmed
    case dronePlacedAtTakeoff
    case geofenceConfigured
    case geofenceCoversMission
    case geofenceCeilingSet
    case takeoffAreaClear
    case altitudeSafeForContour
    case weatherAndWindSafe
    case gnssAndCompassReady
    case batterySufficient
    case cameraAndStorageReady

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boundaryConfirmed:
            return "1. Batas lahan sudah dikonfirmasi"
        case .dronePlacedAtTakeoff:
            return "2. Drone sudah ditempatkan di tempat lepas landas"
        case .geofenceConfigured:
            return "3. Geofence sudah di-set"
        case .geofenceCoversMission:
            return "4. Luas geofence mencakup seluruh area misi scanning"
        case .geofenceCeilingSet:
            return "5. Geofence sudah di-set untuk ketinggian (Ceiling) yang sesuai"
        case .takeoffAreaClear:
            return "6. Area lepas landas sudah clear dan diperiksa keamanannya"
        case .altitudeSafeForContour:
            return "7. Ketinggian terbang aman dan sesuai kontur lahan"
        case .weatherAndWindSafe:
            return "8. Kondisi cuaca cerah & kecepatan angin aman (< 8 m/s)"
        case .gnssAndCompassReady:
            return "9. Sinyal GNSS/GPS terkunci & kompas bebas interferensi"
        case .batterySufficient:
            return "10. Daya baterai drone & remote mencukupi durasi misi"
        case .cameraAndStorageReady:
            return "11. Kamera & penyimpanan siap untuk seluruh foto misi"
        }
    }

    func subtitle(route: FlightRoute) -> String {
        switch self {
        case .boundaryConfirmed:
            return "Titik batas kebun sesuai kondisi fisik di lapangan."
        case .dronePlacedAtTakeoff:
            if let home = route.home, home.isValid {
                return "Posisi fisik drone sesuai titik Home (H) di peta."
            } else {
                return "Taruh titik Home (H) di peta sesuai lokasi fisik lepas landas."
            }
        case .geofenceConfigured:
            if let safety = route.safetyResult, safety.enabled {
                return "Tipe \(safety.type.title.lowercased()) · aksi: \(safety.breachAction.title)."
            }
            return "Aktifkan geofence dan hitung jalur di mesin QGC."
        case .geofenceCoversMission:
            if let safety = route.safetyResult, safety.enabled {
                return safety.coversMission
                    ? "Seluruh lintasan, manuver putar balik, dan Home berada di dalam geofence."
                    : "Perbesar buffer/radius geofence hingga mencakup seluruh jalur."
            }
            return "Menunggu evaluasi cakupan geofence dari mesin QGC."
        case .geofenceCeilingSet:
            if let safety = route.safetyResult, safety.enabled {
                return String(
                    format: "Tinggi terbang %.0f m · batas atas (Ceiling) %.0f m.",
                    route.defaultAltitude,
                    safety.ceilingMeters
                )
            }
            return "Pastikan batas atas ketinggian (Ceiling) di atas tinggi terbang."
        case .takeoffAreaClear:
            return "Bebas dari orang, kendaraan, kabel, dan pelepah pohon sawit."
        case .altitudeSafeForContour:
            return String(
                format: "Tinggi %.0f m AGL aman di atas tajuk pohon sawit dan kontur tanah.",
                route.defaultAltitude
            )
        case .weatherAndWindSafe:
            return "Tidak hujan, jarak pandang jelas, dan hembusan angin stabil."
        case .gnssAndCompassReady:
            return "Satelit memadai dan lokasi lepas landas jauh dari logam besar."
        case .batterySufficient:
            if let stats = route.surveyStatistics, stats.flightTimeSeconds > 0 {
                let mins = Int((stats.flightTimeSeconds / 60.0).rounded(.up))
                return "Cukup untuk estimasi terbang ~\(max(1, mins)) menit beserta cadangan RTL."
            }
            return "Pastikan baterai utama dan remote terisi penuh."
        case .cameraAndStorageReady:
            if let stats = route.surveyStatistics, stats.photoCount > 0 {
                return "Lensa bersih & ruang simpan cukup untuk \(stats.photoCount) foto."
            }
            return "Lensa bersih dan ruang penyimpanan mencukupi."
        }
    }

    /// Evaluates whether the QGC engine and planning state satisfy the prerequisite for this item.
    func precondition(isAreaConfirmed: Bool, route: FlightRoute) -> (met: Bool, blockerReason: String?) {
        let hasSurveyCalculation = !route.visualTransects.isEmpty && route.surveyStatistics != nil

        switch self {
        case .boundaryConfirmed:
            guard isAreaConfirmed else {
                return (false, "Konfirmasi batas area kebun terlebih dahulu.")
            }
            return (true, nil)

        case .dronePlacedAtTakeoff:
            guard let home = route.home, home.isValid else {
                return (false, "Taruh titik Home (H) di peta terlebih dahulu.")
            }
            return (true, nil)

        case .geofenceConfigured:
            guard route.geofence.enabled else {
                return (false, "Aktifkan Geofence pada panel parameter terbang.")
            }
            guard let safety = route.safetyResult, safety.enabled else {
                return (false, "Hitung jalur survei untuk menerapkan Geofence di QGC.")
            }
            return (true, nil)

        case .geofenceCoversMission:
            guard let safety = route.safetyResult, safety.enabled else {
                return (false, "Aktifkan Geofence dan hitung jalur di QGC terlebih dahulu.")
            }
            guard safety.coversMission else {
                let msg =
                    safety.issues.first(where: { $0.code.contains("COVERAGE") || $0.code.contains("HOME") })?
                    .message
                    ?? "Geofence belum mencakup seluruh jalur terbang dan titik Home."
                return (false, msg)
            }
            return (true, nil)

        case .geofenceCeilingSet:
            guard let safety = route.safetyResult, safety.enabled else {
                return (false, "Aktifkan Geofence dan hitung jalur di QGC terlebih dahulu.")
            }
            guard safety.ceilingOk else {
                let msg =
                    safety.issues.first(where: { $0.code == "CEILING_EXCEEDED" })?.message
                    ?? "Tinggi terbang melebihi batas Ceiling geofence."
                return (false, msg)
            }
            return (true, nil)

        case .altitudeSafeForContour, .takeoffAreaClear, .weatherAndWindSafe, .gnssAndCompassReady,
            .batterySufficient, .cameraAndStorageReady:
            guard hasSurveyCalculation else {
                return (false, "Hitung jalur survei terlebih dahulu.")
            }
            return (true, nil)
        }
    }
}
