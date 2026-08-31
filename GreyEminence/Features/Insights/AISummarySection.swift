import SwiftUI

struct AISummarySection: View {
    let summary: String
    var onOpenWorkspace: (() -> Void)?
    var reanalyzeControl: InsightReanalyzeControl? = nil
    var onReplaceSummary: ((String) -> Void)? = nil
    var onResearch: ((String) -> Void)? = nil
    @Environment(\.meetingFindQuery) private var findQuery
    @State private var isExpanded = true
    @State private var selectedSection: Int?
    @State private var editingSection: Int?
    @State private var draft = ""

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
                            .onTapGesture {
                                if let onOpenWorkspace {
                                    onOpenWorkspace()
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                                }
                            }
                            .help("Open Summaries — browse write-ups across meetings")
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
                    CopyButton(
                        label: "Copy",
                        help: "Copy the full summary",
                        html: { htmlText(from: summary) }
                    ) { plainText(from: summary) }
                }
                if let reanalyzeControl {
                    reanalyzeControl
                }
            }

            if isExpanded {
                if let sections, !sections.isEmpty {
                    StructuredSummaryView(
                        sections: sections,
                        rawSummary: summary,
                        selectedSection: $selectedSection,
                        onModify: onReplaceSummary == nil ? nil : { index, section in
                            var next = sections
                            next[index] = section
                            if let encoded = SummarySection.encode(next) {
                                onReplaceSummary?(encoded)
                            }
                        },
                        onDelete: onReplaceSummary == nil ? nil : { index in
                            var next = sections
                            next.remove(at: index)
                            if let encoded = SummarySection.encode(next) {
                                onReplaceSummary?(encoded)
                            }
                        },
                        onMove: onReplaceSummary == nil ? nil : { source, dest in
                            var next = sections
                            next.move(fromOffsets: source, toOffset: dest)
                            if let encoded = SummarySection.encode(next) {
                                onReplaceSummary?(encoded)
                            }
                        },
                        onResearch: onResearch
                    )
                } else if !summary.isEmpty {
                    InsightItemChrome(
                        isSelected: selectedSection == 0,
                        onSelect: { selectedSection = 0 },
                        copyText: summary,
                        onModify: onReplaceSummary == nil ? nil : {
                            draft = summary
                            editingSection = 0
                        },
                        onDelete: nil,
                        onResearch: onResearch == nil ? nil : { onResearch?(summary) }
                    ) {
                        HighlightedBody(text: summary, query: findQuery, font: .callout, color: .secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: Binding(
            get: { editingSection != nil && sections == nil },
            set: { if !$0 { editingSection = nil } }
        )) {
            InsightEditSheet(
                title: "Modify summary",
                text: $draft,
                onCancel: { editingSection = nil },
                onSave: {
                    onReplaceSummary?(draft)
                    editingSection = nil
                }
            )
        }
    }

    private func plainText(from raw: String) -> String {
        guard let sections = SummarySection.parse(raw) else { return raw }
        return RichClipboard.summaryPlainText(sections)
    }

    /// Rich flavour for the same content. A legacy flat-string summary has no
    /// structure to mark up, so it is escaped and sent as one paragraph
    /// rather than being dressed in headings it does not have.
    private func htmlText(from raw: String) -> String {
        guard let sections = SummarySection.parse(raw) else {
            return "<p>\(RichClipboard.escape(raw))</p>"
        }
        return RichClipboard.summaryHTML(sections)
    }
}

// MARK: - Structured layout

private struct StructuredSummaryView: View {
    let sections: [SummarySection]
    let rawSummary: String
    @Binding var selectedSection: Int?
    var onModify: ((Int, SummarySection) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onMove: ((IndexSet, Int) -> Void)?
    var onResearch: ((String) -> Void)?
    @State private var editingIndex: Int?
    @State private var draft = ""

    var body: some View {
        List {
            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                InsightItemChrome(
                    isSelected: selectedSection == idx,
                    onSelect: { selectedSection = idx },
                    copyText: sectionPlainText(section),
                    onModify: onModify == nil ? nil : {
                        draft = sectionPlainText(section)
                        editingIndex = idx
                    },
                    onDelete: onDelete == nil ? nil : { onDelete?(idx) },
                    onResearch: onResearch == nil ? nil : { onResearch?(section.title) }
                ) {
                    SectionCard(section: section, number: idx + 1)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
        .frame(height: CGFloat(max(sections.count, 1) * 120))
        .padding(.top, 4)
        .help("Click to select. Right-click to modify, research, or delete. Drag to reorder.")
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )) {
            InsightEditSheet(
                title: "Modify summary section",
                text: $draft,
                onCancel: { editingIndex = nil },
                onSave: {
                    if let editingIndex {
                        var section = sections[editingIndex]
                        let parts = draft.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                        section.title = parts.first.map(String.init) ?? section.title
                        if parts.count > 1 {
                            let rest = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                            section.intro = rest.isEmpty ? nil : rest
                        }
                        onModify?(editingIndex, section)
                    }
                    editingIndex = nil
                }
            )
        }
    }

    private func sectionPlainText(_ section: SummarySection) -> String {
        var lines = [section.title]
        if let intro = section.intro { lines.append(intro) }
        for point in section.points {
            lines.append("  • \(point.label): \(point.detail)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Section card

private struct SectionCard: View {
    let section: SummarySection
    let number: Int
    @Environment(\.meetingFindQuery) private var findQuery
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

                HighlightedBody(text: section.title, query: findQuery, font: .subheadline.weight(.semibold))

                Spacer()

                if isHovered {
                    CopyButton(label: nil, html: { RichClipboard.summaryHTML([section]) }) {
                        sectionPlainText()
                    }
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
                            HighlightedBody(text: intro, query: findQuery, font: .callout, color: .secondary, italic: true)
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
    @Environment(\.meetingFindQuery) private var findQuery

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            HighlightedBody(
                text: "\(point.label): \(point.detail)",
                query: findQuery,
                font: .callout
            )
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

