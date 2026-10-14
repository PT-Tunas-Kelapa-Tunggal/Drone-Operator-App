import Foundation

protocol WebODMExportService {
    func photos(_ id: UUID) throws -> [ExportPhoto]
    func export(
        id: UUID, referenceID: UUID?, patch: GrayPatch, confirmed: Bool,
        overlap: Bool, progress: (Int, Int) -> Void
    ) throws -> ExportResult
}
