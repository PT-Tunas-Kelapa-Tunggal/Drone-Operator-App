import Foundation
import ImageIO

/// Prepares the two generated VARI JPEGs for CloudKit without changing the originals.
enum CloudKitVARIImageCompressor {
    static let maximumAssetBytes = 5 * 1_024 * 1_024

    struct PreparedImage {
        let fileURL: URL
        private let temporaryDirectoryURL: URL?

        init(fileURL: URL, temporaryDirectoryURL: URL? = nil) {
            self.fileURL = fileURL
            self.temporaryDirectoryURL = temporaryDirectoryURL
        }

        func removeTemporaryFile() {
            if let temporaryDirectoryURL {
                try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            }
        }
    }

    enum CompressionError: LocalizedError {
        case missingOrUnreadableImage(String)
        case couldNotFitWithinLimit(String)

        var errorDescription: String? {
            switch self {
            case .missingOrUnreadableImage(let name):
                return "Gambar VARI tidak dapat dibaca: \(name)"
            case .couldNotFitWithinLimit(let name):
                return "Gambar VARI tidak dapat dikompresi hingga 5 MB: \(name)"
            }
        }
    }

    /// Files at or below 5 MiB are returned untouched. Larger files are re-encoded
    /// into a temporary JPEG that is no larger than 5 MiB, or an error is thrown.
    static func prepareForUpload(at sourceURL: URL) throws -> PreparedImage {
        let fileManager = FileManager.default
        guard sourceURL.isFileURL,
            let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
            let originalBytes = attributes[.size] as? Int,
            originalBytes > 0,
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else {
            throw CompressionError.missingOrUnreadableImage(sourceURL.lastPathComponent)
        }

        guard originalBytes > maximumAssetBytes else {
            return PreparedImage(fileURL: sourceURL)
        }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CloudKitVARI-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        do {
            let outputURL = temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            let originalMaxDimension = max(width, height)
            let maxDimensions = [
                min(originalMaxDimension, 8_192), 6_144, 4_608, 3_456,
                2_592, 1_944, 1_458, 1_094, 820,
            ].filter { $0 <= originalMaxDimension }

            for maxDimension in maxDimensions {
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0, thumbnailOptions as CFDictionary)
                else {
                    throw CompressionError.missingOrUnreadableImage(sourceURL.lastPathComponent)
                }

                for quality in [0.78, 0.62, 0.45] {
                    try? fileManager.removeItem(at: outputURL)
                    guard let destination = CGImageDestinationCreateWithURL(
                        outputURL as CFURL, "public.jpeg" as CFString, 1, nil)
                    else {
                        throw CompressionError.couldNotFitWithinLimit(sourceURL.lastPathComponent)
                    }
                    CGImageDestinationAddImage(
                        destination,
                        image,
                        [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
                    )
                    guard CGImageDestinationFinalize(destination) else {
                        throw CompressionError.couldNotFitWithinLimit(sourceURL.lastPathComponent)
                    }
                    let compressedBytes = try fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? Int
                    if let compressedBytes, compressedBytes > 0,
                        compressedBytes <= maximumAssetBytes
                    {
                        return PreparedImage(
                            fileURL: outputURL,
                            temporaryDirectoryURL: temporaryDirectory
                        )
                    }
                }
            }

            throw CompressionError.couldNotFitWithinLimit(sourceURL.lastPathComponent)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }
}
