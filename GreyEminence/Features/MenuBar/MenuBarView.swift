import SwiftUI
import SwiftData

struct MenuBarView: View {
    var viewModel: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.state {
            case .recording:
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording — \(viewModel.formattedTime)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()

                Button("Pause Recording") {
                    viewModel.pauseRecording()
                }

                Button("Stop Recording") {
                    viewModel.stopRecording(in: modelContext)
                }

            case .paused:
                HStack {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Paused — \(viewModel.formattedTime)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()

                Button("Resume Recording") {
                    viewModel.resumeRecording()
                }

                Button("Stop Recording") {
                    viewModel.stopRecording(in: modelContext)
                }

            case .idle:
                // A detected call we chose not to auto-record. Offered here
                // because this menu is reachable without leaving the call.
                if let promptApp = viewModel.pendingCallPromptApp {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.badge.waveform.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(promptApp) call detected")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Button("Record This Call") {
                        viewModel.acceptCallPrompt(in: modelContext)
                    }
                    Button("Not Now") {
                        viewModel.dismissCallPrompt()
                    }

                    Divider()
                }

                Button("Start Recording") {
                    viewModel.startRecording(in: modelContext)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            Divider()

            Button("Open \(AppIdentity.displayName)") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
