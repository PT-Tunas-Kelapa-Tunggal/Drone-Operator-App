import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts raster images (such as orthomosaic TIFFs) into high-quality JPEG format.
public enum TIFFToJPEGConverter {
    private static let maxBandBufferBytes = 64 * 1024 * 1024
    private static let maxBandHeight = 512
    private static let minBandHeight = 64

    /// Converts a TIFF (or other raster format) into a JPEG file with a solid black background.
    /// Transparent borders or nodata areas are composited against black (#000000) in bounded horizontal strips
    /// so `>20k × 20k` rasters do not force multi-gigabyte anonymous bitmap allocations at once.
    /// If an existing JPEG is present at `destinationURL`, it is removed first to ensure a completely fresh file.
    @discardableResult
    public static func convert(
        from sourceURL: URL,
        to destinationURL: URL,
        quality: Double = 1.0,
        shouldCancel: () -> Bool = { false }
    ) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        let parentDir = destinationURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let rawScratchURL = parentDir.appendingPathComponent(".tiff-rgba-\(UUID().uuidString).raw")
        let tempJPEGURL = parentDir.appendingPathComponent(".tiff-jpeg-\(UUID().uuidString).tmp")
        defer {
            try? fm.removeItem(at: rawScratchURL)
            try? fm.removeItem(at: tempJPEGURL)
        }

        try autoreleasepool {
            guard !shouldCancel() else { throw CancellationError() }

            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw MappingError.invalid("Tidak dapat membaca berkas citra: \(sourceURL.lastPathComponent)")
            }
            // Disable upfront full-raster caching so ImageIO decodes strips on demand.
            let decodeOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
            ]
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions as CFDictionary)
            else {
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

            let bytesPerRow = width * 4
            let nominalBandHeight = max(
                minBandHeight, min(maxBandHeight, maxBandBufferBytes / max(1, bytesPerRow)))
            let bitmapInfo =
                CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

            guard
                let reusableBandContext = CGContext(
                    data: nil,
                    width: width,
                    height: min(nominalBandHeight, height),
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            else {
                throw MappingError.invalid("Gagal mengalokasikan konteks grafis untuk konversi JPEG.")
            }

            fm.createFile(atPath: rawScratchURL.path, contents: nil)
            let scratchHandle = try FileHandle(forWritingTo: rawScratchURL)
            var didCloseHandle = false
            defer {
                if !didCloseHandle { try? scratchHandle.close() }
            }

            var bandY = 0
            while bandY < height {
                if shouldCancel() { throw CancellationError() }
                let rows = min(nominalBandHeight, height - bandY)

                try autoreleasepool {
                    let stripContext: CGContext
                    if rows == reusableBandContext.height {
                        stripContext = reusableBandContext
                    } else {
                        guard
                            let trailingContext = CGContext(
                                data: nil,
                                width: width,
                                height: rows,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo
                            )
                        else {
                            throw MappingError.invalid("Gagal mengalokasikan strip konversi JPEG.")
                        }
                        stripContext = trailingContext
                    }

                    stripContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
                    stripContext.fill(CGRect(x: 0, y: 0, width: width, height: rows))

                    let cropRect = CGRect(x: 0, y: bandY, width: width, height: rows)
                    if let cropped = cgImage.cropping(to: cropRect) {
                        stripContext.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: rows))
                    } else {
                        let yOffset = -(height - bandY - rows)
                        stripContext.draw(cgImage, in: CGRect(x: 0, y: yOffset, width: width, height: height))
                    }

                    guard let pixelData = stripContext.data else {
                        throw MappingError.invalid("Buffer piksel konversi JPEG tidak tersedia.")
                    }
                    let byteCount = rows * bytesPerRow
                    let chunk = Data(bytesNoCopy: pixelData, count: byteCount, deallocator: .none)
                    try scratchHandle.write(contentsOf: chunk)
                }

                bandY += rows
            }

            try scratchHandle.close()
            didCloseHandle = true

            if shouldCancel() { throw CancellationError() }

            guard let provider = CGDataProvider(url: rawScratchURL as CFURL) else {
                throw MappingError.invalid("Gagal membaca buffer komposit sementara.")
            }
            let flattenedBitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
            guard
                let flattenedImage = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: flattenedBitmapInfo,
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            else {
                throw MappingError.invalid("Gagal merender citra komposit JPEG.")
            }

            guard
                let destination = CGImageDestinationCreateWithURL(
                    tempJPEGURL as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                )
            else {
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

        if shouldCancel() { throw CancellationError() }
        try fm.moveItem(at: tempJPEGURL, to: destinationURL)

        return destinationURL
    }
}
