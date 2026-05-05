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
struct RubricWeightBar: View {
    @Bindable var rubric: Rubric

    /// Minimum weight for any single section. Keeps the divider reachable
    /// — a 0-width segment would have no draggable surface.
    private static let minWeight: Double = 5
    private static let barHeight: CGFloat = 28
    private static let dividerWidth: CGFloat = 8

    private var sortedSections: [RubricSection] {
        rubric.sections.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var totalWeight: Double {
        sortedSections.reduce(0) { $0 + max($1.weight, 0) }
    }

    var body: some View {
        let sections = sortedSections
        if sections.isEmpty {
            EmptyView()
        } else if sections.count == 1 {
            // Single section gets the whole bar — no handles to drag.
            singleSegmentBar(sections[0])
        } else {
            multiSegmentBar(sections)
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

    // MARK: - Multi-section bar with draggable dividers

    private func multiSegmentBar(_ sections: [RubricSection]) -> some View {
        GeometryReader { geo in
            let total = max(totalWeight, 1)
            // Compute each segment's pixel width based on its proportion of
            // the total. Subtract divider widths from the available area so
            // segments and dividers tile exactly to the bar's width.
            let dividerCount = sections.count - 1
            let availableWidth = max(geo.size.width - CGFloat(dividerCount) * Self.dividerWidth, 0)

            HStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                    let fraction = max(section.weight, 0) / total
                    let width = availableWidth * fraction
                    segmentView(section: section, index: idx, width: width)
                    if idx < sections.count - 1 {
                        dividerHandle(
                            left: section,
                            right: sections[idx + 1],
                            barWidth: geo.size.width,
                            total: total
                        )
                    }
                }
            }
            .frame(height: Self.barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: Self.barHeight)
    }

    private func segmentView(section: RubricSection, index: Int, width: CGFloat) -> some View {
        let percent = Int((section.weight / max(totalWeight, 1) * 100).rounded())
        return Rectangle()
            .fill(color(for: index).gradient)
            .frame(width: max(width, 0))
            .overlay(
                HStack(spacing: 4) {
                    Text(section.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(percent)%")
                        .fontDesign(.monospaced)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            )
            .help("\(section.title): \(percent)%")
    }

    private func dividerHandle(
        left: RubricSection,
        right: RubricSection,
        barWidth: CGFloat,
        total: Double
    ) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.001)) // hit area; visible chevron drawn on top
            .frame(width: Self.dividerWidth)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .rotationEffect(.degrees(90))
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convert the drag's pixel translation to a weight
                        // delta. `barWidth` corresponds to `total` weight.
                        let pixelsPerWeight = barWidth / CGFloat(total)
                        guard pixelsPerWeight > 0 else { return }
                        let deltaWeight = Double(value.translation.width / pixelsPerWeight)
                        applyDelta(deltaWeight, fromLeftBaseline: leftBaseline(for: left), toRightBaseline: rightBaseline(for: right), left: left, right: right)
                    }
                    .onEnded { _ in
                        // Reset the baseline so the next drag starts from
                        // the post-drag weight.
                        baselineLeft = nil
                        baselineRight = nil
                    }
            )
    }

    // Track baseline weights at drag start so we apply the cumulative
    // translation rather than a per-frame delta — keeps the segment exactly
    // under the cursor instead of drifting with rounding error.
    @State private var baselineLeft: (id: UUID, weight: Double)?
    @State private var baselineRight: (id: UUID, weight: Double)?

    private func leftBaseline(for section: RubricSection) -> Double {
        if let baseline = baselineLeft, baseline.id == section.id { return baseline.weight }
        baselineLeft = (section.id, section.weight)
        return section.weight
    }

    private func rightBaseline(for section: RubricSection) -> Double {
        if let baseline = baselineRight, baseline.id == section.id { return baseline.weight }
        baselineRight = (section.id, section.weight)
        return section.weight
    }

    private func applyDelta(
        _ delta: Double,
        fromLeftBaseline leftBaseline: Double,
        toRightBaseline rightBaseline: Double,
        left: RubricSection,
        right: RubricSection
    ) {
        // Clamp so neither side falls below the minimum.
        let combined = leftBaseline + rightBaseline
        let proposedLeft = leftBaseline + delta
        let clampedLeft = min(max(proposedLeft, Self.minWeight), combined - Self.minWeight)
        let clampedRight = combined - clampedLeft
        left.weight = clampedLeft
        right.weight = clampedRight
    }

    // MARK: - Colors

    /// Distinct hues per section index; cycles past the palette length.
    /// Chosen for readability on white text labels.
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
            // Pathological all-zeros: distribute evenly.
            let even = 100.0 / Double(sections.count)
            for section in sections { section.weight = even }
            return
        }
        // Skip if already within tolerance of 100 — avoids floating-point
        // drift on every open.
        if abs(total - 100) < 0.01 { return }
        let scale = 100.0 / total
        for section in sections {
            section.weight = max(section.weight, 0) * scale
        }
    }
}
