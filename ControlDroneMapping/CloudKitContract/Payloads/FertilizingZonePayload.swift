import Foundation

/// 2D image-relative pixel coordinate point.
nonisolated public struct PixelPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Fertilization zone defined in orthomosaic pixel space.
nonisolated public struct FertilizingZoneItem: Codable, Equatable, Sendable {
    public let id: Int64
    public let treeCount: Int64
    public let boundingBox: [PixelPoint]

    public init(id: Int64, treeCount: Int64, boundingBox: [PixelPoint]) {
        self.id = id
        self.treeCount = treeCount
        self.boundingBox = boundingBox
    }
}
