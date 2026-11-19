import Foundation

enum TestOrtoPreset: String, CaseIterable, Identifiable {
    case walkingHand = "Jalan Kaki (Pegang HP)"
    case walkingPole = "Jalan Kaki (Tongsis/Tinggi)"
    case balcony = "Balkon / Tangga"
    case lowDrone = "Drone Rendah"

    var id: String { rawValue }

    var heightAGL: Double {
        switch self {
        case .walkingHand: return 1.5
        case .walkingPole: return 2.5
        case .balcony: return 5.0
        case .lowDrone: return 20.0
        }
    }

    var speed: Double {
        switch self {
        case .walkingHand: return 0.4
        case .walkingPole: return 0.6
        case .balcony: return 0.8
        case .lowDrone: return 3.0
        }
    }

    var forwardOverlap: Double {
        0.80
    }

    var sideOverlap: Double {
        0.75
    }

    var subtitle: String {
        switch self {
        case .walkingHand: return "1.5 m • 0.4 m/s (~1.4 km/jam)"
        case .walkingPole: return "2.5 m • 0.6 m/s (~2.2 km/jam)"
        case .balcony: return "5.0 m • 0.8 m/s (~2.9 km/jam)"
        case .lowDrone: return "20 m • 3.0 m/s (~10.8 km/jam)"
        }
    }
}

struct TestOrtoOverlayMetrics {
    let gsdMeters: Double
    let footprintWidthMeters: Double
    let footprintAlongMeters: Double
    let forwardStepMeters: Double
    let sideStepMeters: Double
    let rawMaximumInterval: Double
    let recommendedAutoInterval: Double
    let maxSpeedForOneSecondInterval: Double
    let maximumShutterSeconds: Double
    let calibratedFocal: Bool

    var gsdCentimeters: Double { gsdMeters * 100 }
    var gsdMillimeters: Double { gsdMeters * 1000 }

    static func calculate(
        heightAGL: Double,
        speed: Double,
        forwardOverlap: Double,
        sideOverlap: Double,
        capabilities: CameraCapabilities?
    ) -> TestOrtoOverlayMetrics? {
        let widthPixels = Double(capabilities?.width ?? 4032)
        let heightPixels = Double(capabilities?.height ?? 3024)
        let fovDegrees = capabilities?.nominalFieldOfView ?? 65.0
        guard widthPixels > 0, heightPixels > 0,
            heightAGL.isFinite, heightAGL >= 0.3,
            speed.isFinite, speed >= 0.05,
            (0.5...0.95).contains(forwardOverlap),
            (0.5...0.95).contains(sideOverlap),
            fovDegrees.isFinite, (10...170).contains(fovDegrees)
        else { return nil }

        let focalPixels = widthPixels / (2 * tan(fovDegrees * .pi / 360))
        guard
            let base = try? MappingEstimate.calculate(
                heightAGL: heightAGL,
                focalPixels: focalPixels,
                alongPixels: heightPixels,
                speed: speed,
                overlap: forwardOverlap
            )
        else { return nil }

        let footprintWidth = base.gsd * widthPixels
        let footprintAlong = base.footprintAlong
        let forwardStep = footprintAlong * (1 - forwardOverlap)
        let sideStep = footprintWidth * (1 - sideOverlap)
        let clampedAutoInterval = max(1.0, min(3600.0, floor(base.maximumInterval * 10) / 10))
        let maxSpeedAt1s = forwardStep / 1.0

        return TestOrtoOverlayMetrics(
            gsdMeters: base.gsd,
            footprintWidthMeters: footprintWidth,
            footprintAlongMeters: footprintAlong,
            forwardStepMeters: forwardStep,
            sideStepMeters: sideStep,
            rawMaximumInterval: base.maximumInterval,
            recommendedAutoInterval: clampedAutoInterval,
            maxSpeedForOneSecondInterval: maxSpeedAt1s,
            maximumShutterSeconds: base.maximumShutter,
            calibratedFocal: capabilities?.nominalFieldOfView != nil
        )
    }
}

struct TestOrtoCapturedItem: Identifiable {
    let id: UUID
    let sequence: Int
    let kind: String
    let requestedAt: Date
    let imageURL: URL
    let location: GeoSample?
    let attitude: AttitudeSample?
    let fileBytes: Int64
}
