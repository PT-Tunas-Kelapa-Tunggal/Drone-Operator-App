import Foundation

/// Executes the bundled VariEngine to process an image into VARI and nutrient analysis.
public struct LocalVariProcessor: VariProcessing {
    public init() {}

    public func checkEngine() async throws -> String {
        try BundledVariEngine.check()
    }

    public func process(
        photoURL: URL,
        plotID: String? = nil,
        outputFolder: URL? = nil
    ) async throws -> VariScanResult {
        try BundledVariEngine.validateEmbedded()
        guard let helper = BundledVariEngine.helperExecutable else {
            throw MappingError.invalid("Helper binary VariPython tidak ditemukan.")
        }

        let destinationFolder = outputFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("VariScans")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let outputJSONURL = outputFolder != nil
            ? destinationFolder.appendingPathComponent("vari_result.json")
            : destinationFolder.appendingPathComponent("vari_result_\(UUID().uuidString).json")

        let process = Process()
        process.executableURL = helper
        var args = [
            "-m", "krops_vari.main",
            "--photo", photoURL.path,
            "--out", outputJSONURL.path
        ]
        if let plotID {
            args += ["--plot-id", plotID]
        }
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw MappingError.invalid("Pengolahan VARI gagal (exit code \(process.terminationStatus)): \(errMsg)")
        }

        guard FileManager.default.fileExists(atPath: outputJSONURL.path) else {
            throw MappingError.invalid("Berkas hasil VARI tidak ditemukan di \(outputJSONURL.path)")
        }

        return try parseScanResult(from: outputJSONURL)
    }

    public func loadCachedResult(from folder: URL) throws -> VariScanResult? {
        let cachedURL = folder.appendingPathComponent("vari_result.json")
        guard FileManager.default.fileExists(atPath: cachedURL.path) else {
            return nil
        }
        return try parseScanResult(from: cachedURL)
    }

    private func parseScanResult(from url: URL) throws -> VariScanResult {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalid("Hasil VARI bukan format JSON yang valid.")
        }

        let imageInfo = json["image"] as? [String: Any]
        let treeCount = imageInfo?["trees"] as? Int ?? 0
        let zones = json["zones"] as? [[String: Any]] ?? []

        let summary = json["summary"] as? [String: Any]
        let meanVari = summary?["reference_zone_mean_vari"] as? Double ?? summary?["p25_zone_mean_vari"] as? Double

        return VariScanResult(
            resultJSONURL: url,
            treeCount: treeCount,
            zoneCount: zones.count,
            referenceMeanVari: meanVari,
            createdAt: Date()
        )
    }
}
