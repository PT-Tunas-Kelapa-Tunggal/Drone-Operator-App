import AVFoundation
import Combine
import Foundation
import ImageIO
import UIKit

final class TestOrtoCameraController: ObservableObject {
    let session = AVCaptureSession()
    let store: any DatasetRepository

    @Published var missionName = "TestOrto Lapangan"
    @Published var heightAGL: Double = 1.5
    @Published var speed: Double = 0.4
    @Published var forwardOverlap: Double = 0.80
    @Published var sideOverlap: Double = 0.75
    @Published var autoInterval: Double = 1.5
    @Published var useGuidedExposure = true
    @Published var cameraSettings = CameraSettings(
        iso: 100, shutterSeconds: 0.001, temperature: 5500, tint: 0, lensPosition: 0.85, raw: false
    )

    @Published private(set) var capabilities: CameraCapabilities?
    @Published private(set) var isSessionReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isAutoCapturing = false
    @Published private(set) var grayCardLocked = false
    @Published private(set) var focusAndExposureLocked = false
    @Published private(set) var activeMission: MissionRecord?
    @Published private(set) var savedMissions: [MissionRecord] = []
    @Published private(set) var currentLocation: GeoSample?
    @Published private(set) var currentAttitude: AttitudeSample?
    @Published private(set) var statusMessage = "Siapkan posisi jalan kaki, lalu tekan Take Gray Card atau TAKE."
    @Published private(set) var lastMappingThumbnail: UIImage?
    @Published private(set) var grayCardThumbnail: UIImage?
    @Published private(set) var lastAssessment: PreviewAssessment?
    @Published private(set) var lastSharpness: SharpnessAssessment?

    private let queue = DispatchQueue(label: "mapping.testorto.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let locations: LocationService
    private var device: AVCaptureDevice?
    private var pendingWriter: PhotoWriter?
    private var autoTimer: DispatchSourceTimer?
    private var currentLocationInternal: GeoSample?
    private var currentAttitudeInternal: AttitudeSample?

    init(
        store: any DatasetRepository = DatasetStore(),
        locations: LocationService = LocationService()
    ) {
        self.store = store
        self.locations = locations
        try? store.migrateLegacy()
        try? store.recoverInterrupted()
        savedMissions = store.records()

        locations.onSample = { [weak self] sample in
            guard let self else { return }
            self.queue.async { self.currentLocationInternal = sample }
            DispatchQueue.main.async { self.currentLocation = sample }
        }
        locations.onAttitude = { [weak self] attitude in
            guard let self else { return }
            self.queue.async { self.currentAttitudeInternal = attitude }
            DispatchQueue.main.async { self.currentAttitude = attitude }
        }
    }

    deinit {
        autoTimer?.cancel()
        locations.stop()
    }

    var overlayMetrics: TestOrtoOverlayMetrics? {
        TestOrtoOverlayMetrics.calculate(
            heightAGL: heightAGL,
            speed: speed,
            forwardOverlap: forwardOverlap,
            sideOverlap: sideOverlap,
            capabilities: capabilities
        )
    }

    func applyPreset(_ preset: TestOrtoPreset) {
        heightAGL = preset.heightAGL
        speed = preset.speed
        forwardOverlap = preset.forwardOverlap
        sideOverlap = preset.sideOverlap
        if let metrics = overlayMetrics {
            autoInterval = metrics.recommendedAutoInterval
            let targetShutter = min(0.001, max(0.000125, metrics.maximumShutterSeconds * 0.8))
            cameraSettings.shutterSeconds = targetShutter
        }
        statusMessage = "Preset \(preset.rawValue) diterapkan."
    }

    func applyRecommendedIntervalAndShutter() {
        guard let metrics = overlayMetrics else { return }
        autoInterval = metrics.recommendedAutoInterval
        let minShutter = capabilities?.minShutter ?? 0.00002
        let maxShutter = capabilities?.maxShutter ?? 0.1
        let recommendedShutter = min(0.001, metrics.maximumShutterSeconds * 0.8)
        cameraSettings.shutterSeconds = min(maxShutter, max(minShutter, recommendedShutter))
        statusMessage = String(
            format: "Interval %.1f dtk & shutter 1/%.0f diterapkan.",
            autoInterval, 1.0 / max(0.00001, cameraSettings.shutterSeconds)
        )
    }

    func activateCamera() {
        UIApplication.shared.isIdleTimerDisabled = true
        locations.start()
        queue.async {
            do {
                try self.prepareSessionIfNeeded()
                DispatchQueue.main.async {
                    self.isSessionReady = true
                    if self.activeMission == nil {
                        self.createFreshMissionOnMain(silent: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Kamera belum siap: \(error.localizedDescription)"
                }
            }
        }
    }

    func deactivateCamera() {
        stopAutoCapture()
        locations.stop()
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionReady = false
            }
        }
    }

    func startNewMission() {
        stopAutoCapture()
        if var previous = activeMission, previous.phase != .completed {
            previous.phase = .completed
            previous.note = previous.saved > 0
                ? "Misi TestOrto selesai (\(previous.saved) foto)"
                : "Ditutup saat membuat misi TestOrto baru"
            try? store.write(previous)
        }
        createFreshMissionOnMain(silent: false)
    }

    func finishCurrentMission() {
        stopAutoCapture()
        guard var mission = activeMission else { return }
        mission.phase = .completed
        mission.note = "Misi TestOrto selesai (\(mission.saved) foto pemetaan)"
        do {
            try store.write(mission)
            activeMission = mission
            savedMissions = store.records()
            statusMessage = "Misi selesai & tersimpan (\(mission.saved) foto)."
        } catch {
            statusMessage = "Gagal menyimpan misi: \(error.localizedDescription)"
        }
    }

    func deleteMission(_ id: UUID) {
        if activeMission?.id == id {
            stopAutoCapture()
            activeMission = nil
        }
        do {
            try store.removeLocalMissionFiles([id])
            savedMissions = store.records()
            statusMessage = "Dataset lokal dihapus."
        } catch {
            statusMessage = "Gagal menghapus dataset: \(error.localizedDescription)"
        }
    }

    func refreshMissions() {
        savedMissions = store.records()
    }

    func lockFocusAndExposure() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Mengukur fokus & exposure permukaan lapangan…"
        let preferredShutter = min(
            0.001,
            (overlayMetrics?.maximumShutterSeconds ?? 0.00125) * 0.8
        )
        let currentSettings = cameraSettings
        queue.async {
            do {
                try self.prepareSessionIfNeeded()
                guard let device = self.device else {
                    throw MappingError.invalid("Kamera tidak tersedia")
                }
                let caps = self.readCapabilities(device)
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()

                self.waitForAdjusting(device: device, timeout: 2.0) {
                    do {
                        let meteredISO = device.iso
                        let meteredShutter = max(caps.minShutter, device.exposureDuration.seconds)
                        let chosen = try GuidedAcquisition.exposure(
                            meteredISO: meteredISO,
                            meteredShutter: meteredShutter,
                            preferredShutter: max(caps.minShutter, min(caps.maxShutter, preferredShutter)),
                            minISO: caps.minISO,
                            maxISO: caps.maxISO,
                            minShutter: caps.minShutter
                        )
                        var updated = currentSettings
                        updated.iso = chosen.iso
                        updated.shutterSeconds = chosen.shutter
                        updated.lensPosition = min(1.0, max(0.0, device.lensPosition))
                        try self.lockHardware(device: device, settings: updated)
                        let focusCal = FocusCalibration(measuredAt: Date(), lensPosition: updated.lensPosition)
                        let expCal = ExposureCalibration(
                            measuredAt: Date(), meteredISO: meteredISO,
                            meteredShutter: meteredShutter, selectedISO: updated.iso,
                            selectedShutter: updated.shutterSeconds
                        )
                        DispatchQueue.main.async {
                            self.cameraSettings = updated
                            self.focusAndExposureLocked = true
                            self.isBusy = false
                            self.activeMission?.plan.focusCalibration = focusCal
                            self.activeMission?.plan.exposureCalibration = expCal
                            self.statusMessage = String(
                                format: "Terkunci: ISO %.0f • Shutter 1/%.0f • Fokus %.2f",
                                updated.iso, 1.0 / max(0.00001, updated.shutterSeconds), updated.lensPosition
                            )
                            self.syncActiveMissionSettings()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isBusy = false
                            self.statusMessage = error.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func applyManualSettings() {
        guard !isBusy else { return }
        isBusy = true
        let requested = cameraSettings
        queue.async {
            do {
                try self.prepareSessionIfNeeded()
                guard let device = self.device else {
                    throw MappingError.invalid("Kamera tidak tersedia")
                }
                try self.lockHardware(device: device, settings: requested)
                DispatchQueue.main.async {
                    self.focusAndExposureLocked = true
                    self.isBusy = false
                    self.statusMessage = "Parameter kamera manual dikunci."
                    self.syncActiveMissionSettings()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func takeGrayCard() {
        guard !isBusy else { return }
        if activeMission == nil || activeMission?.phase == .completed {
            createFreshMissionOnMain(silent: true)
        }
        guard let missionSnapshot = activeMission else { return }
        isBusy = true
        statusMessage = "Mengukur & menyimpan referensi Gray Card 18%…"
        let guided = useGuidedExposure
        let preferredShutter = min(
            0.001,
            (overlayMetrics?.maximumShutterSeconds ?? 0.00125) * 0.8
        )
        let baseSettings = cameraSettings

        queue.async {
            do {
                try self.prepareSessionIfNeeded()
                guard let device = self.device else {
                    throw MappingError.invalid("Kamera tidak tersedia")
                }
                let caps = self.readCapabilities(device)
                if guided {
                    try device.lockForConfiguration()
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    device.unlockForConfiguration()
                }

                self.waitForAdjusting(device: device, timeout: guided ? 1.8 : 0.2) {
                    do {
                        var updated = baseSettings
                        let gains = device.grayWorldDeviceWhiteBalanceGains
                        updated.whiteBalanceGains = [gains.redGain, gains.greenGain, gains.blueGain]
                        let wbValues = device.temperatureAndTintValues(for: gains)
                        updated.temperature = min(12000, max(2000, wbValues.temperature))
                        updated.tint = min(150, max(-150, wbValues.tint))

                        var exposureCalibration: ExposureCalibration?
                        if guided {
                            let meteredISO = device.iso
                            let meteredShutter = max(caps.minShutter, device.exposureDuration.seconds)
                            if let chosen = try? GuidedAcquisition.exposure(
                                meteredISO: meteredISO,
                                meteredShutter: meteredShutter,
                                preferredShutter: max(caps.minShutter, min(caps.maxShutter, preferredShutter)),
                                minISO: caps.minISO,
                                maxISO: caps.maxISO,
                                minShutter: caps.minShutter
                            ) {
                                updated.iso = chosen.iso
                                updated.shutterSeconds = chosen.shutter
                                exposureCalibration = ExposureCalibration(
                                    measuredAt: Date(), meteredISO: meteredISO,
                                    meteredShutter: meteredShutter, selectedISO: updated.iso,
                                    selectedShutter: updated.shutterSeconds
                                )
                            }
                        }

                        try self.lockHardware(device: device, settings: updated)
                        var updatedMission = missionSnapshot
                        updatedMission.plan.camera = updated
                        if let exposureCalibration {
                            updatedMission.plan.exposureCalibration = exposureCalibration
                        }
                        try self.store.write(updatedMission)

                        try self.captureOnQueue(
                            mission: updatedMission,
                            sequence: 0,
                            settings: updated,
                            kind: "calibration-before"
                        ) { result in
                            DispatchQueue.main.async {
                                self.isBusy = false
                                switch result {
                                case .success(let preview):
                                    self.cameraSettings = updated
                                    self.activeMission = updatedMission
                                    self.savedMissions = self.store.records()
                                    self.grayCardLocked = true
                                    self.focusAndExposureLocked = true
                                    if let data = preview?.imageData, let image = UIImage(data: data) {
                                        self.grayCardThumbnail = image
                                    }
                                    self.lastAssessment = preview?.assessment
                                    self.statusMessage =
                                        "Gray Card 18% tersimpan & warna dikunci (\(Int(updated.temperature))K)."
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                case .failure(let error):
                                    self.statusMessage = "Gagal menyimpan Gray Card: \(error.localizedDescription)"
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isBusy = false
                            self.statusMessage = error.localizedDescription
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func takePhoto() {
        guard !isBusy else { return }
        if activeMission == nil || activeMission?.phase == .completed {
            createFreshMissionOnMain(silent: true)
        }
        guard var missionSnapshot = activeMission else { return }
        isBusy = true
        let currentSettings = cameraSettings
        missionSnapshot.plan.camera = currentSettings
        let nextSequence = missionSnapshot.saved + 1

        queue.async {
            do {
                try self.prepareSessionIfNeeded()
                guard let device = self.device else {
                    throw MappingError.invalid("Kamera tidak tersedia")
                }
                if !self.focusAndExposureLocked {
                    try? self.lockHardware(device: device, settings: currentSettings)
                }
                try self.captureOnQueue(
                    mission: missionSnapshot,
                    sequence: nextSequence,
                    settings: currentSettings,
                    kind: "mapping"
                ) { result in
                    switch result {
                    case .success:
                        var committedMission = missionSnapshot
                        committedMission.saved = nextSequence
                        committedMission.phase = self.isAutoCapturing ? .capturing : .ready
                        committedMission.note = "TestOrto (\(committedMission.saved) foto)"
                        try? self.store.write(committedMission)
                        let latestThumb = self.loadLatestMappingInspection(missionID: committedMission.id)
                        DispatchQueue.main.async {
                            self.isBusy = false
                            self.focusAndExposureLocked = true
                            self.activeMission = committedMission
                            self.savedMissions = self.store.records()
                            if let latestThumb {
                                self.lastMappingThumbnail = latestThumb.image
                                self.lastAssessment = latestThumb.assessment
                                self.lastSharpness = latestThumb.sharpness
                            }
                            let stepHint = self.overlayMetrics.map {
                                String(format: "Maju %.2f m untuk foto berikutnya.", $0.forwardStepMeters)
                            } ?? ""
                            self.statusMessage = "Foto #\(nextSequence) tersimpan. \(stepHint)"
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.isBusy = false
                            self.statusMessage = "Gagal memotret: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func toggleAutoCapture() {
        if isAutoCapturing {
            stopAutoCapture()
            statusMessage = "Auto-interval dijeda. Anda tetap bisa menekan TAKE manual."
        } else {
            startAutoCapture()
        }
    }

    func stopAutoCapture() {
        autoTimer?.cancel()
        autoTimer = nil
        if isAutoCapturing {
            isAutoCapturing = false
        }
    }

    private func startAutoCapture() {
        stopAutoCapture()
        let interval = max(1.0, autoInterval)
        isAutoCapturing = true
        statusMessage = String(format: "Auto-capture aktif setiap %.1f detik. Berjalanlah stabil.", interval)
        takePhoto()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self, self.isAutoCapturing else { return }
            if !self.isBusy {
                self.takePhoto()
            }
        }
        autoTimer = timer
        timer.resume()
    }

    func capturedItems(for missionID: UUID) -> [TestOrtoCapturedItem] {
        guard let indexes = try? store.captureIndexes(missionID) else { return [] }
        let decoder = JSONDecoder()
        let baseDir = store.directory(missionID)
        var items: [TestOrtoCapturedItem] = []
        for metaURL in indexes {
            guard let data = try? Data(contentsOf: metaURL),
                let record = try? decoder.decode(CaptureRecord.self, from: data)
            else { continue }
            let jpgName = record.files.first(where: { $0.hasSuffix(".jpg") }) ?? "image.jpg"
            let imageURL =
                record.layoutVersion == 2
                ? baseDir.appendingPathComponent(jpgName)
                : metaURL.deletingLastPathComponent().appendingPathComponent(jpgName)
            let bytes =
                ((try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size]) as? NSNumber)?
                .int64Value ?? 0
            items.append(
                TestOrtoCapturedItem(
                    id: record.id,
                    sequence: record.sequence,
                    kind: record.kind,
                    requestedAt: record.requestedAt,
                    imageURL: imageURL,
                    location: record.location,
                    attitude: record.attitude,
                    fileBytes: bytes
                )
            )
        }
        return items.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.requestedAt < $1.requestedAt
        }
    }

    func missionFolderURL(_ missionID: UUID) -> URL {
        store.directory(missionID)
    }

    // MARK: - Internal Camera Helpers

    private func createFreshMissionOnMain(silent: Bool) {
        var geometry = SurveyGeometry()
        geometry.heightAGL = heightAGL
        geometry.speed = speed
        geometry.forwardOverlap = forwardOverlap
        geometry.sideOverlap = sideOverlap
        geometry.useGrayCard = true
        geometry.reviewed = true

        var plan = MissionPlan()
        let trimmed = missionName.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.name = trimmed.isEmpty ? "TestOrto Lapangan" : trimmed
        plan.interval = max(1.0, min(3600.0, autoInterval))
        plan.photoLimit = 500
        plan.camera = cameraSettings
        plan.survey = geometry

        let record = MissionRecord(plan: plan, phase: .ready, saved: 0, missed: 0, note: "Mode eksperimen TestOrto")
        do {
            try store.write(record)
            activeMission = record
            savedMissions = store.records()
            grayCardLocked = false
            grayCardThumbnail = nil
            lastMappingThumbnail = nil
            if !silent {
                statusMessage = "Misi baru siap: \(plan.name). Ambil Gray Card atau tekan TAKE."
            }
        } catch {
            statusMessage = "Gagal membuat misi: \(error.localizedDescription)"
        }
    }

    private func syncActiveMissionSettings() {
        guard var mission = activeMission else { return }
        mission.plan.camera = cameraSettings
        mission.plan.interval = max(1.0, min(3600.0, autoInterval))
        try? store.write(mission)
        activeMission = mission
    }

    private func prepareSessionIfNeeded() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted = ok
                sem.signal()
            }
            sem.wait()
            guard granted else { throw MappingError.invalid("Izin kamera ditolak") }
        default:
            throw MappingError.invalid("Aktifkan izin kamera di Pengaturan iOS")
        }

        if let existing = device, session.isRunning {
            let caps = readCapabilities(existing)
            DispatchQueue.main.async { self.capabilities = caps }
            return
        }

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw MappingError.invalid("Kamera belakang tidak ditemukan")
        }
        let input = try AVCaptureDeviceInput(device: backCamera)
        session.beginConfiguration()
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw MappingError.invalid("Gagal mengonfigurasi sesi kamera TestOrto")
        }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        session.commitConfiguration()
        if !session.isRunning {
            session.startRunning()
        }
        device = backCamera
        let caps = readCapabilities(backCamera)
        DispatchQueue.main.async {
            self.capabilities = caps
            self.cameraSettings.iso = min(caps.maxISO, max(caps.minISO, self.cameraSettings.iso))
            self.cameraSettings.shutterSeconds = min(
                caps.maxShutter, max(caps.minShutter, self.cameraSettings.shutterSeconds)
            )
        }
    }

    private func readCapabilities(_ camera: AVCaptureDevice) -> CameraCapabilities {
        let dims = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let fov = Double(camera.activeFormat.videoFieldOfView)
        return CameraCapabilities(
            model: UIDevice.current.model,
            minISO: camera.activeFormat.minISO,
            maxISO: camera.activeFormat.maxISO,
            minShutter: max(0.00001, camera.activeFormat.minExposureDuration.seconds),
            maxShutter: min(1.0, camera.activeFormat.maxExposureDuration.seconds),
            width: Int(dims.width),
            height: Int(dims.height),
            bayerRAW: !output.availableRawPhotoPixelFormatTypes.isEmpty,
            manualExposure: camera.isExposureModeSupported(.custom),
            manualFocus: camera.isLockingFocusWithCustomLensPositionSupported,
            manualWB: camera.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            nominalFieldOfView: fov.isFinite && fov > 0 ? fov : 65.0
        )
    }

    private func lockHardware(device: AVCaptureDevice, settings: CameraSettings) throws {
        let caps = readCapabilities(device)
        let clampedISO = min(caps.maxISO, max(caps.minISO, settings.iso))
        let clampedShutter = min(caps.maxShutter, max(caps.minShutter, settings.shutterSeconds))
        let clampedLens = min(1.0, max(0.0, settings.lensPosition))

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.locked), device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: clampedLens, completionHandler: nil)
        }
        if device.isExposureModeSupported(.custom) {
            let duration = CMTimeMakeWithSeconds(clampedShutter, preferredTimescale: 1_000_000_000)
            device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
        }
        if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            let rawGains: AVCaptureDevice.WhiteBalanceGains
            if let custom = settings.whiteBalanceGains, custom.count == 3 {
                rawGains = AVCaptureDevice.WhiteBalanceGains(
                    redGain: custom[0], greenGain: custom[1], blueGain: custom[2]
                )
            } else {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: settings.temperature, tint: settings.tint
                )
                rawGains = device.deviceWhiteBalanceGains(for: tempAndTint)
            }
            let maxGain = device.maxWhiteBalanceGain
            let safeGains = AVCaptureDevice.WhiteBalanceGains(
                redGain: min(maxGain, max(1.0, rawGains.redGain)),
                greenGain: min(maxGain, max(1.0, rawGains.greenGain)),
                blueGain: min(maxGain, max(1.0, rawGains.blueGain))
            )
            device.setWhiteBalanceModeLocked(with: safeGains, completionHandler: nil)
        }
    }

    private func waitForAdjusting(
        device: AVCaptureDevice,
        timeout: Double,
        completion: @escaping () -> Void
    ) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        func poll() {
            let busy = device.isAdjustingFocus || device.isAdjustingExposure || device.isAdjustingWhiteBalance
            if !busy || ProcessInfo.processInfo.systemUptime >= deadline {
                completion()
            } else {
                queue.asyncAfter(deadline: .now() + 0.06, execute: poll)
            }
        }
        queue.asyncAfter(deadline: .now() + 0.12, execute: poll)
    }

    private func captureOnQueue(
        mission: MissionRecord,
        sequence: Int,
        settings: CameraSettings,
        kind: String,
        completion: @escaping (Result<CapturePreview?, Error>) -> Void
    ) throws {
        guard pendingWriter == nil else {
            throw MappingError.invalid("Masih menyimpan foto sebelumnya")
        }
        let photoSettings: AVCapturePhotoSettings
        if settings.raw, let rawFormat = output.availableRawPhotoPixelFormatTypes.first {
            photoSettings = AVCapturePhotoSettings(
                rawPixelFormatType: rawFormat,
                processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
        } else {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        photoSettings.photoQualityPrioritization = settings.raw ? .speed : .balanced
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }

        let writer = PhotoWriter(
            mission: mission,
            sequence: sequence,
            settings: settings,
            location: currentLocationInternal,
            attitude: currentAttitudeInternal,
            kind: kind,
            referenceCommandID: nil,
            store: store
        ) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                self.pendingWriter = nil
                completion(result)
            }
        }
        pendingWriter = writer
        output.capturePhoto(with: photoSettings, delegate: writer)
    }

    private func loadLatestMappingInspection(missionID: UUID) -> (
        image: UIImage, assessment: PreviewAssessment?, sharpness: SharpnessAssessment?
    )? {
        let items = capturedItems(for: missionID).filter { $0.kind == "mapping" }
        guard let latest = items.last,
            let data = try? Data(contentsOf: latest.imageURL),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480,
                ] as CFDictionary
            )
        else { return nil }
        return (
            UIImage(cgImage: cg),
            PreviewAssessment.image(data),
            SharpnessAssessment.image(at: latest.imageURL)
        )
    }
}
