import SwiftUI
import SwiftData

/// Always-visible strip at the top of the main window: watch for calls,
/// live AI, and a kill switch. Idle does not capture this Mac's microphone
/// or system audio — it only polls whether another app is already on a call.
struct CaptureKillSwitchBar: View {
    var viewModel: RecordingViewModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage("autoStartRecording") private var watchForMeetings = false
    @AppStorage(RecordingViewModel.liveIntelligenceDefaultsKey) private var liveAI = true

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.state != .idle {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isPaused ? Color.orange : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isPaused ? "PAUSED" : "REC")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(viewModel.isPaused ? Color.orange : Color.red)
                    Text(viewModel.formattedTime)
                        .font(.caption.monospacedDigit())
                }
            } else {
                Label(watchForMeetings ? "Waiting for a call" : "Not watching", systemImage: watchForMeetings ? "ear" : "ear.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(watchForMeetings ? .secondary : .tertiary)
                    .helpTip(.waitingForCall)
            }

            Toggle("Watch for meetings", isOn: $watchForMeetings)
                .toggleStyle(.checkbox)
                .font(.caption)
                .helpTip(.watchForMeetings)
                .disabled(viewModel.state != .idle && !watchForMeetings)

            Toggle("Live AI", isOn: $liveAI)
                .toggleStyle(.checkbox)
                .font(.caption)
                .helpTip(.liveAI)
                .onChange(of: liveAI) { _, enabled in
                    viewModel.setLiveIntelligenceEnabled(enabled)
                }

            Spacer(minLength: 8)

            Button {
                viewModel.killSwitch(in: modelContext)
                watchForMeetings = false
                liveAI = false
            } label: {
                Label("Stop all", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(viewModel.state == .idle && !watchForMeetings && !isAIBusy)
            .helpTip(.stopAll)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onChange(of: watchForMeetings) { _, enabled in
            viewModel.setAutoDetectionEnabled(enabled)
        }
        .onAppear {
            viewModel.setLiveIntelligenceEnabled(liveAI)
        }
    }

    private var isAIBusy: Bool {
        switch viewModel.aiActivityState {
        case .idle: false
        default: true
        }
    }
}
