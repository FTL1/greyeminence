import SwiftUI

/// Side panel shown next to the recording pane during a live meeting. Flips
/// between the live transcript and the meeting prep (carried-over tasks, open
/// questions, and prior topics) so the user can glance at talking points
/// mid-meeting without leaving the recording view.
///
/// The Prep tab only appears when there's prep to show — a recurring meeting
/// with prior occurrences (`MeetingPrepContext.shouldDisplay`). For one-off
/// meetings the panel is just the transcript, exactly as before, so we never
/// surface an empty toggle.
struct RecordingInspectorPanel: View {
    @Bindable var viewModel: RecordingViewModel

    enum Mode: Hashable { case transcript, prep }
    @State private var mode: Mode = .transcript

    private var showsPrepTab: Bool {
        viewModel.prepContext?.shouldDisplay == true
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPrepTab {
                Picker("View", selection: $mode) {
                    Text("Transcript").tag(Mode.transcript)
                    Text("Prep").tag(Mode.prep)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
            }

            if mode == .prep, showsPrepTab, let prep = viewModel.prepContext {
                ScrollView {
                    MeetingPrepView(context: prep)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LiveTranscriptView(
                    segments: viewModel.segments,
                    segmentConfidence: viewModel.segmentConfidence
                )
            }
        }
        // If prep stops being applicable mid-recording (e.g. the calendar link
        // is cleared), drop back to the transcript so the toggle never strands
        // the user on an empty pane.
        .onChange(of: showsPrepTab) { _, hasPrep in
            if !hasPrep { mode = .transcript }
        }
    }
}
