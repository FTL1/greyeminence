import SwiftUI
import SwiftData

struct EditableTranscriptSegmentRow: View {
    @Bindable var segment: TranscriptSegment
    var hasNext: Bool
    var isSelected: Bool = false
    var onDelete: (() -> Void)?
    var onMergeWithNext: (() -> Void)?
    var onSplit: ((String, String) -> Void)?
    var onSplitMeeting: (() -> Void)?
    var onChangeSpeakerForAll: ((Speaker) -> Void)?
    var onToggleSelection: (() -> Void)?
    /// When set (meeting has captured screen frames), the timestamp becomes
    /// a click target that seeks the screen-share player to this moment.
    var onSeekToTime: ((TimeInterval) -> Void)?
    var onPlayLine: (() -> Void)?
    var isPlayingLine: Bool = false
    var speakerActions: SpeakerBadgeActions = SpeakerBadgeActions()
    var highlightQuery: String = ""

    @State private var isEditingText = false
    @State private var editedText: String = ""
    @State private var showContactPicker = false
    @State private var showSpeakerRename = false
    @State private var speakerName: String = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Selection checkbox (visible when multi-select is active)
            if onToggleSelection != nil {
                Button {
                    onToggleSelection?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            // Timestamp — clickable when a screen-share player is present
            if let onSeekToTime {
                Button {
                    onSeekToTime(segment.startTime)
                } label: {
                    Text(segment.formattedTimestamp)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("Show the shared screen at this moment")
            } else {
                Text(segment.formattedTimestamp)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Speaker badge
            speakerBadgeView

            if onPlayLine != nil {
                Button {
                    onPlayLine?()
                } label: {
                    Image(systemName: isPlayingLine ? "stop.fill" : "play.fill")
                        .font(.caption2)
                        .foregroundStyle(isPlayingLine ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPlayingLine ? "Stop this line" : "Play the audio for this line")
            } else if segment.isEdited {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Edited")
            }

            // Text content
            textContentView

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        )
        .contextMenu { contextMenuItems }
        .confirmationDialog(
            "Delete this segment?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("\"\(segment.text.prefix(80))...\"")
        }
    }

    // MARK: - Speaker Badge

    @ViewBuilder
    private var speakerBadgeView: some View {
        SpeakerBadge(
            speaker: segment.speaker,
            actions: mergedSpeakerActions
        )
        .popover(isPresented: $showContactPicker) {
            ContactPicker(excludedContacts: []) { contact in
                changeSpeakerForAll(to: .other(contact.name))
                showContactPicker = false
            }
        }
        .popover(isPresented: $showSpeakerRename) {
            speakerRenamePopover
        }
    }

    /// Editor-specific items (this-one vs all) sit behind the shared speaker menu.
    private var mergedSpeakerActions: SpeakerBadgeActions {
        var merged = speakerActions
        if merged.onRename == nil {
            merged.onRename = { name, _ in
                speakerName = name
                commitSpeakerRename(applyToAll: true)
            }
        }
        if merged.onAddToContacts == nil {
            merged.onAddToContacts = { showContactPicker = true }
        }
        if merged.onSetAsMe == nil, !segment.speaker.isMe {
            merged.onSetAsMe = { changeSpeakerForAll(to: Speaker.resolvedMe()) }
        }
        return merged
    }

    // MARK: - Speaker Rename Popover

    private var speakerRenamePopover: some View {
        VStack(spacing: 8) {
            Text("Rename Speaker")
                .font(.headline)

            TextField("Speaker name", text: $speakerName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSpeakerRename(applyToAll: false) }

            HStack {
                Button("Cancel") {
                    showSpeakerRename = false
                }
                Spacer()
                Button("This One") {
                    commitSpeakerRename(applyToAll: false)
                }
                Button("All From This Speaker") {
                    commitSpeakerRename(applyToAll: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Text Content

    @ViewBuilder
    private var textContentView: some View {
        if isEditingText {
            TextField("", text: $editedText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitEdit() }
                .onExitCommand { cancelEdit() }
                .onAppear {
                    // Auto-focus handled by SwiftUI
                }
        } else {
            Text(TranscriptTextHighlight.attributed(segment.text, query: highlightQuery))
                .font(.body)
                .textSelection(.enabled)
                .onTapGesture(count: 2) {
                    startEditing()
                }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Edit Text") {
            startEditing()
        }
        .keyboardShortcut(.return, modifiers: [])

        Divider()

        if hasNext {
            Button("Merge with Next Segment") {
                onMergeWithNext?()
            }
        }

        Button("Split Segment...") {
            startEditing()
        }

        Divider()

        Button("Split Into New Meeting") {
            onSplitMeeting?()
        }

        Divider()

        Button("Delete Segment", role: .destructive) {
            showDeleteConfirmation = true
        }

        if segment.isEdited {
            Divider()
            Button("Revert to Original") {
                revertToOriginal()
            }
        }
    }

    // MARK: - Text Editing

    private func startEditing() {
        editedText = segment.text
        isEditingText = true
    }

    private func commitEdit() {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != segment.text else {
            isEditingText = false
            return
        }

        if !segment.isEdited {
            segment.originalText = segment.text
            segment.originalSpeakerData = segment.speakerData
        }
        segment.text = trimmed
        segment.isEdited = true
        isEditingText = false
    }

    private func cancelEdit() {
        isEditingText = false
    }

    // MARK: - Revert

    private func revertToOriginal() {
        guard segment.isEdited else { return }
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

    // MARK: - Speaker Changes

    private func changeSpeaker(to newSpeaker: Speaker) {
        if !segment.isEdited {
            segment.originalText = segment.text
            segment.originalSpeakerData = segment.speakerData
        }
        segment.speaker = newSpeaker
        segment.isEdited = true
    }

    private func changeSpeakerForAll(to newSpeaker: Speaker) {
        onChangeSpeakerForAll?(newSpeaker)
    }

    private func commitSpeakerRename(applyToAll: Bool) {
        let trimmed = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showSpeakerRename = false
            return
        }

        let newSpeaker = Speaker.renamed(from: segment.speaker, displayName: trimmed)

        if applyToAll {
            changeSpeakerForAll(to: newSpeaker)
        } else {
            changeSpeaker(to: newSpeaker)
        }
        showSpeakerRename = false
    }
}
