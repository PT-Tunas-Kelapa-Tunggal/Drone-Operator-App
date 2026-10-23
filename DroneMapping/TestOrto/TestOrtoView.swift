import SwiftUI

enum TestOrtoTab: Hashable {
    case capture
    case datasets
    case companion
}

struct TestOrtoView: View {
    @StateObject private var controller = TestOrtoCameraController()
    @State private var selectedTab: TestOrtoTab = .capture
    @State private var manualCameraExpanded = false
    @State private var expandedMissionID: UUID?
    @State private var companionDependencies: CameraDependencies?

    private let externalModel: CameraViewModel?
    private let externalLink: LocalLink?

    init(model: CameraViewModel? = nil, link: LocalLink? = nil) {
        self.externalModel = model
        self.externalLink = link
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                captureWorkspace
                    .navigationTitle("TestOrto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Text("EKSPERIMENTAL")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                controller.startNewMission()
                            } label: {
                                Label("Misi Baru", systemImage: "plus.circle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(controller.isBusy)
                        }
                    }
            }
            .tabItem {
                Label("TestOrto", systemImage: "viewfinder.circle.fill")
            }
            .tag(TestOrtoTab.capture)

            NavigationStack {
                datasetWorkspace
                    .navigationTitle("Dataset TestOrto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Segarkan") {
                                controller.refreshMissions()
                            }
                        }
                    }
            }
            .tabItem {
                Label("Dataset", systemImage: "photo.stack.fill")
            }
            .tag(TestOrtoTab.datasets)

            Group {
                if let externalModel, let externalLink {
                    ContentView(model: externalModel, link: externalLink)
                } else if let companionDependencies {
                    ContentView(model: companionDependencies.viewModel, link: companionDependencies.link)
                } else {
                    ProgressView("Menyiapkan mode DroneCam…")
                        .onAppear {
                            companionDependencies = CameraDependencies()
                        }
                }
            }
            .tabItem {
                Label("DroneCam", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(TestOrtoTab.companion)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedTab == .capture {
                controller.activateCamera()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .capture:
                controller.activateCamera()
            case .datasets:
                controller.stopAutoCapture()
                controller.refreshMissions()
            case .companion:
                controller.deactivateCamera()
                if externalModel == nil && companionDependencies == nil {
                    companionDependencies = CameraDependencies()
                }
            }
        }
    }

    // MARK: - Tab 1: Standalone Capture Workspace

    private var captureWorkspace: some View {
        ScrollView {
            VStack(spacing: 14) {
                viewfinderSection
                shutterControlBar
                quickActionAndPreviewBar
                overlayCalculatorSection
                cameraAttributesSection
            }
            .padding()
        }
    }

    private var viewfinderSection: some View {
        ZStack {
            CameraPreview(session: controller.session, active: selectedTab == .capture)
                .frame(height: 290)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(
                            controller.isAutoCapturing ? Color.green : Color.white.opacity(0.14),
                            lineWidth: controller.isAutoCapturing ? 2 : 1
                        )
                )

            // Center framing & gray card target reticle
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 96, height: 96)
                .allowsHitTesting(false)

            VStack {
                HStack(spacing: 8) {
                    nadirBadge
                    gpsBadge
                    Spacer()
                    savedCounterBadge
                }
                .padding(12)

                Spacer()

                if let metrics = controller.overlayMetrics {
                    HStack(spacing: 10) {
                        Label(
                            String(format: "Maju %.2f m/foto", metrics.forwardStepMeters),
                            systemImage: "figure.walk"
                        )
                        Text("•")
                        Text(String(format: "Geser jalur %.2f m", metrics.sideStepMeters))
                        Spacer()
                        Text(
                            metrics.gsdCentimeters < 1.0
                                ? String(format: "GSD %.1f mm", metrics.gsdMillimeters)
                                : String(format: "GSD %.2f cm", metrics.gsdCentimeters)
                        )
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var nadirBadge: some View {
        Group {
            if let attitude = controller.currentAttitude {
                Label(
                    String(format: "Nadir %.0f°", attitude.tiltFromNadirDegrees),
                    systemImage: attitude.isOblique ? "exclamationmark.triangle.fill" : "level.fill"
                )
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(attitude.isOblique ? Color.orange : Color.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.7), in: Capsule())
            } else {
                Label("IMU…", systemImage: "gyroscope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
            }
        }
    }

    private var gpsBadge: some View {
        Group {
            if let loc = controller.currentLocation, loc.horizontalAccuracy >= 0 {
                Label(
                    String(format: "GPS ±%.1fm", loc.horizontalAccuracy),
                    systemImage: "location.fill"
                )
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(loc.horizontalAccuracy <= 10 ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.7), in: Capsule())
            } else {
                Label("Mencari GPS…", systemImage: "location.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
            }
        }
    }

    private var savedCounterBadge: some View {
        HStack(spacing: 6) {
            if controller.grayCardLocked {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.cyan)
            }
            Text("\(controller.activeMission?.saved ?? 0) foto")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75), in: Capsule())
    }

    // MARK: - Primary Shutter & Gray Card Bar

    private var shutterControlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // 1. Take Gray Card button
                Button {
                    controller.takeGrayCard()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(
                                systemName: controller.grayCardLocked
                                    ? "checkmark.circle.fill" : "circle.lefthalf.filled"
                            )
                            Text("Gray Card")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        Text(controller.grayCardLocked ? "Terkunci ✓" : "Ambil 18%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.bordered)
                .tint(controller.grayCardLocked ? .cyan : .secondary)
                .disabled(controller.isBusy || controller.isAutoCapturing)

                // 2. Main Manual TAKE Photo button
                Button {
                    controller.takePhoto()
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                            Text("TAKE")
                                .font(.title3.weight(.bold))
                        }
                        Text("Foto #\((controller.activeMission?.saved ?? 0) + 1)")
                            .font(.caption2.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(controller.isBusy)

                // 3. Auto-Interval Walking Capture toggle
                Button {
                    controller.toggleAutoCapture()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(
                                systemName: controller.isAutoCapturing
                                    ? "stop.circle.fill" : "timer"
                            )
                            Text(controller.isAutoCapturing ? "Stop" : "Auto")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        Text(String(format: "Tiap %.1fs", controller.autoInterval))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.bordered)
                .tint(controller.isAutoCapturing ? .orange : .blue)
            }

            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Quick Lock, Thumbnails, & Session Controls

    private var quickActionAndPreviewBar: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        controller.lockFocusAndExposure()
                    } label: {
                        Label(
                            controller.focusAndExposureLocked
                                ? "Kunci Ulang Fokus & Exposure" : "Kunci Fokus & Exposure",
                            systemImage: controller.focusAndExposureLocked ? "lock.fill" : "scope"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(controller.focusAndExposureLocked ? .green : .accentColor)
                    .disabled(controller.isBusy || controller.isAutoCapturing)

                    Spacer()

                    if (controller.activeMission?.saved ?? 0) > 0,
                        controller.activeMission?.phase != .completed
                    {
                        Button {
                            controller.finishCurrentMission()
                        } label: {
                            Label("Selesai Misi", systemImage: "flag.checkered")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(controller.isBusy)
                    }
                }

                if controller.grayCardThumbnail != nil || controller.lastMappingThumbnail != nil {
                    HStack(spacing: 12) {
                        if let grayThumb = controller.grayCardThumbnail {
                            HStack(spacing: 8) {
                                Image(uiImage: grayThumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gray Card")
                                        .font(.caption.weight(.semibold))
                                    Text("\(Int(controller.cameraSettings.temperature))K terkunci")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let mapThumb = controller.lastMappingThumbnail {
                            HStack(spacing: 8) {
                                Image(uiImage: mapThumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Foto Terakhir (#\(controller.activeMission?.saved ?? 0))")
                                        .font(.caption.weight(.semibold))
                                    if let blocker = controller.lastAssessment?.blocker {
                                        Text(blocker)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .lineLimit(1)
                                    } else if let sharp = controller.lastSharpness {
                                        Text(
                                            String(
                                                format: "Ketajaman %.0f • Area tekstur %d/5",
                                                sharp.scores.first ?? 0, sharp.texturedPatches
                                            )
                                        )
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Height, Walking Speed & Overlay Calculator Section

    private var overlayCalculatorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Tinggi, Kecepatan & Overlay", systemImage: "square.stack.3d.down.right.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let metrics = controller.overlayMetrics {
                        Text(
                            String(
                                format: "Cakupan %.2f × %.2f m",
                                metrics.footprintWidthMeters, metrics.footprintAlongMeters
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                // Preset Chips for Walking vs Drone
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TestOrtoPreset.allCases) { preset in
                            let selected =
                                abs(controller.heightAGL - preset.heightAGL) < 0.05
                                && abs(controller.speed - preset.speed) < 0.05
                            Button {
                                controller.applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.rawValue)
                                        .font(.caption.weight(.semibold))
                                    Text(preset.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Height AGL Control (0.5m walking up to 100m)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tinggi Kamera ke Tanah")
                            .font(.caption)
                        Spacer()
                        Button("-0.1m") {
                            controller.heightAGL = max(0.5, (controller.heightAGL * 10 - 1).rounded() / 10)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        Text(
                            controller.heightAGL < 10
                                ? String(format: "%.1f m", controller.heightAGL)
                                : String(format: "%.0f m", controller.heightAGL)
                        )
                        .font(.caption.weight(.bold).monospacedDigit())
                        .frame(minWidth: 50, alignment: .center)
                        Button("+0.1m") {
                            controller.heightAGL = min(100, (controller.heightAGL * 10 + 1).rounded() / 10)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                    Slider(
                        value: $controller.heightAGL,
                        in: 0.5...50.0,
                        step: 0.1
                    )
                }

                // Walking / Movement Speed Control
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Kecepatan Jalan / Gerak")
                            .font(.caption)
                        Spacer()
                        Button("-0.1") {
                            controller.speed = max(0.1, (controller.speed * 10 - 1).rounded() / 10)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        Text(
                            String(
                                format: "%.1f m/s (%.1f km/j)",
                                controller.speed, controller.speed * 3.6
                            )
                        )
                        .font(.caption.weight(.bold).monospacedDigit())
                        Button("+0.1") {
                            controller.speed = min(15.0, (controller.speed * 10 + 1).rounded() / 10)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                    Slider(
                        value: $controller.speed,
                        in: 0.1...10.0,
                        step: 0.1
                    )
                }

                // Forward & Side Overlap Sliders
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Overlap Maju")
                            Spacer()
                            Text("\(Int((controller.forwardOverlap * 100).rounded()))%")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: $controller.forwardOverlap, in: 0.60...0.90, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Overlap Samping")
                            Spacer()
                            Text("\(Int((controller.sideOverlap * 100).rounded()))%")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: $controller.sideOverlap, in: 0.60...0.90, step: 0.05)
                    }
                }

                // Calculated Overlay Guidance Grid
                if let metrics = controller.overlayMetrics {
                    Divider()
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        metricCell(
                            title: "JARAK MAJU / FOTO",
                            value: String(format: "%.2f m", metrics.forwardStepMeters),
                            subtitle: "Ambil TAKE tiap maju jarak ini"
                        )
                        metricCell(
                            title: "GESER JALUR SAMPING",
                            value: String(format: "%.2f m", metrics.sideStepMeters),
                            subtitle: "Jarak geser saat pindah baris"
                        )
                        metricCell(
                            title: "INTERVAL MAKSIMAL",
                            value: String(format: "%.2f dtk", metrics.rawMaximumInterval),
                            subtitle: metrics.rawMaximumInterval < 1.0
                                ? String(
                                    format: "Untuk auto 1s, jalan ≤ %.2f m/s",
                                    metrics.maxSpeedForOneSecondInterval
                                )
                                : "Interval aman untuk Auto"
                        )
                        metricCell(
                            title: "BATAS SHUTTER & GSD",
                            value: String(
                                format: "≤ 1/%.0f s",
                                max(1, 1.0 / max(0.00001, metrics.maximumShutterSeconds))
                            ),
                            subtitle: metrics.gsdCentimeters < 1.0
                                ? String(format: "Detail %.1f mm/px", metrics.gsdMillimeters)
                                : String(format: "Detail %.2f cm/px", metrics.gsdCentimeters)
                        )
                    }

                    HStack {
                        Stepper(
                            value: $controller.autoInterval,
                            in: 1.0...30.0,
                            step: 0.5
                        ) {
                            Text(String(format: "Interval Auto: %.1f dtk", controller.autoInterval))
                                .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        Button("Sesuaikan") {
                            controller.applyRecommendedIntervalAndShutter()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func metricCell(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Camera Attributes & Manual Overrides Section

    private var cameraAttributesSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $manualCameraExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Ukur exposure otomatis saat Take Gray Card",
                        isOn: $controller.useGuidedExposure
                    )
                    .font(.caption)

                    HStack {
                        Text("Nama Misi")
                            .font(.caption)
                        TextField("TestOrto Lapangan", text: $controller.missionName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    let minISO = controller.capabilities?.minISO ?? 32
                    let maxISO = controller.capabilities?.maxISO ?? 1600
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("ISO")
                            Spacer()
                            Text("\(Int(controller.cameraSettings.iso))")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: $controller.cameraSettings.iso,
                            in: minISO...maxISO,
                            step: 10
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Shutter Speed")
                            Spacer()
                            Text(
                                String(
                                    format: "1/%.0f s (%.2f ms)",
                                    1.0 / max(0.00001, controller.cameraSettings.shutterSeconds),
                                    controller.cameraSettings.shutterSeconds * 1000
                                )
                            )
                            .monospacedDigit()
                        }
                        .font(.caption)
                        HStack(spacing: 6) {
                            ForEach([2000.0, 1000.0, 500.0, 250.0, 125.0], id: \.self) { denom in
                                Button("1/\(Int(denom))") {
                                    controller.cameraSettings.shutterSeconds = 1.0 / denom
                                }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .tint(
                                    abs(controller.cameraSettings.shutterSeconds - (1.0 / denom)) < 0.0001
                                        ? .accentColor : .secondary
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Fokus Lensa (0 dekat – 1 jauh)")
                            Spacer()
                            Text(String(format: "%.2f", controller.cameraSettings.lensPosition))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: $controller.cameraSettings.lensPosition, in: 0.0...1.0, step: 0.02)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("White Balance (Kelvin)")
                            Spacer()
                            Text("\(Int(controller.cameraSettings.temperature))K")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: $controller.cameraSettings.temperature, in: 2500...8500, step: 100)
                    }

                    if controller.capabilities?.bayerRAW == true {
                        Toggle("Simpan Bayer RAW (.dng) + JPEG", isOn: $controller.cameraSettings.raw)
                            .font(.caption)
                    }

                    Button {
                        controller.applyManualSettings()
                    } label: {
                        Label("Terapkan & Kunci Parameter Manual", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isBusy)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Label("Atribut Kamera & Kalibrasi", systemImage: "camera.aperture")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(
                        String(
                            format: "ISO %.0f • 1/%.0f • %dK",
                            controller.cameraSettings.iso,
                            1.0 / max(0.00001, controller.cameraSettings.shutterSeconds),
                            Int(controller.cameraSettings.temperature)
                        )
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tab 2: Dataset Inspector & Export/Transfer

    private var datasetWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "Dataset yang diambil dari TestOrto disimpan dalam format standar misi (termasuk EXIF GPS, sudut Nadir, dan referensi Gray Card). Anda dapat membagikannya via AirDrop/Files ke Mac atau mentransfer lewat DroneCam."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if controller.savedMissions.isEmpty {
                    GroupBox {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Belum ada dataset misi")
                                .font(.headline)
                            Text("Ambil foto di tab TestOrto untuk mulai menguji orthomosaic.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                } else {
                    ForEach(controller.savedMissions) { mission in
                        missionCard(mission)
                    }
                }
            }
            .padding()
        }
    }

    private func missionCard(_ mission: MissionRecord) -> some View {
        let items = controller.capturedItems(for: mission.id)
        let hasGrayCard = items.contains(where: { $0.kind == "calibration-before" })
        let mappingCount = items.filter { $0.kind == "mapping" }.count
        let obliqueCount = items.filter { $0.kind == "mapping" && $0.attitude?.isOblique == true }.count
        let gpsCount = items.filter { $0.kind == "mapping" && $0.location != nil }.count
        let folderURL = controller.missionFolderURL(mission.id)

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.plan.name)
                            .font(.headline)
                        Text(mission.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(mission.phase.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                }

                HStack(spacing: 10) {
                    Label("\(mappingCount) foto", systemImage: "photo.stack")
                    Label(
                        hasGrayCard ? "Gray Card ✓" : "Tanpa Gray Card",
                        systemImage: hasGrayCard ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(hasGrayCard ? .cyan : .secondary)
                    Label("GPS \(gpsCount)/\(mappingCount)", systemImage: "location.fill")
                        .foregroundStyle(gpsCount == mappingCount && mappingCount > 0 ? .green : .orange)
                }
                .font(.caption2)

                if obliqueCount > 0 {
                    Text(
                        "\(obliqueCount) foto memiliki kemiringan >12° dari nadir (dapat difilter otomatis di Mac)."
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 8) {
                    ShareLink(item: folderURL) {
                        Label("Bagikan / AirDrop Misi", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)

                    if let externalModel, externalModel.canTransfer {
                        Button("Kirim ke Mac") {
                            externalModel.transferToMac(mission.id)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        controller.deleteMission(mission.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                if !items.isEmpty {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedMissionID == mission.id },
                            set: { expandedMissionID = $0 ? mission.id : nil }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items) { item in
                                HStack(spacing: 8) {
                                    Text(
                                        item.kind == "calibration-before"
                                            ? "GRAY" : String(format: "#%03d", item.sequence)
                                    )
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(item.kind == "calibration-before" ? .cyan : .primary)
                                    .frame(width: 44, alignment: .leading)

                                    if let loc = item.location {
                                        Text(String(format: "GPS ±%.1fm", loc.horizontalAccuracy))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Tanpa GPS")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }

                                    if let att = item.attitude {
                                        Text(String(format: "Nadir %.0f°", att.tiltFromNadirDegrees))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(att.isOblique ? .orange : .secondary)
                                    }

                                    Spacer()

                                    ShareLink(item: item.imageURL) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Rincian \(items.count) berkas tangkapan")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
