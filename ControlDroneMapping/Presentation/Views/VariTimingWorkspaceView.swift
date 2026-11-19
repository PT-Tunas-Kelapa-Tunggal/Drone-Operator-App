import AppKit
import SwiftUI

/// Presents the full `krops_vari.timing` output inside **5. Hasil -> Jadwal Pemupukan**
/// so operators inspect rounds, daily L5/L8 weather windows, step waits, and 12-month climate basis
/// without needing raw JSON inspection.
public struct VariTimingContextSummary: Sendable, Equatable {
    public let farmName: String?
    public let coordinate: VariTimingRequest.Coordinate?
    public let fertilizingFrequencyPerYear: Int?
    public let selectedNPKType: ContractFertilizerType?
    public let dolomiteTotalKg: Double
    public let ureaTotalKg: Double
    public let npkTotalKg: Double
    public let blockerReason: String?

    public init(
        farmName: String? = nil,
        coordinate: VariTimingRequest.Coordinate? = nil,
        fertilizingFrequencyPerYear: Int? = nil,
        selectedNPKType: ContractFertilizerType? = nil,
        dolomiteTotalKg: Double = 0,
        ureaTotalKg: Double = 0,
        npkTotalKg: Double = 0,
        blockerReason: String? = nil
    ) {
        self.farmName = farmName
        self.coordinate = coordinate
        self.fertilizingFrequencyPerYear = fertilizingFrequencyPerYear
        self.selectedNPKType = selectedNPKType
        self.dolomiteTotalKg = dolomiteTotalKg
        self.ureaTotalKg = ureaTotalKg
        self.npkTotalKg = npkTotalKg
        self.blockerReason = blockerReason
    }
}

public struct VariTimingWorkspaceView: View {
    public let result: VariTimingExecutionResult?
    public let isRunning: Bool
    public let errorMessage: String?
    public let context: VariTimingContextSummary
    public let onRun: () -> Void
    public let onDismissError: (() -> Void)?

    @State private var isRemovedDaysExpanded = false
    @State private var isMonthlyClimateExpanded = false
    @State private var isCandidateSetsExpanded = false

    public init(
        result: VariTimingExecutionResult?,
        isRunning: Bool,
        errorMessage: String?,
        context: VariTimingContextSummary,
        onRun: @escaping () -> Void,
        onDismissError: (() -> Void)? = nil
    ) {
        self.result = result
        self.isRunning = isRunning
        self.errorMessage = errorMessage
        self.context = context
        self.onRun = onRun
        self.onDismissError = onDismissError
    }

    public var body: some View {
        Group {
            if let result {
                loadedReport(result)
            } else if isRunning {
                loadingState
            } else {
                emptyOrErrorState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KropsStyle.canvas)
    }

    // MARK: - Empty / Loading States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Menjalankan Analisis Jadwal Pemupukan…")
                .font(KropsTypography.sectionTitle)
            Text(
                "Menghitung putaran pemupukan, basis iklim bulanan NASA POWER, dan jendela tabur harian."
            )
            .font(KropsTypography.supporting)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
        }
        .padding(32)
    }

    private var emptyOrErrorState: some View {
        ContentUnavailableView {
            Label(
                errorMessage == nil ? "Jadwal Pemupukan" : "Analisis Jadwal Gagal",
                systemImage: errorMessage == nil ? "calendar.badge.clock" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(errorMessage == nil ? KropsStyle.accent : .red)
        } description: {
            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                } else if let blocker = context.blockerReason {
                    Text(blocker)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                } else {
                    Text(
                        "Analisis jadwal pemupukan menggabungkan batas kebun & frekuensi dari CloudKit dengan dosis pupuk hasil VARI & HARA."
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                }

                timingContextSummaryPills
            }
        } actions: {
            Button(errorMessage == nil ? "Jalankan Analisis Jadwal" : "Coba Lagi", action: onRun)
                .kropsPrimaryAction(size: .large)
                .disabled(context.blockerReason != nil || isRunning)
        }
        .padding(24)
    }

    @ViewBuilder
    private var timingContextSummaryPills: some View {
        VStack(spacing: 6) {
            if let coordinate = context.coordinate {
                let farmPrefix = context.farmName.map { "\($0) · " } ?? ""
                let freqText = context.fertilizingFrequencyPerYear.map { "\($0)x/tahun" } ?? "Frekuensi —"
                Text("\(farmPrefix)\(TimingFormat.coordinate(coordinate)) · \(freqText)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if context.dolomiteTotalKg > 0 || context.ureaTotalKg > 0 || context.npkTotalKg > 0 {
                let npkTitle = context.selectedNPKType?.rawValue ?? "NPK"
                Text(
                    String(
                        format: "Dosis input: Dolomite %.1f kg · Urea %.1f kg · %@ %.1f kg",
                        context.dolomiteTotalKg,
                        context.ureaTotalKg,
                        npkTitle,
                        context.npkTotalKg
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
    }

    // MARK: - Loaded Report

    private func loadedReport(_ execution: VariTimingExecutionResult) -> some View {
        let schedule = execution.schedule
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isRunning {
                    runningBanner
                }
                if let errorMessage {
                    errorBanner(errorMessage)
                }

                reportHeader(execution)
                kpiGrid(schedule)

                if !schedule.flags.isEmpty {
                    flagsSection(schedule.flags)
                }

                dailySection(schedule)
                roundsSection(schedule)
                weatherBasisSection(schedule)
                diagnosticsFooter(execution)
            }
            .padding(24)
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Memperbarui jadwal pemupukan dari engine…")
                .font(KropsTypography.supporting.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pembaruan Jadwal Gagal")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onDismissError {
                Button("Tutup", action: onDismissError)
                    .kropsToolbarAction(size: .compact)
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.25)))
    }

    private func reportHeader(_ execution: VariTimingExecutionResult) -> some View {
        let schedule = execution.schedule
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Jadwal Pemupukan \(String(schedule.planYear))")
                    .font(KropsTypography.pageTitle)
                TimingStatusBadge(
                    text: "Sinkron CloudKit & VARI",
                    icon: "checkmark.icloud.fill",
                    tone: .positive
                )
                .help(
                    "Koordinat kebun, frekuensi pemupukan tahunan, serta dosis Dolomite, Urea, dan NPK bersumber dari CloudKit & hasil VARI & HARA."
                )
                Spacer()
            }

            HStack(spacing: 12) {
                Label(
                    "Frekuensi: \(execution.request.fertilizerFreq)x/thn",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                Text("·")
                Label(
                    "Tanggal acuan WIB: \(TimingFormat.date(schedule.today))",
                    systemImage: "calendar"
                )
                Text("·")
                Label(
                    TimingFormat.coordinate(
                        VariTimingRequest.Coordinate(
                            latitude: execution.request.latitude,
                            longitude: execution.request.longitude
                        )),
                    systemImage: "location"
                )
                Text("·")
                Label(
                    "Diperbarui: \(execution.ranAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "clock"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - KPI Strip

    private func kpiGrid(_ schedule: VariTimingSchedule) -> some View {
        let allSteps = schedule.rounds.flatMap(\.steps)
        let doneCount = allSteps.filter { $0.card.state == "done" }.count
        let overdueCount = allSteps.filter { $0.card.state == "overdue" }.count
        let readyCount = allSteps.filter { $0.card.state == "ready" }.count

        let activeRound =
            schedule.rounds.first(where: { $0.status == "ongoing" })
            ?? schedule.rounds.first(where: { $0.status == "upcoming" })
            ?? schedule.rounds.last

        let roundMetricTitle: String
        let roundMetricSub: String
        if let r = activeRound {
            if let day = r.dayOfRound {
                roundMetricTitle = "Putaran \(r.round)"
                roundMetricSub = "Hari ke-\(day) dari \(r.totalDays) (\(r.startMonthName)–\(r.endMonthName))"
            } else if let daysUntil = r.daysUntilStart {
                roundMetricTitle = "Putaran \(r.round)"
                roundMetricSub = "Mulai dlm \(daysUntil) hari (\(r.startMonthName)–\(r.endMonthName))"
            } else {
                roundMetricTitle = "Putaran \(r.round)"
                roundMetricSub =
                    "\(r.startMonthName)–\(r.endMonthName) · \(TimingLabels.roundStatus(r.status))"
            }
        } else {
            roundMetricTitle = "—"
            roundMetricSub = "Belum ada putaran terbuka"
        }

        let dailyRound = schedule.rounds.first(where: { $0.daily != nil })
        let l8Value: String
        let l8Sub: String
        let safeValue: String
        let safeSub: String

        if let daily = dailyRound?.daily {
            l8Value = TimingLabels.l8State(daily.l8.state)
            let p30Text = daily.l5?.p30Mm.map { "\(TimingFormat.number($0, decimals: 1)) mm" } ?? "P30 N/A"
            l8Sub = "Gerbang: \(TimingLabels.gate(daily.l8.monthGate.gate)) · P30 \(p30Text)"

            safeValue = "\(daily.l8.safeDays.count) hari"
            if let firstSafe = daily.l8.safeDays.first {
                safeSub = "Terdekat: \(TimingFormat.shortDate(firstSafe))"
            } else if let wait = daily.wait, !wait.isEmpty {
                safeSub = wait
            } else {
                safeSub = "Belum ada hari aman di prakiraan"
            }
        } else {
            l8Value = "Nonaktif / N/A"
            l8Sub = "Mode --no-daily atau di luar horizon 10 hari"
            safeValue = "—"
            safeSub = "Menunggu jendela prakiraan harian"
        }

        let stepSub: String
        if overdueCount > 0 {
            stepSub = "\(overdueCount) terlewat · \(readyCount) siap tabur"
        } else {
            stepSub = "\(readyCount) siap tabur · \(allSteps.count) total langkah"
        }

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 205, maximum: 280), spacing: 12)],
            spacing: 12
        ) {
            TimingKpiCard(
                title: "Frekuensi Tahunan",
                value: "\(schedule.roundsPerYear)x / thn",
                subtitle: "Tahun rencana \(schedule.planYear) · \(schedule.rounds.count) putaran",
                systemImage: "repeat"
            )
            TimingKpiCard(
                title: "Putaran Aktif / Berikutnya",
                value: roundMetricTitle,
                subtitle: roundMetricSub,
                systemImage: "calendar.circle"
            )
            TimingKpiCard(
                title: "Progres Langkah",
                value: "\(doneCount)/\(allSteps.count)",
                subtitle: stepSub,
                systemImage: "checklist"
            )
            TimingKpiCard(
                title: "Jendela Harian (L8)",
                value: l8Value,
                subtitle: "\(l8Sub) · Hari aman: \(safeValue) (\(safeSub))",
                systemImage: "cloud.sun.rain"
            )
        }
    }

    // MARK: - Flags Section

    private func flagsSection(_ flags: [String]) -> some View {
        ControlPanel("Catatan & Peringatan Engine (\(flags.count))", state: nil) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        Text(flag)
                            .font(KropsTypography.supporting)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Daily Weather Gate Section (L5 + L8)

    @ViewBuilder
    private func dailySection(_ schedule: VariTimingSchedule) -> some View {
        let dailyRounds = schedule.rounds.compactMap { round in
            round.daily.map { (round: round, daily: $0) }
        }

        if dailyRounds.isEmpty {
            ControlPanel("Evaluasi Cuaca Harian (L5 & L8)", state: nil) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text(
                        "Data cuaca harian (`daily`) tidak dimuat—baik karena opsi `--no-daily` di Pengaturan aktif atau belum ada putaran yang sedang berjalan / dimulai dalam horizon prakiraan 10 hari."
                    )
                    .font(KropsTypography.supporting)
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            ForEach(dailyRounds, id: \.round.id) { item in
                let daily = item.daily
                ControlPanel(
                    "Evaluasi Cuaca Harian · Putaran \(item.round.round)",
                    state: nil
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Label(
                                "Diperiksa: \(TimingFormat.date(daily.checkedOn))",
                                systemImage: "checkmark.shield"
                            )
                            Text("·")
                            Label(
                                "Hari referensi: \(TimingFormat.date(daily.referenceDay))",
                                systemImage: "calendar"
                            )
                            Spacer()
                            if let wait = daily.wait, !wait.isEmpty {
                                TimingStatusBadge(text: wait, icon: "pause.circle.fill", tone: .warning)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 320, maximum: 540), spacing: 12)],
                            spacing: 12
                        ) {
                            l5Card(daily.l5)
                            l8Card(daily.l8)
                        }

                        DisclosureGroup(
                            isExpanded: $isRemovedDaysExpanded
                        ) {
                            removedDaysDetail(daily.l8.removed)
                                .padding(.top, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(.secondary)
                                Text(
                                    daily.l8.removed.isEmpty
                                        ? "Hari Dihapus dari Prakiraan (Tidak ada hari dihapus)"
                                        : "Hari Dihapus dari Prakiraan (\(daily.l8.removed.totalCount) hari)"
                                )
                                .font(.callout.weight(.medium))
                            }
                        }
                    }
                }
            }
        }
    }

    private func l5Card(_ l5: VariTimingL5Assessment?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("L5 Keseimbangan Air (P30)")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let stress = l5?.waterStress {
                    TimingStatusBadge(
                        text: stress ? "Stres Air (< 60 mm)" : "Air Cukup (>= 60 mm)",
                        icon: stress ? "drop.triangle.fill" : "drop.fill",
                        tone: stress ? .warning : .positive
                    )
                } else {
                    TimingStatusBadge(text: "P30 Tidak Tersedia", icon: "questionmark.circle", tone: .neutral)
                }
            }

            Divider()

            if let l5 {
                VStack(alignment: .leading, spacing: 6) {
                    keyValueRow(
                        "Total Hujan 30 Hari",
                        l5.p30Mm.map { "\(TimingFormat.number($0, decimals: 1)) mm" } ?? "N/A"
                    )
                    if let start = l5.p30StartDate, let end = l5.p30EndDate {
                        keyValueRow(
                            "Rentang P30", "\(TimingFormat.shortDate(start)) – \(TimingFormat.shortDate(end))"
                        )
                    }
                    keyValueRow("Sumber Data", l5.p30Source ?? "—")
                    keyValueRow("Kualitas Data", l5.p30Quality ?? "—")
                    if let missing = l5.p30MissingDays, !missing.isEmpty {
                        let summary =
                            missing
                            .sorted { $0.key < $1.key }
                            .map { "\($0.key): \($0.value)h" }
                            .joined(separator: ", ")
                        keyValueRow("Hari Kosong", summary)
                    }
                }
            } else {
                Text("Rekaman L5 P30 tidak tersedia untuk evaluasi ini.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
    }

    private func l8Card(_ l8: VariTimingL8Assessment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("L8 Gerbang Bulan & Prakiraan")
                    .font(.callout.weight(.semibold))
                Spacer()
                TimingStatusBadge(
                    text: TimingLabels.l8State(l8.state),
                    icon: TimingLabels.l8Icon(l8.state),
                    tone: TimingLabels.l8Tone(l8.state)
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                keyValueRow(
                    "Gerbang Bulan \(TimingFormat.monthName(l8.monthGate.month))",
                    "\(TimingFormat.number(l8.monthGate.avgMm, decimals: 1)) mm · \(TimingLabels.gate(l8.monthGate.gate))"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Hari Aman Menabur (\(l8.safeDays.count)):")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if l8.safeDays.isEmpty {
                    Text("Tidak ada hari aman dalam jendela prakiraan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowDateWrap(dates: l8.safeDays)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
    }

    @ViewBuilder
    private func removedDaysDetail(_ removed: VariTimingRemovedDays) -> some View {
        if removed.isEmpty {
            Text("Tidak ada hari yang dikeluarkan oleh filter hujan lebat atau batas akhir cache.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !removed.heavy.isEmpty {
                    removedGroupRow("Hujan Lebat (> 25 mm/hari)", dates: removed.heavy, tone: .critical)
                }
                if !removed.dayBeforeHeavy.isEmpty {
                    removedGroupRow(
                        "Sehari Sebelum Hujan Lebat (risiko pencucian)",
                        dates: removed.dayBeforeHeavy,
                        tone: .warning
                    )
                }
                if !removed.lastCached.isEmpty {
                    removedGroupRow(
                        "Hari Terakhir Prakiraan (tanpa data esok hari)",
                        dates: removed.lastCached,
                        tone: .neutral
                    )
                }
            }
            .padding(12)
            .background(KropsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
        }
    }

    private func removedGroupRow(_ title: String, dates: [String], tone: TimingBadgeTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(dates, id: \.self) { day in
                    TimingStatusBadge(text: TimingFormat.shortDate(day), icon: nil, tone: tone)
                }
            }
        }
    }

    // MARK: - Fertilization Rounds Section

    private func roundsSection(_ schedule: VariTimingSchedule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Putaran Pemupukan (\(schedule.rounds.count))")
                .font(KropsTypography.sectionTitle)

            if schedule.rounds.isEmpty {
                ControlPanel("Belum Ada Jadwal Putaran", state: nil) {
                    Text(
                        "Tidak ditemukan kombinasi \(schedule.roundsPerYear) bulan terbuka dengan jarak antarpemupukan \(12 / max(schedule.roundsPerYear, 1)) bulan."
                    )
                    .font(KropsTypography.supporting)
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(schedule.rounds) { round in
                    roundCard(round)
                }
            }
        }
    }

    private func roundCard(_ round: VariTimingRound) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Putaran \(round.round) · \(round.startMonthName) – \(round.endMonthName)")
                        .font(KropsTypography.sectionTitle)
                    Text(
                        "\(TimingFormat.date(round.startDate)) – \(TimingFormat.date(round.endDate)) · \(round.totalDays) hari"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                TimingStatusBadge(
                    text: TimingLabels.roundCardText(round.card, fallbackStatus: round.status),
                    icon: TimingLabels.roundCardIcon(round.card.state),
                    tone: TimingLabels.roundCardTone(round.card.state)
                )
            }
            .padding(18)

            Divider()

            if round.steps.isEmpty {
                Text("Tidak ada pupuk yang terjadwal pada putaran ini.")
                    .font(KropsTypography.supporting)
                    .foregroundStyle(.secondary)
                    .padding(18)
            } else {
                stepTableHeader
                Divider()
                ForEach(Array(round.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step)
                    if index < round.steps.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
    }

    private var stepTableHeader: some View {
        HStack(spacing: 12) {
            Text("Urutan & Pupuk")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Dosis / Putaran")
                .frame(width: 150, alignment: .trailing)
            Text("Jeda Setelah Tabur")
                .frame(width: 190, alignment: .leading)
            Text("Status Kartu")
                .frame(width: 185, alignment: .leading)
            Text("Jadwal Harian")
                .frame(width: 195, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(KropsStyle.canvas)
    }

    private func stepRow(_ step: VariTimingStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 1. Step + Product
            HStack(alignment: .top, spacing: 10) {
                Text("\(step.step)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(width: 24, height: 24)
                    .background(KropsStyle.accent.opacity(0.12), in: Circle())
                    .foregroundStyle(KropsStyle.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.displayName)
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 6) {
                        if let rawName = step.name, rawName != step.displayName {
                            Text(rawName)
                        }
                        if step.fertilizerId == nil {
                            Text("Tanpa ID (tidak dapat ditandai)")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            // 2. Dose
            VStack(alignment: .trailing, spacing: 2) {
                Text(step.doseKg.map { "\(TimingFormat.number($0, decimals: 1)) kg" } ?? "—")
                    .font(.callout.weight(.semibold).monospacedDigit())
                Text(TimingFormat.doseSubtitle(annualKg: step.annualDoseKg, bagKg: step.bagKg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .trailing)

            // 3. Wait window after step
            VStack(alignment: .leading, spacing: 4) {
                if let wait = step.waitAfterDays {
                    TimingStatusBadge(
                        text: TimingLabels.waitText(wait),
                        icon: wait.state == "done" ? "checkmark" : "hourglass",
                        tone: TimingLabels.waitTone(wait.state)
                    )
                    if let until = wait.until {
                        Text("Tersedia s.d. \(TimingFormat.shortDate(until))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Langkah terakhir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, alignment: .leading)

            // 4. Card state
            VStack(alignment: .leading, spacing: 4) {
                TimingStatusBadge(
                    text: TimingLabels.stepCardTitle(step.card.state),
                    icon: TimingLabels.stepCardIcon(step.card.state),
                    tone: TimingLabels.stepCardTone(step.card.state)
                )
                if let detail = TimingLabels.stepCardDetail(step.card) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 185, alignment: .leading)

            // 5. Daily schedule
            VStack(alignment: .leading, spacing: 4) {
                if let sched = step.schedule {
                    TimingStatusBadge(
                        text: TimingLabels.scheduleTitle(sched),
                        icon: TimingLabels.scheduleIcon(sched.status),
                        tone: TimingLabels.scheduleTone(sched.status)
                    )
                    if let note = sched.wait {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Tidak dijadwalkan harian")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 195, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Climate Basis & Candidate Sets (Collapsible)

    private func weatherBasisSection(_ schedule: VariTimingSchedule) -> some View {
        let basis = schedule.weatherBasis
        let chosenMonths = schedule.rounds.map(\.startMonthName)
        let periodText = basis.period.map { $0.map(String.init).joined(separator: "–") } ?? "—"

        return ControlPanel("Basis Iklim & Pemilihan Bulan (\(periodText))", state: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text(basis.rule)
                    .font(KropsTypography.supporting)
                Text(basis.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                DisclosureGroup(isExpanded: $isMonthlyClimateExpanded) {
                    monthlyTable(basis.months)
                        .padding(.top, 10)
                } label: {
                    Label(
                        "Tabel Curah Hujan Bulanan NASA POWER (12 Bulan)",
                        systemImage: "tablecells"
                    )
                    .font(.callout.weight(.medium))
                }

                Divider()

                DisclosureGroup(isExpanded: $isCandidateSetsExpanded) {
                    candidateSetsTable(basis.candidateSets, chosenMonths: chosenMonths)
                        .padding(.top, 10)
                } label: {
                    Label(
                        "Kandidat Kombinasi Bulan (\(basis.candidateSets.count) opsi)",
                        systemImage: "calendar"
                    )
                    .font(.callout.weight(.medium))
                }
            }
        }
    }

    private func monthlyTable(_ months: [String: VariTimingMonthlyClimate]) -> some View {
        let sortedEntries =
            months
            .compactMap { key, value -> (month: Int, climate: VariTimingMonthlyClimate)? in
                guard let m = Int(key) else { return nil }
                return (m, value)
            }
            .sorted { $0.month < $1.month }

        return VStack(spacing: 0) {
            HStack {
                Text("Bulan")
                    .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                Text("Rerata Hujan")
                    .frame(width: 130, alignment: .trailing)
                Text("Dalam Rentang 100–200 mm")
                    .frame(width: 180, alignment: .trailing)
                Text("Gerbang Bulan")
                    .frame(width: 120, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(KropsStyle.canvas)

            Divider()

            ForEach(Array(sortedEntries.enumerated()), id: \.element.month) { index, entry in
                HStack {
                    Text("\(entry.month). \(entry.climate.name)")
                        .font(.callout)
                        .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                    Text("\(TimingFormat.number(entry.climate.avgMm, decimals: 1)) mm")
                        .font(.callout.monospacedDigit())
                        .frame(width: 130, alignment: .trailing)
                    Text("\(TimingFormat.number(entry.climate.inBandShare * 100, decimals: 1))%")
                        .font(.callout.monospacedDigit())
                        .frame(width: 180, alignment: .trailing)
                    TimingStatusBadge(
                        text: TimingLabels.gate(entry.climate.gate),
                        icon: nil,
                        tone: TimingLabels.gateTone(entry.climate.gate)
                    )
                    .frame(width: 120, alignment: .center)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                if index < sortedEntries.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
    }

    @ViewBuilder
    private func candidateSetsTable(
        _ sets: [VariTimingCandidateSet],
        chosenMonths: [String]
    ) -> some View {
        if sets.isEmpty {
            Text("Tidak ada kombinasi bulan yang memenuhi syarat gerbang terbuka.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, candidate in
                    let isChosen = candidate.months == chosenMonths
                    HStack {
                        Text(candidate.months.joined(separator: " · "))
                            .font(.callout.weight(isChosen ? .semibold : .regular))
                        Spacer()
                        Text("Skor In-Band: \(TimingFormat.number(candidate.inBandShare, decimals: 3))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if isChosen {
                            TimingStatusBadge(text: "Dipilih", icon: "checkmark.circle.fill", tone: .positive)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isChosen ? KropsStyle.accent.opacity(0.06) : Color.clear)
                    if index < sets.count - 1 {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(KropsStyle.border))
        }
    }

    // MARK: - Diagnostics Footer

    private func diagnosticsFooter(_ execution: VariTimingExecutionResult) -> some View {
        HStack(spacing: 12) {
            Text(
                "Schema v\(execution.schedule.schemaVersion) · Output: \(execution.resultJSONURL.lastPathComponent) · Cache: \(execution.cacheDirectoryURL.lastPathComponent)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([execution.resultJSONURL])
            } label: {
                Label("Tampilkan di Finder", systemImage: "folder")
            }
            .kropsToolbarAction(size: .compact)
        }
        .padding(.top, 4)
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Compact Subviews

private struct TimingKpiCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(KropsTypography.metric)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(KropsStyle.border))
    }
}

private enum TimingBadgeTone {
    case neutral
    case info
    case positive
    case warning
    case critical

    var foreground: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return .blue
        case .positive: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var background: Color {
        switch self {
        case .neutral: return Color.primary.opacity(0.06)
        case .info: return Color.blue.opacity(0.12)
        case .positive: return Color.green.opacity(0.14)
        case .warning: return Color.orange.opacity(0.14)
        case .critical: return Color.red.opacity(0.14)
        }
    }
}

private struct TimingStatusBadge: View {
    let text: String
    let icon: String?
    let tone: TimingBadgeTone

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tone.background, in: Capsule())
        .foregroundStyle(tone.foreground)
    }
}

private struct FlowDateWrap: View {
    let dates: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 95, maximum: 130), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(dates, id: \.self) { day in
                TimingStatusBadge(
                    text: TimingFormat.shortDate(day),
                    icon: "checkmark",
                    tone: .positive
                )
            }
        }
    }
}

// MARK: - Formatting & Domain Labels

private enum TimingFormat {
    private static let isoParser: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private static let idDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "d MMM yyyy"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private static let idShortDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "EEE, d MMM"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    private static let monthsID = [
        "Januari", "Februari", "Maret", "April", "Mei", "Juni",
        "Juli", "Agustus", "September", "Oktober", "November", "Desember",
    ]

    static func date(_ iso: String) -> String {
        guard let parsed = isoParser.date(from: iso) else { return iso }
        return idDate.string(from: parsed)
    }

    static func shortDate(_ iso: String) -> String {
        guard let parsed = isoParser.date(from: iso) else { return iso }
        return idShortDate.string(from: parsed)
    }

    static func monthName(_ month: Int) -> String {
        guard (1...monthsID.count).contains(month) else { return "Bulan \(month)" }
        return monthsID[month - 1]
    }

    static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    static func coordinate(_ c: VariTimingRequest.Coordinate) -> String {
        String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    static func doseSubtitle(annualKg: Double?, bagKg: Double?) -> String {
        var parts: [String] = []
        if let annualKg {
            parts.append("Thn: \(number(annualKg, decimals: 0)) kg")
        }
        if let bagKg, bagKg > 0 {
            parts.append("Sak \(number(bagKg, decimals: 0)) kg")
        }
        return parts.joined(separator: " · ")
    }
}

private enum TimingLabels {
    static func roundStatus(_ status: String) -> String {
        switch status {
        case "upcoming": return "Akan Datang"
        case "ongoing": return "Sedang Berlangsung"
        case "done": return "Selesai"
        default: return status
        }
    }

    static func roundCardText(_ card: VariTimingRoundCard, fallbackStatus: String) -> String {
        switch card.state {
        case "upcoming":
            if let days = card.daysUntilStart { return "Dimulai dalam \(days) hari" }
            return "Akan Datang"
        case "ongoing":
            if let day = card.dayOfRound, let total = card.totalDays {
                return "Berjalan · Hari \(day)/\(total)"
            }
            return "Sedang Berjalan"
        case "started":
            if let started = card.startedOn { return "Dimulai \(TimingFormat.shortDate(started))" }
            return "Sudah Dimulai"
        case "period_passed":
            if let end = card.periodEnd { return "Periode Berakhir \(TimingFormat.shortDate(end))" }
            return "Periode Terlewati"
        case "completed":
            if let done = card.completedOn { return "Tuntas \(TimingFormat.shortDate(done))" }
            return "Putaran Selesai"
        default:
            return roundStatus(fallbackStatus)
        }
    }

    static func roundCardIcon(_ state: String) -> String {
        switch state {
        case "completed": return "checkmark.circle.fill"
        case "started", "ongoing": return "play.circle.fill"
        case "period_passed": return "exclamationmark.circle.fill"
        default: return "clock"
        }
    }

    static func roundCardTone(_ state: String) -> TimingBadgeTone {
        switch state {
        case "completed": return .positive
        case "started", "ongoing": return .info
        case "period_passed": return .critical
        default: return .neutral
        }
    }

    static func waitText(_ wait: VariTimingWaitWindow) -> String {
        let range = wait.max.map { "\(wait.min)–\($0) hari" } ?? "≥ \(wait.min) hari"
        switch wait.state {
        case "counting": return "Jeda \(range) · Berhitung"
        case "done": return "Jeda \(range) · Terpenuhi"
        default: return "Tunggu \(range)"
        }
    }

    static func waitTone(_ state: String) -> TimingBadgeTone {
        switch state {
        case "counting": return .warning
        case "done": return .positive
        default: return .neutral
        }
    }

    static func stepCardTitle(_ state: String) -> String {
        switch state {
        case "locked": return "Terkunci"
        case "ready": return "Siap Dipupuk"
        case "waiting": return "Menunggu Jeda"
        case "done": return "Selesai"
        case "overdue": return "Terlewat"
        default: return state
        }
    }

    static func stepCardIcon(_ state: String) -> String {
        switch state {
        case "locked": return "lock.fill"
        case "ready": return "checkmark.seal"
        case "waiting": return "hourglass"
        case "done": return "checkmark.circle.fill"
        case "overdue": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    static func stepCardTone(_ state: String) -> TimingBadgeTone {
        switch state {
        case "ready": return .info
        case "done": return .positive
        case "waiting": return .warning
        case "overdue": return .critical
        default: return .neutral
        }
    }

    static func stepCardDetail(_ card: VariTimingStepCard) -> String? {
        switch card.state {
        case "done":
            return card.doneOn.map { "Pada \(TimingFormat.shortDate($0))" }
        case "waiting":
            return card.availableFrom.map { "Mulai \(TimingFormat.shortDate($0))" }
        case "ready":
            if let from = card.availableFrom, let end = card.deadline {
                return "\(TimingFormat.shortDate(from)) – \(TimingFormat.shortDate(end))"
            }
            return card.deadline.map { "Batas \(TimingFormat.shortDate($0))" }
        case "overdue":
            return card.overdueSince.map { "Batas \(TimingFormat.shortDate($0))" }
        default:
            return nil
        }
    }

    static func scheduleTitle(_ schedule: VariTimingStepSchedule) -> String {
        switch schedule.status {
        case "done":
            return schedule.date.map { "Selesai \(TimingFormat.shortDate($0))" } ?? "Selesai"
        case "planned":
            return schedule.date.map { "Tabur \(TimingFormat.shortDate($0))" } ?? "Terjadwal"
        case "not_before":
            return schedule.notBefore.map { "Paling cepat \(TimingFormat.shortDate($0))" }
                ?? "Di Luar Prakiraan"
        case "wait":
            return "Tunggu Kondisi"
        default:
            return schedule.status
        }
    }

    static func scheduleIcon(_ status: String) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "planned": return "calendar.badge.checkmark"
        case "not_before": return "calendar.badge.clock"
        case "wait": return "pause.circle.fill"
        default: return "calendar"
        }
    }

    static func scheduleTone(_ status: String) -> TimingBadgeTone {
        switch status {
        case "done": return .positive
        case "planned": return .info
        case "not_before", "wait": return .warning
        default: return .neutral
        }
    }

    static func gate(_ gate: String) -> String {
        switch gate {
        case "open": return "Terbuka"
        case "cek": return "Cek Lapangan"
        case "tunda": return "Tunda"
        default: return gate
        }
    }

    static func gateTone(_ gate: String) -> TimingBadgeTone {
        switch gate {
        case "open": return .positive
        case "cek": return .warning
        case "tunda": return .critical
        default: return .neutral
        }
    }

    static func l8State(_ state: String) -> String {
        switch state {
        case "jendela_tabur": return "Jendela Tabur"
        case "cek_hujan": return "Cek Hujan"
        case "cek": return "Cek Kelembaban"
        case "tunda": return "Tunda"
        default: return state
        }
    }

    static func l8Icon(_ state: String) -> String {
        switch state {
        case "jendela_tabur": return "sun.max.fill"
        case "cek_hujan", "cek": return "cloud.rain.fill"
        case "tunda": return "xmark.octagon.fill"
        default: return "cloud"
        }
    }

    static func l8Tone(_ state: String) -> TimingBadgeTone {
        switch state {
        case "jendela_tabur": return .positive
        case "cek_hujan", "cek": return .warning
        case "tunda": return .critical
        default: return .neutral
        }
    }
}
