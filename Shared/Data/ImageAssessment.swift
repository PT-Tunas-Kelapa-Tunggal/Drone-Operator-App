import CoreGraphics
import Foundation
import ImageIO

extension PreviewAssessment {
    static func image(_ data: Data) -> PreviewAssessment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
            return true
        }
        return rendered ? pixels(bytes) : nil
    }
}

extension SharpnessAssessment {
    static func image(at url: URL) -> SharpnessAssessment? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width >= 128,
            image.height >= 128
        else { return nil }
        var scores: [Double] = []
        var textured = 0
        for point in [(0.5, 0.5), (0.15, 0.15), (0.85, 0.15), (0.15, 0.85), (0.85, 0.85)] {
            let x = min(image.width - 128, max(0, Int(Double(image.width) * point.0) - 64))
            let y = min(image.height - 128, max(0, Int(Double(image.height) * point.1) - 64))
            guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 128, height: 128)) else {
                return nil
            }
            var bytes = [UInt8](repeating: 0, count: 128 * 128)
            let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: 128, height: 128, bitsPerComponent: 8,
                        bytesPerRow: 128, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return false }
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 128, height: 128))
                return true
            }
            guard rendered, let result = score(bytes, width: 128, height: 128) else { return nil }
            scores.append(result.energy)
            if result.contrast >= 8 { textured += 1 }
        }
        return SharpnessAssessment(scores: scores, texturedPatches: textured)
    }
}

extension CapturedExposure {
    init?(metadata: [String: Any]) {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
            let values = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber],
            let iso = values.first,
            let shutter = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber
        else { return nil }
        self.init(iso: iso.doubleValue, shutterSeconds: shutter.doubleValue)
    }
}
