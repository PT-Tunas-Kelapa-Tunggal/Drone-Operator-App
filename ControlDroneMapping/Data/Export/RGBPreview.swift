import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision
import simd

// Small sRGB previews are used only to estimate correction. Full-size pixels are never warped.
struct RGBPreview {
    let image: CGImage
    let width: Int
    let height: Int
    let pixels: [UInt8]
    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 768,
                ] as CFDictionary)
        else { throw MappingError.invalid("Foto tidak dapat dibaca: " + url.lastPathComponent) }
        let width = image.width
        let height = image.height
        self.image = image
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw MappingError.invalid("Gagal membaca warna foto") }
        pixels = bytes
    }
    static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    func rgb(x: Int, y: Int) -> [Double] {
        let start = (y * width + x) * 4
        return (0..<3).map { Self.linear(Double(pixels[start + $0]) / 255) }
    }
    func luminance(x: Int, y: Int) -> Double {
        let c = rgb(x: x, y: y)
        return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
    }
    func grayGain(patch: GrayPatch) throws -> ColorGain {
        guard [patch.x, patch.y, patch.width, patch.height].allSatisfy({ $0.isFinite }),
            patch.x >= 0, patch.y >= 0, patch.width >= 0.02, patch.height >= 0.02,
            patch.x + patch.width <= 1.00001, patch.y + patch.height <= 1.00001
        else { throw MappingError.invalid("Pilih area kartu yang valid") }
        let x0 = Int(patch.x * Double(width))
        let x1 = min(width, Int((patch.x + patch.width) * Double(width)))
        let y0 = Int(patch.y * Double(height))
        let y1 = min(height, Int((patch.y + patch.height) * Double(height)))
        var channels = [[Double](), [Double](), [Double]()]
        var bad = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * width + x) * 4
                if (0..<3).contains(where: { pixels[offset + $0] < 10 || pixels[offset + $0] > 245 }) {
                    bad += 1
                }
                let c = rgb(x: x, y: y)
                for k in 0..<3 { channels[k].append(c[k]) }
            }
        }
        guard channels[0].count >= 64, Double(bad) / Double(channels[0].count) < 0.01 else {
            throw MappingError.invalid(
                "Area kartu terlalu kecil, gelap, atau terpotong highlight. Ambil referensi ulang.")
        }
        let means = channels.map { Self.median($0) }
        // Texture/uniformity is a rejection gate, not automatic recognition of a physical gray card.
        for k in 0..<3 {
            let deviations = channels[k].map { abs($0 - means[k]) }
            guard Self.median(deviations) / means[k] < 0.12 else {
                throw MappingError.invalid(
                    "Area kartu tidak merata. Hindari tepi kartu, bayangan, tulisan, dan glare.")
            }
        }
        let gains = means.map { 0.18 / $0 }
        guard gains.allSatisfy({ $0.isFinite && (0.25...4).contains($0) }) else {
            throw MappingError.invalid("Koreksi kartu melebihi batas aman ±2 EV. Ambil referensi ulang.")
        }
        return ColorGain(red: gains[0], green: gains[1], blue: gains[2])
    }
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
    func clipping(gain: ColorGain) -> Double {
        var clipped = 0
        var count = 0
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let c = rgb(x: x, y: y)
                if (0..<3).contains(where: { c[$0] * gain.values[$0] >= 0.99 }) { clipped += 1 }
                count += 1
            }
        }
        return Double(clipped) / Double(max(1, count))
    }
}
