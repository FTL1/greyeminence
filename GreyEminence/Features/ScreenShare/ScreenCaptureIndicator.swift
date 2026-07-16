import SwiftUI

/// Toolbar chip showing screen-share capture status during a recording.
/// Clicking opens the capture popover (preview, controls, window picker).
/// Renders nothing when the feature is off for this recording.
struct ScreenCaptureIndicator: View {
    @Bindable var viewModel: RecordingViewModel
    @State private var showPopover = false
    @State private var showWindowPicker = false

    var body: some View {
        switch viewModel.screenCaptureState {
        case .off:
            EmptyView()
        default:
            Button {
                showPopover.toggle()
            } label: {
                chipLabel
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ScreenCapturePopover(viewModel: viewModel, showWindowPicker: $showWindowPicker)
            }
            .sheet(isPresented: $showWindowPicker) {
                ScreenShareWindowPickerSheet(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var chipLabel: some View {
        switch viewModel.screenCaptureState {
        case .off:
            EmptyView()

        case .watching:
            HStack(spacing: 4) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.caption2)
                Text(viewModel.screenCaptureUserPaused ? "Capture paused" : "Watching for shares")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .help("Screen-share capture is on — waiting for a popped-out share window")

        case .capturing(let windowTitle):
            HStack(spacing: 4) {
                Circle()
                    .fill(.cyan)
                    .frame(width: 7, height: 7)
                    .modifier(PulsingModifier())
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.caption2)
                Text(windowTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140)
                Text("\(viewModel.screenShareFrameCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.cyan)
            .fixedSize(horizontal: false, vertical: true)
            .help("Capturing \"\(windowTitle)\" — \(viewModel.screenShareFrameCount) frames kept")

        case .denied:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("Capture issue")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .lineLimit(1)
            .fixedSize()
            .help("Screen Recording permission is off")
        }
    }
}
