import SwiftUI

/// Popover hanging off the toolbar capture chip: latest-frame preview,
/// capture stats, pause/resume, and the window-picker entry point.
struct ScreenCapturePopover: View {
    @Bindable var viewModel: RecordingViewModel
    @Binding var showWindowPicker: Bool

    @State private var previewImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            preview
            stats
            Divider()
            controls
        }
        .padding(12)
        .frame(width: 304)
        .task(id: viewModel.screenShareLatestFramePath) {
            await loadPreview()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        switch viewModel.screenCaptureState {
        case .off:
            EmptyView()
        case .watching:
            Label(
                viewModel.screenCaptureUserPaused ? "Capture paused" : "Watching for share windows",
                systemImage: "rectangle.dashed.badge.record"
            )
            .font(.headline)
        case .capturing(let windowTitle):
            VStack(alignment: .leading, spacing: 2) {
                Label("Capturing share", systemImage: "rectangle.inset.filled.and.person.filled")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Text(windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Screen Recording permission is off", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Shared-screen capture is disabled for this recording. The rest of the recording is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let previewImage {
            VStack(alignment: .leading, spacing: 3) {
                Image(decorative: previewImage, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                if let at = viewModel.screenShareLatestFrameAt {
                    Text("captured \(at, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if case .watching = viewModel.screenCaptureState {
            Text("\(ShareAppProfiles.genericPopOutHint) Capture starts automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stats: some View {
        if viewModel.screenShareFrameCount > 0 {
            Text("\(viewModel.screenShareFrameCount) frames · every \(Int(ScreenShareSettings.intervalSeconds))s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if viewModel.screenCaptureState != .denied {
                Button {
                    viewModel.toggleScreenCapturePause()
                } label: {
                    Label(
                        viewModel.screenCaptureUserPaused ? "Resume" : "Pause capture",
                        systemImage: viewModel.screenCaptureUserPaused ? "play.fill" : "pause.fill"
                    )
                }
                .controlSize(.small)

                Button("Choose Window…") {
                    showWindowPicker = true
                }
                .controlSize(.small)
            }
            Spacer()
        }
    }

    private func loadPreview() async {
        guard let path = viewModel.screenShareLatestFramePath,
              let meetingID = viewModel.currentMeeting?.id else {
            previewImage = nil
            return
        }
        let url = StorageManager.shared.frameURL(for: meetingID, relativePath: path)
        previewImage = await FrameThumbnailCache.shared.thumbnail(at: url, size: .preview)
    }
}
