import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision
import simd

struct OverlapExposure {
    // Floating-image pixels -> reference-image pixels, bottom-left coordinates (Vision).
    static func factor(reference: RGBPreview, floating: RGBPreview, transform: simd_float3x3) -> Double? {
        guard reference.width == floating.width, reference.height == floating.height,
            abs(simd_determinant(transform)) > 0.000001
        else { return nil }
        var a = [Double]()
        var b = [Double]()
        var ratios = [Double]()
        var cells = Set<Int>()
        for y in stride(from: 12, to: floating.height - 12, by: 8) {
            for x in stride(from: 12, to: floating.width - 12, by: 8) {
                let point = transform * SIMD3<Float>(Float(x), Float(floating.height - 1 - y), 1)
                guard point.z.isFinite, abs(point.z) > 0.000001 else { continue }
                let rx = Double(point.x / point.z)
                let ry = Double(reference.height - 1) - Double(point.y / point.z)
                guard rx.isFinite, ry.isFinite, rx >= 2, ry >= 2, rx < Double(reference.width - 2),
                    ry < Double(reference.height - 2)
                else { continue }
                let ix = Int(rx.rounded())
                let iy = Int(ry.rounded())
                let ar = reference.rgb(x: ix, y: iy)
                let br = floating.rgb(x: x, y: y)
                guard (ar + br).allSatisfy({ (0.01...0.85).contains($0) }) else { continue }
                let av = reference.luminance(x: ix, y: iy)
                let bv = floating.luminance(x: x, y: y)
                a.append(av)
                b.append(bv)
                ratios.append(log(av / bv))
                cells.insert((y * 3 / floating.height) * 3 + x * 3 / floating.width)
            }
        }
        guard a.count >= 200, cells.count >= 4 else { return nil }
        let gain = exp(RGBPreview.median(ratios))
        guard gain.isFinite, (0.5...2).contains(gain) else { return nil }
        let ma = a.reduce(0, +) / Double(a.count)
        let mb = b.reduce(0, +) / Double(b.count)
        var aa = 0.0
        var bb = 0.0
        var ab = 0.0
        for i in a.indices {
            aa += pow(a[i] - ma, 2)
            bb += pow(b[i] - mb, 2)
            ab += (a[i] - ma) * (b[i] - mb)
        }
        guard sqrt(aa / Double(a.count)) > 0.025, sqrt(bb / Double(b.count)) > 0.015,
            ab / sqrt(aa * bb) > 0.95,
            RGBPreview.median(ratios.map { abs($0 - log(gain)) }) < 0.08
        else { return nil }
        return gain
    }
    // Equalize a global luminance gain for registration ONLY; measurements still use original previews.
    static func alignmentImage(_ preview: RGBPreview) -> CGImage? {
        var luminances = [Double]()
        luminances.reserveCapacity(preview.width * preview.height)
        for y in 0..<preview.height {
            for x in 0..<preview.width { luminances.append(preview.luminance(x: x, y: y)) }
        }
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        guard mean > 0.005 else { return nil }
        let bytes = luminances.map { value -> UInt8 in
            let linear = min(1, max(0, value * 0.18 / mean))
            let encoded = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
            return UInt8(min(255, max(0, (encoded * 255).rounded())))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: preview.width, height: preview.height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: preview.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    static func register(reference: RGBPreview, floating: RGBPreview) -> Double? {
        guard reference.width == floating.width, reference.height == floating.height,
            let target = alignmentImage(floating), let source = alignmentImage(reference)
        else { return nil }
        do {
            let request = VNHomographicImageRegistrationRequest(targetedCGImage: target)
            try VNImageRequestHandler(cgImage: source).perform([request])
            if let transform = request.results?.first?.warpTransform,
                let matched = factor(reference: reference, floating: floating, transform: transform)
            {
                return matched
            }
            let translation = VNTranslationalImageRegistrationRequest(targetedCGImage: target)
            try VNImageRequestHandler(cgImage: source).perform([translation])
            guard let t = translation.results?.first?.alignmentTransform else { return nil }
            let transform = simd_float3x3(
                columns: (
                    SIMD3(Float(t.a), Float(t.b), 0), SIMD3(Float(t.c), Float(t.d), 0),
                    SIMD3(Float(t.tx), Float(t.ty), 1)
                ))
            return factor(reference: reference, floating: floating, transform: transform)
        } catch { return nil }
    }

}
