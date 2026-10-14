import CoreLocation

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onSample: ((GeoSample?) -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { return }
        onSample?(
            GeoSample(
                latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                altitudeMSL: value.altitude, horizontalAccuracy: value.horizontalAccuracy,
                verticalAccuracy: value.verticalAccuracy, timestamp: value.timestamp))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { onSample?(nil) }
}
