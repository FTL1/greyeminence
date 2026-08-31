import SwiftUI
import SwiftData

/// Keyword find across transcripts and Meeting Intelligence, in the main pane.
struct LibrarySearchView: View {
    var currentMeetingID: UUID?
    var selectedMeetingIDs: Set<UUID>
    var onOpenHit: (LibrarySearchHit) -> Void

    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @State private var query = ""
    @State private var useRegex = false
    @State private var meetingName = ""
    @State private var speaker = ""
    @State private var useFromDate = false
    @State private var useToDate = false
    @State private var fromDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var toDate = Date()
    @State private var scope: LibrarySearchScope
    @State private var includeTranscript = true
    @State private var includeIntelligence = true
    @State private var hits: [LibrarySearchHit] = []
    @State private var regexError: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    init(
        currentMeetingID: UUID?,
        selectedMeetingIDs: Set<UUID>,
        preferredScope: LibrarySearchScope = .thisMeeting,
        onOpenHit: @escaping (LibrarySearchHit) -> Void
    ) {
        self.currentMeetingID = currentMeetingID
        self.selectedMeetingIDs = selectedMeetingIDs
        self.onOpenHit = onOpenHit
        let start: LibrarySearchScope
        if preferredScope == .thisMeeting, currentMeetingID == nil, selectedMeetingIDs.isEmpty {
            start = .allMeetings
        } else {
            start = preferredScope
        }
        _scope = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
        }
        .onAppear {
            fieldFocused = true
            refresh()
        }
        .onChange(of: query) { _, _ in scheduleRefresh() }
        .onChange(of: useRegex) { _, _ in refresh() }
        .onChange(of: meetingName) { _, _ in scheduleRefresh() }
        .onChange(of: speaker) { _, _ in refresh() }
        .onChange(of: useFromDate) { _, _ in refresh() }
        .onChange(of: useToDate) { _, _ in refresh() }
        .onChange(of: fromDate) { _, _ in refresh() }
        .onChange(of: toDate) { _, _ in refresh() }
        .onChange(of: scope) { _, _ in refresh() }
        .onChange(of: includeTranscript) { _, _ in refresh() }
        .onChange(of: includeIntelligence) { _, _ in refresh() }
        .onDisappear { searchTask?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(useRegex ? "Regular expression" : "Find in transcripts and Meeting Intelligence", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit { refresh() }

                Toggle("Regex", isOn: $useRegex)
                    .toggleStyle(.checkbox)
                    .helpTip(.libraryFindRegex)

                if !query.isEmpty || !meetingName.isEmpty || !speaker.isEmpty || useFromDate || useToDate {
                    Button("Clear") {
                        query = ""
                        meetingName = ""
                        speaker = ""
                        useFromDate = false
                        useToDate = false
                        regexError = nil
                        hits = []
                    }
                    .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Picker("Scope", selection: $scope) {
                    ForEach(LibrarySearchScope.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Toggle("Transcript", isOn: $includeTranscript)
                    .toggleStyle(.checkbox)
                Toggle("Intelligence", isOn: $includeIntelligence)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 10, rowAlignment: .center) {
                HStack(spacing: 6) {
                    Text("Meeting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Name contains…", text: $meetingName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 140, maxWidth: 220)
                }

                HStack(spacing: 6) {
                    Text("Speaker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Me, Jordan…", text: $speaker)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 110, maxWidth: 160)
                    if !knownSpeakers.isEmpty {
                        Menu {
                            Button("Any speaker") { speaker = "" }
                            Divider()
                            ForEach(knownSpeakers, id: \.self) { name in
                                Button(name) { speaker = name }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Choose a speaker heard in this scope")
                    }
                }

                HStack(spacing: 6) {
                    Toggle("From", isOn: $useFromDate)
                        .toggleStyle(.checkbox)
                    DatePicker(
                        "From",
                        selection: $fromDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .disabled(!useFromDate)
                    .opacity(useFromDate ? 1 : 0.45)
                }

                HStack(spacing: 6) {
                    Toggle("To", isOn: $useToDate)
                        .toggleStyle(.checkbox)
                    DatePicker(
                        "To",
                        selection: $toDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .disabled(!useToDate)
                    .opacity(useToDate ? 1 : 0.45)
                }
            }

            if let regexError {
                Text(regexError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var results: some View {
        if !filter.hasCriteria && regexError == nil {
            ContentUnavailableView(
                "Find in your meetings",
                systemImage: "magnifyingglass",
                description: Text("This is the main Find pane. Filter by meeting name, date, speaker, and text (optional regex). Ask is the AI question box.")
            )
        } else if hits.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "text.magnifyingglass",
                description: Text(emptyReason)
            )
        } else {
            List {
                ForEach(groupedKeys, id: \.self) { meetingID in
                    let group = grouped[meetingID] ?? []
                    Section {
                        ForEach(group) { hit in
                            Button {
                                onOpenHit(hit)
                            } label: {
                                hitRow(hit)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.first.map { "\($0.meetingTitle)  ·  \($0.meetingDate.formatted(date: .abbreviated, time: .shortened))" } ?? "")
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func hitRow(_ hit: LibrarySearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(hit.kind.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                if let speaker = hit.speakerName, !speaker.isEmpty {
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if useRegex {
                Text(hit.snippet)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                Text(TranscriptTextHighlight.attributed(hit.snippet, query: query))
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var grouped: [UUID: [LibrarySearchHit]] {
        Dictionary(grouping: hits, by: \.meetingID)
    }

    private var groupedKeys: [UUID] {
        hits.reduce(into: [UUID]()) { result, hit in
            if !result.contains(hit.meetingID) {
                result.append(hit.meetingID)
            }
        }
    }

    private var sources: LibrarySearchSources {
        var value: LibrarySearchSources = []
        if includeTranscript { value.insert(.transcript) }
        if includeIntelligence { value.insert(.intelligence) }
        return value
    }

    private var filter: LibrarySearchFilter {
        LibrarySearchFilter(
            text: query,
            useRegex: useRegex,
            meetingName: meetingName,
            speaker: speaker,
            fromDate: useFromDate ? fromDate : nil,
            toDate: useToDate ? toDate : nil,
            sources: sources
        )
    }

    private var scopedMeetings: [Meeting] {
        switch scope {
        case .thisMeeting:
            if let currentMeetingID {
                return allMeetings.filter { $0.id == currentMeetingID }
            }
            return allMeetings.filter { selectedMeetingIDs.contains($0.id) }
        case .selectedMeetings:
            return allMeetings.filter { selectedMeetingIDs.contains($0.id) }
        case .allMeetings:
            return Array(allMeetings)
        }
    }

    private var knownSpeakers: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for meeting in scopedMeetings {
            for segment in meeting.segments {
                let name = segment.speaker.displayName
                let key = name.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                names.append(name)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var statusLine: String {
        let count = scopedMeetings.count
        let meetingWord = count == 1 ? "meeting" : "meetings"
        if hits.isEmpty {
            return "Searching \(count) \(meetingWord)."
        }
        return "\(hits.count) match\(hits.count == 1 ? "" : "es") in \(count) \(meetingWord)."
    }

    private var emptyReason: String {
        if let regexError { return regexError }
        if sources.isEmpty {
            return "Turn on Transcript, Intelligence, or both."
        }
        if scopedMeetings.isEmpty {
            switch scope {
            case .thisMeeting:
                return "Open a meeting, or switch scope to All meetings."
            case .selectedMeetings:
                return "Select meetings in the Meetings list first."
            case .allMeetings:
                return "There are no meetings in this library."
            }
        }
        return "Nothing matched these filters in this scope."
    }

    private func scheduleRefresh() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func refresh() {
        regexError = nil
        guard filter.hasCriteria else {
            hits = []
            return
        }
        switch LibrarySearch.search(filter: filter, in: scopedMeetings) {
        case .invalidRegex(let message):
            regexError = "Invalid regex: \(message)"
            hits = []
        case .hits(let found):
            hits = found
        }
    }
}
