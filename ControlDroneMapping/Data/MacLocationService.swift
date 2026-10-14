import CoreLocation

/// One-shot operator location. No background tracking, persistence or network transmission by this service.
final class MacLocationService: NSObject, CLLocationManagerDelegate, OperatorLocationProviding {
    var onUpdate: ((OperatorLocationState) -> Void)?
    private let manager = CLLocationManager()
    private var requested = false
    private var timeout: Timer?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func request() {
        requested = true
        guard CLLocationManager.locationServicesEnabled() else {
            onUpdate?(.unavailable("Layanan Lokasi Mac nonaktif."))
            return
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            timeout?.invalidate()
            onUpdate?(.denied)
        case .notDetermined:
            onUpdate?(.locating)
            manager.requestWhenInUseAuthorization()
        default:
            onUpdate?(.locating)
            locate()
        }
    }
    deinit { timeout?.invalidate() }
    private func locate() {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.onUpdate?(
                .unavailable("Lokasi belum tersedia. Periksa Wi-Fi atau gunakan peta secara manual."))
        }
        manager.requestLocation()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requested else { return }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            timeout?.invalidate()
            onUpdate?(.denied)
        case .authorizedAlways, .authorizedWhenInUse: locate()
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        timeout?.invalidate()
        guard let sample = locations.last else { return }
        let location = OperatorLocationSample(
            coordinate: MapCoordinate(
                latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude),
            accuracy: sample.horizontalAccuracy, timestamp: sample.timestamp)
        guard location.isUsable() else {
            onUpdate?(.unavailable("Lokasi yang diterima belum valid atau sudah lama. Coba lagi."))
            return
        }
        onUpdate?(.available(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        timeout?.invalidate()
        if (error as? CLError)?.code == .denied {
            onUpdate?(.denied)
        } else {
            onUpdate?(
                .unavailable("Lokasi belum tersedia. Periksa Wi-Fi dan Layanan Lokasi, lalu coba lagi."))
        }
    }
}
