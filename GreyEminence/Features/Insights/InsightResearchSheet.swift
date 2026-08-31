import SwiftUI
import SwiftData
import AppKit

/// Grounded lookup for one intelligence item against this meeting's transcript.
struct InsightResearchSheet: View {
    let title: String
    let itemText: String
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    @State private var answer: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Research")
                .font(.headline)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(itemText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Divider()
            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking this up from the meeting transcript…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !answer.isEmpty {
                ScrollView {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Copy answer") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                }
                .disabled(answer.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520, height: 420)
        .task { await run() }
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let client = try await AIClientFactory.makeClient() else {
                errorMessage = "No AI key configured. Add one in Settings → AI."
                return
            }
            let excerpts = Self.excerpts(from: meeting)
            let prompt = """
            Research this item from a recorded meeting. Use ONLY the excerpts.
            If the excerpts are not enough, say what is missing. Do not invent \
            facts, numbers, people, or outcomes.

            MEETING: \(meeting.title)
            DATE: \(meeting.date.formatted(date: .abbreviated, time: .shortened))
            ITEM: \(itemText)

            EXCERPTS:
            \(excerpts)
            """
            answer = try await AIUsageContext.attribute(.ask, meetingID: meeting.id) {
                try await client.sendMessage(
                    system: "You research a meeting follow-up using only the supplied transcript excerpts.",
                    userContent: prompt
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func excerpts(from meeting: Meeting, limit: Int = 40) -> String {
        let lines = meeting.segments
            .sorted { $0.startTime < $1.startTime }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let picked = lines.count <= limit ? lines : Array(lines.prefix(limit / 2)) + Array(lines.suffix(limit / 2))
        return picked.map { "\($0.speaker.displayName): \($0.text)" }.joined(separator: "\n")
    }
}
