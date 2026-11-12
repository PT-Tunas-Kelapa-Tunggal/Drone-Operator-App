import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts raster images (such as orthomosaic TIFFs) into high-quality JPEG format.
public enum TIFFToJPEGConverter {
    /// Converts a TIFF (or other raster format) into a JPEG file with a solid black background.
    /// Transparent borders or nodata areas are composited against black (#000000).
    /// If an existing JPEG is present at `destinationURL`, it is removed first to ensure a completely fresh file.
    @discardableResult
    public static func convert(
        from sourceURL: URL,
        to destinationURL: URL,
        quality: Double = 1.0
    ) throws -> URL {
        // Ensure any existing JPEG is removed so the output is always freshly generated
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        try autoreleasepool {
            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw MappingError.invalid("Tidak dapat membaca berkas citra: \(sourceURL.lastPathComponent)")
            }
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw MappingError.invalid("Tidak dapat mendekode frame citra TIFF.")
            }

            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0 else {
                throw MappingError.invalid("Dimensi citra tidak valid (\(width)x\(height)).")
            }

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw MappingError.invalid("Gagal menginisialisasi profil warna sRGB.")
            }

            // Create context with black background to flatten alpha/nodata margins
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw MappingError.invalid("Gagal mengalokasikan konteks grafis untuk konversi JPEG.")
            }

            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let flattenedImage = context.makeImage() else {
                throw MappingError.invalid("Gagal merender citra komposit JPEG.")
            }

            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw MappingError.invalid("Gagal membuat tujuan berkas JPEG di \(destinationURL.path).")
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.0), 1.0)
            ]

            CGImageDestinationAddImage(destination, flattenedImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw MappingError.invalid("Gagal menyelesaikan penulisan berkas JPEG.")
            }
        }

        return destinationURL
    }
}
