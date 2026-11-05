import AppKit
import SwiftUI

struct SurveyConfigurationView: View {
    @ObservedObject var model: ControlViewModel
    var planner: FlightPlannerViewModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let planner {
                Button {
                    planner.planningStep = .boundary
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text("Ubah Batas Area")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KropsStyle.accent)
            }

            ControlPanel("Survei", state: model.geometry.reviewed ? "Ditinjau" : nil) {
                HStack(spacing: 12) {
                    ControlField("Tinggi terbang") { NumberField($model.geometry.heightAGL, unit: "m") }
                        .help("Tinggi kamera di atas tanah (AGL), bukan altitude GPS.")
                    ControlField("Kecepatan") { NumberField($model.geometry.speed, unit: "m/s") }
                }

                if let planner {
                    SurveyActionSection(planner: planner, model: model)
                }

                HStack {
                    Toggle("Rencana terbang sudah diperiksa", isOn: $model.geometry.reviewed).font(.body)
                    Spacer()
                }
            }.disabled(model.editingLocked)
        }
    }
}

private struct SurveyActionSection: View {
    @ObservedObject var planner: FlightPlannerViewModel
    @ObservedObject var model: ControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Camera & Resolution info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Kamera", systemImage: "camera")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("iPhone 17")
                        .font(.caption.weight(.medium))
                }
                Picker("Resolusi", selection: $planner.draft.cameraResolution) {
                    ForEach(CameraOpticalSpec.Resolution.allCases) { res in
                        Text(res.rawValue).tag(res)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                ControlField("Side Overlap") {
                    NumberField($planner.draft.sideOverlap, unit: "%")
                }
                .help("Persentase tumpang tindih antar jalur foto sejajar (rekomendasi: 70%).")

                ControlField("Frontal Overlap") {
                    NumberField($planner.draft.frontalOverlap, unit: "%")
                }
                .help("Persentase tumpang tindih sepanjang jalur foto (rekomendasi: 75%).")
            }

            HStack(spacing: 12) {
                ControlField("Sudut jalur") {
                    NumberField($planner.draft.gridAngle, unit: "°")
                }
                .help("Arah orientasi jalur terbang relatif terhadap utara (0°–360°).")
            }

            // Calculated telemetry preview
            calculatedTelemetryPreview

            VStack(alignment: .leading, spacing: 6) {
                Text("Titik Lepas Landas & Masuk").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        planner.mode = (planner.mode == .home ? .inspect : .home)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text(planner.mode == .home ? "Pilih Home..." : (planner.draft.home != nil ? "Ubah Home" : "Pilih Home"))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(planner.mode == .home ? .green : .secondary)
                    .help("Klik tombol ini, lalu klik di mana saja pada peta untuk menentukan posisi Home (H).")

                    Button {
                        planner.mode = (planner.mode == .entry ? .inspect : .entry)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 8, height: 8)
                            Text(planner.mode == .entry ? "Pilih Entry..." : (planner.draft.surveyEntry != nil ? "Ubah Entry" : "Pilih Entry"))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(planner.mode == .entry ? .cyan : .secondary)
                    .help("Klik tombol ini, lalu klik pada garis batas kebun untuk menentukan titik masuk (E).")
                }

                if planner.mode == .home {
                    Text("Klik pada peta untuk memilih posisi Home.").font(.caption2).foregroundStyle(.green)
                } else if planner.mode == .entry {
                    Text("Klik pada garis batas kebun untuk memilih posisi Entry.").font(.caption2).foregroundStyle(.cyan)
                }
            }

            Toggle("Kembali ke Home (RTL)", isOn: $planner.draft.returnToHome)
                .font(.body)
                .help("Drone otomatis kembali ke titik Home setelah menyelesaikan lintasan survei.")

            DisclosureGroup("Pengaturan lanjutan") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ControlField("Jarak putar") {
                            NumberField($planner.draft.turnaroundDistance, unit: "m")
                        }
                        .help("Jarak manuver putar balik di luar batas area kebun.")
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)

            Button {
                Task {
                    await planner.generateSurveyWaypoints(
                        altitude: model.geometry.heightAGL,
                        speed: model.geometry.speed,
                        gridAngle: planner.draft.gridAngle,
                        sideOverlap: planner.draft.sideOverlap,
                        frontalOverlap: planner.draft.frontalOverlap,
                        cameraResolution: planner.draft.cameraResolution,
                        lineSpacing: planner.draft.lineSpacing,
                        triggerDistance: planner.draft.triggerDistance,
                        turnaroundDistance: planner.draft.turnaroundDistance,
                        entryLocation: planner.draft.entryLocation
                    )
                }
            } label: {
                HStack {
                    if planner.isGeneratingWaypoints {
                        ProgressView().controlSize(.small)
                        Text("Menghitung di QGC...")
                    } else {
                        Label("Rencanakan Jalur Survei", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .kropsPrimaryAction()
            .disabled(planner.isGeneratingWaypoints)

            if let stats = planner.draft.surveyStatistics, stats.totalDistanceMeters > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Hasil Jalur QGC")
                        .font(.caption).bold().foregroundStyle(.primary)
                    if stats.calculatedLineSpacing > 0 {
                        HStack {
                            Text("Jarak antar jalur:")
                            Spacer()
                            Text(String(format: "%.1f m", stats.calculatedLineSpacing))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if stats.calculatedTriggerDistance > 0 {
                        HStack {
                            Text("Jarak antar foto:")
                            Spacer()
                            Text(String(format: "%.1f m", stats.calculatedTriggerDistance))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if stats.groundResolutionCmPerPx > 0 {
                        HStack {
                            Text("Resolusi GSD:")
                            Spacer()
                            Text(String(format: "%.2f cm/px", stats.groundResolutionCmPerPx))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total jarak:")
                        Spacer()
                        Text(String(format: "%.0f m", stats.totalDistanceMeters))
                    }.font(.caption).foregroundStyle(.secondary)
                    if stats.flightTimeSeconds > 0 {
                        HStack {
                            Text("Estimasi durasi:")
                            Spacer()
                            Text(MissionWorkspaceView.formattedDuration(stats.flightTimeSeconds))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Estimasi foto:")
                        Spacer()
                        Text("\(stats.photoCount)")
                    }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Jumlah lintasan:")
                        Spacer()
                        Text("\(stats.transectCount)")
                    }.font(.caption).foregroundStyle(.secondary)
                    if stats.coveredAreaSquareMeters > 0 {
                        HStack {
                            Text("Cakupan area:")
                            Spacer()
                            Text(String(format: "%.2f ha", stats.coveredAreaSquareMeters / 10_000.0))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var calculatedTelemetryPreview: some View {
        var spec = CameraOpticalSpec.iphone17
        spec.setResolution(planner.draft.cameraResolution)
        let estSpacing = planner.draft.calculatedLineSpacing ?? spec.estimatedLineSpacing(altitude: model.geometry.heightAGL, sideOverlapPercent: planner.draft.sideOverlap)
        let estTrigger = planner.draft.calculatedTriggerDistance ?? spec.estimatedTriggerDistance(altitude: model.geometry.heightAGL, frontalOverlapPercent: planner.draft.frontalOverlap)
        let estGSD = planner.draft.groundResolutionCmPerPx ?? spec.estimatedGSDcm(altitude: model.geometry.heightAGL)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarak Jalur").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.1f m", estSpacing)).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarak Foto").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.1f m", estTrigger)).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("GSD").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.2f cm/px", estGSD)).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
