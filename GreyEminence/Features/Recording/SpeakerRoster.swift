import Foundation
import SwiftData

/// Who we expect in this meeting, and which detected voices are bound to them.
@Observable
final class SpeakerRoster {
    struct Seat: Identifiable, Hashable {
        var id: UUID
        var name: String
        var contactID: UUID?
        var isMe: Bool
        var isLocked: Bool
        var boundSpeakers: [Speaker]

        var speaker: Speaker {
            isMe ? Speaker.resolvedMe() : .other(name)
        }

        func binds(_ speaker: Speaker) -> Bool {
            if isMe && speaker.isMe { return true }
            if speaker.matchesIdentity(self.speaker) { return true }
            if boundSpeakers.contains(where: { $0.matchesIdentity(speaker) }) { return true }
            if !speaker.isGuestPlaceholder && SpeakerNameMatcher.samePerson(name, speaker.displayName) {
                return true
            }
            return false
        }
    }

    var seats: [Seat] = []
    /// When set, clicking a transcript line paints it as this seat.
    var paintSeatID: UUID?
    /// Header chip click: show only this speaker in the live/finished transcript.
    var isolatedSpeaker: Speaker?
    /// Mixer: hidden speakers stay in the meeting but their lines are off.
    var hiddenSpeakers: [Speaker] = []
    /// Bumped on hide / show / isolate so the transcript LazyVStack is a new
    /// view. Mixed UUID/String row ids were recycling the first snippet of
    /// each speaker (Alex at 0:00, first guest-1, first guest-2).
    var mixerGeneration: Int = 0

    private func bumpMixer() {
        mixerGeneration += 1
    }

    var paintSeat: Seat? {
        seats.first { $0.id == paintSeatID }
    }

    func ensureMe(named name: String?) {
        if let index = seats.firstIndex(where: \.isMe) {
            if let name, !name.isEmpty { seats[index].name = name }
            return
        }
        seats.insert(
            Seat(
                id: UUID(),
                name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Me",
                contactID: nil,
                isMe: true,
                isLocked: true,
                boundSpeakers: [.me]
            ),
            at: 0
        )
    }

    func seed(attendeeNames: [String], meName: String?) {
        ensureMe(named: meName)
        for raw in attendeeNames {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if seats.contains(where: { Self.namesAreSamePerson($0.name, name) }) {
                continue
            }
            seats.append(
                Seat(
                    id: UUID(),
                    name: name,
                    contactID: nil,
                    isMe: false,
                    isLocked: false,
                    boundSpeakers: []
                )
            )
        }
        collapseSamePersonSeats()
    }

    func addSeat(name: String, contactID: UUID? = nil) -> Seat {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = seats.first(where: { Self.namesAreSamePerson($0.name, trimmed) }) {
            if existing.contactID == nil, let contactID {
                if let index = seats.firstIndex(where: { $0.id == existing.id }) {
                    seats[index].contactID = contactID
                    return seats[index]
                }
            }
            return existing
        }
        let seat = Seat(
            id: UUID(),
            name: trimmed,
            contactID: contactID,
            isMe: false,
            isLocked: false,
            boundSpeakers: []
        )
        seats.append(seat)
        return seat
    }

    func renameSeat(matching speaker: Speaker, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = seats.firstIndex(where: {
            $0.binds(speaker) || $0.speaker.matchesIdentity(speaker)
        }) else { return }
        seats[index].name = trimmed
        bind(detected: seats[index].speaker, to: seats[index].id)
        bumpMixer()
    }

    func removeSeat(_ id: UUID) {
        seats.removeAll { $0.id == id && !$0.isMe }
        if paintSeatID == id { paintSeatID = nil }
    }

    func setLocked(_ id: UUID, _ locked: Bool) {
        guard let index = seats.firstIndex(where: { $0.id == id }) else { return }
        seats[index].isLocked = locked
    }

    func lockAllBound() {
        for index in seats.indices where !seats[index].boundSpeakers.isEmpty || seats[index].isMe {
            seats[index].isLocked = true
        }
    }

    func bind(detected: Speaker, to seatID: UUID) {
        guard let index = seats.firstIndex(where: { $0.id == seatID }) else { return }
        if !seats[index].boundSpeakers.contains(where: { $0.matchesIdentity(detected) }) {
            seats[index].boundSpeakers.append(detected)
        }
    }

    func seat(id: UUID) -> Seat? {
        seats.first { $0.id == id }
    }

    func seat(matching speaker: Speaker) -> Seat? {
        seats.first { $0.binds(speaker) }
    }

    func toggleIsolated(_ speaker: Speaker) {
        if let current = isolatedSpeaker, current.matchesIdentity(speaker) {
            isolatedSpeaker = nil
        } else {
            isolatedSpeaker = speaker
        }
        bumpMixer()
    }

    func isHidden(_ speaker: Speaker) -> Bool {
        hiddenSpeakers.contains { $0.matchesIdentity(speaker) }
    }

    func toggleHidden(_ speaker: Speaker) {
        if let index = hiddenSpeakers.firstIndex(where: { $0.matchesIdentity(speaker) }) {
            hiddenSpeakers.remove(at: index)
        } else {
            hiddenSpeakers.append(speaker)
            if isolatedSpeaker?.matchesIdentity(speaker) == true {
                isolatedSpeaker = nil
            }
        }
        bumpMixer()
    }

    private func liveSeat(_ seat: Seat) -> Seat {
        seats.first { $0.id == seat.id } ?? seat
    }

    /// Hide/show every identity that belongs to this seat (Jordan + Jordan
    /// Hale + bound guest leftovers, or Me + a remote labeled "Alex").
    func toggleHidden(seat: Seat, in segments: [TranscriptSegment]) {
        let seat = liveSeat(seat)
        let identities = identities(for: seat, in: segments)
        let anyHidden = identities.contains { isHidden($0) } || isHidden(seat.speaker)
        if anyHidden {
            hiddenSpeakers.removeAll { speaker in
                identities.contains { $0.matchesIdentity(speaker) }
                    || speaker.matchesIdentity(seat.speaker)
            }
        } else {
            for identity in identities where !isHidden(identity) {
                hiddenSpeakers.append(identity)
            }
            if let isolated = isolatedSpeaker,
               identities.contains(where: { $0.matchesIdentity(isolated) }) {
                isolatedSpeaker = nil
            }
        }
        bumpMixer()
    }

    func isSeatHidden(_ seat: Seat, in segments: [TranscriptSegment]) -> Bool {
        let seat = liveSeat(seat)
        return identities(for: seat, in: segments).contains { isHidden($0) }
            || isHidden(seat.speaker)
    }

    func identities(for seat: Seat, in segments: [TranscriptSegment]) -> [Speaker] {
        let seat = liveSeat(seat)
        var result: [Speaker] = [seat.speaker]
        func add(_ speaker: Speaker) {
            if !result.contains(where: { $0.matchesIdentity(speaker) }) {
                result.append(speaker)
            }
        }
        for bound in seat.boundSpeakers { add(bound) }
        for segment in segments {
            if seat.binds(segment.speaker) {
                add(segment.speaker)
                continue
            }
            if segment.speaker.isGuestPlaceholder { continue }
            if SpeakerNameMatcher.samePerson(seat.name, segment.speaker.displayName) {
                add(segment.speaker)
            }
        }
        if seat.isMe {
            for segment in segments where segment.speaker.isMe {
                add(segment.speaker)
            }
            let meNames = [seat.name, SpeakerNames.effectiveMeName].compactMap { $0 }
            for segment in segments where !segment.speaker.isGuestPlaceholder {
                if meNames.contains(where: {
                    $0.compare(segment.speaker.displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    add(segment.speaker)
                }
            }
        }
        return result
    }

    /// Every identity that should disappear when the mixer hides the given set.
    func hiddenIdentities(in segments: [TranscriptSegment]) -> [Speaker] {
        var result: [Speaker] = []
        func add(_ speaker: Speaker) {
            if !result.contains(where: { $0.matchesIdentity(speaker) }) {
                result.append(speaker)
            }
        }
        for hidden in hiddenSpeakers {
            add(hidden)
            if let seat = seat(matching: hidden)
                ?? seats.first(where: { SpeakerNameMatcher.samePerson($0.name, hidden.displayName) }) {
                for identity in identities(for: seat, in: segments) { add(identity) }
            } else {
                for segment in segments {
                    if hidden.isMe && segment.speaker.isMe {
                        add(segment.speaker)
                    } else if SpeakerNameMatcher.samePerson(hidden.displayName, segment.speaker.displayName) {
                        add(segment.speaker)
                    }
                }
            }
        }
        return result
    }

    func isolatedIdentities(in segments: [TranscriptSegment]) -> [Speaker]? {
        guard let isolated = isolatedSpeaker else { return nil }
        if let seat = seat(matching: isolated) {
            return identities(for: seat, in: segments)
        }
        var ids = [isolated]
        for segment in segments {
            if isolated.isMe && segment.speaker.isMe {
                if !ids.contains(where: { $0.matchesIdentity(segment.speaker) }) {
                    ids.append(segment.speaker)
                }
            } else if SpeakerNameMatcher.samePerson(isolated.displayName, segment.speaker.displayName) {
                if !ids.contains(where: { $0.matchesIdentity(segment.speaker) }) {
                    ids.append(segment.speaker)
                }
            }
        }
        return ids
    }

    func showAllSpeakers() {
        hiddenSpeakers = []
        isolatedSpeaker = nil
        bumpMixer()
    }

    /// Seat speaker to store on transcript lines so Jordan and “Jordan Hale”
    /// share one identity after an ID merge.
    func canonicalSpeaker(matching speaker: Speaker) -> Speaker? {
        if let seat = seat(matching: speaker)
            ?? seats.first(where: {
                SpeakerNameMatcher.samePerson($0.name, speaker.displayName)
                    || $0.name.compare(speaker.displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
            return seat.speaker
        }
        return nil
    }

    /// Bind `old` onto `new`’s seat and drop `old` from the hide list without
    /// hiding the destination (guest-1 → Jordan must not grey Jordan).
    func adopt(from old: Speaker, onto new: Speaker, in segments: [TranscriptSegment]) {
        let target = canonicalSpeaker(matching: new) ?? new
        if let seat = seat(matching: target)
            ?? seats.first(where: { SpeakerNameMatcher.samePerson($0.name, target.displayName) }) {
            bind(detected: old, to: seat.id)
            bind(detected: target, to: seat.id)
            bind(detected: seat.speaker, to: seat.id)
        } else if !target.isMe, !target.isGuestPlaceholder {
            let seat = addSeat(name: target.displayName)
            bind(detected: old, to: seat.id)
            bind(detected: target, to: seat.id)
        }
        hiddenSpeakers.removeAll { $0.matchesIdentity(old) }
        unifyOntoSeats(in: segments)
        bumpMixer()
    }

    /// “Click to show” on a hide stub: unhide this person and every alias
    /// (Jordan / Jordan Hale / bound leftovers). Never hide the other copy.
    func reveal(_ speaker: Speaker, in segments: [TranscriptSegment]) {
        let group = identityGroup(for: speaker, in: segments)
        hiddenSpeakers.removeAll { hidden in
            group.contains { $0.matchesIdentity(hidden) || hidden.matchesIdentity($0) }
                || SpeakerNameMatcher.samePerson(hidden.displayName, speaker.displayName)
        }
        bumpMixer()
    }

    func identityGroup(for speaker: Speaker, in segments: [TranscriptSegment]) -> [Speaker] {
        if let seat = seat(matching: speaker)
            ?? seats.first(where: { SpeakerNameMatcher.samePerson($0.name, speaker.displayName) }) {
            return identities(for: seat, in: segments)
        }
        var result: [Speaker] = [speaker]
        for segment in segments {
            let other = segment.speaker
            if result.contains(where: { $0.matchesIdentity(other) }) { continue }
            if other.matchesIdentity(speaker)
                || SpeakerNameMatcher.samePerson(other.displayName, speaker.displayName) {
                result.append(other)
            }
        }
        return result
    }

    /// Rewrite same-person labels onto the seat speaker so hide/show/talk-share
    /// use one ID after guest-1 is tagged as Jordan.
    @discardableResult
    func unifyOntoSeats(in segments: [TranscriptSegment]) -> Int {
        bindNamedVoices(in: segments)
        var changed = 0
        for segment in segments {
            let speaker = segment.speaker
            let seat: Seat?
            if let match = self.seat(matching: speaker) {
                seat = match
            } else if !speaker.isGuestPlaceholder,
                      let match = seats.first(where: { SpeakerNameMatcher.samePerson($0.name, speaker.displayName) }) {
                seat = match
            } else {
                seat = nil
            }
            guard let seat else { continue }
            let canonical = liveSeat(seat).speaker
            if speaker != canonical {
                if seat.isMe {
                    var meNames = [seat.name, canonical.displayName]
                    if let me = SpeakerNames.effectiveMeName { meNames.append(me) }
                    let namedLikeMe = meNames.contains {
                        Self.namesAreSamePerson($0, speaker.displayName)
                    }
                    guard speaker.isMe || namedLikeMe else { continue }
                } else if speaker.isMe {
                    continue
                }
                segment.speaker = canonical
                changed += 1
            }
            bind(detected: canonical, to: seat.id)
        }
        return changed
    }

    func isolationSpeaker(for seat: Seat, in segments: [TranscriptSegment]) -> Speaker? {
        let seat = liveSeat(seat)
        return segments.first(where: { seat.binds($0.speaker) })?.speaker
    }

    func talkSharePercent(
        for seat: Seat,
        percents: [Speaker.IdentityKey: Int],
        in segments: [TranscriptSegment]
    ) -> Int? {
        let total = identities(for: liveSeat(seat), in: segments).reduce(0) { sum, speaker in
            sum + (percents[speaker.identityKey] ?? 0)
        }
        return total > 0 ? min(total, 100) : nil
    }

    /// Attach named transcript voices to existing seats (Jordan ↔ Jordan
    /// Hale, Alex-as-remote ↔ Me) instead of minting a second chip.
    func bindNamedVoices(
        in segments: [TranscriptSegment],
        contactNames: [UUID: [String]] = [:]
    ) {
        var seen: [Speaker] = []
        for segment in segments {
            let speaker = segment.speaker
            if seen.contains(where: { $0.matchesIdentity(speaker) }) { continue }
            seen.append(speaker)

            if let existing = seat(matching: speaker) {
                bind(detected: speaker, to: existing.id)
                continue
            }

            if let match = seats.first(where: { seatMatches($0, speaker, contactNames: contactNames) }) {
                bind(detected: speaker, to: match.id)
                continue
            }

            if speaker.isMe || speaker.isGuestPlaceholder { continue }
            let seat = addSeat(name: speaker.displayName)
            bind(detected: speaker, to: seat.id)
        }
        collapseSamePersonSeats()
    }

    /// One mixer chip per person. "Alex you" and calendar "Alex Morgan" were
    /// two seats that both bound the same lines (53% twice, two colors).
    func collapseSamePersonSeats() {
        var keep: [Seat] = []
        var retarget: [UUID: UUID] = [:]
        for seat in seats {
            if let idx = keep.firstIndex(where: { samePersonSeats($0, seat) }) {
                let merged = mergeSeats(keeper: keep[idx], extra: seat)
                if keep[idx].id != merged.id {
                    retarget[keep[idx].id] = merged.id
                }
                if seat.id != merged.id {
                    retarget[seat.id] = merged.id
                }
                keep[idx] = merged
                continue
            }
            keep.append(seat)
        }
        if let paint = paintSeatID, let dest = retarget[paint] {
            paintSeatID = dest
        }
        let changed = keep.map(\.id) != seats.map(\.id)
        seats = keep
        if changed { bumpMixer() }
    }

    /// Prefer Me when folding a calendar/contact alias into the local seat.
    private func mergeSeats(keeper: Seat, extra: Seat) -> Seat {
        var primary = extra.isMe && !keeper.isMe ? extra : keeper
        let secondary = primary.id == extra.id ? keeper : extra
        for bound in secondary.boundSpeakers {
            if !primary.boundSpeakers.contains(where: { $0.matchesIdentity(bound) }) {
                primary.boundSpeakers.append(bound)
            }
        }
        if primary.contactID == nil {
            primary.contactID = secondary.contactID
        }
        return primary
    }

    func spokenSeats(in segments: [TranscriptSegment]) -> [Seat] {
        let raw: [Seat]
        if segments.isEmpty {
            raw = seats
        } else {
            raw = seats.filter { seat in
                segments.contains { liveSeat(seat).binds($0.speaker) }
            }
        }
        var unique: [Seat] = []
        for seat in raw {
            if let idx = unique.firstIndex(where: { samePersonSeats($0, seat) }) {
                if seat.isMe { unique[idx] = liveSeat(seat) }
                continue
            }
            unique.append(liveSeat(seat))
        }
        return unique
    }

    func samePersonSeats(_ a: Seat, _ b: Seat) -> Bool {
        if a.id == b.id { return true }
        if a.isMe && b.isMe { return true }
        if Self.namesAreSamePerson(a.name, b.name) { return true }
        if a.binds(b.speaker) || b.binds(a.speaker) { return true }
        return false
    }

    private static func namesAreSamePerson(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            || SpeakerNameMatcher.samePerson(a, b)
    }

    private func seatMatches(
        _ seat: Seat,
        _ speaker: Speaker,
        contactNames: [UUID: [String]]
    ) -> Bool {
        if seat.binds(speaker) { return true }
        if speaker.isGuestPlaceholder { return false }
        if SpeakerNameMatcher.samePerson(seat.name, speaker.displayName) { return true }
        if let contactID = seat.contactID, let names = contactNames[contactID] {
            return names.contains { SpeakerNameMatcher.samePerson($0, speaker.displayName) }
        }
        return false
    }

    func unboundVoices(in segments: [TranscriptSegment]) -> [Speaker] {
        var seen: [Speaker] = []
        for segment in segments where !segment.speaker.isMe {
            let speaker = segment.speaker
            if seat(matching: speaker) != nil { continue }
            if seen.contains(where: { $0.matchesIdentity(speaker) }) { continue }
            seen.append(speaker)
        }
        return seen
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
