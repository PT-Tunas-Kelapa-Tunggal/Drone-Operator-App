import SwiftUI

struct MissionView: View {
    @ObservedObject var model: ControlViewModel
    @ObservedObject var link: LocalLink
    private var active: Bool { model.isActiveMission && model.selectedMissionIsCurrent }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.currentMissionName).font(KropsTypography.pageTitle)
                Spacer()
                Text("Tersimpan di Mac").font(.callout).foregroundStyle(.secondary)
            }
            if model.selectedMission?.phase == .completed {
                Text("Misi selesai. Area dan pengaturan tetap tersimpan di Mac.").foregroundStyle(.secondary)
                if let id = model.selectedMission?.remoteID {
                    Button("Lihat hasil misi") { model.showDatasets(missionID: id) }.kropsPrimaryAction()
                }
            } else if active {
                CaptureProgressView(model: model, link: link)
            } else {
                SurveyConfigurationView(model: model)
                    .disabled(model.hasLocalDraft && model.selectedMission?.preparationRequested == true)
            }
        }
    }
}
