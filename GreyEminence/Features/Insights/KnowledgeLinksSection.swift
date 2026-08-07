import SwiftUI

struct KnowledgeLinksSection: View {
    let topics: [String]
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            FlowLayout(spacing: 6) {
                ForEach(topics, id: \.self) { topic in
                    TopicBadge(topic: topic)
                }
            }
            .padding(.top, 4)
        } label: {
            Label {
                Text("Topics")
            } icon: {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
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
    @Environment(\.topicMapViewModel) private var topicMapViewModel

    var body: some View {
        Button {
            topicMapViewModel?.pendingFocusTopic = topic
        } label: {
            Text(topic)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.purple.opacity(0.1), in: Capsule())
                .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
        .help("View in Topic Map")
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
