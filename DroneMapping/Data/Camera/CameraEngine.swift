import AVFoundation
import Foundation
import ImageIO
import UIKit

// All mutable capture state is confined to queue. No network callback owns mission timing.
final class CameraEngine: NSObject, CameraService {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "mapping.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let store: any DatasetRepository
    private var device: AVCaptureDevice?
    private var record: MissionRecord?
    private var settings = CameraSettings()
    private var status = Telemetry()
    private var timer: DispatchSourceTimer?
    private var schedule: CaptureSchedule?
    private var countdown: StartCountdown?
    private var pending: PhotoWriter?
    private var configuring = false
    private var location: GeoSample?
    private var observers: [NSObjectProtocol] = []
    private var battery: Float = -1
    var onStatus: ((Telemetry) -> Void)?
    var onPreview: ((CapturePreview) -> Void)?

    init(store: any DatasetRepository = DatasetStore()) {
        self.store = store
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) {
                    [weak self] _ in
                    self?.queue.async {
                        self?.pause(
                            reason: "Kamera terinterupsi. Periksa perangkat lalu lanjutkan secara manual.")
                    }
                })
        }
    }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.cancel()
    }
    func updateLocation(_ value: GeoSample?) { queue.async { self.location = value } }
    func health(battery: Float) {
        queue.async {
            self.battery = battery
            self.publish()
        }
    }
    func backgrounded() {
        queue.async { self.pause(reason: "Aplikasi tidak aktif; capture dijeda oleh batasan iOS") }
    }
    func perform(_ command: Command, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let finish: (Result<String, Error>) -> Void = { result in
                self.publish()
                DispatchQueue.main.async { completion(result) }
            }
            do {
                switch command.action {
                case .prepare:
                    guard !self.configuring, self.pending == nil,
                        ![.capturing, .countdown].contains(self.status.phase)
                    else { throw MappingError.invalid("Kamera sibuk") }
                    try self.prepare()
                    finish(.success("Kamera siap; terapkan parameter sebelum memulai"))
                case .createMission:
                    guard let plan = command.plan, self.device != nil, self.session.isRunning,
                        self.pending == nil, !self.configuring,
                        ![.capturing, .countdown, .paused].contains(self.status.phase)
                    else { throw MappingError.invalid("Selesaikan misi aktif dan siapkan kamera dahulu") }
                    try plan.validate()
                    if var previous = self.record, previous.phase == .ready {
                        previous.phase = .completed
                        previous.note = "Persiapan ditutup saat membuat misi baru"
                        try self.store.write(previous)
                    }
                    let mission = MissionRecord(plan: plan)
                    try self.store.write(mission)
                    self.record = mission
                    self.status.phase = .ready
                    self.status.exposureCalibration = nil
                    self.status.focusCalibration = nil
                    self.status.message = "Misi baru: " + plan.name
                    finish(.success("Misi baru dibuat: " + plan.name))
                case .apply:
                    guard let plan = command.plan else { throw MappingError.invalid("Konfigurasi hilang") }
                    try plan.validate()
                    self.status.focusCalibration = nil
                    self.status.exposureCalibration = nil
                    try self.apply(plan.camera, completion: finish)
                case .grayCard, .grayCardReference:
                    guard let device = self.device else {
                        throw MappingError.invalid("Siapkan kamera dahulu")
                    }
                    if command.action == .grayCardReference {
                        guard self.status.phase == .ready, self.record != nil,
                            command.plan?.camera == self.settings
                        else {
                            throw MappingError.invalid(
                                "Buat misi dan terapkan kamera sebelum mengambil referensi")
                        }
                    }
                    if command.action == .grayCardReference, command.plan?.guidedMode == true {
                        guard let plan = command.plan else { throw MappingError.invalid("Rencana hilang") }
                        try self.meterGrayCard(plan: plan, commandID: command.id, finish: finish)
                        return
                    }
                    var target = self.settings
                    let gains = device.grayWorldDeviceWhiteBalanceGains
                    target.whiteBalanceGains = [gains.redGain, gains.greenGain, gains.blueGain]
                    let values = device.temperatureAndTintValues(for: gains)
                    target.temperature = min(12000, max(2000, values.temperature))
                    target.tint = min(150, max(-150, values.tint))
                    try self.apply(target) { result in
                        // apply completes on the camera queue. Once accepted, this entire
                        // operation finishes locally even if the Mac disconnects.
                        if command.action == .grayCardReference, case .success = result {
                            do {
                                self.record?.plan.camera = self.settings
                                if let record = self.record { try self.store.write(record) }
                                try self.capture(kind: "calibration-before", referenceCommandID: command.id)
                                finish(.success("Warna terkunci; menunggu foto referensi tersimpan"))
                            } catch { finish(.failure(error)) }
                        } else {
                            finish(result)
                        }
                    }
                case .start:
                    guard let plan = command.plan else { throw MappingError.invalid("Rencana misi hilang") }
                    try plan.validate()
                    guard self.record == nil || [.completed, .failed].contains(self.status.phase) else {
                        throw MappingError.invalid("Selesaikan misi aktif sebelum membuat misi baru")
                    }
                    guard plan.camera == self.settings, self.status.settings != nil, self.device != nil,
                        self.pending == nil, !self.configuring, self.session.isRunning
                    else {
                        throw MappingError.invalid("Terapkan parameter kamera dan tunggu konfirmasi dahulu")
                    }
                    var mission = MissionRecord(plan: plan)
                    mission.phase = .countdown
                    try self.store.write(mission)
                    self.record = mission
                    self.status.phase = .countdown
                    self.status.message = "Bersiap memulai misi"
                    self.startTimer()
                    finish(.success("Hitung mundur dimulai"))
                case .download:
                    guard self.pending == nil, !self.configuring,
                        ![.capturing, .countdown].contains(self.status.phase)
                    else {
                        throw MappingError.invalid(
                            "Tunggu capture/konfigurasi selesai dan jeda misi sebelum transfer")
                    }
                    finish(.success("Dataset siap ditransfer"))
                case .finish:
                    guard self.record != nil, self.pending == nil, !self.configuring else {
                        throw MappingError.invalid("Tunggu foto selesai disimpan")
                    }
                    self.timer?.cancel()
                    self.timer = nil
                    self.countdown = nil
                    self.status.countdownRemaining = nil
                    self.record?.phase = .completed
                    self.status.phase = .completed
                    if let record = self.record { try self.store.write(record) }
                    self.status.message = "Misi selesai"
                    finish(.success("Misi selesai"))
                case .pause:
                    self.pause(reason: "Dijeda oleh operator")
                    finish(.success("Misi dijeda"))
                case .resume:
                    guard self.status.phase == .paused, self.record != nil, self.pending == nil,
                        self.session.isRunning, !self.session.isInterrupted, !self.configuring,
                        self.status.settings == self.settings
                    else {
                        throw MappingError.invalid(
                            "Misi belum siap dilanjutkan; periksa atau terapkan kamera ulang")
                    }
                    self.status.phase = .countdown
                    self.record?.phase = .countdown
                    if let record = self.record { try self.store.write(record) }
                    self.status.message = "Misi dilanjutkan; gap jeda perlu diperiksa"
                    self.startTimer()
                    finish(.success("Misi dilanjutkan"))
                case .testCapture, .calibrationBefore, .calibrationAfter:
                    guard ![.capturing, .countdown].contains(self.status.phase) else {
                        throw MappingError.invalid("Jeda misi sebelum mengambil referensi")
                    }
                    if self.record == nil
                        || (command.action != .calibrationAfter && self.status.phase == .completed)
                    {
                        var mission = MissionRecord(plan: command.plan ?? MissionPlan())
                        mission.plan.camera = self.settings
                        try mission.plan.validate()
                        try self.store.write(mission)
                        self.record = mission
                        self.status.phase = .ready
                    }
                    if command.action == .testCapture, command.plan?.guidedMode == true {
                        try self.focusAndTest(commandID: command.id, finish: finish)
                        return
                    }
                    try self.capture(
                        kind: command.action == .testCapture
                            ? "quality-test"
                            : command.action == .calibrationBefore
                                ? "calibration-before" : "calibration-after", referenceCommandID: command.id)
                    finish(.success("Referensi diminta; tunggu konfirmasi penyimpanan"))
                default: throw MappingError.invalid("Perintah bukan untuk kamera")
                }
            } catch { finish(.failure(error)) }
        }
    }
    // Starts a ready mission that already contains a preflight reference.
    func startPrepared(_ plan: MissionPlan, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                try plan.validate()
                guard self.status.phase == .ready, var record = self.record,
                    self.pending == nil, !self.configuring, self.session.isRunning,
                    self.status.settings != nil, !self.session.isInterrupted, plan.camera == self.settings
                else { throw MappingError.invalid("Referensi/parameter belum siap") }
                record.plan = plan
                record.phase = .countdown
                try self.store.write(record)
                self.record = record
                self.status.phase = .countdown
                self.status.message = "Bersiap memulai misi"
                self.startTimer()
                self.publish()
                DispatchQueue.main.async { completion(.success("Hitung mundur dimulai")) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func prepare() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw MappingError.invalid("Izin kamera diperlukan")
        }
        if device != nil {
            if !session.isRunning { session.startRunning() }
            if status.phase == .failed {
                // Preserve the failed dataset, then prepare a new mission rather than reusing its UUID.
                record = nil
                status.phase = .ready
            }
            status.message = "Kamera siap. Terapkan pengaturan dan ulangi pemeriksaan foto."
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { throw MappingError.invalid("Kamera wide belakang tidak tersedia") }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw MappingError.invalid("Input kamera tidak tersedia")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            throw MappingError.invalid("Output foto tidak tersedia")
        }
        session.addOutput(output)
        if let dimensions = camera.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) {
            output.maxPhotoDimensions = dimensions
        }
        output.maxPhotoQualityPrioritization = .quality
        if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
        session.commitConfiguration()
        device = camera
        session.startRunning()
        status.capabilities = CameraCapabilities(
            model: camera.localizedName, minISO: camera.activeFormat.minISO,
            maxISO: camera.activeFormat.maxISO, minShutter: camera.activeFormat.minExposureDuration.seconds,
            maxShutter: camera.activeFormat.maxExposureDuration.seconds,
            width: Int(output.maxPhotoDimensions.width),
            height: Int(output.maxPhotoDimensions.height), bayerRAW: rawType != nil,
            manualExposure: camera.isExposureModeSupported(.custom),
            manualFocus: camera.isLockingFocusWithCustomLensPositionSupported,
            manualWB: camera.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            nominalFieldOfView: Double(camera.activeFormat.videoFieldOfView))
        if record == nil { status.phase = .ready }
        status.message = "Kamera siap. Terapkan pengaturan manual."
    }
    private var rawType: OSType? {
        output.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
    }
    private func apply(_ value: CameraSettings, completion: @escaping (Result<String, Error>) -> Void) throws
    {
        try value.validate()
        guard let camera = device, pending == nil, !configuring,
            ![.capturing, .countdown].contains(status.phase)
        else { throw MappingError.invalid("Siapkan/jeda kamera dan tunggu penyimpanan selesai") }
        guard camera.isExposureModeSupported(.custom), camera.isLockingFocusWithCustomLensPositionSupported,
            camera.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        else { throw MappingError.invalid("Kontrol manual lengkap tidak didukung kamera ini") }
        guard (camera.activeFormat.minISO...camera.activeFormat.maxISO).contains(value.iso),
            (camera.activeFormat.minExposureDuration.seconds...camera.activeFormat.maxExposureDuration.seconds)
                .contains(value.shutterSeconds),
            !value.raw || rawType != nil
        else { throw MappingError.invalid("ISO, shutter, atau RAW di luar kemampuan perangkat") }
        var gains = camera.deviceWhiteBalanceGains(
            for: .init(temperature: value.temperature, tint: value.tint))
        if let custom = value.whiteBalanceGains {
            gains = .init(redGain: custom[0], greenGain: custom[1], blueGain: custom[2])
        }
        guard
            [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({
                $0.isFinite && (1...camera.maxWhiteBalanceGain).contains($0)
            })
        else { throw MappingError.invalid("White balance di luar rentang gain perangkat") }
        try camera.lockForConfiguration()
        configuring = true
        status.settings = nil
        var completed = false
        queue.asyncAfter(deadline: .now() + 5) {
            guard !completed else { return }
            completed = true
            self.configuring = false
            self.status.settings = nil
            self.status.exposureCalibration = nil
            self.status.focusCalibration = nil
            self.status.message = "Penerapan kamera melewati batas waktu. Siapkan kamera ulang."
            completion(.failure(MappingError.invalid(self.status.message)))
        }
        let group = DispatchGroup()
        group.enter()
        camera.setExposureModeCustom(
            duration: CMTime(seconds: value.shutterSeconds, preferredTimescale: 1_000_000_000), iso: value.iso
        ) { _ in group.leave() }
        group.enter()
        camera.setFocusModeLocked(lensPosition: value.lensPosition) { _ in group.leave() }
        group.enter()
        camera.setWhiteBalanceModeLocked(with: gains) { _ in group.leave() }
        camera.videoZoomFactor = 1
        camera.isSubjectAreaChangeMonitoringEnabled = false
        camera.unlockForConfiguration()
        group.notify(queue: queue) { [weak self] in
            guard let self, !completed else { return }
            completed = true
            self.configuring = false
            self.settings = value
            self.status.settings = value
            self.status.message = "Exposure, fokus, dan WB terkunci"
            completion(.success(self.status.message))
        }
    }
    // AE is used only for a preflight meter reading; the flight remains fully manual.
    private func meterGrayCard(
        plan: MissionPlan, commandID: UUID, finish: @escaping (Result<String, Error>) -> Void
    ) throws {
        guard let camera = device, pending == nil, !configuring, session.isRunning,
            !session.isInterrupted, camera.isExposureModeSupported(.continuousAutoExposure),
            camera.isExposurePointOfInterestSupported, let geometry = plan.survey,
            let c = status.capabilities
        else { throw MappingError.invalid("Pengukuran cahaya belum didukung atau kamera sibuk") }
        let recommended = try GuidedAcquisition.plan(plan, geometry: geometry, capabilities: c)
        let previous = settings
        try camera.lockForConfiguration()
        configuring = true
        camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        camera.setExposureTargetBias(0, completionHandler: nil)
        camera.exposureMode = .continuousAutoExposure
        camera.unlockForConfiguration()
        status.message = "Mengukur cahaya kartu; tahan posisi hingga referensi tersimpan"
        publish()
        let began = ProcessInfo.processInfo.systemUptime
        var stable = 0
        var lastProduct = 0.0
        func poll() {
            let product = Double(camera.iso) * camera.exposureDuration.seconds
            if !camera.isAdjustingExposure, product.isFinite, product > 0,
                lastProduct > 0, abs(log2(product / lastProduct)) < 0.05
            {
                stable += 1
            } else {
                stable = 0
            }
            lastProduct = product
            if self.session.isInterrupted || !self.session.isRunning
                || ProcessInfo.processInfo.systemUptime - began > 6
            {
                restore(
                    MappingError.invalid(
                        "Cahaya belum stabil atau kamera terinterupsi. Tahan kartu dan ulangi pengukuran"))
                return
            }
            if stable < 3 {
                self.queue.asyncAfter(deadline: .now() + 0.2, execute: poll)
                return
            }
            do {
                let meteredISO = camera.iso
                let meteredShutter = camera.exposureDuration.seconds
                let value = try GuidedAcquisition.exposure(
                    meteredISO: meteredISO, meteredShutter: meteredShutter,
                    preferredShutter: recommended.camera.shutterSeconds, minISO: c.minISO,
                    maxISO: min(800, c.maxISO), minShutter: c.minShutter)
                var target = recommended.camera
                target.lensPosition = previous.lensPosition
                target.iso = value.iso
                target.shutterSeconds = value.shutter
                let gains = camera.grayWorldDeviceWhiteBalanceGains
                target.whiteBalanceGains = [gains.redGain, gains.greenGain, gains.blueGain]
                let wb = camera.temperatureAndTintValues(for: gains)
                target.temperature = min(12000, max(2000, wb.temperature))
                target.tint = min(150, max(-150, wb.tint))
                self.configuring = false
                try self.apply(target) { result in
                    if case .failure = result {
                        finish(result)
                        return
                    }
                    do {
                        let calibration = ExposureCalibration(
                            measuredAt: Date(), meteredISO: meteredISO,
                            meteredShutter: meteredShutter, selectedISO: target.iso,
                            selectedShutter: target.shutterSeconds)
                        self.status.exposureCalibration = calibration
                        self.record?.plan = recommended
                        self.record?.plan.camera = target
                        self.record?.plan.exposureCalibration = calibration
                        self.record?.plan.focusCalibration = self.status.focusCalibration
                        if let record = self.record { try self.store.write(record) }
                        try self.capture(kind: "calibration-before", referenceCommandID: commandID)
                        finish(.success("Exposure dan warna terkunci; menunggu referensi tersimpan"))
                    } catch { finish(.failure(error)) }
                }
            } catch { restore(error) }
        }
        func restore(_ error: Error) {
            self.configuring = false
            do { try self.apply(previous) { _ in finish(.failure(error)) } } catch {
                self.status.settings = nil
                finish(.failure(error))
            }
        }
        queue.asyncAfter(deadline: .now() + 0.6, execute: poll)
    }
    private func focusAndTest(commandID: UUID, finish: @escaping (Result<String, Error>) -> Void) throws {
        guard let camera = device, status.phase == .ready, record != nil, pending == nil, !configuring,
            session.isRunning, !session.isInterrupted, camera.isFocusModeSupported(.autoFocus),
            camera.isFocusPointOfInterestSupported
        else {
            throw MappingError.invalid("Autofocus belum tersedia; siapkan kamera dan tunggu operasi selesai")
        }
        let previous = settings.lensPosition
        status.focusCalibration = nil
        record?.plan.focusCalibration = nil
        try camera.lockForConfiguration()
        configuring = true
        camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        camera.focusMode = .autoFocus
        camera.unlockForConfiguration()
        status.message = "Mencari fokus; tahan kamera pada objek bertekstur di jarak kerja"
        publish()
        let began = ProcessInfo.processInfo.systemUptime
        var stable = 0
        var last: Float = -1
        var completed = false
        func lock(_ position: Float, failure: Error? = nil) {
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard !completed else { return }
                completed = true
                self.configuring = false
                self.status.settings = nil
                self.status.focusCalibration = nil
                finish(
                    .failure(
                        MappingError.invalid("Konfirmasi penguncian fokus terlambat; siapkan kamera ulang")))
            }
            do {
                try camera.lockForConfiguration()
                camera.setFocusModeLocked(lensPosition: position) { _ in
                    self.queue.async {
                        guard !completed else { return }
                        completed = true
                        self.configuring = false
                        self.settings.lensPosition = position
                        self.status.settings = self.settings
                        if let failure {
                            finish(.failure(failure))
                            return
                        }
                        do {
                            guard self.session.isRunning, !self.session.isInterrupted else {
                                throw MappingError.invalid("Kamera terinterupsi; ulangi foto uji")
                            }
                            let calibration = FocusCalibration(measuredAt: Date(), lensPosition: position)
                            self.status.focusCalibration = calibration
                            self.record?.plan.camera = self.settings
                            self.record?.plan.focusCalibration = calibration
                            if let record = self.record { try self.store.write(record) }
                            try self.capture(kind: "quality-test", referenceCommandID: commandID)
                            finish(.success("Fokus ditemukan dan dikunci; periksa foto asli"))
                        } catch {
                            self.status.focusCalibration = nil
                            finish(.failure(error))
                        }
                    }
                }
                camera.unlockForConfiguration()
            } catch {
                completed = true
                self.configuring = false
                self.status.settings = nil
                finish(.failure(error))
            }
        }
        func poll() {
            let position = camera.lensPosition
            if !camera.isAdjustingFocus, position.isFinite, abs(position - last) < 0.002 {
                stable += 1
            } else {
                stable = 0
            }
            last = position
            if !self.session.isRunning || self.session.isInterrupted
                || ProcessInfo.processInfo.systemUptime - began > 6
            {
                lock(
                    previous,
                    failure: MappingError.invalid(
                        "Fokus belum stabil. Arahkan ke objek bertekstur dengan cahaya cukup, lalu ulangi"))
                return
            }
            if stable >= 3 {
                lock(position)
                return
            }
            self.queue.asyncAfter(deadline: .now() + 0.2, execute: poll)
        }
        queue.asyncAfter(deadline: .now() + 0.6, execute: poll)
    }
    private func startTimer() {
        timer?.cancel()
        guard let record else { return }
        let start = StartCountdown(now: ProcessInfo.processInfo.systemUptime)
        countdown = start
        status.countdownRemaining = 3
        schedule = CaptureSchedule(next: start.deadline, interval: record.plan.interval)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(15))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }
    private func tick() {
        if status.phase == .countdown, let countdown {
            let remaining = countdown.remaining(now: ProcessInfo.processInfo.systemUptime)
            if remaining > 0 {
                if status.countdownRemaining != remaining {
                    status.countdownRemaining = remaining
                    publish()
                }
                return
            }
            self.countdown = nil
            status.countdownRemaining = 0
            status.phase = .capturing
            record?.phase = .capturing
            status.message = "START • misi berjalan mandiri di iPhone"
            do { if let record { try store.write(record) } } catch {
                fail(error)
                return
            }
            publish()
            queue.asyncAfter(deadline: .now() + 1) {
                if self.status.countdownRemaining == 0 {
                    self.status.countdownRemaining = nil
                    self.publish()
                }
            }
        }
        guard status.phase == .capturing,
            let skipped = schedule?.consume(now: ProcessInfo.processInfo.systemUptime)
        else { return }
        record?.missed += skipped
        if pending != nil {
            record?.missed += 1
            publish()
            return
        }
        do { try capture(kind: "mapping") } catch { fail(error) }
    }
    private func capture(kind: String, referenceCommandID: UUID? = nil) throws {
        guard let camera = device, let mission = record, pending == nil, !configuring,
            session.isRunning, !session.isInterrupted, status.settings != nil
        else { throw MappingError.invalid("Kamera belum siap mengambil foto") }
        guard ProcessInfo.processInfo.thermalState != .critical else {
            throw MappingError.invalid("Suhu kritis; capture dihentikan")
        }
        let free = freeSpace()
        guard free >= 512 * 1024 * 1024 else {
            throw MappingError.invalid("Ruang penyimpanan kurang dari cadangan 512 MB")
        }
        let photoSettings: AVCapturePhotoSettings
        if settings.raw {
            guard let raw = rawType else { throw MappingError.invalid("RAW tidak tersedia") }
            photoSettings = AVCapturePhotoSettings(
                rawPixelFormatType: raw, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        photoSettings.maxPhotoDimensions = output.maxPhotoDimensions
        // AVFoundation requires .speed for Bayer RAW, including RAW+JPEG.
        photoSettings.photoQualityPrioritization = .speed
        photoSettings.isAutoContentAwareDistortionCorrectionEnabled = false
        if camera.hasFlash { photoSettings.flashMode = .off }
        let writer = PhotoWriter(
            mission: mission, settings: settings, location: location, kind: kind,
            referenceCommandID: referenceCommandID, store: store
        ) { result in
            self.queue.async {
                self.pending = nil
                switch result {
                case .success(let preview):
                    if let preview { DispatchQueue.main.async { self.onPreview?(preview) } }
                    if kind == "mapping" { self.record?.saved += 1 }
                    self.status.message =
                        kind == "mapping" ? "Foto dan metadata tersimpan" : "Referensi kalibrasi tersimpan"
                    if let current = self.record, current.saved >= current.plan.photoLimit {
                        self.timer?.cancel()
                        self.timer = nil
                        self.record?.phase = .completed
                        self.status.phase = .completed
                    }
                    do { if let record = self.record { try self.store.write(record) } } catch {
                        self.fail(error)
                    }
                case .failure(let error): self.fail(error)
                }
                self.publish()
            }
        }
        pending = writer
        publish()
        output.capturePhoto(with: photoSettings, delegate: writer)
        // A missing callback must not leave a mission falsely reporting active capture forever.
        queue.asyncAfter(deadline: .now() + 30) { [weak self, weak writer] in
            guard let self, let writer, self.pending === writer else { return }
            self.pause(reason: "Capture melebihi 30 detik; tunggu callback atau mulai ulang aplikasi")
        }
    }
    private func pause(reason: String) {
        timer?.cancel()
        timer = nil
        countdown = nil
        status.countdownRemaining = nil
        if [.capturing, .countdown].contains(status.phase) {
            status.phase = .paused
            record?.phase = .paused
        }
        status.message = reason
        do { if let record { try store.write(record) } } catch {
            status.phase = .failed
            status.message = error.localizedDescription
        }
        publish()
    }
    private func fail(_ error: Error) {
        timer?.cancel()
        timer = nil
        countdown = nil
        status.countdownRemaining = nil
        status.phase = .failed
        record?.phase = .failed
        status.message = error.localizedDescription
        record?.note = error.localizedDescription
        if let record { try? store.write(record) }
        publish()
    }
    private func freeSpace() -> Int64 {
        (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize]
            as? NSNumber)?.int64Value ?? 0
    }
    private func publish() {
        status.captureBusy = pending != nil || configuring
        status.missionID = record?.id
        status.saved = record?.saved ?? 0
        status.missed = record?.missed ?? 0
        status.battery = battery
        status.freeBytes = freeSpace()
        status.updatedAt = Date()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: status.thermal = "Normal"
        case .fair: status.thermal = "Hangat"
        case .serious: status.thermal = "Panas"
        case .critical: status.thermal = "Kritis"
        @unknown default: status.thermal = "Unknown"
        }
        let snapshot = status
        DispatchQueue.main.async { self.onStatus?(snapshot) }
    }
}
