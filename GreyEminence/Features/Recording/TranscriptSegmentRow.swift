import SwiftUI
import AppKit

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    var confidence: Float?
    var speakerActions: SpeakerBadgeActions = SpeakerBadgeActions()
    var highlightQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header line: speaker · timestamp · flags. Keeping these on their own
            // row lets the spoken text use the full width below instead of being
            // squeezed into the column to the right of the badge.
            HStack(spacing: 6) {
                SpeakerBadge(speaker: segment.speaker, actions: speakerActions)

                Text(segment.formattedTimestamp)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)

                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Edited")
                }

                // Confidence dot (only shown for live, low-confidence segments)
                if let conf = confidence, conf < 0.6 {
                    Circle()
                        .fill(conf < 0.3 ? Color.red : Color.yellow)
                        .frame(width: 6, height: 6)
                        .help(String(format: "Confidence: %.0f%%", conf * 100))
                }

                Spacer(minLength: 0)
            }

            // Spoken text — full width, always wraps (never truncated/clipped).
            Text(TranscriptTextHighlight.attributed(segment.text, query: highlightQuery))
                .font(.body)
                .foregroundStyle(segment.isFinal ? .primary : .secondary)
                .italic(!segment.isFinal)
                .textSelection(.enabled)
                .opacity(confidenceOpacity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .opacity(segment.isFinal ? 1.0 : 0.7)
    }

    private var confidenceOpacity: Double {
        guard let conf = confidence else { return 1.0 }
        if conf >= 0.6 { return 1.0 }
        if conf >= 0.3 { return 0.8 }
        return 0.6
    }
}

/// Actions for one speaker badge. Double-click renames. Right-click opens
/// the speaker menu (hide/show lives there so a rename tap cannot bury them).
struct SpeakerBadgeActions {
    var talkSharePercent: Int?
    var color: Color?
    var colorSlot: Int?
    var isColorLocked: Bool = false
    var onPickColor: ((Int, Bool) -> Void)?
    var isHidden: Bool = false
    var onToggleHidden: (() -> Void)?
    var onRename: ((String, Bool) -> Void)?
    var onSearch: ((String) -> Void)?
    var searchQuery: String = ""
    /// Host the menu on the transcript pane, not the badge. Search used
    /// to mutate the LazyVStack (isolate + filter) and destroy the badge
    /// that presented the popover after one character.
    var onOpenMenu: (() -> Void)?
    var searchMatchCount: Int = 0
    /// 0-based index into the current match list.
    var searchMatchIndex: Int = 0
    var onJumpToMatch: ((Int) -> Void)?
    var onToggleIsolate: (() -> Void)?
    var isIsolated: Bool = false
    var onAddToContacts: (() -> Void)?
    var onSaveAsNewContact: (() -> Void)?
    var speakerLinks: SpeakerLinkGroups = .empty
    var onSelectSpeakerLink: ((SpeakerLinkPerson) -> Void)?
    var onEnrollVoicePrint: (() -> Void)?
    var voicePrintState: VoicePrintUIState = .ready(onto: nil)
    var onRecoverSpeakers: (() -> Void)?
    var isRecoveringSpeakers: Bool = false
    var onSetAsMe: (() -> Void)?

    var hasMenu: Bool {
        onOpenMenu != nil
            || talkSharePercent != nil
            || onRename != nil
            || onSearch != nil
            || onToggleIsolate != nil
            || onAddToContacts != nil
            || onSaveAsNewContact != nil
            || onSelectSpeakerLink != nil
            || onEnrollVoicePrint != nil
            || onRecoverSpeakers != nil
            || onSetAsMe != nil
            || onToggleHidden != nil
            || onPickColor != nil
    }
}

struct SpeakerBadge: View {
    let speaker: Speaker
    var actions: SpeakerBadgeActions = SpeakerBadgeActions()

    @State private var isEditing = false
    @State private var showMenu = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .frame(width: 140)
                    .focused($fieldFocused)
                    .onSubmit { commit(saveAsDefault: false) }
                    .onExitCommand { cancel() }
                    .onAppear { fieldFocused = true }
            } else {
                Text(speaker.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(badgeColor)
                    .onTapGesture(count: 2) { beginEdit() }
                    .overlay {
                        if actions.hasMenu {
                            RightMouseDownCatcher {
                                if let onOpenMenu = actions.onOpenMenu {
                                    onOpenMenu()
                                } else {
                                    showMenu = true
                                }
                            }
                        }
                    }
                    .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                        SpeakerActionPopover(
                            speaker: speaker,
                            actions: actions,
                            onBeginInlineRename: {
                                showMenu = false
                                beginEdit()
                            },
                            onClose: { showMenu = false }
                        )
                    }
                    .help(actions.hasMenu
                          ? "Double-click to rename. Right-click to hide, search, or link a contact."
                          : "")
            }
        }
    }

    private var badgeColor: Color {
        actions.color ?? speaker.color
    }

    private func beginEdit() {
        guard actions.onRename != nil else { return }
        draft = speaker.displayName
        isEditing = true
    }

    private func commit(saveAsDefault: Bool) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        fieldFocused = false
        guard !trimmed.isEmpty else { return }
        actions.onRename?(trimmed, saveAsDefault)
    }

    private func cancel() {
        isEditing = false
        fieldFocused = false
    }
}

/// Right-click menu for one speaker: talk-time share, rename, search,
/// isolate, and contact / voice-print hooks.
struct SpeakerActionPopover: View {
    let speaker: Speaker
    var actions: SpeakerBadgeActions
    var onBeginInlineRename: () -> Void
    var onClose: (() -> Void)? = nil

    @State private var renameDraft: String = ""
    @State private var searchDraft: String = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(speaker.color)
                    .frame(width: 8, height: 8)
                Text(speaker.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                if let percent = actions.talkSharePercent {
                    Text("\(percent)%")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(speaker.color)
                }
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }
            if let percent = actions.talkSharePercent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("of talking time in this transcript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(percent), total: 100)
                        .tint(speaker.color)
                }
            }

            if actions.onRename != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rename")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TextField("Display name", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submitRename(saveAsDefault: false) }
                        Button("Apply") { submitRename(saveAsDefault: false) }
                            .controlSize(.small)
                    }
                    if speaker.isMe {
                        Button("Save as default name") {
                            submitRename(saveAsDefault: true)
                        }
                        .controlSize(.small)
                    }
                    if let setAsMe = actions.onSetAsMe {
                        Button("Set as Me") {
                            setAsMe()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if actions.onPickColor != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(SpeakerPalette.swatches) { swatch in
                            Button {
                                actions.onPickColor?(swatch.slot, true)
                            } label: {
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        if actions.colorSlot == swatch.slot {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(swatch.name)
                        }
                    }
                    Button(actions.isColorLocked ? "Unlock color" : "Lock this color") {
                        let slot = actions.colorSlot ?? SpeakerPalette.hashSlot(for: speaker.displayName)
                        actions.onPickColor?(slot, !actions.isColorLocked)
                    }
                    .controlSize(.small)
                    .help("Locked colors stay on this person in later meetings.")
                }
            }

            if actions.onSearch != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search this speaker's comments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Find in their lines", text: $searchDraft)
                            .textFieldStyle(.plain)
                            .onSubmit { actions.onSearch?(searchDraft) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: searchDraft) { _, query in
                        searchTask?.cancel()
                        searchTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            guard !Task.isCancelled else { return }
                            actions.onSearch?(query)
                        }
                    }
                    .onDisappear { searchTask?.cancel() }

                    let needle = searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if needle.isEmpty {
                        Text("Type a word or phrase. Matches stay highlighted in the transcript.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if actions.searchMatchCount == 0 {
                        Text("No matches for “\(needle)”")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 8) {
                            Text(actions.searchMatchCount == 1
                                 ? "1 match"
                                 : "\(actions.searchMatchIndex + 1) of \(actions.searchMatchCount) matches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if actions.searchMatchCount > 1 {
                                Button {
                                    actions.onJumpToMatch?(-1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .help("Previous match")
                                Button {
                                    actions.onJumpToMatch?(1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .help("Next match")
                            }
                        }
                    }
                }
            }

            if actions.onToggleHidden != nil {
                Button {
                    actions.onToggleHidden?()
                    onClose?()
                } label: {
                    Label(
                        actions.isHidden ? "Show this speaker" : "Hide this speaker",
                        systemImage: actions.isHidden ? "eye" : "eye.slash"
                    )
                }
                .buttonStyle(.plain)
            }



            if actions.onRecoverSpeakers != nil {
                Divider()
                Button {
                    actions.onRecoverSpeakers?()
                } label: {
                    if actions.isRecoveringSpeakers {
                        Label("Recovering speakers…", systemImage: "waveform.badge.magnifyingglass")
                    } else {
                        Label("Recover guest-1, guest-2… from audio", systemImage: "person.3.sequence")
                    }
                }
                .buttonStyle(.plain)
                .disabled(actions.isRecoveringSpeakers)
                Text("This recording lumped every remote person together. Recovery listens to the saved audio and splits them into guest-1, guest-2, guest-3…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if actions.onSelectSpeakerLink != nil
                || actions.onAddToContacts != nil
                || actions.onSaveAsNewContact != nil
                || actions.onEnrollVoicePrint != nil {
                Divider()
                speakerLinkSection
                voicePrintSection
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            renameDraft = speaker.displayName == Speaker.defaultMeLabel ? "" : speaker.displayName
            searchDraft = actions.searchQuery
        }
    }

    private func submitRename(saveAsDefault: Bool) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        actions.onRename?(trimmed, saveAsDefault)
    }

    @ViewBuilder
    private var speakerLinkSection: some View {
        Text("Speakers")
            .font(.caption)
            .foregroundStyle(.secondary)
        if !actions.speakerLinks.thisMeeting.isEmpty || !actions.speakerLinks.priorSpeakers.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !actions.speakerLinks.thisMeeting.isEmpty {
                        Text("This meeting")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        ForEach(Array(actions.speakerLinks.thisMeeting.prefix(8))) { person in
                            speakerLinkRow(person)
                        }
                    }
                    if !actions.speakerLinks.priorSpeakers.isEmpty {
                        Menu("Prior speakers") {
                            ForEach(actions.speakerLinks.priorSpeakers) { person in
                                Button(person.name) {
                                    guard !person.isThisVoice else { return }
                                    actions.onSelectSpeakerLink?(person)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 168)
        }
        if actions.onAddToContacts != nil {
            Button {
                actions.onAddToContacts?()
            } label: {
                Label("Link other contact…", systemImage: "link")
            }
            .buttonStyle(.plain)
        }
        if let save = actions.onSaveAsNewContact {
            Button {
                save()
            } label: {
                Label("Save as new contact", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .disabled(speaker.displayNameIsPlaceholder)
        }
    }

    private func speakerLinkRow(_ person: SpeakerLinkPerson) -> some View {
        Button {
            guard !person.isThisVoice else { return }
            actions.onSelectSpeakerLink?(person)
        } label: {
            HStack(spacing: 8) {
                Text(initials(for: person.name))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(speaker.color.opacity(person.isThisVoice ? 1 : 0.7), in: Circle())
                Text(person.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if person.hasVoicePrint {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help("Voice print enrolled")
                }
                Spacer(minLength: 0)
                if person.isThisVoice {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speaker.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(person.isThisVoice
              ? "This voice is already \(person.name)"
              : "Tag this voice as \(person.name)")
    }

    @ViewBuilder
    private var voicePrintSection: some View {
        if actions.onEnrollVoicePrint != nil {
            Divider()
            Button {
                actions.onEnrollVoicePrint?()
            } label: {
                switch actions.voicePrintState {
                case .working:
                    Label("Enrolling voice print…", systemImage: "waveform")
                case .enrolled:
                    Label("Update voice print", systemImage: "waveform")
                default:
                    Label("Enroll voice print", systemImage: "waveform")
                }
            }
            .buttonStyle(.plain)
            .disabled({
                if case .working = actions.voicePrintState { return true }
                if case .needsPerson = actions.voicePrintState { return true }
                return false
            }())
            voicePrintCaption
        }
    }

    @ViewBuilder
    private var voicePrintCaption: some View {
        switch actions.voicePrintState {
        case .ready(let onto):
            Text(onto.map { "Saves this voice to \($0). Later meetings will tag matching speech as \($0)." }
                 ?? "Pick someone above, then enroll so later meetings recognize them.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .enrolled(let onto, let at):
            Text(at.map { "Enrolled on \(onto) \($0.formatted(.relative(presentation: .named)))." }
                 ?? "Enrolled on \(onto).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .working:
            Text("Listening to this speaker’s audio…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .needsPerson:
            Text("Pick someone in This meeting or Prior speakers first, then enroll.")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

extension Speaker {
    var displayNameIsPlaceholder: Bool {
        SpeakerLinkCatalog.isPlaceholder(displayName)
    }
}

enum TranscriptTextHighlight {
    static func attributed(_ text: String, query: String) -> AttributedString {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return AttributedString(text) }

        var output = AttributedString()
        var cursor = text.startIndex
        while let found = text.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: cursor..<text.endIndex
        ) {
            if cursor < found.lowerBound {
                output.append(AttributedString(String(text[cursor..<found.lowerBound])))
            }
            var hit = AttributedString(String(text[found]))
            hit.backgroundColor = Color.yellow.opacity(0.45)
            output.append(hit)
            cursor = found.upperBound
        }
        if cursor < text.endIndex {
            output.append(AttributedString(String(text[cursor...])))
        }
        return output
    }
}

/// One row in a filtered transcript: a real segment, or a collapsed
/// stand-in so a hidden speaker's badge stays clickable.
enum TranscriptDisplayItem: Identifiable, Equatable {
    case segment(TranscriptSegment)
    case collapsed(speaker: Speaker, hiddenCount: Int)

    /// Every row in the transcript LazyVStack must use this String. Do not
    /// also tag playable rows with `.id(segment.id)` (a UUID) — SwiftUI then
    /// mixes identity types and recycles index 0 as the original playable
    /// snippet, so hide/show does nothing to the first line of each speaker.
    var id: String {
        switch self {
        case .segment(let segment): Self.scrollID(for: segment.id)
        case .collapsed(let speaker, _): speaker.identityKey.hideStubID
        }
    }

    static func scrollID(for segmentID: UUID) -> String {
        "segment:\(segmentID.uuidString)"
    }

    static func == (lhs: TranscriptDisplayItem, rhs: TranscriptDisplayItem) -> Bool {
        switch (lhs, rhs) {
        case (.segment(let a), .segment(let b)):
            return a.id == b.id
        case (.collapsed(let speakerA, let countA), .collapsed(let speakerB, let countB)):
            return speakerA.identityKey == speakerB.identityKey && countA == countB
        default:
            return false
        }
    }
}

enum TranscriptDisplay {
    static func items(
        from segments: [TranscriptSegment],
        hiddenSpeakers: [Speaker],
        isolatedSpeaker: Speaker?,
        searchSpeaker: Speaker?,
        searchQuery: String,
        isolatedSpeakers: [Speaker]? = nil
    ) -> [TranscriptDisplayItem] {
        var items: [TranscriptDisplayItem] = []
        var stubIndex: [Speaker.IdentityKey: Int] = [:]
        let isolatedGroup = isolatedSpeakers ?? isolatedSpeaker.map { [$0] }

        for segment in segments {
            if let isolatedGroup, !isolatedGroup.isEmpty {
                if !isolatedGroup.contains(where: { $0.matchesIdentity(segment.speaker) }) {
                    continue
                }
            }
            if let searchSpeaker, !searchQuery.isEmpty {
                if !segment.speaker.matchesIdentity(searchSpeaker) { continue }
                if !segment.text.localizedCaseInsensitiveContains(searchQuery) { continue }
            }

            if isHidden(segment.speaker, hiddenSpeakers: hiddenSpeakers) {
                let key = collapseKey(for: segment.speaker, hiddenSpeakers: hiddenSpeakers)
                if let index = stubIndex[key],
                   case .collapsed(let speaker, let count) = items[index] {
                    items[index] = .collapsed(speaker: speaker, hiddenCount: count + 1)
                } else {
                    stubIndex[key] = items.count
                    let stubSpeaker = hiddenSpeakers.first(where: { $0.identityKey == key })
                        ?? segment.speaker
                    items.append(.collapsed(speaker: stubSpeaker, hiddenCount: 1))
                }
                continue
            }

            items.append(.segment(segment))
        }
        return items
    }

    static func isHidden(_ speaker: Speaker, hiddenSpeakers: [Speaker]) -> Bool {
        hiddenSpeakers.contains { candidate in
            if candidate.matchesIdentity(speaker) { return true }
            if candidate.isMe && speaker.isMe { return true }
            if namesMatch(candidate.displayName, speaker.displayName) { return true }
            // Me ↔ a remote labeled with the local name (Alex). Never use
            // candidate.displayName == me-name here: when candidate is Me
            // that is always true and would hide guest-1 / guest-2 too.
            if let me = SpeakerNames.effectiveMeName, !me.isEmpty {
                if candidate.isMe && namesMatch(me, speaker.displayName) { return true }
                if speaker.isMe && namesMatch(me, candidate.displayName) { return true }
            }
            return SpeakerNameMatcher.samePerson(candidate.displayName, speaker.displayName)
        }
    }

    private static func namesMatch(_ a: String, _ b: String) -> Bool {
        SpeakerNameMatcher.normalize(a) == SpeakerNameMatcher.normalize(b)
    }

    private static func collapseKey(
        for speaker: Speaker,
        hiddenSpeakers: [Speaker]
    ) -> Speaker.IdentityKey {
        // Prefer Me so a remote labeled "Alex" shares the same stub as you,
        // instead of leaving a second identity that SwiftUI can pin to 0:00.
        if let me = hiddenSpeakers.first(where: \.isMe) {
            if speaker.isMe { return me.identityKey }
            if namesMatch(me.displayName, speaker.displayName)
                || SpeakerNameMatcher.samePerson(me.displayName, speaker.displayName) {
                return me.identityKey
            }
        }
        if let hit = hiddenSpeakers.first(where: { $0.matchesIdentity(speaker) }) {
            return hit.identityKey
        }
        if let hit = hiddenSpeakers.first(where: {
            SpeakerNameMatcher.samePerson($0.displayName, speaker.displayName)
        }) {
            return hit.identityKey
        }
        return speaker.identityKey
    }
}

struct CollapsedSpeakerRow: View {
    let speaker: Speaker
    let hiddenCount: Int
    var actions: SpeakerBadgeActions

    private var tint: Color { actions.color ?? speaker.color }

    var body: some View {
        Button {
            actions.onToggleHidden?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(tint)
                Text("Show \(speaker.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(hiddenCount == 1 ? "1 hidden line" : "\(hiddenCount) hidden lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Click to show")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(speaker.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(speaker.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
        .help("\(speaker.displayName) is hidden. Click to show their lines again.")
    }
}

/// Captures right-click without stealing left-click / double-click.
private struct RightMouseDownCatcher: NSViewRepresentable {
    var onRightMouseDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightMouseDown = onRightMouseDown
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightMouseDown = onRightMouseDown
    }

    final class CatcherView: NSView {
        var onRightMouseDown: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = window?.currentEvent, event.type == .rightMouseDown {
                return self
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightMouseDown?()
        }
    }
}
