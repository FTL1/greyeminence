import SwiftUI
import SwiftData

struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Binding var selectedMeeting: Meeting?
    var onShowArchive: (() -> Void)?

    /// Recent list shows the current month plus the two prior months. Anything
    /// older lives in the Archive. Keeps the sidebar list bounded as the
    /// meeting count grows over time.
    private static let monthsVisible = 3

    private var cutoffDate: Date {
        let cal = Calendar.current
        let startOfCurrentMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return cal.date(byAdding: .month, value: -(Self.monthsVisible - 1), to: startOfCurrentMonth) ?? .distantPast
    }

    private var visibleMeetings: [Meeting] {
        let cutoff = cutoffDate
        return meetings.filter { !$0.isInterviewMeeting && $0.date >= cutoff }
    }

    private var archivedCount: Int {
        let cutoff = cutoffDate
        return meetings.filter { !$0.isInterviewMeeting && $0.date < cutoff }.count
    }

    private var groupedMeetings: [(String, [Meeting])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleMeetings) { meeting -> String in
            if calendar.isDateInToday(meeting.date) {
                return "Today"
            } else if calendar.isDateInYesterday(meeting.date) {
                return "Yesterday"
            } else if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: .now),
                      weekInterval.contains(meeting.date) {
                return "This Week"
            } else if let monthInterval = calendar.dateInterval(of: .month, for: .now),
                      monthInterval.contains(meeting.date) {
                return "This Month"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: meeting.date)
            }
        }
        let order = ["Today", "Yesterday", "This Week", "This Month"]
        return grouped.sorted { a, b in
            let aIdx = order.firstIndex(of: a.key) ?? Int.max
            let bIdx = order.firstIndex(of: b.key) ?? Int.max
            if aIdx != bIdx { return aIdx < bIdx }
            return a.key > b.key
        }
    }

    private func deleteMeeting(_ meeting: Meeting) {
        if selectedMeeting == meeting {
            selectedMeeting = nil
        }
        MeetingDeletion.delete(meeting, in: modelContext, allMeetings: meetings)
    }

    var body: some View {
        List(selection: $selectedMeeting) {
            ForEach(groupedMeetings, id: \.0) { section, sectionMeetings in
                Section {
                    ForEach(sectionMeetings) { meeting in
                        MeetingRowView(meeting: meeting)
                            .tag(meeting)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteMeeting(meeting)
                                } label: {
                                    Label("Delete Meeting", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            deleteMeeting(sectionMeetings[index])
                        }
                    }
                } header: {
                    Text(section)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }

            if archivedCount > 0, let onShowArchive {
                Section {
                    Button {
                        onShowArchive()
                    } label: {
                        HStack {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.secondary)
                            Text("View archive")
                            Spacer()
                            Text("\(archivedCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Meetings")
        .overlay {
            if visibleMeetings.isEmpty && archivedCount == 0 {
                ContentUnavailableView(
                    "No Meetings Yet",
                    systemImage: "waveform",
                    description: Text("Start a recording to create your first meeting")
                )
            }
        }
    }
}
