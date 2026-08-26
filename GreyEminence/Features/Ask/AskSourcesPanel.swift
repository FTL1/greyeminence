import SwiftUI
import SwiftData

/// Right-hand panel: the snippets the conversation is standing on.
///
/// It occupies the slot the transcript panel uses elsewhere in the app, and
/// plays the same role — the raw material behind what the centre pane is
/// asserting. Numbers here match the `[3]` citations in the answers.
struct AskSourcesPanel: View {
    @Bindable var viewModel: AskViewModel
    var onResultSelected: ((SearchResult) -> Void)?

    enum Scope: String, CaseIterable, Identifiable {
        case all
        case cited
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .cited: "Cited"
            }
        }
    }

    @State private var scope: Scope = .all
    @State private var kindFilter: EmbeddingRecord.SourceKind?

    private var conversation: AskConversation? { viewModel.currentConversation }

    /// Turn the panel is narrowed to, if that turn still exists.
    private var focusedTurn: AskTurn? {
        guard let id = viewModel.focusedTurnID else { return nil }
        return conversation?.turns.first { $0.id == id }
    }

    private var citedNumbers: Set<Int> {
        Set(conversation?.turns.flatMap(\.citedNumbers) ?? [])
    }

    private var visibleSources: [AskSource] {
        guard let conversation else { return [] }
        var sources: [AskSource]

        if let focusedTurn {
            // Rank order for the turn: what the model actually read, best first.
            sources = focusedTurn.promptedNumbers.compactMap { conversation.source(number: $0) }
        } else {
            sources = conversation.sources.sorted { $0.result.score > $1.result.score }
        }
        if scope == .cited {
            let cited = citedNumbers
            sources = sources.filter { cited.contains($0.number) }
        }
        if let kindFilter {
            sources = sources.filter { $0.result.sourceKind == kindFilter }
        }
        return sources
    }

    private var availableKinds: [EmbeddingRecord.SourceKind] {
        guard let conversation else { return [] }
        let kinds = Set(conversation.sources.map(\.result.sourceKind))
        return [.transcriptSegment, .screenObservation, .sessionNarrative].filter { kinds.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if visibleSources.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(.background)
        .onChange(of: viewModel.selectedConversationID) { _, _ in
            scope = .all
            kindFilter = nil
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                Text("\(visibleSources.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                kindMenu
            }

            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let focusedTurn {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text("Behind one answer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Show all") {
                        viewModel.focusedTurnID = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
                .help(focusedTurn.question)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var kindMenu: some View {
        Menu {
            Button {
                kindFilter = nil
            } label: {
                if kindFilter == nil { Label("All kinds", systemImage: "checkmark") } else { Text("All kinds") }
            }
            ForEach(availableKinds, id: \.self) { kind in
                Button {
                    kindFilter = kind
                } label: {
                    if kindFilter == kind {
                        Label(AskSourceStyle.label(kind), systemImage: "checkmark")
                    } else {
                        Text(AskSourceStyle.label(kind))
                    }
                }
            }
        } label: {
            Image(systemName: kindFilter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(availableKinds.isEmpty)
        .help("Filter by source kind")
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var emptyMessage: String {
        if conversation?.sources.isEmpty ?? true {
            return "Snippets found while answering will be listed here, numbered to match the citations."
        }
        if scope == .cited {
            return "No snippet in this view has been cited yet."
        }
        return "No snippets match this filter."
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleSources) { source in
                        sourceRow(source)
                            .id(source.number)
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.selectedSourceNumber) { _, number in
                guard let number else { return }
                // A citation can point at a snippet the current filter hides —
                // widen back to everything rather than scroll to nothing.
                if !visibleSources.contains(where: { $0.number == number }) {
                    scope = .all
                    kindFilter = nil
                }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(number, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: AskSource) -> some View {
        let result = source.result
        let isSelected = viewModel.selectedSourceNumber == source.number
        let isCited = citedNumbers.contains(source.number)

        Button {
            viewModel.selectedSourceNumber = source.number
            onResultSelected?(result.toSearchResult)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(source.number)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isCited ? Color.accentColor : .secondary)
                        .frame(minWidth: 20, minHeight: 16)
                        .background(
                            (isCited ? Color.accentColor : Color.secondary).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    Text(AskSourceStyle.label(result.sourceKind))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AskSourceStyle.color(result.sourceKind).opacity(0.18), in: Capsule())
                        .foregroundStyle(AskSourceStyle.color(result.sourceKind))
                    Spacer(minLength: 4)
                    if isCited {
                        Image(systemName: "quote.opening")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .help("Cited in an answer")
                    }
                    Text(AskSourceStyle.percentage(result.score))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 5) {
                    Text(result.meetingTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(result.meetingDate, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if result.sourceKind == .screenObservation {
                    HStack(alignment: .top, spacing: 8) {
                        AskScreenThumb(frameID: result.sourceID, meetingID: result.meetingID)
                        Text(result.text)
                            .font(.caption)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text(result.text)
                        .font(.caption)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open this moment in its meeting")
    }
}

/// Shared kind styling so the panel and any future surface agree on what a
/// TRANSCRIPT chip looks like.
enum AskSourceStyle {
    static func label(_ kind: EmbeddingRecord.SourceKind) -> String {
        switch kind {
        case .transcriptSegment: "TRANSCRIPT"
        case .actionItem: "TASK"
        case .followUpQuestion: "QUESTION"
        case .meetingSummary: "SUMMARY"
        case .screenObservation: "SCREEN"
        case .sessionNarrative: "RECAP"
        }
    }

    static func color(_ kind: EmbeddingRecord.SourceKind) -> Color {
        switch kind {
        case .transcriptSegment: .indigo
        case .actionItem: .orange
        case .followUpQuestion: .teal
        case .meetingSummary: .purple
        case .screenObservation: .cyan
        case .sessionNarrative: .mint
        }
    }

    static func percentage(_ score: Float) -> String {
        "\(Int((max(0, min(1, score)) * 100).rounded()))%"
    }
}

/// Thumbnail for a screen-observation hit. The embedding record doesn't carry
/// `imagePath`, so the frame row is resolved at render time; a missing frame
/// or file falls back to a placeholder rather than an empty box.
struct AskScreenThumb: View {
    let frameID: UUID
    let meetingID: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var image: CGImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 35)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: missing ? "photo.badge.exclamationmark" : "photo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 35)
        .task(id: frameID) {
            let id = frameID
            var descriptor = FetchDescriptor<ScreenShareFrame>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let frame = try? modelContext.fetch(descriptor).first else {
                missing = true
                return
            }
            let url = StorageManager.shared.frameURL(for: meetingID, relativePath: frame.imagePath)
            image = await FrameThumbnailCache.shared.thumbnail(at: url, size: .strip)
            missing = image == nil
        }
    }
}
