import AppKit
import Combine
import Foundation

public enum QGCEngineStatus: Equatable {
    case stopped
    case starting
    case healthy(port: Int, pid: pid_t?)
    case skipped(reason: String)
    case failed(reason: String)

    public var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    public var isSkipped: Bool {
        if case .skipped = self { return true }
        return false
    }

    public var pid: pid_t? {
        if case .healthy(_, let p) = self { return p }
        return nil
    }

    public var port: Int? {
        if case .healthy(let p, _) = self { return p }
        return nil
    }
}

@MainActor
public final class QGCEngineManager: ObservableObject {
    public static let shared = QGCEngineManager()

    // Process ID tracking for global atexit teardown
    nonisolated(unsafe) private static var activeChildPID: pid_t?
    private static var atexitRegistered = false

    @Published public private(set) var status: QGCEngineStatus = .stopped
    @Published public private(set) var vehicles: [ConnectedDrone] = []
    @Published public var selectedVehicleID: Int? = nil

    public let port: Int = 18080
    public let healthURL: URL = BundledQGCEngine.healthURL
    public let vehiclesURL: URL = BundledQGCEngine.baseURL.appendingPathComponent("api/v1/vehicles")
    public let vehicleCommandURL: URL = BundledQGCEngine.baseURL.appendingPathComponent(
        "api/v1/vehicles/command")
    public let uploadPlanURL: URL = BundledQGCEngine.baseURL.appendingPathComponent(
        "api/v1/plan/upload")

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public var activeVehicle: ConnectedDrone? {
        if let selectedVehicleID, let match = vehicles.first(where: { $0.id == selectedVehicleID }) {
            return match
        }
        return vehicles.first(where: { $0.active }) ?? vehicles.first
    }

    public var reachableVehicles: [ConnectedDrone] {
        vehicles.filter(\.isReachable)
    }

    public var pid: pid_t? {
        if case .healthy(_, let p) = status { return p }
        return process?.processIdentifier
    }

    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private var isTerminating = false
    private var sigTermSource: DispatchSourceSignal?
    private var sigIntSource: DispatchSourceSignal?

    public init() {
        setupLifecycleObservers()
    }

    deinit {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
    }

    private func setupLifecycleObservers() {
        // 1. AppKit normal quit notification (Cmd+Q, Quit menu)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopEngine()
            }
        }

        // 2. UNIX SIGTERM handling
        signal(SIGTERM, SIG_IGN)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.stopEngine()
                exit(0)
            }
        }
        termSource.resume()
        self.sigTermSource = termSource

        // 3. UNIX SIGINT handling (Ctrl+C)
        signal(SIGINT, SIG_IGN)
        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.stopEngine()
                exit(0)
            }
        }
        intSource.resume()
        self.sigIntSource = intSource

        // 4. atexit fallback handler
        if !Self.atexitRegistered {
            Self.atexitRegistered = true
            atexit {
                if let pid = QGCEngineManager.activeChildPID {
                    kill(pid, SIGTERM)
                    usleep(400_000)
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    public func startEngine() {
        // 0. Check if UI Preview Mode (Skip Engine) was requested via Scheme / Environment
        if ProcessInfo.processInfo.environment["SKIP_QGC_ENGINE"] == "1" {
            self.status = .skipped(reason: "Mode Pratinjau UI (Engine QGC dilewati)")
            return
        }

        // Idempotency: if already starting or healthy, do not start another instance
        if status == .starting { return }
        if case .healthy = status, process?.isRunning == true { return }

        status = .starting

        Task { [weak self] in
            guard let self = self else { return }

            // 1. Pre-flight Idempotency Check:
            // If an instance is already responding on port 18080, adopt it.
            if await self.checkHealthEndpoint() {
                self.status = .healthy(port: self.port, pid: self.process?.processIdentifier)
                self.startPeriodicPolling()
                return
            }

            // 2. Resolve embedded QGC executable binary
            guard let executable = BundledQGCEngine.executableURL else {
                #if DEBUG
                    self.status = .skipped(reason: "Engine belum disertakan dalam bundle (Mode Debug).")
                #else
                    self.status = .failed(reason: "Executable QGroundControl belum tersedia dalam bundle.")
                #endif
                return
            }

            // 3. Configure headless process
            let proc = Process()
            proc.executableURL = executable
            var env = ProcessInfo.processInfo.environment
            env["QGC_HEADLESS"] = "1"
            proc.environment = env

            // Standard I/O redirection: Avoid 64 KB pipe stall by redirecting to log file or nullDevice
            let logDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/ControlDroneMapping")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            let logFile = logDir.appendingPathComponent("qgc-engine.log")
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                proc.standardOutput = fileHandle
                proc.standardError = fileHandle
            } else {
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
            }

            proc.terminationHandler = { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if !self.isTerminating && self.process === p {
                        Self.activeChildPID = nil
                        self.process = nil
                        let code = p.terminationStatus
                        self.status = .failed(reason: "QGC berhenti tiba-tiba (exit code \(code)).")
                    }
                }
            }

            do {
                try proc.run()
                self.process = proc
                Self.activeChildPID = proc.processIdentifier
            } catch {
                self.status = .failed(reason: "Gagal menjalankan QGC: \(error.localizedDescription)")
                return
            }

            // 4. Poll health endpoint until healthy
            let start = Date()
            let timeout: TimeInterval = 12.0
            var ready = false

            while Date().timeIntervalSince(start) < timeout {
                if !proc.isRunning {
                    let code = proc.terminationStatus
                    self.status = .failed(reason: "Proses QGC berhenti sebelum siap (exit code \(code)).")
                    return
                }
                if await self.checkHealthEndpoint() {
                    ready = true
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            if ready {
                self.status = .healthy(port: self.port, pid: proc.processIdentifier)
                self.startPeriodicPolling()
            } else {
                self.status = .failed(
                    reason: "Health check timeout: 127.0.0.1:18080/healthz tidak merespons.")
            }
        }
    }

    public func stopEngine() {
        isTerminating = true
        pollTask?.cancel()
        pollTask = nil

        if let proc = process {
            let pid = proc.processIdentifier
            Self.activeChildPID = nil
            if proc.isRunning {
                proc.terminate()
                let deadline = Date().addingTimeInterval(1.5)
                while proc.isRunning && Date() < deadline {
                    usleep(50_000)
                }
                if proc.isRunning {
                    kill(pid, SIGKILL)
                }
            }
            self.process = nil
        } else if let fallbackPID = Self.activeChildPID {
            Self.activeChildPID = nil
            kill(fallbackPID, SIGTERM)
            usleep(200_000)
            kill(fallbackPID, SIGKILL)
        }
        self.status = .stopped
        self.vehicles = []
        self.isTerminating = false
    }

    public func restartEngine() {
        stopEngine()
        startEngine()
    }

    public func fetchVehicles() async {
        guard case .healthy = status else {
            await MainActor.run {
                if !self.vehicles.isEmpty {
                    self.vehicles = []
                }
            }
            return
        }

        var components = URLComponents(url: vehiclesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "t", value: String(Date().timeIntervalSince1970))
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }
            let decoded = try JSONDecoder().decode(VehiclesResponse.self, from: data)
            await MainActor.run {
                self.vehicles = decoded.vehicles
            }
        } catch {
            print("[QGCEngineManager] fetchVehicles decode error: \(error)")
        }
    }

    public func sendCommand(
        _ command: DroneFlightCommand,
        param: Any? = nil,
        vehicleID: Int? = nil
    ) async throws {
        guard case .healthy = status else {
            throw MappingError.invalid("QGC Engine belum aktif.")
        }

        var payload: [String: Any] = [
            "command": command.rawValue
        ]
        if let vehicleID {
            payload["vehicleId"] = vehicleID
        } else if let active = activeVehicle {
            payload["vehicleId"] = active.id
        }
        if let param {
            payload["param"] = param
        }

        var request = URLRequest(url: vehicleCommandURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MappingError.invalid("Tidak ada respons dari QGC Engine.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg =
                (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? "Gagal menjalankan perintah drone (HTTP \(httpResponse.statusCode))."
            throw MappingError.invalid(errorMsg)
        }

        await fetchVehicles()
    }

    public func uploadMissionPlan(
        _ planData: Data,
        vehicleID: Int? = nil
    ) async throws {
        guard case .healthy = status else {
            throw MappingError.invalid("QGC Engine belum aktif.")
        }

        let planObj = (try? JSONSerialization.jsonObject(with: planData) as? [String: Any]) ?? [:]
        guard !planObj.isEmpty else {
            throw MappingError.invalid("Format data rute (.plan) tidak valid atau kosong.")
        }

        var payload: [String: Any] = [
            "plan": planObj
        ]
        if let vehicleID {
            payload["vehicleId"] = vehicleID
        } else if let active = activeVehicle {
            payload["vehicleId"] = active.id
        }

        var request = URLRequest(url: uploadPlanURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12.0
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MappingError.invalid("Tidak ada respons dari QGC Engine saat mengunggah misi.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg =
                (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? "Gagal mengunggah misi ke drone (HTTP \(httpResponse.statusCode))."
            throw MappingError.invalid(errorMsg)
        }

        await fetchVehicles()
    }

    private func checkHealthEndpoint() async -> Bool {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["status"] as? String == "ok"
            else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func startPeriodicPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self, !Task.isCancelled else { break }
                let isUp = await self.checkHealthEndpoint()
                if isUp {
                    await MainActor.run {
                        if case .healthy = self.status {
                            // Keep current healthy status
                        } else {
                            self.status = .healthy(port: self.port, pid: self.process?.processIdentifier)
                        }
                    }
                    await self.fetchVehicles()
                } else {
                    await MainActor.run {
                        if case .healthy = self.status {
                            if let proc = self.process, !proc.isRunning {
                                self.status = .failed(
                                    reason: "Proses QGC terhenti (exit code \(proc.terminationStatus)).")
                            } else {
                                self.status = .failed(reason: "Endpoint 127.0.0.1:18080/healthz tidak merespons.")
                            }
                        }
                        self.vehicles = []
                    }
                }
            }
        }
    }
}
