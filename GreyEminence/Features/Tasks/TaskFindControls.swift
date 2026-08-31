import SwiftUI
import SwiftData

enum TaskMeetingScope: String, CaseIterable, Identifiable {
    case analyzed = "Analyzed meetings"
    case selected = "Selected meetings"
    case series = "Series"
    case calendar = "Calendar event"
    case picked = "Chosen meetings"
    var id: String { rawValue }
}

enum TaskPeopleScope: String, CaseIterable, Identifiable {
    case me = "Me"
    case meAndUnassigned = "Me + unassigned"
    case others = "Others"
    case everyone = "Everyone"
    case custom = "Specific people"
    var id: String { rawValue }
}

enum TaskGroupBy: String, CaseIterable, Identifiable {
    case status = "Status"
    case meeting = "Meeting"
    case date = "Date"
    case series = "Series / collection"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .status: "circle.lefthalf.filled"
        case .meeting: "calendar"
        case .date: "calendar.badge.clock"
        case .series: "rectangle.stack"
        }
    }
}

/// Pick which unanalyzed (or filter) meetings to act on. Analysis is sequential
/// and slow, so nothing is checked by default.
struct TaskMeetingPickerSheet: View {
    enum Purpose {
        case analyze
        case filter
    }

    let purpose: Purpose
    let meetings: [Meeting]
    @Binding var pickedIDs: Set<UUID>
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Meeting] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.lowercased().contains(q)
                || ($0.calendarEventTitle?.lowercased().contains(q) ?? false)
                || ($0.seriesTitle?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if meetings.isEmpty {
                ContentUnavailableView(
                    purpose == .analyze ? "Nothing left to analyze" : "No meetings",
                    systemImage: "checkmark.circle",
                    description: Text(
                        purpose == .analyze
                            ? "Every meeting with a transcript already has AI analysis."
                            : "No meetings match this list."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(purpose == .analyze ? "Analyze meetings" : "Search these meetings")
                .font(.headline)
            if purpose == .analyze {
                Text("Each meeting is analyzed one at a time and can take several minutes. Pick only the ones you need.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tasks will be limited to the meetings you check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by title, series, or calendar event", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
    }

    private var allShownSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { pickedIDs.contains($0.id) }
    }

    private var someShownSelected: Bool {
        filtered.contains { pickedIDs.contains($0.id) }
    }

    private var selectAllShownBinding: Binding<Bool> {
        Binding(
            get: { allShownSelected },
            set: { on in
                if on {
                    for meeting in filtered { pickedIDs.insert(meeting.id) }
                } else {
                    for meeting in filtered { pickedIDs.remove(meeting.id) }
                }
            }
        )
    }

    private var list: some View {
        List {
            Section {
                Toggle(isOn: selectAllShownBinding) {
                    Text(allShownSelected ? "Deselect all" : "Select all")
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.checkbox)
                .help("Check to select every meeting in this list. Uncheck to clear them.")
                .listRowBackground(Color.secondary.opacity(0.08))
                .accessibilityLabel(allShownSelected ? "Deselect all meetings" : "Select all meetings")
                .accessibilityValue(someShownSelected && !allShownSelected ? "Some selected" : "")

                ForEach(filtered, id: \.id) { meeting in
                    Toggle(isOn: binding(for: meeting.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(meeting.date, style: .date)
                                Text(meeting.formattedDuration)
                                if meeting.latestInsight != nil {
                                    Text("analyzed")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("not analyzed")
                                        .foregroundStyle(.orange)
                                }
                                if let cal = meeting.calendarEventTitle, !cal.isEmpty {
                                    Text(cal)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Button("Select shown") {
                for meeting in filtered { pickedIDs.insert(meeting.id) }
            }
            .disabled(filtered.isEmpty)
            Button("Clear") { pickedIDs.removeAll() }
                .disabled(pickedIDs.isEmpty)
            Text("\(pickedIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button(purpose == .analyze ? "Analyze selected" : "Use selected") {
                onConfirm()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(pickedIDs.isEmpty)
        }
        .padding(16)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { pickedIDs.contains(id) },
            set: { on in
                if on { pickedIDs.insert(id) } else { pickedIDs.remove(id) }
            }
        )
    }
}
