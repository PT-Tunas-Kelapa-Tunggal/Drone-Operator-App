import AppKit
import SwiftUI

struct MissionFooterView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    private var active: Bool { model.isActiveMission && model.selectedMissionIsCurrent }
    private var showingResults: Bool { model.step == .datasets }
    var body: some View {
        let readiness = model.readiness()
        return HStack(spacing: 16) {
            if let pending = model.pending {
                ProgressView().controlSize(.small)
                Text(pending.action.userTitle + "…").font(.callout)
            } else if showingResults {
                Text(link.receiving ? "Transfer berlangsung…" : link.transferStatus).font(.callout)
                    .foregroundStyle(.secondary)
            } else if active {
                Text(
                    model.telemetry.phase == .paused
                        ? "Misi dijeda" : "Capture mandiri • iPhone tetap membuka DroneCam"
                ).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        model.iphoneCaptureStatus,
                        systemImage: model.iphoneReadyForCapture
                            ? "checkmark.circle.fill" : "iphone"
                    )
                    .font(.callout).foregroundStyle(model.iphoneReadyForCapture ? Color.green : Color.orange)
                    if !model.iphoneReadyForCapture {
                        Text(model.capturePreparationAdvice).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
            if !showingResults {
                if active {
                    if model.telemetry.phase == .paused {
                        Button("Lanjut • 3–2–1") { model.send(.resume) }.disabled(!model.canOperate)
                    } else {
                        Button("Jeda") { model.send(.pause) }.disabled(
                            !link.connected || !model.freshness() || model.pending != nil)
                    }
                    Button("Selesai") { model.send(.finish) }.disabled(!model.canOperate)
                } else {
                    Button("Mulai capture • 3–2–1") { model.send(.start) }.kropsPrimaryAction(
                        size: .large
                    ).tint(KropsStyle.accent).disabled(!readiness.canStart)
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 16).background(KropsStyle.surface)
    }
}
