import Foundation

enum ControlScreen: String, CaseIterable, Identifiable {
    case dashboard, requests, mission, datasets, devices, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Ringkasan"
        case .requests: return "Permintaan"
        case .mission: return "Misi"
        case .datasets: return "Hasil"
        case .devices: return "Perangkat"
        case .settings: return "Pengaturan"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .requests: return "tray"
        case .mission: return "paperplane"
        case .datasets: return "photo.stack"
        case .devices: return "antenna.radiowaves.left.and.right"
        case .settings: return "gearshape"
        }
    }
}

enum DatasetFilter: String, CaseIterable, Identifiable {
    case all, attention, today, withPhotos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Semua misi"
        case .attention: return "Perlu diperiksa"
        case .today: return "Dibuat hari ini"
        case .withPhotos: return "Memiliki foto"
        }
    }
}
enum OperatorStage: String {
    case waiting, mission, connection, survey, camera, reference, test, review, ready, capture, results
    var title: String {
        switch self {
        case .waiting: return "Menunggu konfirmasi atau penyimpanan"
        case .mission: return "Buat misi pengambilan"
        case .connection: return "Hubungkan iPhone untuk melanjutkan persiapan"
        case .survey: return "Periksa rencana penerbangan"
        case .camera: return "Siapkan kamera"
        case .reference: return "Ukur kartu gray card sebelum terbang"
        case .test: return "Cari fokus dan ambil foto uji"
        case .review: return "Periksa foto asli dan kesiapan"
        case .ready: return "Siap memulai pengambilan foto"
        case .capture: return "Pengambilan mandiri di iPhone"
        case .results: return "Transfer dan periksa hasil misi"
        }
    }
}

extension CommandAction {
    var userTitle: String {
        switch self {
        case .createMission: return "Buat misi baru"
        case .prepare: return "Siapkan kamera"
        case .apply: return "Terapkan pengaturan"
        case .start: return "Mulai misi"
        case .pause: return "Jeda misi"
        case .resume: return "Lanjutkan misi"
        case .finish: return "Selesaikan misi"
        case .testCapture: return "Ambil foto uji"
        case .grayCard: return "Ukur white balance"
        case .grayCardReference: return "Ambil referensi gray card 18%"
        case .calibrationBefore: return "Simpan referensi sebelum"
        case .calibrationAfter: return "Simpan referensi sesudah"
        case .list: return "Perbarui dataset"
        case .download: return "Unduh dataset"
        }
    }
}
