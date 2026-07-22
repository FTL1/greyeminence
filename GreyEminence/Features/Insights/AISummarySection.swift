import SwiftUI

struct AISummarySection: View {
    let summary: String
    @State private var isExpanded = true

    private var sections: [SummarySection]? {
        SummarySection.parse(summary)
    }

    var body: some View {
        // Plain Button header with the Copy button as a SIBLING — not a
        // DisclosureGroup, whose label swallows taps to toggle, so a Copy
        // button nested in it never fired (it just collapsed the section).
        // Mirrors FollowUpQuestionsSection / ActionItemsSection.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text("Summary")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !summary.isEmpty {
                    CopyButton(label: "Copy", help: "Copy the full summary") { plainText(from: summary) }
                }
            }

            if isExpanded {
                if let sections, !sections.isEmpty {
                    StructuredSummaryView(sections: sections, rawSummary: summary)
                } else if !summary.isEmpty {
                    // Legacy flat-string fallback
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal)
    }

    private func plainText(from raw: String) -> String {
        guard let sections = SummarySection.parse(raw) else { return raw }
        return sections.enumerated().map { idx, section in
            var lines = ["\(idx + 1). \(section.title)"]
            if let intro = section.intro { lines.append(intro) }
            for point in section.points {
                lines.append("  • \(point.label): \(point.detail)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

// MARK: - Structured layout

private struct StructuredSummaryView: View {
    let sections: [SummarySection]
    let rawSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                SectionCard(section: section, number: idx + 1)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Section card

private struct SectionCard: View {
    let section: SummarySection
    let number: Int
    @State private var isExpanded = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                // Number badge
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.blue.opacity(0.75), in: Circle())

                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if isHovered {
                    CopyButton(label: nil) { sectionPlainText() }
                        .transition(.opacity)
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
            .onHover { isHovered = $0 }

            // SwiftUI doesn't clip transitioning views, so the collapsing
            // content would slide up over the header (and neighboring cards)
            // while it fades. This wrapper is a stable parent whose bounds
            // shrink with the collapse — clipping to it masks the roll-up at
            // the header/content boundary.
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        if let intro = section.intro {
                            Text(intro)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.horizontal, 10)
                                .padding(.bottom, 6)
                        }

                        ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                            PointRow(point: point)
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func sectionPlainText() -> String {
        var lines = [section.title]
        if let intro = section.intro { lines.append(intro) }
        for point in section.points {
            lines.append("  • \(point.label): \(point.detail)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Point row

private struct PointRow: View {
    let point: SummaryPoint

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            // Bold label + regular detail in one Text via concatenation
            (Text(point.label + ": ").fontWeight(.semibold) + Text(point.detail))
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

