import AVFoundation
import Foundation

/// Hardware boundary. Implementations own scheduling and deliver results on the main queue.
protocol CameraService: AnyObject {
    var session: AVCaptureSession { get }
    var onStatus: ((Telemetry) -> Void)? { get set }
    var onPreview: ((CapturePreview) -> Void)? { get set }
    func perform(_ command: Command, completion: @escaping (Result<String, Error>) -> Void)
    func startPrepared(_ plan: MissionPlan, completion: @escaping (Result<String, Error>) -> Void)
    func updateLocation(_ value: GeoSample?)
    func updateAttitude(_ value: AttitudeSample?)
    func health(battery: Float)
    func backgrounded()
}

extension CameraService {
    func updateAttitude(_ value: AttitudeSample?) {}
}
