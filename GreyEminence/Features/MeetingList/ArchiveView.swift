import SwiftUI
import SwiftData

/// Full meeting library for extract, and a place to file meetings away from
/// the recent list. The Meetings sidebar stays the last three months minus
/// anything filed here.
struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @Binding var selectedMeeting: Meeting?
    @Binding var selectedMeetingIDs: Set<UUID>
    var onExtract: (ArchiveExtractLaunch) -> Void

    @State private var query: String = ""
    @State private var selectedYear: Int? = nil
    @State private var requireInsights = false
    @State private var requireExported = false
    @State private var requireActionItems = false
    @State private var requireFiled = false
    @State private var collapsedQuarters: Set<String> = []
    @State private var renamingMeetingID: UUID?
    @AppStorage("meetingListGroupBy") private var groupByRaw = MeetingListGroupBy.date.rawValue

    private var groupBy: MeetingListGroupBy {
        MeetingListGroupBy(rawValue: groupByRaw) ?? .date
    }

    private var cutoffDate: Date {
        MeetingLibrary.recentCutoff()
    }

    private var archivedMeetings: [Meeting] {
        allMeetings.filter { MeetingLibrary.isLibrary($0) }
    }

    private var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(archivedMeetings.map { cal.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    private var filteredMeetings: [Meeting] {
        let cal = Calendar.current
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return archivedMeetings.filter { meeting in
            if let year = selectedYear, cal.component(.year, from: meeting.date) != year {
                return false
            }
            if requireInsights && meeting.insights.isEmpty { return false }
            if requireExported && !meeting.isExportedToObsidian { return false }
            if requireActionItems && meeting.pendingActionCount == 0 { return false }
            if requireFiled && !meeting.isArchived { return false }
            if !trimmedQuery.isEmpty {
                let titleMatches = meeting.title.lowercased().contains(trimmedQuery)
                let attendeeMatches = meeting.attendees.contains { $0.name.lowercased().contains(trimmedQuery) }
                let summaryMatches = meeting.insights.contains { $0.summary.lowercased().contains(trimmedQuery) }
                if !(titleMatches || attendeeMatches || summaryMatches) { return false }
            }
            return true
        }
    }

    /// Date mode: calendar quarters. Series / Related: same buckets as the
    /// recent Meetings list.
    private var archiveGroups: [(String, [Meeting])] {
        switch groupBy {
        case .date:
            return quarterlyGroups
        case .series, .related:
            return MeetingListGrouping.sections(
                for: filteredMeetings,
                groupBy: groupBy,
                now: .now
            )
        }
    }

    /// Group by calendar quarter — "Q1 2026", "Q4 2025", etc. Quarters scale
    /// gracefully: even with 100 meetings/month, a quarter is ~300 rows worst
    /// case which List virtualizes fine; users typically know roughly when an
    /// old meeting happened to within a quarter.
    private var quarterlyGroups: [(String, [Meeting])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredMeetings) { meeting -> String in
            let year = cal.component(.year, from: meeting.date)
            let month = cal.component(.month, from: meeting.date)
            let quarter = (month - 1) / 3 + 1
            return "Q\(quarter) \(year)"
        }
        return grouped
            .map { key, values in (key, values.sorted { $0.date > $1.date }) }
            .sorted { quarterSortKey($0.0) > quarterSortKey($1.0) }
    }

    /// "Q3 2025" → 2025 * 4 + 3 = 8103. Higher = more recent.
    private func quarterSortKey(_ label: String) -> Int {
        let parts = label.split(separator: " ")
        guard parts.count == 2,
              let q = Int(parts[0].dropFirst()),
              let y = Int(parts[1]) else { return 0 }
        return y * 4 + q
    }

    private var hasActiveFilters: Bool {
        selectedYear != nil || requireInsights || requireExported || requireActionItems || requireFiled || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearFilters() {
        query = ""
        selectedYear = nil
        requireInsights = false
        requireExported = false
        requireActionItems = false
        requireFiled = false
    }

    private func setArchived(_ meeting: Meeting, _ archived: Bool) {
        MeetingLibrary.setArchived([meeting], archived, in: modelContext)
    }

    private func archiveSelected() {
        let targets = allMeetings.filter { selectedMeetingIDs.contains($0.id) }
        MeetingLibrary.setArchived(targets, true, in: modelContext)
    }

    private func deleteMeeting(_ meeting: Meeting) {
        selectedMeetingIDs.remove(meeting.id)
        MeetingDeletion.delete(meeting, in: modelContext, allMeetings: allMeetings)
    }

    private func makeLaunch(
        scope: ArchiveExtractScope,
        meeting: Meeting?,
        group: [Meeting] = [],
        seriesLabel: String? = nil
    ) -> ArchiveExtractLaunch {
        ArchiveExtractLaunch(
            initialScope: scope,
            seriesLabel: seriesLabel,
            seedMeetingID: meeting?.id,
            selectedIDs: selectedMeetingIDs,
            visibleIDs: Set(filteredMeetings.map(\.id)),
            groupMeetingIDs: Set(group.map(\.id))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchAndFilterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.background)
            Divider()
            Group {
                if archivedMeetings.isEmpty {
                    ContentUnavailableView(
                        "No meetings yet",
                        systemImage: "archivebox",
                        description: Text("Every recording shows up here so you can extract it. File any meeting away from the recent Meetings list without waiting three months.")
                    )
                } else if filteredMeetings.isEmpty {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term, year, or clear the filters.")
                    )
                } else {
                    meetingList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Archive")
        .onChange(of: selectedMeetingIDs) { oldIDs, newIDs in
            let next = MeetingListSelection.detailMeeting(
                previousIDs: oldIDs,
                newIDs: newIDs,
                current: selectedMeeting,
                from: allMeetings
            )
            if selectedMeeting?.id != next?.id {
                selectedMeeting = next
            }
        }
    }

    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(MeetingListGroupBy.allCases) { option in
                        Button {
                            groupByRaw = option.rawValue
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if groupBy == option { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Group: \(groupBy.rawValue)", systemImage: groupBy.systemImage)
                }
                .help(groupBy.help)
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title, attendee, or summary…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Wraps to multiple rows when the column is narrow so chips stop
            // collapsing into vertical letter stacks. fixedSize on each chip
            // pins the natural width — no mid-word breaks.
            FlowLayout(spacing: 6) {
                yearMenu
                filterChip("Insights", systemImage: "lightbulb", isOn: $requireInsights)
                filterChip("Exported", systemImage: "arrow.up.doc", isOn: $requireExported)
                filterChip("Actions", systemImage: "checkmark.circle", isOn: $requireActionItems)
                filterChip("Filed away", systemImage: "archivebox", isOn: $requireFiled)
            }

            HStack(spacing: 8) {
                Text("\(filteredMeetings.count) of \(archivedMeetings.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if hasActiveFilters {
                    Button("Clear filters") { clearFilters() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onExtract(makeLaunch(
                        scope: selectedMeetingIDs.isEmpty ? .allVisible : .selected,
                        meeting: selectedMeeting
                    ))
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(filteredMeetings.isEmpty)
                .help("Export transcripts and intel as a zip or PDF for the selected meetings, a series, or everything currently listed.")
            }
        }
    }

    private var yearMenu: some View {
        Menu {
            Button("All years") { selectedYear = nil }
            Divider()
            ForEach(availableYears, id: \.self) { year in
                Button {
                    selectedYear = year
                } label: {
                    HStack {
                        Text(String(year))
                        if selectedYear == year {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(selectedYear.map(String.init) ?? "All years")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (selectedYear != nil ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.secondary.opacity(0.10))),
                in: Capsule()
            )
            .foregroundStyle(selectedYear != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func filterChip(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isOn.wrappedValue ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.secondary.opacity(0.10)),
                in: Capsule()
            )
            .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private var meetingList: some View {
        List(selection: $selectedMeetingIDs) {
            ForEach(archiveGroups, id: \.0) { quarter, quarterMeetings in
                Section {
                    if !collapsedQuarters.contains(quarter) {
                        ForEach(quarterMeetings) { meeting in
                            MeetingRowView(meeting: meeting, renamingID: $renamingMeetingID)
                                .tag(meeting.id)
                                .contextMenu {
                                    Button("Rename") {
                                        renamingMeetingID = meeting.id
                                    }
                                    MeetingExtractContextButtons(
                                        meeting: meeting,
                                        selectedIDs: selectedMeetingIDs,
                                        visibleIDs: Set(filteredMeetings.map(\.id)),
                                        library: allMeetings,
                                        onExtract: onExtract
                                    )
                                    if meeting.isArchived {
                                        Button {
                                            setArchived(meeting, false)
                                        } label: {
                                            Label("Put Back on Meetings", systemImage: "tray.and.arrow.up")
                                        }
                                        .disabled(meeting.date < cutoffDate)
                                        .help(meeting.date < cutoffDate
                                              ? "Older than three months — it stays in Archive."
                                              : "Show this meeting on the recent Meetings list again.")
                                    } else {
                                        Button {
                                            if selectedMeetingIDs.count > 1, selectedMeetingIDs.contains(meeting.id) {
                                                archiveSelected()
                                            } else {
                                                setArchived(meeting, true)
                                            }
                                        } label: {
                                            if selectedMeetingIDs.count > 1, selectedMeetingIDs.contains(meeting.id) {
                                                Label("File Selected Away (\(selectedMeetingIDs.count))", systemImage: "archivebox")
                                            } else {
                                                Label("File Away from Meetings", systemImage: "archivebox")
                                            }
                                        }
                                        .help("Hide from the recent Meetings list. It stays here for extract.")
                                    }
                                    Divider()
                                    MeetingReanalyzeContextButtons(
                                        meeting: meeting,
                                        selectedIDs: selectedMeetingIDs
                                    )
                                    Divider()
                                    Button(role: .destructive) {
                                        deleteMeeting(meeting)
                                    } label: {
                                        Label("Delete Meeting", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Button {
                        if collapsedQuarters.contains(quarter) {
                            collapsedQuarters.remove(quarter)
                        } else {
                            collapsedQuarters.insert(quarter)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: collapsedQuarters.contains(quarter) ? "chevron.right" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(quarter)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(quarterMeetings.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            let scope: ArchiveExtractScope = (groupBy == .date) ? .thisGroup : .thisSeries
                            onExtract(makeLaunch(
                                scope: scope,
                                meeting: quarterMeetings.first,
                                group: quarterMeetings,
                                seriesLabel: quarter
                            ))
                        } label: {
                            Label("Export \(quarter)…", systemImage: "square.and.arrow.up")
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MeetingSelectionBar(
                selectedIDs: selectedMeetingIDs,
                onExtract: {
                    onExtract(makeLaunch(scope: .selected, meeting: selectedMeeting))
                },
                onArchive: { archiveSelected() }
            )
        }
    }
}

