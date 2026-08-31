import SwiftUI
import SwiftData

/// This meeting's topics as a cloud. Click a topic to see matching transcript
/// lines. Optionally fold in the same topic from other meetings.
struct MeetingTopicCloudSheet: View {
    let meeting: Meeting
    var initialTopic: String?
    var onOpenSegment: ((Meeting, UUID) -> Void)?
    var onOpenInTopicMap: ((String) -> Void)?

    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: String?
    @State private var includeOtherMeetings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cloud
                    if let topic = selectedTopic {
                        dialog(for: topic)
                    } else {
                        Text("Click a topic to see the conversation that mentioned it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            if selectedTopic == nil {
                selectedTopic = initialTopic ?? topics.first
            }
        }
    }

    private var topics: [String] {
        if let insightTopics = meeting.latestInsight?.topics, !insightTopics.isEmpty {
            return insightTopics
        }
        return []
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Topic cloud", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text(meeting.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Toggle("Include other meetings", isOn: $includeOtherMeetings)
                .toggleStyle(.checkbox)
                .help("Also show matching lines from other meetings tagged with this topic")
            if let topic = selectedTopic, onOpenInTopicMap != nil {
                Button("Open in Topic Map") {
                    onOpenInTopicMap?(topic)
                    dismiss()
                }
                .help("See this topic across the whole library")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var cloud: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This meeting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if topics.isEmpty {
                Text("No topics yet. Reanalyze this meeting to generate them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        let weight = currentSnippets(for: topic).count
                        Button {
                            selectedTopic = topic
                        } label: {
                            Text(topic)
                                .font(.system(size: fontSize(for: weight), weight: selectedTopic == topic ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedTopic == topic
                                        ? Color.purple.opacity(0.28)
                                        : Color.purple.opacity(0.10),
                                    in: Capsule()
                                )
                                .foregroundStyle(.purple)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedTopic == topic ? Color.purple : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Show conversation about \(topic)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dialog(for topic: String) -> some View {
        let current = currentSnippets(for: topic)
        let others = includeOtherMeetings ? otherSnippets(for: topic) : []

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(topic)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(includeOtherMeetings
                     ? "\(current.count) here · \(others.count) elsewhere"
                     : "\(current.count) line\(current.count == 1 ? "" : "s") in this meeting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            snippetBlock(
                title: "This meeting",
                snippets: current,
                empty: "No matching lines in this transcript. The topic was tagged from the whole discussion."
            )

            if includeOtherMeetings {
                snippetBlock(
                    title: "Other meetings",
                    snippets: others,
                    empty: "No other analyzed meetings mention this topic, or none of their lines match."
                )
            }
        }
    }

    private func snippetBlock(title: String, snippets: [TopicDialogSnippet], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if snippets.isEmpty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(snippets) { snippet in
                    Button {
                        if let target = allMeetings.first(where: { $0.id == snippet.meetingID }) {
                            onOpenSegment?(target, snippet.id)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(snippet.speakerName)
                                    .font(.caption.weight(.semibold))
                                Text(snippet.timestamp)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if !snippet.isCurrentMeeting {
                                    Text(snippet.meetingTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(snippet.meetingDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            Text(snippet.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(snippet.isCurrentMeeting
                          ? "Jump to this line in the transcript"
                          : "Open that meeting and jump to this line")
                }
            }
        }
    }

    private func currentSnippets(for topic: String) -> [TopicDialogSnippet] {
        TopicDialogMatcher.snippets(
            from: meeting.segments,
            topic: topic,
            meeting: meeting,
            isCurrentMeeting: true
        )
    }

    private func otherSnippets(for topic: String) -> [TopicDialogSnippet] {
        let others = TopicDialogMatcher.meetings(
            sharing: topic,
            excluding: meeting.id,
            among: allMeetings.filter { !$0.isInterviewMeeting }
        )
        var collected: [TopicDialogSnippet] = []
        for other in others {
            let hits = TopicDialogMatcher.snippets(
                from: other.segments,
                topic: topic,
                meeting: other,
                isCurrentMeeting: false,
                limit: 6
            )
            collected.append(contentsOf: hits)
            if collected.count >= 24 { break }
        }
        return collected
    }

    private func fontSize(for matchCount: Int) -> CGFloat {
        CGFloat(12 + min(max(matchCount, 1), 6))
    }
}
