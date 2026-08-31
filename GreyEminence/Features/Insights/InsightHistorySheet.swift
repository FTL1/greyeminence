import SwiftUI
import SwiftData

struct InsightHistorySheet: View {
    let meeting: Meeting
    var scope: InsightScope
    var onRestore: (MeetingInsight) -> Void
    @Environment(\.dismiss) private var dismiss

    private var rows: [MeetingInsight] {
        InsightRevision.history(for: meeting)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(scope.label) log")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            if rows.isEmpty {
                ContentUnavailableView("No prior results", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows, id: \.id) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(insight.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(badge(insight))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(preview(insight))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                        Button("Restore this") {
                            onRestore(insight)
                            dismiss()
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func badge(_ insight: MeetingInsight) -> String {
        let scopeLabel = InsightScope(rawValue: insight.scopeRaw ?? "")?.label ?? "Full"
        let depthLabel = InsightDepth(rawValue: insight.depthRaw ?? "")?.label ?? "Original"
        return "\(scopeLabel) · \(depthLabel)"
    }

    private func preview(_ insight: MeetingInsight) -> String {
        switch scope {
        case .followUps:
            return insight.followUpQuestions.prefix(3).joined(separator: "\n")
        case .topics:
            return insight.topics.prefix(8).joined(separator: ", ")
        case .actionItems:
            let items = InsightRevision.decodeActions(insight.actionItemsJSON)
            if !items.isEmpty {
                return items.prefix(3).map(\.text).joined(separator: "\n")
            }
            fallthrough
        case .summary, .full:
            if let sections = SummarySection.parse(insight.summary), let first = sections.first {
                return first.intro ?? first.title
            }
            return String(insight.summary.prefix(220))
        }
    }
}
