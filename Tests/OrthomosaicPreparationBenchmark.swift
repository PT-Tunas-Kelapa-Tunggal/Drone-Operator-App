// Opt-in benchmark using real photos. Never modifies inputs or runs as part of unit tests.
import CoreGraphics
import CoreImage
import Foundation

@main enum OrthomosaicPreparationBenchmark {
    static func main() throws {
        guard CommandLine.arguments.count == 4, let count = Int(CommandLine.arguments[3]), count > 0 else {
            fatalError("Usage: preparation-benchmark INPUT_IMAGES NEW_OUTPUT_DIRECTORY COUNT")
        }
        let fm = FileManager.default
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !fm.fileExists(atPath: output.path) else { fatalError("Output directory must not exist") }
        let photos = try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(count)
        guard photos.count == count else { fatalError("Insufficient JPEG inputs") }
        let context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        ])
        var results = [[String: Any]]()
        for mode in ["legacy", "optimized"] {
            let run = output.appendingPathComponent(mode)
            let images = run.appendingPathComponent("dataset/images")
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            let start = ProcessInfo.processInfo.systemUptime
            var entries = [[String: Any]]()
            var overrides = [String: Any]()
            var bytes: Int64 = 0
            var reused = 0
            for (index, url) in photos.enumerated() {
                try autoreleasepool {
                    let hash = try DatasetStore.hashFile(url)
                    let photo = OrthomosaicPhoto(url: url, sha256: hash)
                    let prepared = try LocalOrthomosaicProcessor.preparePhoto(
                        url, stem: images.appendingPathComponent(String(format: "image_%05d", index + 1)),
                        gain: nil, context: context, allowOriginalJPEG: mode == "optimized")
                    let preparedHash = try DatasetStore.hashFile(prepared.url)
                    precondition(!prepared.reused || preparedHash == hash)
                    reused += prepared.reused ? 1 : 0
                    bytes +=
                        (try fm.attributesOfItem(atPath: prepared.url.path)[.size] as! NSNumber).int64Value
                    entries.append([
                        "image": prepared.url.lastPathComponent, "source": url.lastPathComponent,
                        "sourceSHA256": hash, "preparedSHA256": preparedHash,
                    ])
                    overrides[prepared.url.lastPathComponent] = LocalOrthomosaicProcessor.exifOverride(
                        photo: photo, properties: prepared.properties)
                }
            }
            let result: [String: Any] = [
                "mode": mode, "count": count, "reused": reused,
                "seconds": ProcessInfo.processInfo.systemUptime - start,
                "preparedBytes": bytes,
            ]
            results.append(result)
            func save(_ value: Any, _ url: URL) throws {
                try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                    .write(to: url, options: .atomic)
            }
            try save(overrides, run.appendingPathComponent("dataset/exif_overrides.json"))
            try save(
                ["version": 2, "images": entries, "normalization": "none", "warnings": []],
                run.appendingPathComponent("request.json"))
            try save(results, output.appendingPathComponent("preparation-benchmark.json"))
            print(
                String(
                    decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
                    as: UTF8.self))
        }
    }
}
