import SwiftUI

struct MeetingPrepView: View {
    let context: MeetingPrepContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Meeting Prep", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                if case .history(let summary) = context.provenance {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch context.provenance {
            case .firstOccurrence(let title):
                firstOccurrenceMessage(title: title)
            case .history:
                if context.hasContent {
                    contentSections
                } else {
                    statedMessage(
                        icon: "checkmark.circle",
                        text: "Nothing carried over from last time — no open items or questions."
                    )
                }
            case .notApplicable:
                EmptyView()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - States

    /// Recurring meeting we've never recorded before — be honest about it.
    private func firstOccurrenceMessage(title: String) -> some View {
        statedMessage(
            icon: "clock.arrow.circlepath",
            text: "First time recording “\(title)”. Once you've recorded it before, unresolved items, open questions, and recent topics from past occurrences will appear here."
        )
    }

    private func statedMessage(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Content (history with carried-over items)

    private var contentSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !context.unresolvedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unresolved Items")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                    ForEach(context.unresolvedItems.prefix(5)) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundStyle(item.daysSinceCreated > 14 ? .red : .orange)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.text)
                                    .font(.caption)
                                HStack(spacing: 4) {
                                    if let assignee = item.assignee {
                                        Text(assignee)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(item.daysSinceCreated)d ago")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }

            if !context.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)

                    ForEach(context.followUps.prefix(3), id: \.self) { question in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .padding(.top, 2)
                            Text(question)
                                .font(.caption)
                        }
                    }
                }
            }

            if !context.previousTopics.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous Topics")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(context.previousTopics.prefix(8), id: \.self) { topic in
                            Text(topic)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
