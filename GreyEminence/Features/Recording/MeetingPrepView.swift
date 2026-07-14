import SwiftUI

struct MeetingPrepView: View {
    let context: MeetingPrepContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Meeting Prep", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                if case .history(let count, let mostRecent) = context.provenance {
                    Text(Self.historySummary(count: count, mostRecent: mostRecent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch context.provenance {
            case .firstOccurrence(let title):
                statedMessage(
                    icon: "clock.arrow.circlepath",
                    text: "First time recording “\(title)”. Once you've recorded it before, unresolved items, open questions, and recent topics from past occurrences will appear here."
                )
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

    // MARK: - Copy (presentation owns the wording; the service carries only data)

    /// Provenance line for the prep card when prior occurrences exist.
    nonisolated static func historySummary(count: Int, mostRecent: Date?) -> String {
        if count <= 1 {
            if let mostRecent {
                return "From the last time you recorded this meeting · \(shortDate(mostRecent))"
            }
            return "From the last time you recorded this meeting"
        }
        return "From your last \(count) recordings of this meeting"
    }

    nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - States

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
