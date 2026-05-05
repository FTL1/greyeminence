import SwiftUI

/// Horizontal segmented bar that visualizes a rubric's section weights as
/// proportional pieces of a single 100% slider. Dragging the divider
/// between two adjacent segments shifts weight from one to the other,
/// keeping the total constant. Each segment shows the section title (when
/// it's wide enough) and its current percentage.
///
/// Why a single bar rather than per-section sliders: the old sliders let
/// you set each section to anything in 1...100 with no enforcement that
/// they summed to 100. Composite scores were therefore weighted by an
/// arbitrary denominator that the user couldn't see, and re-balancing
/// required updating every section by hand. With one bar the invariant
/// "weights sum to 100" is enforced by construction.
///
/// Implementation note: the draggable handles are overlaid at absolute
/// x-offsets rather than placed inside the segment HStack. This keeps
/// drag translation stable in the bar's named coordinate space — if the
/// handles lived inside the resizing HStack, their local coordinates
/// would shift mid-drag and the gesture would jerk.
struct RubricWeightBar: View {
    @Bindable var rubric: Rubric

    /// Minimum weight for any single section. Keeps each segment wide
    /// enough that the divider hit area stays reachable.
    private static let minWeight: Double = 5
    private static let barHeight: CGFloat = 28
    private static let handleHitWidth: CGFloat = 16
    private static let coordSpaceName = "rubricWeightBar"

    /// Baseline weights captured at the start of a divider drag. Cleared
    /// on `onEnded` so the next drag re-captures from the new state.
    @State private var dragBaseline: DragBaseline?

    private struct DragBaseline {
        let leftID: UUID
        let rightID: UUID
        let leftWeight: Double
        let rightWeight: Double
        /// X-offset of the divider at drag start, in the bar's coord space.
        let startOffset: CGFloat
    }

    private var sortedSections: [RubricSection] {
        rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var totalWeight: Double {
        sortedSections.reduce(0) { $0 + max($1.weight, 0) }
    }

    var body: some View {
        let sections = sortedSections
        Group {
            if sections.isEmpty {
                EmptyView()
            } else if sections.count == 1 {
                singleSegmentBar(sections[0])
            } else {
                multiSegmentBar(sections)
            }
        }
    }

    // MARK: - Single section

    private func singleSegmentBar(_ section: RubricSection) -> some View {
        ZStack {
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
    }

    // MARK: - Multi-section bar

    private func multiSegmentBar(_ sections: [RubricSection]) -> some View {
        GeometryReader { geo in
            let total = max(totalWeight, 1)
            let barWidth = geo.size.width
            // Cumulative weight before each section, used to compute each
            // segment's leading edge in pixels.
            let cumulativeOffsets = cumulativeWeightOffsets(for: sections)

            ZStack(alignment: .leading) {
                // Background segments — colored bands, no gestures.
                HStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                        let fraction = max(section.weight, 0) / total
                        Rectangle()
                            .fill(color(for: idx).gradient)
                            .frame(width: max(barWidth * fraction, 0))
                            .overlay(segmentLabel(section: section))
                    }
                }
                .frame(height: Self.barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Disable any implicit animation on segment width — we
                // want widths to track the drag in real time, not animate
                // toward each updated value.
                .animation(nil, value: totalWeight)

                // Draggable handles overlaid at absolute positions. Each
                // handle's gesture is anchored to the bar's named coord
                // space so translation stays stable as the segments
                // around it resize.
                ForEach(Array(sections.dropLast().enumerated()), id: \.element.id) { idx, leftSection in
                    let rightSection = sections[idx + 1]
                    let dividerWeightOffset = cumulativeOffsets[idx + 1]
                    let dividerX = barWidth * CGFloat(dividerWeightOffset / total)
                    handleView(
                        leftSection: leftSection,
                        rightSection: rightSection,
                        dividerX: dividerX,
                        barWidth: barWidth,
                        total: total
                    )
                }
            }
            .coordinateSpace(name: Self.coordSpaceName)
        }
        .frame(height: Self.barHeight)
    }

    private func cumulativeWeightOffsets(for sections: [RubricSection]) -> [Double] {
        var offsets: [Double] = [0]
        var running: Double = 0
        for section in sections {
            running += max(section.weight, 0)
            offsets.append(running)
        }
        return offsets
    }

    private func segmentLabel(section: RubricSection) -> some View {
        let percent = Int((section.weight / max(totalWeight, 1) * 100).rounded())
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
        // The handle is a thin vertical bar centered on the divider X
        // position, with a wider invisible hit area for easy grabbing.
        ZStack {
            // Visible chevron centered on the divider
            Rectangle()
                .fill(.white.opacity(0.6))
                .frame(width: 2, height: Self.barHeight - 8)
            // Invisible hit area
            Color.clear
                .frame(width: Self.handleHitWidth, height: Self.barHeight)
                .contentShape(Rectangle())
        }
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
        let clampedLeft = min(max(proposedLeft, Self.minWeight), combined - Self.minWeight)
        let clampedRight = combined - clampedLeft

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

extension RubricWeightBar {
    /// Normalize the rubric's section weights to sum to exactly 100. Called
    /// on first appearance of the editor so old rubrics with arbitrary
    /// weights (e.g., 50 + 30 + 20 + 25 = 125) get reshaped to a clean
    /// 100-total view without a visible jolt mid-edit.
    @MainActor
    static func normalizeToHundred(_ rubric: Rubric) {
        let sections = rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
        guard !sections.isEmpty else { return }
        let total = sections.reduce(0.0) { $0 + max($1.weight, 0) }
        guard total > 0 else {
            let even = 100.0 / Double(sections.count)
            for section in sections { section.weight = even }
            return
        }
        if abs(total - 100) < 0.01 { return }
        let scale = 100.0 / total
        for section in sections {
            section.weight = max(section.weight, 0) * scale
        }
    }
}
