import Foundation

/// Executes `VariPython -m krops_vari.timing` with a writable App Sandbox weather cache
/// and optional WeatherKit environment variables.
public struct LocalVariTimingProcessor: VariTimingProcessing {
    public static let requestFileName = "jadwal_pemupukan_request.json"
    public static let outputFileName = "jadwal_pemupukan_hasil.json"

    public init() {}

    public func runTiming(
        request: VariTimingRequest,
        options: VariTimingRunOptions,
        outputFolder: URL
    ) async throws -> VariTimingExecutionResult {
        try BundledVariEngine.validateEmbedded()
        guard let helper = BundledVariEngine.helperExecutable else {
            throw VariTimingError.missingPythonHelper
        }

        let fm = FileManager.default
        try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let cacheDirectory = VariTimingWeatherSettings.writableWeatherCacheDirectory(demo: false)
        try seedWeatherCacheIfNeeded(to: cacheDirectory)

        let requestURL = outputFolder.appendingPathComponent(Self.requestFileName)
        let outputURL = outputFolder.appendingPathComponent(Self.outputFileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let requestData = try encoder.encode(request)
        try requestData.write(to: requestURL, options: .atomic)

        var arguments = [
            "-m", "krops_vari.timing",
            "--request", requestURL.path,
            "--cache-dir", cacheDirectory.path,
            "--out", outputURL.path,
        ]
        if let todayOverride = options.todayOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
            !todayOverride.isEmpty
        {
            arguments.append(contentsOf: ["--today", todayOverride])
        }
        if let yearOverride = options.yearOverride {
            arguments.append(contentsOf: ["--year", String(yearOverride)])
        }
        if options.skipDaily {
            arguments.append("--no-daily")
        }

        var environment = ProcessInfo.processInfo.environment
        if let wk = options.weatherKit, fm.isReadableFile(atPath: wk.keyFileURL.path) {
            environment["WK_TEAM_ID"] = wk.teamID
            environment["WK_KEY_ID"] = wk.keyID
            environment["WK_SERVICE_ID"] = wk.serviceID
            environment["WK_KEY_PATH"] = wk.keyFileURL.path
        }

        let (status, logs) = try await runProcess(
            executable: helper,
            arguments: arguments,
            environment: environment
        )
        try Task.checkCancellation()

        guard status == 0 else {
            let detail = logs.isEmpty ? "Tidak ada pesan error dari Python." : logs
            throw VariTimingError.executionFailed(code: status, detail: detail)
        }

        guard fm.fileExists(atPath: outputURL.path) else {
            throw VariTimingError.missingOutputFile(outputURL)
        }

        let schedule = try decodeSchedule(at: outputURL)
        return VariTimingExecutionResult(
            request: request,
            schedule: schedule,
            requestJSONURL: requestURL,
            resultJSONURL: outputURL,
            cacheDirectoryURL: cacheDirectory,
            ranAt: Date()
        )
    }

    public func loadCachedResult(in outputFolder: URL) -> VariTimingExecutionResult? {
        let fm = FileManager.default
        let outputURL = outputFolder.appendingPathComponent(Self.outputFileName)
        guard fm.fileExists(atPath: outputURL.path),
            let schedule = try? decodeSchedule(at: outputURL)
        else {
            return nil
        }

        let requestURL = outputFolder.appendingPathComponent(Self.requestFileName)
        let request: VariTimingRequest
        if fm.fileExists(atPath: requestURL.path),
            let data = try? Data(contentsOf: requestURL),
            let decoded = try? JSONDecoder().decode(VariTimingRequest.self, from: data)
        {
            request = decoded
        } else {
            request = VariTimingRequest.placeholderTemplate()
        }

        let modifiedDate =
            (try? fm.attributesOfItem(atPath: outputURL.path)[.modificationDate] as? Date)
            ?? Date()

        return VariTimingExecutionResult(
            request: request,
            schedule: schedule,
            requestJSONURL: requestURL,
            resultJSONURL: outputURL,
            cacheDirectoryURL: VariTimingWeatherSettings.writableWeatherCacheDirectory(demo: false),
            ranAt: modifiedDate
        )
    }

    // MARK: - Helpers

    private func decodeSchedule(at url: URL) throws -> VariTimingSchedule {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(VariTimingSchedule.self, from: data)
        } catch {
            throw VariTimingError.invalidJSON(error.localizedDescription)
        }
    }

    /// Copies bundled climate cache files non-destructively into writable Application Support storage
    /// so offline cells work out of the box without overwriting newly fetched NASA POWER/WeatherKit data.
    private func seedWeatherCacheIfNeeded(to destinationRoot: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        guard let sourceRoot = BundledVariEngine.bundledTimingWeatherCacheDirectory else {
            return
        }

        let sourcePath = sourceRoot.standardizedFileURL.path
        guard
            let enumerator = fm.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = String(sourceURL.standardizedFileURL.path.dropFirst(sourcePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }

            let destURL = destinationRoot.appendingPathComponent(relativePath)
            let isDir = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if !fm.fileExists(atPath: destURL.path) {
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                }
            } else if !fm.fileExists(atPath: destURL.path) {
                try fm.createDirectory(
                    at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: sourceURL, to: destURL)
            }
        }
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> (Int32, String) {
        let cancelBox = ProcessCancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.environment = environment

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    cancelBox.register(process)
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    cancelBox.clear()

                    let logs =
                        String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, logs))
                }
            }
        } onCancel: {
            cancelBox.cancel()
        }
    }
}

private final class ProcessCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func register(_ newProcess: Process) {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            newProcess.terminate()
        } else {
            process = newProcess
        }
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning {
            running.terminate()
        }
    }
}
