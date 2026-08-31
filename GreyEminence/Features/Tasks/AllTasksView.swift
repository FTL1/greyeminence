import SwiftUI
import SwiftData
import AppKit

enum TaskSort: String, CaseIterable, Identifiable {
    case created = "Date Created"
    case dueDate = "Due Date"
    case meetingDate = "Meeting Date"
    case alphabetical = "Alphabetical"
    var id: String { rawValue }
}

enum TaskSortDirection: String, CaseIterable, Identifiable {
    case descending = "Descending"
    case ascending = "Ascending"
    var id: String { rawValue }
}

private let selfAssigneeSynonyms: Set<String> = ["me", "myself", "i"]

struct AllTasksView: View {
    var selectedMeetingIDs: Set<UUID> = []
    var onMeetingSelected: ((Meeting) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @AppStorage("stalledThresholdDays") private var stalledThresholdDays = 7
    @AppStorage("myContactID") private var myContactIDString = ""
    @AppStorage("taskSort") private var sortRaw = TaskSort.dueDate.rawValue
    @AppStorage("taskSortDirection") private var sortDirectionRaw = TaskSortDirection.ascending.rawValue
    @AppStorage("taskShowCompleted") private var showCompleted = true
    @AppStorage("taskShowDismissed") private var showDismissed = false
    @AppStorage("taskGroupBy") private var groupByRaw = TaskGroupBy.status.rawValue

    @Query(filter: #Predicate<ActionItem> { !$0.isCompleted && $0.dismissedAt == nil })
    private var pendingItems: [ActionItem]
    @Query(filter: #Predicate<ActionItem> { $0.isCompleted })
    private var completedItems: [ActionItem]
    @Query(filter: #Predicate<ActionItem> { $0.dismissedAt != nil })
    private var dismissedItems: [ActionItem]
    @Query private var allContacts: [Contact]
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]

    @State private var detailTask: ActionItem?
    @State private var showBulkDismissConfirmation = false
    @State private var meetingScope: TaskMeetingScope = .analyzed
    @State private var selectedSeriesID: UUID?
    @State private var selectedCalendarKey: String?
    @State private var pickedMeetingIDs: Set<UUID> = []
    @State private var peopleScope: TaskPeopleScope = .me
    @State private var customAssigneeIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var showAnalyzePrompt = false
    @State private var showAnalyzePicker = false
    @State private var showFilterPicker = false
    @State private var analyzePickIDs: Set<UUID> = []
    @State private var dismissedAnalyzeBanner = false

    private var sort: TaskSort {
        TaskSort(rawValue: sortRaw) ?? .dueDate
    }

    private var sortDirection: TaskSortDirection {
        TaskSortDirection(rawValue: sortDirectionRaw) ?? .ascending
    }

    private var groupBy: TaskGroupBy {
        TaskGroupBy(rawValue: groupByRaw) ?? .status
    }

    private var myContact: Contact? {
        guard let id = UUID(uuidString: myContactIDString) else { return nil }
        return allContacts.first { $0.id == id }
    }

    private var mySelfTokens: Set<String> {
        var tokens = selfAssigneeSynonyms
        if let name = myContact?.name {
            let lower = name.lowercased()
            tokens.insert(lower)
            if let first = lower.split(separator: " ").first {
                tokens.insert(String(first))
            }
        }
        return tokens
    }

    private var seriesOptions: [(id: UUID, title: String)] {
        var seen: [UUID: String] = [:]
        for meeting in allMeetings {
            if let id = meeting.seriesID {
                seen[id] = meeting.seriesTitle ?? meeting.title
            }
        }
        return seen.map { (id: $0.key, title: $0.value) }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var assigneeChoices: [Contact] {
        allContacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isUnassigned(_ item: ActionItem) -> Bool {
        item.assignedContact == nil
            && (item.assignee?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    private func isMine(_ item: ActionItem) -> Bool {
        if let assigned = item.assignedContact {
            return assigned.id == myContact?.id
        }
        guard let raw = item.assignee?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return false }
        return mySelfTokens.contains(raw.lowercased())
    }

    private func matchesPeople(_ item: ActionItem) -> Bool {
        switch peopleScope {
        case .me:
            return isMine(item)
        case .meAndUnassigned:
            return isMine(item) || isUnassigned(item)
        case .others:
            return !isMine(item) && !isUnassigned(item)
        case .everyone:
            return true
        case .custom:
            if let contactID = item.assignedContact?.id {
                return customAssigneeIDs.contains(contactID)
            }
            if let raw = item.assignee?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !raw.isEmpty {
                return assigneeChoices.contains {
                    customAssigneeIDs.contains($0.id) && $0.name.lowercased().contains(raw)
                }
            }
            return false
        }
    }

    private func isAnalyzed(_ meeting: Meeting) -> Bool {
        meeting.latestInsight != nil
    }

    private var libraryMeetings: [Meeting] {
        allMeetings.filter { !$0.isInterviewMeeting }
    }

    private var unanalyzedMeetings: [Meeting] {
        libraryMeetings.filter {
            $0.status == .completed
                && !$0.segments.isEmpty
                && !isAnalyzed($0)
        }
    }

    private var calendarEventOptions: [(key: String, title: String, count: Int)] {
        var buckets: [String: (title: String, count: Int)] = [:]
        for meeting in libraryMeetings {
            let title = (meeting.calendarEventTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = meeting.calendarEventID ?? title
            let current = buckets[key]?.count ?? 0
            buckets[key] = (title, current + 1)
        }
        return buckets.map { (key: $0.key, title: $0.value.title, count: $0.value.count) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func matchesMeetings(_ item: ActionItem) -> Bool {
        guard let meeting = item.meeting else { return false }
        switch meetingScope {
        case .analyzed:
            guard isAnalyzed(meeting) else { return false }
        case .selected:
            guard selectedMeetingIDs.contains(meeting.id) else { return false }
        case .series:
            guard let seriesID = selectedSeriesID, meeting.seriesID == seriesID else { return false }
        case .calendar:
            guard let key = selectedCalendarKey else { return false }
            let meetingKey = meeting.calendarEventID ?? meeting.calendarEventTitle
            guard meetingKey == key else { return false }
        case .picked:
            guard pickedMeetingIDs.contains(meeting.id) else { return false }
        }
        return true
    }

    private func matchesSearch(_ item: ActionItem) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if item.text.lowercased().contains(q) { return true }
        if item.displayAssignee?.lowercased().contains(q) == true { return true }
        if item.meeting?.title.lowercased().contains(q) == true { return true }
        if item.meeting?.calendarEventTitle?.lowercased().contains(q) == true { return true }
        return false
    }

    private func isVisible(_ item: ActionItem) -> Bool {
        matchesPeople(item) && matchesMeetings(item) && matchesSearch(item)
    }

    private func compare(_ a: ActionItem, _ b: ActionItem) -> Bool {
        let ascending = sortDirection == .ascending
        switch sort {
        case .created:
            return ascending ? a.createdAt < b.createdAt : a.createdAt > b.createdAt
        case .dueDate:
            switch (a.dueDate, b.dueDate) {
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.createdAt > b.createdAt
            case let (.some(x), .some(y)): return ascending ? x < y : x > y
            }
        case .meetingDate:
            let ad = a.meeting?.date ?? .distantPast
            let bd = b.meeting?.date ?? .distantPast
            return ascending ? ad < bd : ad > bd
        case .alphabetical:
            let result = a.text.localizedCaseInsensitiveCompare(b.text)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func sorted(_ items: [ActionItem]) -> [ActionItem] {
        items.sorted(by: compare)
    }

    private var stalledItems: [StalledCommitment] {
        CommitmentTrackingService()
            .stalledCommitments(in: modelContext, threshold: stalledThresholdDays)
            .filter { isVisible($0.actionItem) }
            .sorted { compare($0.actionItem, $1.actionItem) }
    }

    private var visiblePending: [ActionItem] {
        sorted(pendingItems.filter(isVisible))
    }

    private var visibleCompleted: [ActionItem] {
        showCompleted ? sorted(completedItems.filter(isVisible)) : []
    }

    private var visibleDismissed: [ActionItem] {
        showDismissed ? sorted(dismissedItems.filter(isVisible)) : []
    }

    private var nonStalledPending: [ActionItem] {
        let stalledIDs = Set(stalledItems.map(\.id))
        return visiblePending.filter { !stalledIDs.contains($0.id) }
    }

    private var exportItems: [ActionItem] {
        stalledItems.map(\.actionItem) + nonStalledPending + visibleCompleted + visibleDismissed
    }

    private var exportRows: [TaskExportRow] {
        TaskExportService.rows(from: exportItems, stalledIDs: Set(stalledItems.map(\.id)))
    }

    private var stalledDaysByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: stalledItems.map { ($0.id, $0.daysStalled) })
    }

    private func groupedSections() -> [(id: String, title: String, items: [ActionItem])] {
        let calendar = Calendar.current
        var buckets: [(id: String, title: String, sort: Date, items: [ActionItem])] = []
        var index: [String: Int] = [:]

        func append(id: String, title: String, sort: Date, item: ActionItem) {
            if let i = index[id] {
                buckets[i].items.append(item)
                if sort > buckets[i].sort { buckets[i].sort = sort }
            } else {
                index[id] = buckets.count
                buckets.append((id: id, title: title, sort: sort, items: [item]))
            }
        }

        for item in exportItems {
            switch groupBy {
            case .status:
                break
            case .meeting:
                let meeting = item.meeting
                append(
                    id: meeting?.id.uuidString ?? "none",
                    title: meeting?.title ?? "No meeting",
                    sort: meeting?.date ?? .distantPast,
                    item: item
                )
            case .date:
                let day = meetingDay(item.meeting?.date ?? item.createdAt, calendar: calendar)
                append(
                    id: day.id,
                    title: day.title,
                    sort: day.sort,
                    item: item
                )
            case .series:
                if let seriesID = item.meeting?.seriesID {
                    append(
                        id: seriesID.uuidString,
                        title: item.meeting?.seriesTitle ?? item.meeting?.title ?? "Series",
                        sort: item.meeting?.date ?? .distantPast,
                        item: item
                    )
                } else {
                    append(
                        id: "one-off",
                        title: "One-off meetings",
                        sort: item.meeting?.date ?? .distantPast,
                        item: item
                    )
                }
            }
        }

        return buckets
            .map { (id: $0.id, title: $0.title, items: sorted($0.items)) }
            .sorted { a, b in
                let ad = buckets.first(where: { $0.id == a.id })?.sort ?? .distantPast
                let bd = buckets.first(where: { $0.id == b.id })?.sort ?? .distantPast
                return ad > bd
            }
    }

    private func meetingDay(_ date: Date, calendar: Calendar) -> (id: String, title: String, sort: Date) {
        let start = calendar.startOfDay(for: date)
        let id = ISO8601DateFormatter().string(from: start)
        let title = start.formatted(date: .abbreviated, time: .omitted)
        return (id, title, start)
    }

    private func runFind() {
        if !dismissedAnalyzeBanner, !unanalyzedMeetings.isEmpty {
            showAnalyzePrompt = true
        }
    }

    private func bulkDismissStalled() {
        for stalled in stalledItems {
            stalled.actionItem.dismissedAt = .now
        }
        PersistenceGate.save(
            modelContext,
            site: "AllTasksView.bulkDismissStalled"
        )
        LogManager.send("Marked \(stalledItems.count) stalled task(s) as Won't Do (people: \(peopleScope.rawValue))", category: .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            queryBar
            Divider()
            taskList
        }
        .navigationTitle("All Tasks")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Mark \(stalledItems.count) stalled task\(stalledItems.count == 1 ? "" : "s") as Won't Do?",
            isPresented: $showBulkDismissConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Won't Do", role: .destructive) {
                bulkDismissStalled()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Affects the current people and meeting filters. Items can be restored from the Won't Do section.")
        }
        .confirmationDialog(
            "\(unanalyzedMeetings.count) meeting\(unanalyzedMeetings.count == 1 ? "" : "s") have a transcript but no AI analysis",
            isPresented: $showAnalyzePrompt,
            titleVisibility: .visible
        ) {
            Button("Choose meetings to analyze…") {
                analyzePickIDs = []
                showAnalyzePicker = true
            }
            Button("Not now", role: .cancel) {
                dismissedAnalyzeBanner = true
            }
        } message: {
            Text("Tasks only come from analyzed meetings. Analysis runs one meeting at a time and is slow — pick a small set.")
        }
        .sheet(isPresented: $showAnalyzePicker) {
            TaskMeetingPickerSheet(
                purpose: .analyze,
                meetings: unanalyzedMeetings,
                pickedIDs: $analyzePickIDs,
                onConfirm: {
                    MeetingReanalysisQueue.shared.enqueue(
                        ids: Array(analyzePickIDs),
                        in: modelContext
                    )
                }
            )
        }
        .sheet(isPresented: $showFilterPicker) {
            TaskMeetingPickerSheet(
                purpose: .filter,
                meetings: libraryMeetings.filter { $0.status == .completed && !$0.segments.isEmpty },
                pickedIDs: $pickedMeetingIDs,
                onConfirm: {
                    meetingScope = .picked
                }
            )
        }
        .overlay {
            if visiblePending.isEmpty && visibleCompleted.isEmpty {
                ContentUnavailableView(
                    pendingItems.isEmpty && completedItems.isEmpty
                        ? "No Action Items"
                        : "No Tasks Match Filter",
                    systemImage: "checkmark.circle",
                    description: Text(emptyDescription)
                )
            }
        }
        .sheet(item: $detailTask) { task in
            TaskDetailView(task: task, onOpenMeeting: onMeetingSelected)
        }
    }

    private var emptyDescription: String {
        if pendingItems.isEmpty && completedItems.isEmpty {
            if !unanalyzedMeetings.isEmpty {
                return "No tasks yet. \(unanalyzedMeetings.count) meeting(s) still need analysis."
            }
            return "Action items from analyzed meetings will appear here"
        }
        if meetingScope == .selected && selectedMeetingIDs.isEmpty {
            return "Select meetings in Meetings or Archive, or pick a series / calendar event"
        }
        return "Widen the meeting or assignee filter"
    }

    private var queryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                meetingScopeMenu
                peopleMenu
                groupByMenu
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search task text, assignee, or meeting title", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { runFind() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                Button("Find") { runFind() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .helpTip(.tasksFind)
                exportMenu
                    .controlSize(.small)
                if !searchText.isEmpty || meetingScope != .analyzed || peopleScope != .me || groupBy != .status {
                    Button("Reset") {
                        searchText = ""
                        meetingScope = .analyzed
                        peopleScope = .me
                        customAssigneeIDs = []
                        pickedMeetingIDs = []
                        selectedSeriesID = nil
                        selectedCalendarKey = nil
                        groupByRaw = TaskGroupBy.status.rawValue
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .helpTip(.tasksReset)
                }
            }
            if !unanalyzedMeetings.isEmpty && !dismissedAnalyzeBanner {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(unanalyzedMeetings.count) meeting\(unanalyzedMeetings.count == 1 ? "" : "s") have a transcript but no analysis, so they have no tasks yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Analyze…") {
                        analyzePickIDs = []
                        showAnalyzePicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Pick which meetings to analyze — one at a time, and slow")
                    Button("Dismiss") { dismissedAnalyzeBanner = true }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var taskList: some View {
        List {
            if groupBy == .status {
                if !stalledItems.isEmpty {
                    Section {
                        ForEach(stalledItems) { stalled in
                            taskRow(stalled.actionItem, stalledDays: stalled.daysStalled)
                        }
                    } header: {
                        Label("Stalled (\(stalledItems.count))", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .textCase(nil)
                    }
                }

                if !nonStalledPending.isEmpty {
                    Section {
                        ForEach(nonStalledPending) { item in
                            taskRow(item)
                        }
                    } header: {
                        Label("Pending (\(nonStalledPending.count))", systemImage: "circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }

                if !visibleCompleted.isEmpty {
                    Section {
                        ForEach(visibleCompleted) { item in
                            taskRow(item)
                        }
                    } header: {
                        Label("Completed (\(visibleCompleted.count))", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }

                if !visibleDismissed.isEmpty {
                    Section {
                        ForEach(visibleDismissed) { item in
                            taskRow(item)
                        }
                    } header: {
                        Label("Won't Do (\(visibleDismissed.count))", systemImage: "nosign")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            } else {
                ForEach(groupedSections(), id: \.id) { section in
                    Section {
                        ForEach(section.items) { item in
                            taskRow(item, stalledDays: stalledDaysByID[item.id])
                        }
                    } header: {
                        Label("\(section.title) (\(section.items.count))", systemImage: groupBy.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    private func taskRow(_ item: ActionItem, stalledDays: Int? = nil) -> some View {
        HStack {
            ActionItemRow(
                item: item,
                onShowDetails: { detailTask = $0 },
                showsMeetingContext: true,
                onOpenMeeting: onMeetingSelected
            )
            if let days = stalledDays {
                Text("\(days)d")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (days > 14 ? Color.red : .orange).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(days > 14 ? .red : .orange)
            }
        }
    }

    private var groupByMenu: some View {
        Menu {
            ForEach(TaskGroupBy.allCases) { option in
                Button {
                    groupByRaw = option.rawValue
                } label: {
                    peopleRow(option.rawValue, selected: groupBy == option)
                }
            }
        } label: {
            Label("Group: \(groupBy.rawValue)", systemImage: "rectangle.3.group")
        }
        .help("Organize the visible tasks by status, meeting, date, or recurring series")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            exportMenu
        }
        ToolbarItem(placement: .primaryAction) {
            optionsMenu
        }
    }

    private var meetingScopeMenu: some View {
        Menu {
            Button {
                meetingScope = .analyzed
            } label: {
                peopleRow("All analyzed meetings", selected: meetingScope == .analyzed)
            }
            Button {
                meetingScope = .selected
            } label: {
                peopleRow(
                    selectedMeetingIDs.isEmpty ? "Selected in Meetings list" : "Selected in Meetings list (\(selectedMeetingIDs.count))",
                    selected: meetingScope == .selected
                )
            }
            Button {
                pickedMeetingIDs = []
                showFilterPicker = true
            } label: {
                peopleRow(
                    pickedMeetingIDs.isEmpty ? "Choose meetings…" : "Chosen meetings (\(pickedMeetingIDs.count))",
                    selected: meetingScope == .picked
                )
            }
            if !seriesOptions.isEmpty {
                Section("Recurring series") {
                    ForEach(seriesOptions, id: \.id) { series in
                        Button {
                            meetingScope = .series
                            selectedSeriesID = series.id
                        } label: {
                            peopleRow(series.title, selected: meetingScope == .series && selectedSeriesID == series.id)
                        }
                    }
                }
            }
            if !calendarEventOptions.isEmpty {
                Section("Calendar") {
                    ForEach(calendarEventOptions, id: \.key) { event in
                        Button {
                            meetingScope = .calendar
                            selectedCalendarKey = event.key
                        } label: {
                            peopleRow(
                                "\(event.title) (\(event.count))",
                                selected: meetingScope == .calendar && selectedCalendarKey == event.key
                            )
                        }
                    }
                }
            }
        } label: {
            Label(meetingScopeLabel, systemImage: "calendar")
        }
        .helpTip(.tasksMeetingsMenu)
    }

    private var meetingScopeLabel: String {
        switch meetingScope {
        case .analyzed: return "Analyzed"
        case .selected: return selectedMeetingIDs.isEmpty ? "Selected" : "Selected (\(selectedMeetingIDs.count))"
        case .series:
            if let id = selectedSeriesID, let title = seriesOptions.first(where: { $0.id == id })?.title {
                return title
            }
            return "Series"
        case .calendar:
            if let key = selectedCalendarKey,
               let title = calendarEventOptions.first(where: { $0.key == key })?.title {
                return title
            }
            return "Calendar"
        case .picked:
            return pickedMeetingIDs.isEmpty ? "Chosen" : "Chosen (\(pickedMeetingIDs.count))"
        }
    }

    private var peopleMenu: some View {
        Menu {
            Button {
                peopleScope = .me
                customAssigneeIDs = []
            } label: {
                peopleRow("Me", selected: peopleScope == .me)
            }
            Button {
                peopleScope = .meAndUnassigned
                customAssigneeIDs = []
            } label: {
                peopleRow("Me + unassigned", selected: peopleScope == .meAndUnassigned)
            }
            Button {
                peopleScope = .others
                customAssigneeIDs = []
            } label: {
                peopleRow("Others", selected: peopleScope == .others)
            }
            Button {
                peopleScope = .everyone
                customAssigneeIDs = []
            } label: {
                peopleRow("Everyone", selected: peopleScope == .everyone)
            }
            if !assigneeChoices.isEmpty {
                Section("Specific people") {
                    ForEach(assigneeChoices) { contact in
                        Button {
                            peopleScope = .custom
                            if customAssigneeIDs.contains(contact.id) {
                                customAssigneeIDs.remove(contact.id)
                            } else {
                                customAssigneeIDs.insert(contact.id)
                            }
                            if customAssigneeIDs.isEmpty { peopleScope = .me }
                        } label: {
                            peopleRow(contact.name, selected: customAssigneeIDs.contains(contact.id))
                        }
                    }
                }
            }
        } label: {
            Label(peopleLabel, systemImage: "person")
        }
        .helpTip(.tasksAssignedMenu)
    }

    private var peopleLabel: String {
        switch peopleScope {
        case .me: return "Me"
        case .meAndUnassigned: return "Me + unassigned"
        case .others: return "Others"
        case .everyone: return "Everyone"
        case .custom:
            return customAssigneeIDs.count == 1 ? "1 person" : "\(customAssigneeIDs.count) people"
        }
    }

    private func peopleRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(TaskExportService.plainText(rows: exportRows), forType: .string)
                TransientActivityCoordinator.shared.flash("Copied \(exportRows.count) action(s)")
            }
            Divider()
            ForEach(TaskExportFormat.allCases) { format in
                Button("Export \(format.rawValue)…") {
                    Task { await TaskExportService.presentSavePanel(format: format, rows: exportRows) }
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .helpTip(.tasksExport)
        .disabled(exportRows.isEmpty)
    }

    private var optionsMenu: some View {
        Menu {
            Section("Sort by") {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(TaskSort.allCases) { s in
                        Text(s.rawValue).tag(s.rawValue)
                    }
                }
            }
            Section("Direction") {
                Picker("Direction", selection: $sortDirectionRaw) {
                    ForEach(TaskSortDirection.allCases) { d in
                        Label(
                            d.rawValue,
                            systemImage: d == .ascending ? "arrow.up" : "arrow.down"
                        ).tag(d.rawValue)
                    }
                }
            }
            Section {
                Toggle("Show Completed", isOn: $showCompleted)
                Toggle("Show Won't Do", isOn: $showDismissed)
            }
            if !stalledItems.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showBulkDismissConfirmation = true
                    } label: {
                        Label("Mark Stalled as Won't Do (\(stalledItems.count))", systemImage: "nosign")
                    }
                }
            }
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Sort and display options")
    }
}
