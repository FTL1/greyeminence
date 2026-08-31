import SwiftUI
import SwiftData

/// Library home for Meeting Intelligence: what has been analyzed, what still
/// needs a pass, and jumps into Questions / Tasks / Summaries / Topics.
struct InsightsHubView: View {
    var selectedMeetingIDs: Set<UUID> = []
    var onMeetingSelected: ((Meeting) -> Void)?
    var onSelectDestination: ((SidebarDestination) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @State private var query = ""

    private var library: [Meeting] {
        allMeetings.filter { !$0.isInterviewMeeting }
    }

    private var analyzed: [Meeting] {
        filtered(library.filter { $0.latestInsight != nil })
    }

    private var needsAnalysis: [Meeting] {
        filtered(library.filter {
            $0.status == .completed && !$0.segments.isEmpty && $0.latestInsight == nil
        })
    }

    private var failed: [Meeting] {
        filtered(library.filter { $0.analysisError != nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                Section("Organize") {
                    workspaceRow(
                        .questions,
                        subtitle: "Create and sort follow-up questions"
                    )
                    workspaceRow(
                        .tasks,
                        subtitle: "Action items across meetings"
                    )
                    workspaceRow(
                        .summaries,
                        subtitle: "Browse and copy write-ups"
                    )
                    workspaceRow(
                        .topicMap,
                        subtitle: "Topics, people, and related dialog"
                    )
                }

                if !failed.isEmpty {
                    Section("Needs attention (\(failed.count))") {
                        ForEach(failed) { meeting in
                            meetingRow(meeting, badge: "failed", tint: .orange)
                        }
                    }
                }

                if !needsAnalysis.isEmpty {
                    Section("Transcript, no analysis (\(needsAnalysis.count))") {
                        ForEach(needsAnalysis) { meeting in
                            meetingRow(meeting, badge: "not analyzed", tint: .orange)
                        }
                    }
                }

                Section("Analyzed (\(analyzed.count))") {
                    if analyzed.isEmpty {
                        Text("Analyze a meeting to build intelligence here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(analyzed) { meeting in
                            meetingRow(meeting, badge: nil, tint: .green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Insights")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search meetings", text: $query)
                .textFieldStyle(.plain)
            if !needsAnalysis.isEmpty {
                Button("Analyze unanalyzed…") {
                    MeetingReanalysisQueue.shared.enqueue(
                        ids: needsAnalysis.map(\.id),
                        in: modelContext
                    )
                }
                .help("Queue AI analysis for meetings that have a transcript but no insight")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func workspaceRow(_ destination: SidebarDestination, subtitle: String) -> some View {
        Button {
            onSelectDestination?(destination)
        } label: {
            HStack(spacing: 10) {
                destination.iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.rawValue)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meetingRow(_ meeting: Meeting, badge: String?, tint: Color) -> some View {
        Button {
            onMeetingSelected?(meeting)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(meeting.date, style: .date)
                        if let insight = meeting.latestInsight {
                            Text("\(insight.followUpQuestions.count) Q")
                            Text("\(meeting.actionItems.filter { !$0.isCompleted && $0.dismissedAt == nil }.count) tasks")
                            Text("\(insight.topics.count) topics")
                        }
                        if let badge {
                            Text(badge)
                                .foregroundStyle(tint)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open meeting") { onMeetingSelected?(meeting) }
            if meeting.latestInsight == nil, meeting.status == .completed, !meeting.segments.isEmpty {
                Button("Analyze") {
                    MeetingReanalysisQueue.shared.enqueue(ids: [meeting.id], in: modelContext)
                }
            }
        }
    }

    private func filtered(_ meetings: [Meeting]) -> [Meeting] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.lowercased().contains(q)
                || ($0.calendarEventTitle?.lowercased().contains(q) ?? false)
        }
    }
}
