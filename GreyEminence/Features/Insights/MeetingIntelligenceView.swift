import SwiftUI
import SwiftData
import AppKit

struct MeetingIntelligenceView: View {
    @Bindable var meeting: Meeting
    /// Screen-share player sync (optional — only the meeting/archive detail
    /// panes wire these; other hosts get a self-contained player).
    var pendingSeekTime: Binding<TimeInterval?> = .constant(nil)
    var onPlayheadSegment: ((UUID) -> Void)? = nil
    var onOpenDialog: ((Meeting, UUID) -> Void)? = nil
    var onSelectDestination: ((SidebarDestination) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Bindable private var reanalysisQueue = MeetingReanalysisQueue.shared
    @State private var reanalyzeSharesTrigger = false
    @State private var isExportingReport = false
    @State private var exportError: String?
    @AppStorage("reportTemplateID") private var reportTemplateID = ReportTemplateCatalog.plain.id
    /// Screenshots collected at the end and cross-linked, or set inline with
    /// the summary. Inline reads better when the pictures are good; at the
    /// end keeps the prose continuous and is what makes the links useful.
    @AppStorage("reportFiguresAtEnd") private var reportFiguresAtEnd = true
    @AppStorage("intelExportSummary") private var includeSummary = true
    @AppStorage("intelExportActions") private var includeActionItems = true
    @AppStorage("intelExportQuestions") private var includeQuestions = true
    @AppStorage("intelExportTopics") private var includeTopics = true
    @AppStorage("intelExportScreens") private var includeSharedScreens = true
    @AppStorage("intelExportTranscript") private var includeTranscript = false
    @AppStorage("intelExportDedupe") private var dedupeTranscript = true
    @AppStorage("intelExportFormat") private var intelExportFormat = IntelligenceExportFormat.pdf.rawValue
    @Query(sort: \Meeting.date, order: .reverse) private var library: [Meeting]
    @State private var showDossierSheet = false
    @State private var dossierRequest = DossierRequest()
    @State private var historyScope: InsightScope?
    @State private var analyzingScope: InsightScope?
    @State private var researchItem: ResearchItem?
    @Environment(MeetingFindController.self) private var meetingFind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        onSelectDestination?(.insights)
                    } label: {
                        Label {
                            Text("Meeting Intelligence")
                        } icon: {
                            Image(systemName: "brain")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .help("Open Insights — organize intelligence across meetings")

                    Spacer()

                    // Truncates first when the pane narrows — the Reanalyze
                    // controls must never be pushed off screen by a caption.
                    MeetingAIUsageCaption(meetingID: meeting.id, isAnalyzing: isThisMeetingBusy)
                        .layoutPriority(-1)

                    if meeting.status == .completed {
                        if isExportingReport {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Exporting…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            // Click exports with the last-used template; the
                            // arrow picks a different one — the same shape as
                            // the Reanalyze control beside it.
                            Menu {
                                Button("Create dossier…") {
                                    dossierRequest.onePagers = false
                                    showDossierSheet = true
                                }
                                Button("One-pagers for everyone") {
                                    var request = DossierRequest()
                                    request.onePagers = true
                                    request.includePromptPackage = true
                                    request.includeReport = false
                                    request.depth = .brief
                                    runDossier(request)
                                }
                                if DossierFacts.relatedMeetings(to: meeting, library: library).count > 1 {
                                    Button("Series dossier…") {
                                        dossierRequest.includeSeries = true
                                        dossierRequest.onePagers = false
                                        showDossierSheet = true
                                    }
                                }
                                Divider()
                                Toggle("All sections", isOn: allSectionsBinding)
                                Toggle("Summary", isOn: $includeSummary)
                                Toggle("Action items", isOn: $includeActionItems)
                                Toggle("Follow-up questions", isOn: $includeQuestions)
                                Toggle("Topics", isOn: $includeTopics)
                                Toggle("Shared screens", isOn: $includeSharedScreens)
                                Divider()
                                Toggle("Raw transcript", isOn: $includeTranscript)
                                Toggle("De-dupe transcript", isOn: $dedupeTranscript)
                                    .disabled(!includeTranscript)
                                Divider()
                                Picker("PDF theme", selection: $reportTemplateID) {
                                    ForEach(ReportTemplateCatalog.all) { template in
                                        Text("\(template.name)  (\(template.code))").tag(template.id)
                                    }
                                }
                                .pickerStyle(.inline)
                                Picker("Screenshots", selection: $reportFiguresAtEnd) {
                                    Text("Collected at the end").tag(true)
                                    Text("Inline with the summary").tag(false)
                                }
                                .pickerStyle(.inline)
                                Divider()
                                ForEach(IntelligenceExportFormat.allCases) { format in
                                    Button(format.menuTitle) {
                                        intelExportFormat = format.rawValue
                                        exportReport(format)
                                    }
                                }
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                            } primaryAction: {
                                exportReport(IntelligenceExportFormat(rawValue: intelExportFormat) ?? .pdf)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                            .help("Click: export in the last format. Arrow: dossier (chatbot pack, series, one-pagers) or the older single-file dump.")
                        }
                    }

                    if meeting.status == .completed && !meeting.segments.isEmpty {
                        if isThisMeetingBusy {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(busyLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    if reanalysisQueue.contains(meeting.id) {
                                        reanalysisQueue.cancelMeeting(meeting.id)
                                    } else {
                                        meeting.isAnalyzing = false
                                        meeting.analysisError = "Analysis canceled by user."
                                        analyzingScope = nil
                                        PersistenceGate.save(
                                            modelContext,
                                            site: "MeetingIntelligenceView.cancelAnalysis",
                                            meetingID: meeting.id
                                        )
                                    }
                                } label: {
                                    Label("Cancel", systemImage: "stop.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Cancel analysis for this meeting")
                            }
                        } else {
                            fullReanalyzeControl
                        }
                    }
                }
                .padding(.horizontal)

                if let generated = meeting.generatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !generated.isEmpty,
                   generated.caseInsensitiveCompare(meeting.title) != .orderedSame {
                    Text(generated)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .help("AI purpose title. The list still shows the calendar event name while this meeting is linked.")
                }

                if let error = exportError ?? meeting.analysisError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") {
                            exportError = nil
                            meeting.analysisError = nil
                        }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)
                }

                ScreenSharePlayerSection(
                    meeting: meeting,
                    pendingSeekTime: pendingSeekTime,
                    onPlayheadSegment: onPlayheadSegment,
                    reanalyzeSharesTrigger: $reanalyzeSharesTrigger
                )

                if let insight = meeting.latestInsight {
                    FollowUpQuestionsSection(
                        questions: insight.followUpQuestions,
                        onOpenWorkspace: { onSelectDestination?(.questions) },
                        reanalyzeControl: sectionControl(.followUps),
                        onDelete: { index in
                            let question = insight.followUpQuestions[index]
                            let key = Self.normalizeKey(question)
                            if !meeting.suppressedFollowUps.contains(key) {
                                meeting.suppressedFollowUps.append(key)
                            }
                            insight.followUpQuestions.remove(at: index)
                            saveInsight("deleteFollowUp")
                        },
                        onMove: { source, dest in
                            insight.followUpQuestions.move(fromOffsets: source, toOffset: dest)
                            saveInsight("reorderFollowUps")
                        },
                        onModify: { index, text in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            insight.followUpQuestions[index] = trimmed
                            saveInsight("modifyFollowUp")
                        },
                        onResearch: { text in
                            researchItem = ResearchItem(title: "Follow-up", text: text)
                        }
                    )
                    ActionItemsSection(
                        items: meeting.paneActionItems(),
                        onOpenWorkspace: { onSelectDestination?(.tasks) },
                        reanalyzeControl: sectionControl(.actionItems),
                        onDelete: { item in
                            let key = Self.normalizeKey(item.text)
                            if !meeting.suppressedActionItems.contains(key) {
                                meeting.suppressedActionItems.append(key)
                            }
                            modelContext.delete(item)
                            saveInsight("deleteActionItem")
                        },
                        onMove: { source, dest in
                            var items = meeting.paneActionItems()
                            items.move(fromOffsets: source, toOffset: dest)
                            for (index, item) in items.enumerated() {
                                item.sortIndex = index
                            }
                            saveInsight("reorderActionItems")
                        },
                        onModify: { item, text in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            item.text = trimmed
                            saveInsight("modifyActionItem")
                        },
                        onResearch: { item in
                            researchItem = ResearchItem(title: "Action item", text: item.text)
                        }
                    )
                    AISummarySection(
                        summary: insight.summary,
                        onOpenWorkspace: { onSelectDestination?(.summaries) },
                        reanalyzeControl: sectionControl(.summary),
                        onReplaceSummary: { text in
                            insight.summary = text
                            saveInsight("modifySummary")
                        },
                        onResearch: { text in
                            researchItem = ResearchItem(title: "Summary", text: text)
                        }
                    )
                    KnowledgeLinksSection(
                        topics: insight.topics,
                        meeting: meeting,
                        onOpenSegment: onOpenDialog,
                        reanalyzeControl: sectionControl(.topics),
                        onMove: { source, dest in
                            insight.topics.move(fromOffsets: source, toOffset: dest)
                            saveInsight("reorderTopics")
                        },
                        onDelete: { index in
                            insight.topics.remove(at: index)
                            saveInsight("deleteTopic")
                        },
                        onModify: { index, text in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            insight.topics[index] = trimmed
                            saveInsight("modifyTopic")
                        },
                        onResearch: { text in
                            researchItem = ResearchItem(title: "Topic", text: text)
                        }
                    )
                } else if meeting.isAnalyzing || isThisMeetingBusy {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(busyLabel == "Queued" ? "Queued for reanalysis..." : "Reanalyzing meeting...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    ContentUnavailableView(
                        "No Insights Yet",
                        systemImage: "brain",
                        description: Text("AI-powered insights will appear after recording")
                    )
                }
            }
            .padding(.vertical)
            .environment(\.meetingFindQuery, meetingFind.query)
        }
        .sheet(item: $researchItem) { item in
            InsightResearchSheet(title: item.title, itemText: item.text, meeting: meeting)
        }
        .sheet(isPresented: $showDossierSheet) {
            DossierComposerSheet(
                meeting: meeting,
                library: library,
                request: $dossierRequest,
                onExport: { runDossier($0) }
            )
        }
        .sheet(item: $historyScope) { scope in
            InsightHistorySheet(meeting: meeting, scope: scope) { insight in
                revertInsight(scope: scope, from: insight)
            }
        }
    }

    private var allSectionsBinding: Binding<Bool> {
        Binding(
            get: {
                includeSummary && includeActionItems && includeQuestions
                    && includeTopics && includeSharedScreens
            },
            set: { value in
                includeSummary = value
                includeActionItems = value
                includeQuestions = value
                includeTopics = value
                includeSharedScreens = value
            }
        )
    }

    private var currentExportSelection: IntelligenceExportSelection {
        IntelligenceExportSelection(
            includeSummary: includeSummary,
            includeActionItems: includeActionItems,
            includeQuestions: includeQuestions,
            includeTopics: includeTopics,
            includeSharedScreens: includeSharedScreens,
            includeTranscript: includeTranscript,
            dedupeTranscript: dedupeTranscript
        )
    }

    private func exportReport(_ format: IntelligenceExportFormat) {
        guard !isExportingReport else { return }
        isExportingReport = true
        exportError = nil
        Task { @MainActor in
            defer { isExportingReport = false }
            do {
                let template = ReportTemplateCatalog.template(id: reportTemplateID)
                if let url = try await ReportExportService.export(
                    for: meeting,
                    selection: currentExportSelection,
                    format: format,
                    template: template,
                    figuresAtEnd: reportFiguresAtEnd
                ) {
                    // Reveal rather than open: the user almost always wants to
                    // attach or send the file next, not read it in Preview.
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func runDossier(_ request: DossierRequest) {
        guard !isExportingReport else { return }
        isExportingReport = true
        exportError = nil
        Task { @MainActor in
            defer { isExportingReport = false }
            do {
                if let url = try await DossierPackageWriter.export(
                    meeting: meeting,
                    library: library,
                    request: request
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private var isThisMeetingBusy: Bool {
        meeting.isAnalyzing || reanalysisQueue.contains(meeting.id)
    }

    private var busyLabel: String {
        if let analyzingScope {
            return analyzingScope == .full ? "Analyzing..." : "Deep \(analyzingScope.label)…"
        }
        if reanalysisQueue.currentID == meeting.id || meeting.isAnalyzing {
            return "Analyzing..."
        }
        return "Queued"
    }

    private var fullReanalyzeControl: InsightReanalyzeControl {
        insightControl(scope: .full, extras: fullExtras)
    }

    private var fullExtras: [InsightReanalyzeExtra] {
        var extras: [InsightReanalyzeExtra] = []
        if !meeting.screenFrames.isEmpty {
            extras.append(
                InsightReanalyzeExtra(
                    id: "screens",
                    title: "Re-analyze screen shares",
                    systemImage: "rectangle.dashed.badge.record"
                ) { reanalyzeSharesTrigger = true }
            )
        }
        extras.append(
            InsightReanalyzeExtra(
                id: "retranscribe",
                title: "Re-transcribe with large-v3",
                systemImage: "waveform.badge.checkmark"
            ) { ReProcessingQueue.shared.enqueue(meetingID: meeting.id) }
        )
        return extras
    }

    private func saveInsight(_ site: String) {
        PersistenceGate.save(modelContext, site: "MeetingIntelligenceView.\(site)", meetingID: meeting.id)
    }

    private func sectionControl(_ scope: InsightScope) -> InsightReanalyzeControl {
        insightControl(scope: scope, extras: [])
    }

    private func insightControl(scope: InsightScope, extras: [InsightReanalyzeExtra]) -> InsightReanalyzeControl {
        InsightReanalyzeControl(
            title: "Reanalyze",
            scope: scope,
            isBusy: analyzingScope == scope,
            canRevert: InsightRevision.canRevert(meeting),
            extras: extras,
            onRun: { depth in runInsight(scope: scope, depth: depth) },
            onRevert: { revertInsight(scope: scope) },
            onViewLog: { historyScope = scope }
        )
    }

    private func runInsight(scope: InsightScope, depth: InsightDepth) {
        if scope == .full, depth == .standard {
            reanalysisQueue.enqueueEligible(in: modelContext, restrictingTo: [meeting.id])
            return
        }
        guard !isThisMeetingBusy else { return }
        analyzingScope = scope
        meeting.isAnalyzing = true
        meeting.analysisError = nil
        Task { @MainActor in
            defer {
                meeting.isAnalyzing = false
                analyzingScope = nil
            }
            do {
                guard let client = try await AIClientFactory.makeClient() else {
                    meeting.analysisError = MeetingReanalysis.Failure.notConfigured.localizedDescription
                    return
                }
                try await MeetingReanalysis.run(
                    meeting: meeting,
                    client: client,
                    context: modelContext,
                    scope: scope,
                    depth: depth
                )
            } catch {
                meeting.analysisError = error.localizedDescription
            }
        }
    }

    private func revertInsight(scope: InsightScope, from insight: MeetingInsight? = nil) {
        do {
            try MeetingReanalysis.revert(
                meeting: meeting,
                scope: scope,
                context: modelContext,
                from: insight
            )
        } catch {
            meeting.analysisError = error.localizedDescription
        }
    }

    /// Normalized key for action-item deduping: lowercased, whitespace-collapsed,
    /// trailing punctuation stripped.
    private static func normalizeKey(_ text: String) -> String {
        MeetingReanalysis.normalizeKey(text)
    }
}

private struct ResearchItem: Identifiable {
    var id = UUID()
    var title: String
    var text: String
}

struct LiveMeetingIntelligenceView: View {
    let summary: String
    let actionItems: [ActionItem]
    let followUpQuestions: [String]
    let topics: [String]
    var aiActivityState: RecordingViewModel.AIActivityState = .idle
    var shareObservations: [ScreenFrameAnalysisService.FrameObservation] = []
    var isCapturingShare: Bool = false
    /// The in-progress meeting, when there is one. The screenshot player
    /// reads frames from the model; without it a live recording can only
    /// show observations as text.
    var meeting: Meeting?

    private var hasResults: Bool {
        !summary.isEmpty || !visibleLiveActionItems.isEmpty
    }

    private var visibleLiveActionItems: [ActionItem] {
        guard let meeting else { return actionItems }
        let roster = MeetingRoster.snapshot(for: meeting)
        return actionItems.filter {
            AIIntelligenceService.keepsActionItem(
                assignee: $0.displayAssignee ?? $0.assignee,
                roster: roster
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label {
                    Text("Meeting Intelligence")
                } icon: {
                    Image(systemName: "brain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .font(.headline)
                .padding(.horizontal)

                if hasResults {
                    // Show a status line for subsequent cycles
                    if case .waiting(let secs) = aiActivityState {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text("Next analysis in \(secs)s")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    } else if case .analyzing = aiActivityState {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Updating analysis...")
                                .font(.caption)
                        }
                        .foregroundStyle(.purple)
                        .padding(.horizontal)
                    }
                }

                if !followUpQuestions.isEmpty {
                    FollowUpQuestionsSection(questions: followUpQuestions)
                }

                if !visibleLiveActionItems.isEmpty {
                    LiveActionItemsSection(items: visibleLiveActionItems)
                }

                if !summary.isEmpty {
                    AISummarySection(summary: summary)
                }

                if let meeting, !meeting.screenFrames.isEmpty {
                    ScreenSharePlayerSection(meeting: meeting, pendingSeekTime: .constant(nil))
                } else if !shareObservations.isEmpty {
                    LiveSharedContentSection(
                        observations: shareObservations,
                        isCapturing: isCapturingShare
                    )
                }

                if !topics.isEmpty {
                    KnowledgeLinksSection(topics: topics)
                }

                if !hasResults {
                    switch aiActivityState {
                    case .waiting(let secs):
                        ContentUnavailableView {
                            Label("Waiting to Analyze", systemImage: "brain")
                        } description: {
                            Text("First analysis in \(secs)s...")
                        }
                    case .analyzing:
                        ContentUnavailableView {
                            Label("Analyzing Transcript", systemImage: "brain")
                        } description: {
                            Text("Processing your meeting transcript...")
                        }
                    case .idle:
                        ContentUnavailableView(
                            "Waiting...",
                            systemImage: "brain",
                            description: Text("AI insights will appear once analysis begins")
                        )
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

/// "AI: 142k in / 9k out (~$0.31)" — the meeting's usage-ledger rollup,
/// with the per-purpose breakdown in the tooltip. Hidden until the ledger
/// has events for this meeting.
struct MeetingAIUsageCaption: View {
    let meetingID: UUID
    /// Re-fetches when an analysis finishes so the number stays current.
    var isAnalyzing: Bool = false
    @Environment(\.modelContext) private var modelContext
    @State private var totals: AIUsageAggregator.Totals?
    @State private var breakdown: [AIUsageAggregator.GroupRollup] = []

    var body: some View {
        Group {
            if let totals, totals.totalInputSideTokens + totals.outputTokens > 0 {
                Text(caption(totals))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(tooltip)
            }
        }
        .task(id: "\(meetingID)-\(isAnalyzing)") { refresh() }
    }

    private func refresh() {
        let id: UUID? = meetingID
        let descriptor = FetchDescriptor<AIUsageEvent>(predicate: #Predicate { $0.meetingID == id })
        let events = (try? modelContext.fetch(descriptor)) ?? []
        let lines = events.map(AIUsageAggregator.Line.init(event:))
        let settings = TrajectorSettings.load()
        totals = AIUsageAggregator.totals(lines, settings: settings)
        breakdown = AIUsageAggregator.byGroup(lines, settings: settings)
    }

    private func caption(_ totals: AIUsageAggregator.Totals) -> String {
        var text = "AI: \(AIUsageAggregator.compactTokens(totals.totalInputSideTokens)) in / \(AIUsageAggregator.compactTokens(totals.outputTokens)) out"
        if totals.estimatedCost > 0 {
            let approx = totals.pricedEverything ? "~" : ">"
            text += String(format: " (%@$%.2f)", approx, totals.estimatedCost)
        }
        return text
    }

    private var tooltip: String {
        var lines = breakdown.map { rollup in
            var line = "\(rollup.group.displayName): \(AIUsageAggregator.compactTokens(rollup.totals.totalInputSideTokens)) in / \(AIUsageAggregator.compactTokens(rollup.totals.outputTokens)) out"
            if rollup.totals.estimatedCost > 0 {
                line += String(format: " (~$%.2f)", rollup.totals.estimatedCost)
            }
            return line
        }
        if totals?.pricedEverything == false {
            lines.append("Some calls used a model without a known price — cost shown is a lower bound.")
        }
        return lines.joined(separator: "\n")
    }
}
