import SwiftUI
import SwiftData
import AppKit

struct TranscriptPanelView: View {
    @Bindable var meeting: Meeting
    var onSplitMeeting: ((Meeting) -> Void)?
    @Binding var scrollToSegmentID: UUID?
    /// When set, segment timestamps become click targets that seek the
    /// screen-share player.
    var onSeekToTime: ((TimeInterval) -> Void)?

    init(meeting: Meeting, onSplitMeeting: ((Meeting) -> Void)? = nil, scrollToSegmentID: Binding<UUID?> = .constant(nil), onSeekToTime: ((TimeInterval) -> Void)? = nil) {
        self._meeting = Bindable(wrappedValue: meeting)
        self.onSplitMeeting = onSplitMeeting
        self._scrollToSegmentID = scrollToSegmentID
        self.onSeekToTime = onSeekToTime
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage("developerToolsEnabled") private var developerToolsEnabled = false
    @AppStorage("autoMergeSameSpeaker") private var autoMergeSameSpeaker = true
    @AppStorage("autoMergeMaxWindowSeconds") private var autoMergeMaxWindowSeconds = 15
    @AppStorage("autoMergePauseSeconds") private var autoMergePauseSeconds = 4.0
    @AppStorage("autoMergeSettingsVersion") private var autoMergeSettingsVersion = 0
    @Environment(MeetingFindController.self) private var meetingFind

    @State private var selectedSegmentIDs: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showBulkSpeakerPicker = false
    @State private var showBulkSpeakerRename = false
    @State private var bulkSpeakerName: String = ""
    @State private var splitConfirmationSegment: TranscriptSegment?
    @State private var isSplittingMeeting = false
    @State private var splitTask: Task<Void, Never>?
    @State private var highlightedSegmentID: UUID?

    @State private var searchSpeaker: Speaker?
    @State private var searchQuery = ""
    @State private var searchMatchIDs: [UUID] = []
    @State private var searchMatchIndex = 0
    @State private var menuSpeaker: Speaker?
    @State private var menuAnchorID: UUID?
    @State private var contactSpeaker: Speaker?
    @State private var sortedSegments: [TranscriptSegment] = []
    @State private var speakerRevision = 0
    @State private var talkShareByKey: [Speaker.IdentityKey: Int] = [:]
    @State private var isRecoveringSpeakers = false
    @State private var showDedupDebug = false
    @State private var editSaveError: String?
    @State private var speakerRoster = SpeakerRoster()
    @State private var speakerUndo = SpeakerLabelUndo()
    @State private var voicePrintProgress: VoicePrintEnrollmentProgress = .idle
    @State private var isExportingTranscript = false
    @State private var showFilteredAssignConfirmation = false
    @State private var pendingAssignSpeaker: Speaker?
    @State private var showReanalyzeSheet = false
    @State private var reanalyzeResult: MeetingSpeakerRecovery.Result?
    @State private var mergeUndo = TranscriptMergeUndo()
    @State private var autoMergedMeetingID: UUID?
    @State private var meetingFindMatchIDs: [UUID] = []
    @State private var meetingFindMatchIndex = 0

    @AppStorage("transcriptExportFormat") private var transcriptExportFormat = TranscriptExportFormat.txt.rawValue
    @Query(sort: \Contact.name) private var contacts: [Contact]

    private var editedCount: Int {
        // Allocation-free scan — read on every body evaluation, so avoid
        // building a throwaway filtered array of up to a few thousand segments.
        meeting.segments.reduce(into: 0) { count, segment in
            if segment.isEdited { count += 1 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SpeakerRosterBar(
                roster: speakerRoster,
                segments: sortedSegments,
                onAssignVoice: { voice, seat in
                    if let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(voice) }) {
                        changeSpeakerForAll(from: representative, to: seat.speaker)
                    }
                    speakerRoster.bind(detected: voice, to: seat.id)
                    speakerRoster.setLocked(seat.id, true)
                },
                onEnrollVoicePrint: { speaker in
                    enrollVoicePrint(for: speaker)
                }
            )
            .onAppear { seedFinishedRoster() }
            .onChange(of: meeting.id) { _, _ in seedFinishedRoster() }

            if meeting.status == .completed && !sortedSegments.isEmpty {
                transcriptToolbar
                Divider()
            }

            if !searchQuery.isEmpty || isSpeakerFilterActive {
                speakerFilterBanner
                Divider()
            }

            if let editSaveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(editSaveError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { self.editSaveError = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }

            if sortedSegments.isEmpty {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "text.bubble",
                    description: Text("This meeting has no transcript segments")
                )
            } else if displayItems.isEmpty {
                ContentUnavailableView(
                    "No matching lines",
                    systemImage: "text.magnifyingglass",
                    description: Text("Nothing in this transcript matches the current filter.")
                )
            } else {
                transcriptList
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { findAndMergeHooks }
        .onAppear {
            let migrated = SpeakerLegacyMigration.migrate(meeting.segments)
            let identified = SpeakerSelfIntroduction.apply(
                segments: meeting.segments,
                inviteeNames: meeting.attendees.map(\.name),
                myLabels: [SpeakerNames.effectiveMeName, Speaker.defaultMeLabel].compactMap { $0 }
            )
            if migrated > 0 || identified > 0 {
                saveEdit(site: "migrateGuestLabels")
                if migrated > 0 {
                    DevLog.ui("migrated \(migrated) line(s) to speaker-N labels")
                }
            }
            refreshSegments()
            considerAutoMerge()
        }
        .onChange(of: meeting.segments.count) { _, count in
            refreshSegments()
            if count > 0 { considerAutoMerge() }
        }
        .onChange(of: speakerRoster.isolatedSpeaker?.identityKey) {
            pruneSelectionToVisible()
        }
        .onChange(of: speakerRoster.hiddenSpeakers.map(\.identityKey)) {
            pruneSelectionToVisible()
            speakerRevision += 1
        }
        .overlay {
            if isSplittingMeeting {
                ZStack {
                    Color.black.opacity(0.25)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Splitting meeting and re-analyzing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            splitTask?.cancel()
                        }
                        .controlSize(.small)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let speaker = menuSpeaker {
                SpeakerActionPopover(
                    speaker: speaker,
                    actions: speakerActions(for: speaker),
                    onBeginInlineRename: {
                        menuSpeaker = nil
                    },
                    onClose: { menuSpeaker = nil }
                )
                .padding(12)
                .frame(width: 300, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(12)
            }
        }
        .confirmationDialog(
            "Delete \(selectedSegmentIDs.count) segment\(selectedSegmentIDs.count == 1 ? "" : "s")?",
            isPresented: $showBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedSegments()
            }
        } message: {
            Text("This cannot be undone.")
        }
        .popover(isPresented: Binding(
            get: { contactSpeaker != nil },
            set: { if !$0 { contactSpeaker = nil } }
        )) {
            ContactPicker(
                excludedContacts: [],
                prioritizedContacts: meeting.attendees,
                includeAppleDirectory: true
            ) { contact in
                if let speaker = contactSpeaker,
                   let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
                    if !contact.speakerAliases.contains(speaker.displayName) {
                        contact.speakerAliases.append(speaker.displayName)
                    }
                    changeSpeakerForAll(from: representative, to: .other(contact.name))
                    DevLog.ui("linked \(speaker.displayName) → contact \(contact.name)")
                }
                contactSpeaker = nil
            }
            .frame(width: 280, height: 320)
        }
        .popover(isPresented: $showBulkSpeakerPicker) {
            ContactPicker(excludedContacts: []) { contact in
                showBulkSpeakerPicker = false
                requestAssignVisible(to: .other(contact.name))
            }
        }
        .confirmationDialog(
            filteredAssignTitle,
            isPresented: $showFilteredAssignConfirmation,
            titleVisibility: .visible
        ) {
            Button("Assign visible lines only") {
                if let speaker = pendingAssignSpeaker {
                    reassignSelectedSegments(to: speaker)
                }
                pendingAssignSpeaker = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAssignSpeaker = nil
            }
        } message: {
            Text("Hidden speakers stay as they are. Use Undo speaker change if this is still wrong.")
        }
        .sheet(isPresented: $showReanalyzeSheet, onDismiss: {
            reanalyzeResult = nil
        }) {
            SpeakerReanalyzeSheet(
                meeting: meeting,
                contacts: Array(contacts),
                isWorking: isRecoveringSpeakers,
                result: reanalyzeResult,
                onRun: { expected in
                    recoverSpeakersFromAudio(expected: expected)
                },
                onAssign: { unknowns, target, contact in
                    assignUnknowns(unknowns, to: target, contact: contact)
                },
                onDismiss: {
                    showReanalyzeSheet = false
                }
            )
        }
        .popover(isPresented: $showBulkSpeakerRename) {
            VStack(spacing: 8) {
                Text("Rename Speaker")
                    .font(.headline)
                TextField("Speaker name", text: $bulkSpeakerName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyBulkSpeakerRename()
                    }
                HStack {
                    Button("Cancel") { showBulkSpeakerRename = false }
                    Spacer()
                    Button("Apply") {
                        applyBulkSpeakerRename()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .frame(width: 280)
        }
        .confirmationDialog(
            splitConfirmationTitle,
            isPresented: Binding(
                get: { splitConfirmationSegment != nil },
                set: { if !$0 { splitConfirmationSegment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Split Into New Meeting") {
                if let segment = splitConfirmationSegment {
                    splitConfirmationSegment = nil
                    splitTask = Task { await splitMeeting(from: segment) }
                }
            }
            Button("Cancel", role: .cancel) {
                splitConfirmationSegment = nil
            }
        } message: {
            Text("This segment and everything after it will be moved into a new meeting. Both meetings will be re-analyzed by AI.")
        }
    }

    /// Kept off `body` so the compiler can type-check the chrome separately.
    private var findAndMergeHooks: some View {
        Color.clear
            .onChange(of: meeting.id) { _, _ in
                mergeUndo.clear()
                autoMergedMeetingID = nil
                meetingFindMatchIDs = []
                meetingFindMatchIndex = 0
                refreshSegments()
                considerAutoMerge()
            }
            .onChange(of: meetingFind.query) { _, _ in
                refreshMeetingFindMatches(jumpToFirst: true)
            }
            .onChange(of: meetingFind.includeTranscript) { _, _ in
                refreshMeetingFindMatches(jumpToFirst: true)
            }
            .onChange(of: meetingFind.transcriptStepNonce) { _, _ in
                stepMeetingFind(by: meetingFind.transcriptStepDelta)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private var splitConfirmationTitle: String {
        guard let seg = splitConfirmationSegment else { return "Split Into New Meeting" }
        let preview = String(seg.text.prefix(60))
        return "Split from \"\(preview)\(seg.text.count > 60 ? "…" : "")\"?"
    }

    // MARK: - Transcript Toolbar

    /// Resting vs selection are different modes. Rare tools (undo, revert, DEV)
    /// live in ⋯ so a narrow inspector does not clip labeled buttons.
    private var transcriptToolbar: some View {
        VStack(spacing: 0) {
            if isSelectionMode {
                selectionBar
            } else {
                restingBar
            }
        }
        .background(.bar)
    }

    private var restingBar: some View {
        ViewThatFits(in: .horizontal) {
            restingBarContents(iconOnly: false)
            restingBarContents(iconOnly: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func restingBarContents(iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isSelectionMode = true
            } label: {
                if iconOnly {
                    Image(systemName: "checklist")
                } else {
                    Label("Select", systemImage: "checklist")
                }
            }
            .controlSize(.small)
            .help("Select lines to merge, assign, or delete")

            exportTranscriptMenu

            if meeting.segments.contains(where: { !$0.speaker.isMe }) {
                Button {
                    reanalyzeResult = nil
                    showReanalyzeSheet = true
                } label: {
                    if isRecoveringSpeakers {
                        ProgressView()
                            .controlSize(.small)
                    } else if iconOnly {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    } else {
                        Label("Re-analyze speakers", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
                .controlSize(.small)
                .disabled(isRecoveringSpeakers)
                .help("Pick who was on the call, match saved voice stamps, and label leftovers as speaker-1…. You stay you.")
            }

            Spacer(minLength: 8)

            overflowMenu
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var overflowMenu: some View {
        Menu {
            if speakerUndo.canUndo {
                Button {
                    undoLastSpeakerChange()
                } label: {
                    Label("Undo speaker change", systemImage: "arrow.uturn.backward")
                }
            }
            if mergeUndo.canUndo {
                Button {
                    undoAutoMerge()
                } label: {
                    Label("Undo auto-merge", systemImage: "arrow.uturn.backward.circle")
                }
            }
            Button {
                applyAutoMerge(userInitiated: true)
            } label: {
                Label("Merge consecutive lines", systemImage: "arrow.triangle.merge")
            }

            if meeting.segments.contains(where: { $0.originalSpeakerData != nil }) {
                Button("Revert speaker labels") {
                    revertSpeakerLabels()
                }
            }
            if editedCount > 0 {
                Button("Revert all text edits") {
                    revertAllEdits()
                }
            }

            if developerToolsEnabled {
                Divider()
                Toggle("Dedup debug", isOn: $showDedupDebug)
                Button("Remove duplicates") {
                    deduplicateTranscript()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("More transcript tools")
        .accessibilityLabel("More transcript tools")
    }

    @ViewBuilder
    private var exportTranscriptMenu: some View {
        let format = TranscriptExportFormat(rawValue: transcriptExportFormat) ?? .txt
        if isExportingTranscript {
            ProgressView()
                .controlSize(.small)
        } else {
            Menu {
                Picker("Format", selection: $transcriptExportFormat) {
                    ForEach(TranscriptExportFormat.allCases) { item in
                        Text(item.menuTitle).tag(item.rawValue)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Copy Full Transcript") {
                    let text = TranscriptExportService.clipboardText(for: meeting)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    TransientActivityCoordinator.shared.flash("Full transcript copied")
                }
            } label: {
                Label("Transcript", systemImage: "doc.plaintext")
                    .font(.caption)
            } primaryAction: {
                isExportingTranscript = true
                Task { @MainActor in
                    defer { isExportingTranscript = false }
                    _ = await TranscriptExportService.presentSavePanel(for: meeting, format: format)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .disabled(sortedSegments.isEmpty)
            .help("Click: export the full transcript as \(format.menuTitle). Arrow: choose a format or copy.")
        }
    }

    /// Selection takes over the bar rather than adding to it, so every control
    /// present acts on the selection. Actions that need a selection appear
    /// only once there is one — the bar grows with intent instead of showing
    /// dead buttons. It flows to a second row in a narrow panel, which reads
    /// as deliberate because everything wrapping belongs to one task.
    private var selectionBar: some View {
        // Centred because this row mixes a caption with bordered controls.
        FlowLayout(spacing: 8, rowAlignment: .center) {
            Button {
                isSelectionMode = false
                selectedSegmentIDs.removeAll()
            } label: {
                Label("Done", systemImage: "checkmark.circle")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)

            Button(allVisibleSelected ? "Select None" : "Select Visible") {
                if allVisibleSelected {
                    selectedSegmentIDs.removeAll()
                } else {
                    selectedSegmentIDs = Set(visibleSegments.map(\.id))
                }
            }
            .controlSize(.small)
            .help("Selects only the lines you can see. Hidden or isolated-out speakers stay out.")

            if selectedSegmentIDs.isEmpty {
                Text("Choose segments to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(selectedSegmentIDs.count) selected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Menu {
                    Button("Choose Contact…") {
                        showBulkSpeakerPicker = true
                    }
                    Button("Type Name…") {
                        bulkSpeakerName = ""
                        showBulkSpeakerRename = true
                    }
                    Divider()
                    Button("Set as Me") {
                        requestAssignVisible(to: Speaker.resolvedMe())
                    }
                } label: {
                    Label("Assign Speaker", systemImage: "person")
                }
                .controlSize(.small)

                Button("Merge") {
                    mergeSelectedSegments()
                }
                .controlSize(.small)
                .disabled(selectedSegmentIDs.count < 2)
                .help("Join the selected lines into one.")

                Button(role: .destructive) {
                    showBulkDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .lineLimit(1)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.10))
    }

    private var displayItems: [TranscriptDisplayItem] {
        // Search highlights and jumps; it must not filter the list or the
        // speaker menu's presenting row disappears after one character.
        TranscriptDisplay.items(
            from: sortedSegments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            searchSpeaker: nil,
            searchQuery: "",
            isolatedSpeakers: mixerIsolatedSpeakers
        )
    }

    private var speakerFilterBanner: some View {
        FlowLayout(spacing: 8, rowAlignment: .center) {
            if let isolated = speakerRoster.isolatedSpeaker {
                Label("Only \(isolated.displayName)", systemImage: "person.crop.rectangle")
                    .font(.caption)
            }
            if !speakerRoster.hiddenSpeakers.isEmpty {
                ForEach(speakerRoster.hiddenSpeakers, id: \.identityKey) { speaker in
                    Button {
                        toggleHidden(speaker)
                    } label: {
                        Label("Show \(speaker.displayName)", systemImage: "eye.slash")
                    }
                    .controlSize(.small)
                    .help("\(speaker.displayName) is hidden. Click to show them.")
                }
            }
            if let searchSpeaker, !searchQuery.isEmpty {
                Text("“\(searchQuery)” in \(searchSpeaker.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Assign changes these \(visibleSegments.count) visible line\(visibleSegments.count == 1 ? "" : "s") only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !visibleSegments.isEmpty {
                Menu {
                    Button("Choose Contact…") {
                        selectedSegmentIDs = Set(visibleSegments.map(\.id))
                        isSelectionMode = true
                        showBulkSpeakerPicker = true
                    }
                    Button("Type Name…") {
                        selectedSegmentIDs = Set(visibleSegments.map(\.id))
                        isSelectionMode = true
                        bulkSpeakerName = ""
                        showBulkSpeakerRename = true
                    }
                } label: {
                    Text("Assign these \(visibleSegments.count)")
                }
                .controlSize(.small)
                .help("Rename only the lines on screen. Hidden speakers are not included.")
            }
            Button("Show all") {
                speakerRoster.showAllSpeakers()
                searchSpeaker = nil
                searchQuery = ""
                searchMatchIDs = []
                searchMatchIndex = 0
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var mixerHiddenSpeakers: [Speaker] {
        speakerRoster.hiddenIdentities(in: sortedSegments)
    }

    private var mixerIsolatedSpeakers: [Speaker]? {
        speakerRoster.isolatedIdentities(in: sortedSegments)
    }

    private var visibleSegments: [TranscriptSegment] {
        SpeakerRelabel.visibleSegments(
            from: sortedSegments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            isolatedSpeakers: mixerIsolatedSpeakers
        )
    }

    private var allVisibleSelected: Bool {
        !visibleSegments.isEmpty && selectedSegmentIDs == Set(visibleSegments.map(\.id))
    }

    // MARK: - Transcript List

    private var transcriptList: some View {
        let systemSegments = showDedupDebug ? sortedSegments.filter { !$0.speaker.isMe } : []
        let mixerToken = "\(speakerRoster.mixerGeneration)-\(speakerRevision)"
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(displayItems, id: \.id) { item in
                        mixerRow(item, systemSegments: systemSegments)
                            .id(item.id)
                    }
                }
                .padding()
                .id(mixerToken)
            }
            .onChange(of: scrollToSegmentID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(TranscriptDisplayItem.scrollID(for: newID), anchor: .center)
                }
                highlightedSegmentID = newID
                scrollToSegmentID = nil
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if highlightedSegmentID == newID {
                        withAnimation { highlightedSegmentID = nil }
                    }
                }
            }
        }
    }

    private func collapsedStub(speaker: Speaker, hiddenCount: Int) -> CollapsedSpeakerRow {
        var actions = speakerActions(for: speaker)
        actions.onToggleHidden = {
            speakerRoster.reveal(speaker, in: sortedSegments)
        }
        return CollapsedSpeakerRow(
            speaker: speaker,
            hiddenCount: hiddenCount,
            actions: actions
        )
    }

    @ViewBuilder
    private func mixerRow(_ item: TranscriptDisplayItem, systemSegments: [TranscriptSegment]) -> some View {
        switch item {
        case .segment(let segment):
            transcriptRow(segment, systemSegments: systemSegments)
                .padding(.vertical, 2)
                .background(
                    highlightedSegmentID == segment.id
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let seat = speakerRoster.paintSeat else { return }
                    speakerUndo.capture(meeting.segments)
                    segment.speaker = seat.speaker
                    speakerRoster.bind(detected: seat.speaker, to: seat.id)
                    saveEdit(site: "roster-paint")
                }
        case .collapsed(let speaker, let count):
            collapsedStub(speaker: speaker, hiddenCount: count)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func transcriptRow(_ segment: TranscriptSegment, systemSegments: [TranscriptSegment]) -> some View {
        if TranscriptDisplay.isHidden(segment.speaker, hiddenSpeakers: mixerHiddenSpeakers) {
            collapsedStub(speaker: segment.speaker, hiddenCount: 1)
        } else {
            transcriptPlayableRow(segment, systemSegments: systemSegments)
        }
    }

    @ViewBuilder
    private func transcriptPlayableRow(_ segment: TranscriptSegment, systemSegments: [TranscriptSegment]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if meeting.status == .completed {
                EditableTranscriptSegmentRow(
                    segment: segment,
                    hasNext: sortedSegments.last?.id != segment.id,
                    isSelected: selectedSegmentIDs.contains(segment.id),
                    onDelete: { deleteSegment(segment) },
                    onMergeWithNext: { mergeSegmentWithNext(segment) },
                    onSplit: { before, after in splitSegment(segment, before: before, after: after) },
                    onSplitMeeting: {
                        if canSplitMeeting(at: segment) {
                            splitConfirmationSegment = segment
                        }
                    },
                    onChangeSpeakerForAll: { newSpeaker in
                        changeSpeakerForAll(from: segment, to: newSpeaker)
                    },
                    onToggleSelection: isSelectionMode ? {
                        toggleSelection(segment)
                    } : nil,
                    onSeekToTime: onSeekToTime,
                    onPlayLine: {
                        let nextStart = sortedSegments.drop(while: { $0.id != segment.id }).dropFirst().first?.startTime
                        SegmentAudioPlayer.shared.toggle(segment: segment, meeting: meeting, nextStart: nextStart)
                        speakerRevision += 1
                    },
                    isPlayingLine: SegmentAudioPlayer.shared.playingSegmentID == segment.id,
                    speakerActions: speakerActions(for: segment.speaker, anchorID: segment.id),
                    highlightQuery: highlightQuery(for: segment)
                )
            } else {
                TranscriptSegmentRow(
                    segment: segment,
                    speakerActions: speakerActions(for: segment.speaker, anchorID: segment.id),
                    highlightQuery: highlightQuery(for: segment)
                )
            }
            if showDedupDebug && segment.speaker.isMe {
                DedupDebugRow(mic: segment, systemSegments: systemSegments)
            }
        }
    }

    private func speakerLinkGroups(for speaker: Speaker) -> SpeakerLinkGroups {
        let people = contacts.filter { !$0.isArchived }.map { $0.asSpeakerLinkPerson() }
        let names = sortedSegments.reduce(into: [String]()) { result, segment in
            let name = segment.speaker.displayName
            if !result.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                result.append(name)
            }
        }
        return SpeakerLinkCatalog.groups(
            people: people,
            transcriptNames: names,
            attendeeNames: meeting.attendees.map(\.name),
            meName: SpeakerNames.effectiveMeName,
            currentSpeakerName: speaker.displayName
        )
    }

    private func applySpeakerLink(_ person: SpeakerLinkPerson, to speaker: Speaker) {
        if let contactID = person.contactID,
           let contact = contacts.first(where: { $0.id == contactID }) {
            if !contact.speakerAliases.contains(where: { $0.compare(speaker.displayName, options: .caseInsensitive) == .orderedSame }) {
                contact.speakerAliases.append(speaker.displayName)
            }
            if !meeting.attendees.contains(where: { $0.id == contact.id }) {
                meeting.attendees.append(contact)
            }
            if !speaker.isMe,
               let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
                changeSpeakerForAll(from: representative, to: .other(contact.name))
            }
            if !speaker.isMe { menuSpeaker = .other(contact.name) }
            return
        }
        if let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
            changeSpeakerForAll(from: representative, to: Speaker.renamed(from: speaker, displayName: person.name))
        }
        if !speaker.isMe { menuSpeaker = .other(person.name) }
    }

    private func voicePrintState(for speaker: Speaker) -> VoicePrintUIState {
        if case .working(let key) = voicePrintProgress, key == speaker.identityKey {
            return .working
        }
        if case .failed(let key, let message) = voicePrintProgress, key == speaker.identityKey {
            return .failed(message)
        }
        let contact = VoicePrintEnrollment.resolveContact(for: speaker, contacts: Array(contacts), mapped: nil)
        if let contact, contact.hasVoicePrint {
            return .enrolled(onto: contact.name, at: contact.voicePrintUpdatedAt)
        }
        if let contact {
            return .ready(onto: contact.name)
        }
        if speaker.isGuestPlaceholder {
            return .needsPerson
        }
        return .ready(onto: speaker.displayName)
    }

    private func enrollVoicePrint(for speaker: Speaker) {
        voicePrintProgress = .working(speaker.identityKey)
        Task {
            var contact = VoicePrintEnrollment.resolveContact(for: speaker, contacts: Array(contacts), mapped: nil)
            if contact == nil, !speaker.isGuestPlaceholder, !speaker.displayNameIsPlaceholder {
                let created = Contact(name: speaker.displayName)
                modelContext.insert(created)
                contact = created
            }
            guard let contact else {
                voicePrintProgress = .failed(
                    speaker.identityKey,
                    VoicePrintEnrollment.EnrollmentError.needsPerson.localizedDescription
                )
                return
            }
            do {
                guard let request = VoicePrintEnrollment.request(
                    for: speaker,
                    in: meeting,
                    segments: sortedSegments
                ) else {
                    throw VoicePrintEnrollment.EnrollmentError.notEnoughAudio
                }
                let embedding = try await VoicePrintEnrollment.extractEmbedding(request)
                contact.mergeVoicePrint(embedding)
                if !contact.speakerAliases.contains(where: { $0.compare(speaker.displayName, options: .caseInsensitive) == .orderedSame }) {
                    contact.speakerAliases.append(speaker.displayName)
                }
                if !meeting.attendees.contains(where: { $0.id == contact.id }) {
                    meeting.attendees.append(contact)
                }
                PersistenceGate.save(modelContext, site: "enrollVoicePrint", critical: false, meetingID: meeting.id)
                if !speaker.isMe,
                   speaker.displayName.compare(contact.name, options: .caseInsensitive) != .orderedSame,
                   let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
                    changeSpeakerForAll(from: representative, to: .other(contact.name))
                }
                voicePrintProgress = .idle
            } catch {
                voicePrintProgress = .failed(speaker.identityKey, error.localizedDescription)
            }
        }
    }

    private func seedFinishedRoster() {
        speakerRoster.showAllSpeakers()
        SpeakerPalette.assign(contacts: Array(contacts))
        let myID = Meeting.storedMyContactID
        speakerRoster.seed(
            attendeeNames: meeting.attendees.filter { $0.id != myID }.map(\.name),
            meName: SpeakerNames.effectiveMeName
        )
        if let myID, let index = speakerRoster.seats.firstIndex(where: \.isMe) {
            speakerRoster.seats[index].contactID = myID
        }
        for attendee in meeting.attendees where attendee.id != myID {
            if let index = speakerRoster.seats.firstIndex(where: {
                SpeakerNameMatcher.samePerson($0.name, attendee.name)
                    || $0.name.compare(attendee.name, options: .caseInsensitive) == .orderedSame
            }), speakerRoster.seats[index].contactID == nil {
                speakerRoster.seats[index].contactID = attendee.id
            }
        }
        speakerRoster.bindNamedVoices(in: meeting.segments, contactNames: contactNameMap())
        speakerRoster.collapseSamePersonSeats()
        if speakerRoster.unifyOntoSeats(in: meeting.segments) > 0 {
            saveEdit(site: "unifySpeakerSeats")
        }
    }

    private func refreshSegments() {
        sortedSegments = meeting.segments.sorted { $0.startTime < $1.startTime }
        talkShareByKey = SpeakerTalkShare.percents(in: sortedSegments)
        speakerRevision += 1
    }

    private func retargetSpeaker(from old: Speaker, to new: Speaker, mergeIntoExisting: Bool) {
        if menuSpeaker?.matchesIdentity(old) == true { menuSpeaker = new }
        if speakerRoster.isolatedSpeaker?.matchesIdentity(old) == true {
            speakerRoster.isolatedSpeaker = new
        }
        if searchSpeaker?.matchesIdentity(old) == true { searchSpeaker = new }
        if mergeIntoExisting {
            // guest-1 → Jordan: do not hide every Jordan line just because
            // the leftover guest chip was off.
            speakerRoster.hiddenSpeakers.removeAll { $0.matchesIdentity(old) }
        } else {
            speakerRoster.hiddenSpeakers = speakerRoster.hiddenSpeakers.map { $0.matchesIdentity(old) ? new : $0 }
        }
    }

    private func toggleHidden(_ speaker: Speaker) {
        DevLog.ui("toggle-hide \(speaker.displayName)")
        withAnimation(.easeInOut(duration: 0.2)) {
            if let seat = speakerRoster.seat(matching: speaker)
                ?? speakerRoster.seats.first(where: { SpeakerNameMatcher.samePerson($0.name, speaker.displayName) }) {
                speakerRoster.toggleHidden(seat: seat, in: sortedSegments)
            } else {
                speakerRoster.toggleHidden(speaker)
            }
        }
    }

    private func highlightQuery(for segment: TranscriptSegment) -> String {
        let meetingQuery = meetingFind.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if meetingFind.includeTranscript, !meetingQuery.isEmpty {
            return meetingQuery
        }
        guard let searchSpeaker, searchSpeaker.matchesIdentity(segment.speaker) else { return "" }
        return searchQuery
    }

    private func refreshMeetingFindMatches(jumpToFirst: Bool) {
        let needle = meetingFind.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meetingFind.includeTranscript, !needle.isEmpty else {
            meetingFindMatchIDs = []
            meetingFindMatchIndex = 0
            return
        }
        meetingFindMatchIDs = sortedSegments.compactMap { segment in
            segment.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil
                ? nil
                : segment.id
        }
        if jumpToFirst, let first = meetingFindMatchIDs.first {
            meetingFindMatchIndex = 0
            scrollToSegmentID = first
        } else if meetingFindMatchIndex >= meetingFindMatchIDs.count {
            meetingFindMatchIndex = 0
        }
    }

    private func stepMeetingFind(by delta: Int) {
        refreshMeetingFindMatches(jumpToFirst: false)
        guard !meetingFindMatchIDs.isEmpty else { return }
        let count = meetingFindMatchIDs.count
        meetingFindMatchIndex = (meetingFindMatchIndex + delta % count + count) % count
        scrollToSegmentID = meetingFindMatchIDs[meetingFindMatchIndex]
    }

    private func migrateAutoMergeSettingsIfNeeded() {
        guard autoMergeSettingsVersion < 1 else { return }
        if autoMergePauseSeconds <= 2.0 { autoMergePauseSeconds = 4.0 }
        if autoMergeMaxWindowSeconds <= 10 { autoMergeMaxWindowSeconds = 15 }
        autoMergeSettingsVersion = 1
    }

    private func considerAutoMerge() {
        migrateAutoMergeSettingsIfNeeded()
        guard autoMergeSameSpeaker else { return }
        guard meeting.status == .completed else { return }
        let source = meeting.segments
        guard !source.isEmpty else { return }
        guard autoMergedMeetingID != meeting.id else { return }
        autoMergedMeetingID = meeting.id
        applyAutoMerge(userInitiated: false)
    }

    private func applyAutoMerge(userInitiated: Bool) {
        let source = meeting.segments.isEmpty ? sortedSegments : Array(meeting.segments)
        let groups = TranscriptAutoMerge.groups(
            in: source,
            maxWindow: TimeInterval(autoMergeMaxWindowSeconds),
            pause: autoMergePauseSeconds
        )
        let mergeable = groups.filter { $0.count >= 2 }
        guard !mergeable.isEmpty else {
            if userInitiated {
                TransientActivityCoordinator.shared.flash("Nothing to merge.")
            }
            return
        }

        var keepers: [TranscriptMergeUndoEntry.KeeperRestore] = []
        var deleted: [TranscriptMergeUndoEntry.Deleted] = []
        var retargets: [(itemID: UUID, oldSource: UUID?)] = []

        for group in mergeable {
            let keeper = group[0]
            keepers.append(
                TranscriptMergeUndoEntry.KeeperRestore(
                    id: keeper.id,
                    text: keeper.text,
                    endTime: keeper.endTime,
                    isEdited: keeper.isEdited,
                    originalText: keeper.originalText,
                    originalSpeakerData: keeper.originalSpeakerData
                )
            )
            if !keeper.isEdited {
                keeper.originalText = keeper.text
                keeper.originalSpeakerData = keeper.speakerData
            }
            keeper.text = TranscriptAutoMerge.joinTexts(group.map(\.text))
            let groupIDs = Set(group.map(\.id))
            let ordered = source.sorted { $0.startTime < $1.startTime }
            let lastIndex = ordered.lastIndex(where: { groupIDs.contains($0.id) })
            let followingStart = lastIndex.flatMap { idx -> TimeInterval? in
                let next = idx + 1
                return next < ordered.count ? ordered[next].startTime : nil
            }
            keeper.endTime = TranscriptAutoMerge.coveredEnd(of: group, followingStart: followingStart)
            keeper.isEdited = true

            for extra in group.dropFirst() {
                deleted.append(.snapshot(extra))
                for item in meeting.actionItems where item.sourceSegmentID == extra.id {
                    retargets.append((item.id, item.sourceSegmentID))
                    item.sourceSegmentID = keeper.id
                }
                meeting.segments.removeAll { $0.id == extra.id }
                modelContext.delete(extra)
                selectedSegmentIDs.remove(extra.id)
            }
        }

        mergeUndo.push(
            TranscriptMergeUndoEntry(
                keepers: keepers,
                deleted: deleted,
                retargetedActionItems: retargets
            )
        )
        refreshSegments()
        saveEdit(site: "autoMergeSameSpeaker")
        TransientActivityCoordinator.shared.flash(
            "Merged \(deleted.count) fragment\(deleted.count == 1 ? "" : "s") into longer lines."
        )
    }

    private func undoAutoMerge() {
        guard let entry = mergeUndo.pop() else { return }
        for keeper in entry.keepers {
            guard let segment = meeting.segments.first(where: { $0.id == keeper.id }) else { continue }
            segment.text = keeper.text
            segment.endTime = keeper.endTime
            segment.isEdited = keeper.isEdited
            segment.originalText = keeper.originalText
            segment.originalSpeakerData = keeper.originalSpeakerData
        }
        for shot in entry.deleted {
            let segment = shot.makeSegment()
            segment.meeting = meeting
            meeting.segments.append(segment)
            modelContext.insert(segment)
        }
        for pair in entry.retargetedActionItems {
            meeting.actionItems.first(where: { $0.id == pair.itemID })?.sourceSegmentID = pair.oldSource
        }
        refreshSegments()
        saveEdit(site: "undoAutoMerge")
        TransientActivityCoordinator.shared.flash("Undid auto-merge.")
    }

    private func applySpeakerSearch(speaker: Speaker, query: String) {
        searchSpeaker = speaker
        searchQuery = query
        let matches = SpeakerSearch.matchingSegments(query: query, speaker: speaker, in: sortedSegments)
        searchMatchIDs = matches.map(\.id)
        guard !matches.isEmpty else {
            searchMatchIndex = 0
            return
        }
        let anchorTime = sortedSegments.first(where: { $0.id == menuAnchorID })?.startTime ?? 0
        searchMatchIndex = SpeakerSearch.nearestMatchIndex(in: matches, after: anchorTime)
        let target = matches[searchMatchIndex].id
        if highlightedSegmentID != target {
            scrollToSegmentID = target
        }
    }

    private func jumpSpeakerSearch(by delta: Int) {
        guard !searchMatchIDs.isEmpty else { return }
        let count = searchMatchIDs.count
        searchMatchIndex = (searchMatchIndex + delta % count + count) % count
        scrollToSegmentID = searchMatchIDs[searchMatchIndex]
    }

    private func speakerActions(for speaker: Speaker, anchorID: UUID? = nil) -> SpeakerBadgeActions {
        let isMenuSpeaker = menuSpeaker?.matchesIdentity(speaker) == true
        return SpeakerBadgeActions(
            talkSharePercent: talkShareByKey[speaker.identityKey],
            color: SpeakerPalette.color(for: speaker, contacts: Array(contacts)),
            colorSlot: SpeakerPalette.contact(for: speaker, in: Array(contacts))?.colorSlot,
            isColorLocked: SpeakerPalette.contact(for: speaker, in: Array(contacts))?.isColorLocked ?? false,
            onPickColor: { slot, locked in
                applySpeakerColor(slot, locked: locked, to: speaker)
            },
            isHidden: TranscriptDisplay.isHidden(speaker, hiddenSpeakers: mixerHiddenSpeakers),
            onToggleHidden: { toggleHidden(speaker) },
            onRename: { name, saveAsDefault in
                DevLog.ui("rename \(speaker.displayName) → \(name)", detail: "saveAsDefault=\(saveAsDefault)")
                if speaker.isMe {
                    SpeakerNames.setSessionMeName(name, saveAsDefault: saveAsDefault)
                }
                let newSpeaker = Speaker.renamed(from: speaker, displayName: name)
                applyRenameFromMenu(current: speaker, to: newSpeaker, anchorID: anchorID)
            },
            onSearch: { query in
                applySpeakerSearch(speaker: speaker, query: query)
            },
            searchQuery: searchSpeaker?.matchesIdentity(speaker) == true ? searchQuery : "",
            onOpenMenu: {
                DevLog.ui("open-speaker-menu \(speaker.displayName)")
                menuSpeaker = speaker
                menuAnchorID = anchorID
                    ?? sortedSegments.first(where: { $0.speaker.matchesIdentity(speaker) })?.id
            },
            searchMatchCount: isMenuSpeaker ? searchMatchIDs.count : 0,
            searchMatchIndex: isMenuSpeaker ? searchMatchIndex : 0,
            onJumpToMatch: { delta in
                jumpSpeakerSearch(by: delta)
            },
            onAddToContacts: {
                DevLog.ui("link-contact picker for \(speaker.displayName)")
                contactSpeaker = speaker
            },
            onSaveAsNewContact: speaker.displayNameIsPlaceholder ? nil : {
                let contact = Contact(name: speaker.displayName)
                contact.speakerAliases.append(speaker.displayName)
                modelContext.insert(contact)
                PersistenceGate.save(modelContext, site: "saveAsNewContact", critical: false, meetingID: meeting.id)
                if let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
                    changeSpeakerForAll(from: representative, to: .other(contact.name))
                }
                DevLog.ui("save-as-new-contact \(contact.name)")
            },
            speakerLinks: speakerLinkGroups(for: speaker),
            onSelectSpeakerLink: { person in
                applySpeakerLink(person, to: speaker)
            },
            onEnrollVoicePrint: {
                enrollVoicePrint(for: speaker)
            },
            voicePrintState: voicePrintState(for: speaker),
            onRecoverSpeakers: MeetingSpeakerRecovery.hasCollapsedRemotes(in: sortedSegments)
                ? {
                    reanalyzeResult = nil
                    showReanalyzeSheet = true
                }
                : nil,
            isRecoveringSpeakers: isRecoveringSpeakers,
            onSetAsMe: speaker.isMe ? nil : {
                if let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(speaker) }) {
                    changeSpeakerForAll(from: representative, to: Speaker.resolvedMe())
                }
            }
        )
    }

    // MARK: - Segment Operations

    private func deleteSegment(_ segment: TranscriptSegment) {
        meeting.segments.removeAll { $0.id == segment.id }
        modelContext.delete(segment)
        selectedSegmentIDs.remove(segment.id)
        saveEdit(site: "deleteSegment")
    }

    private func deleteSelectedSegments() {
        let toDelete = meeting.segments.filter { selectedSegmentIDs.contains($0.id) }
        for segment in toDelete {
            meeting.segments.removeAll { $0.id == segment.id }
            modelContext.delete(segment)
        }
        selectedSegmentIDs.removeAll()
        saveEdit(site: "deleteSelectedSegments")
    }

    private func applyRenameFromMenu(current: Speaker, to newSpeaker: Speaker, anchorID: UUID?) {
        if !selectedSegmentIDs.isEmpty {
            requestAssignVisible(to: newSpeaker)
            return
        }
        let targetID = menuAnchorID ?? anchorID
        if let targetID, let segment = meeting.segments.first(where: { $0.id == targetID }) {
            selectedSegmentIDs = [segment.id]
            reassignSelectedSegments(to: newSpeaker)
            selectedSegmentIDs = []
            return
        }
        if let representative = meeting.segments.first(where: { $0.speaker.matchesIdentity(current) }) {
            changeSpeakerForAll(from: representative, to: newSpeaker)
        }
    }

    private func applySpeakerColor(_ slot: Int, locked: Bool, to speaker: Speaker) {
        var contact = SpeakerPalette.contact(for: speaker, in: Array(contacts))
        if contact == nil {
            let created = Contact(name: speaker.displayName)
            if !speaker.isGuestPlaceholder {
                created.speakerAliases.append(speaker.displayName)
            }
            modelContext.insert(created)
            if !meeting.attendees.contains(where: { $0.id == created.id }) {
                meeting.attendees.append(created)
            }
            contact = created
        }
        guard let contact else { return }
        contact.colorSlot = slot
        contact.isColorLocked = locked
        SpeakerPalette.assign(contacts: Array(contacts) + [contact])
        PersistenceGate.save(modelContext, site: "speakerColor", critical: false, meetingID: meeting.id)
        speakerRevision += 1
    }

    private func mergeSelectedSegments() {
        let selected = sortedSegments.filter { selectedSegmentIDs.contains($0.id) }
        guard selected.count >= 2 else { return }
        speakerUndo.capture(meeting.segments)
        let keeper = selected[0]
        if !keeper.isEdited {
            keeper.originalText = keeper.text
            keeper.originalSpeakerData = keeper.speakerData
        }
        let joined = TranscriptAutoMerge.joinTexts(selected.map(\.text))
        let selectedIDs = Set(selected.map(\.id))
        let followingStart = sortedSegments.first { segment in
            !selectedIDs.contains(segment.id) && segment.startTime >= selected.last!.startTime
        }?.startTime
        let end = TranscriptAutoMerge.coveredEnd(of: selected, followingStart: followingStart)
        for extra in selected.dropFirst() {
            meeting.segments.removeAll { $0.id == extra.id }
            modelContext.delete(extra)
            selectedSegmentIDs.remove(extra.id)
        }
        keeper.text = joined
        keeper.endTime = end
        keeper.isEdited = true
        refreshSegments()
        saveEdit(site: "mergeSelectedSegments")
        TransientActivityCoordinator.shared.flash("Merged \(selected.count) lines.")
    }

    private func mergeSegmentWithNext(_ segment: TranscriptSegment) {
        let sorted = sortedSegments
        guard let idx = sorted.firstIndex(where: { $0.id == segment.id }),
              idx + 1 < sorted.count else { return }

        let next = sorted[idx + 1]

        if !segment.isEdited {
            segment.originalText = segment.text
            segment.originalSpeakerData = segment.speakerData
        }

        segment.text = TranscriptAutoMerge.joinTexts([segment.text, next.text])
        let followingStart = sorted.drop(while: { $0.id != next.id }).dropFirst().first?.startTime
        segment.endTime = TranscriptAutoMerge.coveredEnd(of: [segment, next], followingStart: followingStart)
        segment.isEdited = true

        meeting.segments.removeAll { $0.id == next.id }
        modelContext.delete(next)
        selectedSegmentIDs.remove(next.id)
        saveEdit(site: "mergeSegmentWithNext")
    }

    private func splitSegment(_ segment: TranscriptSegment, before: String, after: String) {
        guard !before.isEmpty, !after.isEmpty else { return }

        let totalLength = Double(segment.text.count)
        let beforeLength = Double(before.count)
        let ratio = beforeLength / totalLength
        let splitTime = segment.startTime + (segment.endTime - segment.startTime) * ratio

        if !segment.isEdited {
            segment.originalText = segment.text
            segment.originalSpeakerData = segment.speakerData
        }
        segment.text = before
        segment.endTime = splitTime
        segment.isEdited = true

        let newSegment = TranscriptSegment(
            speaker: segment.speaker,
            text: after,
            startTime: splitTime,
            endTime: segment.endTime,
            isFinal: true
        )
        newSegment.meeting = meeting
        meeting.segments.append(newSegment)
        saveEdit(site: "splitSegment")
    }

    private func applyBulkSpeakerRename() {
        let name = bulkSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let original = meeting.segments.first(where: { selectedSegmentIDs.contains($0.id) })?.speaker ?? .other(name)
        if original.isMe {
            SpeakerNames.setSessionMeName(name, saveAsDefault: false)
        }
        requestAssignVisible(to: Speaker.renamed(from: original, displayName: name))
        showBulkSpeakerRename = false
    }

    private var isSpeakerFilterActive: Bool {
        speakerRoster.isolatedSpeaker != nil || !speakerRoster.hiddenSpeakers.isEmpty
    }

    private var filteredAssignTitle: String {
        let name = pendingAssignSpeaker?.displayName ?? "this speaker"
        let count = SpeakerRelabel.assignmentTargets(
            selected: selectedSegmentIDs,
            segments: meeting.segments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            newSpeaker: pendingAssignSpeaker ?? .other(name),
            isolatedSpeakers: mixerIsolatedSpeakers
        ).count
        return "Assign \(count) visible line\(count == 1 ? "" : "s") to \(name)?"
    }

    private func requestAssignVisible(to speaker: Speaker) {
        if selectedSegmentIDs.isEmpty {
            selectedSegmentIDs = Set(visibleSegments.map(\.id))
        }
        pruneSelectionToVisible()
        let targets = SpeakerRelabel.assignmentTargets(
            selected: selectedSegmentIDs,
            segments: meeting.segments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            newSpeaker: speaker,
            isolatedSpeakers: mixerIsolatedSpeakers
        )
        guard !targets.isEmpty else {
            TransientActivityCoordinator.shared.flash("Nothing visible to assign")
            return
        }
        if isSpeakerFilterActive {
            pendingAssignSpeaker = speaker
            showFilteredAssignConfirmation = true
            return
        }
        reassignSelectedSegments(to: speaker)
    }

    private func reassignSelectedSegments(to speaker: Speaker) {
        let canonical = speakerRoster.canonicalSpeaker(matching: speaker) ?? speaker
        let targets = SpeakerRelabel.assignmentTargets(
            selected: selectedSegmentIDs,
            segments: meeting.segments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            newSpeaker: canonical,
            isolatedSpeakers: mixerIsolatedSpeakers
        )
        guard !targets.isEmpty else { return }
        speakerUndo.capture(meeting.segments)
        let targetIDs = Set(targets.map(\.id))
        var absorbed: [Speaker] = []
        for segment in meeting.segments where targetIDs.contains(segment.id) {
            if !segment.isEdited {
                segment.originalText = segment.text
                segment.originalSpeakerData = segment.speakerData
            }
            let old = segment.speaker
            segment.speaker = canonical
            segment.isEdited = true
            if !old.matchesIdentity(canonical),
               !absorbed.contains(where: { $0.matchesIdentity(old) }) {
                absorbed.append(old)
            }
        }
        for old in absorbed {
            speakerRoster.adopt(from: old, onto: canonical, in: meeting.segments)
            retargetSpeaker(from: old, to: canonical, mergeIntoExisting: true)
        }
        speakerRoster.unifyOntoSeats(in: meeting.segments)
        refreshSegments()
        saveEdit(site: "reassignSelectedSegments")
        TransientActivityCoordinator.shared.flash(
            "Assigned \(targets.count) visible line\(targets.count == 1 ? "" : "s") to \(canonical.displayName)."
        )
    }

    private func deduplicateTranscript() {
        let snapshots = sortedSegments
        let result = TranscriptDeduplicator.deduplicate(snapshots)
        guard result.removedCount > 0 else { return }
        for removed in result.removedSegments {
            if let seg = meeting.segments.first(where: { $0.id == removed.id }) {
                modelContext.delete(seg)
            }
        }
        saveEdit(site: "deduplicateTranscript")
        sortedSegments = meeting.segments.sorted { $0.startTime < $1.startTime }
        LogManager.send("Manual dedup removed \(result.removedCount) segment(s)", category: .transcription)
    }

    private func revertAllEdits() {
        for segment in meeting.segments where segment.isEdited {
            if let originalText = segment.originalText {
                segment.text = originalText
            }
            if let originalSpeakerData = segment.originalSpeakerData {
                segment.speakerData = originalSpeakerData
            }
            segment.originalText = nil
            segment.originalSpeakerData = nil
            segment.isEdited = false
        }
        saveEdit(site: "revertAllEdits")
    }

    private func toggleSelection(_ segment: TranscriptSegment) {
        if selectedSegmentIDs.contains(segment.id) {
            selectedSegmentIDs.remove(segment.id)
        } else {
            selectedSegmentIDs.insert(segment.id)
        }
    }

    private func changeSpeakerForAll(from segment: TranscriptSegment, to newSpeaker: Speaker) {
        let currentSpeaker = segment.speaker
        let canonical = speakerRoster.canonicalSpeaker(matching: newSpeaker) ?? newSpeaker
        let merging = speakerRoster.seat(matching: canonical) != nil
            && !currentSpeaker.matchesIdentity(canonical)
        speakerUndo.capture(meeting.segments)
        var count = 0
        for seg in meeting.segments where SpeakerRelabel.matchesForRelabel(seg.speaker, current: currentSpeaker) {
            if !seg.isEdited {
                seg.originalText = seg.text
                seg.originalSpeakerData = seg.speakerData
            }
            seg.speaker = canonical
            seg.isEdited = true
            count += 1
        }
        if merging {
            speakerRoster.adopt(from: currentSpeaker, onto: canonical, in: meeting.segments)
        } else {
            speakerRoster.renameSeat(matching: currentSpeaker, to: canonical.displayName)
        }
        retargetSpeaker(from: currentSpeaker, to: canonical, mergeIntoExisting: merging)
        speakerRoster.unifyOntoSeats(in: meeting.segments)
        refreshSegments()
        saveEdit(site: "changeSpeakerForAll")
        DevLog.ui(
            "saved rename \(currentSpeaker.displayName) → \(canonical.displayName)",
            detail: "\(count) segment(s)"
        )
        TransientActivityCoordinator.shared.flash(
            "Renamed \(count) \(currentSpeaker.displayName) line\(count == 1 ? "" : "s") to \(canonical.displayName)."
        )
    }

    private func undoLastSpeakerChange() {
        guard let labels = speakerUndo.pop() else { return }
        SpeakerLabelUndo.apply(labels, to: meeting.segments)
        refreshSegments()
        saveEdit(site: "undoSpeakerChange")
        TransientActivityCoordinator.shared.flash("Undid the last speaker change.")
    }

    private func revertSpeakerLabels() {
        speakerUndo.capture(meeting.segments)
        var count = 0
        for segment in meeting.segments {
            guard let originalSpeakerData = segment.originalSpeakerData else { continue }
            segment.speakerData = originalSpeakerData
            segment.originalSpeakerData = nil
            if segment.originalText == nil {
                segment.isEdited = false
            }
            count += 1
        }
        refreshSegments()
        saveEdit(site: "revertSpeakerLabels")
        TransientActivityCoordinator.shared.flash(
            "Restored original speaker labels on \(count) line\(count == 1 ? "" : "s")."
        )
    }

    private func pruneSelectionToVisible() {
        let visible = SpeakerRelabel.visibleIDs(
            from: sortedSegments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: speakerRoster.isolatedSpeaker,
            isolatedSpeakers: mixerIsolatedSpeakers
        )
        selectedSegmentIDs = selectedSegmentIDs.intersection(visible)
    }

    private func recoverSpeakersFromAudio(expected: [MeetingSpeakerRecovery.ExpectedSpeaker] = []) {
        guard !isRecoveringSpeakers else { return }
        isRecoveringSpeakers = true
        speakerUndo.capture(meeting.segments)
        DevLog.ui(
            "recover-speakers-from-audio",
            detail: expected.map(\.name).joined(separator: ", ")
        )
        Task {
            defer { isRecoveringSpeakers = false }
            do {
                let result = try await MeetingSpeakerRecovery.recover(
                    meeting: meeting,
                    expected: expected
                )
                enrollRecoveredPrints(result, expected: expected)
                speakerRoster.bindNamedVoices(
                    in: meeting.segments,
                    contactNames: contactNameMap()
                )
                refreshSegments()
                saveEdit(site: "recoverSpeakers")
                reanalyzeResult = result
                editSaveError = result.changed == 0
                    ? "Audio did not yield distinct speakers beyond the current labels."
                    : nil
                if result.changed > 0 {
                    let leftover = result.unknownSpeakers.isEmpty
                        ? "You were not changed."
                        : "Leftovers are speaker-1…. Assign them in the sheet."
                    TransientActivityCoordinator.shared.flash(
                        "Re-analyzed \(result.changed) remote line\(result.changed == 1 ? "" : "s") from audio. \(leftover)"
                    )
                }
                DevLog.ui(
                    "recover-speakers done",
                    detail: "relabeled \(result.changed) line(s), \(result.unknownSpeakers.count) unknown"
                )
            } catch {
                editSaveError = error.localizedDescription
                DevLog.ui("recover-speakers failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func contactNameMap() -> [UUID: [String]] {
        Dictionary(uniqueKeysWithValues: contacts.map { contact in
            (contact.id, [contact.name] + contact.speakerAliases)
        })
    }

    private func enrollRecoveredPrints(
        _ result: MeetingSpeakerRecovery.Result,
        expected: [MeetingSpeakerRecovery.ExpectedSpeaker]
    ) {
        for person in expected {
            let embedding = result.embeddings[person.speaker.identityKey] ?? person.embedding
            guard let embedding, embedding.count >= 8 else { continue }
            let contact = resolveOrCreateContact(
                named: person.name,
                contactID: person.contactID,
                isMe: person.isMe
            )
            guard let contact else { continue }
            contact.mergeVoicePrint(embedding)
            rememberAlias(person.speaker.displayName, on: contact)
        }
        for speaker in result.matchedSpeakers where !speaker.isMe && !speaker.isGuestPlaceholder {
            guard let embedding = result.embeddings[speaker.identityKey], embedding.count >= 8 else { continue }
            let contact = resolveOrCreateContact(
                named: speaker.displayName,
                contactID: nil,
                isMe: false
            )
            contact?.mergeVoicePrint(embedding)
            if let contact {
                rememberAlias(speaker.displayName, on: contact)
            }
        }
    }

    private func assignUnknowns(_ speakers: [Speaker], to newSpeaker: Speaker, contact: Contact?) {
        guard !speakers.isEmpty else { return }
        speakerUndo.capture(meeting.segments)
        var count = 0
        for segment in meeting.segments where speakers.contains(where: { $0.matchesIdentity(segment.speaker) }) {
            if !segment.isEdited {
                segment.originalText = segment.text
                segment.originalSpeakerData = segment.speakerData
            }
            segment.speaker = newSpeaker
            segment.isEdited = true
            count += 1
        }
        for speaker in speakers {
            retargetSpeaker(from: speaker, to: newSpeaker, mergeIntoExisting: speakerRoster.seat(matching: newSpeaker) != nil)
        }

        let resolvedContact: Contact?
        if newSpeaker.isMe {
            resolvedContact = resolveOrCreateContact(
                named: newSpeaker.displayName,
                contactID: Meeting.storedMyContactID,
                isMe: true
            )
        } else {
            resolvedContact = contact ?? resolveOrCreateContact(
                named: newSpeaker.displayName,
                contactID: nil,
                isMe: false
            )
        }

        if let resolvedContact {
            rememberAlias(newSpeaker.displayName, on: resolvedContact)
            for speaker in speakers {
                rememberAlias(speaker.displayName, on: resolvedContact)
            }
            if let embeddings = reanalyzeResult?.embeddings {
                for speaker in speakers {
                    if let embedding = embeddings[speaker.identityKey], embedding.count >= 8 {
                        resolvedContact.mergeVoicePrint(embedding)
                    }
                }
            }
            if !newSpeaker.isMe, !meeting.attendees.contains(where: { $0.id == resolvedContact.id }) {
                meeting.attendees.append(resolvedContact)
            }
        }

        if let seat = speakerRoster.seats.first(where: {
            $0.speaker.matchesIdentity(newSpeaker)
                || SpeakerNameMatcher.samePerson($0.name, newSpeaker.displayName)
        }) {
            for speaker in speakers {
                speakerRoster.bind(detected: speaker, to: seat.id)
            }
            speakerRoster.bind(detected: newSpeaker, to: seat.id)
            speakerRoster.setLocked(seat.id, true)
        } else if !newSpeaker.isMe {
            let seat = speakerRoster.addSeat(name: newSpeaker.displayName, contactID: resolvedContact?.id)
            for speaker in speakers {
                speakerRoster.bind(detected: speaker, to: seat.id)
            }
            speakerRoster.setLocked(seat.id, true)
        }

        refreshSegments()
        saveEdit(site: "assignUnknowns")
        if var current = reanalyzeResult {
            current.unknownSpeakers.removeAll { leftover in
                speakers.contains { $0.matchesIdentity(leftover) }
            }
            reanalyzeResult = current
        }
        TransientActivityCoordinator.shared.flash(
            "Assigned \(count) line\(count == 1 ? "" : "s") to \(newSpeaker.displayName) and saved a voice stamp."
        )
        DevLog.ui(
            "assigned unknowns → \(newSpeaker.displayName)",
            detail: "\(count) line(s)"
        )
    }

    private func resolveOrCreateContact(named name: String, contactID: UUID?, isMe: Bool) -> Contact? {
        if let contactID, let existing = contacts.first(where: { $0.id == contactID }) {
            return existing
        }
        if isMe, let myID = Meeting.storedMyContactID,
           let me = contacts.first(where: { $0.id == myID }) {
            return me
        }
        if let existing = contacts.first(where: { $0.matchesSpeakerName(name) }) {
            return existing
        }
        if SpeakerLinkCatalog.isPlaceholder(name) { return nil }
        let created = Contact(name: name)
        modelContext.insert(created)
        return created
    }

    private func rememberAlias(_ name: String, on contact: Contact) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SpeakerLinkCatalog.isPlaceholder(trimmed) else { return }
        if !contact.speakerAliases.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame })
            && contact.name.compare(trimmed, options: .caseInsensitive) != .orderedSame {
            contact.speakerAliases.append(trimmed)
        }
    }

    /// Persist a user edit and surface failures. Used by all segment-editing
    /// actions (delete, merge, split, reassign, dedup, revert). On failure
    /// we log and show a transient error banner — if the user doesn't know
    /// their edit was dropped, they'll lose work silently.
    private func saveEdit(site: String) {
        let ok = PersistenceGate.save(
            modelContext,
            site: "MeetingDetailView.\(site)",
            meetingID: meeting.id
        )
        if !ok {
            editSaveError = "Edit couldn't be saved: \(PersistenceGate.lastFailureMessage ?? "unknown error"). Try again, or check disk space."
        } else {
            editSaveError = nil
        }
    }

    // Only disallow splitting at the very first segment (nothing would remain in the original).
    private func canSplitMeeting(at segment: TranscriptSegment) -> Bool {
        guard sortedSegments.count >= 2 else { return false }
        guard let idx = sortedSegments.firstIndex(where: { $0.id == segment.id }) else { return false }
        return idx > 0
    }

    @MainActor
    private func splitMeeting(from splitSegment: TranscriptSegment) async {
        guard let splitIdx = sortedSegments.firstIndex(where: { $0.id == splitSegment.id }),
              splitIdx > 0 else { return }

        isSplittingMeeting = true
        defer {
            isSplittingMeeting = false
            splitTask = nil
        }

        let keepSegments = Array(sortedSegments[0..<splitIdx])
        let moveSegments = Array(sortedSegments[splitIdx...])

        let splitTime = splitSegment.startTime
        let newMeetingDate = meeting.date.addingTimeInterval(splitTime)
        let newMeeting = Meeting(
            title: "Meeting \(DateFormatter.shortDate.string(from: newMeetingDate))",
            date: newMeetingDate,
            duration: meeting.duration - splitTime,
            status: .completed
        )
        modelContext.insert(newMeeting)

        newMeeting.attendees = meeting.attendees

        // Audio files aren't physically split — we record offsets into the
        // source meeting's audio timeline. If the meeting being split is
        // itself a child, preserve the original root and compound the
        // offsets so re-transcription walks the right chunks.
        let rootSource = meeting.audioSourceMeetingID ?? meeting.id
        let rootOffset = meeting.audioStartOffset
        newMeeting.audioSourceMeetingID = rootSource
        newMeeting.audioStartOffset = rootOffset + splitTime
        newMeeting.audioEndOffset = meeting.audioEndOffset
        // The meeting we're splitting now ends at the split point in the
        // source timeline.
        meeting.audioEndOffset = rootOffset + splitTime

        for segment in moveSegments {
            segment.startTime -= splitTime
            segment.endTime -= splitTime
            segment.meeting = newMeeting
        }

        meeting.duration = keepSegments.last.map { $0.endTime } ?? splitTime

        for old in meeting.insights { modelContext.delete(old) }
        for old in meeting.actionItems { modelContext.delete(old) }
        for old in newMeeting.insights { modelContext.delete(old) }
        for old in newMeeting.actionItems { modelContext.delete(old) }

        let splitSplitOK = PersistenceGate.save(
            modelContext,
            site: "splitMeeting/afterSegmentMove",
            critical: true,
            meetingID: meeting.id
        )
        if !splitSplitOK {
            editSaveError = "Split failed while saving the new meeting layout — both meetings may be in an inconsistent state. Check the activity log and consider reverting."
            return
        }

        let originalSnapshots = meeting.segments
            .sorted { $0.startTime < $1.startTime }
            .map { SegmentSnapshot(speaker: $0.speaker, text: $0.text, formattedTimestamp: $0.formattedTimestamp, isFinal: $0.isFinal) }
        let newSnapshots = newMeeting.segments
            .sorted { $0.startTime < $1.startTime }
            .map { SegmentSnapshot(speaker: $0.speaker, text: $0.text, formattedTimestamp: $0.formattedTimestamp, isFinal: $0.isFinal) }

        guard let client = try? await AIClientFactory.makeClient() else {
            onSplitMeeting?(newMeeting)
            return
        }

        meeting.isAnalyzing = true
        newMeeting.isAnalyzing = true
        PersistenceGate.save(
            modelContext,
            site: "splitMeeting/markAnalyzing",
            meetingID: meeting.id
        )

        await analyzeMeetingAfterSplit(meeting, snapshots: originalSnapshots, client: client)
        if Task.isCancelled {
            newMeeting.isAnalyzing = false
            PersistenceGate.save(modelContext, site: "splitMeeting/cancelled", meetingID: meeting.id)
            onSplitMeeting?(newMeeting)
            return
        }
        await analyzeMeetingAfterSplit(newMeeting, snapshots: newSnapshots, client: client)

        let finalOK = PersistenceGate.save(
            modelContext,
            site: "splitMeeting/finalInsights",
            critical: true,
            meetingID: meeting.id
        )
        if !finalOK {
            editSaveError = "Split re-analysis completed but saving insights failed. Both meetings have transcripts but may be missing AI insights — use Reanalyze to retry."
        }

        onSplitMeeting?(newMeeting)
    }

    private func analyzeMeetingAfterSplit(_ target: Meeting, snapshots: [SegmentSnapshot], client: any AIClient) async {
        guard !snapshots.isEmpty else {
            target.isAnalyzing = false
            return
        }

        let service = AIIntelligenceService(
            client: client,
            meetingID: target.id
        )
        do {
            let roster = MeetingRoster.snapshot(for: target)
            let finalResult = try await AIUsageContext.attribute(.reanalysis, meetingID: target.id) {
                try await service.reanalyze(
                    segments: snapshots,
                    roster: roster,
                    calendarTitle: target.analysisTitleHint
                )
            }
            if let result = finalResult {
                if let title = result.title {
                    target.applyGeneratedTitle(title)
                }
                let insight = MeetingInsight(
                    summary: result.summary,
                    followUpQuestions: result.followUps,
                    topics: result.topics,
                    rawLLMResponse: result.rawResponse,
                    modelIdentifier: client.modelIdentifier,
                    promptVersion: AIPromptTemplates.promptVersion
                )
                insight.meeting = target
                target.insights.append(insight)
                for parsed in result.actionItems {
                    let item = ActionItem(parsed: parsed, sourceSegments: target.segments)
                    item.meeting = target
                    target.actionItems.append(item)
                }
            }
        } catch {
            LogManager.send("Split meeting analysis failed: \(error.localizedDescription)", category: .ai, level: .error)
        }
        target.isAnalyzing = false
    }
}
