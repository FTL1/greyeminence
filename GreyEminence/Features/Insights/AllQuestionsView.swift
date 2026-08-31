import SwiftUI
import SwiftData
import AppKit

/// Follow-up questions across meetings — add your own, delete, copy, jump.
struct AllQuestionsView: View {
    var selectedMeetingIDs: Set<UUID> = []
    var onMeetingSelected: ((Meeting) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var draft = ""
    @State private var addToMeetingID: UUID?

    private var library: [Meeting] {
        allMeetings.filter { !$0.isInterviewMeeting && $0.latestInsight != nil }
    }

    private var rows: [(id: String, text: String, index: Int, meeting: Meeting)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [(id: String, text: String, index: Int, meeting: Meeting)] = []
        for meeting in library {
            guard let questions = meeting.latestInsight?.followUpQuestions else { continue }
            for (index, text) in questions.enumerated() {
                if !q.isEmpty {
                    let hit = text.lowercased().contains(q) || meeting.title.lowercased().contains(q)
                    if !hit { continue }
                }
                result.append((
                    id: "\(meeting.id.uuidString)-\(index)",
                    text: text,
                    index: index,
                    meeting: meeting
                ))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Follow-up Questions" : "No Matches",
                    systemImage: "questionmark.bubble",
                    description: Text(
                        searchText.isEmpty
                            ? "Questions appear after a meeting is analyzed. You can also add your own."
                            : "Try a different search."
                    )
                )
            } else {
                List {
                    ForEach(rows, id: \.id) { row in
                        questionRow(row)
                    }
                }
            }
        }
        .navigationTitle("Questions")
        .sheet(isPresented: $showAdd) {
            addSheet
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search questions or meeting title", text: $searchText)
                .textFieldStyle(.plain)
            Button("Copy all") {
                let text = rows.enumerated().map { "\($0.offset + 1). \($0.element.text) — \($0.element.meeting.title)" }
                    .joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .disabled(rows.isEmpty)
            .help("Copy the visible questions")
            Button {
                addToMeetingID = selectedMeetingIDs.first ?? library.first?.id
                draft = ""
                showAdd = true
            } label: {
                Label("New question", systemImage: "plus")
            }
            .disabled(library.isEmpty)
            .help("Add a follow-up to an analyzed meeting")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func questionRow(_ row: (id: String, text: String, index: Int, meeting: Meeting)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.text)
                .textSelection(.enabled)
            Button {
                onMeetingSelected?(row.meeting)
            } label: {
                Text(row.meeting.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                + Text(" · ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                + Text(row.meeting.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.text, forType: .string)
            }
            Button("Open meeting") { onMeetingSelected?(row.meeting) }
            Button("Delete", role: .destructive) {
                deleteQuestion(in: row.meeting, at: row.index)
            }
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New follow-up question")
                .font(.headline)
            Picker("Meeting", selection: $addToMeetingID) {
                ForEach(library) { meeting in
                    Text(meeting.title).tag(Optional(meeting.id))
                }
            }
            TextField("What should we ask next time?", text: $draft, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showAdd = false }
                Button("Add") { addQuestion() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addToMeetingID == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func addQuestion() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = addToMeetingID,
              let meeting = library.first(where: { $0.id == id }),
              let insight = meeting.latestInsight else { return }
        insight.followUpQuestions.append(text)
        PersistenceGate.save(modelContext, site: "AllQuestionsView.add", meetingID: meeting.id)
        showAdd = false
        draft = ""
    }

    private func deleteQuestion(in meeting: Meeting, at index: Int) {
        guard let insight = meeting.latestInsight,
              insight.followUpQuestions.indices.contains(index) else { return }
        let text = insight.followUpQuestions[index]
        let key = MeetingReanalysis.normalizeKey(text)
        if !meeting.suppressedFollowUps.contains(key) {
            meeting.suppressedFollowUps.append(key)
        }
        insight.followUpQuestions.remove(at: index)
        PersistenceGate.save(modelContext, site: "AllQuestionsView.delete", meetingID: meeting.id)
    }
}
