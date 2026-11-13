import AppKit
import SwiftUI
import UniformTypeIdentifiers

public enum VariReportInitialSection: String, Sendable {
    case vari = "vari"
    case hara = "hara"
}

private enum VariVisualLayer: String, CaseIterable, Identifiable {
    case annotated = "Zonasi Deteksi"
    case whiteSeparatorsWithNumbers = "Batas & Nomor"
    case quartiles = "Kuartil Tajuk"
    case heatmapMontage = "Montase Heatmap"
    case pipeline = "Alur Pipeline"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .annotated: return "map.fill"
        case .whiteSeparatorsWithNumbers: return "number.square.fill"
        case .quartiles: return "chart.bar.xaxis"
        case .heatmapMontage: return "square.grid.3x3.fill"
        case .pipeline: return "arrow.triangle.pull"
        }
    }
}

/// A comprehensive, high-taste single-page scrolling report presenting all Iteration 2 VARI & Fertilizer results.
/// Adheres to Apple Human Interface Guidelines and macOS design principles.
public struct VariReportWorkspaceView: View {
    public let result: VariScanResult
    public let initialSection: VariReportInitialSection
    public let selectedNPKForTiming: ContractFertilizerType?
    public let onSelectNPKForTiming: ((ContractFertilizerType) -> Void)?
    public let onRerun: (() -> Void)?

    @State private var selectedLayer = VariVisualLayer.annotated
    @State private var selectedZoneForCropDetail: VariZoneDetail?

    public init(
        result: VariScanResult,
        initialSection: VariReportInitialSection = .vari,
        selectedNPKForTiming: ContractFertilizerType? = nil,
        onSelectNPKForTiming: ((ContractFertilizerType) -> Void)? = nil,
        onRerun: (() -> Void)? = nil
    ) {
        self.result = result
        self.initialSection = initialSection
        self.selectedNPKForTiming = selectedNPKForTiming
        self.onSelectNPKForTiming = onSelectNPKForTiming
        self.onRerun = onRerun
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroHeader
                    metricCardsGrid
                    visualMapSection
                    zoneVariSection
                    Divider().padding(.vertical, 8)
                    fertilizerAllocationSection
                        .id("hara_section")
                    if let budget = result.budget, !budget.candidates.isEmpty {
                        Divider().padding(.vertical, 8)
                        budgetMatchingSection(budget: budget)
                            .id("budget_section")
                    }
                    distributionAndMontageSection
                    Divider().padding(.vertical, 8)
                    actionsSection
                }
                .padding(24)
            }
            .onAppear {
                if initialSection == .hara {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo("hara_section", anchor: .top)
                        }
                    }
                }
            }
            .sheet(item: $selectedZoneForCropDetail) { zone in
                ZoneCropDetailSheet(zone: zone)
            }
        }
        .background(KropsStyle.canvas)
    }

    // MARK: - 1. Hero Header

    private var heroHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.green)
                    Text("Laporan Analisis VARI & Nutrisi Pohon")
                        .font(.title2.weight(.bold))
                }
                Text("Citra: \(result.resultJSONURL.deletingLastPathComponent().lastPathComponent) · Diproses: \(result.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.resultJSONURL])
                } label: {
                    Label("Buka di Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if let onRerun {
                    Button(action: onRerun) {
                        Label("Jalankan Ulang", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 2. Metric Cards Grid

    private var metricCardsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)], spacing: 14) {
            metricCard(
                title: "Pohon Terdeteksi",
                value: "\(result.treeCount)",
                unit: "pohon",
                systemImage: "tree.fill",
                color: .green
            )
            metricCard(
                title: "Jumlah Zona",
                value: "\(result.zoneCount)",
                unit: "area",
                systemImage: "square.grid.2x2.fill",
                color: .blue
            )
            metricCard(
                title: "Rerata Indeks VARI",
                value: result.referenceMeanVari.map { String(format: "%.3f", $0) } ?? "N/A",
                unit: variHealthDescription(result.referenceMeanVari),
                systemImage: "leaf.fill",
                color: variColor(result.referenceMeanVari)
            )
            metricCard(
                title: "Mode Suplemen",
                value: result.summary?.boostMode == "blanket_p25" ? "Blanket P25" : "Zone-Specific",
                unit: "algoritma boost",
                systemImage: "bolt.badge.automatic.fill",
                color: result.summary?.boostMode == "blanket_p25" ? .orange : .teal
            )
            metricCard(
                title: "Rekomendasi NPK",
                value: result.budget?.closestOption ?? "Standard",
                unit: "opsi mendekati",
                systemImage: "bag.fill",
                color: .indigo
            )
            metricCard(
                title: "Batas Anggaran Petani",
                value: result.budget?.targetBudgetRp.map { formatRupiah($0) } ?? "Rp 0",
                unit: "anggaran modal",
                systemImage: "banknote",
                color: .purple
            )
            metricCard(
                title: "Estimasi Biaya Pupuk",
                value: result.budget?.candidates.first(where: { $0.isClosest }).map { formatRupiah($0.combinedCostRp) }
                    ?? (result.budget?.targetBudgetRp.map { formatRupiah($0) } ?? "Rp 0"),
                unit: "rekap tahunan",
                systemImage: "banknote.fill",
                color: .mint
            )
        }
    }

    private func metricCard(title: String, value: String, unit: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color)
                    )
            }
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(KropsStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
    }

    // MARK: - 3. Visual Map Layer Section

    private var visualMapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title & subtitle on top with breathing room
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Visual Citra & Pemetaan Kanopi Sawit")
                    .font(.headline)
                Text("Pilih lapisan visualisasi untuk meninjau zonasi, nomor plot, kuartil tajuk, atau alur deteksi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Layer Selector Bar — Dedicated full-width segmented control without horizontal squeeze
            Picker("Pilih Lapisan Citra", selection: $selectedLayer) {
                ForEach(VariVisualLayer.allCases) { layer in
                    Label(layer.title, systemImage: layer.icon)
                        .tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Viewport Container with perfect viewport fit, interactive drag & zoom
            InteractiveImageViewport(
                imageURL: urlForLayer(selectedLayer),
                layer: selectedLayer
            )
        }
    }

    private func urlForLayer(_ layer: VariVisualLayer) -> URL? {
        switch layer {
        case .annotated:
            return result.assets.annotatedMapURL
        case .whiteSeparatorsWithNumbers:
            return result.assets.whiteSeparatorsWithNumbersURL
        case .quartiles:
            return result.assets.quartilesMapURL
        case .heatmapMontage:
            return result.assets.heatmapMontageURL
        case .pipeline:
            return result.assets.pipelinePlotURL
        }
    }

    // MARK: - 4. Zone VARI Table Section

    private var zoneVariSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Statistik Indeks Vegetasi VARI per Zona")
                        .font(.headline)
                    Text("Pengelompokan tajuk sawit per zona untuk mendeteksi variabilitas spasial dan zona acuan (reference zone).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let refMean = result.summary?.referenceZoneMeanVari {
                    HStack(spacing: 6) {
                        Text("Zona Acuan:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(result.summary?.referenceZoneIDs.map { "Z\($0)" }.joined(separator: ", ") ?? "Semua")
                            .font(.caption.weight(.bold))
                        Text("(Rerata VARI: \(String(format: "%.3f", refMean)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            // Interactive Table
            VStack(spacing: 0) {
                // Table Header
                HStack {
                    Text("Zona").frame(width: 60, alignment: .leading)
                    Text("Baris").frame(width: 50, alignment: .leading)
                    Text("Pohon").frame(width: 60, alignment: .trailing)
                    Text("Luas (ha)").frame(width: 75, alignment: .trailing)
                    Text("Rerata VARI").frame(width: 100, alignment: .trailing)
                    Text("Rentang Min-Max").frame(width: 130, alignment: .center)
                    Text("Keyakinan").frame(width: 80, alignment: .trailing)
                    Text("Status Boost").frame(width: 110, alignment: .center)
                    Spacer()
                    Text("Crop Tajuk").frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(KropsStyle.canvas)

                Divider()

                // Table Rows
                if result.zones.isEmpty {
                    Text("Belum ada data rincian zona.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(result.zones) { zone in
                        HStack {
                            Text("Z\(zone.zoneID)")
                                .font(.body.weight(.semibold))
                                .frame(width: 60, alignment: .leading)
                            Text(zone.approxRow.map { "R\($0)" } ?? "-")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text("\(zone.treeCount)")
                                .font(.callout.monospacedDigit())
                                .frame(width: 60, alignment: .trailing)
                            Text(zone.areaHa.map { String(format: "%.2f", $0) } ?? "-")
                                .font(.callout.monospacedDigit())
                                .frame(width: 75, alignment: .trailing)

                            // Mean VARI Badge
                            HStack(spacing: 4) {
                                Circle().fill(variColor(zone.meanVari)).frame(width: 8, height: 8)
                                Text(zone.meanVari.map { String(format: "%.3f", $0) } ?? "N/A")
                                    .font(.callout.monospacedDigit().weight(.medium))
                            }
                            .frame(width: 100, alignment: .trailing)

                            Text(formatMinMax(min: zone.minVari, max: zone.maxVari))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .center)

                            Text(zone.confidence.map { "\(Int($0 * 100))%" } ?? "-")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)

                            // Boost Mode Pill
                            Text(zone.boostMode == "blanket_p25" ? "Blanket P25" : "Spesifik")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (zone.boostMode == "blanket_p25" ? Color.orange : Color.green).opacity(0.14),
                                    in: Capsule()
                                )
                                .frame(width: 110, alignment: .center)

                            Spacer()

                            // Crop Preview Button
                            if zone.baseImageCropURL != nil || zone.exgImageCropURL != nil {
                                Button {
                                    selectedZoneForCropDetail = zone
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "viewfinder")
                                        Text("Lihat")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 90, alignment: .trailing)
                            } else {
                                Text("-")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
            .background(KropsStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
        }
    }

    // MARK: - 5. Fertilizer Allocation / HARA Section

    private var fertilizerAllocationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.triangle.fill")
                            .foregroundStyle(Color.green)
                        Text("3. Rekomendasi Alokasi Pupuk & Dosis HARA")
                            .font(.headline)
                    }
                    Text("Perhitungan suplemen unsur hara Mg dan N berbasis variasi defisit VARI, dikonversi ke massa pupuk Dolomite & Urea.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let csvURL = result.assets.fertilizerMassCSVURL {
                    Button {
                        VariFilePanels.saveCSV(from: csvURL, suggestedName: "alokasi_pupuk_sawit.csv")
                    } label: {
                        Label("Ekspor CSV Pupuk", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Products Table
            VStack(spacing: 0) {
                // Table Header
                HStack {
                    Text("Zona / Cakupan").frame(width: 120, alignment: .leading)
                    Text("Produk Pupuk").frame(width: 110, alignment: .leading)
                    Text("Unsur").frame(width: 60, alignment: .center)
                    Text("Suplemen VARI (kg)").frame(width: 140, alignment: .trailing)
                    Text("Dosis Dasar (kg)").frame(width: 120, alignment: .trailing)
                    Text("Total Gabungan (kg)").frame(width: 140, alignment: .trailing)
                    Text("Total Dibulatkan (kg)").frame(width: 150, alignment: .trailing)
                    Spacer()
                    Text("Estimasi Karung (50kg)").frame(width: 160, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(KropsStyle.canvas)

                Divider()

                if result.products.isEmpty {
                    Text("Belum ada tabel konversi produk pupuk yang dihasilkan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(result.products) { row in
                        let isTotalRow = row.zoneLabel.lowercased().contains("total")
                        HStack {
                            Text(row.zoneLabel)
                                .font(isTotalRow ? .body.weight(.bold) : .body)
                                .frame(width: 120, alignment: .leading)
                            Text(row.productName)
                                .font(isTotalRow ? .callout.weight(.bold) : .callout)
                                .frame(width: 110, alignment: .leading)
                            Text(row.nutrientType ?? "-")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text(String(format: "%.2f", row.supplementKg))
                                .font(.callout.monospacedDigit())
                                .frame(width: 140, alignment: .trailing)
                            Text(String(format: "%.2f", row.baseProductKg))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing)
                            Text(String(format: "%.2f", row.combinedKg))
                                .font(.callout.monospacedDigit().weight(isTotalRow ? .bold : .regular))
                                .frame(width: 140, alignment: .trailing)
                            Text(String(format: "%.1f", row.roundedCombinedKg))
                                .font(.callout.monospacedDigit().weight(isTotalRow ? .bold : .semibold))
                                .frame(width: 150, alignment: .trailing)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(row.fullBagsNeeded) karung")
                                    .font(.callout.weight(isTotalRow ? .bold : .medium))
                                Text("(\(String(format: "%.2f", row.estimatedBags)))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 160, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isTotalRow ? KropsStyle.accent.opacity(0.08) : Color.clear)
                        Divider()
                    }
                }
            }
            .background(KropsStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
        }
    }

    // MARK: - 6. Budget Matching & Commercial NPK Section

    private func budgetMatchingSection(budget: VariBudgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.indigo)
                        Text("4. Pencocokan Anggaran & Formulasi NPK Komersial")
                            .font(.headline)
                    }
                    Text("Perbandingan opsi formula pupuk NPK/NPKMg komersial seluruh kebun dipadukan dengan total Mg (Dolomite) & Urea per zona.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let userBlend = result.userBlend {
                        let ratioText =
                            userBlend.ratio.map {
                                "(\(Int($0.n.rounded()))-\(Int($0.p2o5.rounded()))-\(Int($0.k2o.rounded()))-\(Int($0.mgo.rounded())))"
                            } ?? ""
                        let kgText = String(format: "%.1f kg/thn", userBlend.npkProductKgFarmPerYear)
                        let doseText = userBlend.dosePerTreeKgPerApplication.map {
                            String(format: " · %.2f kg/pohon", $0)
                        } ?? ""
                        Text("Baseline pupuk petani: NPK \(ratioText) · \(kgText)\(doseText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let target = budget.targetBudgetRp {
                    HStack(spacing: 6) {
                        Text("Target Anggaran:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(formatRupiah(target))
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.12), in: Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Table Header
                    HStack {
                        Text("Blend\noption")
                            .frame(width: 140, alignment: .leading)
                        Text("Label N-P₂O₅-K₂O-MgO\n(%)")
                            .frame(width: 145, alignment: .leading)
                        Text("NPK full\nbags/farm/year")
                            .frame(width: 110, alignment: .trailing)
                        Text("NPK cost")
                            .frame(width: 115, alignment: .trailing)
                        Text("Zone\nMg/Urea cost")
                            .frame(width: 115, alignment: .trailing)
                        Text("Combined\nestimate")
                            .frame(width: 125, alignment: .trailing)
                        Text("Budget\ntarget")
                            .frame(width: 115, alignment: .trailing)
                        Text("Budget\ndifference")
                            .frame(width: 155, alignment: .trailing)
                        Text("Budget fit")
                            .frame(width: 130, alignment: .center)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(KropsStyle.canvas)

                    Divider()

                    ForEach(budget.candidates) { candidate in
                        HStack {
                            Text(candidate.blendOption)
                                .font(.callout.weight(candidate.isClosest ? .semibold : .regular))
                                .frame(width: 140, alignment: .leading)

                            Text(candidate.labelRatio)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 145, alignment: .leading)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(candidate.npkFullBags) karung")
                                    .font(.callout.monospacedDigit())
                                if let annualKg = candidate.recommendedAnnualKgFarm, annualKg > 0 {
                                    Text("\(String(format: "%.1f", VariDoseRounding.roundToHalfKg(annualKg))) kg/thn")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 110, alignment: .trailing)

                            Text(formatRupiah(candidate.npkCostRp))
                                .font(.callout.monospacedDigit())
                                .frame(width: 115, alignment: .trailing)

                            Text(formatRupiah(candidate.zoneTopupCostRp))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 115, alignment: .trailing)

                            Text(formatRupiah(candidate.combinedCostRp))
                                .font(.callout.monospacedDigit().weight(candidate.isClosest ? .bold : .medium))
                                .frame(width: 125, alignment: .trailing)

                            Text(formatRupiah(candidate.budgetTargetRp))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 115, alignment: .trailing)

                            Text(formatBudgetDifference(candidate.budgetDifferenceRp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(candidate.budgetDifferenceRp <= 0 ? Color.green : Color.primary)
                                .frame(width: 155, alignment: .trailing)

                            VStack(spacing: 4) {
                                if candidate.isClosest {
                                    Text("CLOSEST TO BUDGET")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color.green)
                                }
                                if let explicitType = candidate.explicitNPKType,
                                    let onSelectNPKForTiming
                                {
                                    let isSelectedForTiming =
                                        selectedNPKForTiming == explicitType
                                        || (selectedNPKForTiming == nil && candidate.isClosest)
                                    Button {
                                        onSelectNPKForTiming(explicitType)
                                    } label: {
                                        Text(isSelectedForTiming ? "Dipakai di Jadwal" : "Pakai di Jadwal")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .tint(isSelectedForTiming ? KropsStyle.accent : .secondary)
                                }
                            }
                            .frame(width: 130, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(candidate.isClosest ? Color.green.opacity(0.06) : Color.clear)
                        Divider()
                    }
                }
                .frame(minWidth: 1080)
            }
            .background(KropsStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
        }
    }

    // MARK: - 7. Distribution Plot & Montage Section

    private var distributionAndMontageSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Plot Card
            VStack(alignment: .leading, spacing: 10) {
                Label("Distribusi Nilai VARI Zona", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Text("Distribusi mean VARI per zona dengan penanda rentang P25–P95.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let plotURL = result.assets.variDistributionPlotURL,
                   let plotImg = NSImage(contentsOf: plotURL) {
                    Image(nsImage: plotImg)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 220)
                        .overlay(
                            Text("Grafik distribusi belum tersedia.")
                                .font(.caption).foregroundStyle(.secondary)
                        )
                }
            }
            .padding(16)
            .background(KropsStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
            .frame(maxWidth: .infinity)

            // Montage Card
            VStack(alignment: .leading, spacing: 10) {
                Label("Montase Heatmap Per-Pohon", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Text("Pratinjau visualisasi tajuk setiap pohon sawit berdasar kuartil VARI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let montageURL = result.assets.heatmapMontageURL,
                   let montageImg = NSImage(contentsOf: montageURL) {
                    Image(nsImage: montageImg)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 220)
                        .overlay(
                            Text("Montase pohon belum tersedia.")
                                .font(.caption).foregroundStyle(.secondary)
                        )
                }
            }
            .padding(16)
            .background(KropsStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 8. Actions & Exports Section

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                VariFilePanels.saveJSON(from: result.resultJSONURL, suggestedName: "vari_result.json")
            } label: {
                Label("Unduh vari_result.json", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)

            if let zoneCSV = result.assets.zoneSummaryCSVURL {
                Button {
                    VariFilePanels.saveCSV(from: zoneCSV, suggestedName: "ringkasan_zona_vari.csv")
                } label: {
                    Label("Unduh CSV Zona", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
            }

            if let fertCSV = result.assets.fertilizerMassCSVURL {
                Button {
                    VariFilePanels.saveCSV(from: fertCSV, suggestedName: "alokasi_pupuk_sawit.csv")
                } label: {
                    Label("Unduh CSV Pupuk", systemImage: "bag")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([result.resultJSONURL])
            } label: {
                Label("Buka Direktori di Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formatRupiah(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        let str = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "Rp\(str)"
    }

    private func formatBudgetDifference(_ delta: Double) -> String {
        let absVal = abs(delta)
        let formatted = formatRupiah(absVal)
        if delta > 0 {
            return "\(formatted) over budget"
        } else if delta < 0 {
            return "\(formatted) under budget"
        } else {
            return "on budget"
        }
    }

    private func formatMinMax(min: Double?, max: Double?) -> String {
        guard let min, let max else { return "N/A" }
        return String(format: "%.2f – %.2f", min, max)
    }

    private func variColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 0.40 { return .green }
        if value >= 0.30 { return .yellow }
        return .orange
    }

    private func variHealthDescription(_ value: Double?) -> String {
        guard let value else { return "Tidak diketahui" }
        if value >= 0.40 { return "Vegetasi Sangat Baik" }
        if value >= 0.30 { return "Vegetasi Cukup / Moderat" }
        return "Defisit Klorofil / Butuh Suplemen"
    }
}

// MARK: - Sheet for Inspecting Zone Crops

private struct ZoneCropDetailSheet: View {
    let zone: VariZoneDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detail Tajuk Citra — Zona Z\(zone.zoneID)")
                        .font(.title3.weight(.bold))
                    Text("\(zone.treeCount) pohon terdeteksi · Rerata VARI: \(zone.meanVari.map { String(format: "%.3f", $0) } ?? "N/A")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 8)

            HStack(spacing: 20) {
                // Base Crop
                VStack(alignment: .leading, spacing: 8) {
                    Text("Citra RGB Asli").font(.headline)
                    if let url = zone.baseImageCropURL, let img = NSImage(contentsOf: url) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        placeholder("Crop citra asli tidak ditemukan")
                    }
                }
                .frame(maxWidth: .infinity)

                // ExG Crop
                VStack(alignment: .leading, spacing: 8) {
                    Text("Segmentasi ExG & Kanopi").font(.headline)
                    if let url = zone.exgImageCropURL, let img = NSImage(contentsOf: url) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        placeholder("Crop ExG tidak ditemukan")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 460)
    }

    private func placeholder(_ text: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.1))
            .overlay(Text(text).font(.caption).foregroundStyle(.secondary))
            .frame(height: 320)
    }
}

// MARK: - Interactive Image Viewport (Fit to Screen + Pan/Zoom)

private struct InteractiveImageViewport: View {
    let imageURL: URL?
    let layer: VariVisualLayer

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var image: NSImage?
    @State private var isLoading = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0
    private let viewportHeight: CGFloat = 520

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .black).opacity(0.92))
                .frame(height: viewportHeight)

            if let image {
                GeometryReader { geo in
                    let containerSize = geo.size

                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .scaleEffect(zoomScale)
                        .offset(
                            x: panOffset.width + dragTranslation.width,
                            y: panOffset.height + dragTranslation.height
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard zoomScale > 1.0 else { return }
                                    dragTranslation = value.translation
                                }
                                .onEnded { value in
                                    guard zoomScale > 1.0 else { return }
                                    let newX = panOffset.width + value.translation.width
                                    let newY = panOffset.height + value.translation.height

                                    let maxPanX = max(0, (containerSize.width * (zoomScale - 1.0)) / 2)
                                    let maxPanY = max(0, (containerSize.height * (zoomScale - 1.0)) / 2)

                                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                                        panOffset = CGSize(
                                            width: min(maxPanX, max(-maxPanX, newX)),
                                            height: min(maxPanY, max(-maxPanY, newY))
                                        )
                                        dragTranslation = .zero
                                    }
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { factor in
                                    let targetZoom = zoomScale * factor
                                    zoomScale = min(maxZoom, max(minZoom, targetZoom))
                                }
                                .onEnded { _ in
                                    if zoomScale <= 1.0 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            zoomScale = 1.0
                                            panOffset = .zero
                                            dragTranslation = .zero
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                if zoomScale > 1.0 {
                                    zoomScale = 1.0
                                    panOffset = .zero
                                    dragTranslation = .zero
                                } else {
                                    zoomScale = 2.0
                                }
                            }
                        }
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: zoomScale)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if isLoading {
                ProgressView("Memuat citra...")
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Lapisan visualisasi belum tersedia untuk berkas ini.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Fixed, Stable Floating Control Bar (Top)
            VStack {
                HStack {
                    // Quick Status Pill on Top Left
                    HStack(spacing: 6) {
                        Circle()
                            .fill(zoomScale > 1.0 ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(zoomScale > 1.0 ? "Mode Detail (Geser untuk navigasi)" : "Tampilan Penuh (Fit)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
                    .padding(14)

                    Spacer()

                    // Controls Pill on Top Right
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                                zoomScale = 1.0
                                panOffset = .zero
                                dragTranslation = .zero
                            }
                        } label: {
                            Text("Fit")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(zoomScale == 1.0 ? Color.white.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .help("Sesuaikan gambar pas ke layar")

                        Divider().frame(height: 14)

                        Button {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                                zoomScale = max(minZoom, zoomScale - 0.25)
                                if zoomScale <= 1.0 {
                                    panOffset = .zero
                                    dragTranslation = .zero
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(zoomScale <= 1.0)
                        .opacity(zoomScale <= 1.0 ? 0.4 : 1.0)
                        .help("Perkecil zoom")

                        Text("\(Int(round(zoomScale * 100)))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 48, alignment: .center)

                        Button {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                                zoomScale = min(maxZoom, zoomScale + 0.25)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(zoomScale >= maxZoom)
                        .opacity(zoomScale >= maxZoom ? 0.4 : 1.0)
                        .help("Perbesar zoom")

                        Divider().frame(height: 14)

                        if let imageURL {
                            Button {
                                let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
                                let suggested = "vari_\(layer.id.lowercased().replacingOccurrences(of: " ", with: "_")).\(ext)"
                                VariFilePanels.saveFile(
                                    from: imageURL,
                                    suggestedName: suggested,
                                    contentTypes: [.image]
                                )
                            } label: {
                                Image(systemName: "arrow.down.doc")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help("Simpan gambar lapisan ini ke disk")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    .padding(14)
                }
                Spacer()
            }
        }
        .frame(height: viewportHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
        .task(id: imageURL) {
            guard let imageURL else {
                image = nil
                return
            }
            isLoading = true
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: imageURL)
            }.value
            await MainActor.run {
                self.image = loaded
                self.isLoading = false
                self.zoomScale = 1.0
                self.panOffset = .zero
                self.dragTranslation = .zero
            }
        }
    }
}
