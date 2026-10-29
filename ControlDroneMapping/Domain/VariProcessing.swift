import Foundation

/// Represents the business domain result of a VARI & vegetation health analysis.
public struct VariScanResult: Sendable, Identifiable {
    public let id: UUID
    public let resultJSONURL: URL
    public let treeCount: Int
    public let zoneCount: Int
    public let referenceMeanVari: Double?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        resultJSONURL: URL,
        treeCount: Int,
        zoneCount: Int,
        referenceMeanVari: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.resultJSONURL = resultJSONURL
        self.treeCount = treeCount
        self.zoneCount = zoneCount
        self.referenceMeanVari = referenceMeanVari
        self.createdAt = createdAt
    }
}

/// Abstract contract for performing and managing VARI analyses.
/// Decouples UI and business workflows from underlying subprocesses, Python helpers, or file formats.
public protocol VariProcessing: Sendable {
    /// Verifies whether the embedded VARI engine is installed and operational.
    func checkEngine() async throws -> String

    /// Processes an orthomosaic or aerial photo and yields a domain result.
    func process(
        photoURL: URL,
        plotID: String?,
        outputFolder: URL?
    ) async throws -> VariScanResult

    /// Loads a previously cached VARI scan result from an orthomosaic project output folder, if present.
    func loadCachedResult(from folder: URL) throws -> VariScanResult?
}
