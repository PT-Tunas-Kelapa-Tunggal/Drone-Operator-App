import Combine
import Foundation

final class OperatorLocationViewModel: ObservableObject {
    @Published private(set) var state: OperatorLocationState = .idle
    @Published private(set) var focusRequest = UUID()
    private let service: any OperatorLocationProviding
    private var expiry: Timer?
    init(service: any OperatorLocationProviding) {
        self.service = service
        service.onUpdate = { [weak self] state in
            guard let self else { return }
            self.expiry?.invalidate()
            self.state = state
            if case .available(let sample) = state, sample.isUsable() {
                self.focusRequest = UUID()
                self.expiry = Timer.scheduledTimer(
                    withTimeInterval: max(0.01, 120 - Date().timeIntervalSince(sample.timestamp) + 0.01),
                    repeats: false
                ) { [weak self] _ in self?.expire() }
            }
        }
    }
    deinit { expiry?.invalidate() }
    func expire(now: Date = Date()) {
        guard case .available(let sample) = state, !sample.isUsable(now: now) else { return }
        state = .unavailable("Lokasi Mac sudah lama. Perbarui lokasi.")
    }
    var sample: OperatorLocationSample? {
        guard case .available(let sample) = state, sample.isUsable() else { return nil }
        return sample
    }
    var status: String {
        switch state {
        case .idle: return "Lokasi Mac belum digunakan"
        case .locating: return "Mencari lokasi Mac…"
        case .denied:
            return
                "Izin lokasi ditolak. Aktifkan Krops di Pengaturan Sistem → Privasi & Keamanan → Layanan Lokasi."
        case .unavailable(let message): return message
        case .available(let sample):
            return sample.isUsable()
                ? String(format: "Lokasi Mac • akurasi ±%.0f m", sample.accuracy)
                : "Lokasi Mac sudah lama. Perbarui lokasi."
        }
    }
    func request() { service.request() }
}
