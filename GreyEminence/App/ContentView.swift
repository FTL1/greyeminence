import SwiftUI
import SwiftData

enum SidebarDestination: String, Hashable, CaseIterable {
    case dashboard = "Dashboard"
    case meetings = "Meetings"
    case archive = "Archive"
    case recording = "New Recording"
    case insights = "Insights"
    case questions = "Questions"
    case tasks = "Tasks"
    case summaries = "Summaries"
    case interviews = "Interviews"
    case people = "People"
    case topicMap = "Topic Map"
    case ask = "Ask"
    case find = "Find"
    case activityLog = "Activity Log"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .meetings: "list.bullet.rectangle"
        case .archive: "archivebox"
        case .recording: "record.circle"
        case .insights: "brain"
        case .questions: "questionmark.bubble"
        case .tasks: "checkmark.circle"
        case .summaries: "doc.text"
        case .interviews: "person.badge.shield.checkmark"
        case .people: "person.2"
        case .topicMap: "bubble.left.and.bubble.right"
        case .ask: "sparkles.square.filled.on.square"
        case .find: "magnifyingglass"
        case .activityLog: "list.bullet.clipboard"
        case .settings: "gear"
        }
    }

    var iconColor: Color {
        switch self {
        case .dashboard: .blue
        case .meetings: .indigo
        case .archive: .brown
        case .recording: .red
        case .insights: .purple
        case .questions: .teal
        case .tasks: .orange
        case .summaries: .blue
        case .interviews: .cyan
        case .people: .green
        case .topicMap: .purple
        case .ask: .pink
        case .find: .mint
        case .activityLog: .gray
        case .settings: .gray
        }
    }

    var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    var helpText: String {
        switch self {
        case .dashboard: HelpTip.sidebarDashboard.tooltip
        case .meetings: HelpTip.sidebarMeetings.tooltip
        case .archive: HelpTip.sidebarArchive.tooltip
        case .recording: HelpTip.sidebarRecording.tooltip
        case .insights: HelpTip.sidebarInsights.tooltip
        case .questions: HelpTip.sidebarQuestions.tooltip
        case .tasks: HelpTip.sidebarTasks.tooltip
        case .summaries: HelpTip.sidebarSummaries.tooltip
        case .interviews: HelpTip.sidebarInterviews.tooltip
        case .people: HelpTip.sidebarPeople.tooltip
        case .topicMap: HelpTip.sidebarTopicMap.tooltip
        case .ask: HelpTip.sidebarAsk.tooltip
        case .find: HelpTip.sidebarFind.tooltip
        case .activityLog: HelpTip.sidebarActivityLog.tooltip
        case .settings: HelpTip.sidebarSettings.tooltip
        }
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDestination: SidebarDestination? = .dashboard
    @State private var selectedMeeting: Meeting?
    @State private var selectedMeetingIDs: Set<UUID> = []
    @State private var showReanalyzeAllConfirm = false
    @State private var reanalyzeAllCount = 0
    @State private var extractLaunch: ArchiveExtractLaunch?
    @State private var topicMapViewModel = TopicMapViewModel()
    @State private var askViewModel = AskViewModel()
    @State private var meetingFind = MeetingFindController()
    @State private var pendingScrollSegmentID: UUID?
    /// Transcript → screen-share player: set by a timestamp tap or an Ask
    /// deep link; consumed by ScreenSharePlayerSection (expand, seek, clear).
    @State private var pendingSeekTime: TimeInterval?
    @AppStorage("showInspector") private var showInspector = true
    @State private var sidebarExpanded = false
    @State private var inspectorWidth: CGFloat?
    @AppStorage("developerToolsEnabled") private var developerToolsEnabled = false
    @AppStorage("myContactID") private var myContactIDString = ""
    @AppStorage("autoStartRecording") private var autoStartRecording = false
    @State private var showProfileSetup = false
    @AppStorage("ftlLegalNoticeAccepted") private var legalNoticeAccepted = false
    @State private var showLegalNotice = false
    @State private var interruptedMeeting: Meeting?
    @State private var showResumeAlert = false
    /// Highest app version whose feature highlights the user has seen. Empty on
    /// first launch under this system — seeded in `presentWhatsNewIfNeeded`.
    @AppStorage("lastSeenHighlightVersion") private var lastSeenHighlightVersion = ""
    /// Staged What's New presentation — non-nil means "show it". Set by the
    /// post-update check and, via the focused value below, by Help → What's New.
    @State private var whatsNew: WhatsNewPresentation?
    @State private var selectedInterview: Interview?
    var recordingViewModel: RecordingViewModel
    var interviewRecordingViewModel: InterviewRecordingViewModel

    var body: some View {
        mainInterface
    }

    private var mainInterface: some View {
        chrome
            .environment(meetingFind)
            .onChange(of: selectedMeeting?.id) { _, _ in
                meetingFind.resetForMeetingChange()
            }
            .background {
                FindShortcutHost(
                    onMeetingFind: focusMeetingOrLibraryFind,
                    onLibraryFind: openFind,
                    onNext: meetingFind.nextTranscriptMatch,
                    onPrevious: meetingFind.previousTranscriptMatch
                )
            }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            CaptureKillSwitchBar(viewModel: recordingViewModel)
            HStack(spacing: 0) {
                SidebarView(
                    selection: $selectedDestination,
                    isExpanded: $sidebarExpanded
                )
                Divider()
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
                    .environment(\.topicMapViewModel, topicMapViewModel)
                    .onChange(of: topicMapViewModel.pendingFocusTopic) { _, topic in
                        if topic != nil {
                            selectedDestination = .topicMap
                        }
                    }
            }
            CallPromptBar(viewModel: recordingViewModel)
            ReProcessingStatusBar()
            MeetingReanalysisStatusBar(onOpenMeeting: openMeeting(id:))
            TransientActivityStatusBar()
            ReanalyzeAllConfirmationHost(
                isPresented: $showReanalyzeAllConfirm,
                count: reanalyzeAllCount
            )
            ReanalyzeFocusedValuesHost(
                selectedMeetingIDs: selectedMeetingIDs,
                showReanalyzeAllConfirm: $showReanalyzeAllConfirm,
                reanalyzeAllCount: $reanalyzeAllCount,
                extractLaunch: $extractLaunch,
                modelContext: modelContext
            )
        }
        .sheet(item: $extractLaunch) { launch in
            ArchiveExtractSheet(launch: launch)
        }
        .toolbar {
            // Title-bar badge marking a local Debug run (empty in Release).
            ToolbarItem(placement: .navigation) {
                DevBuildBanner()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openFind()
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .helpTip(.toolbarFind)
            }
            if selectedDestination == .meetings || selectedDestination == .archive || selectedDestination == .recording || selectedDestination == .interviews {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Toggle Insights", systemImage: "sidebar.right")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .helpTip(.toolbarInspector)
                }
            }
        }
        .onChange(of: recordingViewModel.completedMeeting) { _, meeting in
            guard let meeting else { return }
            if meeting.isInterviewMeeting {
                selectedInterview = interviewRecordingViewModel.completedInterview
                interviewRecordingViewModel.reset()
                selectedDestination = .interviews
            } else {
                selectedMeeting = meeting
                selectedMeetingIDs = [meeting.id]
                selectedDestination = .meetings
            }
            recordingViewModel.completedMeeting = nil
        }
        .onChange(of: selectedMeeting?.id) { _, newID in
            if let newID, !selectedMeetingIDs.contains(newID) {
                selectedMeetingIDs = [newID]
            }
        }
        .onChange(of: developerToolsEnabled) { _, enabled in
            if !enabled && selectedDestination == .activityLog {
                selectedDestination = .dashboard
            }
        }
        .onAppear {
            // The test bundle is hosted by this app, so a test run launches it
            // for real. None of what follows may touch the developer's live
            // store: maintenance rewrites rows, recovery re-imports frames,
            // auto-detection can start a recording. Tests exercise these
            // services directly with their own contexts instead.
            guard !TestEnvironment.isRunningTests else { return }

            TransientActivityCoordinator.shared.run("Checking for an interrupted recording…") {
                checkForInterruptedRecording()
            }
            TransientActivityCoordinator.shared.run("Checking interviews…") {
                recoverOrphanedInterviews()
            }
            if !legalNoticeAccepted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showLegalNotice = true
                }
            } else if myContactIDString.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    showProfileSetup = true
                }
            }
            presentWhatsNewIfNeeded()
            recordingViewModel.configureAutoDetection(enabled: autoStartRecording) { [modelContext] in
                modelContext
            }
            Task(priority: .background) { @MainActor [modelContext] in
                let report = TransientActivityCoordinator.shared.run("Running startup maintenance…") {
                    MaintenanceService.runStartupMaintenance(modelContext: modelContext)
                }
                if !report.skipped {
                    TransientActivityCoordinator.shared.flash("Maintenance complete")
                }
                // Unthrottled (unlike maintenance): rows lost to a schema
                // downgrade should come back on the very next launch, and
                // the no-op case costs one fetch + a directory check.
                let recovered = await TransientActivityCoordinator.shared.runAsync(
                    "Checking screen-share frames…"
                ) {
                    await ScreenFrameRecoveryService.recoverAtLaunch(modelContext: modelContext)
                }
                if recovered > 0 {
                    TransientActivityCoordinator.shared.flash("Recovered \(recovered) screen-share frame(s)")
                }
            }
        }
        .onChange(of: autoStartRecording) { _, enabled in
            recordingViewModel.setAutoDetectionEnabled(enabled)
        }
        // Lets Help → What's New present the sheet in this window when it's the
        // key one — see FocusedValues.whatsNewPresentation.
        .focusedSceneValue(\.whatsNewPresentation, $whatsNew)
        .sheet(isPresented: $showLegalNotice) {
            LegalNoticeSheet {
                legalNoticeAccepted = true
                showLegalNotice = false
                if myContactIDString.isEmpty {
                    showProfileSetup = true
                }
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showProfileSetup) {
            MyProfileSetupSheet()
        }
        // "What's New" — post-update or on demand from the Help menu. Dismissal
        // (any path — Got it, Escape, Try it) records the current version via
        // onDismiss so the post-update sheet never re-nags.
        .sheet(item: $whatsNew, onDismiss: {
            lastSeenHighlightVersion = FeatureHighlightCatalog.currentVersion
        }) { presentation in
            WhatsNewSheet(
                highlights: presentation.highlights,
                version: FeatureHighlightCatalog.currentVersion
            ) { highlight in
                // Deep-link into the feature, and count that as discovering it
                // so the in-context badge doesn't also fire.
                whatsNew = nil
                if let destination = highlight.destination {
                    selectedDestination = destination
                }
                FeatureDiscovery.shared.markSeen(highlight.id)
            }
        }
        // Presented at the root so it appears regardless of which destination is
        // active — a recording (and its multi-event calendar choice) can be
        // started from the menu bar or auto-detector while the Recording tab
        // isn't open.
        .sheet(isPresented: Binding(
            get: { !recordingViewModel.pendingCalendarChoices.isEmpty },
            set: { if !$0 { recordingViewModel.pendingCalendarChoices = [] } }
        )) {
            CalendarEventPickerSheet(
                events: recordingViewModel.pendingCalendarChoices,
                onPick: { event in
                    recordingViewModel.matchCalendarEventManually(event, in: modelContext)
                    recordingViewModel.pendingCalendarChoices = []
                },
                onSkip: { recordingViewModel.pendingCalendarChoices = [] }
            )
        }
        .alert("Resume Recording?", isPresented: $showResumeAlert) {
            Button("Resume") {
                if let meeting = interruptedMeeting {
                    recordingViewModel.resumeInterruptedRecording(meeting: meeting, in: modelContext)
                    selectedDestination = .recording
                    interruptedMeeting = nil
                }
            }
            Button("Discard", role: .destructive) {
                interruptedMeeting = nil
                recoverOrphanedMeetings()
            }
        } message: {
            if let meeting = interruptedMeeting {
                Text("\"\(meeting.title)\" was interrupted. Resume recording or discard it?\n\(meeting.segments.count) segments, \(meeting.formattedDuration) elapsed")
            }
        }
    }

    /// Revert any Interview rows stuck in `.recording` back to `.scheduled`.
    /// The recording engine is process-local — if the app was restarted or
    /// crashed mid-interview, the status persists but no audio is being
    /// captured. `checkForInterruptedRecording` already declines to resume
    /// interview meetings (they're too complex to restore), so without this
    /// the row's Start button stays hidden forever and the user is stuck
    /// looking at a "In Progress" badge they can't act on. Reverting to
    /// `.scheduled` restores the Start button so they can re-enter cleanly.
    private func recoverOrphanedInterviews() {
        let descriptor = FetchDescriptor<Interview>()
        let interviews = (try? modelContext.fetch(descriptor)) ?? []
        var reverted = 0
        for interview in interviews where interview.status == .recording {
            interview.status = .scheduled
            interview.interruptedAt = .now
            reverted += 1
        }
        guard reverted > 0 else { return }
        PersistenceGate.save(
            modelContext,
            site: "ContentView.recoverOrphanedInterviews",
            critical: true
        )
        LogManager.send("Recovered \(reverted) orphaned interview row(s) — reverted to scheduled", category: .general)
        TransientActivityCoordinator.shared.flash(
            "Restored \(reverted) interrupted interview\(reverted == 1 ? "" : "s") — click Start to resume"
        )
    }

    /// Decide whether to show the post-update "What's New" sheet, and stage its
    /// highlights. Runs once per launch from `onAppear`.
    private func presentWhatsNewIfNeeded() {
        // Never interrupt an in-progress recording that survived a relaunch.
        guard recordingViewModel.state == .idle else { return }

        if lastSeenHighlightVersion.isEmpty {
            // First launch under this system. A brand-new user (no profile set,
            // no changelog reads) is onboarding — suppress the sheet and just
            // start tracking from here so they only ever see FUTURE updates.
            // An existing user upgrading INTO the system sees the current
            // highlights once (seed to "0.0.0"), then only newer ones after.
            let brandNewUser = myContactIDString.isEmpty && ChangelogReadStore.readVersions().isEmpty
            if brandNewUser {
                lastSeenHighlightVersion = FeatureHighlightCatalog.currentVersion
                return
            }
            lastSeenHighlightVersion = "0.0.0"
        }

        let pending = FeatureHighlightCatalog.pending(since: lastSeenHighlightVersion)
        guard !pending.isEmpty else { return }

        // Sequence behind the first-run profile sheet so the two never stack.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !showProfileSetup, !showLegalNotice else { return }
            whatsNew = WhatsNewPresentation(highlights: pending)
        }
    }

    /// Check if there's an interrupted recording from a previous session.
    /// If found, prompt the user to resume or discard. Otherwise, run orphan cleanup.
    private func checkForInterruptedRecording() {
        guard let meetingID = RecordingViewModel.interruptedMeetingID() else {
            recoverOrphanedMeetings()
            return
        }

        // Find the meeting in SwiftData
        let descriptor = FetchDescriptor<Meeting>()
        guard let meeting = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == meetingID }),
              meeting.status == .recording || meeting.status == .paused else {
            // Meeting not found or already completed — clear the marker and clean up
            UserDefaults.standard.removeObject(forKey: "activeRecordingMeetingID")
            recoverOrphanedMeetings()
            return
        }

        // Don't resume interview meetings — too complex to restore
        if meeting.isInterviewMeeting {
            UserDefaults.standard.removeObject(forKey: "activeRecordingMeetingID")
            recoverOrphanedMeetings()
            return
        }

        interruptedMeeting = meeting
        showResumeAlert = true
    }

    /// On launch, clean up any meetings still stuck in .recording or .paused from a previous session.
    /// Empty orphans (0 segments) are deleted; non-empty ones are marked completed (interrupted).
    /// Also cross-references on-disk `recording.lock` sidecar files so we can detect
    /// audio that was captured before SwiftData even got a chance to save the meeting row.
    private func recoverOrphanedMeetings() {
        let statusRecording = MeetingStatus.recording
        let statusPaused = MeetingStatus.paused
        let allMeetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let orphansFetched = allMeetings.filter {
            $0.status == statusRecording || $0.status == statusPaused
        }

        // Build the protected-IDs set BEFORE purging. The lock-file scan must
        // come first so a recording whose meeting row failed to save (so it's
        // missing from `allMeetings`) doesn't get its audio nuked just because
        // SwiftData doesn't know about it. The lock file is the on-disk
        // breadcrumb that "this audio is in-progress, don't touch."
        let lockFiles = RecordingLockFile.scanAll()
        var referenced = Set(allMeetings.map(\.id))
        for m in allMeetings {
            if let src = m.audioSourceMeetingID { referenced.insert(src) }
        }
        for lock in lockFiles {
            referenced.insert(lock.meetingID)
        }

        let purged = StorageManager.shared.purgeOrphanedRecordings(referencedIDs: referenced)
        if purged.count > 0 {
            let mb = Double(purged.bytes) / 1_048_576
            LogManager.send(
                "Purged \(purged.count) orphaned recording folder(s), freed \(String(format: "%.1f", mb)) MB",
                category: .general
            )
        }

        // Recording-retention sweep: drop audio files for completed meetings
        // older than the configured threshold. Transcripts + meeting rows
        // stay; only the (large) m4a files go. 0 = unlimited.
        let retentionDays = UserDefaults.standard.integer(forKey: "recordingRetentionDays")
        if retentionDays > 0 {
            var ages: [UUID: Date] = [:]
            for m in allMeetings where m.status == .completed {
                ages[m.id] = m.date.addingTimeInterval(m.duration)
            }
            let aged = StorageManager.shared.purgeRecordingsOlderThan(
                days: retentionDays,
                meetingFinishedAt: ages
            )
            if aged.count > 0 {
                let mb = Double(aged.bytes) / 1_048_576
                LogManager.send(
                    "Retention sweep: removed audio for \(aged.count) meeting(s) older than \(retentionDays) day\(retentionDays == 1 ? "" : "s"), freed \(String(format: "%.1f", mb)) MB",
                    category: .general
                )
            }
        }

        if !lockFiles.isEmpty {
            let knownIDs = Set(allMeetings.map(\.id))
            let ghosts = lockFiles.filter { !knownIDs.contains($0.meetingID) }
            for ghost in ghosts {
                LogManager.send(
                    "Ghost recording detected on disk: \(ghost.meetingID) started \(ghost.startedAt) — audio files exist but no meeting row. Check Recordings/\(ghost.meetingID.uuidString)/",
                    category: .general,
                    level: .warning
                )
            }
            // Clean up lock files that correspond to meetings we're about to
            // mark completed/deleted — otherwise they'll stay and re-warn.
            let touched = Set(orphansFetched.map(\.id))
            for file in lockFiles where touched.contains(file.meetingID) {
                RecordingLockFile.remove(for: file.meetingID)
            }
        }

        guard !orphansFetched.isEmpty else { return }
        let orphans = orphansFetched

        var recovered = 0
        var deleted = 0
        for meeting in orphans {
            if meeting.segments.isEmpty && meeting.duration < 1 {
                // No useful data — just delete it (plus any stray audio on disk)
                MeetingDeletion.delete(meeting, in: modelContext, allMeetings: orphans)
                deleted += 1
            } else {
                meeting.status = .completed
                if !meeting.title.contains("(interrupted)") {
                    meeting.title += " (interrupted)"
                }
                recovered += 1
            }
        }
        // Critical: if we can't save here, the orphan meetings stay stuck in
        // .recording forever and will re-prompt on every launch.
        PersistenceGate.save(
            modelContext,
            site: "ContentView.recoverOrphanedMeetings",
            critical: true
        )
        if recovered + deleted > 0 {
            LogManager.send("Orphan cleanup: \(recovered) recovered, \(deleted) deleted", category: .general)
        }
    }

    private func openMeetingFromIntelligence(_ meeting: Meeting) {
        selectedMeeting = meeting
        selectedMeetingIDs = [meeting.id]
        selectedDestination = .meetings
    }

    private func openFindHit(_ hit: LibrarySearchHit) {
        let meetingID = hit.meetingID
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        descriptor.fetchLimit = 1
        guard let meeting = try? modelContext.fetch(descriptor).first else { return }
        selectedMeeting = meeting
        selectedMeetingIDs = [meeting.id]
        selectedDestination = .meetings
        if let segmentID = hit.segmentID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                pendingScrollSegmentID = segmentID
            }
        } else {
            showInspector = true
        }
    }

    private func openFind() {
        selectedDestination = .find
    }

    private func focusMeetingOrLibraryFind() {
        let onMeeting = selectedDestination == .meetings || selectedDestination == .archive
        if onMeeting, selectedMeeting != nil {
            meetingFind.requestFocus()
        } else {
            openFind()
        }
    }

    private func openMeeting(id: UUID) {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let meeting = try? modelContext.fetch(descriptor).first else { return }
        selectedMeeting = meeting
        selectedMeetingIDs = [meeting.id]
        selectedDestination = .meetings
    }

    private func openTopicDialog(meeting: Meeting, segmentID: UUID) {
        selectedMeeting = meeting
        selectedMeetingIDs = [meeting.id]
        pendingScrollSegmentID = segmentID
        showInspector = true
        if selectedDestination != .meetings && selectedDestination != .archive {
            selectedDestination = .meetings
        }
    }

    private func inspectorDragHandle(containerWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = (inspectorWidth ?? containerWidth * 0.5) - value.translation.width
                        inspectorWidth = min(max(newWidth, 280), containerWidth * 0.7)
                    }
            )
            .overlay {
                Divider()
            }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch selectedDestination {
        case .dashboard:
            DashboardView(
                onMeetingSelected: { meeting in
                    selectedMeeting = meeting
                    selectedMeetingIDs = [meeting.id]
                    selectedDestination = .meetings
                },
                onSelectDestination: { destination in
                    selectedDestination = destination
                }
            )
        case .meetings:
            NavigationSplitView {
                MeetingListView(
                    selectedMeeting: $selectedMeeting,
                    selectedMeetingIDs: $selectedMeetingIDs,
                    onShowArchive: { selectedDestination = .archive },
                    onExtract: { extractLaunch = $0 }
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            } detail: {
                if let meeting = selectedMeeting {
                    GeometryReader { geo in
                        // Priority for collapsing: center > sidebar > transcript.
                        // The center pane gets a healthy floor (60% min), and
                        // the transcript inspector is clamped to at most 45%
                        // of the available width so the header never squishes
                        // into the character-wrapping disaster from earlier.
                        let defaultWidth = geo.size.width * 0.4
                        let width = inspectorWidth ?? defaultWidth
                        let clampedWidth = min(max(width, 280), geo.size.width * 0.45)

                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                MeetingHeaderBar(meeting: meeting)
                                Divider()
                                MeetingIntelligenceView(
                                    meeting: meeting,
                                    pendingSeekTime: $pendingSeekTime,
                                    onPlayheadSegment: { pendingScrollSegmentID = $0 },
                                    onOpenDialog: openTopicDialog(meeting:segmentID:),
                                    onSelectDestination: { selectedDestination = $0 }
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(2)
                            if showInspector {
                                inspectorDragHandle(containerWidth: geo.size.width)
                                TranscriptPanelView(
                                    meeting: meeting,
                                    onSplitMeeting: { newMeeting in
                                        selectedMeeting = newMeeting
                                    },
                                    scrollToSegmentID: $pendingScrollSegmentID,
                                    onSeekToTime: meeting.screenFrames.isEmpty ? nil : { pendingSeekTime = $0 }
                                )
                                .frame(width: clampedWidth)
                                .layoutPriority(0)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Meeting Selected",
                        systemImage: "doc.text",
                        description: Text("Select a meeting to view its details")
                    )
                }
            }
        case .archive:
            NavigationSplitView {
                ArchiveView(
                    selectedMeeting: $selectedMeeting,
                    selectedMeetingIDs: $selectedMeetingIDs,
                    onExtract: { extractLaunch = $0 }
                )
                    .navigationSplitViewColumnWidth(min: 360, ideal: 480)
            } detail: {
                if let meeting = selectedMeeting {
                    GeometryReader { geo in
                        let defaultWidth = geo.size.width * 0.4
                        let width = inspectorWidth ?? defaultWidth
                        let clampedWidth = min(max(width, 280), geo.size.width * 0.45)

                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                MeetingHeaderBar(meeting: meeting)
                                Divider()
                                MeetingIntelligenceView(
                                    meeting: meeting,
                                    pendingSeekTime: $pendingSeekTime,
                                    onPlayheadSegment: { pendingScrollSegmentID = $0 },
                                    onOpenDialog: openTopicDialog(meeting:segmentID:),
                                    onSelectDestination: { selectedDestination = $0 }
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(2)
                            if showInspector {
                                inspectorDragHandle(containerWidth: geo.size.width)
                                TranscriptPanelView(
                                    meeting: meeting,
                                    onSplitMeeting: { newMeeting in
                                        selectedMeeting = newMeeting
                                    },
                                    scrollToSegmentID: $pendingScrollSegmentID,
                                    onSeekToTime: meeting.screenFrames.isEmpty ? nil : { pendingSeekTime = $0 }
                                )
                                .frame(width: clampedWidth)
                                .layoutPriority(0)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Meeting Selected",
                        systemImage: "doc.text",
                        description: Text("Pick a meeting from the archive to view its details")
                    )
                }
            }
        case .recording:
            VStack(spacing: 0) {
                SpeakerRosterBar(
                    roster: recordingViewModel.speakerRoster,
                    segments: recordingViewModel.segments,
                    onAssignVoice: { voice, seat in
                        recordingViewModel.assignDetectedVoice(voice, to: seat)
                    },
                    onAddedPerson: { _, contact in
                        if let meeting = recordingViewModel.currentMeeting {
                            recordingViewModel.applyRosterToMeeting(meeting, in: modelContext)
                            if let contact, !meeting.attendees.contains(where: { $0.id == contact.id }) {
                                meeting.attendees.append(contact)
                            }
                        }
                    },
                    onEnrollVoicePrint: { speaker in
                        recordingViewModel.enrollVoicePrint(for: speaker)
                    }
                )
                .onAppear {
                    recordingViewModel.speakerRoster.ensureMe(named: SpeakerNames.effectiveMeName)
                }
                Divider()
                GeometryReader { geo in
                    // Keep the live transcript a healthy panel but never let it crowd
                    // the recording pane (whose toolbar is horizontally dense): floor
                    // the recording side at ~50% by clamping the inspector to 50% max.
                    let defaultWidth = geo.size.width * 0.4
                    let width = inspectorWidth ?? defaultWidth
                    let clampedWidth = min(max(width, 280), geo.size.width * 0.5)

                    HStack(spacing: 0) {
                        RecordingView(viewModel: recordingViewModel, showsTranscript: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(2)
                        // Only show the live transcript pane while a recording is
                        // active. When idle (e.g. returning here to start a new one)
                        // there's nothing live to show, and rendering it would
                        // surface the previous recording's transcript.
                        if showInspector && recordingViewModel.state != .idle {
                            inspectorDragHandle(containerWidth: geo.size.width)
                            RecordingInspectorPanel(viewModel: recordingViewModel)
                                .frame(width: clampedWidth)
                                .layoutPriority(0)
                        }
                    }
                }
            }
        case .interviews:
            InterviewHubView(
                interviewViewModel: interviewRecordingViewModel,
                selectedInterview: $selectedInterview,
                showInspector: $showInspector,
                inspectorWidth: $inspectorWidth
            )
        case .insights:
            InsightsHubView(
                selectedMeetingIDs: selectedMeetingIDs,
                onMeetingSelected: openMeetingFromIntelligence(_:),
                onSelectDestination: { selectedDestination = $0 }
            )
        case .questions:
            AllQuestionsView(
                selectedMeetingIDs: selectedMeetingIDs,
                onMeetingSelected: openMeetingFromIntelligence(_:)
            )
        case .tasks:
            AllTasksView(
                selectedMeetingIDs: selectedMeetingIDs,
                onMeetingSelected: openMeetingFromIntelligence(_:)
            )
        case .summaries:
            AllSummariesView(onMeetingSelected: openMeetingFromIntelligence(_:))
        case .people:
            PeopleView()
        case .topicMap:
            TopicMapView(viewModel: topicMapViewModel, onMeetingSelected: { meeting in
                selectedMeeting = meeting
                selectedMeetingIDs = [meeting.id]
                selectedDestination = .meetings
            })
        case .find:
            LibrarySearchView(
                currentMeetingID: selectedMeeting?.id,
                selectedMeetingIDs: selectedMeetingIDs,
                preferredScope: selectedMeeting == nil && selectedMeetingIDs.isEmpty
                    ? .allMeetings
                    : (selectedMeetingIDs.count > 1 ? .selectedMeetings : .thisMeeting),
                onOpenHit: openFindHit(_:)
            )
        case .ask:
            AskView(viewModel: askViewModel, onResultSelected: { result in
                let descriptor = FetchDescriptor<Meeting>()
                if let meeting = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == result.meetingID }) {
                    selectedMeeting = meeting
                    selectedMeetingIDs = [meeting.id]
                    selectedDestination = .meetings
                    if result.sourceKind == .transcriptSegment {
                        // Delay so MeetingDetailView mounts before we try to scroll
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            pendingScrollSegmentID = result.sourceID
                        }
                    } else if result.sourceKind == .screenObservation {
                        // Resolve the frame's timestamp at click time (the
                        // embedding record doesn't carry it) and seek the
                        // screen-share player there once the view mounts.
                        let timestamp = meeting.screenFrames.first(where: { $0.id == result.sourceID })?.timestamp
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            if let timestamp {
                                pendingSeekTime = timestamp
                            }
                        }
                    }
                }
            })
        case .activityLog:
            LogView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView(
                "Select a section",
                systemImage: "sidebar.left",
                description: Text("Choose a section from the sidebar")
            )
        }
    }
}

private struct FindShortcutHost: View {
    var onMeetingFind: () -> Void
    var onLibraryFind: () -> Void
    var onNext: () -> Void
    var onPrevious: () -> Void

    var body: some View {
        Group {
            Button("Find in Meeting", action: onMeetingFind)
                .keyboardShortcut("f", modifiers: .command)
            Button("Library Find", action: onLibraryFind)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Find Next", action: onNext)
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous", action: onPrevious)
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

struct ActionItemRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.meetingFindQuery) private var findQuery
    @Bindable var item: ActionItem
    var onDelete: ((ActionItem) -> Void)?
    var onShowDetails: ((ActionItem) -> Void)?
    var showsMeetingContext: Bool = false
    var onOpenMeeting: ((Meeting) -> Void)?
    @State private var showContactPicker = false

    private func persist(_ site: String) {
        PersistenceGate.save(modelContext, site: "ActionItemRow.\(site)", meetingID: item.meeting?.id)
    }

    private var excludedIDs: Set<PersistentIdentifier> {
        if let contact = item.assignedContact {
            return [contact.persistentModelID]
        }
        return []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                item.isCompleted.toggle()
                persist("toggleCompleted")
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "Mark this action incomplete" : "Mark this action complete")

            VStack(alignment: .leading, spacing: 2) {
                HighlightedBody(
                    text: item.text,
                    query: findQuery,
                    font: .body,
                    color: item.isCompleted || item.isDismissed ? Color.secondary : Color.primary,
                    strikethrough: item.isCompleted || item.isDismissed
                )
                .textSelection(.enabled)
                // Assignee row only when one is set — assign/unlink live in the
                // context menu, so unassigned items stay a single clean line
                // rather than a second row with a dangling icon.
                if let contact = item.assignedContact {
                    HStack(spacing: 4) {
                        Text(contact.initials)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(contact.avatarColor.gradient, in: Circle())
                        Text(contact.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let assignee = item.assignee, !assignee.isEmpty {
                    Text(assignee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsMeetingContext {
                    HStack(spacing: 8) {
                        if let meeting = item.meeting {
                            Button {
                                onOpenMeeting?(meeting)
                            } label: {
                                Label(meeting.title, systemImage: "calendar")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Open \(meeting.title)")
                            Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.tertiary)
                        }
                        if let due = item.dueDate {
                            Text("due \(due.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onShowDetails != nil {
                Button {
                    onShowDetails?(item)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show task details")
            }
        }
        .contextMenu {
            if onShowDetails != nil {
                Button("Show Details") { onShowDetails?(item) }
            }
            if let meeting = item.meeting, onOpenMeeting != nil {
                Button("Open Meeting") { onOpenMeeting?(meeting) }
            }
            if onShowDetails != nil || onOpenMeeting != nil {
                Divider()
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                let text = if let assignee = item.displayAssignee {
                    "\(item.text) (\(assignee))"
                } else {
                    item.text
                }
                NSPasteboard.general.setString(text, forType: .string)
            }
            Divider()
            Button("Assign Contact...") {
                showContactPicker = true
            }
            if item.assignedContact != nil {
                Button("Unlink Contact") {
                    item.assignedContact = nil
                    persist("unlinkContact")
                }
            }
            Divider()
            if item.isDismissed {
                Button("Restore (mark Pending)") {
                    item.dismissedAt = nil
                    persist("restoreFromDismissed")
                }
            } else if !item.isCompleted {
                Button("Mark as Won't Do") {
                    item.dismissedAt = .now
                    persist("dismiss")
                }
            }
            if let onDelete {
                Divider()
                Button("Delete", role: .destructive) {
                    onDelete(item)
                }
            }
        }
        .popover(isPresented: $showContactPicker) {
            ContactPicker(
                excludedContacts: excludedIDs,
                prioritizedContacts: item.meeting?.attendees ?? []
            ) { contact in
                item.assignedContact = contact
                persist("assignContact")
                showContactPicker = false
            }
        }
    }
}

