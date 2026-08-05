import SwiftUI

/// Manual window picker: grid of capturable windows with live thumbnails,
/// Teams share candidates badged and sorted first. Selecting a card starts
/// capturing that window; auto-detect can be restored from here too.
struct ScreenShareWindowPickerSheet: View {
    @Bindable var viewModel: RecordingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [WindowCandidate] = []
    @State private var thumbnails: [CGWindowID: CGImage] = [:]
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a window to capture")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
            .padding()

            Divider()

            content

            Divider()

            HStack {
                Button("Use Auto-Detect") {
                    viewModel.selectShareWindow(nil)
                    dismiss()
                }
                .help("Return to automatic share-window detection")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 560, height: 440)
        .task { await refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && candidates.isEmpty {
            Spacer()
            ProgressView("Finding windows…")
            Spacer()
        } else if candidates.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No windows found",
                systemImage: "macwindow.badge.plus",
                description: Text("If Screen Recording permission was just granted, quit and reopen the app.")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
                .padding()
            }
        }
    }

    private func candidateCard(_ candidate: WindowCandidate) -> some View {
        Button {
            viewModel.selectShareWindow(candidate.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                    if let thumb = thumbnails[candidate.id] {
                        Image(decorative: thumb, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "macwindow")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 125)

                HStack(spacing: 4) {
                    Text(candidate.appName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if candidate.score >= 100 {
                        Text("Suggested")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.cyan.opacity(0.15), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                }
                Text(candidate.title.isEmpty ? "Untitled window" : candidate.title)
                    .font(.caption)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        isLoading = true
        let found = await viewModel.screenCapture.currentCandidates()
        candidates = found
        isLoading = false
        // Thumbnails load after the list so the grid appears immediately.
        for candidate in found where thumbnails[candidate.id] == nil {
            if let thumb = await viewModel.screenCapture.thumbnail(for: candidate.id) {
                thumbnails[candidate.id] = thumb
            }
        }
    }
}
