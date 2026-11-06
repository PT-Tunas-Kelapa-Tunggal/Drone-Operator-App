import SwiftUI

struct GeofenceInspectorSection: View {
    @Binding var geofence: GeofenceSettings
    let safetyResult: SurveySafetyResult?
    let canEdit: Bool
    let onParameterChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("Geofence & Batas Aman")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Toggle(
                    "Aktif",
                    isOn: Binding(
                        get: { geofence.enabled },
                        set: { val in
                            guard canEdit else { return }
                            geofence.enabled = val
                            onParameterChanged()
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Aktifkan batas pengaman virtual (Geofence) di mesin QGC.")
            }

            if geofence.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bentuk Geofence")
                        .font(KropsTypography.supporting)
                        .foregroundStyle(.secondary)
                    Picker(
                        "Bentuk Geofence",
                        selection: Binding(
                            get: { geofence.type },
                            set: { val in
                                guard canEdit else { return }
                                geofence.type = val
                                onParameterChanged()
                            }
                        )
                    ) {
                        ForEach(GeofenceType.allCases) { fenceType in
                            Text(fenceType.title).tag(fenceType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help(
                        "Pilih bentuk Geofence: mengikuti poligon batas kebun atau lingkaran dari titik Home."
                    )
                }

                HStack(spacing: 10) {
                    if geofence.type == .polygon {
                        ControlField("Buffer Fence") {
                            NumberField(
                                Binding(
                                    get: { geofence.bufferMeters },
                                    set: { val in
                                        guard canEdit else { return }
                                        geofence.bufferMeters = max(0, val)
                                        onParameterChanged()
                                    }
                                ),
                                unit: "m"
                            )
                        }
                        .help(
                            "Jarak perluasan poligon Geofence di luar batas kebun agar manuver putar balik tercakup."
                        )
                    } else {
                        ControlField("Radius Fence") {
                            NumberField(
                                Binding(
                                    get: {
                                        if geofence.radiusMeters > 0 {
                                            return geofence.radiusMeters
                                        }
                                        return safetyResult?.circleRadiusMeters ?? 0
                                    },
                                    set: { val in
                                        guard canEdit else { return }
                                        geofence.radiusMeters = max(0, val)
                                        onParameterChanged()
                                    }
                                ),
                                unit: "m"
                            )
                        }
                        .help("Radius lingkaran Geofence dari titik Home (isi 0 untuk otomatis dari QGC).")
                    }

                    ControlField("Ceiling") {
                        NumberField(
                            Binding(
                                get: { geofence.ceilingMeters },
                                set: { val in
                                    guard canEdit else { return }
                                    geofence.ceilingMeters = max(5, val)
                                    onParameterChanged()
                                }
                            ),
                            unit: "m"
                        )
                    }
                    .help("Batas ketinggian terbang maksimum (Ceiling) sebagai mekanisme pengaman.")
                }

                if geofence.type == .circle && geofence.radiusMeters > 0 {
                    Button("Gunakan Radius Otomatis QGC") {
                        guard canEdit else { return }
                        geofence.radiusMeters = 0
                        onParameterChanged()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Aksi Saat Batas Dilanggar")
                        .font(KropsTypography.supporting)
                        .foregroundStyle(.secondary)
                    Picker(
                        "Aksi Pelanggaran",
                        selection: Binding(
                            get: { geofence.breachAction },
                            set: { val in
                                guard canEdit else { return }
                                geofence.breachAction = val
                                onParameterChanged()
                            }
                        )
                    ) {
                        ForEach(GeofenceBreachAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                }

                if let safety = safetyResult, safety.enabled {
                    if safety.coversMission && safety.ceilingOk {
                        Label(
                            "Geofence & Ceiling QGC aman mencakup seluruh jalur",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    } else {
                        ForEach(safety.issues) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Label(
                    "Geofence nonaktif. Aktifkan untuk memenuhi SOP keselamatan.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }
}
