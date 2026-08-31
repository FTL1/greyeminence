import SwiftUI
import SwiftData

struct LiveTranscriptView: View {
    let segments: [TranscriptSegment]
    var segmentConfidence: [UUID: Float] = [:]
    var onRenameSpeaker: ((Speaker, String, Bool) -> Void)?
    var onLinkSpeakerToContact: ((Speaker, Contact) -> Void)?
    var roster: SpeakerRoster?
    /// When false the parent already shows the People header (live record split).
    var showsRoster: Bool = true
    var onAssignVoice: ((Speaker, SpeakerRoster.Seat) -> Void)?
    var onPaintSegment: ((UUID) -> Void)?
    var onAddedPerson: ((SpeakerRoster.Seat, Contact?) -> Void)?
    var attendees: [Contact] = []
    var onEnrollVoicePrint: ((Speaker) -> Void)?
    var voicePrintProgress: VoicePrintEnrollmentProgress = .idle
    var voicePrintState: ((Speaker, [Contact]) -> VoicePrintUIState)?
    var canUndoSpeakerChange = false
    var onUndoSpeakerChange: (() -> Void)?
    @Binding var scrollToSegmentID: UUID?
    @State private var highlightedSegmentID: UUID?
    @State private var highlightTask: Task<Void, Never>?
    @State private var isolatedSpeaker: Speaker?
    @State private var hiddenSpeakers: [Speaker] = []
    @State private var searchSpeaker: Speaker?
    @State private var searchQuery = ""
    @State private var searchMatchIDs: [UUID] = []
    @State private var searchMatchIndex = 0
    @State private var menuSpeaker: Speaker?
    @State private var menuAnchorID: UUID?
    @State private var contactSpeaker: Speaker?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]

    init(
        segments: [TranscriptSegment],
        segmentConfidence: [UUID: Float] = [:],
        onRenameSpeaker: ((Speaker, String, Bool) -> Void)? = nil,
        onLinkSpeakerToContact: ((Speaker, Contact) -> Void)? = nil,
        roster: SpeakerRoster? = nil,
        showsRoster: Bool = true,
        onAssignVoice: ((Speaker, SpeakerRoster.Seat) -> Void)? = nil,
        onPaintSegment: ((UUID) -> Void)? = nil,
        onAddedPerson: ((SpeakerRoster.Seat, Contact?) -> Void)? = nil,
        attendees: [Contact] = [],
        onEnrollVoicePrint: ((Speaker) -> Void)? = nil,
        voicePrintProgress: VoicePrintEnrollmentProgress = .idle,
        voicePrintState: ((Speaker, [Contact]) -> VoicePrintUIState)? = nil,
        canUndoSpeakerChange: Bool = false,
        onUndoSpeakerChange: (() -> Void)? = nil,
        scrollToSegmentID: Binding<UUID?> = .constant(nil)
    ) {
        self.segments = segments
        self.segmentConfidence = segmentConfidence
        self.onRenameSpeaker = onRenameSpeaker
        self.onLinkSpeakerToContact = onLinkSpeakerToContact
        self.roster = roster
        self.showsRoster = showsRoster
        self.onAssignVoice = onAssignVoice
        self.onPaintSegment = onPaintSegment
        self.onAddedPerson = onAddedPerson
        self.attendees = attendees
        self.onEnrollVoicePrint = onEnrollVoicePrint
        self.voicePrintProgress = voicePrintProgress
        self.voicePrintState = voicePrintState
        self.canUndoSpeakerChange = canUndoSpeakerChange
        self.onUndoSpeakerChange = onUndoSpeakerChange
        self._scrollToSegmentID = scrollToSegmentID
    }

    private var markerSegmentIDs: [UUID: String] {
        var result: [UUID: String] = [:]
        var lastTag: String?
        for segment in segments {
            if let tag = segment.sectionTag, tag != lastTag {
                result[segment.id] = tag
            }
            lastTag = segment.sectionTag
        }
        return result
    }

    private var activeIsolated: Speaker? {
        roster?.isolatedSpeaker ?? isolatedSpeaker
    }

    private func setIsolated(_ speaker: Speaker?) {
        if let roster {
            roster.isolatedSpeaker = speaker
        } else {
            isolatedSpeaker = speaker
        }
    }

    private var mixerHiddenSpeakers: [Speaker] {
        roster?.hiddenIdentities(in: segments) ?? hiddenSpeakers
    }

    private var displayItems: [TranscriptDisplayItem] {
        TranscriptDisplay.items(
            from: segments,
            hiddenSpeakers: mixerHiddenSpeakers,
            isolatedSpeaker: activeIsolated,
            searchSpeaker: nil,
            searchQuery: "",
            isolatedSpeakers: roster?.isolatedIdentities(in: segments)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsRoster, let roster {
                SpeakerRosterBar(
                    roster: roster,
                    segments: segments,
                    onAssignVoice: onAssignVoice,
                    onAddedPerson: onAddedPerson,
                    onEnrollVoicePrint: onEnrollVoicePrint
                )
                Divider()
            }
            if activeIsolated != nil || !searchQuery.isEmpty || !(roster?.hiddenSpeakers ?? hiddenSpeakers).isEmpty {
                filterBanner
                Divider()
            }
            if displayItems.isEmpty, !segments.isEmpty {
                ContentUnavailableView(
                    "No matching lines",
                    systemImage: "text.magnifyingglass",
                    description: Text("Nothing in this transcript matches the current filter.")
                )
            } else {
                transcriptScroll
            }
        }
        .popover(isPresented: Binding(
            get: { contactSpeaker != nil },
            set: { if !$0 { contactSpeaker = nil } }
        )) {
            ContactPicker(
                excludedContacts: [],
                prioritizedContacts: attendees,
                includeAppleDirectory: true
            ) { contact in
                if let speaker = contactSpeaker {
                    onLinkSpeakerToContact?(speaker, contact)
                }
                contactSpeaker = nil
            }
            .frame(width: 280, height: 320)
        }
        .overlay(alignment: .topTrailing) {
            if let speaker = menuSpeaker {
                SpeakerActionPopover(
                    speaker: speaker,
                    actions: actions(for: speaker),
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
    }

    private var filterBanner: some View {
        HStack(spacing: 8) {
            if let isolated = activeIsolated {
                Label("Only \(isolated.displayName)", systemImage: "person.crop.rectangle")
                    .font(.caption)
            }
            if !(roster?.hiddenSpeakers ?? hiddenSpeakers).isEmpty {
                ForEach(roster?.hiddenSpeakers ?? hiddenSpeakers, id: \.identityKey) { speaker in
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
            Spacer()
            Button("Show all") {
                roster?.showAllSpeakers()
                setIsolated(nil)
                hiddenSpeakers = []
                searchSpeaker = nil
                searchQuery = ""
                searchMatchIDs = []
                searchMatchIndex = 0
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let markers = markerSegmentIDs
                    ForEach(displayItems, id: \.id) { item in
                        liveMixerRow(item, markers: markers)
                            .id(item.id)
                    }
                }
                .padding()
                .id("live-mixer-\(roster?.mixerGeneration ?? 0)-\(hiddenSpeakers.count)")
            }
            .onChange(of: segments.count) { _, _ in
                if let lastID = segments.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(TranscriptDisplayItem.scrollID(for: lastID), anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollToSegmentID) { _, newID in
                guard let targetID = newID else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(TranscriptDisplayItem.scrollID(for: targetID), anchor: .center)
                }
                highlightedSegmentID = targetID
                scrollToSegmentID = nil
                // Clear highlight after a short delay
                highlightTask?.cancel()
                highlightTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.5)) {
                        if highlightedSegmentID == targetID {
                            highlightedSegmentID = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func liveMixerRow(_ item: TranscriptDisplayItem, markers: [UUID: String]) -> some View {
        switch item {
        case .segment(let segment):
            if TranscriptDisplay.isHidden(segment.speaker, hiddenSpeakers: mixerHiddenSpeakers) {
                CollapsedSpeakerRow(
                    speaker: segment.speaker,
                    hiddenCount: 1,
                    actions: revealActions(for: segment.speaker)
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let markerTitle = markers[segment.id] {
                        SectionMarkerView(
                            title: markerTitle,
                            timestamp: segment.formattedTimestamp
                        )
                    }
                    TranscriptSegmentRow(
                        segment: segment,
                        confidence: segmentConfidence[segment.id],
                        speakerActions: actions(for: segment.speaker, anchorID: segment.id),
                        highlightQuery: highlightQuery(for: segment)
                    )
                    .background(
                        highlightedSegmentID == segment.id
                            ? Color.cyan.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard roster?.paintSeatID != nil else { return }
                        onPaintSegment?(segment.id)
                    }
                }
            }
        case .collapsed(let speaker, let count):
            CollapsedSpeakerRow(
                speaker: speaker,
                hiddenCount: count,
                actions: revealActions(for: speaker)
            )
        }
    }

    private func revealActions(for speaker: Speaker) -> SpeakerBadgeActions {
        var actions = actions(for: speaker)
        actions.onToggleHidden = {
            if let roster {
                roster.reveal(speaker, in: segments)
            } else {
                toggleHidden(speaker)
            }
        }
        return actions
    }

    private func toggleHidden(_ speaker: Speaker) {
        if let roster {
            if let seat = roster.seat(matching: speaker) {
                roster.toggleHidden(seat: seat, in: segments)
            } else {
                roster.toggleHidden(speaker)
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = hiddenSpeakers.firstIndex(where: { $0.matchesIdentity(speaker) }) {
                hiddenSpeakers.remove(at: index)
            } else {
                hiddenSpeakers.append(speaker)
                if activeIsolated?.matchesIdentity(speaker) == true {
                    setIsolated(nil)
                }
            }
        }
    }

    private func highlightQuery(for segment: TranscriptSegment) -> String {
        guard let searchSpeaker, searchSpeaker.matchesIdentity(segment.speaker) else { return "" }
        return searchQuery
    }

    private func applySpeakerSearch(speaker: Speaker, query: String) {
        searchSpeaker = speaker
        searchQuery = query
        let matches = SpeakerSearch.matchingSegments(query: query, speaker: speaker, in: segments)
        searchMatchIDs = matches.map(\.id)
        guard !matches.isEmpty else {
            searchMatchIndex = 0
            return
        }
        let anchorTime = segments.first(where: { $0.id == menuAnchorID })?.startTime ?? 0
        searchMatchIndex = SpeakerSearch.nearestMatchIndex(in: matches, after: anchorTime)
        scrollToSegmentID = matches[searchMatchIndex].id
    }

    private func jumpSpeakerSearch(by delta: Int) {
        guard !searchMatchIDs.isEmpty else { return }
        let count = searchMatchIDs.count
        searchMatchIndex = (searchMatchIndex + delta % count + count) % count
        scrollToSegmentID = searchMatchIDs[searchMatchIndex]
    }

    private func actions(for speaker: Speaker, anchorID: UUID? = nil) -> SpeakerBadgeActions {
        let isMenuSpeaker = menuSpeaker?.matchesIdentity(speaker) == true
        return SpeakerBadgeActions(
            talkSharePercent: SpeakerTalkShare.percent(for: speaker, in: segments),
            isHidden: (roster?.isHidden(speaker) ?? hiddenSpeakers.contains(where: { $0.matchesIdentity(speaker) })),
            onToggleHidden: { toggleHidden(speaker) },
            onRename: onRenameSpeaker.map { callback in
                { name, saveAsDefault in
                    callback(speaker, name, saveAsDefault)
                }
            },
            onSearch: { query in
                applySpeakerSearch(speaker: speaker, query: query)
            },
            searchQuery: searchSpeaker?.matchesIdentity(speaker) == true ? searchQuery : "",
            onOpenMenu: {
                menuSpeaker = speaker
                menuAnchorID = anchorID
                    ?? segments.first(where: { $0.speaker.matchesIdentity(speaker) })?.id
            },
            searchMatchCount: isMenuSpeaker ? searchMatchIDs.count : 0,
            searchMatchIndex: isMenuSpeaker ? searchMatchIndex : 0,
            onJumpToMatch: { delta in
                jumpSpeakerSearch(by: delta)
            },
            onToggleIsolate: {
                if let isolated = activeIsolated, isolated.matchesIdentity(speaker) {
                    setIsolated(nil)
                } else {
                    setIsolated(speaker)
                }
            },
            isIsolated: activeIsolated?.matchesIdentity(speaker) == true,
            onAddToContacts: onLinkSpeakerToContact == nil ? nil : {
                contactSpeaker = speaker
            },
            onSaveAsNewContact: onLinkSpeakerToContact == nil ? nil : {
                saveAsNewContact(speaker)
            },
            speakerLinks: speakerLinkGroups(for: speaker),
            onSelectSpeakerLink: onLinkSpeakerToContact == nil ? nil : { person in
                applySpeakerLink(person, to: speaker)
            },
            onEnrollVoicePrint: onEnrollVoicePrint == nil ? nil : {
                onEnrollVoicePrint?(speaker)
            },
            voicePrintState: resolvedVoicePrintState(for: speaker),
            onSetAsMe: speaker.isMe ? nil : {
                onRenameSpeaker?(speaker, "me", false)
            }
        )
    }

    private func speakerLinkGroups(for speaker: Speaker) -> SpeakerLinkGroups {
        let people = contacts.filter { !$0.isArchived }.map { $0.asSpeakerLinkPerson() }
        let names = segments.reduce(into: [String]()) { result, segment in
            let name = segment.speaker.displayName
            if !result.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                result.append(name)
            }
        }
        return SpeakerLinkCatalog.groups(
            people: people,
            transcriptNames: names,
            attendeeNames: attendees.map(\.name),
            meName: SpeakerNames.effectiveMeName,
            currentSpeakerName: speaker.displayName
        )
    }

    private func resolvedVoicePrintState(for speaker: Speaker) -> VoicePrintUIState {
        if case .working(let key) = voicePrintProgress, key == speaker.identityKey {
            return .working
        }
        if case .failed(let key, let message) = voicePrintProgress, key == speaker.identityKey {
            return .failed(message)
        }
        if let voicePrintState {
            return voicePrintState(speaker, Array(contacts))
        }
        return .ready(onto: speaker.isGuestPlaceholder ? nil : speaker.displayName)
    }

    private func applySpeakerLink(_ person: SpeakerLinkPerson, to speaker: Speaker) {
        if let contactID = person.contactID,
           let contact = contacts.first(where: { $0.id == contactID }) {
            onLinkSpeakerToContact?(speaker, contact)
            if !speaker.isMe { menuSpeaker = .other(contact.name) }
            return
        }
        onRenameSpeaker?(speaker, person.name, false)
        if !speaker.isMe { menuSpeaker = .other(person.name) }
    }

    private func saveAsNewContact(_ speaker: Speaker) {
        let name = speaker.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !speaker.displayNameIsPlaceholder else { return }
        let contact = Contact(name: name)
        modelContext.insert(contact)
        PersistenceGate.save(modelContext, site: "saveAsNewContact", critical: false, meetingID: nil)
        onLinkSpeakerToContact?(speaker, contact)
    }
}
