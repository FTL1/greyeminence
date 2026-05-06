import SwiftUI

/// Horizontal segmented bar that visualizes a rubric's section weights as
/// proportional pieces of a single 100% slider. Dragging the divider
/// between two adjacent segments shifts weight from one to the other,
/// keeping the total constant.
///
/// Implementation note: draggable handles are overlaid at absolute
/// x-offsets rather than placed inside the segment HStack. If the
/// handles lived inside the resizing HStack, their local coordinates
/// would shift mid-drag and the gesture would jerk.
struct RubricWeightBar: View {
    @Bindable var rubric: Rubric

    /// Minimum weight for any single section — keeps each segment wide
    /// enough that the divider hit area stays reachable. Also the snap
    /// step (every drag rounds to the nearest multiple).
    private static let minWeight: Double = 5
    private static let snapStep: Double = 5
    private static let barHeight: CGFloat = 28
    private static let handleHitWidth: CGFloat = 16
    private static let coordSpaceName = "rubricWeightBar"

    @State private var dragBaseline: DragBaseline?

    private struct DragBaseline {
        let leftID: UUID
        let rightID: UUID
        let leftWeight: Double
        let rightWeight: Double
        let startOffset: CGFloat
    }

    /// Pre-computed layout values for one render of the bar. Each `body`
    /// pass walks the sections array exactly once to build this; segment
    /// and handle helpers read it without recomputing reductions.
    private struct Layout {
        let sections: [RubricSection]
        let total: Double
        /// `cumulative[i]` = sum of weights of sections [0..<i]. Length is
        /// `sections.count + 1`. `cumulative.last` always equals `total`.
        let cumulative: [Double]

        var dividerCount: Int { max(sections.count - 1, 0) }
    }

    private func makeLayout() -> Layout {
        let sections = rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
        var cumulative: [Double] = [0]
        var running: Double = 0
        for section in sections {
            running += max(section.weight, 0)
            cumulative.append(running)
        }
        return Layout(sections: sections, total: max(running, 1), cumulative: cumulative)
    }

    var body: some View {
        let layout = makeLayout()
        if layout.sections.isEmpty {
            EmptyView()
        } else if layout.sections.count == 1 {
            singleSegmentBar(layout.sections[0])
        } else {
            multiSegmentBar(layout)
        }
    }

    private func singleSegmentBar(_ section: RubricSection) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color(for: 0).gradient)
            .overlay(
                Text("\(section.title) — 100%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            )
            .frame(height: Self.barHeight)
    }

    private func multiSegmentBar(_ layout: Layout) -> some View {
        GeometryReader { geo in
            let barWidth = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(layout.sections.enumerated()), id: \.element.id) { idx, section in
                        let fraction = max(section.weight, 0) / layout.total
                        Rectangle()
                            .fill(color(for: idx).gradient)
                            .frame(width: max(barWidth * fraction, 0))
                            .overlay(segmentLabel(section: section, total: layout.total))
                    }
                }
                .frame(height: Self.barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Real-time drag tracking — without this, segment widths
                // animate toward each frame's value instead of following
                // the cursor 1:1.
                .animation(nil, value: layout.total)

                ForEach(Array(layout.sections.dropLast().enumerated()), id: \.element.id) { idx, leftSection in
                    let rightSection = layout.sections[idx + 1]
                    let dividerX = barWidth * CGFloat(layout.cumulative[idx + 1] / layout.total)
                    handleView(
                        leftSection: leftSection,
                        rightSection: rightSection,
                        dividerX: dividerX,
                        barWidth: barWidth,
                        total: layout.total
                    )
                }
            }
            .coordinateSpace(name: Self.coordSpaceName)
        }
        .frame(height: Self.barHeight)
    }

    private func segmentLabel(section: RubricSection, total: Double) -> some View {
        let percent = Int((section.weight / total * 100).rounded())
        return HStack(spacing: 4) {
            Text(section.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(percent)%")
                .fontDesign(.monospaced)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .help("\(section.title): \(percent)%")
    }

    private func handleView(
        leftSection: RubricSection,
        rightSection: RubricSection,
        dividerX: CGFloat,
        barWidth: CGFloat,
        total: Double
    ) -> some View {
        // Wider invisible hit area centered on the divider, with a thin
        // visible bar drawn on top via overlay.
        Color.clear
            .frame(width: Self.handleHitWidth, height: Self.barHeight)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(.white.opacity(0.6))
                    .frame(width: 2, height: Self.barHeight - 8)
            )
            .position(x: dividerX, y: Self.barHeight / 2)
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordSpaceName))
                .onChanged { value in
                    handleDrag(
                        location: value.location,
                        leftSection: leftSection,
                        rightSection: rightSection,
                        dividerX: dividerX,
                        barWidth: barWidth,
                        total: total
                    )
                }
                .onEnded { _ in
                    dragBaseline = nil
                }
        )
    }

    /// Called on every drag-change event. Captures the baseline once at
    /// gesture start, then computes the new weights from the cursor's
    /// absolute x-position in the bar's coord space — not from the
    /// view-relative translation that would drift as the handle moves.
    private func handleDrag(
        location: CGPoint,
        leftSection: RubricSection,
        rightSection: RubricSection,
        dividerX: CGFloat,
        barWidth: CGFloat,
        total: Double
    ) {
        guard barWidth > 0, total > 0 else { return }

        // Capture baseline on first event of this drag.
        if dragBaseline == nil
            || dragBaseline?.leftID != leftSection.id
            || dragBaseline?.rightID != rightSection.id {
            dragBaseline = DragBaseline(
                leftID: leftSection.id,
                rightID: rightSection.id,
                leftWeight: leftSection.weight,
                rightWeight: rightSection.weight,
                startOffset: dividerX
            )
        }
        guard let baseline = dragBaseline else { return }

        // Cursor position translates directly to a divider position in
        // weight space. Cumulative weight before the left section stays
        // fixed at baseline; any pixels left of that are off-limits.
        let combined = baseline.leftWeight + baseline.rightWeight
        // Pixels before the left section's leading edge (locked).
        let leftAnchorX = baseline.startOffset - CGFloat(baseline.leftWeight / total) * barWidth
        // Cursor's offset from the left section's leading edge, in pixels.
        let cursorOffsetFromAnchor = location.x - leftAnchorX
        // Convert to weight units. Total weight maps to barWidth pixels.
        let proposedLeft = Double(cursorOffsetFromAnchor / barWidth) * total
        // Snap to the nearest 5% increment. Snapping the LEFT side and
        // computing right = combined - left preserves the sum exactly,
        // so the rest of the bar stays at 100% even if `combined` isn't
        // itself a multiple of 5.
        let snappedLeft = (proposedLeft / Self.snapStep).rounded() * Self.snapStep
        let clampedLeft = min(max(snappedLeft, Self.minWeight), combined - Self.minWeight)
        let clampedRight = combined - clampedLeft

        // Skip the write if it didn't actually change — avoids redundant
        // SwiftData mutations on every pixel of cursor movement between
        // snap points.
        guard clampedLeft != leftSection.weight else { return }
        leftSection.weight = clampedLeft
        rightSection.weight = clampedRight
    }

    // MARK: - Colors

    /// Distinct hues per section index; cycles past the palette length.
    /// Chosen for readability with white text labels on top.
    private static let palette: [Color] = [
        .indigo, .teal, .orange, .purple, .blue, .pink, .green, .red,
    ]

    private func color(for index: Int) -> Color {
        Self.palette[index % Self.palette.count]
    }
}

