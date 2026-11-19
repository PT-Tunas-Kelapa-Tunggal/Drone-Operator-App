import SwiftUI

struct PreflightChecklistView: View {
    @ObservedObject var planner: FlightPlannerViewModel
    let canEdit: Bool
    let onChecklistChanged: () -> Void

    private var completedCount: Int {
        PreflightChecklistItem.allCases.filter { item in
            planner.checkedSOPItems.contains(item) && planner.precondition(for: item).met
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Checklist SOP Pra-Terbang")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(completedCount)/\(PreflightChecklistItem.allCases.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        completedCount == PreflightChecklistItem.allCases.count ? .green : .secondary)
            }

            Text(
                "Periksa seluruh poin keselamatan berikut. Mengubah parameter terbang akan me-reset seluruh daftar periksa."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PreflightChecklistItem.allCases) { item in
                    checklistRow(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func checklistRow(for item: PreflightChecklistItem) -> some View {
        let status = planner.precondition(for: item)
        let isChecked = planner.checkedSOPItems.contains(item) && status.met

        VStack(alignment: .leading, spacing: 2) {
            Toggle(
                isOn: Binding(
                    get: { isChecked },
                    set: { newValue in
                        guard canEdit, status.met else { return }
                        if newValue {
                            planner.checkedSOPItems.insert(item)
                        } else {
                            planner.checkedSOPItems.remove(item)
                        }
                        onChecklistChanged()
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status.met ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blocker = status.blockerReason {
                        Text(blocker)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(item.subtitle(route: planner.draft))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!canEdit || !status.met)
        }
    }
}
