import SwiftUI

/// "Shared Content" card in the live intelligence column: the most recent
/// screen observations as a compact timeline. Text only — frame imagery
/// lives in the toolbar popover.
struct LiveSharedContentSection: View {
    let observations: [ScreenFrameAnalysisService.FrameObservation]
    /// True while a share window is actively being captured; shows a subtle
    /// "watching" hint next to the header.
    let isCapturing: Bool

    /// Newest first, capped for the live column.
    private static let visibleLimit = 5

    @State private var isExpanded = true

    private var recent: [ScreenFrameAnalysisService.FrameObservation] {
        Array(observations.suffix(Self.visibleLimit).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.cyan.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("Shared Content")
                    .font(.headline)
                if isCapturing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                Text("\(observations.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recent, id: \.frameID) { observation in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(observation.formattedTimestamp)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.tertiary)
                            Text(observation.observation)
                                .font(.callout)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                                .help(observation.observation)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal)
    }
}
