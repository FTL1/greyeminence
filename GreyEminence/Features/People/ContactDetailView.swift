import SwiftUI
import SwiftData

struct ContactDetailView: View {
    @Bindable var contact: Contact
    @AppStorage("stalledThresholdDays") private var stalledThresholdDays = 7

    var body: some View {
        List {
            if contact.isArchived {
                Section {
                    Label("This contact is inactive (e.g. left the company). They won't appear in search, pickers, or calendar auto-linking — but stay on the meetings they already attended.", systemImage: "person.crop.circle.badge.xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Voice") {
                if contact.hasVoicePrint {
                    Label("Voice print enrolled", systemImage: "waveform")
                    if let date = contact.voicePrintUpdatedAt {
                        Text("Updated \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove voice print", role: .destructive) {
                        contact.clearVoicePrint()
                    }
                } else {
                    Text("No voice print yet. Right-click this person in a transcript and choose Enroll voice print.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                TextField("Name", text: $contact.name)
                TextField("Nickname", text: Binding(
                    get: { contact.nickname ?? contact.firstName },
                    set: { new in
                        let trimmed = new.trimmingCharacters(in: .whitespaces)
                        contact.nickname = trimmed == contact.firstName ? nil : (trimmed.isEmpty ? nil : trimmed)
                    }
                ), prompt: Text(contact.firstName))
                TextField("Email", text: Binding(
                    get: { contact.email ?? "" },
                    set: { contact.email = $0.isEmpty ? nil : $0 }
                ))
                Toggle("Interviewer", isOn: $contact.isInterviewer)
            }

            if !contact.meetings.isEmpty {
                Section("Meetings (\(contact.meetings.count))") {
                    ForEach(sortedMeetings) { meeting in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(.body)
                                Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !contact.assignedActionItems.isEmpty {
                Section {
                    if let rate = commitmentService.completionRate(for: contact) {
                        HStack {
                            Text("Completion Rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", rate * 100))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(rate >= 0.7 ? .green : .orange)
                        }
                    }

                    ForEach(contact.assignedActionItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                            Text(item.text)
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        }
                    }
                } header: {
                    Text("Commitments (\(contact.assignedActionItems.count))")
                }

                let stalled = commitmentService.stalledCommitments(for: contact, threshold: stalledThresholdDays)
                if !stalled.isEmpty {
                    Section("Stalled (\(stalled.count))") {
                        ForEach(stalled) { item in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(item.daysStalled > 14 ? .red : .orange)
                                Text(item.actionItem.text)
                                    .font(.body)
                                Spacer()
                                Text("\(item.daysStalled)d")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItem {
                Button {
                    contact.isArchived.toggle()
                } label: {
                    Label(
                        contact.isArchived ? "Mark Active" : "Mark Inactive",
                        systemImage: contact.isArchived ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark"
                    )
                }
                .help(contact.isArchived
                      ? "Reactivate this contact so they appear in search and pickers again"
                      : "Mark inactive (e.g. left the company) — hides them from search, pickers, and calendar auto-linking")
            }
        }
    }

    private let commitmentService = CommitmentTrackingService()

    private var sortedMeetings: [Meeting] {
        contact.meetings.sorted { $0.date > $1.date }
    }
}
