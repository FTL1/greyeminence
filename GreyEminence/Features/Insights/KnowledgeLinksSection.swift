import SwiftUI

struct KnowledgeLinksSection: View {
    let topics: [String]
    var meeting: Meeting?
    var onOpenSegment: ((Meeting, UUID) -> Void)?
    var reanalyzeControl: InsightReanalyzeControl? = nil
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onDelete: ((Int) -> Void)? = nil
    var onModify: ((Int, String) -> Void)? = nil
    var onResearch: ((String) -> Void)? = nil
    @State private var isExpanded = true
    @State private var showCloud = false
    @State private var cloudTopic: String?
    @State private var selectedIndex: Int?
    @State private var editingIndex: Int?
    @State private var draft = ""
    @Environment(\.topicMapViewModel) private var topicMapViewModel

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if onMove != nil || onDelete != nil {
                List {
                    ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                        InsightItemChrome(
                            isSelected: selectedIndex == index,
                            onSelect: { selectedIndex = index },
                            copyText: topic,
                            onModify: onModify == nil ? nil : {
                                draft = topic
                                editingIndex = index
                            },
                            onDelete: onDelete == nil ? nil : { onDelete?(index) },
                            onResearch: onResearch == nil ? nil : { onResearch?(topic) }
                        ) {
                            TopicBadge(topic: topic) {
                                openCloud(topic: topic)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, dest in
                        onMove?(source, dest)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(max(topics.count, 1) * 40))
                .padding(.top, 4)
                .help("Click to select. Right-click to modify, research, or delete. Drag to reorder.")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        TopicBadge(topic: topic) {
                            openCloud(topic: topic)
                        }
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            HStack(spacing: 8) {
                Button {
                    openCloud(topic: nil)
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open this meeting's topic cloud")
                .disabled(meeting == nil)

                Text("Topics")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let reanalyzeControl {
                    reanalyzeControl
                }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )) {
            InsightEditSheet(
                title: "Modify topic",
                text: $draft,
                onCancel: { editingIndex = nil },
                onSave: {
                    if let editingIndex {
                        onModify?(editingIndex, draft)
                    }
                    self.editingIndex = nil
                }
            )
        }
        .sheet(isPresented: $showCloud) {
            if let meeting {
                MeetingTopicCloudSheet(
                    meeting: meeting,
                    initialTopic: cloudTopic,
                    onOpenSegment: onOpenSegment,
                    onOpenInTopicMap: { topic in
                        topicMapViewModel?.pendingFocusTopic = topic
                    }
                )
            }
        }
    }

    private func openCloud(topic: String?) {
        guard meeting != nil else {
            if let topic {
                topicMapViewModel?.pendingFocusTopic = topic
            }
            return
        }
        cloudTopic = topic
        showCloud = true
    }
}

// MARK: - Topic Navigation Environment

private struct TopicMapViewModelKey: EnvironmentKey {
    static let defaultValue: TopicMapViewModel? = nil
}

extension EnvironmentValues {
    var topicMapViewModel: TopicMapViewModel? {
        get { self[TopicMapViewModelKey.self] }
        set { self[TopicMapViewModelKey.self] = newValue }
    }
}

// MARK: - Topic Badge

struct TopicBadge: View {
    let topic: String
    var onSelect: (() -> Void)?
    @Environment(\.topicMapViewModel) private var topicMapViewModel
    @Environment(\.meetingFindQuery) private var findQuery

    var body: some View {
        Button {
            if let onSelect {
                onSelect()
            } else {
                topicMapViewModel?.pendingFocusTopic = topic
            }
        } label: {
            HighlightedBody(text: topic, query: findQuery, font: .caption, color: .purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || topic.range(of: findQuery, options: [.caseInsensitive, .diacriticInsensitive]) == nil
                        ? Color.purple.opacity(0.1)
                        : Color.yellow.opacity(0.28),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(onSelect == nil ? "View in Topic Map" : "Show conversation about \(topic)")
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    /// Cross-axis alignment within a row. Rows that mix control heights — a
    /// caption beside bordered buttons — need `.center`, or the short item
    /// rides high against its neighbours. Defaults to `.top` so the existing
    /// uniform-height badge callers keep their exact behaviour; the callers
    /// that need centring ask for it.
    var rowAlignment: VerticalAlignment = .top

    struct Cache {
        var sizes: [CGSize]
        /// Width the cached rows were computed for; `nil` means not yet valid.
        var rowsWidth: CGFloat?
        var rows: [Row] = []
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    // Subview measurement is Core Text layout for the text and controls in
    // these rows, and both entry points need the same numbers. Without a cache
    // a single pass measures everything three times: once in sizeThatFits,
    // again in placeSubviews, and again while positioning.
    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, rowsWidth: nil)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.rowsWidth = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let rows = rows(proposal: proposal, cache: &cache)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        // Fall back to the widest row when the proposal is unconstrained —
        // returning .infinity here would poison the parent's layout.
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let rows = rows(proposal: proposal, cache: &cache)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                let dy: CGFloat = switch rowAlignment {
                case .top: 0
                case .bottom: row.height - size.height
                default: (row.height - size.height) / 2
                }
                subviews[index].place(
                    at: CGPoint(x: x, y: y + dy),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(proposal: ProposedViewSize, cache: inout Cache) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        if cache.rowsWidth == maxWidth { return cache.rows }

        var rows: [Row] = []
        var current = Row()

        for (index, size) in cache.sizes.enumerated() {
            let added = current.indices.isEmpty ? size.width : size.width + spacing
            if !current.indices.isEmpty, current.width + added > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width += added
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }

        cache.rowsWidth = maxWidth
        cache.rows = rows
        return rows
    }
}
