import AppKit
import Foundation

extension ControlViewModel {
    var iphoneReadyForCapture: Bool { selectedMissionIsCurrent && readiness().canStart }
    var iphoneCaptureStatus: String {
        if !link.connected { return "iPhone terputus" }
        if !freshness() { return "iPhone · menunggu status" }
        if selectedMissionIsCurrent && isActiveMission {
            return telemetry.phase == .paused ? "iPhone · capture dijeda" : "iPhone · capture berjalan"
        }
        return iphoneReadyForCapture ? "iPhone siap capture" : "iPhone belum siap capture"
    }
    var capturePreparationAdvice: String {
        if !link.connected || !freshness() || !selectedMissionIsCurrent || hasLocalDraft {
            return "Selesaikan koneksi dan persiapan iPhone di panel Perangkat."
        }
        if !geometry.reviewed { return "Periksa rencana survei misi ini sebelum mulai." }
        return readiness().blockers.first.map { "Perangkat: " + $0 } ?? "Siap memulai capture."
    }
    var dashboardAvailableCount: Int { records.filter { $0.saved > 0 }.count }
    var dashboardAttentionCount: Int {
        missionLibrary.missions.filter { [.idle, .paused, .failed].contains($0.phase) }.count
    }
    var dashboardTodayCount: Int {
        missionLibrary.missions.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }
    func dashboardRecords(search: String) -> [MissionRecord] {
        recentRecords.filter {
            search.isEmpty || $0.plan.name.localizedCaseInsensitiveContains(search)
                || $0.id.uuidString.localizedCaseInsensitiveContains(search)
        }
    }
    var isActiveMission: Bool { [.capturing, .countdown, .paused].contains(telemetry.phase) }
    var currentMissionName: String {
        if isActiveMission && selectedMissionIsCurrent { return monitoringPlan.name }
        if selectedMissionID != nil { return plan.name }
        return records.first(where: { $0.id == telemetry.missionID })?.plan.name ?? plan.name
    }
    var phaseTitle: String {
        switch telemetry.phase {
        case .idle: return "Menunggu kamera"
        case .ready: return "Siap dikonfigurasi"
        case .countdown: return "Hitung mundur"
        case .capturing: return "Capture berjalan"
        case .paused: return "Dijeda"
        case .completed: return "Selesai"
        case .failed: return "Periksa kamera"
        }
    }
    var nextStepAdvice: String {
        switch operatorStage {
        case .survey:
            return
                "Samakan tinggi, kecepatan, dan overlap dengan rencana di QGroundControl; lalu tandai rencana sudah diperiksa."
        case .camera: return "Terapkan pengaturan kamera berdasarkan rencana ini."
        case .reference: return "Posisikan kartu fisik pada cahaya kebun sebelum mengukur."
        case .test: return "Singkirkan kartu dan arahkan kamera ke objek bertekstur pada jarak kerja."
        case .review: return readiness().blockers.first ?? "Periksa foto asli sebelum mulai."
        case .ready:
            return
                "Mulai pengambilan hanya menjalankan kamera iPhone. Penerbangan diatur melalui QGroundControl."
        case .connection:
            return draftNeedsRetry
                ? "Setelah memperbaiki masalah, pilih Coba siapkan misi."
                : "Misi tetap tersimpan di Mac. Koneksi dan persiapan iPhone tersedia di panel Perangkat."
        default: return "Tunggu operasi selesai sebelum melanjutkan."
        }
    }
    func requestPendingStatus() {
        guard let pending else { return }
        do { try link.send(Packet(replyRequestID: pending.id)) } catch {
            errorMessage = error.localizedDescription
        }
    }
    func hasLocalDataset(_ id: UUID) -> Bool {
        FileManager.default.fileExists(
            atPath: link.store.directory(id).appendingPathComponent("mission.json").path)
    }
    func refreshLocalDatasets() {
        let local = link.store.records()
        records = (records.filter { remote in !local.contains(where: { $0.id == remote.id }) } + local)
            .sorted { $0.createdAt > $1.createdAt }
    }
    func openDatasetFolder(missionID: UUID? = nil) {
        let folder = missionID.map { link.store.directory($0) } ?? link.store.root
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch { errorMessage = error.localizedDescription }
    }
    func openQGroundControl() { QGroundControlLauncher.open { [weak self] in self?.errorMessage = $0 } }
    func setDurationMinutes(_ minutes: Double) {
        plan.durationSeconds = minutes * 60
        if minutes.isFinite, minutes > 0, plan.interval > 0 {
            plan.photoLimit = Int(min(100000, ceil(minutes * 60 / plan.interval)))
        }
    }
    func setShutterDenominator(_ denominator: Double) {
        plan.camera.shutterSeconds = denominator > 0 ? 1 / denominator : 0
    }
    func setTemperature(_ value: Float) {
        plan.camera.whiteBalanceGains = nil
        plan.camera.temperature = value
    }
    func setTint(_ value: Float) {
        plan.camera.whiteBalanceGains = nil
        plan.camera.tint = value
    }
}
