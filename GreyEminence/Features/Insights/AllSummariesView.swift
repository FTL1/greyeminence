import SwiftUI
import SwiftData
import AppKit

/// Meeting summaries in one place — search, group, copy, open the meeting.
struct AllSummariesView: View {
    var onMeetingSelected: ((Meeting) -> Void)?

    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @State private var searchText = ""
    @AppStorage("summaryGroupBySeries") private var groupBySeries = false

    private var items: [(meeting: Meeting, summary: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allMeetings.compactMap { meeting in
            guard !meeting.isInterviewMeeting, let summary = meeting.latestInsight?.summary,
                  !summary.isEmpty else { return nil }
            if !q.isEmpty {
                let hit = meeting.title.lowercased().contains(q)
                    || summary.lowercased().contains(q)
                    || (meeting.seriesTitle?.lowercased().contains(q) ?? false)
                if !hit { return nil }
            }
            return (meeting, summary)
        }
    }

    private var grouped: [(title: String, items: [(meeting: Meeting, summary: String)])] {
        if !groupBySeries {
            return [("All summaries", items)]
        }
        var buckets: [String: [(meeting: Meeting, summary: String)]] = [:]
        for item in items {
            let key = item.meeting.seriesTitle ?? "One-off meetings"
            buckets[key, default: []].append(item)
        }
        return buckets
            .map { (title: $0.key, items: $0.value) }
            .sorted { a, b in
                let ad = a.items.first?.meeting.date ?? .distantPast
                let bd = b.items.first?.meeting.date ?? .distantPast
                return ad > bd
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if items.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Summaries" : "No Matches",
                    systemImage: "doc.text",
                    description: Text(
                        searchText.isEmpty
                            ? "Summaries appear after a meeting is analyzed."
                            : "Try a different search."
                    )
                )
            } else {
                List {
                    ForEach(grouped, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.items, id: \.meeting.id) { item in
                                summaryRow(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Summaries")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search summaries or meeting title", text: $searchText)
                .textFieldStyle(.plain)
            Toggle("Group by series", isOn: $groupBySeries)
                .toggleStyle(.checkbox)
                .help("Put recurring meetings in their own piles")
            Button("Copy all") {
                let text = items.map { item in
                    "\(item.meeting.title) — \(item.meeting.date.formatted(date: .abbreviated, time: .omitted))\n\(plain(item.summary))"
                }.joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .disabled(items.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func summaryRow(_ item: (meeting: Meeting, summary: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onMeetingSelected?(item.meeting)
            } label: {
                HStack {
                    Text(item.meeting.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(item.meeting.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Text(preview(item.summary))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Copy summary") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plain(item.summary), forType: .string)
            }
            Button("Open meeting") { onMeetingSelected?(item.meeting) }
        }
    }

    private func preview(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.split(separator: "\n").first {
            return String(first)
        }
        return trimmed
    }

    private func plain(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
