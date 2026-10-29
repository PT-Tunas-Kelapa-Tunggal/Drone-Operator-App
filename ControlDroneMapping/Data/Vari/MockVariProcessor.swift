import Foundation

/// Mock implementation of VariProcessing for SwiftUI previews, testing, and offline demo.
public final class MockVariProcessor: VariProcessing, @unchecked Sendable {
    public var shouldThrowError: Error?
    public var mockResult: VariScanResult?

    public init(shouldThrowError: Error? = nil, mockResult: VariScanResult? = nil) {
        self.shouldThrowError = shouldThrowError
        self.mockResult = mockResult
    }

    public func checkEngine() async throws -> String {
        if let shouldThrowError { throw shouldThrowError }
        return "VARI engine siap (Demo Mode)"
    }

    public func process(
        photoURL: URL,
        plotID: String? = nil,
        outputFolder: URL? = nil
    ) async throws -> VariScanResult {
        if let shouldThrowError { throw shouldThrowError }
        if let mockResult { return mockResult }

        // Simulate calculation delay
        try await Task.sleep(nanoseconds: 800_000_000)

        let targetDir = outputFolder ?? FileManager.default.temporaryDirectory
        let mockURL = targetDir.appendingPathComponent("vari_result.json")
        let dummyJSON = """
        {
          "schema": 1,
          "image": { "trees": 128 },
          "zones": [{}, {}, {}, {}],
          "summary": { "reference_zone_mean_vari": 0.42 }
        }
        """
        try? dummyJSON.write(to: mockURL, atomically: true, encoding: .utf8)

        return VariScanResult(
            resultJSONURL: mockURL,
            treeCount: 128,
            zoneCount: 4,
            referenceMeanVari: 0.42,
            createdAt: Date()
        )
    }

    public func loadCachedResult(from folder: URL) throws -> VariScanResult? {
        let cachedURL = folder.appendingPathComponent("vari_result.json")
        guard FileManager.default.fileExists(atPath: cachedURL.path) else {
            return nil
        }
        return VariScanResult(
            resultJSONURL: cachedURL,
            treeCount: 128,
            zoneCount: 4,
            referenceMeanVari: 0.42,
            createdAt: Date()
        )
    }
}
