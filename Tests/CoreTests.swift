import CoreGraphics
import Foundation
import ImageIO
import MultipeerConnectivity

@main enum CoreTests {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        func rejects(_ work: () throws -> Void) {
            do {
                try work()
                preconditionFailure("Expected rejection")
            } catch { assertions += 1 }
        }
        let estimate = try MappingEstimate.calculate(
            heightAGL: 80, focalPixels: 3000, alongPixels: 3024, speed: 5, overlap: 0.8)
        check(abs(estimate.gsd - 0.0266666667) < 0.000001, "GSD units")
        check(abs(estimate.maximumInterval - 3.2256) < 0.00001, "Overlap interval")
        check(abs(estimate.maximumShutter - 0.0026666667) < 0.000001, "Blur budget")
        rejects {
            _ = try MappingEstimate.calculate(
                heightAGL: 0, focalPixels: 3000, alongPixels: 3024, speed: 5, overlap: 0.8)
        }
        rejects {
            _ = try MappingEstimate.calculate(
                heightAGL: 80, focalPixels: 3000, alongPixels: 3024, speed: 0, overlap: 0.8)
        }
        rejects {
            _ = try MappingEstimate.calculate(
                heightAGL: 80, focalPixels: 3000, alongPixels: 3024, speed: 5, overlap: 1)
        }
        let exposure = try GuidedAcquisition.exposure(
            meteredISO: 100, meteredShutter: 0.002, preferredShutter: 0.001, minISO: 32, maxISO: 800,
            minShutter: 0.00001)
        check(
            exposure.iso == 200 && abs(exposure.shutter - 0.001) < 0.000001,
            "Meter product preserves exposure while enforcing fast shutter")
        let bright = try GuidedAcquisition.exposure(
            meteredISO: 32, meteredShutter: 0.0001, preferredShutter: 0.001, minISO: 32, maxISO: 800,
            minShutter: 0.00001)
        check(
            bright.iso == 32 && abs(bright.shutter - 0.0001) < 0.000001,
            "Bright card shortens shutter instead of clipping ISO below hardware minimum")
        rejects {
            _ = try GuidedAcquisition.exposure(
                meteredISO: 1000, meteredShutter: 0.01, preferredShutter: 0.001, minISO: 32, maxISO: 800,
                minShutter: 0.00001)
        }
        rejects {
            _ = try GuidedAcquisition.exposure(
                meteredISO: .nan, meteredShutter: 0.01, preferredShutter: 0.001, minISO: 32, maxISO: 800,
                minShutter: 0.00001)
        }
        rejects {
            _ = try GuidedAcquisition.exposure(
                meteredISO: 32, meteredShutter: 0.0000001, preferredShutter: 0.001, minISO: 32, maxISO: 800,
                minShutter: 0.00001)
        }
        check(
            PreviewAssessment.pixels([0, 0, 0, 255])?.blocker != nil,
            "Black preview must not pass exposure review")
        check(
            PreviewAssessment.pixels([255, 255, 255, 255])?.blocker != nil,
            "Clipped preview must not pass exposure review")
        check(
            PreviewAssessment.pixels([128, 128, 128, 255])?.blocker == nil,
            "Neutral preview is only a basic exposure pass")
        check(PreviewAssessment.pixels([]) == nil, "Empty preview cannot produce quality evidence")
        let guidedCaps = CameraCapabilities(
            model: "test", minISO: 32, maxISO: 1600, minShutter: 0.00001, maxShutter: 1, width: 4032,
            height: 3024, bayerRAW: true, manualExposure: true, manualFocus: true, manualWB: true,
            nominalFieldOfView: 65)
        var guidedDraft = MissionPlan()
        guidedDraft.guidedMode = true
        guidedDraft.durationSeconds = 600
        let guidedPlan = try GuidedAcquisition.plan(
            guidedDraft, geometry: SurveyGeometry(), capabilities: guidedCaps)
        check(
            guidedPlan.photoLimit == Int(ceil(600 / guidedPlan.interval)), "Duration determines photo count")
        check(
            guidedPlan.camera.shutterSeconds <= 0.001 && guidedPlan.interval >= 1,
            "Guided planning preserves shutter and scheduler bounds")
        guidedDraft.durationSeconds = .infinity
        rejects {
            _ = try GuidedAcquisition.plan(guidedDraft, geometry: SurveyGeometry(), capabilities: guidedCaps)
        }
        guidedDraft.durationSeconds = 600
        var fast = SurveyGeometry()
        fast.speed = 100
        rejects { _ = try GuidedAcquisition.plan(guidedDraft, geometry: fast, capabilities: guidedCaps) }
        var tooHigh = SurveyGeometry()
        tooHigh.heightAGL = 1000
        rejects { _ = try GuidedAcquisition.plan(guidedDraft, geometry: tooHigh, capabilities: guidedCaps) }
        let flat = SharpnessAssessment.score([UInt8](repeating: 128, count: 64), width: 8, height: 8)!
        let edgePixels: [UInt8] = (0..<64).map { $0 % 8 < 4 ? 0 : 255 }
        let edge = SharpnessAssessment.score(edgePixels, width: 8, height: 8)!
        check(
            flat.energy == 0 && edge.energy > flat.energy && edge.contrast > flat.contrast,
            "Detail metric distinguishes an edge from a flat patch")
        check(
            SharpnessAssessment.score([], width: 8, height: 8) == nil,
            "Invalid patch does not produce a score")
        var focused = CameraSettings()
        focused.lensPosition = 0.72
        check(
            focused.sameRadiometry(as: CameraSettings()), "Focus change preserves exposure and color settings"
        )
        focused.iso = 200
        check(
            !focused.sameRadiometry(as: CameraSettings()), "Exposure change invalidates radiometric reference"
        )
        let countdown = StartCountdown(now: 100)
        check(countdown.remaining(now: 100) == 3, "Countdown starts at three")
        check(countdown.remaining(now: 101) == 2, "Countdown second two")
        check(countdown.remaining(now: 102) == 1, "Countdown second one")
        check(countdown.remaining(now: 102.999) == 1, "Never start before deadline")
        check(countdown.remaining(now: 103) == 0, "Start at deadline")
        check(countdown.remaining(now: 105) == 0, "Delayed timer cannot go negative")
        var delayedSchedule = CaptureSchedule(next: countdown.deadline, interval: 3)
        check(delayedSchedule.consume(now: 102.999) == nil, "No photo during countdown")
        check(delayedSchedule.consume(now: 103) == 0, "First photo follows countdown")
        var schedule = CaptureSchedule(next: 10, interval: 3)
        check(schedule.consume(now: 9) == nil, "No early shot")
        check(schedule.consume(now: 10) == 0, "Initial shot")
        check(schedule.consume(now: 20) == 2, "Missed slots must be counted")
        check(schedule.next == 22, "No catch-up bursts")
        check(schedule.consume(now: 20) == nil, "No duplicate slot")
        var plan = MissionPlan()
        try plan.validate()
        plan.interval = .nan
        rejects { try plan.validate() }
        plan.interval = 3
        plan.photoLimit = 0
        rejects { try plan.validate() }
        plan.photoLimit = 2
        plan.camera.iso = .infinity
        rejects { try plan.validate() }
        plan.camera.iso = 100
        plan.camera.whiteBalanceGains = [1, 2]
        rejects { try plan.validate() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DatasetStore(root: root)
        let mission = MissionRecord(plan: MissionPlan())
        try store.write(mission)
        check(store.records().count == 1, "Manifest readable")
        check(store.records()[0].id == mission.id, "Mission identity round-trip")
        let hash = DatasetStore.hash(Data("abc".utf8))
        check(
            hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA256 standard vector")
        let manifest = store.directory(mission.id).appendingPathComponent("mission.json")
        let streamingHash = try DatasetStore.hashFile(manifest)
        let dataHash = try DatasetStore.hash(Data(contentsOf: manifest))
        check(streamingHash == dataHash, "Streaming file checksum")
        let validName = "\(mission.id)|\(hash)|capture/image.dng"
        let (path, receivedHash) = try DatasetStore.destination(resource: validName, root: root)
        check(path.path.hasPrefix(store.directory(mission.id).path + "/"), "Destination confined")
        check(receivedHash == hash, "Checksum parsed")
        for path in ["../outside", "/absolute", "a/../../b", ".pending/image.dng", "a\\b", "a:b", ""] {
            rejects {
                _ = try DatasetStore.destination(resource: "\(mission.id)|\(hash)|\(path)", root: root)
            }
        }
        let hidden = store.directory(mission.id).appendingPathComponent(".partial")
        try Data().write(to: hidden)
        let files = try store.files(mission.id)
        check(files.count == 1, "Partial files never exported")
        let packet = Packet(command: Command(action: .start, plan: MissionPlan()))
        let roundTrip = try JSONDecoder().decode(Packet.self, from: JSONEncoder().encode(packet))
        check(roundTrip.command?.id == packet.command?.id, "Retry keeps command identity")
        check(roundTrip.version == 1, "Protocol version")
        var interrupted = mission
        interrupted.phase = .countdown
        interrupted.saved = 99
        try store.write(interrupted)
        try store.recoverInterrupted()
        check(store.records()[0].phase == .paused, "Restart never resumes shutter")
        check(store.records()[0].saved == 0, "Recovery reconciles committed captures")
        var reconnect = ReconnectPolicy()
        check(reconnect.canAttempt(now: 0), "Reconnect can start immediately")
        reconnect.didAttempt(now: 0)
        check(!reconnect.canAttempt(now: 11.99), "Discovery events cannot flood invitations")
        check(reconnect.canAttempt(now: 12), "Retry after timeout plus backoff")
        reconnect.didAttempt(now: 12)
        check(reconnect.nextAttemptAt == 26, "Retry backoff increases")
        for _ in 0..<10 { reconnect.didAttempt(now: 100) }
        check(reconnect.nextAttemptAt == 125, "Backoff stays bounded")
        reconnect.didConnect()
        check(
            reconnect.canAttempt(now: 0) && reconnect.attempts == 0,
            "Successful reconnect resets retry policy")
        let suiteName = "DroneMappingTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = PeerIdentityStore(camera: true, defaults: defaults)
        let localPeer = identity.localPeer()
        check(
            PeerIdentityStore(camera: true, defaults: defaults).localPeer() == localPeer,
            "Local peer survives recreation")
        check(identity.approvedPeer == nil, "New installs never approve unknown peers")
        let approved = MCPeerID(displayName: "Ground station")
        identity.approve(approved)
        check(
            PeerIdentityStore(camera: true, defaults: defaults).approvedPeer == approved,
            "Pairing persists across recreation")
        check(
            identity.approvedPeer != MCPeerID(displayName: "Ground station"),
            "Same display name cannot substitute approved peer")
        check(
            PeerIdentityStore(camera: false, defaults: defaults).approvedPeer == nil,
            "Camera and controller roles isolated")
        let statusRequest = Packet(replyRequestID: UUID())
        let decodedRequest = try JSONDecoder().decode(Packet.self, from: JSONEncoder().encode(statusRequest))
        check(
            decodedRequest.command == nil && decodedRequest.replyRequestID == statusRequest.replyRequestID,
            "ACK recovery never contains a mission command")
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        check(
            GeoSample.normalizedAge(
                requestedAt: baseDate, sampleTimestamp: baseDate.addingTimeInterval(0.3)) == 0,
            "Sub-second negative clock jitter between CLLocation and capture request is clamped to zero")
        check(
            GeoSample.normalizedAge(
                requestedAt: baseDate, sampleTimestamp: baseDate.addingTimeInterval(2.0)) < 0,
            "Large future clock anomalies remain rejected")
        let nadir = AttitudeSample.fromGravity(x: 0, y: 0, z: -1, roll: 0, pitch: 0, yaw: 0)
        check(abs(nadir.tiltFromNadirDegrees) < 0.001 && !nadir.isOblique, "Flat nadir camera has 0° tilt")
        let banked = AttitudeSample.fromGravity(x: 0.35, y: 0, z: -0.9367, roll: 0.35, pitch: 0, yaw: 0)
        check(banked.tiltFromNadirDegrees > 12 && banked.isOblique, "Banking turn >12° is flagged as oblique")
        var pixel: [UInt8] = [120, 130, 140, 255]
        let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cgImg = ctx.makeImage()!
        let rawJPEG = NSMutableData()
        let dest = CGImageDestinationCreateWithData(rawJPEG, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImg, nil)
        check(CGImageDestinationFinalize(dest), "Create baseline sRGB JPEG")
        let sampleGeo = GeoSample(
            latitude: -6.914744, longitude: 107.609810, altitudeMSL: 768.5,
            horizontalAccuracy: 3.2, verticalAccuracy: 4.5, timestamp: baseDate)
        let taggedJPEG = sampleGeo.embeddingEXIF(into: rawJPEG as Data)
        let taggedSource = CGImageSourceCreateWithData(taggedJPEG as CFData, nil)!
        let taggedProps = CGImageSourceCopyPropertiesAtIndex(taggedSource, 0, nil) as? [String: Any]
        let gpsDict = taggedProps?[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        check(
            (gpsDict?[kCGImagePropertyGPSLatitudeRef as String] as? String) == "S"
                && (gpsDict?[kCGImagePropertyGPSLongitudeRef as String] as? String) == "E"
                && abs(((gpsDict?[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue ?? 0) - 6.914744) < 0.0001
                && abs(((gpsDict?[kCGImagePropertyGPSHPositioningError as String] as? NSNumber)?.doubleValue ?? 0) - 3.2) < 0.0001,
            "Lossless EXIF GPS embedding writes latitude, longitude, hemisphere refs, and horizontal positioning error"
        )
        assertions += WorkflowPressureTests.run()
        assertions += try DatasetLayoutTests.run()
        print("PASS: \(assertions) core assertions")
    }
}
