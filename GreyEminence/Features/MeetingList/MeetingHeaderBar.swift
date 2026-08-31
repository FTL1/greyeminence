import SwiftUI
import SwiftData
import AppKit

struct MeetingHeaderBar: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @Bindable private var reProcessingQueue: ReProcessingQueue = .shared
    @AppStorage("developerToolsEnabled") private var developerToolsEnabled = false
    @AppStorage("transcriptExportFormat") private var transcriptExportFormat = TranscriptExportFormat.txt.rawValue
    @State private var isEditingTitle = false
    @State private var exportState: ExportState = .idle
    @State private var showTranscriptSavePanel = false
    @State private var isExportingTranscript = false
    /// Coverage of this meeting in the embedding store. `nil` = not yet
    /// checked (don't render the Index button until we know), `0` = missing,
    /// `>0` = covered. Refreshed when the meeting changes and after an
    /// on-demand index pass completes.
    @State private var indexedRecordCount: Int?
    @State private var isIndexingForSearch = false
    @Environment(MeetingFindController.self) private var meetingFind
    @FocusState private var findFocused: Bool
    @State private var findExpanded = false

    private enum ExportState: Equatable {
        case idle, success, error(String)
    }

    private var editedCount: Int {
        // Allocation-free scan — this is read on every body evaluation
        // (including each frame of a window-resize drag), so avoid building
        // and discarding a filtered array of up to a few thousand segments.
        meeting.segments.reduce(into: 0) { count, segment in
            if segment.isEdited { count += 1 }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                MeetingTitleLabel(
                    meeting: meeting,
                    isEditing: $isEditingTitle,
                    font: .title2,
                    weight: .bold,
                    singleClickStartsEditing: true
                )

                if developerToolsEnabled {
                    HStack(spacing: 4) {
                        Text(meeting.id.uuidString)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                        CopyButton(content: meeting.id.uuidString, help: "Copy meeting ID", font: .caption2)
                    }
                }

                // Wrapping layout — badges and buttons flow to the next line
                // in narrow windows instead of pushing each other off screen.
                FlowLayout(spacing: 10) {
                    Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Label(meeting.formattedDuration, systemImage: "clock")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Label("\(meeting.segments.count) segments", systemImage: "text.bubble")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    MeetingCalendarLinkMenu(meeting: meeting)
                    if editedCount > 0 {
                        Label("\(editedCount) edited", systemImage: "pencil")
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let raw = meeting.reProcessingState,
                       let state = ReProcessingState(rawValue: raw) {
                        HStack(spacing: 4) {
                            StatusPill(label: pillLabel(state: state), tint: state.tint)
                            if state == .failed, let reason = meeting.reProcessingError, !reason.isEmpty {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help(reason)
                            }
                            if state == .failed {
                                Button {
                                    reProcessingQueue.enqueue(meetingID: meeting.id)
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Retry re-transcription with WhisperKit large-v3")
                            } else {
                                Button {
                                    reProcessingQueue.cancelCurrent(meetingID: meeting.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Cancel re-transcription")
                            }
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    } else if meeting.transcriptionModel?.hasPrefix("whisperkit-large-v3") == true {
                        StatusPill(label: "large-v3", tint: .green)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if meeting.status == .completed && !meeting.segments.isEmpty {
                        Button {
                            reProcessingQueue.enqueue(meetingID: meeting.id)
                        } label: {
                            Label("Upgrade to large-v3", systemImage: "waveform.badge.checkmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .helpTip(.meetingUpgradeV3)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    // "Index for search" — appears only when this meeting has
                    // segments but no embedding records. The post-recording
                    // index pass can fail silently (crash, force quit) and
                    // leave the meeting invisible to Ask until the user runs
                    // a full "Reindex all"; this button is the per-meeting
                    // recovery, paired with the launch-time backfill scan.
                    if shouldShowIndexButton {
                        if isIndexingForSearch {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("Indexing…").font(.caption2)
                            }
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        } else {
                            Button {
                                Task { await indexThisMeetingForSearch() }
                            } label: {
                                Label("Index for search", systemImage: "magnifyingglass.circle")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .helpTip(.meetingIndexSearch)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if meeting.status == .completed {
                    MeetingAttendeesRow(meeting: meeting)
                }

                meetingFindRow
            }

            Spacer()

            ViewThatFits(in: .horizontal) {
                actionButtons(iconOnly: false)
                actionButtons(iconOnly: true)
            }
        }
        .padding()
        .onChange(of: meetingFind.focusNonce) { _, _ in
            findExpanded = true
            findFocused = true
        }
        .onChange(of: showTranscriptSavePanel) { _, show in
            guard show else { return }
            showTranscriptSavePanel = false
            DispatchQueue.main.async {
                saveTranscriptFile()
            }
        }
        .task(id: meeting.id) {
            refreshIndexedRecordCount()
        }
    }

    private var shouldShowIndexButton: Bool {
        guard meeting.status == .completed,
              !meeting.segments.isEmpty,
              meeting.reProcessingState == nil,
              let count = indexedRecordCount else { return false }
        return count == 0
    }

    private func refreshIndexedRecordCount() {
        indexedRecordCount = EmbeddingStore.shared?.recordCount(forMeetingID: meeting.id)
    }

    private func indexThisMeetingForSearch() async {
        isIndexingForSearch = true
        defer { isIndexingForSearch = false }
        let count = await EmbeddingBackfillService.indexSingleMeeting(meeting)
        indexedRecordCount = count
    }

    private var exportHelpText: String {
        switch exportState {
        case .idle: "Sync to Obsidian vault"
        case .success: "Successfully synced to Obsidian"
        case .error(let msg): msg
        }
    }

    @ViewBuilder
    private var meetingFindRow: some View {
        ViewThatFits(in: .horizontal) {
            meetingFindField(compact: false)
            if findExpanded || !meetingFind.query.isEmpty {
                meetingFindField(compact: true)
            } else {
                Button {
                    findExpanded = true
                    meetingFind.requestFocus()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .helpTip(.meetingFind)
            }
        }
        .padding(.top, 6)
    }

    private var meetingFindQueryBinding: Binding<String> {
        Binding(get: { meetingFind.query }, set: { meetingFind.query = $0 })
    }

    private var meetingFindTranscriptBinding: Binding<Bool> {
        Binding(get: { meetingFind.includeTranscript }, set: { meetingFind.includeTranscript = $0 })
    }

    private func meetingFindField(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search this meeting", text: meetingFindQueryBinding)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { meetingFind.nextTranscriptMatch() }
            Toggle("Transcript", isOn: meetingFindTranscriptBinding)
                .toggleStyle(.checkbox)
                .helpTip(.meetingFindTranscript)
            if !meetingFind.query.isEmpty {
                Button("Clear") {
                    meetingFind.query = ""
                    findExpanded = false
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(minWidth: compact ? 220 : 320, maxWidth: 520)
    }

    @ViewBuilder
    private func actionButtons(iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                do {
                    _ = try ObsidianExportService.export(meeting: meeting)
                    PersistenceGate.save(modelContext, site: "MeetingDetailView.obsidianExport", meetingID: meeting.id)
                    exportState = .success
                } catch {
                    exportState = .error(error.localizedDescription)
                }
            } label: {
                actionLabel(
                    title: exportTitle,
                    systemImage: exportIcon,
                    iconOnly: iconOnly
                )
            }
            .disabled(UserDefaults.standard.string(forKey: "obsidianVaultPath")?.isEmpty != false)
            .keyboardShortcut("e", modifiers: .command)
            .help(exportHelpText)

            exportTranscriptButton(iconOnly: iconOnly)

            if developerToolsEnabled {
                Button {
                    showTranscriptSavePanel = true
                } label: {
                    actionLabel(title: "Save Transcript", systemImage: "doc.badge.arrow.up", iconOnly: iconOnly)
                }
                .help("Save .getranscript.json for rubric testing")
            }

            statusBadge
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func exportTranscriptButton(iconOnly: Bool) -> some View {
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
                    copyFullTranscript()
                }
                .disabled(meeting.segments.isEmpty)
            } label: {
                if iconOnly {
                    Image(systemName: "doc.plaintext")
                } else {
                    Label("Transcript", systemImage: "doc.plaintext")
                        .font(.caption)
                }
            } primaryAction: {
                exportFullTranscript(format)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .disabled(meeting.segments.isEmpty)
            .help("Click: export the full transcript as \(format.menuTitle). Arrow: choose a format or copy.")
        }
    }

    private func exportFullTranscript(_ format: TranscriptExportFormat) {
        guard !isExportingTranscript else { return }
        isExportingTranscript = true
        Task { @MainActor in
            defer { isExportingTranscript = false }
            _ = await TranscriptExportService.presentSavePanel(for: meeting, format: format)
        }
    }

    private func copyFullTranscript() {
        let text = TranscriptExportService.clipboardText(for: meeting)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        TransientActivityCoordinator.shared.flash("Full transcript copied")
    }

    @ViewBuilder
    private func actionLabel(title: String, systemImage: String, iconOnly: Bool) -> some View {
        if iconOnly {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var exportTitle: String {
        switch exportState {
        case .idle: "Sync to Obsidian"
        case .success: "Synced to Obsidian"
        case .error: "Sync Failed"
        }
    }

    private var exportIcon: String {
        switch exportState {
        case .idle: "arrow.up.doc"
        case .success: "checkmark.circle.fill"
        case .error: "exclamation.triangle.fill"
        }
    }

    private func pillLabel(state: ReProcessingState) -> String {
        if state == .transcribing,
           let job = reProcessingQueue.current,
           job.id == meeting.id,
           job.chunksTotal > 0 {
            return "\(state.label) \(job.chunksDone)/\(job.chunksTotal)"
        }
        return state.label
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color) = switch meeting.status {
        case .recording: ("Recording", Color.red)
        case .paused: ("Paused", Color.orange)
        case .completed: ("Completed", Color.green)
        }

        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func saveTranscriptFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(meeting.title).getranscript.json"
        panel.title = "Save Transcript"
        panel.message = "Save this transcript for rubric testing"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = TranscriptFile.from(meeting: meeting)
            try file.write(to: url)
        } catch {
            LogManager.shared.log("Transcript save failed: \(error.localizedDescription)", category: .general, level: .error)
        }
    }
}
