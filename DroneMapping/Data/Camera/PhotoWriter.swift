import AVFoundation
import Foundation
import ImageIO
import UIKit

// A capture is published only after all image callbacks and metadata writes succeed.
final class PhotoWriter: NSObject, AVCapturePhotoCaptureDelegate {
    private let queue = DispatchQueue(label: "mapping.photo-writer", qos: .utility)
    private let store: any DatasetRepository
    private let mission: MissionRecord
    private let sequence: Int
    private let settings: CameraSettings
    private let validLocation: GeoSample?
    private let validLocationAge: Double?
    private let attitude: AttitudeSample?
    private let kind: String
    private let referenceCommandID: UUID?
    private let requestedAt = Date()
    private let id = UUID()
    private var files: [String] = []
    private var hashes: [String: String] = [:]
    private var hostTime = 0.0
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var capturedExposure: CapturedExposure?
    private var storedBytes: Int64 = 0
    private var width = 0
    private var height = 0
    private var failure: Error?
    private let completion: (Result<CapturePreview?, Error>) -> Void
    private var staging: URL {
        store.directory(mission.id).appendingPathComponent(".\(id.uuidString).pending")
    }
    init(
        mission: MissionRecord, sequence: Int, settings: CameraSettings, location: GeoSample?,
        attitude: AttitudeSample? = nil, kind: String, referenceCommandID: UUID?,
        store: any DatasetRepository,
        completion: @escaping (Result<CapturePreview?, Error>) -> Void
    ) {
        self.mission = mission
        self.sequence = sequence
        self.settings = settings
        self.attitude = attitude
        self.kind = kind
        self.referenceCommandID = referenceCommandID
        self.store = store
        self.completion = completion
        let now = requestedAt
        if let sample = location {
            let age = GeoSample.normalizedAge(requestedAt: now, sampleTimestamp: sample.timestamp)
            if sample.horizontalAccuracy >= 0, (0...10).contains(age) {
                self.validLocation = sample
                self.validLocationAge = age
            } else {
                self.validLocation = nil
                self.validLocationAge = nil
            }
        } else {
            self.validLocation = nil
            self.validLocationAge = nil
        }
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        queue.async {
            do {
                if let error { throw error }
                guard let rawData = photo.fileDataRepresentation() else {
                    throw MappingError.invalid("Data foto kosong")
                }
                let data =
                    (!photo.isRawPhoto && self.validLocation != nil)
                    ? self.validLocation!.embeddingEXIF(into: rawData) : rawData
                try FileManager.default.createDirectory(at: self.staging, withIntermediateDirectories: true)
                let name = photo.isRawPhoto ? "image.dng" : "image.jpg"
                try data.write(to: self.staging.appendingPathComponent(name), options: .atomic)
                var metaDict = photo.metadata
                if let geo = self.validLocation {
                    metaDict[kCGImagePropertyGPSDictionary as String] = geo.gpsMetadataDictionary
                }
                let metadata = try PropertyListSerialization.data(
                    fromPropertyList: metaDict, format: .xml, options: 0)
                try metadata.write(
                    to: self.staging.appendingPathComponent(name + ".metadata.plist"), options: .atomic)
                self.storedBytes += Int64(data.count + metadata.count)
                if !photo.isRawPhoto { self.capturedExposure = CapturedExposure(metadata: metaDict) }
                self.files.append(name)
                self.hashes[name] = DatasetStore.hash(data)
                self.hostTime = photo.timestamp.seconds
                if !photo.isRawPhoto {
                    self.width = Int(photo.resolvedSettings.photoDimensions.width)
                    self.height = Int(photo.resolvedSettings.photoDimensions.height)
                }
            } catch { self.failure = error }
        }
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        queue.async {
            do {
                if let error = error ?? self.failure { throw error }
                guard self.files.count == (self.settings.raw ? 2 : 1) else {
                    throw MappingError.invalid("Capture tidak lengkap")
                }
                let record = CaptureRecord(
                    id: self.id, missionID: self.mission.id,
                    sequence: self.sequence, kind: self.kind, requestedAt: self.requestedAt,
                    photoHostTimeSeconds: self.hostTime, settings: self.settings,
                    location: self.validLocation, locationAgeAtRequest: self.validLocationAge,
                    attitude: self.attitude, files: self.files, sha256: self.hashes)
                try self.store.encode(record).write(
                    to: self.staging.appendingPathComponent("capture.json"), options: .atomic)
                let committed = try self.store.commit(staging: self.staging, capture: record)
                let elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
                var preview: CapturePreview?
                if self.kind != "mapping" {
                    let url = self.store.directory(self.mission.id).appendingPathComponent(
                        committed.files.first(where: { $0.hasSuffix(".jpg") }) ?? "")
                    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                        let thumb = CGImageSourceCreateThumbnailAtIndex(
                            source, 0,
                            [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceThumbnailMaxPixelSize: 1200,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                            ] as CFDictionary),
                        let data = UIImage(cgImage: thumb).jpegData(compressionQuality: 0.75),
                        data.count < 500_000
                    {
                        preview = CapturePreview(
                            captureID: self.id, missionID: self.mission.id, kind: self.kind,
                            settings: self.settings, imageData: data, captureSeconds: elapsed,
                            savedAt: Date(), width: self.width, height: self.height,
                            referenceCommandID: self.referenceCommandID,
                            assessment: PreviewAssessment.image(data),
                            sharpness: self.kind == "quality-test" ? SharpnessAssessment.image(at: url) : nil,
                            actualExposure: self.capturedExposure, storedBytes: self.storedBytes)
                    }
                }
                self.completion(.success(preview))
            } catch { self.completion(.failure(error)) }
        }
    }
}
