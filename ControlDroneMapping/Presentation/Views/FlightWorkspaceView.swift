import AppKit
import MapKit
import SwiftUI

// MARK: - Apple Design Floating Card Modifier

private struct FlightDeckFloatingCard: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // System frosted material for native blur
                    Rectangle().fill(.regularMaterial)
                    // High-opacity neutral backing so terrain colors never distort text contrast
                    Color(NSColor.windowBackgroundColor).opacity(0.88)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 5)
    }
}

extension View {
    fileprivate func flightDeckCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(FlightDeckFloatingCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Flight Workspace View

/// Tab 3 (Penerbangan): QGC-inspired edge-to-edge Map-first flight deck with
/// rotating live drone position, compact bottom-left telemetry HUD, and safety-first
/// hold-to-confirm flight commands. Follows Apple Human Interface Guidelines.
struct FlightWorkspaceView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    @ObservedObject var planner: FlightPlannerViewModel
    let mission: SavedMission?
    @Binding var activeTab: ReviewTab

    @ObservedObject var engineManager = QGCEngineManager.shared

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingCommandMenu = false
    @State private var showingSensorDetails = false
    @State private var commandError: String? = nil
    @State private var showingCommandAlert = false
    @State private var followDrone = true
    @State private var visibleAlertMessage: String? = nil
    @State private var lastPresentedAlertKey: String? = nil
    @State private var alertDismissTask: Task<Void, Never>? = nil

    private var activeDrone: ConnectedDrone? {
        engineManager.activeVehicle
    }

    private var flightPath: [CLLocationCoordinate2D] {
        planner.flightTrail(for: mission?.id ?? planner.draft.missionID).map(\.clCoordinate)
    }

    private var isMissionChecklistComplete: Bool {
        planner.draft.isPlanLocked
            || (planner.isSOPChecklistComplete && (model.geometry.reviewed || planner.reviewed))
    }

    /// Pre-flight ground-to-air commands (Arming from disarmed, Takeoff from ground)
    private var canExecuteFlightCommands: Bool {
        guard let drone = activeDrone else { return false }
        return drone.isReachable && isMissionChecklistComplete
    }

    /// In-flight and safety recovery commands (Hold/Loiter, RTL, Land, Disarm, Resume/Start Mission while armed)
    /// Following QGC's GuidedActionsController pattern, an armed or flying vehicle never blocks operator control on checklists.
    private var canExecuteActiveOrRecoveryCommands: Bool {
        guard let drone = activeDrone, drone.isReachable else { return false }
        return drone.armed || drone.flying || isMissionChecklistComplete
    }

    private var boundaryCoordinates: [CLLocationCoordinate2D] {
        let routeBoundary = planner.draft.waypoints.filter { $0.coordinate.isValid }.map(\.coordinate.clCoordinate)
        if routeBoundary.count >= 3 {
            return routeBoundary
        }
        if let missionArea = mission?.area, missionArea.coordinates.count >= 3 {
            return missionArea.coordinates
        }
        return []
    }

    private var surveyTransectCoordinates: [CLLocationCoordinate2D] {
        planner.draft.visualTransects.map(\.clCoordinate)
    }

    private var homeCoordinate: CLLocationCoordinate2D? {
        guard let home = planner.draft.home, home.isValid else { return nil }
        return home.clCoordinate
    }

    private var entryCoordinate: CLLocationCoordinate2D? {
        guard let first = planner.draft.visualTransects.first, first.isValid else { return nil }
        return first.clCoordinate
    }

    private var exitCoordinate: CLLocationCoordinate2D? {
        guard planner.draft.visualTransects.count > 1,
            let last = planner.draft.visualTransects.last,
            last.isValid
        else { return nil }
        return last.clCoordinate
    }

    private var droneLiveCoordinate: CLLocationCoordinate2D? {
        guard let drone = activeDrone,
            drone.telemetry.latitude != 0,
            drone.telemetry.longitude != 0
        else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: drone.telemetry.latitude,
            longitude: drone.telemetry.longitude
        )
    }

    var body: some View {
        ZStack {
            // 1. Edge-to-edge Apple Maps Satellite Background
            mapLayer
                .edgesIgnoringSafeArea(.all)

            // 2. Floating Overlays
            VStack(spacing: 0) {
                topFlightBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer()

                bottomControlsRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }

            // 3. Slide-out Flight Commands Palette (Top-Right)
            if showingCommandMenu {
                HStack {
                    Spacer()
                    VStack {
                        commandPalette
                            .padding(.trailing, 16)
                            .padding(.top, 64)
                        Spacer()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingCommandMenu)
        .alert("Perintah Ditolak oleh Drone", isPresented: $showingCommandAlert) {
            Button("Tutup", role: .cancel) { }
        } message: {
            Text(commandError ?? "Terjadi kesalahan saat mengeksekusi perintah pada wahana.")
        }
        .onAppear {
            if let mission, planner.draft.missionID != mission.id {
                planner.open(
                    farm: mission.area,
                    name: "Rute " + mission.plan.name,
                    altitude: model.geometry.heightAGL,
                    speed: model.geometry.speed,
                    missionID: mission.id
                )
            }
            initializeMapRegion()
            presentAndScheduleAlertDismissal(for: activeDrone?.latestAlertKey)
        }
        .onDisappear {
            alertDismissTask?.cancel()
            alertDismissTask = nil
        }
        .onChange(of: activeDrone?.latestAlertKey) { _, newKey in
            presentAndScheduleAlertDismissal(for: newKey)
        }
        .onChange(of: activeDrone?.telemetry.latitude) { _, _ in
            updateDronePositionAndTrail()
        }
        .onChange(of: activeDrone?.telemetry.longitude) { _, _ in
            updateDronePositionAndTrail()
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            // 1. Geofence safety envelope (dashed orange/red, matching 1. Rencana)
            if let safety = planner.draft.safetyResult, safety.enabled {
                let fenceColor: Color = (safety.coversMission && safety.ceilingOk) ? .orange : .red
                switch safety.type {
                case .polygon:
                    let fenceCoords = safety.polygonCoordinates.filter(\.isValid).map(\.clCoordinate)
                    if fenceCoords.count >= 3 {
                        MapPolygon(coordinates: fenceCoords)
                            .stroke(fenceColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .foregroundStyle(fenceColor.opacity(0.08))
                    }
                case .circle:
                    if let center = safety.circleCenter, center.isValid, safety.circleRadiusMeters > 0 {
                        MapCircle(center: center.clCoordinate, radius: safety.circleRadiusMeters)
                            .stroke(fenceColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .foregroundStyle(fenceColor.opacity(0.08))
                    }
                }
            }

            // 2. Operator-configured survey boundary polygon (green, matching 1. Rencana)
            if boundaryCoordinates.count >= 3 {
                MapPolygon(coordinates: boundaryCoordinates)
                    .stroke(Color.green, lineWidth: 2)
                    .foregroundStyle(Color.green.opacity(0.18))
            }

            // 3. Planned ingress/egress transit lines (Home -> First Transect & Exit -> Home)
            if !surveyTransectCoordinates.isEmpty,
                let home = planner.draft.home, home.isValid
            {
                if let first = planner.draft.visualTransects.first, first.isValid {
                    MapPolyline(coordinates: [home.clCoordinate, first.clCoordinate])
                        .stroke(Color.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                if let last = planner.draft.visualTransects.last, last.isValid, planner.draft.returnToHome {
                    MapPolyline(coordinates: [last.clCoordinate, home.clCoordinate])
                        .stroke(Color.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }

            // 4. Planned survey transect lines
            if !surveyTransectCoordinates.isEmpty {
                MapPolyline(coordinates: surveyTransectCoordinates)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            }

            // 5. Historical live flight trail (blue/cyan trailing line)
            if flightPath.count > 1 {
                MapPolyline(coordinates: flightPath)
                    .stroke(Color.cyan, lineWidth: 2.8)
            }

            // 6. Entry (E) marker (read-only at first transect waypoint)
            if let entry = entryCoordinate {
                Annotation("Entry", coordinate: entry) {
                    routePinBadge("E", color: .cyan)
                }
            }

            // 7. Exit (X) marker (read-only at last transect waypoint)
            if let exit = exitCoordinate {
                Annotation("Exit", coordinate: exit) {
                    routePinBadge("X", color: .cyan)
                }
            }

            // 8. Home (H) marker
            if let home = homeCoordinate {
                Annotation("Home", coordinate: home) {
                    routePinBadge("H", color: .green)
                }
            }

            // 9. Live Drone Annotation with rotating heading
            if let coord = droneLiveCoordinate, let drone = activeDrone {
                Annotation(
                    "Drone #\(drone.id)",
                    coordinate: coord,
                    anchor: .center
                ) {
                    liveDroneAnnotationView(drone)
                }
            }
        }
        .mapStyle(.imagery)
        .mapControls {
            MapCompass()
            MapZoomStepper()
            MapScaleView()
        }
    }

    private func routePinBadge(_ label: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func liveDroneAnnotationView(_ drone: ConnectedDrone) -> some View {
        ZStack {
            // Pulse circle
            Circle()
                .fill(droneStatusColor(drone).opacity(0.22))
                .frame(width: 50, height: 50)

            Circle()
                .stroke(droneStatusColor(drone), lineWidth: 1.5)
                .frame(width: 36, height: 36)

            // Drone heading indicator (arrow rotating to exact heading)
            Image(systemName: "location.north.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(droneStatusColor(drone))
                .rotationEffect(.degrees(drone.telemetry.heading))
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)

            // Altitude tag
            Text(String(format: "%.0fm", drone.telemetry.altitudeRelative))
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.black.opacity(0.75), in: Capsule())
                .offset(y: 25)
        }
    }

    // MARK: - Top Flight Bar

    private var topFlightBar: some View {
        ZStack {
            // Center Drone Status & Multi-Drone Switcher Capsule
            if let drone = activeDrone {
                HStack(spacing: 12) {
                    // Connection Dot & Drone ID
                    HStack(spacing: 7) {
                        Circle()
                            .fill(droneStatusColor(drone))
                            .frame(width: 8, height: 8)

                        if engineManager.vehicles.count > 1 {
                            Menu {
                                ForEach(engineManager.vehicles) { v in
                                    Button {
                                        engineManager.selectedVehicleID = v.id
                                        Task {
                                            try? await engineManager.sendCommand(.setActive, vehicleID: v.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text("Drone #\(v.id) (\(v.firmwareType))")
                                            if v.id == drone.id {
                                                Image(systemName: "checkmark")
                                            }
                                            if v.communicationLost {
                                                Text(" · Terputus")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Drone #\(drone.id)")
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Drone #\(drone.id)")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Text("·").foregroundStyle(.tertiary)

                    // Mode Tag Badge
                    Text(drone.communicationLost ? "TERPUTUS" : drone.flightMode.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(drone.communicationLost ? Color.red : KropsStyle.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (drone.communicationLost ? Color.red : KropsStyle.accent).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                    // SOP Checklist Warning Pill
                    if !isMissionChecklistComplete && !drone.armed && !drone.flying {
                        Text("·").foregroundStyle(.tertiary)
                        Button {
                            activeTab = .mission
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.system(size: 11))
                                Text("Checklist Belum Selesai")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Selesaikan checklist SOP di tab 1. Rencana sebelum mengizinkan arm motor")
                    }

                    Text("·").foregroundStyle(.tertiary)

                    // Battery
                    HStack(spacing: 5) {
                        Image(systemName: batterySystemImage(drone.battery.percent))
                            .foregroundStyle(batteryColor(drone.battery.percent))
                        Text(String(format: "%.0f%%", drone.battery.percent))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(batteryColor(drone.battery.percent))
                    }

                    // GPS Satellites
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(drone.gps.satellites)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .flightDeckCard(cornerRadius: 22)
                .onTapGesture {
                    showingSensorDetails.toggle()
                }
                .popover(isPresented: $showingSensorDetails) {
                    sensorDetailsPopover(drone)
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Menunggu Koneksi Drone (UDP 14550)...")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .flightDeckCard(cornerRadius: 20)
            }

            // Map View Adjustment Buttons (Top-Right)
            HStack {
                Spacer()

                HStack(spacing: 6) {
                    Button {
                        followDrone.toggle()
                        if followDrone, let coord = droneLiveCoordinate {
                            cameraPosition = .region(
                                MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                            )
                        }
                    } label: {
                        Image(systemName: followDrone ? "location.fill" : "location")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(followDrone ? KropsStyle.accent : Color.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .flightDeckCard(cornerRadius: 16)
                    .help("Kunci kamera ke posisi drone")

                    Button {
                        fitMissionArea()
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .flightDeckCard(cornerRadius: 16)
                    .help("Tampilkan seluruh area kebun misi")

                    // Burger Flight Commands Button
                    Button {
                        showingCommandMenu.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showingCommandMenu ? "xmark" : "line.3.horizontal")
                                .font(.system(size: 13, weight: .bold))
                            Text(showingCommandMenu ? "Tutup" : "Perintah")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(showingCommandMenu ? Color.secondary : KropsStyle.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .flightDeckCard(cornerRadius: 20)
                    .help("Buka menu kontrol penerbangan")
                }
            }
        }
    }

    // MARK: - Slide-Out Command Palette

    private var commandPalette: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Perintah Penerbangan")
                    .font(KropsTypography.sectionTitle)
                Spacer()
                Button {
                    showingCommandMenu = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if let drone = activeDrone {
                // Warning Banners
                if drone.communicationLost {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.red)
                        Text("Komunikasi Terputus! Perintah MAVLink dikunci.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.25), lineWidth: 1))
                } else if !isMissionChecklistComplete && !drone.armed && !drone.flying {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "shield.slash.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Checklist SOP Belum Diverifikasi")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Selesaikan checklist di tab 1. Rencana untuk membuka kunci kontrol motor (Arming).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Button {
                            showingCommandMenu = false
                            activeTab = .mission
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checklist")
                                Text("Buka Checklist (1. Rencana)")
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                }

                ScrollView {
                    VStack(spacing: 8) {
                        // 1. Arm / Disarm
                        HoldToConfirmButton(
                            drone.armed ? "Disarm Drone" : "Arm Drone",
                            systemImage: drone.armed ? "bolt.slash.fill" : "bolt.fill",
                            disabled: drone.armed ? !drone.isReachable : !canExecuteFlightCommands
                        ) {
                            executeCommand(drone.armed ? .disarm : .arm)
                        }

                        // 2. Takeoff
                        HoldToConfirmButton(
                            "Lepas Landas (Takeoff 10m)",
                            systemImage: "airplane.departure",
                            disabled: !canExecuteFlightCommands || !drone.armed || drone.flying
                        ) {
                            executeCommand(.takeoff)
                        }

                        // 3. Start Mission
                        HoldToConfirmButton(
                            "Mulai Misi Survei",
                            systemImage: "play.fill",
                            disabled: !canExecuteActiveOrRecoveryCommands || !drone.armed
                        ) {
                            executeCommand(.startMission)
                        }

                        // 4. Hold / Loiter
                        HoldToConfirmButton(
                            "Tahan Posisi (Hold / Loiter)",
                            systemImage: "pause.circle.fill",
                            disabled: !canExecuteActiveOrRecoveryCommands
                        ) {
                            executeCommand(.pause)
                        }

                        // 5. RTL
                        HoldToConfirmButton(
                            "Kembali ke Home (RTL)",
                            systemImage: "house.fill",
                            disabled: !canExecuteActiveOrRecoveryCommands
                        ) {
                            executeCommand(.rtl)
                        }

                        // 6. Land
                        HoldToConfirmButton(
                            "Mendarat di Posisi (Land)",
                            systemImage: "airplane.arrival",
                            disabled: !canExecuteActiveOrRecoveryCommands
                        ) {
                            executeCommand(.land)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // 7. Emergency Stop (Red destructive)
                        HoldToConfirmButton(
                            "STOP MOTOR (DARURAT)",
                            systemImage: "exclamationmark.octagon.fill",
                            role: .destructive,
                            disabled: !drone.isReachable
                        ) {
                            executeCommand(.emergencyStop)
                        }
                    }
                }
                .frame(maxHeight: 380)

            } else {
                Text("Tidak ada drone terhubung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .flightDeckCard(cornerRadius: 16)
    }

    // MARK: - Bottom Controls Row: HUD Telemetry & Camera Mini-Card

    private var bottomControlsRow: some View {
        HStack(alignment: .bottom) {
            // Bottom-Left Compact HUD Telemetry Card
            if let drone = activeDrone {
                compactTelemetryHUD(drone)
            } else {
                simulatorNoticeCard
            }

            Spacer()

            // Bottom-Right: Autopilot Alert Badge + Camera Mini-Card
            VStack(alignment: .trailing, spacing: 8) {
                if let alertMsg = visibleAlertMessage, !alertMsg.isEmpty {
                    autopilotAlertBadge(alertMsg)
                }

                cameraShutterMiniCard
            }
        }
    }

    private func autopilotAlertBadge(_ message: String) -> some View {
        let isInfo = message.lowercased().hasPrefix("info:") || message.lowercased().hasPrefix("notice:")
        return HStack(spacing: 8) {
            Image(systemName: isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isInfo ? KropsStyle.accent : .orange)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Button {
                alertDismissTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    visibleAlertMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Tutup notifikasi")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 300, alignment: .leading)
        .flightDeckCard(cornerRadius: 10)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func presentAndScheduleAlertDismissal(for newKey: String?) {
        guard let newKey, !newKey.isEmpty else {
            alertDismissTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) {
                visibleAlertMessage = nil
            }
            return
        }
        guard newKey != lastPresentedAlertKey else { return }
        lastPresentedAlertKey = newKey

        guard let message = activeDrone?.activeAlertMessage, !message.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            visibleAlertMessage = message
        }

        alertDismissTask?.cancel()
        alertDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                visibleAlertMessage = nil
            }
        }
    }

    private func compactTelemetryHUD(_ drone: ConnectedDrone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Heading Compass & Home distance
            HStack(spacing: 8) {
                // Rotating compass dial
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.red)
                        .rotationEffect(.degrees(drone.telemetry.heading))
                }

                Text("\(Int(drone.telemetry.heading))° \(compassHeadingString(drone.telemetry.heading))")
                    .font(.subheadline.weight(.bold).monospacedDigit())

                Spacer()

                Label(
                    String(format: "%.0f m", drone.telemetry.distanceToHome),
                    systemImage: "house"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Divider()

            // Metrics Grid (Altitude, Speed, Climb, Waypoint)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    telemetryMetricItem("Alt (Rel)", String(format: "%.1f m", drone.telemetry.altitudeRelative))
                    telemetryMetricItem("Kecepatan", String(format: "%.1f m/s", drone.telemetry.groundSpeed))
                }
                GridRow {
                    telemetryMetricItem("Alt (AMSL)", String(format: "%.1f m", drone.telemetry.altitudeAMSL))
                    telemetryMetricItem("Naik/Turun", String(format: "%.1f m/s", drone.telemetry.climbRate))
                }
            }

            Divider()

            // Power, Sats & Current Waypoint
            HStack {
                Label(
                    String(format: "%.1fV (%.0f%%)", drone.battery.voltage, drone.battery.percent),
                    systemImage: batterySystemImage(drone.battery.percent)
                )
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(batteryColor(drone.battery.percent))

                Spacer()

                Label("\(drone.gps.satellites) Sats", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if drone.telemetry.missionCurrentSeq > 0 {
                    Spacer()
                    Text("WP #\(drone.telemetry.missionCurrentSeq)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(KropsStyle.accent)
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .flightDeckCard(cornerRadius: 14)
        .opacity(drone.communicationLost ? 0.7 : 1.0)
    }

    private func telemetryMetricItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private var cameraShutterMiniCard: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.iphoneReadyForCapture ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(model.iphoneReadyForCapture ? "DroneCam Siap" : "Kamera Belum Siap")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                model.send(.testCapture)
            } label: {
                Label("Ambil Foto Uji", systemImage: "camera.fill")
                    .font(.callout.weight(.medium))
            }
            .kropsPrimaryAction()
            .disabled(!model.iphoneReadyForCapture)

            if let saved = mission?.saved, saved > 0 {
                Text("\(saved) foto tersimpan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .flightDeckCard(cornerRadius: 14)
    }

    private var simulatorNoticeCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Menunggu Sinyal Drone (UDP 14550)")
                    .font(.caption.weight(.semibold))
                Text("Jalankan simulator ArduPilot untuk mulai.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .flightDeckCard(cornerRadius: 12)
    }

    private func sensorDetailsPopover(_ drone: ConnectedDrone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status Sensor Autopilot")
                .font(KropsTypography.sectionTitle)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Koneksi:")
                    Spacer()
                    Text(drone.communicationLost ? "Terputus" : "Normal")
                        .foregroundStyle(drone.communicationLost ? .red : .green)
                }
                HStack {
                    Text("Checklist SOP:")
                    Spacer()
                    Text(isMissionChecklistComplete ? "Lengkap" : "Belum Selesai")
                        .foregroundStyle(isMissionChecklistComplete ? .green : .orange)
                }
                HStack {
                    Text("Kesiapan Arm:")
                    Spacer()
                    Text(canExecuteFlightCommands ? "Siap Arm" : "Terkunci")
                        .foregroundStyle(canExecuteFlightCommands ? .green : .orange)
                }
            }
            .font(.caption)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(zip(drone.sensorNames, drone.sensorStatus)), id: \.0) { name, status in
                        HStack {
                            Text(name).font(.caption2)
                            Spacer()
                            Text(status)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(
                                    status.localizedCaseInsensitiveContains("healthy") || status == "Normal"
                                        ? Color.green : Color.orange)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Logic & Actions

    private func executeCommand(_ cmd: DroneFlightCommand) {
        commandError = nil
        Task {
            do {
                try await engineManager.sendCommand(cmd)
            } catch {
                await MainActor.run {
                    self.commandError = error.localizedDescription
                    self.showingCommandAlert = true
                }
            }
        }
    }

    private func updateDronePositionAndTrail() {
        guard let coord = droneLiveCoordinate else { return }

        if let drone = activeDrone,
            drone.isReachable && (drone.armed || drone.flying),
            let missionID = mission?.id ?? planner.draft.missionID
        {
            planner.appendTrailCoordinate(
                MapCoordinate(latitude: coord.latitude, longitude: coord.longitude),
                for: missionID
            )
        }

        // Auto follow camera if active
        if followDrone {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                )
            )
        }
    }

    private func initializeMapRegion() {
        if let coord = droneLiveCoordinate {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                )
            )
        } else {
            fitMissionArea()
        }
    }

    private func fitMissionArea() {
        var allCoords = boundaryCoordinates + surveyTransectCoordinates
        if let fenceCoords = planner.draft.safetyResult?.polygonCoordinates.filter(\.isValid).map(\.clCoordinate) {
            allCoords.append(contentsOf: fenceCoords)
        }
        if let home = homeCoordinate { allCoords.append(home) }
        if let droneCoord = droneLiveCoordinate { allCoords.append(droneCoord) }

        guard !allCoords.isEmpty else { return }

        let minLat = allCoords.map(\.latitude).min() ?? -2.0
        let maxLat = allCoords.map(\.latitude).max() ?? -2.0
        let minLon = allCoords.map(\.longitude).min() ?? 118.0
        let maxLon = allCoords.map(\.longitude).max() ?? 118.0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func droneStatusColor(_ drone: ConnectedDrone) -> Color {
        if drone.communicationLost { return .red }
        if drone.flying { return .blue }
        if drone.armed { return .green }
        return drone.canArm ? .green : .orange
    }

    private func batterySystemImage(_ pct: Double) -> String {
        if pct > 75 { return "battery.100" }
        if pct > 50 { return "battery.75" }
        if pct > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(_ pct: Double) -> Color {
        if pct <= 0 { return .secondary }
        if pct < 20 { return .red }
        if pct < 40 { return .orange }
        return .primary
    }

    private func compassHeadingString(_ deg: Double) -> String {
        let d = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch d {
        case 337.5...360, 0..<22.5: return "U"
        case 22.5..<67.5: return "TL"
        case 67.5..<112.5: return "T"
        case 112.5..<157.5: return "TG"
        case 157.5..<202.5: return "S"
        case 202.5..<247.5: return "BD"
        case 247.5..<292.5: return "B"
        case 292.5..<337.5: return "BL"
        default: return "U"
        }
    }
}
