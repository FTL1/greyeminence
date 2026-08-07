import SwiftUI
import SwiftData

/// Asks whether to record a detected call, anchored at the bottom of the main
/// window alongside the other status bars.
///
/// The same question is also posted as a system notification, since you are in
/// the calling app rather than this one when it fires. This bar is the copy
/// that cannot go missing: notification delivery depends on a permission that
/// may be off, and a prompt nobody sees is indistinguishable from no feature.
struct CallPromptBar: View {
    var viewModel: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let promptApp = viewModel.pendingCallPromptApp {
            HStack(spacing: 10) {
                Image(systemName: "phone.badge.waveform.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
                    .frame(width: 16, height: 16)

                Text("\(promptApp) call detected")
                    .font(.caption.weight(.medium))

                Spacer(minLength: 8)

                Button("Not Now") {
                    viewModel.dismissCallPrompt()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Record") {
                    viewModel.acceptCallPrompt(in: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .bottomActivityBarStyle()
            .animation(.easeInOut(duration: 0.2), value: promptApp)
        }
    }
}
