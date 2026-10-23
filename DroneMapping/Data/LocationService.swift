import CoreLocation
import CoreMotion

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "mapping.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    var onSample: ((GeoSample?) -> Void)?
    var onAttitude: ((AttitudeSample?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .airborne
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: motionQueue) {
                [weak self] data, _ in
                guard let self, let data else { return }
                let sample = AttitudeSample.fromGravity(
                    x: data.gravity.x, y: data.gravity.y, z: data.gravity.z,
                    roll: data.attitude.roll, pitch: data.attitude.pitch, yaw: data.attitude.yaw)
                self.onAttitude?(sample)
            }
        }
    }

    func stop() {
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0 else { return }
        onSample?(
            GeoSample(
                latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                altitudeMSL: value.altitude, horizontalAccuracy: value.horizontalAccuracy,
                verticalAccuracy: value.verticalAccuracy, timestamp: value.timestamp))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            // Retain the most recent valid sample during brief GNSS sky-view interruptions.
            return
        }
        onSample?(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            onSample?(nil)
        default:
            break
        }
    }
}
