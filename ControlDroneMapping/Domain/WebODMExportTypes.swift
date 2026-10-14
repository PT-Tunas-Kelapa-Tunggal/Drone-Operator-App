import Foundation

struct ExportPhoto: Identifiable {
    var capture: CaptureRecord
    var url: URL
    var id: UUID { capture.id }
}
struct GrayPatch: Codable {
    // Coordinates in the orientation-corrected preview, origin at top left.
    var x: Double = 0.4
    var y: Double = 0.4
    var width: Double = 0.2
    var height: Double = 0.2
}
struct ColorGain: Codable {
    var red: Double
    var green: Double
    var blue: Double
    static let identity = ColorGain(red: 1, green: 1, blue: 1)
    var values: [Double] { [red, green, blue] }
    func scaled(_ factor: Double) -> ColorGain {
        ColorGain(red: red * factor, green: green * factor, blue: blue * factor)
    }
}
struct ExportEntry: Codable {
    var filename: String
    var sourceSHA256: String
    var outputSHA256: String
    var gains: ColorGain
    var overlapReference: String?
    var warning: String?
}
struct ExportReport: Codable {
    var version = 1
    var missionID: UUID
    var createdAt = Date()
    var mode: String
    var referenceID: UUID?
    var referenceSHA256: String?
    var referencePatch: GrayPatch?
    var patchOperatorConfirmed: Bool
    var entries: [ExportEntry]
    var warnings: [String]
    var limitations =
        "Visual RGB normalization, not calibrated reflectance. Overlap uses a planar homography and bounded scalar exposure gains. Shadows, parallax, clipping, blur and GNSS errors are not repaired. Original files are untouched. Compare against an uncorrected reconstruction."
}
struct ExportResult {
    var folder: URL
    var count: Int
    var warnings: [String]
}
