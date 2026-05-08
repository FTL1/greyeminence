import SwiftUI
import SwiftData

/// Right panel during a live interview. Tabs between Transcript and Notes.
struct LiveInterviewView: View {
    @Environment(\.modelContext) private var modelContext
    var interviewViewModel: InterviewRecordingViewModel
    @State private var activeTab: PanelTab = .transcript

    enum PanelTab: String, CaseIterable {
        case transcript = "Transcript"
        case notes = "Notes"
    }

    private var recordingVM: RecordingViewModel {
        interviewViewModel.recordingViewModel
    }

    private var activePhaseNoteCount: Int {
        let activeID = interviewViewModel.interview?.activePhase?.id
        return interviewViewModel.notes.filter {
            $0.parentNote == nil && $0.phase?.id == activeID
        }.count
    }

    private func tabLabel(_ tab: PanelTab) -> String {
        switch tab {
        case .transcript: return tab.rawValue
        case .notes:
            return activePhaseNoteCount > 0
                ? "Notes  \(activePhaseNoteCount)"
                : "Notes"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker + recording status
            HStack(spacing: 6) {
                Picker("", selection: $activeTab) {
                    ForEach(PanelTab.allCases, id: \.self) { tab in
                        Text(tabLabel(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Spacer(minLength: 4)

                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(recordingVM.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.bar)

            Divider()

            switch activeTab {
            case .transcript:
                LiveTranscriptView(
                    segments: recordingVM.segments,
                    segmentConfidence: recordingVM.segmentConfidence,
                    scrollToSegmentID: Binding(
                        get: { interviewViewModel.scrollToSegmentID },
                        set: { interviewViewModel.scrollToSegmentID = $0 }
                    )
                )
            case .notes:
                ScrollView {
                    InterviewNotesTable(interviewViewModel: interviewViewModel)
                        .padding(8)
                }
            }
        }
    }
}
